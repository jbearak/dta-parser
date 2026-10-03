#!/usr/bin/env python3
"""Stage audited long/float evidence, preserving original hashes and observations."""
import ast,csv,hashlib,json,re,sys
from pathlib import Path
WORK=Path(__file__).resolve().parent
BASELINE=Path('<private-tmp>/dta-native-integration-final-evidence/combined-build')
REPO=Path('<private-tmp>/dta-long-float-addition')
BASE='7003eba901671797ee91fffc97f08e28a1f7f515'
PREVIOUS='387227cdb8a174feccb24e5f52745177c5af3f95'
FINAL='3de25ecca674a3ffed3618223a011f499383bd57'
INTEGRATION='958082e4e9eb3fd78be6a81f1e70b6fabca27d9f'
def need(c,m):
 if not c:raise RuntimeError(m)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
def encoded(x):return (json.dumps(x,indent=2,sort_keys=True)+'\n').encode()
def bound(p,digest):need(sha(p)==digest,'Changed bound artifact: '+str(p))
def artifact_checks(folder,record):
 for name,digest in record['artifacts'].items():
  path=Path(name);need(not path.is_absolute() and '..' not in path.parts,'Unsafe artifact path')
  bound(folder/path,digest)
def stage_checks(folder,qualification,candidate,audit_path,auditor,controller):
 complete=read(folder/'completion.json');qualified=read(qualification/'completion.json')
 for record,phase,count,rounds in ((complete,'measure',696,6),(qualified,'qualify',116,1)):
  need(record['phase']==phase and record['observations']==count and record['rounds']==rounds,'Incomplete matrix')
  need(record['exact_results'] is True and record['provenance_unchanged'] is True,'Failed stage gate')
 artifact_checks(folder,complete);artifact_checks(qualification,qualified)
 before=read(folder/'provenance-before.json')
 need(before==read(folder/'provenance-after.json')==read(qualification/'provenance-before.json')==read(qualification/'provenance-after.json'),'Changed stage identities')
 expected={'baseline':BASE,'candidate':candidate}
 need({role:before['builds'][role]['receipt']['base_commit'] for role in expected}==expected,'Wrong stage sources')
 assignments=[ast.literal_eval(node.value) for node in ast.parse((controller/'run.py').read_text()).body
  if isinstance(node,ast.Assign) and any(isinstance(target,ast.Name) and target.id=='COMMITS' for target in node.targets)]
 need(assignments==[expected],'Frozen controller source pins differ')
 for path in (folder/'protocol.json',qualification/'protocol.json'):
  protocol=read(path)
  # These historical protocols have no commit fields. Their exact hashes are
  # checked above through completion; source pins are checked independently
  # against both frozen controller literals and audited build receipts.
  need(protocol['cases_per_build_round']==58,'Wrong protocol case count')
 audit=read(audit_path)
 need(audit['status']=='PASS' and audit['observations']==696 and audit['summary_rows']==26 and audit['qualification_observations']==116 and audit['source_commits']==expected,'Wrong or failed independent audit')
 bound(folder/'completion.json',audit['timing_completion_sha256']);bound(qualification/'completion.json',audit['qualification_completion_sha256']);bound(auditor,audit['auditor_sha256'])
 for name,key in (('run.py','controller'),('core.py','validation'),('worker.R','worker'),('test-run.py','protocol_tests')):
  bound(controller/name,before['controllers'][key])
 with (folder/'raw.csv').open() as stream:need(sum(1 for _ in csv.DictReader(stream))==696,'Raw matrix count differs')
 return before

def privacy_tokens(files):
 values,digests=set(),set()
 def visit(value):
  if isinstance(value,dict):
   for key,item in value.items():
    if key in ('USER','LOGNAME') and isinstance(item,dict):
     identity=item.get('value');digest=item.get('sha256')
     if isinstance(identity,str) and identity and not identity.startswith('<'):values.add(identity)
     if isinstance(digest,str) and re.fullmatch('[0-9a-f]{64}',digest):digests.add(digest)
    visit(item)
  elif isinstance(value,list):
   for item in value:visit(item)
 for path in files:
  if path.suffix=='.json':visit(read(path))
 for value in values:digests.add(hashlib.sha256(value.encode()).hexdigest())
 return values,digests

def redact(data,values,digests):
 text=data.decode()
 for digest in digests:text=text.replace(digest,'<redacted-identity-sha256>')
 for value in sorted(values,key=len,reverse=True):
  text=re.sub(r'(?<![A-Za-z0-9_])'+re.escape(value)+r'(?![A-Za-z0-9_])','<redacted-identity>',text)
 text=re.sub(r'<user-home>/\s"\)\]]+','<user-home>',text)
 text=re.sub(r'<private-temp>"\)\]]+','<private-temp>',text)
 text=re.sub(r'<private-temp>"\)\]]+','<private-temp>',text)
 text=text.replace('<private-tmp>/','<private-tmp>/')
 text=re.sub(r'(?<![A-Za-z0-9_<>])<temporary>/','<temporary>/',text)
 need(not re.search(r'/(?:Users|private/tmp|private/var/folders|var/folders)/',text),'Private path survived')
 need(not any(d in text for d in digests),'Identity digest survived')
 return text.encode()

def main(output):
 need(not output.exists(),'Use a fresh staging destination')
 files={}
 def add(relative,path):
  p=Path(relative);need(not p.is_absolute() and '..' not in p.parts and relative not in files,'Invalid publication path')
  need(path.is_file() and not path.is_symlink(),'Missing or linked artifact: '+str(path));files[relative]=path
 builds={'baseline':BASELINE,'previous':WORK/'candidate-v1','final':WORK/'candidate-all-missing-v1','integration':WORK/'publication-build-v1'}
 for label,stage,qualification,candidate,audit_name,auditor_name,controller_name in (
  ('initial','screen-v1','qualification-v1',PREVIOUS,'screen-independent-audit.json','independent-audit.py','screen-controller'),
  ('final','screen-all-missing-v1','qualification-all-missing-v1',FINAL,'screen-all-missing-independent-audit.json','independent-all-missing-audit.py','screen-controller-all-missing')):
  folder=WORK/stage;qual=WORK/qualification;controller=WORK/controller_name
  stage_checks(folder,qual,candidate,WORK/audit_name,WORK/auditor_name,controller)
  for source,destination in ((folder,label),(qual,label+'-qualification')):
   for path in sorted(source.iterdir()):
    if path.suffix in ('.csv','.json','.patch'):add(destination+'/'+path.name,path)
  for name in ('run.py','core.py','worker.R','test-run.py'):add('controllers/'+label+'/'+name,controller/name)
  add('audits/'+label+'.json',WORK/audit_name);add('audits/'+label+'.py',WORK/auditor_name)
 for role,build in builds.items():
  receipt=read(build/'build-receipt.json')
  expected={'baseline':BASE,'previous':PREVIOUS,'final':FINAL,'integration':INTEGRATION}[role]
  need(receipt['base_commit']==expected and receipt['exit_code']==0 and receipt['pre_post_source_equal'] is True,'Wrong build receipt')
  need((build/'source.patch').read_bytes()==b'','Patched build source')
  for folder,key in ((build/'source','source_inventory'),(build/'library/dtatools','installed_inventory')):
   actual={p.relative_to(folder).as_posix():sha(p) for p in folder.rglob('*') if p.is_file()}
   need(actual==receipt[key],'Build inventory changed: '+role)
  for name in ('build-receipt.json','input-record.json','source.patch'):add('builds/'+role+'/'+name,build/name)
 integration=WORK/'publication-integration-v1';qualified=read(integration/'integration-binding.json')
 need(qualified['status']=='PASS' and qualified['integration_commit']==INTEGRATION and qualified['measured_commit']==FINAL,'Combined qualification failed')
 bound(integration/'bind-integration.py',qualified['binder_sha256'])
 for name,digest in qualified['input_sha256'].items():bound(Path(name),digest)
 decision=read(WORK/'final-decision.json')
 need(decision['status']=='ACCEPTED' and decision['candidate_commit']==FINAL and decision['integration_commit']==INTEGRATION,'Final decision missing or for wrong sources')
 for stage,commit,code,failures in (('all-missing-red-v1',PREVIOUS,1,58),('all-missing-green-v2','254edb0770d04777870f920034f97798d8ec1e92',0,0),('publication-structural-v1',INTEGRATION,0,0)):
  folder=WORK/stage;receipt=read(folder/'receipt.json')
  need(receipt['commit']==commit and receipt['exit_code']==code and receipt['cases']==162 and receipt['semantic_failures']==0 and receipt['work_failures']==failures and receipt['require_proved'] is True and receipt['source_before_after_equal'] is True,'Structural gate differs')
  for name,digest in receipt['artifact_sha256'].items():bound(folder/name,digest)
  controller=REPO/'benchmarks/long-float-addition' if stage=='publication-structural-v1' else WORK/'all-missing-probe'
  for name,key in (('work-count.py','controller_sha256'),('work-count.c','probe_sha256')):
   bound(controller/name,receipt[key]);add('structural/'+stage+'/controllers/'+name,controller/name)
  for path in sorted(folder.iterdir()):
   if path.suffix in ('.json','.csv','.log','.h'):add('structural/'+stage+'/'+path.name,path)
 for label in ('baseline-focused-v1','candidate-focused-v1','all-missing-baseline-focused-v1','all-missing-candidate-focused-v1','publication-focused-v1'):
  folder=WORK/label
  # Focused stages bind distinct installed runtime and external test source.
  complete=read(folder/'completion.json');need(complete['status']=='PASS','Focused gate failed')
  artifact_checks(folder,complete)
  for path in sorted(folder.iterdir()):
   if path.suffix in ('.json','.csv','.patch'):add('focused/'+label+'/'+path.name,path)
 full=WORK/'candidate-full-v1';complete=read(full/'completion.json')
 need(complete['status']=='PASS' and complete['source_commit']==PREVIOUS and complete['manifest_complete'] is True and complete['blocks']==1812 and complete['totals']=={'passed':104302,'failed':0,'warning':7},'Previous full-suite gate differs')
 artifact_checks(full,complete)
 for path in sorted(full.iterdir()):
  if path.suffix in ('.json','.csv'):add('previous-full-suite/'+path.name,path)
 for path in sorted(integration.iterdir()):
  if path.is_file() and path.suffix in ('.json','.py','.R','.sh','.log'):add('integration/'+path.name,path)
 routs=[Path(name) for name in qualified['input_sha256'] if name.endswith('/testthat.Rout')]
 need(len(routs)==1,'Archive suite transcript is ambiguous')
 add('integration/archive-testthat.Rout',routs[0])
 comparison=read(WORK/'exact-loop-comparison.json')
 need(comparison['status']=='PASS' and comparison['equal_instruction_count']==1260,'Exact fallback codegen comparison failed')
 bound(WORK/'compare-exact-codegen.py',comparison['controller_sha256'])
 for role,build,binding_file,dump_file,commit in (
  ('previous',builds['previous'],'candidate-codegen-binding.json','candidate-otool.txt',PREVIOUS),
  ('final',builds['final'],'all-missing-candidate-codegen-binding.json','all-missing-candidate-otool.txt',FINAL)):
  record=read(WORK/binding_file);item=comparison['inputs'][role]
  need(record['commit']==commit and item['commit']==commit,'Wrong codegen sources')
  bound(WORK/binding_file,item['binding_sha256']);bound(WORK/dump_file,item['dump_sha256'])
  bound(build/'library/dtatools/libs/dtatools.so',record['dll_sha256'])
  bound(build/'build-receipt.json',record['build_receipt_sha256'])
 for name in ('final-decision.json','screen-coordination.md','codegen-findings.md','candidate-codegen-binding.json','all-missing-candidate-codegen-binding.json','all-missing-fill-codegen.json','all-missing-fill-excerpt.txt','compare-exact-codegen.py','exact-loop-comparison.json','previous-exact-loop.txt','final-exact-loop.txt','all-missing-design.md'):
  add('validation/'+name,WORK/name)
 # Preserve the rejected launch without representing it as an executed probe.
 add('structural/green-v1-launch-error.txt',WORK/'all-missing-green-v1/launch-error.txt')
 add('publish.py',Path(__file__))
 values,digests=privacy_tokens(files.values());pending={};mapping=[]
 for name,path in sorted(files.items()):
  original=path.read_bytes();public=redact(original,values,digests);pending[name]=public
  mapping.append(dict(artifact=name,source_sha256=hashlib.sha256(original).hexdigest(),published_sha256=hashlib.sha256(public).hexdigest(),transformation='none' if original==public else 'private paths and direct identity values/digests'))
 pending['publication-source-map.json']=encoded(mapping)
 pending['publication-manifest.json']=encoded({name:hashlib.sha256(data).hexdigest() for name,data in sorted(pending.items())})
 output.mkdir(parents=True)
 for name,data in pending.items():
  path=output/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
 print('Published',len(pending),'artifacts; original evidence unchanged')
if __name__=='__main__':main(Path(sys.argv[1]).resolve())
