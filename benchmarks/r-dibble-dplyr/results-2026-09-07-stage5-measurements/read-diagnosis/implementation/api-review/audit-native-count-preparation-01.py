"""Read-only source/build/tiny-output audit; no count controls are executed."""
from pathlib import Path
import csv
import hashlib
import json
import shlex

ROOT=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance')
OUT=Path(__file__).with_suffix('.json')
CACHE={}
def identity(path):
    path=Path(path); target=path.resolve(strict=True); st=target.stat()
    key=(str(target),st.st_size,st.st_mtime_ns,st.st_mode)
    if key not in CACHE:
        h=hashlib.sha256()
        with target.open('rb') as stream:
            while chunk:=stream.read(8*1024*1024):h.update(chunk)
        CACHE[key]=h.hexdigest()
    return dict(path=str(path),resolved=str(target),bytes=st.st_size,mode=oct(st.st_mode&0o777),sha256=CACHE[key])

pins={'read-count-control-v1.c':'6a8e877c22228606c5a223cf276629ce94421f020dc355854b810aac70a6612d',
      'read-count-control-v1.R':'fa4b27a88d55d808236403b4958ff3a1d9bcef9796ffb9be13b26dbfddbb1c88',
      'read-count-control-v1.py':'01d124dc60c85649b813dc8b92b053066fecb2efa3c1f78cafa31b99614e64e6',
      'build-read-count-control-v1.py':'2626d2cde41d8224668d1db6b76880851ea1ebfe73ca24fef1b3aaf8f578c5dd'}
for name,digest in pins.items():assert identity(ROOT/name)['sha256']==digest
old_build=(ROOT/'build-read-control-v5.py').read_text()
assert old_build.replace('Usage: build-read-control-v5.py NEW_OUTPUT_NAME','Usage: build-read-count-control-v1.py NEW_OUTPUT_NAME').replace("source = ROOT / 'read-control-v1.c'","source = ROOT / 'read-count-control-v1.c'")==(ROOT/'build-read-count-control-v1.py').read_text()
old_runtime=(ROOT/'read-control-v3.py').read_text().splitlines(); new_runtime=(ROOT/'read-count-control-v1.py').read_text().splitlines()
assert len(old_runtime)==len(new_runtime)
runtime_deltas=[(i,a,b) for i,(a,b) in enumerate(zip(old_runtime,new_runtime),1) if a!=b]
assert len(runtime_deltas)==3 and all(i in (1,78,135) for i,a,b in runtime_deltas)
driver=(ROOT/'read-count-control-v1.R').read_text(); tiny=(ROOT/'read-count-tiny-check-v1.R').read_text()
assert tiny.startswith(driver[:driver.index('records <- states <- visits <- list()')])
assert 'atomic_profile(' not in tiny and 'bench::mark(' not in tiny
prior=json.loads((Path(__file__).parent/'audit-native-control-v3-evidence-01.json').read_text())
for record in prior['sources'].values():assert identity(record['path'])==record
assert identity(prior['accepted_build_receipt']['path'])==prior['accepted_build_receipt']
assert identity(prior['old_failed_receipt']['path'])==prior['old_failed_receipt']

build=ROOT/'native-read-count-control-build-v1-01'; rp=build/'completed-receipt.json'
assert identity(rp)['sha256']=='13a64e286d65a0fc233ec5df24fc1fbe439ea13681f8ba51a938d303be320b08'
receipt=json.loads(rp.read_text()); result=json.loads((build/'execution-result.json').read_text())
assert receipt['accepted'] and result['accepted'] and receipt['changed_inputs']==result['changed_inputs']==[] and result['error'] is None
assert receipt['manifest']==identity(build/'manifest.json')
products=json.loads((build/'manifest.json').read_text())['products']
assert all(identity(row['path'])==row for row in products)
assert {str(p) for p in build.iterdir()}=={r['path'] for r in products}|{str(build/'manifest.json'),str(rp)}
build_inputs=json.loads((build/'inputs-before.json').read_text())['inputs']
preparation=json.loads((build/'preparation-inputs-before.json').read_text())['inputs']
assert all(identity(row['path'])==row for row in build_inputs+preparation)
assert len(result['commands'])==2 and all(c['returncode']==0 for c in result['commands'])
assert (build/'build.log').read_text()==(build/'dependency-discovery.log').read_text()==''
def dependencies(path):
    target,sep,names=path.read_text().replace('\\\n',' ').partition(':')
    assert sep and target.strip()=='diagnostic'
    return {str(Path(x).resolve(strict=True)) for x in shlex.split(names)}
discovered=dependencies(build/'dependency-discovery.txt'); compiled=dependencies(build/'compiled-dependencies.txt')
assert discovered==compiled and compiled<={row['resolved'] for row in build_inputs}
compile_command=result['commands'][1]['command']
assert '--ld-path=/Library/Developer/CommandLineTools/usr/bin/ld' in compile_command
assert '-Wl,-undefined,dynamic_lookup' in compile_command and '-nostdlib' not in compile_command
expected_build=[identity(rp),identity(build/'manifest.json'),*products,*build_inputs]
run_records=[]; common=None
for name,pin in [('baseline-ec10-read-count-tiny-01','8a68e63121b4f908dacbba79e9fafc1eb6e75d5293342e0704b83a01914cbce4'),('candidate-a2d8b6a-read-count-tiny-01','259cbd153f9cdfd42b7008c723bcfd2b24c640ed5277d1f385a5bde6c28b3d90')]:
    folder=ROOT/name; receipt_path=ROOT/(name+'-receipt.json'); receipt_id=identity(receipt_path)
    assert receipt_id['sha256']==pin
    r=json.loads(receipt_path.read_text()); result=json.loads((folder/'execution-result.json').read_text())
    assert r['manifest']==identity(folder/'manifest.json')
    run_products=json.loads((folder/'manifest.json').read_text())['products']
    assert all(identity(row['path'])==row for row in run_products)
    assert {str(p) for p in folder.iterdir()}=={row['path'] for row in run_products}|{str(folder/'manifest.json')}
    inputs_doc=json.loads((folder/'inputs-before.json').read_text()); inputs=inputs_doc['inputs']; by_path={row['path']:row for row in inputs}
    assert len(by_path)==len(inputs) and all(identity(row['path'])==row for row in inputs)
    assert all(by_path[row['path']]==row for row in expected_build)
    expected_source='ec10a6ac34602f3bd691e8043019c1b479babda4' if name.startswith('baseline') else 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
    assert inputs_doc['source']==expected_source
    command=inputs_doc['command']; assert command[2]==str(ROOT/'read-count-tiny-check-v1.R') and command[-1]==str(build/'dta_read_control.so')
    assert by_path[str(ROOT/'read-count-tiny-check-v1.py')]==identity(ROOT/'read-count-tiny-check-v1.py')
    shared=[row for row in inputs if not Path(row['path']).is_relative_to(Path(command[3])/'dtatools')]
    if common is None:common=shared
    else:assert shared==common
    assert r['accepted'] and r['returncode']==result['returncode']==0
    assert r['changed_inputs']==result['changed_inputs']==[] and r['integrity_error']==result['integrity_error']==None
    assert r['namespace_coverage'] and r['dll_coverage'] and result['namespace_coverage'] and result['dll_coverage']
    bound={row['resolved'] for row in inputs}
    with (folder/'namespaces.tsv').open() as stream:namespaces=list(csv.DictReader(stream,delimiter='\t'))
    with (folder/'dlls.tsv').open() as stream:dlls=list(csv.DictReader(stream,delimiter='\t'))
    assert all(str((Path(row['path'])/'DESCRIPTION').resolve(strict=True)) in bound for row in namespaces)
    assert all((row['name']=='base' and row['path']=='base') or str(Path(row['path']).resolve(strict=True)) in bound for row in dlls)
    log=(folder/'execution.log').read_text()
    assert log.count('Checking tiny nonmissing control')==24
    assert 'PASS 24 untimed logical/factor/ordered correctness cases; no profiling or timing' in log
    assert 'Warning' not in log and 'Error' not in log
    assert not list(folder.glob('raw-timing-*')) and not (folder/'read-count-control.csv').exists()
    run_records.append(dict(name=name,source=expected_source,receipt=receipt_id,inputs=len(inputs),products=len(run_products),namespace_rows=len(namespaces),dll_rows=len(dlls),tiny_cases=24,accepted=True))
    assert identity(receipt_path)==receipt_id and r['manifest']==identity(folder/'manifest.json')
report=dict(status='clear',reviewer_source=identity(__file__),sources={name:identity(ROOT/name) for name in [*pins,'read-count-tiny-check-v1.R','read-count-tiny-check-v1.py','read-count-control-preparation.md']},
 build=dict(receipt=identity(rp),inputs=len(build_inputs),preparation_inputs=len(preparation),products=len(products),matching_dependency_entries=len(compiled),diagnostic_dll=identity(build/'dta_read_control.so')),
 runs=run_records,common_nonpackage_inputs=len(common),runtime_changed_lines=runtime_deltas,tiny_prefix_exact=True,
 scope='Source review and current complete build/tiny input/product/receipt/namespace/DLL audit only; no build, benchmark or native correctness rerun. Separate saved-data reader checks the retained 48 tiny type/attribute/count records.',
 limits=['Native full scans are not allocation-equivalent implementations of public sum(!is.na()); do not infer isolated base getter costs from their absolute latency.', 'Tiny cases establish the untimed prefix only; the 24-series measurement driver remains unexecuted at this review.', 'Full compiler, external OS libraries and Python closures remain outside the explicit binding scope. Historical rejected attempts retain original identities.'])
with OUT.open('x') as stream:json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps(dict(status='clear',build_inputs=len(build_inputs),preparation_inputs=len(preparation),build_products=len(products),dependencies=len(compiled),runs=run_records),indent=2))
