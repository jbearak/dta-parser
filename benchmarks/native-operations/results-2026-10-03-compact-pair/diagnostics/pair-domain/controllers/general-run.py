#!/usr/bin/env python3
"""Measure general compact arithmetic against typed and ordinary doubles."""
import argparse
from collections import Counter
import csv
import difflib
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import platform
import shutil
import statistics
import subprocess

HERE = Path(__file__).resolve().parent
RECORDS_PATH = Path('<repo>/benchmarks/native-operations/run.py')
SPEC = importlib.util.spec_from_file_location('operation_records', RECORDS_PATH)
RECORDS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RECORDS)
REPRESENTATIONS = ('compact', 'typed_double', 'ordinary')
FIELDS = ('width', 'missing', 'operation', 'representation')
CASE_OPERATIONS = {'int': ('scale_binary', 'mixed_add', 'mixed_multiply'),
                   'float': ('scale_binary', 'scale_general'),
                   'long': ('long_float_add',)}
EXPECTED = {(width, missing, operation, representation)
            for width, operations in CASE_OPERATIONS.items()
            for missing in ('FALSE', 'TRUE') for operation in operations
            for representation in REPRESENTATIONS}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def worker_runtime(rscript):
    # Query the exact launcher used for workers: R on PATH may refer to a
    # different installation. Compare its runtime with both build receipts.
    r_home = Path(subprocess.check_output(
        [str(rscript), '--vanilla', '-e', 'cat(R.home())'], text=True).strip())
    return dict(Rscript_launcher_sha256=sha(rscript),
                R_runtime_sha256=sha(r_home / 'bin/exec/R'),
                R_version=subprocess.check_output(
                    [str(rscript), '--vanilla', '-e', 'cat(R.version.string)'],
                    text=True).strip())


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def write_csv(path, rows):
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def validate_round(rows, round_number, variant):
    keys = Counter(tuple(row[key] for key in FIELDS) for row in rows)
    require(keys == Counter({key: 1 for key in EXPECTED}), 'Incomplete or duplicated case matrix')
    for row in rows:
        require(int(row['round']) == round_number and int(row['n']) == 1000000,
                'Wrong round or input size')
        require(int(row['iterations']) > 0, 'Nonpositive repetition count')
        for metric in ('cpu', 'wall'):
            require(math.isfinite(float(row[metric])) and float(row[metric]) > 0,
                    'Nonpositive or nonfinite timing')
        for key in ('result_sha256', 'missing_sha256', 'input_sha256', 'y_sha256'):
            require(len(row[key]) == 64 and all(c in '0123456789abcdef' for c in row[key]),
                    'Malformed result or source checksum')
        for prefix in ('compact', 'materialized', 'y_compact', 'y_materialized'):
            require(row[prefix + '_before'] == row[prefix + '_after'], 'Changed source state')
        if row['representation'] == 'compact':
            require(row['compact_before'] == 'TRUE' and row['materialized_before'] == 'FALSE',
                    'Compact source was already materialized')
        if variant in ('baseline', 'candidate'):
            expected_calls = 0 if row['representation'] == 'ordinary' else int(row['iterations'])
            require(float(row['native_calls']) == expected_calls, 'Candidate did not use native arithmetic')
    for case in {tuple(row[k] for k in FIELDS[:-1]) for row in rows}:
        selected = [row for row in rows if tuple(row[k] for k in FIELDS[:-1]) == case]
        require({int(row['order']) for row in selected} == {1, 2, 3}, 'Invalid representation order')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--rounds', default=6, type=int)
    args = parser.parse_args()
    require(args.rounds >= 6 and args.rounds % 6 == 0, 'Rounds must be a positive multiple of six')
    require(platform.system() != 'Windows',
            'This benchmark requires the Unix R runtime layout; Windows is not supported')
    found = shutil.which('Rscript')
    require(found is not None, 'Rscript was not found on PATH')
    rscript = Path(found).resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    builds = {'baseline': args.baseline.resolve(), 'candidate': args.candidate.resolve()}
    worker = HERE / 'general-worker.R'
    controllers = {p.name: sha(p) for p in (Path(__file__).resolve(), worker, RECORDS_PATH)}
    before = {name: RECORDS.inventory(build, json.loads((build / 'build-receipt.json').read_text())['variant']) for name, build in builds.items()}
    runtime_before = worker_runtime(rscript)
    require({before[name]['receipt']['toolchain']['R_runtime_sha256'] for name in builds} ==
            {runtime_before['R_runtime_sha256']}, 'Worker runtime differs from package build runtime')
    write_json(output / 'provenance-before.json', dict(builds=before, controllers=controllers, runtime=runtime_before,
        platform=platform.platform(), machine=platform.machine(),
        R=runtime_before['R_version']))
    patch = []
    for name in sorted(set(before['baseline']['source']) | set(before['candidate']['source'])):
        if before['baseline']['source'].get(name) == before['candidate']['source'].get(name):
            continue
        left = builds['baseline'] / 'source' / name
        right = builds['candidate'] / 'source' / name
        a = left.read_text().splitlines(keepends=True) if left.exists() else []
        b = right.read_text().splitlines(keepends=True) if right.exists() else []
        patch.extend(difflib.unified_diff(a, b, fromfile='a/' + name, tofile='b/' + name))
    (output / 'source.patch').write_text(''.join(patch))
    write_json(output / 'protocol.json', dict(experiment='Compact physical-pair range proof; six mixed-pair cases and six unchanged scalar controls', rounds=args.rounds, rows=1000000,
        cases_per_build_round=len(EXPECTED),
        baseline_commit=before['baseline']['receipt']['base_commit'],
        candidate_commit=before['candidate']['receipt']['base_commit'],
        interval='Preloaded public operations. Result allocation and automatic GC included; construction, explicit GC, qualification, hashing and calibration excluded.',
        repetitions='Calibrate at least 25 ms; choose a count targeting at least 150 ms per retained interval.',
        order='Alternate build order each round. Fixed case order; rotate and reverse three representations through all six orders.',
        correctness='Full little-endian binary64 result hashes, independent Stata normalization/promotion/float-rounding oracle, missing masks/cache, storage, source hashes and source states.',
        limits='One host and constructed deterministic columns. Retained chunks, all missing codes and floating boundaries are covered by the correctness suite, not this timing matrix. Typed results impose storage policy beyond bare arithmetic.'))
    rows = []
    for round_number in range(1, args.rounds + 1):
        order = ('baseline', 'candidate') if round_number % 2 else ('candidate', 'baseline')
        for variant in order:
            result = output / f'{round_number:02}-{variant}.csv'
            with (output / f'{round_number:02}-{variant}.log').open('w') as log:
                subprocess.run([str(rscript), '--vanilla', str(worker), str(builds[variant] / 'library'),
                    str(round_number), str(result), 'candidate', 'measure'], stdout=log,
                    stderr=subprocess.STDOUT, check=True)
            with result.open(newline='') as stream:
                batch = list(csv.DictReader(stream))
            validate_round(batch, round_number, variant)
            rows.extend(dict(variant=variant, **row) for row in batch)
            print(f'Completed round {round_number}: {variant}, {len(batch)} observations', flush=True)
    after = {name: RECORDS.inventory(build, json.loads((build / 'build-receipt.json').read_text())['variant']) for name, build in builds.items()}
    runtime_after = worker_runtime(rscript)
    controllers_after = {p.name: sha(p) for p in (Path(__file__).resolve(), worker, RECORDS_PATH)}
    write_json(output / 'provenance-after.json', dict(builds=after, controllers=controllers_after, runtime=runtime_after))
    require(before == after and controllers == controllers_after and runtime_before == runtime_after,
            'Build, worker runtime or controller changed during measurement')
    grouped = {}
    for row in rows:
        grouped.setdefault(tuple(row[k] for k in FIELDS), []).append(row)
    result_fields = ('result_sha256', 'missing_sha256', 'missing_count', 'result_storage',
                     'input_sha256', 'y_sha256', 'compact_before', 'materialized_before',
                     'y_compact_before', 'y_materialized_before')
    for key, batch in grouped.items():
        require(len({tuple(row[k] for k in result_fields) for row in batch}) == 1,
                f'Result, storage or source differs between builds/rounds: {key}')
        for variant in builds:
            selected = [row for row in batch if row['variant'] == variant]
            require(len(selected) == args.rounds, 'Missing repeated observation')
            require(Counter(int(row['order']) for row in selected) == Counter({1: args.rounds//3, 2: args.rounds//3, 3: args.rounds//3}),
                    'Representation positions are not balanced')
    write_csv(output / 'raw.csv', rows)
    summary = []
    for case in sorted({key[:-1] for key in grouped}):
        medians = {}
        for variant in builds:
            for rep in REPRESENTATIONS:
                selected = [row for row in grouped[case + (rep,)] if row['variant'] == variant]
                medians[variant, rep] = statistics.median(float(row['cpu']) / int(row['iterations']) for row in selected)
        for variant in builds:
            selected = {rep: medians[variant, rep] for rep in REPRESENTATIONS}
            per_round_ratio = []
            for round_number in range(1, args.rounds + 1):
                pair = {rep: next(row for row in grouped[case + (rep,)] if row['variant'] == variant and int(row['round']) == round_number)
                        for rep in ('compact', 'typed_double')}
                per_round_ratio.append((float(pair['compact']['cpu']) / int(pair['compact']['iterations'])) /
                                       (float(pair['typed_double']['cpu']) / int(pair['typed_double']['iterations'])))
            summary.append(dict(variant=variant, n=1000000, **dict(zip(FIELDS[:-1], case)), **selected,
                compact_typed_ratio=selected['compact']/selected['typed_double'],
                compact_ordinary_ratio=selected['compact']/selected['ordinary'],
                paired_compact_typed_ratio=statistics.median(per_round_ratio),
                compact_speedup=medians['baseline','compact']/medians['candidate','compact']))
    write_csv(output / 'summary.csv', summary)
    write_json(output / 'completion.json', dict(observations=len(rows), rounds=args.rounds,
        exact_results=True, missing_cache_matches=True, source_state_unchanged=True,
        provenance_unchanged=True, worker_runtime_unchanged=True, source_patch_sha256=sha(output / 'source.patch')))
    print(f'Complete: {len(rows)} qualified observations', flush=True)


if __name__ == '__main__':
    main()
