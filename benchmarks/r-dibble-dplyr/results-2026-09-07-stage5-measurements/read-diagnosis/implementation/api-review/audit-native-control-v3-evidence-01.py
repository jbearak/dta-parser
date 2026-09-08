"""Audit six completed native-control runs without launching native or timed work."""
from pathlib import Path
import csv
import hashlib
import json
import math

ROOT=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance')
OUT=Path(__file__).with_suffix('.json')
CACHE={}
def identity(path):
    path=Path(path); resolved=path.resolve(strict=True); st=resolved.stat()
    key=(str(resolved),st.st_size,st.st_mtime_ns,st.st_mode)
    if key not in CACHE:
        h=hashlib.sha256()
        with resolved.open('rb') as stream:
            while chunk:=stream.read(8*1024*1024):h.update(chunk)
        CACHE[key]=h.hexdigest()
    return dict(path=str(path),resolved=str(resolved),bytes=st.st_size,mode=oct(st.st_mode&0o777),sha256=CACHE[key])

assessment_path=ROOT/'read-control-v3-root-assessment-01.json'
assessment_identity=identity(assessment_path)
assessment=json.loads(assessment_path.read_text())
previous=json.loads((Path(__file__).parent/'audit-native-control-fixture-correction-01.json').read_text())
for name,record in previous['sources'].items():
    if name!='read-control-diagnosis.md':assert identity(ROOT/name)==record
failed=previous['runs'][0]
assert identity(ROOT/(failed['name']+'-receipt.json'))==failed['receipt']
failed_receipt=json.loads((ROOT/(failed['name']+'-receipt.json')).read_text())
assert failed_receipt['manifest']==identity(ROOT/failed['name']/'manifest.json') and not failed_receipt['accepted']
assert all(identity(row['path'])==row for row in json.loads((ROOT/failed['name']/'manifest.json').read_text())['products'])
build=ROOT/'native-read-control-build-v5-01'
assert identity(build/'completed-receipt.json')['sha256']=='a90771dd5c644160a2afe0bcce66f9bbf8d381ffe1d0987b5e1470125624cd74'
expected_build=[identity(build/'completed-receipt.json'),identity(build/'manifest.json'),*json.loads((build/'manifest.json').read_text())['products'],*json.loads((build/'inputs-before.json').read_text())['inputs']]
records=[]; metrics={}; common=None; all_products={}
for repeat in range(1,4):
    for tag,source in [('baseline-ec10','ec10a6ac34602f3bd691e8043019c1b479babda4'),('candidate-a2d8b6a','a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9')]:
        name=f'{tag}-read-control-v3-{repeat:02d}'; folder=ROOT/name; receipt_path=ROOT/(name+'-receipt.json')
        receipt_identity=identity(receipt_path); receipt=json.loads(receipt_path.read_text())
        assert receipt_identity['sha256']==assessment['bindings'][name]['receipt_sha256']
        assert receipt['manifest']==assessment['bindings'][name]['manifest']==identity(folder/'manifest.json')
        products=json.loads((folder/'manifest.json').read_text())['products']; all_products.update({row['path']:row for row in products})
        assert all(identity(row['path'])==row for row in products)
        assert {str(p) for p in folder.iterdir()}=={row['path'] for row in products}|{str(folder/'manifest.json')}
        inputs_doc=json.loads((folder/'inputs-before.json').read_text()); inputs=inputs_doc['inputs']; by_path={row['path']:row for row in inputs}
        assert len(by_path)==len(inputs) and all(identity(row['path'])==row for row in inputs)
        assert all(by_path[row['path']]==row for row in expected_build)
        assert inputs_doc['source']==source and inputs_doc['runner_source']=='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
        command=inputs_doc['command']; assert command[2]==str(ROOT/'read-control-v2.R') and command[-2]=='7' and command[-1]==str(build/'dta_read_control.so')
        assert by_path[str(ROOT/'read-control-v3.py')]==identity(ROOT/'read-control-v3.py')
        package_dir=Path(command[3])/'dtatools'
        shared=[row for row in inputs if not Path(row['path']).is_relative_to(package_dir)]
        if common is None:common=shared
        else:assert shared==common
        result=json.loads((folder/'execution-result.json').read_text())
        assert receipt['accepted'] and receipt['returncode']==result['returncode']==0
        assert receipt['changed_inputs']==result['changed_inputs']==[] and receipt['integrity_error']==result['integrity_error']==None
        assert receipt['namespace_coverage'] and result['namespace_coverage'] and receipt['dll_coverage'] and result['dll_coverage']
        bound={row['resolved'] for row in inputs}
        with (folder/'namespaces.tsv').open() as stream:namespaces=list(csv.DictReader(stream,delimiter='\t'))
        with (folder/'dlls.tsv').open() as stream:dlls=list(csv.DictReader(stream,delimiter='\t'))
        assert all(str((Path(row['path'])/'DESCRIPTION').resolve(strict=True)) in bound for row in namespaces)
        assert all((row['name']=='base' and row['path']=='base') or str(Path(row['path']).resolve(strict=True)) in bound for row in dlls)
        log=(folder/'execution.log').read_text()
        assert log.count('Checking tiny native control')==8 and 'PASS eight declared-character read controls; visit counts were untimed' in log
        assert 'Warning' not in log and 'Error' not in log
        with (folder/'read-control.csv').open() as stream:rows=list(csv.DictReader(stream))
        assert len(rows)==8 and {(r['operation'],int(r['rows'])) for r in rows}=={(op,n) for op in ['public_table','public_column','native_elt','native_pointer'] for n in [100000,1000000]}
        for row in rows:
            assert row['columns']=='1' and row['iterations']=='7' and row['gc_count']=='0'
            assert float(row['median_ms'])>0 and all(float(row[k])==0 for k in row if k.startswith(('native_','r_','bench_allocated')))
            for k in ['validation_scan_calls','validation_scanned_values']:assert row[k]==('NA' if tag.startswith('baseline') else '0')
            metrics[(repeat,tag,row['operation'],int(row['rows']))]=float(row['median_ms'])
        records.append(dict(name=name,receipt=receipt_identity,source=source,inputs=len(inputs),products=len(products),series=8,namespace_rows=len(namespaces),dll_rows=len(dlls),raw_samples=56,accepted=True,changed_inputs=[]))
        assert receipt_identity==identity(receipt_path) and receipt['manifest']==identity(folder/'manifest.json')
for row in assessment['comparisons']:
    key=(row['repeat'],row['operation'],row['rows'])
    b=metrics[(key[0],'baseline-ec10',key[1],key[2])];c=metrics[(key[0],'candidate-a2d8b6a',key[1],key[2])]
    assert row['baseline_ms']==b and row['candidate_ms']==c
    assert math.isclose(row['delta_ms'],c-b,rel_tol=1e-12,abs_tol=1e-12) and math.isclose(row['ratio'],c/b,rel_tol=1e-12)
    assert row['flag']==(c/b>1.1 and c-b>1)
assert len(assessment['comparisons'])==24
flags=[r for r in assessment['comparisons'] if r['flag']]
assert len(flags)==9 and all(r['rows']==1000000 and r['operation']!='native_pointer' for r in flags)
assert assessment_identity==identity(assessment_path)
assert all(identity(path)==row for path,row in all_products.items())
report=dict(status='clear',reviewer_source=identity(__file__),runs=records,common_nonpackage_input_records=len(common),root_assessment=assessment_identity,comparisons_recalculated=24,flags=flags,
 sources={n:identity(ROOT/n) for n in ['read-control-v1.c','read-control-v2.R','read-control-v3.py']},accepted_build_receipt=identity(build/'completed-receipt.json'),old_failed_receipt=failed['receipt'],
 scope='Current complete retained input/product/receipt and common-runtime equality audit, CSV arithmetic and source reporting review. Separate saved-RDS reader checks raw samples and four source-state checkpoints; no benchmarks or native controls rerun.',
 limits=['One declared-character column, two sizes, three sequential pairs only; no claim for other types or operations.', 'Native visit counts are a separate untimed loop; neither its count nor separately compiled STRING_ELT latency measures the internal base anyNA getter.', 'Temporary allocation events and each timed call native counters are not retained. Value/metadata preservation is an executed assertion; saved state permits independent handle/backing checks.', 'Root assessment records CSV arithmetic with current bindings, not a new pre-bound benchmark execution; full external OS/compiler/Python closures remain outside scope.'])
with OUT.open('x') as stream:json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps({'status':'clear','runs':len(records),'series':48,'raw_samples':336,'comparisons':24,'flags':len(flags),'common_nonpackage_inputs':len(common)},indent=2))
