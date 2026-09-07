"""Read-only retained clean-R 4.6.0 install and runtime evidence audit."""
from pathlib import Path
import csv
import hashlib
import json
import subprocess

ROOT = Path('/private/tmp/dta-direct-stage5-validation/root-r460-integration')
REPO = Path('/private/tmp/dta-direct-stage5')
SOURCE = 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
NAME = 'candidate-a2d8b6a-v1'
CACHE = {}
def identity(p):
    p = Path(p); target = p.resolve(strict=True); info = target.stat()
    key = (str(target), info.st_size, info.st_mtime_ns, info.st_mode)
    if key not in CACHE: CACHE[key] = hashlib.sha256(target.read_bytes()).hexdigest()
    return dict(path=str(p),resolved=str(target),bytes=info.st_size,mode=oct(info.st_mode & 0o777),sha256=CACHE[key])
def verify(record):
    actual = identity(record['path'])
    assert all(actual[k] == v for k,v in record.items() if k in actual), record['path']
def git(*args):
    return subprocess.check_output(['git','-C',str(REPO),*args])
reports=[]
for suffix in ['', '-behavior', '-observe', '-focused']:
    name = NAME + suffix; folder = ROOT/name
    receipt_path = folder/'completed-receipt.json' if not suffix else ROOT/(name+'-receipt.json')
    receipt = json.loads(receipt_path.read_text())
    assert receipt.get('status') == 'complete' if not suffix else receipt['accepted']
    verify(receipt['manifest'])
    manifest = json.loads((folder/'output-manifest.json').read_text())
    products = manifest['products']
    extras = {str(folder/'output-manifest.json')} | ({str(receipt_path)} if not suffix else set())
    assert {str(p) for p in folder.rglob('*') if p.is_file()} == {x['path'] for x in products} | extras
    assert len({x['path'] for x in products}) == len(products)
    for record in products: verify(record)
    inputs = json.loads((folder/'inputs-before.json').read_text())
    for record in inputs['inputs']: verify(record)
    result = json.loads((folder/'execution-result.json').read_text())
    if not suffix:
        assert inputs['revision'] == receipt['revision'] == SOURCE
        assert receipt['package_tree'] == git('rev-parse',SOURCE+':r-package/dtatools').decode().strip()
        assert result['status']=='complete' and not result['changed_bound_inputs'] and not result['generated_export_files']
        assert all(x['returncode']==0 for x in result['commands'])
        verify(json.loads((folder/'built-source-before-install.json').read_text()))
        for row in inputs['export_inventory']:
            verify(row)
            path = Path(row['path']); relative = str(path.relative_to(folder/'export'))
            entry = git('ls-tree',SOURCE,'--',relative).decode().strip().split()
            data=path.read_bytes()
            assert entry[0]==row['git_mode'] and entry[2]==row['git_blob']
            assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==row['git_blob']
        assert len(inputs['export_inventory'])==233
        assert 'exports = 106L' in (folder/'installed-identity.R').read_text()
    else:
        assert inputs['source']==SOURCE and result['returncode']==0 and not result['changed_inputs'] and result['integrity_error'] is None
        for phase in ['before','after']:
            expected = ['/private/tmp/dta-direct-stage5-minimum-preflight/r460-clean-install/lib/R/lib/libR.dylib']
            assert result['runtime_coverage'][phase]['libR']==expected
    for phase in ['before','after']:
        guard=(folder/('runtime-guard-'+phase+'.R')).read_text()
        assert 'R version 4.6.0 (2026-04-24)' in guard
        images=(folder/('loaded-images-'+phase+'.txt')).read_text().splitlines()
        assert [x for x in images if x.endswith('/libR.dylib')] == ['/private/tmp/dta-direct-stage5-minimum-preflight/r460-clean-install/lib/R/lib/libR.dylib']
        namespaces=list(csv.DictReader((folder/('guard-namespaces-'+phase+'.tsv')).open(),delimiter='\t'))
        assert all('/opt/homebrew/' not in str(x) for x in namespaces)
    reports.append(dict(name=name,receipt_sha256=identity(receipt_path)['sha256'],manifest_sha256=receipt['manifest']['sha256'],products=len(products),inputs=len(inputs['inputs'])))

rows=list(csv.DictReader((ROOT/(NAME+'-focused')/'tests.csv').open()))
def number(x): return 1 if x=='TRUE' else 0 if x=='FALSE' else int(x)
counts={key:sum(number(x[key]) for x in rows) for key in ['passed','failed','error','skipped','warning']}
assert counts==dict(passed=8859,failed=0,error=0,skipped=3,warning=4)
expressions=[x for x in rows if x['file']=='test-dibble-expressions.R']
assert len(expressions)==22 and sum(int(x['passed']) for x in expressions)==187
assert all(all(number(x[k])==0 for k in ['failed','error','skipped','warning']) for x in expressions)
report=dict(status='pass',runs=reports,focused_counts=counts,expression_rows=22,expression_assertions=187,
            scope='Recorded clean R 4.6.0 / dplyr 1.2.1 integration; classified capability skips remain. Loaded-image observations cover these R processes, not full subprocess/OS shared-cache/Python closure or performance qualification.')
with Path(__file__).with_suffix('.json').open('x') as stream: json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps(report))
