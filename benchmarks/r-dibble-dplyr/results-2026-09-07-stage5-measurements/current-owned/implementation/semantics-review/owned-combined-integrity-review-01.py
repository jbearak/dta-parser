from pathlib import Path
from datetime import datetime,timezone
import json,hashlib,subprocess
root=Path('/private/tmp/dta-direct-stage5-validation/root-stage5-owned-performance-a2d8b6a');validation=root.parent;review=Path(__file__).parent;repo=Path('/private/tmp/dta-direct-stage4');source='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9';baseline='f622f1ddba04b2bb7ac07415faccf2b417aab0e6'
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
def inventory(p):return {str(x) for x in p.rglob('*') if x.is_file() or x.is_symlink()}
rid=ident(root/'completed-receipt.json');assert rid['sha256']=='dcfe9a472ca789f22cf2b526a72e41da1452c1ae9b639a74773f371a55650ad3'
r=json.loads((root/'completed-receipt.json').read_text());m=json.loads((root/'output-manifest.json').read_text());b=json.loads((root/'input-identities.json').read_text());e=json.loads((root/'execution-result.json').read_text())
assert r['status']==e['status']=='complete' and not r['changed_inputs'] and not e['changed_inputs'] and e['failure'] is None
for j in [r,b,e]:assert j['baseline_source']==baseline and j['candidate_source']==j['runner_source']==source
assert r['manifest']==ident(root/'output-manifest.json')
for x in m['products']:assert ident(x['path'])==x,x['path']
assert {x['path'] for x in m['products']}==inventory(root)-{str(root/'output-manifest.json'),str(root/'completed-receipt.json')}
for x in b['inputs']:assert ident(x['path'])==x,x['path']
for p,paths in b['inventories'].items():assert set(paths)==inventory(Path(p)),p
expected_commands=[f'{family}-{label}-{phase}' for family in ['atomic','double'] for phase in ['operations','memory'] for label in ['baseline','candidate']]+['heap-baseline','heap-candidate','compare-atomic','compare-double','compare-heap']
assert [x['name'] for x in e['commands']]==expected_commands and all(x['exit_code']==0 for x in e['commands'])
releases=[];frozen=0
for x in e['commands']:
 assert x==json.loads((root/(x['name']+'-command.json')).read_text()) and x['log']==ident(x['log']['path'])
 products=json.loads((root/(x['name']+'-products.json')).read_text())['products']
 for row in products:
  current=ident(row['path'])
  if x['name'].endswith('-operations') and Path(row['path']).name=='root-manifest.json':
   assert current!=row;releases.append(dict(phase=x['name'],before=row,final=current))
  else:assert current==row,row['path'];frozen+=1
assert len(releases)==4
c=json.loads((root/'comparison-inputs.json').read_text())
for row in c['inputs']:assert ident(row['path'])==row
for p,paths in c['inventories'].items():assert inventory(Path(p))==set(paths)
# Every helper used by child commands equals the exact a2 Git blob.
helpers=['helpers.R','owned-double-helpers.R','owned-atomic-helpers.R','owned-double.R','owned-double-memory.R','owned-atomic.R','owned-atomic-memory.R','owned-heap.R','run-owned-qualification.py','run-atomic-qualification.py','run-heap-qualification.py']
for name in helpers:
 rel='benchmarks/r-dibble-dplyr/'+name;assert (repo/rel).read_bytes()==subprocess.check_output(['git','show',source+':'+rel],cwd=repo)
for family in ['atomic','double','heap']:
 for label in ['baseline','candidate']:
  folder=root/(family+'-'+label);j=json.loads((folder/'root-manifest.json').read_text());assert j['source_sha']==(source if label=='candidate' else baseline) and j['runner_source_sha']==source and j['mode']==label
  for name,h in j['runner_sha256'].items():
   p=repo/name if '/' in name else repo/'benchmarks/r-dibble-dplyr'/name
   assert ident(p)['sha256']==h
assert ident(validation/'run-stage5-owned-performance-v3.py')['sha256']=='f62c2544ebfd3414aa748dcbad97c3b7eb26a0c41b78e22958e841053be637f4'
assert ident(validation/'compare-heap-stage5-v3.py')['sha256']=='603ddca3f3c20bf90d1bda791d257752e733df9c2570aacdfbf99c6e2a9c50a6'
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='owned_combined_outer_integrity_clear_outcome_audit_pending',reviewer_script=ident(__file__),receipt=rid,manifest=ident(root/'output-manifest.json'),products=len(m['products']),inputs=len(b['inputs']),input_inventories=len(b['inventories']),comparison_inputs=len(c['inputs']),completed_commands={x['name']:x['exit_code'] for x in e['commands']},frozen_phase_records_checked=frozen,deliberate_manifest_extensions=releases,assessment='All13 commands returned0 with no changed inputs. Every current completed product and declared original/consumed input identity was independently rehashed, exact input/product inventories match, all11 child source files equal a2 Git blobs, and baseline/candidate installed source/mode/runner records match. Four operations-phase child root manifests were deliberately extended by memory phases; their original identity records are retained, all other operation products still match, and final memory/heap/comparison products are frozen and unchanged.',limits=['Integrity clearance only; detailed matrix, budget, raw memory derivation and historical comparison outcome audits remain pending. No overall acceptance.','The four earlier manifest bodies are not separately retained; their original hash/size/mode identities and the reviewed pre-extension guard establish the recorded transition. They are not misreported as matching current extended bodies.','Outer coordinator binds full visible R/site/both package trees plus selected executables; full Python/OS dynamic-library closures are not frozen.','No child command, measurement, allocation profiler or test rerun by reviewer.'])
with (review/'owned-combined-integrity-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],products=result['products'],inputs=result['inputs'],commands=13,manifest_extensions=4)))
