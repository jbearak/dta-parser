#!/usr/bin/env python3
"""Run and bind the 204 untimed final acceptance qualifications."""
from collections import Counter
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
CONTROLLER = HERE / 'acceptance-controller/general-run.py'
SPEC = importlib.util.spec_from_file_location('final_acceptance', CONTROLLER)
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)
BUILDS = {
    'baseline': Path('<baseline-build>'),
    'candidate': Path('<candidate-build>'),
}

def require(value, message):
    if not value:
        raise RuntimeError(message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def snapshot():
    records = {role: RUN.RECORDS.inventory(build, 'baseline') for role, build in BUILDS.items()}
    require({role: value['receipt']['base_commit'] for role, value in records.items()} == RUN.COMMITS,
            'Unexpected clean build source')
    runtime = RUN.worker_runtime(launcher)
    require({record['receipt']['toolchain']['R_runtime_sha256'] for record in records.values()} ==
            {runtime['R_runtime_sha256']}, 'Worker runtime differs from build runtime')
    files = [CONTROLLER, worker, RUN.RECORDS_PATH, Path(__file__).resolve(),
             CONTROLLER.with_name('test-general-run.py'), CONTROLLER.with_name('README.md'),
             *RUN.RECORDER_DEPENDENCIES]
    return {'builds': records, 'runtime': runtime, 'controller_sha256': {str(p): sha(p) for p in files}}

found = shutil.which('Rscript')
require(found is not None, 'Rscript unavailable')
launcher = Path(found).resolve(strict=True)
worker = CONTROLLER.with_name('general-worker.R')
before = snapshot()
paths = [HERE / f'acceptance-{role}-qualification.{suffix}' for role in BUILDS for suffix in ('csv', 'log')]
require(not any(p.exists() for p in paths), 'Qualification output already exists')
(HERE / 'acceptance-qualification-before.json').write_text(json.dumps(before, indent=2, sort_keys=True) + '\n')
results = {}
for role, build in BUILDS.items():
    output = HERE / f'acceptance-{role}-qualification.csv'
    with output.with_suffix('.log').open('w') as log:
        subprocess.run([str(launcher), '--vanilla', str(worker), str(build / 'library'),
                        '1', str(output), 'candidate', 'qualify'], stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    with output.open(newline='') as stream:
        rows = list(csv.DictReader(stream))
    require(Counter(tuple(row[k] for k in RUN.FIELDS) for row in rows) ==
            Counter({key: 1 for key in RUN.EXPECTED}), 'Incomplete qualification matrix')
    for row in rows:
        require(row['cpu'] == row['wall'] == 'NA' and row['iterations'] == '1',
                'Untimed qualification contains timing')
        require(row['native_calls'] == ('0' if row['representation'] == 'ordinary' else '1'),
                'Qualification used unexpected native route')
        require(row['mutation_checked'] == ('FALSE' if row['representation'] == 'ordinary' else 'TRUE'),
                'Missing count mutation check absent')
    # Reuse the controller's matrix/hash/state/entry validators without claiming
    # any measured interval: only these in-memory copies receive placeholders.
    RUN.validate_round([dict(row, cpu='1', wall='1') for row in rows], 1, role)
    results[role] = rows
    print(f'{role}: {len(rows)} untimed qualifications passed', flush=True)
require(results['baseline'] == results['candidate'], 'Builds differ in qualification semantics')
after = snapshot()
require(before == after, 'Runtime, build or controller changed during qualification')
(HERE / 'acceptance-qualification-after.json').write_text(json.dumps(after, indent=2, sort_keys=True) + '\n')
completion = {
    'status': 'PASS', 'scope': 'Untimed acceptance qualification only; no performance measurements.',
    'cases_per_build': len(RUN.EXPECTED), 'total': sum(map(len, results.values())),
    'exact_results_and_missing_caches': True, 'source_state_unchanged': True,
    'native_routes_checked_in_both_builds': True, 'provenance_unchanged': True,
    'input_sha256': {str(p): sha(p) for p in paths + [HERE / 'acceptance-qualification-before.json',
                                                   HERE / 'acceptance-qualification-after.json']},
}
(HERE / 'acceptance-qualification-completion.json').write_text(json.dumps(completion, indent=2, sort_keys=True) + '\n')
print(json.dumps({k: v for k, v in completion.items() if k != 'input_sha256'}))
