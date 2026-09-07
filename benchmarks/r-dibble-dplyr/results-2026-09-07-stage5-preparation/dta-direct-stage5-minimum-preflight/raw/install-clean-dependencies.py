"""Build exact CRAN dependency archives into the isolated R 4.6.0 library."""
from pathlib import Path
import json, os, subprocess, hashlib, datetime
root = Path('/private/tmp/dta-direct-stage5-minimum-preflight')
rbin = root / 'r460-clean-install/bin/R'
library = root / 'r460-clean-dependencies'
library.mkdir(exist_ok=True)
empty = root / 'empty-user-library'
empty.mkdir(exist_ok=True)
records = {x['package']: x for x in json.loads((root / 'manifests/dependency-downloads.json').read_text())}
order = ['cli','generics','glue','magrittr','R6','rlang','utf8','pkgconfig','withr','lifecycle','vctrs','pillar','tibble','tidyselect']
env = os.environ.copy()
env.update(R_LIBS_SITE=str(library), R_LIBS_USER=str(empty), R_LIBS=str(library),
           R_MAKEVARS_USER='/dev/null', R_ENVIRON_USER='/dev/null', R_PROFILE_USER='/dev/null',
           MAKEFLAGS='-j4')
results = []
for name in order:
    item = records[name]
    archive = root / item['archive']
    if hashlib.sha256(archive.read_bytes()).hexdigest() != item['sha256']:
        raise RuntimeError(f'Archive changed: {name}')
    if (library / name).exists():
        raise RuntimeError(f'Refusing to replace installed dependency: {name}')
    command = [str(rbin), 'CMD', 'INSTALL', '--library='+str(library), str(archive)]
    log = root / 'logs' / ('clean-dependency-'+name+'.log')
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with log.open('x') as output:
        process = subprocess.run(command, cwd=root, env=env, stdout=output, stderr=subprocess.STDOUT)
    results.append({'package':name,'version':item['version'],'command':command,'started_utc':started,
                    'exit_code':process.returncode,'log':str(log.relative_to(root)),
                    'log_sha256':hashlib.sha256(log.read_bytes()).hexdigest()})
    (root / 'manifests/clean-dependency-installs.json').write_text(json.dumps(results,indent=2)+'\n')
    print(name, process.returncode, flush=True)
    if process.returncode:
        raise RuntimeError(f'Dependency setup failed: {name}; see {log}')
