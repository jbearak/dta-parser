#!/usr/bin/env python3
"""Publish audited polling artifacts, preserving original hashes before redaction."""
import hashlib,json,re,sys
from pathlib import Path
W=Path('<work>')
R=Path('<publication-repository>')
BASE=Path('<baseline-build>')
OUT=Path(sys.argv[1]).resolve()
def need(ok,message):
    if not ok:raise RuntimeError(message)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(name):return json.loads((W/name).read_text())
def bound(p,digest):need(sha(p)==digest,'Historical artifact changed: '+str(p))
def encoded(v):return (json.dumps(v,indent=2,sort_keys=True)+'\n').encode()
def redact(v):
    if isinstance(v,dict):
        for k,x in v.items():
            if k in ('USER','LOGNAME'):
                need(isinstance(x,dict) and set(x)=={'value','sha256'} and all(isinstance(y,str) for y in x.values()),'Unknown identity schema')
                x['value']=x['sha256']='<private>'
            else:redact(x)
    elif isinstance(v,list):
        for x in v:redact(x)
need(not OUT.exists(),'Publication destination exists')
audit=read('poll-v2-screen-independent-audit.json')
need(audit['status']=='PASS' and audit['observations']==696 and audit['qualification_observations']==116 and audit['summary_rows']==26,'Independent audit incomplete')
bound(W/'independent-poll-v2-audit.py',audit['auditor_sha256'])
for stage,count,rounds,phase,key in [('poll-screen-v2',696,6,'measure','timing_completion_sha256'),('poll-qualification-v2',116,1,'qualify','qualification_completion_sha256')]:
    bound(W/stage/'completion.json',audit[key]);complete=read(stage+'/completion.json')
    need(complete['observations']==count and complete['rounds']==rounds and complete['phase']==phase and complete['exact_results'] is True and complete['provenance_unchanged'] is True,'Matrix/semantic gate failed')
    for name,digest in complete['artifacts'].items():bound(W/stage/name,digest)
    before=read(stage+'/provenance-before.json');after=read(stage+'/provenance-after.json');need(before==after,'Provenance changed')
    need({k:v['receipt']['base_commit'] for k,v in before['builds'].items()}=={'baseline':'3de25ecca674a3ffed3618223a011f499383bd57','candidate':'e1b0278b1403b4d8fc2d9a2dfc0c4ddaa7cde3a2'},'Wrong measured commits')
    for filename,key in [('run.py','controller'),('worker.R','worker'),('core.py','validation'),('test-run.py','protocol_tests')]:bound(W/'poll-controller-v2'/filename,before['controllers'][key])
    for filename,key in [('native-operations/run.py','build_validation'),('r-file-readers/record-builds.py','build_recorder'),('io-optimization/record-builds.py','build_recorder_parent')]:bound(R/'benchmarks'/filename,before['controllers'][key])
    for role,build in [('baseline',BASE),('candidate',W/'poll-candidate-v2')]:
        b=before['builds'][role];bound(build/'build-receipt.json',b['receipt_sha256'])
        bound(build/'input-record.json',b['receipt']['input_record_sha256']);bound(build/'source.patch',b['receipt']['source_patch_sha256'])
for stage,commit,code,failures in [('poll-v2-baseline-red-final','3de25ecca674a3ffed3618223a011f499383bd57',1,14),('poll-v2-green-final','e1b0278b1403b4d8fc2d9a2dfc0c4ddaa7cde3a2',0,0)]:
    probe=read(stage+'/receipt.json')
    need(probe['commit']==commit and probe['exit_code']==code and probe['require_proved'] is True and probe['cases']==18 and probe['semantic_failures']==0 and probe['work_failures']==failures,'Wrong structural stage')
    for name,digest in probe['artifact_sha256'].items():bound(W/stage/name,digest)
    for filename,key in [('work-count.py','controller_sha256'),('work-count.c','probe_sha256'),('cadence.h','cadence_sha256')]:bound(W/'pair-probe-v2'/filename,probe[key])
v1=read('poll-green-final/receipt.json')
need(v1['commit']=='d02deee2bb063305e6056daa163c8e08691f6e7d' and v1['cases']==18 and v1['exit_code']==0 and v1['semantic_failures']==0,'Wrong intermediate structural source')
for name,digest in v1['artifact_sha256'].items():bound(W/'poll-green-final'/name,digest)
for filename,key in [('work-count.py','controller_sha256'),('work-count.c','probe_sha256')]:bound(W/'pair-probe'/filename,v1[key])
integration=read('publication-binding.json');need(integration['status']=='PASS' and integration['source_commit']=='58630e9914129b3f54197d7ac3207b75e8c10fe8' and integration['measured_writer_byte_identical'] is True,'Publication integration not bound')
for name,digest in integration['input_sha256'].items():bound(Path(name),digest)
archive=read('publication-conformance.json')
need(archive['source_commit']==integration['source_commit'] and all(archive[k] is True for k in ('checked_source_matches_clean_export','clean_export_matches_source_commit','exact_packaged_source_inventory','expected_hashes_from_committed_blobs','repository_environment_overrides_removed','required_conformance_passed')),'Archive validation failed')
bound(W/'publication-conformance.tar.gz',archive['source_archive_sha256'])
pending={};mapping=[]
def queue(p,name):
    original=p.read_bytes();text=original.decode()
    if p.suffix=='.json':
        v=json.loads(text);redact(v);text=encoded(v).decode()
    for old,new in [(str(W),'<work>'),(str(R),'<publication-repository>'),(str(BASE),'<baseline-build>'),(str(Path.home()),'<user>')]:text=text.replace(old,new)
    text=re.sub(r'/(?:private/)?tmp/([^/\s\"\'<>]+)',r'<private-work>/\1',text)
    text=re.sub(r'/(?:private/)?var/folders/[^\s\"\'<>]+','<temporary>',text)
    privacy_check=text.replace(r'/(?:Users|home|private/tmp|tmp)/','<privacy-pattern>') if p.resolve()==Path(__file__).resolve() else text
    need(not re.search(r'/(?:Users|home|private/tmp|tmp)/',privacy_check),'Unmapped private path: '+name)
    need(name not in pending,'Duplicate publication path')
    public=text.encode();pending[name]=public
    mapping.append(dict(artifact=name,source_sha256=hashlib.sha256(original).hexdigest(),published_sha256=hashlib.sha256(public).hexdigest(),transformation='none' if original==public else 'private paths/identity redaction or JSON formatting'))
for stage in ('poll-screen-v2','poll-qualification-v2'):
    for p in sorted((W/stage).iterdir()):
        if p.suffix in ('.csv','.json','.patch'):queue(p,stage+'/'+p.name)
for filename in ('run.py','worker.R','core.py','test-run.py'):queue(W/'poll-controller-v2'/filename,'measured-controller/'+filename)
for filename in ('native-operations/run.py','r-file-readers/record-builds.py','io-optimization/record-builds.py'):queue(R/'benchmarks'/filename,'measured-controller/dependencies/'+filename)
for role,build in [('baseline',BASE),('candidate',W/'poll-candidate-v2'),('publication',W/'publication-build-v1')]:
    for filename in ('build-receipt.json','input-record.json','source.patch'):queue(build/filename,'builds/'+role+'/'+filename)
for stage in ('poll-v2-baseline-red-final','poll-v2-green-final','publication-current-probe-v1'):
    for filename in ('work-count.csv','work-count.log','receipt.json'):queue(W/stage/filename,'structural/'+stage+'/'+filename)
for filename in ('work-count.py','work-count.c','cadence.h'):queue(W/'pair-probe-v2'/filename,'structural/measured-controller/'+filename)
for filename in ('work-count.csv','work-count.log','receipt.json'):queue(W/'poll-green-final'/filename,'structural/intermediate-v1/'+filename)
for filename in ('work-count.py','work-count.c'):queue(W/'pair-probe'/filename,'structural/intermediate-controller/'+filename)
for filename in ('independent-poll-v2-audit.py','poll-v2-screen-independent-audit.json','poll-v2-control-normalization.json','poll-v2-control-normalization-root.json','bind-publication.py','publication-binding.json','publication-conformance.json','publication-conformance.log','publication-conformance-preflight.json','publication-conformance-gate.sh','retain-publication-conformance.py'):
    queue(W/filename,'validation/'+filename)
for filename in ('before.json','after.json','command.json','completion.json','focused.csv','focused.log','test-source.patch'):queue(W/'publication-focused-v1'/filename,'validation/focused/'+filename)
queue(W/'publication-conformance-retained/dtatools.Rcheck/tests/testthat.Rout','validation/archive-testthat.Rout')
queue(W/'publication-conformance-retained/dtatools.Rcheck/00check.log','validation/archive-00check.log')
queue(Path(__file__).resolve(),'publish.py')
pending['publication-source-map.json']=encoded(mapping)
pending['publication-manifest.json']=encoded({k:hashlib.sha256(v).hexdigest() for k,v in sorted(pending.items())})
OUT.mkdir(parents=True)
for name,data in pending.items():
    p=OUT/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
print('Published',len(pending),'artifacts; historical originals unchanged')
