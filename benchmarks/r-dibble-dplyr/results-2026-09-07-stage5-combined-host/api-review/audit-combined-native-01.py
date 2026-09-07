"""Read-only native gate artifacts, counters, source and runtime identity audit."""
from pathlib import Path
import csv
import hashlib
import json
import re
import subprocess
import tarfile

ROOT=Path('/private/tmp/dta-direct-stage5-validation/implementation/native-combined-01')
REPO=Path('/private/tmp/dta-direct-stage5')
SOURCE='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
CACHE={}
def identity(p):
    p=Path(p); target=p.resolve(strict=True); info=target.stat()
    key=(str(target),info.st_size,info.st_mtime_ns,info.st_mode)
    if key not in CACHE: CACHE[key]=hashlib.sha256(target.read_bytes()).hexdigest()
    return dict(path=str(p),resolved=str(target),bytes=info.st_size,mode=oct(info.st_mode&0o777),sha256=CACHE[key])
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
for row in inputs['inputs']: verify(row)
input_paths={x['path'] for x in inputs['inputs']}
result=json.loads((ROOT/'execution-result.json').read_text())
assert result['status']=='complete' and not result['changed_inputs']
assert [x['label'] for x in result['records']]==['preflight','native','native-atoms','rename']
assert all(x['exit_code']==0 for x in result['records'])
entries=subprocess.check_output(['git','-C',str(REPO),'ls-tree','-r','-z',SOURCE]).split(b'\0')
expected={}
for entry in entries:
    if not entry: continue
    metadata,path=entry.split(b'\t',1);mode,kind,blob=metadata.decode().split()
    assert kind=='blob';expected[path.decode()]=(mode,blob)
with tarfile.open(ROOT/'source.tar') as archive:
    members=[x for x in archive.getmembers() if x.isfile()]
    assert {x.name for x in members}==set(expected)
    for member in members:
        data=archive.extractfile(member).read();mode,blob=expected[member.name]
        assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==blob
        assert bool(member.mode&0o111)==(mode=='100755')
        path=ROOT/'source'/member.name
        assert path.read_bytes()==data and str(path) in input_paths
for name in ['benchmarks/r-reference-mutation/owned-atoms.R','benchmarks/r-dibble-dplyr/helpers.R']:
    assert str(REPO/name) in input_paths
    assert (REPO/name).read_bytes()==(ROOT/'source'/name).read_bytes()
session=(ROOT/'atoms/owned-native-atoms-session.txt').read_text()
assert 'source '+SOURCE in session
assert 'runner_revision ea031bec2df4d6711f1214b5dd3d00ebf029b3f1' in session
assert 'library /private/tmp/dta-direct-stage5-validation/implementation/candidate-combined-01/library' in session
for name in ['benchmarks/r-reference-mutation/owned-atoms.R','benchmarks/r-dibble-dplyr/helpers.R']:
    assert name+' '+identity(REPO/name)['sha256'] in session
metrics=dict(line.split('\t',1) for line in (ROOT/'native.log').read_text().splitlines() if '\t' in line)
rendered=dict(re.findall(r'^\| `([^`]+)` \| ([^|]+) \|$',(ROOT/'native.md').read_text(),re.M))
assert len(metrics)==len(rendered)==410 and metrics==rendered
assert metrics['benchmark_source_sha']==SOURCE and metrics['benchmark_source_state']=='clean'
assert metrics['existing_payload_copy_detected']=='false'
assert float(metrics['repeated_generation_large_seconds'])<max(.1,float(metrics['repeated_generation_small_seconds'])*8)
assert float(metrics['repeated_generation_large_total_profiled_allocation_bytes'])<max(500000,float(metrics['repeated_generation_small_total_profiled_allocation_bytes'])*8)
atoms=list(csv.DictReader((ROOT/'atoms/owned-native-atoms.csv').open()))
assert len(atoms)==18
assert {(x['kind'],x['rows'],x['operation']) for x in atoms}=={(k,n,o) for k in ['integer','factor','ordered'] for n in ['100000','1000000'] for o in ['first_shared','subsequent_private','full_replacement']}
for row in atoms:
    n=int(row['rows']);operation=row['operation']
    assert all(float(row[k])==0 for k in ['owned_capture','compact_copy','old_journal','native_scratch_allocated'])
    assert float(row['staged_new'])==4
    assert float(row['mutation_target_copy'])==(n*4 if operation=='first_shared' else 0)
    assert float(row['r_allocated_bytes'])==float(row['r_largest_allocation_bytes'])==(0 if operation=='subsequent_private' else n*4+48)
rename=[int(x) for x in re.findall(r': (\d+) bytes',(ROOT/'rename.log').read_text())]
assert rename==[0,0,40056,80112] and max(rename)<800000
report=dict(status='pass',receipt_sha256=identity(ROOT/'receipt.json')['sha256'],manifest_sha256=receipt['manifest']['sha256'],products=len(products),inputs=len(inputs['inputs']),git_export_files=len(expected),native_metrics=410,atomic_cases=18,rename_allocation_bytes=rename,
    limits='Native elapsed values and allocation aggregates are retained gate metrics, not a paired full-expression result. Temporary Rprofmem traces were not retained. Atomic staged_new remains 4 bytes; subsequent private zero applies to R allocation and target copies. Rename uses a 10,000-byte profiling threshold. No workload rerun.')
with Path(__file__).with_suffix('.json').open('x') as stream: json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps(report))
