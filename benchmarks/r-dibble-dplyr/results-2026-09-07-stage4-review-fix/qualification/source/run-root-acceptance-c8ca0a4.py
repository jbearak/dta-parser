"""Replay the four unchanged historical R behavior matrices on the fixed artifact."""
from pathlib import Path
import datetime
import hashlib
import json
import shutil
import subprocess

ROOT = Path('/private/tmp/dta-direct-stage4-validation')
PRIOR = ROOT / 'root-acceptance-e343b3b'
OUTPUT = ROOT / 'root-acceptance-c8ca0a4'
LIBRARY = ROOT / 'candidate-c8ca0a4-library'
REPO = Path('/private/tmp/dta-direct-stage4')
SOURCE = 'c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe'
CASES = {'generation-names': 45, 'delayed-mask': 72,
         'delayed-private-mask': 72, 'symbol-private-callback': 30}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(value, message):
    if not value:
        raise RuntimeError(message)


require(not OUTPUT.exists(), 'Refusing to replace root regression evidence')
old_manifest = json.loads((PRIOR / 'root-manifest.json').read_text())
for name, sha in old_manifest['files'].items():
    require(digest(PRIOR / name) == sha, f'Historical input changed: {name}')
OUTPUT.mkdir()
for name in CASES:
    for suffix in ['-matrix.R', '-baseline.rds']:
        shutil.copy2(PRIOR / (name + suffix), OUTPUT / (name + suffix))
for name in ['root-manifest.json', 'reused-input-identities.json', 'pre-run-input-identities.json']:
    shutil.copy2(PRIOR / name, OUTPUT / ('historical-' + name))
old_driver = (PRIOR / 'run.R').read_text()
require(old_driver.count(str(PRIOR)) == 1, 'Unexpected historical output binding')
with (OUTPUT / 'run.R').open('x') as stream:
    stream.write(old_driver.replace(str(PRIOR), str(OUTPUT)))
helper = REPO / 'benchmarks/r-dibble-dplyr/helpers.R'
require(helper.read_bytes() == subprocess.check_output(
    ['git', 'show', SOURCE + ':benchmarks/r-dibble-dplyr/helpers.R'], cwd=REPO),
    'Installation helper differs from committed source')
dll = LIBRARY / 'dtatools/libs/dtatools.so'
require(hashlib.md5(dll.read_bytes()).hexdigest() == 'c655c59a09cbf1cd72a6f72e7e94758e',
        'Unexpected fixed artifact DLL')
paths = list(OUTPUT.iterdir()) + [helper, dll, LIBRARY / 'dtatools/Meta/benchmark-provenance.rds',
                                 Path(__file__).resolve()]
inputs = {str(path): digest(path) for path in paths}
with (OUTPUT / 'input-identities.json').open('x') as stream:
    json.dump(inputs, stream, indent=2)
    stream.write('\n')
command = ['Rscript', '--vanilla', str(OUTPUT / 'run.R'), str(LIBRARY), SOURCE]
with (OUTPUT / 'driver.log').open('xb') as stream:
    result = subprocess.run(command, cwd=REPO, stdout=stream, stderr=subprocess.STDOUT)
require(all(digest(Path(path)) == sha for path, sha in inputs.items()), 'Regression input changed')
require(result.returncode == 0, 'Historical R behavior comparison failed; inspect retained log')
for name in CASES:
    require((OUTPUT / (name + '-candidate.rds')).read_bytes() ==
            (OUTPUT / (name + '-baseline.rds')).read_bytes(), f'RDS bytes differ: {name}')
    require('DLL_md5 c655c59a09cbf1cd72a6f72e7e94758e' in
            (OUTPUT / (name + '-candidate.log')).read_text(), f'Wrong child DLL: {name}')
with (OUTPUT / 'root-manifest.json').open('x') as stream:
    json.dump({'source_sha': SOURCE, 'library': str(LIBRARY), 'command': command,
               'process_exit_code': result.returncode, 'cases': CASES,
               'inputs_before_and_after': inputs,
               'files': {p.name: digest(p) for p in OUTPUT.iterdir() if p.is_file()},
               'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'scope': '219 unchanged pure R historical cases. R identical() and exact RDS bytes '
                        'match; source/installation guards and child DLL identities checked. '
                        'Historical 18 native observers remain excluded because their C source is unavailable.'},
              stream, indent=2)
    stream.write('\n')
print((OUTPUT / 'driver.log').read_text(), end='')
