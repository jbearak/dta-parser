#!/usr/bin/env python3
"""Publish audited uniform-locator artifacts, preserving original hashes before redaction."""
import hashlib,json,re,sys
from pathlib import Path
W=Path('<work>')
R=Path('<publication-repository>')
BASE=Path('<baseline-build>')
TRACE=Path('<private-work>/dta-retained-span-evidence/poll-v2-green-final')
PROBE=Path('<private-work>/dta-retained-span-evidence/rust-red-bound/retained_span_probe.rs')
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
audit=read('screen-independent-audit.json')
need(audit['status']=='PASS' and audit['observations']==696 and audit['qualification_observations']==116 and audit['summary_rows']==26,'Independent audit incomplete')
bound(W/'independent-audit.py',audit['auditor_sha256'])
for stage,count,rounds,phase,key in [('screen',696,6,'measure','timing_completion_sha256'),('qualification',116,1,'qualify','qualification_completion_sha256')]:
    bound(W/stage/'completion.json',audit[key]);complete=read(stage+'/completion.json')
    need(complete['observations']==count and complete['rounds']==rounds and complete['phase']==phase and complete['exact_results'] is True and complete['provenance_unchanged'] is True,'Matrix/semantic gate failed')
    for name,digest in complete['artifacts'].items():bound(W/stage/name,digest)
    before=read(stage+'/provenance-before.json');after=read(stage+'/provenance-after.json');need(before==after,'Provenance changed')
    need({k:v['receipt']['base_commit'] for k,v in before['builds'].items()}=={'baseline':'e1b0278b1403b4d8fc2d9a2dfc0c4ddaa7cde3a2','candidate':'1b1d3770a84353efd14a62a64dabecedfcdf2380'},'Wrong measured commits')
    for filename,key in [('run.py','controller'),('worker.R','worker'),('core.py','validation'),('test-run.py','protocol_tests')]:bound(W/'controller'/filename,before['controllers'][key])
    for filename,key in [('native-operations/run.py','build_validation'),('r-file-readers/record-builds.py','build_recorder'),('io-optimization/record-builds.py','build_recorder_parent')]:bound(R/'benchmarks'/filename,before['controllers'][key])
    for role,build in [('baseline',BASE),('candidate',W/'candidate-build')]:
        b=before['builds'][role];bound(build/'build-receipt.json',b['receipt_sha256'])
        bound(build/'input-record.json',b['receipt']['input_record_sha256']);bound(build/'source.patch',b['receipt']['source_patch_sha256'])
structural_replay=read('independent-structural-replay.json')
need(structural_replay['status']=='PASS' and len(structural_replay['stages'])==2,'Structural replay missing')
for stage,commit,code,failures in [('baseline-red-final','e1b0278b1403b4d8fc2d9a2dfc0c4ddaa7cde3a2',101,10),('candidate-green-final','1b1d3770a84353efd14a62a64dabecedfcdf2380',0,0)]:
    probe=read(stage+'/receipt.json')
    replay=next(v for v in structural_replay['stages'] if v['stage']==stage)
    bound(W/stage/'receipt.json',replay['receipt_sha256'])
    need(probe['commit']==commit and probe['exit_code']==code and probe['api_checks']==11367 and probe['uniform_work_failures']==failures and probe['geometries']==12 and probe['c_header_cases']==18,'Wrong structural stage')
    need(probe['status']==('EXPECTED_RED' if failures else 'PASS'),'Wrong structural status')
    for name,digest in probe['artifacts'].items():bound(W/stage/name,digest)
    bound(W/'structural.py',probe['controller_sha256']);bound(PROBE,probe['probe_sha256'])
    for name,digest in probe['c_header_binding'].items():bound(TRACE/name,digest)
    for name,digest in probe['compiler_hashes'].items():bound(Path(name),digest)
    for name,digest in probe['instrumented_source'].items():bound(W/stage/'source'/name,digest)
codegen=read('codegen/binding.json')
for role,commit in [('baseline','e1b0278b1403b4d8fc2d9a2dfc0c4ddaa7cde3a2'),('candidate','1b1d3770a84353efd14a62a64dabecedfcdf2380')]:
    record=codegen[role];need(record['source_commit']==commit,'Wrong codegen source')
    for name,digest in record['inputs_sha256'].items():bound(Path(name),digest)
    bound(W/'codegen'/(role+'.txt'),record['artifact_sha256'])
owner=read('owner-tests.json')
need(owner['source_commit']=='1b1d3770a84353efd14a62a64dabecedfcdf2380' and owner['exit_code']==0,'Wrong owner tests')
bound(W/'owner-tests.log',owner['log_sha256'])
need('12 passed; 0 failed' in (W/'owner-tests.log').read_text(),'Incomplete owner tests')
integration=read('publication-binding.json');need(integration['status']=='PASS' and integration['source_commit']=='a6b6b9e792eb046716e04c96e72fbff94baf4910' and integration['measured_locator_byte_identical'] is True,'Publication integration not bound')
for name,digest in integration['input_sha256'].items():bound(Path(name),digest)
publication=integration['build']
bound(W/'publication-build-v1/build-receipt.json',publication['receipt_sha256'])
bound(W/'publication-build-v1/input-record.json',publication['receipt']['input_record_sha256'])
bound(W/'publication-build-v1/source.patch',publication['receipt']['source_patch_sha256'])
focused=read('publication-focused-v1/completion.json')
for name,digest in focused['artifacts'].items():bound(W/'publication-focused-v1'/name,digest)
preflight=read('publication-conformance-preflight.json')
need(preflight['commit']==integration['source_commit'],'Wrong conformance preflight source')
bound(W/'publication-conformance-gate.sh',preflight['retained_gate_sha256'])
bound(W/'retain-publication-conformance.py',preflight['retainer_sha256'])
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
for stage in ('screen','qualification'):
    for p in sorted((W/stage).iterdir()):
        if p.suffix in ('.csv','.json','.patch'):queue(p,stage+'/'+p.name)
for filename in ('run.py','worker.R','core.py','test-run.py'):queue(W/'controller'/filename,'measured-controller/'+filename)
for filename in ('native-operations/run.py','r-file-readers/record-builds.py','io-optimization/record-builds.py'):queue(R/'benchmarks'/filename,'measured-controller/dependencies/'+filename)
for role,build in [('baseline',BASE),('candidate',W/'candidate-build'),('publication',W/'publication-build-v1')]:
    for filename in ('build-receipt.json','input-record.json','source.patch'):queue(build/filename,'builds/'+role+'/'+filename)
for stage in ('baseline-red-final','candidate-green-final'):
    for filename in ('work-count.csv','run.log','build.log','build.jsonl','receipt.json'):queue(W/stage/filename,'structural/'+stage+'/'+filename)
    queue(W/stage/'source/r-package/dtatools/src/rust/src/owned_numeric.rs','structural/'+stage+'/instrumented-owned_numeric.rs')
queue(PROBE,'structural/retained_span_probe.rs')
queue(W/'structural.py','structural/structural.py')
for filename in ('receipt.json','work-count.csv'):queue(TRACE/filename,'structural/c-trace/'+filename)
for filename in ('binding.json','baseline.txt','candidate.txt'):queue(W/'codegen'/filename,'codegen/'+filename)
for filename in ('independent-audit.py','screen-independent-audit.json','control-normalization-root.json','independent-structural-replay.json','owner-tests.json','owner-tests.log','bind-publication.py','publication-binding.json','publication-conformance.json','publication-conformance.log','publication-conformance-preflight.json','publication-conformance-gate.sh','retain-publication-conformance.py'):
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
