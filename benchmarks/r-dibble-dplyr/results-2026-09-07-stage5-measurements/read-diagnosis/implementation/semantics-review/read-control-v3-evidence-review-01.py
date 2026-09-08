from pathlib import Path
from datetime import datetime,timezone
import csv,hashlib,json,math
root=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance')
review=Path('/private/tmp/dta-direct-stage5-validation/implementation/semantics-review')
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=hashlib.sha256(q.read_bytes()).hexdigest())
def check(x):assert ident(x['path'])==x,x['path']
def close(a,b):assert math.isclose(float(a),float(b),rel_tol=1e-12,abs_tol=1e-10),(a,b)
prior=json.loads((review/'read-control-fixture-correction-review-01.json').read_text())
for x in prior['sources']:
 if x['path'].endswith(('read-control-v2.R','read-control-v3.py')):check(x)
build=json.loads((root/'native-read-control-build-v5-01/completed-receipt.json').read_text());check(build['manifest']);assert build['accepted']
build_products=json.loads((root/'native-read-control-build-v5-01/manifest.json').read_text())['products'];build_inputs=json.loads((root/'native-read-control-build-v5-01/inputs-before.json').read_text())['inputs']
expected_build=[ident(root/'native-read-control-build-v5-01/completed-receipt.json'),build['manifest'],*build_products,*build_inputs]
raw=list(csv.DictReader((review/'read-control-raw-series-01.csv').open()));samples=list(csv.DictReader((review/'read-control-raw-samples-01.csv').open()));states=list(csv.DictReader((review/'read-control-state-facts-01.csv').open()));assert len(raw)==48 and len(samples)==336 and len(states)==192
assert 'PASS 48 medians, 336 samples and 192 saved state facts' in (review/'read-control-raw-record-reader-01.log').read_text()
assessment=json.loads((root/'read-control-v3-root-assessment-01.json').read_text())
all_inputs={};common=None;runs=[];metrics={}
for repeat in range(1,4):
 for label in ['baseline-ec10','candidate-a2d8b6a']:
  name=f'{label}-read-control-v3-{repeat:02d}';d=root/name;rp=root/(name+'-receipt.json');rec=json.loads(rp.read_text());ib=json.loads((d/'inputs-before.json').read_text());m=json.loads((d/'manifest.json').read_text())
  assert rec['accepted'] and rec['returncode']==0 and rec['changed_inputs']==[] and rec['namespace_coverage'] and rec['dll_coverage'] and rec['integrity_error'] is None
  check(rec['manifest']);assert ident(rp)['sha256']==assessment['bindings'][name]['receipt_sha256'] and rec['manifest']==assessment['bindings'][name]['manifest']
  for x in m['products']:check(x)
  assert len(m['products'])==16
  assert {p.name for p in d.iterdir() if p.is_file()}=={Path(x['path']).name for x in m['products']}|{'manifest.json'}
  index={x['path']:x for x in ib['inputs']};assert len(index)==len(ib['inputs'])
  for row in expected_build:assert index[row['path']]==row
  for x in ib['inputs']:
   if x['path'] in all_inputs:assert all_inputs[x['path']]==x
   all_inputs[x['path']]=x
  source='ec10a6ac34602f3bd691e8043019c1b479babda4' if label=='baseline-ec10' else 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
  assert ib['source']==source and ib['runner_source']=='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
  command=ib['command'];assert command[2]==str(root/'read-control-v2.R') and command[-2]=='7' and command[-1]==str(root/'native-read-control-build-v5-01/dta_read_control.so')
  ns=list(csv.DictReader((d/'namespaces.tsv').open(),delimiter='\t'));bound={x['resolved'] for x in ib['inputs']}
  package=Path(next(x['path'] for x in ns if x['name']=='dtatools')).resolve()
  for x in ns:assert str((Path(x['path'])/'DESCRIPTION').resolve()) in bound
  for x in csv.DictReader((d/'dlls.tsv').open(),delimiter='\t'):
   if x['name']=='base' and x['path']=='base':continue
   assert str(Path(x['path']).resolve()) in bound
  nonpackage={k:v for k,v in index.items() if not Path(k).is_relative_to(package)}
  if common is None:common=nonpackage
  else:assert nonpackage==common
  csvrows=list(csv.DictReader((d/'read-control.csv').open()));assert len(csvrows)==8
  assert {(x['operation'],int(x['rows']),int(x['columns'])) for x in csvrows}=={(op,n,1) for op in ['public_table','public_column','native_elt','native_pointer'] for n in [100000,1000000]}
  for i,row in enumerate(csvrows,1):
   rawrow=next(x for x in raw if x['run']==name and int(x['index'])==i)
   close(row['median_ms'],rawrow['median_ms']);assert int(row['iterations'])==7 and float(row['gc_count'])==float(rawrow['gc_count'])==0
   assert float(row['bench_allocated_bytes'])==float(rawrow['allocation'])==0
   assert all(float(v)==0 for k,v in row.items() if k.startswith(('native_','r_allocated','r_largest')))
   for k in ['validation_scan_calls','validation_scanned_values']:assert row[k]==('NA' if label=='baseline-ec10' else '0')
   metrics[(repeat,label,row['operation'],int(row['rows']))]=row
  for n in [100000,1000000]:
   ss=[x for x in states if x['run']==name and int(x['rows'])==n];assert len(ss)==16
   assert len({x['backing'] for x in ss})==len({x['handle'] for x in ss})==1
   assert all(x['exposed']=='FALSE' and x['backing_private']=='FALSE' and x['handle_shared']=='TRUE' for x in ss)
  assert (d/'execution.log').read_text().rstrip().endswith('PASS eight declared-character read controls; visit counts were untimed')
  runs.append(dict(name=name,receipt=ident(rp),products=16,inputs=len(index),source=source,package_namespace=str(package),command=command))
for x in all_inputs.values():check(x)
comparisons=[]
for x in assessment['comparisons']:
 b=metrics[(x['repeat'],'baseline-ec10',x['operation'],x['rows'])];c=metrics[(x['repeat'],'candidate-a2d8b6a',x['operation'],x['rows'])]
 bv=float(b['median_ms']);cv=float(c['median_ms']);delta=cv-bv;ratio=cv/bv;flag=delta>1 and ratio>1.1
 for field,value in [('baseline_ms',bv),('candidate_ms',cv),('delta_ms',delta),('ratio',ratio)]:close(x[field],value)
 assert x['flag']==flag;comparisons.append(x)
assert len(comparisons)==24 and sum(x['flag'] for x in comparisons)==9
assert all(x['rows']==1000000 and x['operation'] in ['public_table','public_column','native_elt'] for x in comparisons if x['flag'])
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='six_control_runs_evidence_clear',reviewer_script=ident(__file__),runs=runs,distinct_inputs_rehashed=len(all_inputs),exact_common_nonpackage_inputs=len(common),raw_series=48,raw_samples=336,state_facts=192,comparisons=comparisons,root_assessment=ident(root/'read-control-v3-root-assessment-01.json'),saved_reader=[ident(review/x) for x in ['read-control-raw-record-reader-01.R','read-control-raw-record-reader-01.log','read-control-raw-series-01.csv','read-control-raw-samples-01.csv','read-control-state-facts-01.csv']],assessment=[
'All six original successful receipts, sixteen products per run, complete input inventories and namespace/DLL bindings independently rechecked. The same accepted v5 diagnostic build and exact corrected R/runtime sources were consumed. All common runtime/helper/driver/build identities match after excluding only each recorded installed dtatools directory.',
'Independent saved-RDS-only reader recalculates all 48 medians from 336 positive raw seconds samples, multiplied by 1000, and checks retained GC/allocation summaries. Every series has seven iterations, zero GC and zero bench allocation. Separate R-profile and native-copy counters are zero; baseline validation scan availability is NA, while candidate scan counts are zero.',
'All 192 saved state facts preserve backing and handle within each one-column fixture across the four operations/phases. Candidate remains unexposed owned depth one, baseline ordinary depth zero; both report shared handles and nonprivate backing. Bytes are exactly eight times rows. Executed source checks preserve values and metadata; full measured value objects are not saved.',
'All 24 paired arithmetic rows and strict greater-than10-percent AND greater-than1-ms flags recalculate. Each pair has three 1M flags: public table, pre-extracted public column and native STRING_ELT. Native pointer has no flag at either size. None of the 100k comparisons crosses the absolute threshold.',
'Pre-extracted public anyNA retains the between-source cost, and matched public-API read-only pointer loops have near-equal times. This narrows the declared-character anyNA investigation toward its element-access path and away from table lookup as a sufficient explanation. It does not measure isolated getter latency or identify an exclusive cause. The native STRING_ELT loop has different absolute cost and is not the base R internal loop.',
'The C visit counter is a separate untimed check of its own loop, not instrumentation of base R. Setup/correctness/profiling/GC/state reads remain outside timed operations. Raw Rprofmem events and per-timed-call native counters were not retained; their scope is distinct from raw bench samples.',
'The original fixture failure and its correction remain separate reviewed evidence. These six runs cover only declared-character anyNA, not all twelve retained base-R flags, and do not establish irreducibility or overall performance/Stage5 acceptance.'
],limits='Retained records/source identity and saved-RDS audit only. No constructor, C/native control, profiling or benchmark rerun. Original measured state and inputs were not changed.')
with (review/'read-control-v3-evidence-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],runs=6,series=48,samples=336,states=192,flags=9,distinct_inputs=len(all_inputs),common_inputs=len(common),report=ident(review/'read-control-v3-evidence-review-01.json'))))
