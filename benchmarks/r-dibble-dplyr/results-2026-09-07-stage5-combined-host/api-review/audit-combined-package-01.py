"""Read-only audit of completed package qualification and distributed archives."""
from pathlib import Path
import hashlib
import json
import re
import tarfile

ROOT=Path('/private/tmp/dta-direct-stage5-validation/implementation/package-combined-01')
SOURCE='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
CACHE={}
def identity(p):
    p=Path(p); target=p.resolve(strict=True); info=target.stat()
    key=(str(target),info.st_size,info.st_mtime_ns,info.st_mode)
    if key not in CACHE: CACHE[key]=hashlib.sha256(target.read_bytes()).hexdigest()
    return dict(path=str(p),resolved=str(target),bytes=info.st_size,mode=oct(info.st_mode & 0o777),sha256=CACHE[key])
def verify(row):
    actual=identity(row['path'])
    assert all(actual[k]==v for k,v in row.items() if k in actual),row['path']
receipt=json.loads((ROOT/'receipt.json').read_text())
assert receipt['status']=='complete' and not receipt['changed_inputs']
assert receipt['source_sha']==receipt['runner_sha']==SOURCE
verify(receipt['manifest'])
products=json.loads((ROOT/'manifest.json').read_text())['products']
assert len(products)==len({x['path'] for x in products})
assert {str(x) for x in ROOT.rglob('*') if x.is_file()}=={x['path'] for x in products}|{str(ROOT/'manifest.json'),str(ROOT/'receipt.json')}
for row in products: verify(row)
inputs=json.loads((ROOT/'inputs-before.json').read_text())
assert inputs['source_sha']==inputs['runner_sha']==SOURCE
for row in inputs['inputs']: verify(row)
result=json.loads((ROOT/'execution-result.json').read_text())
assert result['status']=='complete' and not result['changed_inputs']
assert all(x['exit_code']==0 for x in result['records'])
labels=[x['label'] for x in result['records']]
assert labels==['preflight','archive-unit','vendor-unit','vendor-rebuild-unit','vendor','rust-source-hash','haven','labelled','haven-conformance','corpus-framework','roxygen','conformance','build','archive','check','binary']
consumed=json.loads((ROOT/'built-source-before-checks.json').read_text())
verify(consumed)
for label in ['archive','check','binary']:
    record=next(x for x in result['records'] if x['label']==label)
    assert consumed['path'] in record['command']
notice=(ROOT/'source/r-package/dtatools/inst/NOTICE').read_bytes()
namespace=(ROOT/'source/r-package/dtatools/NAMESPACE').read_bytes()
assert sum(x.startswith(b'export(') for x in namespace.splitlines())==106
archive_details=[]
for archive_path,is_source in [(Path(consumed['path']),True),(ROOT/'binary/dtatools_0.7.1.tgz',False)]:
    with tarfile.open(archive_path) as archive:
        members={x.name:x for x in archive.getmembers() if x.isfile()}
        assert archive.extractfile(members['dtatools/'+('inst/' if is_source else '')+'NOTICE']).read()==notice
        assert archive.extractfile(members['dtatools/NAMESPACE']).read()==namespace
        if is_source:
            for path in (ROOT/'source/r-package/dtatools/R').glob('*.R'):
                assert archive.extractfile(members['dtatools/R/'+path.name]).read()==path.read_bytes()
            for path in ['src/init.c','tests/testthat/helper-generation-interrupt.R','tests/testthat/test-dibble-expressions.R','tests/testthat/test-mutate-data.R']:
                assert archive.extractfile(members['dtatools/'+path]).read()==(ROOT/'source/r-package/dtatools'/path).read_bytes()
        archive_details.append(dict(**identity(archive_path),file_members=len(members)))
for package in [ROOT/'binary/library/dtatools',ROOT/'dtatools.Rcheck/dtatools']:
    assert (package/'NOTICE').read_bytes()==notice
    assert (package/'NAMESPACE').read_bytes()==namespace
log=(ROOT/'dtatools.Rcheck/00check.log').read_text()
assert 'Status: 3 WARNINGs, 2 NOTEs' in log and 'No news entries found' not in log
warnings=[x for x in log.splitlines() if x.startswith('* checking') and x.endswith('WARNING')]
notes=[x for x in log.splitlines() if x.startswith('* checking') and x.endswith('NOTE')]
assert len(warnings)==3 and len(notes)==2
tests=(ROOT/'dtatools.Rcheck/tests/testthat.Rout').read_text()
assert re.search(r'FAIL\s+0.*WARN\s+4.*SKIP\s+0.*PASS\s+16750',tests), tests[-1000:]
report=dict(status='pass',source=SOURCE,receipt_sha256=identity(ROOT/'receipt.json')['sha256'],manifest_sha256=receipt['manifest']['sha256'],products=len(products),inputs=len(inputs['inputs']),commands=len(labels),consumed_source=consumed,archives=archive_details,Rcheck_warnings=warnings,Rcheck_notes=notes,public_exports=106,
    limits='R CMD check --no-manual on the recorded host, with three established warnings and two notes. External OS dylibs/full SDK/Python closure remain outside scope. No commands or tests were rerun for this audit.')
with Path(__file__).with_suffix('.json').open('x') as stream: json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps(report))
