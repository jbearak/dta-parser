from pathlib import Path
from datetime import datetime,timezone
import json,csv,hashlib,math,itertools,difflib
root=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance');review=Path(__file__).parent
sources={'baseline':'f622f1ddba04b2bb7ac07415faccf2b417aab0e6','candidate':'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'}
def identity(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
def lite(p):return {k:v for k,v in identity(p).items() if k in ['path','resolved','sha256']}
def readcsv(p):return list(csv.DictReader(p.open()))
def audit(name):
 folder=root/name;receipt=identity(root/(name+'-receipt.json'));r=json.loads(Path(receipt['path']).read_text());m=json.loads((folder/'manifest.json').read_text());assert r['accepted'] and r['manifest']==identity(folder/'manifest.json')
 for x in m['products']:assert identity(x['path'])==x
 assert {x['path'] for x in m['products']}|{str(folder/'manifest.json')}=={str(p) for p in folder.iterdir()}
 input_file=folder/('inputs-before.json' if (folder/'inputs-before.json').exists() else 'inputs.json');b=json.loads(input_file.read_text())
 for x in b['inputs']:assert identity(x['path'])==x
 assert len({x['path'] for x in b['inputs']})==len(b['inputs'])
 assert identity(Path(receipt['path']))==receipt
 return dict(name=name,receipt=receipt,products=len(m['products']),inputs=len(b['inputs'])),b
prep=json.loads((review/'pipeline-repeat-preparation-review-01.json').read_text())
for row in prep['sources']:assert identity(row['path'])==row
coordinator=root/'pipeline-repeats-a2d8b6a-01';plan=json.loads((coordinator/'plan.json').read_text());completed=json.loads((coordinator/'result.json').read_text());cr=json.loads((coordinator/'receipt.json').read_text())
assert cr['plan']==lite(coordinator/'plan.json') and cr['result']==lite(coordinator/'result.json')
assert completed['complete'] and completed['failure'] is None and not completed['changed_inputs'] and len(completed['commands'])==6
assert [x['command'] for x in completed['commands']]==plan['commands'] and all(x['returncode']==0 for x in completed['commands']) and plan['environment_overrides']=={'DTA_EXPRESSION_ITERATIONS':'7'}
for row in plan['inputs']:assert lite(row['path'])==row
assert {p.name for p in coordinator.iterdir()}=={'plan.json','result.json','receipt.json'}
common=None;runs=[];audits=[];all_states=0;values={};inv_records=[]
for repeat_id in range(1,4):
 for label in sources:
  name=f'{label}-pipeline-repeat-{repeat_id:02d}';folder=root/name
  record,b=audit(name);runs.append(record);audit_record,ab=audit(name+'-audit-01');audits.append(audit_record)
  e=json.loads((folder/'execution-result.json').read_text());ae=json.loads((root/(name+'-audit-01')/'result.json').read_text())
  assert e['returncode']==ae['returncode']==0 and e['integrity_error'] is None and ae['error'] is None and not e['changed_inputs'] and not ae['changed_inputs'] and e['namespace_coverage']
  assert b['source']==sources[label] and b['case_set']=='pipeline_repeat'
  ns=list(csv.DictReader((folder/'namespaces.tsv').open(),delimiter='\t'));packages=[x['path'] for x in ns if x['name']=='dtatools'];assert len(packages)==1;package=packages[0]
  bindings={x['path']:x for x in b['inputs']};resolved={x['resolved'] for x in b['inputs']}
  for row in ns:assert str((Path(row['path'])/'DESCRIPTION').resolve(strict=True)) in resolved
  for tree in [Path(package),Path('/opt/homebrew/Cellar/r/4.6.1/lib/R')]:assert {str(p) for p in tree.rglob('*') if p.is_file()}=={p for p in bindings if p.startswith(str(tree)+'/')}
  current={p:x for p,x in bindings.items() if not p.startswith(package+'/')}
  if common is None:common=current
  else:assert current==common
  grid=readcsv(folder/'grid.csv');rows=readcsv(folder/'measurements.csv');states=readcsv(folder/'source-states.csv')
  assert grid==[dict(rows='1000000',columns='16',groups='1',kind='ungrouped',operation='pipeline_five')]
  assert len(rows)==2 and {x['mode'] for x in rows}=={'safe_reference','direct'}
  for x in rows:
   assert x['actual_input_columns']=='16' and x['iterations']=='7' and int(x['gc_count'])>=0
   for k,v in x.items():
    if k.endswith('_bytes') or k=='median_ms':assert math.isfinite(float(v)) and float(v)>=0
   values[(repeat_id,label,x['mode'])]=x
  expected=set(itertools.product(['safe_reference','direct'],['before_oracle','before_profile','before_timing','after_timing'],['x','s']+[f'p{i}' for i in range(3,17)]))
  assert len(states)==128 and {(x['mode'],x['phase'],x['column']) for x in states}==expected
  backing={}
  for x in states:
   assert x['owned']=='TRUE' and x['depth']=='1' and x['exposed']=='FALSE' and x['handle_shared']=='TRUE' and x['backing_private']=='FALSE' and float(x['bytes'])==8000000 and x['type']==('character' if x['column']=='s' else 'double')
   k=(x['mode'],x['column']);backing.setdefault(k,set()).add(x['backing'])
  assert all(len(s)==1 for s in backing.values());all_states+=len(states)
  lines=(folder/'execution.log').read_text().splitlines();assert len(lines)==4 and sum(x.startswith('RUN ') for x in lines)==sum(x.startswith('MEASURED ') for x in lines)==2
  assert 'PASS 2 raw seven-sample medians, units, GC counts and allocation records' in (root/(name+'-audit-01')/'execution.log').read_text()
assert len(common)==3347
assessment_path=root/'pipeline-repeat-assessment-a2d8b6a-01.json';assessment=json.loads(assessment_path.read_text())
for row in assessment['input_bindings']:assert identity(row['path'])['sha256']==row['sha256']
assert len(assessment['records'])==6
pairs=[]
for x in assessment['records']:
 k=x['repeat'];mode=x['mode'];baseline=float(values[(k,'baseline',mode)]['median_ms']);candidate=float(values[(k,'candidate',mode)]['median_ms']);delta=candidate-baseline;ratio=candidate/baseline
 for key,value in [('baseline_ms',baseline),('candidate_ms',candidate),('delta_ms',delta),('ratio',ratio)]:assert math.isclose(x[key],value,rel_tol=1e-12,abs_tol=1e-12)
 assert x['flag']==(delta>1 and ratio>1.1)==False;pairs.append(x)
raw=readcsv(review/'pipeline-repeat-raw-records-01.csv');assert len(raw)==84 and len({(x['run'],x['mode']) for x in raw})==12
assert 'PASS six runs, 12 raw series, 84 samples' in (review/'pipeline-repeat-record-reader-01.log').read_text()
source_diffs={b:''.join(difflib.unified_diff((root/a).read_text().splitlines(True),(root/b).read_text().splitlines(True),fromfile=a,tofile=b)) for a,b in [('audit-width-repeat.py','audit-pipeline-repeat.py'),('audit-width-repeat.R','audit-pipeline-repeat.R')]}
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='pipeline_repeat_retained_evidence_clear',reviewer_script=identity(__file__),coordinator=[identity(coordinator/n) for n in ['plan.json','result.json','receipt.json']],runs=runs,audits=audits,source_diffs=source_diffs,audit_sources=[identity(root/n) for n in ['audit-pipeline-repeat.py','audit-pipeline-repeat.R']],reader=[identity(review/n) for n in ['pipeline-repeat-record-reader-01.R','pipeline-repeat-record-reader-01.log','pipeline-repeat-raw-records-01.csv']],series=12,samples=84,state_rows=all_states,exact_common_driver_runtime_python_inputs=len(common),assessment=identity(assessment_path),pairs=pairs,conclusion='All six unchanged single-case runs and six retained raw audits are complete, with every declared input/product rehashed, source/library and namespace bindings checked, expected two-mode grid and all 768 source states stable. Own read-only RDS calculation verifies every median in ms from seven raw seconds samples plus allocation and GC fields. Root audit deltas only narrow row counts/script names and add exact pipeline grid assertions. All six paired comparisons recalculate with no strict >10% plus >1ms flags. The original full-matrix safe-reference pipeline flag does not recur in any of three coordinated repeats.',limits=['This is bounded repeatability evidence for existing 1M-row 16-column ungrouped pipeline_five only. It does not establish a cause, confidence interval, cross-host result or overall Stage5 acceptance. Original full matrix including its flagged row is unchanged.','Same shared-source read/evaluate measurement setup, checks outside timing and safe-reference corpus limits remain. Raw bench samples/allocation summaries are retained; Rprofmem event logs and all timed result objects are not. Allocation fields overlap and are not RSS or retained memory.','Coordinator records its launcher and child command identities; each child independently binds runtime/corpus/package inputs. External OS/full Python closure remains excluded.','No benchmark, profiling, fixture construction or test workload rerun by reviewer. Only retained JSON/CSV/source/RDS files were read.'])
with (review/'pipeline-repeat-evidence-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],runs=6,audits=6,series=12,samples=84,states=all_states,paired_flags=0)))
