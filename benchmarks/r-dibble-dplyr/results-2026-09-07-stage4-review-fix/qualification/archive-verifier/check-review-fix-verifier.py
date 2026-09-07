"""Exercise the archive verifier with tiny synthetic inventories, without R work."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys
root=Path('/private/tmp/dta-direct-stage4-validation/review-fix-verifier-guards')
root.mkdir()
source=Path('/private/tmp/dta-direct-stage4/benchmarks/r-dibble-dplyr/results-2026-09-07-stage4-review-fix/verify.py')
result=[]
for mode,args,envadd in [('default',[],{}),('optimized',['-O'],{}),('envoptimized',[],{'PYTHONOPTIMIZE':'1'})]:
 for case in ['valid','wrong-bytes','extra-file','wrong-executable','duplicate-path','escaping-path']:
  p=root/(mode+'-'+case);p.mkdir(); shutil.copy2(source,p/'verify.py')
  (p/'payload.txt').write_text('original\n');(p/'payload.txt').chmod(0o644)
  def rec(path):
   b=path.read_bytes();return {'path':path.name,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest(),'mode':oct(path.stat().st_mode&0o777)}
  index={'files':[rec(p/'payload.txt')],'authored_files':[rec(p/'verify.py')],'external_artifacts':[]}
  if case=='wrong-bytes':(p/'payload.txt').write_text('modified\n')
  if case=='extra-file':(p/'unexpected.txt').write_text('unexpected\n')
  if case=='wrong-executable':(p/'payload.txt').chmod(0o755)
  if case=='duplicate-path':index['files'].append(index['files'][0])
  if case=='escaping-path':index['files'][0]['path']='../payload.txt'
  (p/'index.json').write_text(json.dumps(index,indent=2)+'\n')
  completed=subprocess.run([sys.executable,*args,str(p/'verify.py')],env=os.environ|envadd,capture_output=True,text=True)
  expected=case=='valid'
  if (completed.returncode==0)!=expected:raise RuntimeError((mode,case,completed))
  result.append({'mode':mode,'case':case,'exit_code':completed.returncode,'stdout':completed.stdout,'stderr':completed.stderr,'expected_accept':expected})
record={'scope':'Synthetic tiny inventories only; no package, R, build, or benchmark execution.',
        'verifier_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'cases':result}
(root/'manifest.json').write_text(json.dumps(record,indent=2)+'\n')
print('PASS:',len(result),'synthetic archive-integrity cases')
