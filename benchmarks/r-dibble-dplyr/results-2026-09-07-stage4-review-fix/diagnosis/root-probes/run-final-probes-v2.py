"""Replay constructor and actual-package width regressions against exact installs."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path('/private/tmp/dta-direct-stage4-validation')
HERE = ROOT / 'root-review-probes'
OUTPUT = ROOT / 'root-review-probes-c8ca0a4-v2'
BASE = 'e343b3b56a8529e9ee0ac40f8bd88beebcd2be15'
FINAL = 'c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe'
HELPER = Path('/private/tmp/dta-direct-stage4/benchmarks/r-dibble-dplyr/helpers.R')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


if OUTPUT.exists():
    raise RuntimeError('Refusing to replace probe evidence')
paths = [Path(__file__).resolve(), HELPER] + [HERE / name for name in
    ['constructor-final-v2.R', 'scan-vmax.R', 'scan-vmax-minimal.R', 'scan-vmax.c', 'scan-vmax.so']]
for short in ['e343b3b', 'c8ca0a4']:
    paths.extend(ROOT / f'candidate-{short}-library/dtatools' / name for name in
                 ['libs/dtatools.so', 'Meta/benchmark-provenance.rds'])
inputs = {str(path): digest(path) for path in paths}
OUTPUT.mkdir()
with (OUTPUT / 'input-identities.json').open('x') as stream:
    json.dump(inputs, stream, indent=2)
    stream.write('\n')
records = []
for name, script, short, revision, expected in [
        ('constructor-baseline', 'constructor-final-v2.R', 'e343b3b', BASE, 1),
        ('constructor-candidate', 'constructor-final-v2.R', 'c8ca0a4', FINAL, 0),
        ('vmax-candidate', 'scan-vmax.R', 'c8ca0a4', FINAL, 0),
        ('vmax-minimal-candidate', 'scan-vmax-minimal.R', 'c8ca0a4', FINAL, 0)]:
    command = ['Rscript', '--vanilla', str(HERE / script),
               str(ROOT / f'candidate-{short}-library'), revision]
    if script.startswith('scan-vmax'):
        command.append(str(HERE / 'scan-vmax.so'))
    command.append(str(OUTPUT / f'{name}.rds'))
    log = OUTPUT / f'{name}.log'
    with log.open('xb') as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
    records.append({'case': name, 'command': command, 'exit_code': result.returncode,
                    'expected_exit_code': expected, 'log_sha256': digest(log)})
    (OUTPUT / 'progress.json').write_text(json.dumps(records, indent=2) + '\n')
    if result.returncode != expected:
        raise RuntimeError(f'Unexpected probe result: {log}')
    if expected and b'Fresh constructor copied backing again or failed source/value isolation' not in log.read_bytes():
        raise RuntimeError('Baseline failed before the intended constructor assertion')
    print(name, 'exit', result.returncode, 'as expected', flush=True)
if any(digest(Path(path)) != value for path, value in inputs.items()):
    raise RuntimeError('Probe input changed during execution')
with (OUTPUT / 'manifest.json').open('x') as stream:
    json.dump({'source': FINAL, 'baseline_source': BASE, 'inputs_before_and_after': inputs,
               'cases': records, 'files': {p.name: digest(p) for p in OUTPUT.iterdir() if p.is_file()},
               'scope': 'Native copy counters, value/source isolation and R temporary marker lifetime. '
                        'No timing, R allocation byte count or peak-RSS claim.'}, stream, indent=2)
    stream.write('\n')
