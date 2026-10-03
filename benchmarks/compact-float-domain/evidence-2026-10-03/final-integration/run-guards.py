import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path('<final_repository>')
HERE=Path(__file__).resolve().parent
PIN='3eadb244253fb817d5773b01b11cb36c284f3a1d'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def need(c,m):
 if not c:raise RuntimeError(m)
need(subprocess.check_output(['git','--no-replace-objects','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==PIN,'Wrong guard source')
files=['scripts/test_native_manifest.py','scripts/test_arithmetic_dependencies.py','benchmarks/integer-reciprocal/test-work-count.py','benchmarks/long-float-addition/test-work-count.py','benchmarks/long-float-addition/test-run.py','benchmarks/compact-float-domain/strict/test-run.py','benchmarks/compact-float-domain/unknown/test-run.py','benchmarks/scalar-float-blocks/test-kernel.py']
before={p:sha(ROOT/p) for p in files};controller=sha(__file__);commands=[]
for i,(file,mode) in enumerate((file,mode) for file in files for mode in ([],['-O'])):
 command=[sys.executable,*mode,file];log=HERE/('guard-%02d.log'%i)
 with log.open('w') as stream:result=subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
 commands.append(dict(command=command,cwd=str(ROOT),returncode=result.returncode,log=log.name,log_sha256=sha(log)))
 need(result.returncode==0,'Guard failed: '+file)
need(before=={p:sha(ROOT/p) for p in files} and sha(__file__)==controller,'Guard sources changed')
(HERE/'guards.json').write_text(json.dumps(dict(status='PASS',source_commit=PIN,files=before,runner_sha256=controller,commands=commands),indent=2)+'\n')
print('PASS',len(commands),'guard commands')
