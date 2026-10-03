from pathlib import Path
import hashlib, importlib.util, json, os, shutil, subprocess
from datetime import datetime, timezone
HERE=Path(__file__).resolve().parent
BUILD=HERE/'candidate-final-v1'
REPO=Path('<repository>')
COMMIT='452ac7232ef6e47c398bcd22c7bb2800b55932c3'
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def require(x,m):
    if not x: raise RuntimeError(m)
def runtime(launcher):
    text=subprocess.check_output([str(launcher),'--vanilla','-e','cat(R.home(), R.version.string, sep=intToUtf8(10L))'],text=True)
    home,version=text.splitlines()
    binary=Path(home)/'bin/exec/R'
    return {'launcher':str(launcher),'launcher_sha256':sha(launcher),'R_home':home,'R_version':version,'R_runtime_sha256':sha(binary)}
def bind():
    recorder=REPO/'benchmarks/native-operations/run.py'
    spec=importlib.util.spec_from_file_location('records',recorder)
    records=importlib.util.module_from_spec(spec);spec.loader.exec_module(records)
    receipt=json.loads((BUILD/'build-receipt.json').read_text())
    records.inventory(BUILD,receipt['variant'])
    require(receipt['base_commit']==COMMIT and receipt['exit_code']==0 and receipt['pre_post_source_equal'] is True,'Build failed or wrong source')
    require((BUILD/'source.patch').read_bytes()==b'','Nonempty source patch')
    for directory,key in ((BUILD/'source','source_inventory'),(BUILD/'library/dtatools','installed_inventory')):
        for name,digest in receipt[key].items(): require(sha(directory/name)==digest,'Bound file changed: '+name)
    require(subprocess.check_output(['git','--no-replace-objects','rev-parse','HEAD'],cwd=REPO,text=True,env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}).strip()==COMMIT,'Integration HEAD changed')
    require(subprocess.check_output(['git','--no-replace-objects','status','--porcelain'],cwd=REPO,text=True,env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')})=='','Integration worktree changed')
    rt=runtime(launcher)
    require(rt['R_runtime_sha256']==receipt['toolchain']['R_runtime_sha256'],'Worker/build runtime differs')
    return {'commit':COMMIT,'build_receipt_sha256':sha(BUILD/'build-receipt.json'),'source_inventory':receipt['source_inventory'],'installed_inventory':receipt['installed_inventory'],'runtime':rt,'controllers':{p.name:sha(p) for p in (Path(__file__),HERE/'full-suite.R',recorder,REPO/'benchmarks/r-file-readers/record-builds.py',REPO/'benchmarks/io-optimization/record-builds.py')}}
launcher=Path(shutil.which('Rscript')).resolve(strict=True)
before=bind()
(HERE/'full-suite-before.json').write_text(json.dumps(before,indent=2,sort_keys=True)+'\n')
cmd=[str(launcher),'--vanilla',str(HERE/'full-suite.R'),str(BUILD/'library'),str(BUILD/'source/tests/testthat'),str(HERE/'full-suite.csv')]
command={'command':cmd,'cwd':str(REPO),'started_utc':datetime.now(timezone.utc).isoformat(),'scope':'Full installed R correctness suite; no timing benchmark.'}
(HERE/'full-suite-command.json').write_text(json.dumps(command,indent=2)+'\n')
with (HERE/'full-suite.log').open('wb') as log: result=subprocess.run(cmd,cwd=REPO,stdout=log,stderr=subprocess.STDOUT)
after=bind()
(HERE/'full-suite-after.json').write_text(json.dumps(after,indent=2,sort_keys=True)+'\n')
require(before==after,'Full-suite provenance changed')
command.update(exit_code=result.returncode,finished_utc=datetime.now(timezone.utc).isoformat(),before_after_equal=True)
(HERE/'full-suite-command.json').write_text(json.dumps(command,indent=2)+'\n')
require(result.returncode==0,'Full R suite failed; inspect preserved log/results')
print('Full installed suite terminal PASS; provenance unchanged')
