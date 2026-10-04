from pathlib import Path
import hashlib, json, os, shutil, subprocess
from datetime import datetime, timezone
HERE=Path(__file__).resolve().parent
BUILD=HERE.parent/'publication-build-v1'
REPO=Path('<private-tmp>/dta-long-float-addition')
COMMIT='958082e4e9eb3fd78be6a81f1e70b6fabca27d9f'
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def require(x,m):
    if not x: raise RuntimeError(m)
def runtime(launcher):
    text=subprocess.check_output([str(launcher),'--vanilla','-e','cat(R.home(), R.version.string, sep=intToUtf8(10L))'],text=True)
    home,version=text.splitlines()
    binary=Path(home)/'bin/exec/R'
    return {'launcher':str(launcher),'launcher_sha256':sha(launcher),'R_home':home,'R_version':version,'R_runtime_sha256':sha(binary)}
def bind():
    receipt=json.loads((BUILD/'build-receipt.json').read_text())
    require(receipt['base_commit']==COMMIT and receipt['exit_code']==0 and receipt['pre_post_source_equal'] is True,'Build failed or wrong source')
    require((BUILD/'source.patch').read_bytes()==b'','Nonempty source patch')
    for directory,key in ((BUILD/'source','source_inventory'),(BUILD/'library/dtatools','installed_inventory')):
        actual={p.relative_to(directory).as_posix():sha(p) for p in directory.rglob('*') if p.is_file()}
        require(actual==receipt[key], 'Bound file inventory changed: '+key)
    require(subprocess.check_output(['git','--no-replace-objects','rev-parse','HEAD'],cwd=REPO,env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')},text=True).strip()==COMMIT,'Integration HEAD changed')
    require(subprocess.check_output(['git','--no-replace-objects','status','--porcelain'],cwd=REPO,env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')},text=True)=='','Integration worktree changed')
    rt=runtime(launcher)
    require(rt['R_runtime_sha256']==receipt['toolchain']['R_runtime_sha256'],'Worker/build runtime differs')
    return {'commit':COMMIT,'build_receipt_sha256':sha(BUILD/'build-receipt.json'),'source_inventory':receipt['source_inventory'],'installed_inventory':receipt['installed_inventory'],'runtime':rt,'controllers':{p.name:sha(p) for p in (Path(__file__),HERE/'full-suite.R')}}
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
