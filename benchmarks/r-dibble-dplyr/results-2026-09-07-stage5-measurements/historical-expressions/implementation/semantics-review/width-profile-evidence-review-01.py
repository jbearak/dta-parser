import collections,csv,hashlib,json,math
from datetime import datetime,timezone
from pathlib import Path
root=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance');review=Path('/private/tmp/dta-direct-stage5-validation/implementation/semantics-review')
def ident(p):
 target=p.resolve(strict=True);s=target.stat();h=hashlib.sha256()
 with target.open('rb') as f:
  for block in iter(lambda:f.read(8*1024*1024),b''):h.update(block)
 return dict(path=str(p),resolved=str(target),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
def match(row):
 actual=ident(Path(row['path']));assert {k:actual[k] for k in row}==row,row['path']
def audit(name,auditor=False):
 folder=root/name;receipt=root/(name+'-receipt.json');r=json.loads(receipt.read_text());m=json.loads((folder/'manifest.json').read_text());b=json.loads((folder/('inputs.json' if auditor else 'inputs-before.json')).read_text());e=json.loads((folder/('result.json' if auditor else 'execution-result.json')).read_text())
 assert r['accepted'] and e['returncode']==0 and not e['changed_inputs']
 assert e.get('error',e.get('integrity_error')) is None
 match(r['manifest'])
 for row in m['products']:match(row)
 assert {x['path'] for x in m['products']}|{str(folder/'manifest.json')}=={str(p) for p in folder.iterdir()}
 for row in b['inputs']:match(row)
 if not auditor:
  assert e['namespace_coverage']
  bound={x['resolved'] for x in b['inputs']}
  for row in csv.DictReader((folder/'namespaces.tsv').open(),delimiter='\t'):assert str((Path(row['path'])/'DESCRIPTION').resolve(strict=True)) in bound
 return dict(name=name,receipt=ident(receipt),manifest=ident(folder/'manifest.json'),products=len(m['products']),bytes=sum(x['bytes'] for x in m['products']),input_bindings=len(b['inputs'])),b
runs=[f'{mode}-width-repeat-{i:02d}' for i in range(1,4) for mode in ['baseline','candidate']]+['baseline-wide-minimum-01','candidate-wide-minimum-01','candidate-wide-profile-01']
records=[];audits=[];states_total=0;common_by_family={};measurements={}
source={'baseline':'f622f1ddba04b2bb7ac07415faccf2b417aab0e6','candidate':'57309d40433a92d99849fefa155ae7b22b86b337'}
for name in runs:
 record,b=audit(name);records.append(record);folder=root/name
 mode=name.split('-')[0];assert b['source']==source[mode]
 family='profile' if 'profile' in name else 'minimum' if 'minimum' in name else 'repeat'
 package=[row['path'] for row in csv.DictReader((folder/'namespaces.tsv').open(),delimiter='\t') if row['name']=='dtatools'];assert len(package)==1
 common={r['path']:r for r in b['inputs'] if not r['path'].startswith(package[0]+'/')}
 if family in common_by_family:assert common_by_family[family]==common
 else:common_by_family[family]=common
 grid=list(csv.DictReader((folder/'grid.csv').open()));count=6 if family=='repeat' else 1;assert len(grid)==count
 expected_cases={(p,o) for p in ['2','16','64'] for o in ['retain','dependent']} if family=='repeat' else {('64','retain')}
 assert {(g['columns'],g['operation']) for g in grid}==expected_cases
 assert all(g['kind']=='ungrouped' and g['groups']=='1' and g['rows']==('100000' if family=='repeat' else '12') for g in grid)
 rows=list(csv.DictReader((folder/'source-states.csv').open()));states_total+=len(rows)
 if family=='profile':
  phases=['before_checks','before_profile','after_profile','after_checks'];expected={(m,p,c) for m in ['safe_reference','direct'] for p in phases for c in ['x','s',*[f'p{i}' for i in range(3,65)]]}
  assert {(r['mode'],r['phase'],r['column']) for r in rows}==expected and len(rows)==512
  grouping=lambda r:(r['mode'],r['column']);row_n=lambda r:12
  assert b['profile_enabled'] and b['profile_calls_per_mode']==2000
  assert ident(root/(name+'-receipt.json'))['sha256']=='c9b838b49c66f8bde1cce9a77080b0ad4d776f6b4d8b25daa549793f61855455'
  prep=json.loads((root/'candidate-wide-profile-prepare-01/inputs-before.json').read_text());assert b['inputs']==prep['inputs'] and b['command']==prep['command']
 else:
  phases=['before_oracle','before_profile','before_timing','after_timing'];keys=['rows','columns','groups','kind','operation'];key=lambda r:tuple(r[k] for k in keys)
  expected={(*key(g),m,p,c) for g in grid for m in ['safe_reference','direct'] for p in phases for c in ['x','s',*[f'p{i}' for i in range(3,int(g['columns'])+1)]]}
  assert len(rows)==len(expected) and {(*key(r),r['mode'],r['phase'],r['column']) for r in rows}==expected
  grouping=lambda r:(*key(r),r['mode'],r['column']);row_n=lambda r:int(r['rows'])
  values=list(csv.DictReader((folder/'measurements.csv').open()));assert len(values)==count*2
  assert {(*key(r),r['mode']) for r in values}=={(*key(g),m) for g in grid for m in ['safe_reference','direct']}
  for r in values:
   assert int(r['actual_input_columns'])==int(r['columns']) and int(r['iterations'])==7 and int(r['gc_count'])>=0
   for k,v in r.items():
    if k.endswith('_bytes') or k=='median_ms':assert math.isfinite(float(v)) and float(v)>=0
  measurements[name]=values
  ar,ab=audit(name+'-audit',True);audits.append(ar)
  audit_bindings={r['path']:r for r in ab['inputs']}
  for p in [folder/'manifest.json',root/(name+'-receipt.json')]:assert audit_bindings[str(p)]==ident(p)
 backings={}
 for r in rows:
  assert r['owned']=='TRUE' and r['depth']=='1' and r['exposed']=='FALSE' and float(r['bytes'])==row_n(r)*8 and r['handle_shared']=='TRUE' and r['backing_private']=='FALSE'
  assert r['type']==('character' if r['column']=='s' else 'double')
  backings.setdefault(grouping(r),set()).add(r['backing'])
 assert all(len(b)==1 for b in backings.values())
assert states_total==9408
co=root/'width-repeats-01';plan=json.loads((co/'plan.json').read_text());result=json.loads((co/'result.json').read_text());receipt=json.loads((co/'receipt.json').read_text())
assert result['complete'] and result['failure'] is None and not result['changed_inputs'] and len(result['commands'])==6
assert [r['command'] for r in result['commands']]==plan['commands'] and all(r['returncode']==0 for r in result['commands'])
assert [r['command'][4] for r in result['commands']]==runs[:6]
assert plan['environment_overrides']=={'DTA_EXPRESSION_ITERATIONS':'7'}
for row in plan['inputs']:match(row)
for row in receipt.values():match(row)
raw=list(csv.DictReader((review/'width-minimum-raw-recalculation-01.csv').open()));assert len(raw)==532
assert len({(r['run'],r['case'],r['mode']) for r in raw})==76
profiles=list(csv.DictReader((review/'profile-summary-recalculation-01.csv').open()));assert len(profiles)==2
assert {r['mode']:int(r['samples']) for r in profiles}=={'safe_reference':395,'direct':2809}
root_audits=json.loads((root/'width-repeat-audits-01.json').read_text())
for row in root_audits['audits']:assert ident(root/(row['run']+'-audit-receipt.json'))['sha256']==row['audit_receipt_sha256']
flags=[]
for i in range(1,4):
 base=measurements[f'baseline-width-repeat-{i:02d}'];candidate=measurements[f'candidate-width-repeat-{i:02d}']
 for operation in ['retain','dependent']:
  selector=lambda r:r['columns']=='64' and r['operation']==operation and r['mode']=='direct'
  before=float(next(r['median_ms'] for r in base if selector(r)));after=float(next(r['median_ms'] for r in candidate if selector(r)))
  flags.append(dict(repeat=i,operation=operation,baseline_ms=before,candidate_ms=after,delta_ms=after-before,ratio=after/before,diagnose=(after-before)>1 and after/before>1.1))
d=dict(utc=datetime.now(timezone.utc).isoformat(),status='retained_repeat_minimum_profile_evidence_clear',records=records,raw_audits=audits,coordinator=ident(co/'receipt.json'),totals=dict(repeat_runs=6,repeat_series=72,repeat_samples=504,minimum_runs=2,minimum_series=4,minimum_samples=28,source_state_rows=9408,profile_calls_per_mode=2000,profile_samples=profiles),raw_recalculation=dict(command=['/opt/homebrew/Cellar/r/4.6.1/bin/Rscript','--vanilla',str(review/'width-profile-retained-records-01.R'),str(root),str(review)],exit_code=0,products=[ident(review/p) for p in ['width-profile-retained-records-01.R','width-profile-retained-records-01.log','width-minimum-raw-recalculation-01.csv','profile-summary-recalculation-01.csv']]),observed_64_column_public_dispatch_flags=flags,scope='Independent retained-artifact/raw-sample/summary/state audit only. No measured or profiled operation rerun.',assessment='All run/audit receipts, inventories, outputs and declared input identities match. Every seven-sample second series yields the recorded plain millisecond median, allocation and GC fields. Full expected ownership-state matrices are present and stable. Profile raw text exactly reproduces saved RDS and by-self/by-total CSV summaries; both modes completed2000 calls with full source snapshot equality and obsolete-mask checks. Repeat pairs use exactly identical common preparation/runtime records excluding their source-specific installed package trees.',limits=['This clears the evidence for diagnosis, not overall Stage5 performance. The64-column observations remain subject to the separately documented diagnosis flags; no successful optimization is claimed.','Raw Rprof sample counts multiplied by the requested1ms interval are nominal sampling summaries, not independent wall-clock phase timings. Stack ancestry and cumulative totals overlap; native children can be charged to R parent frames. GC samples remain included.','Temporary Rprofmem event files are not retained; R/native allocation summaries remain separate and overlapping. They cannot be added or read as retained memory/peak RSS.','The minimized12-row run changes only observations within the same64-column retain constructor; it narrows the reproduction without identifying a cause.','The profile uses unchanged operations with profiler/loop overhead and retained validation snapshots. Setup, checks and source snapshots are outside its sampled loop. No namespace tracing or body changes occurred in the reviewed driver.','All records still belong to baselinef622 or candidate57309. Future source changes or native integration need distinct package identities and qualification.'])
with (review/'width-profile-evidence-review-01.json').open('x') as f:json.dump(d,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=d['status'],runs=len(records),audits=len(audits),states=states_total,series=76,samples=532,profile_samples=[r['samples'] for r in profiles],flags=flags)))
