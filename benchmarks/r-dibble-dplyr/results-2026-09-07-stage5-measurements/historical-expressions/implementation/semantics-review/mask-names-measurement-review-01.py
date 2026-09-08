from pathlib import Path
from datetime import datetime, timezone
import csv, hashlib, json, math

root=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance')
review=Path(__file__).parent
source='ad976f7a6854be19db08549a3ef87373448fdfe9'
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
 'candidate-ad976-wide-minimum-01':('candidate-ad976-wide-minimum-audit-01','candidate-622-wide-minimum-01','802b57c94b13acbaa84d0f038600c01d6ee07d110639d57ac46c9e61c795e62c'),
 'candidate-ad976-width-repeat-01':('candidate-ad976-width-repeat-audit-01','candidate-622-width-repeat-01','e403eb940865265a36a3c76152336b937e983dfc1cebac1cae2bf9fde6adb1d4')}
expected_audits={'candidate-ad976-wide-minimum-audit-01':'1dd2b0a14bba1ec50017756ebc67d4706e696937517b626659b5ca387937bbf2','candidate-ad976-width-repeat-audit-01':'3d4f39117f0d1f3695fe55a976a7b61617ff6a0be5835fa85a46468c28bf820b'}
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
assert states_total==1824
raw=list(csv.DictReader((review/'mask-names-raw-recalculation-01.csv').open()));assert len(raw)==98 and len({(r['run'],r['case'],r['mode']) for r in raw})==14
assert 'PASS 14 raw timing series /98 samples' in (review/'mask-names-retained-records-01.log').read_text()
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='mask_names_retained_measurement_evidence_clear',source=source,reviewer_script=ident(__file__),records=records,raw_audits=audits,totals=dict(timing_series=14,timing_samples=98,source_state_rows=states_total),raw_recalculation=dict(command=['/opt/homebrew/Cellar/r/4.6.1/bin/Rscript','--vanilla',str(review/'mask-names-retained-records-01.R'),str(root),str(review)],exit_code=0,products=[ident(review/p) for p in ['mask-names-retained-records-01.R','mask-names-retained-records-01.log','mask-names-raw-recalculation-01.csv']]),same_candidate_64_column_observations=observations,assessment='Both completed measurement receipts and both raw audits bind unchanged inputs and exact products. Independent saved-RDS readers reproduce all14 numeric millisecond medians from98 raw second samples and allocation/GC fields. All1824 expected source-state rows remain owned, unexposed and backing-stable. Common driver/corpus/runtime identities and R commands match the corresponding622 records exactly after excluding only each recorded installed dtatools package directory.',limits=[
 'These are one minimum run and one six-case width run of ad976f7a, which includes the622 repair guard and the mask-name change. They are diagnostic evidence, not final combined-source or overallStage5 performance qualification.',
 'The64-column same-candidate comparisons do not exceed both diagnosis thresholds in these retained observations. This does not replace required repeated or full-matrix checks, and differs from comparing public dispatch across source revisions.',
 'R/native allocation fields have overlapping scopes and cannot be summed. Temporary Rprofmem events were not retained, and no retained-heap or peak-RSS interpretation is made.',
 'No profiling or benchmark operations were rerun. The only R process read saved raw timing RDS records.',
 'Native interrupt patch725 is not part of these measured package identities. OS/Homebrew/fullPython closure exclusions remain explicit.'
])
with (review/'mask-names-measurement-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],runs=len(records),audits=len(audits),states=states_total,series=14,samples=98,observations=observations)))
