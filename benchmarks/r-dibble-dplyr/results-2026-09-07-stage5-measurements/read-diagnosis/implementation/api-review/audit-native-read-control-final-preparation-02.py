"""Read-only completed-artifact audit; no R or measured operation is launched."""
from pathlib import Path
import collections
import csv
import hashlib
import json
import math

ROOT = Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance')
OUT = Path(__file__).with_suffix('.json')
CACHE = {}

def identity(path):
    path = Path(path)
    target = path.resolve(strict=True)
    info = target.stat()
    key = (str(target), info.st_size, info.st_mtime_ns, info.st_mode)
    if key not in CACHE:
        CACHE[key] = hashlib.sha256(target.read_bytes()).hexdigest()
    return dict(path=str(path), resolved=str(target), bytes=info.st_size,
                mode=oct(info.st_mode & 0o777), sha256=CACHE[key])

def read_csv(path):
    with path.open() as stream:
        return list(csv.DictReader(stream))


import shlex
records=[]
for version in range(1,6):
 folder=ROOT/f'native-read-control-build-v{version}-01';receipt_path=folder/'completed-receipt.json'
 receipt=json.loads(receipt_path.read_text());manifest=json.loads((folder/'manifest.json').read_text());result=json.loads((folder/'execution-result.json').read_text())
 assert receipt['manifest']==identity(folder/'manifest.json') and not receipt['changed_inputs']
 assert receipt['accepted']==result['accepted']==(version==5) and not result['changed_inputs']
 assert all(identity(x['path'])==x for x in manifest['products'])
 assert {str(x) for x in folder.iterdir()}=={x['path'] for x in manifest['products']}|{str(folder/'manifest.json'),str(receipt_path)}
 inputs=[];preparation=[]
 for filename in ['preparation-inputs-before.json','inputs-before.json']:
  path=folder/filename
  if path.exists():
   items=json.loads(path.read_text())['inputs'];assert all(identity(x['path'])==x for x in items)
   if filename=='inputs-before.json':inputs=items
   else:preparation=items
 expected_error={1:"'stdlib.h' file not found",2:"'-fuse-ld=' taking a path is deprecated",3:'cast-function-type-mismatch',4:'must link with libSystem.dylib'}
 if version<5:
  assert result['error'] is not None and result['commands'][-1]['returncode']==1
  log=(folder/('dependency-discovery.log' if version==1 else 'build.log')).read_text();assert expected_error[version] in log
 else:
  assert result['error'] is None and len(result['commands'])==2 and all(r['returncode']==0 for r in result['commands'])
  assert len(inputs)==192 and len(preparation)==58 and len(manifest['products'])==8
  assert (folder/'build.log').read_text()=='' and (folder/'dependency-discovery.log').read_text()==''
  def dependencies(path):
   text=path.read_text().replace('\\\n',' ');target,sep,names=text.partition(':');assert sep and target.strip()=='diagnostic';return {str(Path(x).resolve(strict=True)) for x in shlex.split(names)}
  discovered=dependencies(folder/'dependency-discovery.txt');compiled=dependencies(folder/'compiled-dependencies.txt');assert discovered==compiled
  bound={x['resolved'] for x in inputs};assert compiled<=bound
  assert '/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk/SDKSettings.json' in bound
  assert '/Library/Developer/CommandLineTools/usr/lib/clang/21/lib/darwin/libclang_rt.osx.a' in bound
  assert any(x.endswith('/usr/lib/libSystem.B.tbd') for x in bound)
  assert '--ld-path=/Library/Developer/CommandLineTools/usr/bin/ld' in result['commands'][1]['command']
  assert '-nostdlib' not in result['commands'][1]['command'] and '-Wno-cast-function-type-mismatch' in result['commands'][1]['command']
  assert identity(receipt_path)['sha256']=='a90771dd5c644160a2afe0bcce66f9bbf8d381ffe1d0987b5e1470125624cd74'
 records.append(dict(version=version,receipt=identity(receipt_path),accepted=version==5,products=len(manifest['products']),inputs=len(inputs),preparation_inputs=len(preparation),builder=identity(ROOT/f'build-read-control-v{version}.py')))
folder=ROOT/'read-control-binding-checks-01';receipt_path=folder/'completed-receipt.json';receipt=json.loads(receipt_path.read_text());manifest=json.loads((folder/'manifest.json').read_text());inputs=json.loads((folder/'inputs-before.json').read_text())['inputs'];result=json.loads((folder/'execution-result.json').read_text())
assert identity(receipt_path)['sha256']=='f2963685ea6aa2c2c9c17b258c8087fa6101a9d971fa93c2e3bb0e48cb8d8471'
assert receipt['accepted'] and receipt['manifest']==identity(folder/'manifest.json')
assert result['accepted'] and result['returncode']==0 and result['error'] is None and not result['changed_inputs']
assert len(inputs)==4 and len(manifest['products'])==3 and all(identity(x['path'])==x for x in inputs+manifest['products'])
assert {str(x) for x in folder.iterdir()}=={x['path'] for x in manifest['products']}|{str(folder/'manifest.json'),str(receipt_path)}
assert 'Ran 8 tests' in (folder/'tests.log').read_text() and '\nOK\n' in (folder/'tests.log').read_text()
original=json.loads((Path(__file__).parent/'native-read-control-source-review-01.json').read_text())
for name in ['read-control-v1.c','read-control-v1.R','build-read-control-v1.py','read-control-v1.py']:
 assert identity(ROOT/name)['sha256']==original['sources'][name]
report=dict(status='clear',builds=records,final_dependency_entries=len(compiled),binding_test_receipt=identity(receipt_path),binding_test_inputs=4,binding_test_products=3,binding_test_cases=8,
 runtime_v2=identity(ROOT/'read-control-v2.py'),C=identity(ROOT/'read-control-v1.c'),R=identity(ROOT/'read-control-v1.R'),diagnostic_dll=identity(ROOT/'native-read-control-build-v5-01/dta_read_control.so'),
 observations={'otool_dependency':'Only /usr/lib/libSystem.B.dylib besides the DLL install name; no second libR load command.','nm_undefined':['DATAPTR_RO','R_NaString','R_forceSymbols','R_registerRoutines','R_useDynamicSymbols','Rf_ScalarLogical','Rf_ScalarReal','Rf_error','Rf_protect','Rf_unprotect','STRING_ELT','TYPEOF','XLENGTH','dyld_stub_binder']},
 conclusions=['Runtime v2 closes accepted-build rebinding gap: receipt/manifest JSON reads are checked against already frozen identities; validated product and input records must match the runtime before snapshot, are checked before launch and again in finally.','Eight retained temporary-file guard tests meaningfully cover altered bytes/mode/target, missing/duplicate paths, rejected parse consumption and final/prelaunch missing input. They test helpers, not a native R run.','V5 uses exact resolved SDK, explicit linker path, precise registration-cast warning exception, bound libSystem stubs and compiler runtime archive. Prepared and actual compilation dependencies match, and the resulting DLL imports public R symbols dynamically.','All four earlier failures and builder source versions remain preserved. V1 failed dependency discovery before persisting its five in-memory input identities, so its retained evidence is command/error/product/receipt scope only. V2-v4 retain explicit preparation/compile input records.','C/R match original reviewed hashes, with rooted nonescaping bounded read loops, separate untimed visits and values/metadata/backing/native-counter gates. No control timing or R execution has occurred in this review; future runtime still needs exact completed-output/coverage audit. Full compiler/OS/Python closures remain excluded.'])
with OUT.open('x') as stream:json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps(dict(status='clear',final_build_inputs=192,prepared_inputs=58,dependency_entries=len(compiled),final_products=8,guard_tests=8,earlier_builds=[{k:r[k] for k in ['version','accepted','products','inputs','preparation_inputs']} for r in records[:-1]],runtime_sha256=report['runtime_v2']['sha256'])))
