from pathlib import Path
from datetime import datetime,timezone
import csv,hashlib,json,math
root=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance')
review=Path('/private/tmp/dta-direct-stage5-validation/implementation/semantics-review')
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=hashlib.sha256(q.read_bytes()).hexdigest())
def check(x):assert ident(x['path'])==x,x['path']
def close(a,b):assert math.isclose(float(a),float(b),rel_tol=1e-12,abs_tol=1e-10),(a,b)
prior=json.loads((review/'read-count-preparation-review-01.json').read_text())
for x in prior['sources']:
 if x['path'].endswith(('read-count-control-v1.R','read-count-control-v1.py')):check(x)
build=json.loads((root/'native-read-count-control-build-v1-01/completed-receipt.json').read_text());check(build['manifest']);assert build['accepted']
build_products=json.loads((root/'native-read-count-control-build-v1-01/manifest.json').read_text())['products'];build_inputs=json.loads((root/'native-read-count-control-build-v1-01/inputs-before.json').read_text())['inputs']
expected_build=[ident(root/'native-read-count-control-build-v1-01/completed-receipt.json'),build['manifest'],*build_products,*build_inputs]
raw=list(csv.DictReader((review/'read-count-raw-series-01.csv').open()));samples=list(csv.DictReader((review/'read-count-raw-samples-01.csv').open()));states=list(csv.DictReader((review/'read-count-state-facts-01.csv').open()));assert len(raw)==144 and len(samples)==1008 and len(states)==576
assert 'PASS 144 medians, 1008 samples, 576 states, 36 untimed count/visit records and 144 tiny records' in (review/'read-count-raw-record-reader-01.log').read_text()
assessment=json.loads((root/'read-count-control-v1-root-assessment-01.json').read_text())
receipt_pins={x['name']:x['sha256'] for x in assessment['runs']}
all_inputs={};common=None;runs=[];metrics={}
for repeat in range(1,4):
 for label in ['baseline-ec10','candidate-a2d8b6a']:
  name=f'{label}-read-count-control-v1-{repeat:02d}';d=root/name;rp=root/(name+'-receipt.json');rec=json.loads(rp.read_text());ib=json.loads((d/'inputs-before.json').read_text());m=json.loads((d/'manifest.json').read_text())
  assert rec['accepted'] and rec['returncode']==0 and rec['changed_inputs']==[] and rec['namespace_coverage'] and rec['dll_coverage'] and rec['integrity_error'] is None
  check(rec['manifest']);assert ident(rp)['sha256']==receipt_pins[name]
  for x in m['products']:check(x)
  assert len(m['products'])==34
  assert {p.name for p in d.iterdir() if p.is_file()}=={Path(x['path']).name for x in m['products']}|{'manifest.json'}
  index={x['path']:x for x in ib['inputs']};assert len(index)==len(ib['inputs'])
  for row in expected_build:assert index[row['path']]==row
  for x in ib['inputs']:
   if x['path'] in all_inputs:assert all_inputs[x['path']]==x
   all_inputs[x['path']]=x
  source='ec10a6ac34602f3bd691e8043019c1b479babda4' if label=='baseline-ec10' else 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
  assert ib['source']==source and ib['runner_source']=='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
  command=ib['command'];assert command[2]==str(root/'read-count-control-v1.R') and command[-2]=='7' and command[-1]==str(root/'native-read-count-control-build-v1-01/dta_read_control.so')
  ns=list(csv.DictReader((d/'namespaces.tsv').open(),delimiter='\t'));bound={x['resolved'] for x in ib['inputs']}
  package=Path(next(x['path'] for x in ns if x['name']=='dtatools')).resolve()
  for x in ns:assert str((Path(x['path'])/'DESCRIPTION').resolve()) in bound
  for x in csv.DictReader((d/'dlls.tsv').open(),delimiter='\t'):
   if x['name']=='base' and x['path']=='base':continue
   assert str(Path(x['path']).resolve()) in bound
  nonpackage={k:v for k,v in index.items() if not Path(k).is_relative_to(package)}
  if common is None:common=nonpackage
  else:assert nonpackage==common
  csvrows=list(csv.DictReader((d/'read-count-control.csv').open()));assert len(csvrows)==24
  assert {(x['kind'],x['operation'],int(x['rows']),int(x['columns'])) for x in csvrows}=={(k,op,n,1) for k in ['logical','factor','ordered'] for op in ['public_table','public_column','native_elt','native_pointer'] for n in [100000,1000000]}
  for i,row in enumerate(csvrows,1):
   rawrow=next(x for x in raw if x['run']==name and int(x['index'])==i)
   close(row['median_ms'],rawrow['median_ms']);assert int(row['iterations'])==7 and float(row['gc_count'])==float(rawrow['gc_count'])
   assert float(row['bench_allocated_bytes'])==float(rawrow['allocation'])
   assert all(float(v)==0 for k,v in row.items() if k.startswith('native_'))
   for k in ['validation_scan_calls','validation_scanned_values']:assert row[k]==('NA' if label=='baseline-ec10' else '0')
   assert int(row['expected_count'])==int(row['rows'])*3//4
   metrics[(repeat,label,row['kind'],row['operation'],int(row['rows']))]=row
  for kind in ['logical','factor','ordered']:
   for n in [100000,1000000]:
    ss=[x for x in states if x['run']==name and x['kind']==kind and int(x['rows'])==n];assert len(ss)==16
    assert len({x['backing'] for x in ss})==len({x['handle'] for x in ss})==1
    assert all(x['exposed']=='FALSE' for x in ss)
    assert len({(x['handle_shared'],x['backing_private']) for x in ss})==1
  assert (d/'execution.log').read_text().rstrip().endswith('PASS 24 logical/factor/ordered nonmissing-count controls; native visit counts were untimed')
  runs.append(dict(name=name,receipt=ident(rp),products=34,inputs=len(index),source=source,package_namespace=str(package),command=command))
for x in all_inputs.values():check(x)
comparisons=[]
for x in assessment['comparisons']:
 b=metrics[(x['pair'],'baseline-ec10',x['kind'],x['operation'],x['rows'])];c=metrics[(x['pair'],'candidate-a2d8b6a',x['kind'],x['operation'],x['rows'])]
 bv=float(b['median_ms']);cv=float(c['median_ms']);delta=cv-bv;ratio=cv/bv;flag=delta>1 and ratio>1.1
 for field,value in [('baseline_ms',bv),('candidate_ms',cv),('delta_ms',delta),('ratio',ratio)]:close(x[field],value)
 assert x['flag']==flag;comparisons.append(x)
assert len(comparisons)==72 and sum(x['flag'] for x in comparisons)==27
assert all(x['rows']==1000000 and x['operation'] in ['public_table','public_column','native_elt'] for x in comparisons if x['flag'])
visit_rows=list(csv.DictReader((review/'read-count-untimed-visits-01.csv').open()));tiny_rows=list(csv.DictReader((review/'read-count-tiny-records-measured-01.csv').open()));assert len(visit_rows)==36 and len(tiny_rows)==144
allocation_equal=True
for x in comparisons:
 b=metrics[(x['pair'],'baseline-ec10',x['kind'],x['operation'],x['rows'])];c=metrics[(x['pair'],'candidate-a2d8b6a',x['kind'],x['operation'],x['rows'])]
 for field in ['bench_allocated_bytes','r_allocated_bytes','r_largest_allocation_bytes']:
  allocation_equal=allocation_equal and b[field]==c[field]
assert allocation_equal
assert ident(root/'read-count-control-v1-root-assessment-01.json')['sha256']=='ef53ccc873e83aa4fd5efb7e6faccd6fae290b6b90815e5d5947e0826fca3f09'
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='six_count_runs_evidence_clear',reviewer_script=ident(__file__),runs=runs,distinct_inputs_rehashed=len(all_inputs),exact_common_nonpackage_inputs=len(common),reviewer_attempt_note='Attempt01 reused an overly restrictive character-control private/shared-state assertion. Count fixtures preserve stable state but factor/ordered candidate backing is private while handles are shared. Attempt02 records the observed state and enforces actual depth/exposure/byte/backing invariants instead; original evidence unchanged.',raw_series=144,raw_samples=1008,state_facts=576,untimed_native_visit_records=visit_rows,tiny_records=tiny_rows,comparisons=comparisons,matched_allocation_metrics=True,root_assessment=ident(root/'read-count-control-v1-root-assessment-01.json'),saved_reader=[ident(review/x) for x in ['read-count-raw-record-reader-01.R','read-count-raw-record-reader-01.log','read-count-raw-series-01.csv','read-count-raw-samples-01.csv','read-count-state-facts-01.csv','read-count-untimed-visits-01.csv','read-count-tiny-records-measured-01.csv']],assessment=[
'All six successful receipts, 34 products per run, complete input inventories and namespace/DLL bindings independently rechecked. All consume the reviewed count C/DLL build and exact R/runtime sources. All common runtime/helper/driver/build identities match after excluding only the recorded installed dtatools directory.',
'Independent saved-RDS reader recalculates144 medians from1008 positive raw second samples multiplied by1000, checks all GC/allocation summaries and seven iterations per series. GC-bearing samples remain included because filter_gc is FALSE. All paired same-operation R/bench allocation summaries match between sources; native copy counters are zero. Baseline validation scan availability is NA and candidate scan counts are zero.',
'All576 saved state facts preserve backing and handle within each fixture across four operations/phases. Candidate is unexposed owned depth one; baseline is ordinary depth zero. Reported bytes are four times rows; observed sharing/privacy states remain recorded. Executed source checks preserve full values and metadata, while saved state records alone are not full value-object snapshots.',
'The36 saved untimed count/visit records equal75 percent nonmissing and full row-count visits for the separate diagnostic loop. The144 saved tiny records preserve expected counts/types/attributes across ordinary and table columns. Those checks do not instrument base R is.na or sum visits.',
'All72 paired arithmetic rows and strict greater-than10-percent AND greater-than1-ms flags recalculate. Each pair has nine1M flags: public table, public column and native element access for each of logical, factor and ordered. No pointer or100k comparison crosses both thresholds. Root flag count27 is exact.',
'Pre-extracted public count expressions retain the between-source cost in all three kinds; matched rooted pointer scans have near-equal between-source times. This supports continuing investigation of element-access paths, including dispatch and compiler optimization opportunities. Native element loops have different absolute costs and cannot isolate getter latency or identify an exclusive cause.',
'Whole public sum(!is.na) creates intermediate vectors; matched native full scans avoid those intermediates. Their observed allocation difference is not an allocation-equivalent implementation comparison. Native scalar result creation occurs outside the pointer loop; reported zero allocation does not assert absence of all allocator activity. R/native counters may overlap and must not be added.',
'These controls cover three nonmissing-count operations only. They do not independently attribute mean/coercion/other retained read costs, establish irreducibility, waive any open flag or establish overall Stage5 acceptance.'
],limits='Retained source/input/product and saved-RDS/CSV audit only. No constructor, native control, benchmark, build, test or allocation-profile rerun. Raw original Rprofmem events and per-timed-call native counters are not retained; timed values/metadata were checked by the executed source.')
with (review/'read-count-control-evidence-review-02.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],runs=6,series=144,samples=1008,states=576,flags=27,distinct_inputs=len(all_inputs),common_inputs=len(common),report=ident(review/'read-count-control-evidence-review-02.json'))))
