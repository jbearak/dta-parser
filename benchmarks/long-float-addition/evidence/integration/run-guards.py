from pathlib import Path
import hashlib,json,os,subprocess,sys
HERE=Path(__file__).resolve().parent
REPO=Path('<private-tmp>/dta-long-float-addition')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
files=('benchmarks/long-float-addition/test-run.py','benchmarks/long-float-addition/test-work-count.py','scripts/test_native_manifest.py','scripts/test_arithmetic_dependencies.py')
commands=[[sys.executable,*mode,file] for file in files for mode in ([],['-O'])]
records=[]
for i,command in enumerate(commands):
 result=subprocess.run(command,cwd=REPO,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 log=HERE/f'guard-{i+1:02d}.log';log.write_bytes(result.stdout)
 records.append(dict(command=command,cwd=str(REPO),returncode=result.returncode,log=log.name,log_sha256=sha(log)))
 if result.returncode:raise RuntimeError('Guard failed: '+str(command))
record=dict(status='PASS',runner_sha256=sha(Path(__file__)),source_commit=subprocess.check_output(['git','--no-replace-objects','rev-parse','HEAD'],cwd=REPO,text=True,env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}).strip(),commands=records,files={name:sha(REPO/name) for name in files})
(HERE/'guards.json').write_text(json.dumps(record,indent=2,sort_keys=True)+'\n')
print('PASS',len(records),'recorded command/mode guards')
