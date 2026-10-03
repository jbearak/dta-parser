import hashlib,importlib.util,json,subprocess,time
from pathlib import Path
P=Path(__file__).resolve().parent; R=Path('<PRIVATE_TMP>/dta-float-reciprocal-adaptive'); PIN='b6f72b585fc7c050aab5f3332a72f58bf3fa0d20'; B=P/'build'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
spec=importlib.util.spec_from_file_location('records',R/'benchmarks/native-operations/run.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
before=m.inventory(B,'baseline')
if before['receipt']['base_commit']!=PIN:raise RuntimeError('Wrong clean build')
(P/'focused-source.R').write_bytes(Path('<PRIVATE_TMP>/dta-float-reciprocal-evidence/focused-source.R').read_bytes())
args=['Rscript','--vanilla',str(P/'focused-source.R'),str(B/'library'),str(P/'focused.csv'),str(R/'r-package/dtatools/tests/testthat')]
record=dict(source_commit=PIN,command=args,cwd=str(R),controller_sha256=sha(__file__),test_runner_sha256=sha(P/'focused-source.R'),recorder_sha256=sha(R/'benchmarks/native-operations/run.py'),before=before)
(P/'focused-command.json').write_text(json.dumps(record,indent=2)+'\n')
with (P/'focused.log').open('w') as f: result=subprocess.run(args,cwd=R,stdout=f,stderr=subprocess.STDOUT)
record['exit_code']=result.returncode;record['after']=m.inventory(B,'baseline')
record['log_sha256']=sha(P/'focused.log');record['csv_sha256']=sha(P/'focused.csv') if (P/'focused.csv').exists() else None
(P/'focused-completion.json').write_text(json.dumps(record,indent=2)+'\n')
if result.returncode or before!=record['after']:raise RuntimeError('Focused qualification failed or build changed')
print('PASS focused integration')
