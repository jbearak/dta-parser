#!/usr/bin/env python3
"""Bind the integrated compact-pair acceptance setup, without measurements."""
from collections import Counter
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = Path('<repo>')
EXPECTED_HEAD = 'af9f76e3eb3b0b0328ec6609ddb017d42edb3c9d'
EXPECTED_BASELINE = '8e4e1cf957558d727a3b8b092df05d2f3dca2f8d'


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    controller = HERE / 'acceptance-controller/general-run.py'
    spec = importlib.util.spec_from_file_location('acceptance_controller', controller)
    run = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(run)
    builds = {role: HERE / ('acceptance-' + role) for role in ('baseline', 'candidate')}
    inventories = {role: run.RECORDS.inventory(build, role) for role, build in builds.items()}
    for role, commit in [('baseline', EXPECTED_BASELINE), ('candidate', EXPECTED_HEAD)]:
        require(inventories[role]['receipt']['base_commit'] == commit, 'Unexpected build commit')
        require((builds[role] / 'source.patch').read_bytes() == b'', 'Build is not a clean source snapshot')
    package = ROOT / 'r-package/dtatools'
    expected = inventories['candidate']['source']
    current = {str(path.relative_to(package)): sha(path) for path in package.rglob('*') if path.is_file()}
    require(current == expected, 'Current source differs from clean candidate build')
    require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == EXPECTED_HEAD,
            'Unexpected current commit')
    launcher = Path(shutil.which('Rscript')).resolve(strict=True)
    runtime = run.worker_runtime(launcher)
    require({row['receipt']['toolchain']['R_runtime_sha256'] for row in inventories.values()} ==
            {runtime['R_runtime_sha256']}, 'Qualification runtime differs from both builds')
    qualifications = {}
    common_rows = None
    for role in builds:
        path = HERE / ('acceptance-' + role + '-qualification.csv')
        rows = list(csv.DictReader(path.open()))
        require(Counter(tuple(row[key] for key in run.FIELDS) for row in rows) ==
                Counter({key: 1 for key in run.EXPECTED}), 'Incorrect qualification matrix')
        for row in rows:
            require(row['cpu'] == 'NA' and row['wall'] == 'NA' and row['iterations'] == '1',
                    'Qualification includes a timing')
            require(row['native_calls'] == ('0' if row['representation'] == 'ordinary' else '1'),
                    'Qualification did not take expected native route')
            require(row['n'] == '1000000' and row['round'] == '1', 'Wrong input geometry')
            for prefix in ('compact', 'materialized', 'y_compact', 'y_materialized'):
                require(row[prefix + '_before'] == row[prefix + '_after'], 'Source state changed')
            for key in ('result_sha256', 'missing_sha256', 'input_sha256', 'y_sha256'):
                require(re.fullmatch('[0-9a-f]{64}', row[key]), 'Malformed semantic hash')
        require(common_rows is None or common_rows == rows, 'Qualification differs between builds')
        common_rows = rows
        qualifications[role] = dict(rows=len(rows), sha256=sha(path))
    path = HERE / 'acceptance-full-tests.csv'
    observations = list(csv.DictReader(path.open()))
    totals = {key: sum(int(row[key]) if key in ('passed', 'failed', 'warning') else row[key] == 'TRUE'
                       for row in observations) for key in ('passed', 'failed', 'error', 'skipped', 'warning')}
    require(totals['passed'] > 95000 and not any(totals[key] for key in ('failed', 'error', 'skipped')),
            'Full suite failed or is incomplete')
    manifest_path = package / 'tools/native-test-manifest.json'
    manifest = json.loads(manifest_path.read_text())
    for entry in [*manifest['helpers'], *manifest['fixtures'],
                  *(entry for family in manifest['families'] for entry in family['files'])]:
        require(sha(package / entry['path']) == entry['sha256'], 'Manifest source hash differs')
    seen = Counter()
    observed_keys = {}
    for row in observations:
        key = (row['file'], row['test'])
        seen[key] += 1
        observed_keys[key + (seen[key],)] = row
    blocks = [block for family in manifest['families'] for block in family['blocks']]
    require(len(blocks) == len(observations), 'Full manifest block count differs')
    for block in blocks:
        key = (block['file'], block['test'], block.get('occurrence', 1))
        require(key in observed_keys, 'Manifest block not observed')
        row = observed_keys[key]
        require(int(row['passed']) >= block['min_pass'], 'Observed block below declared minimum')
        if block['skip'] == 'forbid':
            require(int(row['warning']) == block['warnings'], 'Unexpected manifest warnings')
    conformance = HERE / 'acceptance-conformance.log'
    require('R package conformance: PASS' in conformance.read_text(), 'Required conformance did not pass')
    paths = [Path(__file__).resolve(), controller, controller.with_name('general-worker.R'),
             controller.with_name('test-general-run.py'), run.RECORDS_PATH,
             ROOT / 'scripts/refresh-r-native-manifest.py', ROOT / 'scripts/test_native_manifest.py',
             manifest_path, Path('<prior-arithmetic-work>/acceptance-v2-full-tests.R')]
    paths.extend(HERE / name for name in ('acceptance-full-tests.csv', 'acceptance-full-tests.log',
                 'acceptance-conformance.log', 'acceptance-controller-tests.log',
                 'acceptance-controller-tests-optimized.log', 'acceptance-native-manifest-tests.log',
                 'acceptance-baseline-qualification.csv', 'acceptance-candidate-qualification.csv'))
    result = dict(status='PASS', scope='Untimed final acceptance setup. Source-bound builds, full-suite and packaged conformance, full original102-case qualification. No performance claim.',
                  current_head=EXPECTED_HEAD, builds=inventories, runtime=runtime,
                  qualification=qualifications, full_suite=dict(totals=totals, blocks=len(blocks)),
                  current_source_equals_candidate=True, input_sha256={str(path): sha(path) for path in paths})
    target = HERE / 'acceptance-validation-binding.json'
    target.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(dict(status='PASS', full_suite=totals, blocks=len(blocks), qualification_each=102,
                         source_files=len(expected), receipt=str(target))))


if __name__ == '__main__':
    main()
