"""Actual pristine dplyr tag installations against the isolated R 4.6.0."""
from pathlib import Path
import json, os, subprocess, hashlib, datetime
root = Path('/private/tmp/dta-direct-stage5-minimum-preflight')
rbin = root / 'r460-install/bin/R'
rscript = root / 'r460-install/bin/Rscript'
records = json.loads((root/'manifests/dplyr-git-archives.json').read_text())
env = os.environ.copy()
env.update(R_LIBS_SITE=str(root/'r460-dependencies'), R_LIBS_USER=str(root/'empty-user-library'),
           R_LIBS=str(root/'r460-dependencies'), R_MAKEVARS_USER='/dev/null',
           R_ENVIRON_USER='/dev/null', R_PROFILE_USER='/dev/null', MAKEFLAGS='-j4')
results = []
for item in records:
    version = item['version']
    library = root / 'r460-dplyr-libraries' / version
    library.mkdir(parents=True, exist_ok=False)
    source = root / item['install_source']
    if hashlib.sha256((source/'src/chop.cpp').read_bytes()).hexdigest() != item['chop_sha256']:
        raise RuntimeError(f'Source changed: {version}')
    command = [str(rbin), 'CMD', 'INSTALL', '--library='+str(library), str(source)]
    log = root / 'logs' / ('r460-dplyr-'+version+'-install.log')
    with log.open('x') as output:
        process = subprocess.run(command, cwd=root, env=env, stdout=output, stderr=subprocess.STDOUT)
    result = {'version':version,'command':command,'exit_code':process.returncode,
              'log':str(log.relative_to(root)), 'log_sha256':hashlib.sha256(log.read_bytes()).hexdigest(),
              'installed_directory_exists':(library/'dplyr').exists()}
    if process.returncode == 0:
        smoke = root/'logs'/('r460-dplyr-'+version+'-smoke.log')
        smoke_env = dict(env, R_LIBS=str(library)+os.pathsep+str(root/'r460-dependencies'))
        smoke_command = [str(rscript),'--vanilla',str(root/'runtime-smoke.R'),str(library),version,'4.6.0']
        with smoke.open('x') as output:
            check = subprocess.run(smoke_command,cwd=root,env=smoke_env,stdout=output,stderr=subprocess.STDOUT)
        result.update(smoke_command=smoke_command,smoke_exit_code=check.returncode,
                      smoke_log=str(smoke.relative_to(root)),smoke_sha256=hashlib.sha256(smoke.read_bytes()).hexdigest())
    results.append(result)
    (root/'manifests/r460-dplyr-installs.json').write_text(json.dumps(results,indent=2)+'\n')
    print(version, 'install', process.returncode, 'smoke', result.get('smoke_exit_code'),flush=True)
    expected = 0 if version == '1.2.1' else 1
    if process.returncode != expected:
        raise RuntimeError(f'Unexpected install result for {version}; inspect retained log')
    if expected and not all(x in log.read_text() for x in ['chop.cpp','SET_PRENV','SET_PRCODE','SET_PRVALUE','compilation failed']):
        raise RuntimeError(f'Failure not classified as expected public-header compilation issue: {version}')
    if not expected and result.get('smoke_exit_code') != 0:
        raise RuntimeError(f'Installed package smoke failed: {version}')
