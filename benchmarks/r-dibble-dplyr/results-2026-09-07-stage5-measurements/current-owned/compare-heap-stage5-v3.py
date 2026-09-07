"""Reverify raw heap checkpoints and derive a paired table without running R."""
import csv
import hashlib
import importlib.util
import itertools
import json
import re
from pathlib import Path
import sys


def require(value, message):
    if not value:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


require(len(sys.argv) == 5, 'Expected repository, baseline, candidate and fresh output')
repo, baseline, candidate, output = map(Path, sys.argv[1:])
require(not output.exists() and not output.is_symlink(), f'Refusing overwrite: {output}')
require(not any(output.resolve().is_relative_to(p.resolve()) for p in [baseline, candidate]),
        'Comparison output must be outside both inputs')

def identity(path):
    resolved = path.resolve(strict=True)
    stat = resolved.stat()
    return dict(path=str(path), resolved=str(resolved), bytes=stat.st_size,
                mode=oct(stat.st_mode & 0o777), sha256=digest(resolved))

def paths(root):
    return {p for p in root.rglob('*') if p.is_file() or p.is_symlink()}

def changed_inputs(before):
    changes = []
    for row in before:
        try:
            current = identity(Path(row['path']))
        except (OSError, RuntimeError) as error:
            changes.append(dict(path=row['path'], error=str(error)))
        else:
            if current != row:
                changes.append(dict(path=row['path'], current=current))
    return changes

inventories = {root: paths(root) for root in [baseline, candidate]}
bound_inputs_before = [identity(path) for path in sorted(set().union(*inventories.values(),
    {Path(__file__).resolve(), Path(sys.executable).resolve(),
     repo/'benchmarks/r-dibble-dplyr/run-heap-qualification.py'}))]

def guard():
    changes = changed_inputs(bound_inputs_before)
    require(not changes, 'Changed comparison inputs: ' + repr(changes))
    for root, expected_paths in inventories.items():
        require(paths(root) == expected_paths, 'Comparison input inventory changed: ' + str(root))
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
    require(manifest['runner_source_sha'] == 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9',
            f'Wrong runner: {root}')
    expected_library = Path('/private/tmp/dta-direct-stage5-validation') / (
        'root-baseline-f622f1d/library' if mode == 'baseline' else 'implementation/candidate-combined-01/library')
    require(manifest['library'] == str(expected_library), f'Wrong library: {root}')
    cases = {}
    for case in manifest['cases']:
        key = (case['kind'], case['rows'], case['operation'])
        require(key not in cases and case['exit_code'] == 0, f'Duplicate/failed case: {key}')
        log = root / case['file']
        require(digest(log) == case['sha256'], f'Changed raw log: {log}')
        text = log.read_text()
        for field, value in [('source_sha', source), ('library', manifest['library']),
                             ('mode', mode), ('kind', case['kind']),
                             ('operation', case['operation']), ('rows', str(case['rows']))]:
            require(re.findall(rf'^heap_{field} (.*?)\s*$', text, re.MULTILINE) == [value],
                    f'Wrong raw runtime identity {field}: {log}')
        metrics, checkpoints = verifier.verify_metrics(text, log)
        require(metrics == case['metrics'] and checkpoints == case['checkpoints'],
                f'Raw/manifest metrics differ: {log}')
        if mode == 'candidate':
            require(metrics['retained_tracked_heap_bytes'] < 1000000 and
                    metrics['excess_tracked_heap_bytes_after_drop_result'] < 1000000,
                    f'Candidate heap exceeds budget: {log}')
        cases[key] = metrics
    require(set(cases) == expected, f'Incomplete matrix: {root}')
    return manifest, cases


a, before = load(baseline, 'baseline', 'f622f1ddba04b2bb7ac07415faccf2b417aab0e6')
b, after = load(candidate, 'candidate', 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9')
require(a['runner_sha256'] == b['runner_sha256'], 'Unpaired runner bytes')
guard()
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
guard()
with (output / 'derivation.json').open('x') as file:
    json.dump({'baseline_manifest': str(baseline / 'root-manifest.json'),
               'baseline_manifest_sha256': digest(baseline / 'root-manifest.json'),
               'candidate_manifest': str(candidate / 'root-manifest.json'),
               'candidate_manifest_sha256': digest(candidate / 'root-manifest.json'),
               'deriver_sha256': digest(Path(__file__)),
               'metric_verifier_sha256': digest(driver),
               'scope': '72 raw logs and all five checkpoint derivations reverified. Tracked R heap only; native external allocation and peak RSS excluded.',
               'inputs_before': bound_inputs_before, 'changed_inputs': changed_inputs(bound_inputs_before),
               'files': {table.name: digest(table)}}, file, indent=2)
    file.write('\n')
guard()
print('36 paired heap cases, 72 raw logs/checkpoint derivations verified; candidate retained/release budgets pass')
