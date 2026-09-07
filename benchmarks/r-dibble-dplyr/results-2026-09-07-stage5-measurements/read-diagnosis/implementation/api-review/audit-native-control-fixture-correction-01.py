"""Retained source/product/input audit only; does not run a native control."""
from pathlib import Path
import csv
import hashlib
import json

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

pins={
 'baseline-ec10-read-control-v2-01':'3674a885a4f7cd22accc9c12da5d37efc364ab0f4573444730232ea0574d5803',
 'baseline-ec10-read-fixture-diagnostic-01':'3dcab58a6646085f3f4a9e58cb589b6b5624c51f55028c48e6a64cbc9222c230',
 'candidate-a2d8b6a-read-fixture-diagnostic-01':'c98cc98e05648f7168b8298d2024decc79d5afff0c7943fbaf99755d88f09097',
 'baseline-ec10-read-tiny-check-01':'5ef010b81d42c5b8146468a91afb127cee8b1593be48a1c4c4801985cfbb8e2d',
 'candidate-a2d8b6a-read-tiny-check-01':'28c23f05271c74a0b1cf19ecc7e2c450f7f4bc167a7338332c335fed9d366f1e',
}
old=json.loads((Path(__file__).parent/'audit-native-read-control-final-preparation-02.json').read_text())
assert identity(ROOT/'read-control-v1.c')==old['C']
assert identity(ROOT/'read-control-v1.R')==old['R']
assert identity(ROOT/'read-control-v2.py')==old['runtime_v2']
assert identity(ROOT/'native-read-control-build-v5-01/dta_read_control.so')==old['diagnostic_dll']
assert identity(ROOT/'read-control-v2.R')['sha256']=='d62d62c92ea403ece6fb90a9d023f4a34d70536ffa9ad88ae026092d296ed9ef'
assert identity(ROOT/'read-control-v3.py')['sha256']=='7d4d620948718e595fb110291417b98a798ea449fd7a131a8fa28bb09a614428'
v1=(ROOT/'read-control-v1.R').read_text(); v2=(ROOT/'read-control-v2.R').read_text(); tiny=(ROOT/'read-control-tiny-check-v1.R').read_text()
assert v1[v1.index('records <- states <- list()'):]==v2[v2.index('records <- states <- list()'):]
assert tiny.startswith(v2[:v2.index('records <- states <- list()')])
assert 'atomic_profile(' not in tiny and 'bench::mark(' not in tiny
assert (ROOT/'read-control-v2.py').read_text().replace("script = ROOT / 'read-control-v1.R'", "script = ROOT / 'read-control-v2.R'")==(ROOT/'read-control-v3.py').read_text()

build=ROOT/'native-read-control-build-v5-01'
build_products=json.loads((build/'manifest.json').read_text())['products']
expected_build=[identity(build/'completed-receipt.json'),identity(build/'manifest.json'),*build_products,*json.loads((build/'inputs-before.json').read_text())['inputs']]
records=[]
for name,pin in pins.items():
    folder=ROOT/name; rp=ROOT/(name+'-receipt.json')
    receipt_identity=identity(rp); assert receipt_identity['sha256']==pin
    receipt=json.loads(rp.read_text()); manifest_path=folder/'manifest.json'
    assert receipt['manifest']==identity(manifest_path)
    products=json.loads(manifest_path.read_text())['products']
    assert all(identity(row['path'])==row for row in products)
    assert {str(p) for p in folder.iterdir()}=={row['path'] for row in products}|{str(manifest_path)}
    inputs_doc=json.loads((folder/'inputs-before.json').read_text()); inputs=inputs_doc['inputs']
    expected_source=('ec10a6ac34602f3bd691e8043019c1b479babda4' if name.startswith('baseline') else 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9')
    assert inputs_doc['source']==expected_source
    assert len({row['path'] for row in inputs})==len(inputs)
    assert all(identity(row['path'])==row for row in inputs)
    by_path={row['path']:row for row in inputs}
    assert all(by_path[row['path']]==row for row in expected_build)
    assert str(ROOT/'native-read-control-build-v5-01/dta_read_control.so')==inputs_doc['command'][-1]
    assert inputs_doc['command'][-2]=='7'
    result=json.loads((folder/'execution-result.json').read_text())
    assert receipt['changed_inputs']==result['changed_inputs']==[]
    assert receipt['integrity_error']==result['integrity_error']==None
    log=(folder/'execution.log').read_text()
    namespaces=dlls=[]
    failed=name=='baseline-ec10-read-control-v2-01'
    assert receipt['accepted']==(not failed) and receipt['returncode']==result['returncode']==int(failed)
    if failed:
        assert 'identical(as.character(x), values) is not TRUE' in log
        assert not receipt['namespace_coverage'] and not receipt['dll_coverage']
        assert not any('measurement' in row['path'] or 'bench' in Path(row['path']).name for row in products)
    else:
        assert receipt['namespace_coverage'] and receipt['dll_coverage']
        bound={row['resolved'] for row in inputs}
        with (folder/'namespaces.tsv').open() as stream:namespaces=list(csv.DictReader(stream,delimiter='\t'))
        with (folder/'dlls.tsv').open() as stream:dlls=list(csv.DictReader(stream,delimiter='\t'))
        assert all(str((Path(row['path'])/'DESCRIPTION').resolve(strict=True)) in bound for row in namespaces)
        assert all((row['name']=='base' and row['path']=='base') or str(Path(row['path']).resolve(strict=True)) in bound for row in dlls)
        assert any(row['path']==inputs_doc['command'][-1] for row in dlls)
        if 'tiny-check' in name:
            assert log.count('Checking tiny native control')==8
            assert 'PASS eight tiny constructor/native controls; no timing or profiling' in log
        else:
            assert 'OBSERVED eight tiny fixture/container combinations; no benchmark or changed oracle' in log
    assert receipt_identity==identity(rp) and receipt['manifest']==identity(manifest_path)
    records.append(dict(name=name,receipt=receipt_identity,products=len(products),inputs=len(inputs),namespace_rows=len(namespaces),dll_rows=len(dlls),accepted=receipt['accepted'],source=expected_source,changed_inputs=[]))

sources={n:identity(ROOT/n) for n in ['read-control-v1.c','read-control-v1.R','read-control-v2.R','read-control-v2.py','read-control-v3.py','read-control-fixture-diagnostic-v1.R','read-control-fixture-diagnostic-v1.py','read-control-tiny-check-v1.R','read-control-tiny-check-v1.py','read-control-diagnosis.md']}
report=dict(status='clear',reviewer_source=identity(__file__),sources=sources,runs=records,
 measured_R_suffix_byteidentical=True,tiny_prefix_byteidentical=True,runtime_only_R_filename_changed=True,accepted_build_records_preserved_in_each_runtime=True,
 scope='Independent source/receipt/product/current input/namespace/DLL checks. No diagnostic or correctness control rerun. Separate saved-RDS-only reader checks the sixteen retained observation records.',
 limits=['Failed baseline preserves its return code 1 and incomplete namespace/DLL coverage; no profiling/timing products exist for that attempt.', 'Tiny checks establish this eight-combination prefix only, not performance or a completed full control run.', 'Constructor normalization is supported by explicit ec10/a2 source and observations; no native implementation change or exclusive performance-cause claim.', 'Full external compiler, OS and Python closures are not frozen. Current checks do not upgrade original provenance or authenticate external records.'])
with OUT.open('x') as stream:json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps({'status':'clear','runs':[{k:r[k] for k in ['name','products','inputs','namespace_rows','dll_rows','accepted']} for r in records]},indent=2))
