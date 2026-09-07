"""Run fresh paired matrices after the implementation's quiet-window handoff.

This coordinator preserves child logs and binds every benchmark source file to
the reviewed commit before and after each child. Individual reviewed drivers
check the exact installed package and their own output protocols. Run only when
all local builds, tests and probes have stopped.
"""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys

REPO = Path('/private/tmp/dta-direct-stage4')
VALIDATION = Path('/private/tmp/dta-direct-stage4-validation')
OUTPUT = VALIDATION / 'root-c8ca0a4-performance'
CANDIDATE = 'c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe'
BASELINE = 'ec10a6ac34602f3bd691e8043019c1b479babda4'
RUNNER = CANDIDATE
RELATIVE = Path('benchmarks/r-dibble-dplyr')
NAMES = ['helpers.R', 'owned-double-helpers.R', 'owned-atomic-helpers.R',
         'owned-double.R', 'owned-double-memory.R', 'owned-atomic.R',
         'owned-atomic-memory.R', 'owned-heap.R', 'run-owned-qualification.py',
         'run-atomic-qualification.py', 'run-heap-qualification.py']
COMPARATORS = ['compare-atomic.py', 'compare-double.py', 'compare-heap-c8ca0a4.py']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(value, message):
    if not value:
        raise RuntimeError(message)


require(not OUTPUT.exists(), f'Refusing to replace evidence: {OUTPUT}')
source = {}
for name in NAMES:
    path = REPO / RELATIVE / name
    expected = subprocess.check_output(['git', 'show', f'{RUNNER}:{RELATIVE / name}'], cwd=REPO)
    require(path.read_bytes() == expected, f'Uncommitted runner input: {name}')
    source[str(path)] = hashlib.sha256(expected).hexdigest()
for name in COMPARATORS:
    source[str(VALIDATION / name)] = sha(VALIDATION / name)
source[str(Path(__file__).resolve())] = sha(Path(__file__).resolve())
OUTPUT.mkdir()
with (OUTPUT / 'input-identities.json').open('x') as stream:
    json.dump({'candidate_source': CANDIDATE, 'baseline_source': BASELINE,
               'runner_source': RUNNER, 'inputs': source}, stream, indent=2)
    stream.write('\n')
commands = []
started = datetime.datetime.now(datetime.timezone.utc).isoformat()


def guard():
    for path, digest in source.items():
        require(sha(Path(path)) == digest, f'Changed executed input: {path}')


def run(name, command):
    guard()
    log = OUTPUT / f'{name}.log'
    record = {'name': name, 'command': command, 'cwd': str(REPO),
              'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'log': str(log)}
    with log.open('xb') as stream:
        result = subprocess.run(command, cwd=REPO, stdout=stream, stderr=subprocess.STDOUT)
    record.update(exit_code=result.returncode, log_sha256=sha(log),
                  finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    commands.append(record)
    (OUTPUT / 'progress.json').write_text(json.dumps(commands, indent=2) + '\n')
    guard()
    print(name, 'exit', result.returncode, flush=True)
    require(result.returncode == 0, f'Qualification failed; retained evidence: {log}')


for family, driver in [('atomic', 'run-atomic-qualification.py'),
                       ('double', 'run-owned-qualification.py')]:
    for phase in ['operations', 'memory']:
        for mode, revision, library in [
                ('baseline', BASELINE, VALIDATION / 'baseline-library'),
                ('candidate', CANDIDATE, VALIDATION / 'candidate-c8ca0a4-library')]:
            run(f'{family}-{mode}-{phase}', [sys.executable, str(REPO / RELATIVE / driver),
                phase, str(REPO), str(OUTPUT / f'{family}-{mode}'), str(library),
                revision, RUNNER, mode])

for mode, revision, library in [
        ('baseline', BASELINE, VALIDATION / 'baseline-library'),
        ('candidate', CANDIDATE, VALIDATION / 'candidate-c8ca0a4-library')]:
    run(f'heap-{mode}', [sys.executable, str(REPO / RELATIVE / 'run-heap-qualification.py'),
        str(REPO), str(OUTPUT / f'heap-{mode}'), str(library), revision, RUNNER, mode])

for family, comparator in [('atomic', 'compare-atomic.py'), ('double', 'compare-double.py'),
                           ('heap', 'compare-heap-c8ca0a4.py')]:
    command = [sys.executable, str(VALIDATION / comparator)]
    if family == 'heap':
        command.append(str(REPO))
    command.extend(str(OUTPUT / name) for name in
                   [f'{family}-baseline', f'{family}-candidate', f'{family}-comparison'])
    run(f'compare-{family}', command)

guard()
with (OUTPUT / 'qualification.json').open('x') as stream:
    json.dump({'candidate_source': CANDIDATE, 'baseline_source': BASELINE,
               'runner_source': RUNNER, 'started_utc': started,
               'finished_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'executed_source_sha256': source, 'commands': commands,
               'scope': 'Fresh paired exact-source operations and separate memory processes. '
                        'Comparison flags remain findings to assess, not an automatic performance pass.'},
              stream, indent=2)
    stream.write('\n')
print('All paired matrices and guarded comparisons complete.', flush=True)
