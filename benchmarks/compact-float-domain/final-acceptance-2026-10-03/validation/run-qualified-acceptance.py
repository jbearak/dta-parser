#!/usr/bin/env python3
"""Require exact untimed qualification before launching the unchanged34-case timing controller."""
import argparse, hashlib, importlib.util, json, shutil, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent
CONTROLLER=ROOT/'acceptance-controller/general-run.py'
def need(ok,message):
    if not ok: raise RuntimeError(message)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text())
def write(path,value):path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
a=argparse.ArgumentParser(description=__doc__)
for name in ('baseline','candidate','output'):a.add_argument('--'+name,type=Path,required=True)
args=a.parse_args()
spec=importlib.util.spec_from_file_location('final_acceptance_controller',CONTROLLER)
run=importlib.util.module_from_spec(spec);spec.loader.exec_module(run)
complete=read(ROOT/'acceptance-qualification-completion.json')
need(complete['status']=='PASS' and complete['total']==204 and complete['cases_per_build']==102,'Completed204-case qualification required')
need(all(complete[k] is True for k in ('exact_results_and_missing_caches','source_state_unchanged','native_routes_checked_in_both_builds','provenance_unchanged')),'Qualification gates incomplete')
expected={str(ROOT/f'acceptance-{role}-qualification.{ext}') for role in ('baseline','candidate') for ext in ('csv','log')}
expected|={str(ROOT/f'acceptance-qualification-{phase}.json') for phase in ('before','after')}
need(set(complete['input_sha256'])==expected,'Incomplete qualification artifact set')
for name,digest in complete['input_sha256'].items():need(sha(Path(name))==digest,'Changed qualification artifact')
qualified=read(ROOT/'acceptance-qualification-before.json')
need(qualified==read(ROOT/'acceptance-qualification-after.json'),'Qualification identities changed')
controller_files=[CONTROLLER,CONTROLLER.with_name('general-worker.R'),run.RECORDS_PATH,ROOT/'qualify-acceptance.py',CONTROLLER.with_name('test-general-run.py'),CONTROLLER.with_name('README.md'),*run.RECORDER_DEPENDENCIES]
need(qualified['controller_sha256']=={str(p):sha(p) for p in controller_files},'Current controller differs from qualification')
found=shutil.which('Rscript');need(found is not None,'Rscript unavailable')
runtime=run.worker_runtime(Path(found).resolve(strict=True))
builds={role:getattr(args,role).resolve() for role in ('baseline','candidate')}
records={role:run.RECORDS.inventory(path,'baseline') for role,path in builds.items()}
need(qualified['runtime']==runtime and qualified['builds']==records,'Current build/runtime differs from qualification')
need({role:r['receipt']['base_commit'] for role,r in records.items()}==run.COMMITS,'Unexpected committed sources')
preflight=dict(status='PASS',qualification_completion_sha256=sha(ROOT/'acceptance-qualification-completion.json'),qualification_binding=qualified,launcher_sha256=sha(Path(__file__)),controller_sha256=sha(CONTROLLER),scope='Exact completed204-case qualification identities verified immediately before launching timing.')
write(ROOT/'timing-preflight.json',preflight)
subprocess.run([sys.executable,str(CONTROLLER),'--baseline',str(builds['baseline']),'--candidate',str(builds['candidate']),'--output',str(args.output),'--rounds','6'],check=True)
before=read(args.output/'provenance-before.json');after=read(args.output/'provenance-after.json')
need(before['builds']==after['builds']==records and before['runtime']==after['runtime']==runtime,'Timing build/runtime differs from qualified preflight')
need(before['controllers']==after['controllers']=={p.name:sha(p) for p in (CONTROLLER,CONTROLLER.with_name('general-worker.R'),run.RECORDS_PATH)},'Timing controllers differ from qualification')
need(sha(Path(__file__))==preflight['launcher_sha256'],'Launch guard changed')
need(qualified['controller_sha256']=={str(p):sha(p) for p in controller_files},'Qualified controller dependency changed during timing')
write(ROOT/'timing-qualification-binding.json',dict(status='PASS',timing_completion_sha256=sha(args.output/'completion.json'),preflight_sha256=sha(ROOT/'timing-preflight.json'),scope='Completed timing uses the same build, controller and runtime identities as completed untimed qualification. Independent result/statistical audit follows separately.'))
print('PASS timing bound to prior204-case qualification',flush=True)
