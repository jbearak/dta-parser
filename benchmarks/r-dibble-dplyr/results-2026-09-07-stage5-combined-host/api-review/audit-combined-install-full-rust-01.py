"""Audit completed artifacts only; does not load R or execute workloads."""
from pathlib import Path
import csv
import hashlib
import json
import subprocess

ROOT = Path('/private/tmp/dta-direct-stage5-validation/implementation')
REPO = Path('/private/tmp/dta-direct-stage5')
SOURCE = 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
BASE = 'f74f15f98be26a0fc0d7d73a144e5f6319af2c5f'
CACHE = {}

def identity(p):
    p = Path(p)
    target = p.resolve(strict=True)
    info = target.stat()
    key = (str(target), info.st_size, info.st_mtime_ns, info.st_mode)
    if key not in CACHE:
        CACHE[key] = hashlib.sha256(target.read_bytes()).hexdigest()
    return dict(path=str(p), resolved=str(target), bytes=info.st_size,
                mode=oct(info.st_mode & 0o777), sha256=CACHE[key])

def verify(record):
    observed = identity(record['path'])
    assert all(observed[k] == v for k, v in record.items() if k in observed), record['path']

def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])

assert git('rev-parse', 'HEAD:r-package/dtatools') == git('rev-parse', SOURCE + ':r-package/dtatools')
assert not git('status', '--porcelain')
assert len(git('diff', '--name-only', BASE, SOURCE).decode().splitlines()) == 10
tree = git('rev-parse', SOURCE + ':r-package/dtatools').decode().strip()
reports = []
for name, receipt_name, manifest_name in [
    ('candidate-combined-01', 'completed-receipt.json', 'output-manifest.json'),
    ('full-combined-01', 'receipt.json', 'manifest.json'),
    ('rust-combined-01', 'receipt.json', 'manifest.json'),
]:
    folder = ROOT / name
    receipt_path = folder / receipt_name
    receipt = json.loads(receipt_path.read_text())
    assert receipt['status'] == 'complete'
    assert not receipt.get('changed_inputs', receipt.get('changed_bound_inputs'))
    verify(receipt['manifest'])
    manifest = json.loads((folder / manifest_name).read_text())
    products = manifest['products']
    assert len({x['path'] for x in products}) == len(products)
    actual = {str(p) for p in folder.rglob('*') if p.is_file()}
    assert actual == {x['path'] for x in products} | {str(receipt_path), str(folder / manifest_name)}
    for product in products:
        verify(product)
    bound = json.loads((folder / 'inputs-before.json').read_text())
    for record in bound['inputs']:
        verify(record)
    result = json.loads((folder / 'execution-result.json').read_text())
    assert result['status'] == 'complete'
    assert not result.get('changed_inputs', result.get('changed_bound_inputs'))
    if name == 'candidate-combined-01':
        assert receipt['revision'] == SOURCE and receipt['package_tree'] == tree
        assert bound['revision'] == SOURCE and bound['package_tree'] == tree
        assert len(bound['export_inventory']) == 234
        for record in bound['export_inventory']:
            verify(record)
            relative = str(Path(record['path']).relative_to(folder / 'export'))
            observed = git('ls-tree', SOURCE, '--', relative).decode().strip().split()
            assert observed[0] == record['git_mode'] and observed[2] == record['git_blob']
            data = Path(record['path']).read_bytes()
            blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
            assert blob == record['git_blob']
        for record in json.loads((folder / 'installed-files.json').read_text())['files']:
            verify(record)
        verify(json.loads((folder / 'built-source-before-install.json').read_text()))
        assert all(x['returncode'] == 0 for x in result['commands'])
        assert not result['generated_export_files']
    else:
        assert receipt['source_sha'] == receipt['runner_sha'] == SOURCE
        assert bound['source_sha'] == bound['runner_sha'] == SOURCE
        assert all(x['exit_code'] == 0 for x in result['records'])
    reports.append(dict(run=name, receipt_sha256=identity(receipt_path)['sha256'],
                        manifest_sha256=receipt['manifest']['sha256'], products=len(products),
                        bound_inputs=len(bound['inputs'])))

rows = list(csv.DictReader((ROOT / 'full-combined-01/tests.csv').open()))
def number(value):
    return {'FALSE': 0, 'TRUE': 1}.get(value, float(value) if value not in ('FALSE', 'TRUE') else 0)
counts = {k: sum(number(x[k]) for x in rows) for k in ('failed', 'skipped', 'error', 'warning', 'passed')}
assert counts == dict(failed=0, skipped=0, error=0, warning=4, passed=16750)
warnings = [(x['file'], x['test'], x['warning']) for x in rows if int(x['warning'])]
assert warnings == [
    ('test-dibble.R', 'gen and := accept factors as mutate does', '1'),
    ('test-dibble.R', 'a logical overwriting a Stata numeric keeps its storage', '1'),
    ('test-dibble.R', 'copying replacement isolates vectors and preserves grouping', '2'),
]
namespace = git('show', SOURCE + ':r-package/dtatools/NAMESPACE')
assert namespace == git('show', BASE + ':r-package/dtatools/NAMESPACE')
assert namespace == (ROOT / 'candidate-combined-01/library/dtatools/NAMESPACE').read_bytes()
installed = (ROOT / 'candidate-combined-01/installed-identity.R').read_text()
preflight = (ROOT / 'full-combined-01/preflight-identity.R').read_text()
assert 'exports = 106L' in installed
assert SOURCE in installed and SOURCE in preflight
assert str(ROOT / 'candidate-combined-01/library/dtatools/libs/dtatools.so') in installed
assert str(ROOT / 'candidate-combined-01/library/dtatools/libs/dtatools.so') in preflight
report = dict(status='pass', source_sha=SOURCE, package_tree=tree, runs=reports,
              test_counts=counts, public_exports=106, archived_source_files=234,
              limits='Completed artifacts and current bound-file identities; no workload rerun, timing acceptance, cross-platform claim, or full external OS/SDK/Python closure qualification.')
output = Path(__file__).with_suffix('.json')
with output.open('x') as stream:
    json.dump(report, stream, indent=2)
    stream.write('\n')
print(json.dumps(report))
