from pathlib import Path
from datetime import datetime, timezone
import csv, hashlib, json, math

root=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance')
review=Path(__file__).parent
source='622ffc194372d9882a78637077dff42f657b14a3'
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
def match(row):
 now=ident(row['path']);assert {k:now[k] for k in row}==row,row['path']
def audit(name,is_audit=False):
 folder=root/name;receipt=root/(name+'-receipt.json')
 r=json.loads(receipt.read_text());m=json.loads((folder/'manifest.json').read_text())
 b=json.loads((folder/('inputs.json' if is_audit else 'inputs-before.json')).read_text())
 e=json.loads((folder/('result.json' if is_audit else 'execution-result.json')).read_text())
 assert r['accepted'] and e['returncode']==0 and not e['changed_inputs'] and e.get('error',e.get('integrity_error')) is None
 match(r['manifest'])
 for row in m['products']:match(row)
 assert {x['path'] for x in m['products']}|{str(folder/'manifest.json')}=={str(p) for p in folder.iterdir()}
 for row in b['inputs']:match(row)
 if not is_audit:
  assert e['namespace_coverage']
  bound={x['resolved'] for x in b['inputs']}
  for row in csv.DictReader((folder/'namespaces.tsv').open(),delimiter='\t'):
   assert str((Path(row['path'])/'DESCRIPTION').resolve(strict=True)) in bound
 return dict(name=name,receipt=ident(receipt),manifest=ident(folder/'manifest.json'),products=len(m['products']),bytes=sum(x['bytes'] for x in m['products']),input_bindings=len(b['inputs'])),b
def common(name,b):
 package=[r['path'] for r in csv.DictReader((root/name/'namespaces.tsv').open(),delimiter='\t') if r['name']=='dtatools'];assert len(package)==1
 return {r['path']:r for r in b['inputs'] if not r['path'].startswith(package[0]+'/')}
runs={
 'candidate-622-wide-minimum-01':('candidate-622-wide-minimum-audit-01','candidate-wide-minimum-01','68923e47764244cf36b29b33ab6e661f1fed496820b88c43547683c1a48722bc'),
 'candidate-622-width-repeat-01':('candidate-622-width-repeat-audit-01','candidate-width-repeat-01','055be9f85789865adde411e6ca55fad223b917183a12fc8c7cf4d80f1b89e07e'),
 'candidate-622-wide-profile-01':(None,'candidate-wide-profile-01','91ad73192126eb9f5df612b3a5da34db1b88b3275401ee1c43a010bbfbd5d3d1')}
expected_audits={'candidate-622-wide-minimum-audit-01':'0b28e0d912d203e891d1c19bb3e1e17c4f3891ceccdb51e71ed193943591d59b','candidate-622-width-repeat-audit-01':'311c6ddeb36190681ee1fe3ec5f357c6212b7444eab88cabb387cc6fb9f99db7'}
records=[];audits=[];states_total=0;observations=[]
for name,(audit_name,old_name,receipt_sha) in runs.items():
 record,b=audit(name);records.append(record);assert record['receipt']['sha256']==receipt_sha
 assert b['source']==source
 folder=root/name;profile='profile' in name;repeat='repeat' in name
 old=json.loads((root/old_name/'inputs-before.json').read_text())
 assert b['command']==old['command'] and common(name,b)==common(old_name,old)
 grid=list(csv.DictReader((folder/'grid.csv').open()));assert len(grid)==(6 if repeat else 1)
 assert {(g['columns'],g['operation']) for g in grid}==({(p,o) for p in ['2','16','64'] for o in ['retain','dependent']} if repeat else {('64','retain')})
 assert all(g['kind']=='ungrouped' and g['groups']=='1' and g['rows']==('100000' if repeat else '12') for g in grid)
 rows=list(csv.DictReader((folder/'source-states.csv').open()));states_total+=len(rows)
 if profile:
  assert b['profile_enabled'] and b['profile_calls_per_mode']==2000 and b['requested_interval_seconds']==0.001
  phases=['before_checks','before_profile','after_profile','after_checks']
  expected={(m,p,c) for m in ['safe_reference','direct'] for p in phases for c in ['x','s',*[f'p{i}' for i in range(3,65)]]}
  assert len(rows)==len(expected)==512 and {(r['mode'],r['phase'],r['column']) for r in rows}==expected
  grouping=lambda r:(r['mode'],r['column']);size=lambda r:12
 else:
  keys=['rows','columns','groups','kind','operation'];key=lambda r:tuple(r[k] for k in keys)
  phases=['before_oracle','before_profile','before_timing','after_timing']
  expected={(*key(g),m,p,c) for g in grid for m in ['safe_reference','direct'] for p in phases for c in ['x','s',*[f'p{i}' for i in range(3,int(g['columns'])+1)]]}
  assert len(rows)==len(expected) and {(*key(r),r['mode'],r['phase'],r['column']) for r in rows}==expected
  grouping=lambda r:(*key(r),r['mode'],r['column']);size=lambda r:int(r['rows'])
  measurements=list(csv.DictReader((folder/'measurements.csv').open()));assert len(measurements)==2*len(grid)
  assert {(*key(r),r['mode']) for r in measurements}=={(*key(g),m) for g in grid for m in ['safe_reference','direct']}
  for r in measurements:
   assert int(r['actual_input_columns'])==int(r['columns']) and int(r['iterations'])==7 and int(r['gc_count'])>=0
   for k,v in r.items():
    if k.endswith('_bytes') or k=='median_ms':assert math.isfinite(float(v)) and float(v)>=0
  ar,ab=audit(audit_name,True);audits.append(ar);assert ar['receipt']['sha256']==expected_audits[audit_name]
  bound={r['path']:r for r in ab['inputs']}
  for p in [folder/'manifest.json',root/(name+'-receipt.json')]:assert bound[str(p)]==ident(p)
  for operation in ['retain','dependent'] if repeat else ['retain']:
   select=lambda r:r['columns']=='64' and r['operation']==operation
   a=float(next(r['median_ms'] for r in measurements if select(r) and r['mode']=='safe_reference'))
   z=float(next(r['median_ms'] for r in measurements if select(r) and r['mode']=='direct'))
   observations.append(dict(run=name,columns=64,operation=operation,safe_reference_ms=a,direct_ms=z,delta_ms=z-a,ratio=z/a,diagnose=z-a>1 and z/a>1.1))
 backings={}
 for r in rows:
  assert r['owned']=='TRUE' and r['depth']=='1' and r['exposed']=='FALSE' and float(r['bytes'])==size(r)*8 and r['handle_shared']=='TRUE' and r['backing_private']=='FALSE'
  assert r['type']==('character' if r['column']=='s' else 'double')
  backings.setdefault(grouping(r),set()).add(r['backing'])
 assert all(len(x)==1 for x in backings.values())
assert states_total==2336
raw=list(csv.DictReader((review/'repair-guard-raw-recalculation-01.csv').open()));assert len(raw)==98 and len({(r['run'],r['case'],r['mode']) for r in raw})==14
profiles=list(csv.DictReader((review/'repair-guard-profile-recalculation-01.csv').open()));assert len(profiles)==2
assert 'PASS 14 raw timing series /98 samples' in (review/'repair-guard-retained-records-01.log').read_text()
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='repair_guard_retained_measurement_profile_evidence_clear',source=source,reviewer_script=ident(__file__),records=records,raw_audits=audits,totals=dict(timing_series=14,timing_samples=98,source_state_rows=states_total,profile_calls_per_mode=2000,profile_samples=profiles),raw_recalculation=dict(command=['/opt/homebrew/Cellar/r/4.6.1/bin/Rscript','--vanilla',str(review/'repair-guard-retained-records-01.R'),str(root),str(review)],exit_code=0,products=[ident(review/p) for p in ['repair-guard-retained-records-01.R','repair-guard-retained-records-01.log','repair-guard-raw-recalculation-01.csv','repair-guard-profile-recalculation-01.csv']]),same_candidate_64_column_observations=observations,assessment='All completed receipts, manifests, products and declared inputs match. Independent saved-RDS readers reproduce all 14 numeric millisecond medians from98 raw second samples and allocation/GC values. All2336 expected owned/unexposed state rows retain their backing. Both2000-call raw profiles exactly reproduce saved RDS and CSV summaries; source snapshots and four obsolete-mask checks pass. Common driver/corpus/runtime bindings and R commands exactly match corresponding57309 records after excluding only each recorded installed dtatools package directory.',limits=[
 'This clears retained evidence for the isolated repair guard diagnostic. It does not establish overall Stage5 performance acceptance or a combined native/mask-name implementation result.',
 'Only one new minimum and one width run are included. Same-source direct/safe-reference comparisons and historical-source comparisons answer different questions; neither is relabeled as paired full-matrix qualification.',
 'The64-column dependent case remains above both same-candidate diagnosis thresholds. Root owns further diagnosis and any new measurement.',
 'Rprof sampled stack counts and nominal interval totals include profiler/loop/GC effects, have overlapping cumulative frames and cannot by themselves identify a unique cause or independent wall-clock cost.',
 'Separate allocation summaries overlap. Temporary Rprofmem events were not retained; these are neither retained heap nor peak RSS measurements.',
 'No benchmark or profiled operation was rerun. The only R process read retained RDS/raw stacks and regenerated summaries.'
])
with (review/'repair-guard-measurement-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],runs=len(records),audits=len(audits),states=states_total,series=14,samples=98,profiles=profiles,observations=observations)))
