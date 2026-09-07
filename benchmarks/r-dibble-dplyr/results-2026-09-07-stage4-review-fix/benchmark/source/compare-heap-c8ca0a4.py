"""Reverify raw heap checkpoints and derive a paired table without running R."""
import csv
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import sys


def require(value, message):
    if not value:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


repo, baseline, candidate, output = map(Path, sys.argv[1:])
driver = repo / 'benchmarks/r-dibble-dplyr/run-heap-qualification.py'
require(digest(driver) == '16c9dd392abe7fa31f074e49fc927eb05218d7b0a10b9b2d257303e01f64390b',
        'Changed reviewed metric verifier')
spec = importlib.util.spec_from_file_location('heap_verifier', driver)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)
expected = set(itertools.product(
    ['double', 'string', 'declared_character', 'logical', 'factor', 'ordered'],
    [100000, 1000000], ['rename', 'pipeline_five', 'pipeline_50']))


def load(root, mode, source):
    manifest = json.loads((root / 'root-manifest.json').read_text())
    require(manifest['mode'] == mode and manifest['source_sha'] == source,
            f'Wrong source/direction: {root}')
    require(manifest['runner_source_sha'] == 'c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe',
            f'Wrong runner: {root}')
    cases = {}
    for case in manifest['cases']:
        key = (case['kind'], case['rows'], case['operation'])
        require(key not in cases and case['exit_code'] == 0, f'Duplicate/failed case: {key}')
        log = root / case['file']
        require(digest(log) == case['sha256'], f'Changed raw log: {log}')
        metrics, checkpoints = verifier.verify_metrics(log.read_text(), log)
        require(metrics == case['metrics'] and checkpoints == case['checkpoints'],
                f'Raw/manifest metrics differ: {log}')
        if mode == 'candidate':
            require(metrics['retained_tracked_heap_bytes'] < 1000000 and
                    metrics['excess_tracked_heap_bytes_after_drop_result'] < 1000000,
                    f'Candidate heap exceeds budget: {log}')
        cases[key] = metrics
    require(set(cases) == expected, f'Incomplete matrix: {root}')
    return manifest, cases


a, before = load(baseline, 'baseline', 'ec10a6ac34602f3bd691e8043019c1b479babda4')
b, after = load(candidate, 'candidate', 'c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe')
require(a['runner_sha256'] == b['runner_sha256'], 'Unpaired runner bytes')
require(not output.exists(), f'Refusing overwrite: {output}')
records = []
for key in sorted(expected):
    row = dict(zip(['kind', 'rows', 'operation'], key))
    for label, cases in [('baseline', before), ('candidate', after)]:
        row.update({label + '_' + name: value for name, value in cases[key].items()})
    records.append(row)
output.mkdir(parents=True)
table = output / 'heap-comparison.csv'
with table.open('x') as file:
    writer = csv.DictWriter(file, fieldnames=records[0])
    writer.writeheader()
    writer.writerows(records)
with (output / 'derivation.json').open('x') as file:
    json.dump({'baseline_manifest': str(baseline / 'root-manifest.json'),
               'baseline_manifest_sha256': digest(baseline / 'root-manifest.json'),
               'candidate_manifest': str(candidate / 'root-manifest.json'),
               'candidate_manifest_sha256': digest(candidate / 'root-manifest.json'),
               'deriver_sha256': digest(Path(__file__)),
               'metric_verifier_sha256': digest(driver),
               'scope': '72 raw logs and all five checkpoint derivations reverified. Tracked R heap only; native external allocation and peak RSS excluded.',
               'files': {table.name: digest(table)}}, file, indent=2)
    file.write('\n')
print('36 paired heap cases, 72 raw logs/checkpoint derivations verified; candidate retained/release budgets pass')
