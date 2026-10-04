"""Prepare completed auxiliary evidence gates; does not publish artifacts."""
import hashlib,json
from pathlib import Path
E=Path(__file__).resolve().parent
ROOT=Path('<final_repository>')
RECORDER_ROOT=Path('<recorder_repository>')
PINS={'baseline':'213ceeee5a0f7953bf0f13316e2207a766dcbb24','rejected':'452ac7232ef6e47c398bcd22c7bb2800b55932c3','corrected':'19f573720b4897a4f742bad0cebba22ce17d9a88','integrated':'3eadb244253fb817d5773b01b11cb36c284f3a1d'}
G={k:[] for k in ('qualifications','structural','codegen','focused','historical_full_suite')};F=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads((E/p).read_text())
def spec(p,root='evidence'):return {'root':root,'path':p}
def bind(p,pointer,out=None,root='evidence'):return {'file':spec(p,root),'digest_pointer':pointer,'publish_as':out or p}
def gate(group,p,expect,bindings,out=None,collections=()):
 r=read(p);G[group].append(dict(receipt=spec(p),receipt_sha256=sha(E/p),expect=expect,bindings=bindings,publish_as=out or p,collections=list(collections)));return r

def collection(pointer,directory,prefix,values,omit=()):
 return dict(digest_pointer=pointer,root='evidence',directory=directory,publish_prefix=prefix,expected_names=sorted(values),omit={k:'Private executable/object/source or installed artifact; original digest retained, not published as text.' for k in omit})

def pointer_key(value):return value.replace('~','~0').replace('/','~1')
def root_children(g,values,pointer,prefix):
 g.setdefault('expected_key_sets',{})[pointer]=sorted(values)
 g['bindings'].extend(bind(name,pointer+'/'+pointer_key(name),prefix+'/'+name) for name in values)

def extra(p,out=None,root='evidence',scope='post-run-publication'):
 base={'evidence':E,'final_repository':ROOT,'recorder_repository':RECORDER_ROOT}[root]
 F.append(dict(file=spec(p,root),publish_as=out or p,sha256=sha(base/p),binding_scope=scope))
for folder,role in [('baseline-213ce','baseline'),('candidate-final-v1','rejected'),('candidate-fallback-v1','corrected'),('final-combined-build','integrated')]:
 p=folder+'/build-receipt.json';r=read(p);pre='builds/'+folder
 gate('qualifications',p,{'/base_commit':{'pin':role},'/exit_code':0,'/pre_post_source_equal':True,'/variant':'baseline'},[
  bind(folder+'/build.log','/build_log_sha256',pre+'/build.log'),bind(folder+'/input-record.json','/input_record_sha256',pre+'/input-record.json'),bind(folder+'/source.patch','/source_patch_sha256',pre+'/source.patch')],pre+'/build-receipt.json',[
  collection('/source_inventory',folder+'/source',pre+'/source',r['source_inventory'],r['source_inventory']),collection('/installed_inventory',folder+'/library/dtatools',pre+'/installed',r['installed_inventory'],r['installed_inventory'])])
for folder,role,blocks,passed in [('focused-final-v1','rejected',42,34602),('focused-fallback-v1','corrected',42,34602),('final-focused-v1','integrated',47,38954)]:
 p=folder+'/completion.json';r=read(p)
 gate('focused',p,{'/status':'PASS','/source_commit':{'pin':role},'/test_source_head':{'pin':role},'/before_after_equal':True,'/blocks':blocks,'/totals':{'failed':0,'passed':passed,'warning':0}},[bind(folder+'/focused.csv','/artifacts/focused.csv')],collections=[collection('/artifacts',folder,folder,r['artifacts'])])
 for phase in ('before','after'):
  q=folder+'/'+phase+'.json';rr=read(q)
  gate('focused',q,{'/test_source_head':{'pin':role},'/build/receipt/base_commit':{'pin':role},'/test_source_patch_sha256':hashlib.sha256(b'').hexdigest()},[
   bind('run-focused.py','/controllers/run-focused.py','focused-controllers/run-focused.py'),
   bind('focused.R','/controllers/focused.R','focused-controllers/focused.R'),
   bind('benchmarks/native-operations/run.py','/controllers/run.py','focused-controllers/dependencies/benchmarks/native-operations/run.py','recorder_repository')])
  G['focused'][-1]['expected_key_sets']={'/controllers':sorted(rr['controllers'])}
p='full-suite-summary.json';r=read(p)
gate('historical_full_suite',p,{'/status':'PASS','/source_commit':{'pin':'rejected'},'/assertions':106731,'/blocks':1823,'/failed':0,'/errors':0,'/skips':0,'/warnings':7},[])
root_children(G['historical_full_suite'][-1],r['artifacts'],'/artifacts','historical-full-suite')
for folder,role,fail in [('fallback-red-v2','rejected',14),('fallback-green-v1','corrected',0),('final-canonical-structural-v1','integrated',0),('final-unknown-structural-v1','integrated',0)]:
 p=folder+'/receipt.json';r=read(p)
 if folder.startswith('fallback-'):
  control='fallback-probe-v1/work-count.py';probe='fallback-probe-v1/work-count.c';root='evidence'
 else:
  sub='compact-float-domain' if 'canonical' in folder else 'long-float-addition';control='benchmarks/'+sub+'/work-count.py';probe='benchmarks/'+sub+'/work-count.c';root='final_repository'
 gate('structural',p,{'/commit':{'pin':role},'/cases':162,'/semantic_failures':0,'/work_failures':fail,'/exit_code':int(fail>0),'/require_proved':True,'/source_before_after_equal':True},[
  bind(control,'/controller_sha256','structural-controllers/'+control,root),bind(probe,'/probe_sha256','structural-controllers/'+probe,root)],collections=[collection('/artifact_sha256',folder,folder,r['artifact_sha256'],[k for k in r['artifact_sha256'] if k=='work-count'])])
# Failed controller draft is auxiliary diagnostic evidence, not a qualified run.
for name in ('compile.log','work-count.csv','work-count.log','launch-error.txt','controllers/work-count.py','controllers/work-count.c'):
 extra('fallback-red-v1/'+name)
for prefix,role,build,suffix in [('', 'rejected','candidate-final-v1',''),('fallback-','corrected','candidate-fallback-v1','-fallback')]:
 label='candidate-'+prefix+'codegen-binding.json';r=read(label);dump='candidate-'+prefix+'otool.txt';helper='bind-codegen'+suffix+'.py'
 gate('codegen',label,{'/status':'PASS','/commit':{'pin':role}},[
  bind(build+'/build-receipt.json','/build_receipt_sha256','builds/'+build+'/build-receipt.json'),bind(helper,'/controller_sha256'),
  bind('benchmarks/native-operations/run.py','/recorder_sha256','codegen-controllers/dependencies/benchmarks/native-operations/run.py','repository')])
 G['codegen'][-1]['omitted_bindings']=[
  dict(file=spec(build+'/library/dtatools/libs/dtatools.so'),digest_pointer='/dll_sha256',artifact='codegen-private/'+build+'/dtatools.so',reason='Installed native binary omitted from text-only publication; current bytes verified against the recorded extraction.'),
  dict(file=spec(dump),digest_pointer='/output_sha256',artifact='codegen-private/'+dump,reason='Full installed disassembly retained privately; current bytes verified against the recorded extraction.')]
 # Installed extraction is retained privately. Its digest remains in the gate;
 # include a concise source-bound excerpt only for the corrected candidate.
 remarks=('fallback-' if prefix else '')+'release-remarks-v1';rr=read(remarks+'/binding.json')
 gate('codegen',remarks+'/binding.json',{'/status':'PASS','/source_commit':{'pin':role}},[
  bind('compile-remarks'+suffix+'.py','/controller_sha256'),bind(build+'/build-receipt.json','/build_receipt_sha256','builds/'+build+'/build-receipt.json')],collections=[collection('/artifacts',remarks,remarks,rr['artifacts'],['numeric-payload-remarks.o'])])
 review='reader-'+prefix+'codegen-independent-review.json';rr=read(review)
 gate('codegen',review,{'/status':'PASS','/commit':{'pin':role},'/source_headers':10,'/consumed_sources':60,
  '/canonical_vectorized_lines':[121,123,127,129],'/unknown_fallback_vectorized_lines':[77,79,81,86,88,90]},[])
 root_children(G['codegen'][-1],rr['artifacts'],'/artifacts','codegen-review')
# Explicit record of intentionally private full disassembly and installed DLLs.
private=[]
for label in ('candidate-codegen-binding.json','candidate-fallback-codegen-binding.json'):
 r=read(label);private.append(dict(binding=label,installed_dll_sha256=r['dll_sha256'],full_disassembly_sha256=r['output_sha256'],scope='Original installed DLL and complete disassembly remain private; fresh extraction and independent replay are recorded by these bound receipts.'))
(E/'codegen-publication-omissions.json').write_text(json.dumps(private,indent=2)+'\n');extra('codegen-publication-omissions.json')
# Transitive recorder helpers are replay/publication dependencies. The focused
# controller itself recorded only the three direct controller identities above.
for name in ('benchmarks/r-file-readers/record-builds.py','benchmarks/io-optimization/record-builds.py','benchmarks/r-file-readers/build-snapshot.py'):
 extra(name,'focused-controllers/dependencies/'+name,'recorder_repository')
config={'ready':False,'pins':PINS,'roots':{'evidence':str(E),'final_repository':str(ROOT),'recorder_repository':str(RECORDER_ROOT)},'groups':G,'files':F}
(E/'publication-config-auxiliary.json').write_text(json.dumps(config,indent=2,sort_keys=True)+'\n')
print('Prepared auxiliary config; publication remains pending')
