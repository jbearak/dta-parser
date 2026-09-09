from pathlib import Path
import datetime,hashlib,json,subprocess,sys

p=Path('/private/tmp/dta-direct-stage8-validation/publication-preparation')
def fact(f):
    f=Path(f);r=f.resolve(strict=True);s=r.stat()
    return dict(path=str(f),resolved=str(r),bytes=s.st_size,mode=oct(s.st_mode&0o7777),sha256=hashlib.sha256(r.read_bytes()).hexdigest())
paths=[p/'prepare-evidence-v2.py',p/'evidence-selection-02.json',Path(sys.executable),Path(__file__)]
before=[fact(f) for f in paths]
expected=['821440e4a518a68811ca1d648fb95509e0010e76d9133d60db335a8b859d9c60','609f49d585ff4ea87d6c92c0c1823bf20b26298fe1d561244429e71144a30674','8e8f1b256a299fe22e6cfe0dad6801ae8f0c62c7cfef844fbc2db92c03cfe32d']
if [f['sha256'] for f in before[:3]]!=expected:raise RuntimeError('Reviewed publication input mismatch')
argv=[str(sys.executable),'-I','-B',str(paths[0]),'build']
record=dict(status='running',argv=argv,selected_before=before,started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
with (p/'build-launch-01.json').open('x') as f:f.write(json.dumps(record,indent=2)+'\n')
try:
    with (p/'build-launch-01.log').open('x') as log:r=subprocess.run(argv,cwd=p,stdout=log,stderr=subprocess.STDOUT)
    record.update(status='complete' if r.returncode==0 else 'failed',exit_code=r.returncode)
except BaseException as exc:
    record.update(status='failed',error=dict(type=type(exc).__name__,message=str(exc)))
    raise
finally:
    record['selected_after']=[fact(f) for f in paths]
    record['changed']=[a['path'] for a,b in zip(before,record['selected_after']) if a!=b]
    record['completed_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    with (p/'build-launch-result-01.json').open('x') as f:f.write(json.dumps(record,indent=2)+'\n')
if r.returncode or record['changed']:raise RuntimeError('Archive transport failed')
print(json.dumps(record))
