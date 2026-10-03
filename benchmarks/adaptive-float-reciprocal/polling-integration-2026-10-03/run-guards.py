import hashlib,json,subprocess
from pathlib import Path
P=Path(__file__).resolve().parent;R=Path('<PRIVATE_TMP>/dta-float-reciprocal-adaptive')
records=[]
for script in ('scripts/test_native_manifest.py','scripts/test_arithmetic_dependencies.py'):
 for opt in (False,True):
  args=['python3']+(['-O'] if opt else [])+[script]
  name=Path(script).stem+('-optimized' if opt else '')+'.log'
  with (P/name).open('w') as f:r=subprocess.run(args,cwd=R,stdout=f,stderr=subprocess.STDOUT)
  records.append(dict(command=args,cwd=str(R),exit_code=r.returncode,script_sha256=hashlib.sha256((R/script).read_bytes()).hexdigest(),log=name,log_sha256=hashlib.sha256((P/name).read_bytes()).hexdigest()))
(P/'guards.json').write_text(json.dumps(records,indent=2)+'\n')
if any(r['exit_code'] for r in records):raise RuntimeError('Guard failed')
print('PASS manifest8+8 dependency1+1')
