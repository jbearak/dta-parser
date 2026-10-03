#!/usr/bin/env python3
"""Source-bound paired public float comparisons; timing is report-only."""
import argparse
from collections import Counter
import csv
import difflib
import hashlib
import importlib.util
import itertools
import json
import math
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess

HERE = Path('<workspace>/benchmarks/float-comparison')
FIELDS = ('threads', 'missing', 'operation', 'representation')
REPRESENTATIONS = ('compact', 'typed_double', 'ordinary')
CASES = {(threads, missing, operation, representation)
         for threads in ('0', '1') for missing in ('FALSE', 'TRUE')
         for operation in ('pair_less', 'scalar_less', 'pair_equal')
         for representation in REPRESENTATIONS}
RESULT_FIELDS = ('result_hash', 'input_hash', 'y_hash', 'metadata_x', 'metadata_y',
                 'compact_before', 'materialized_before',
                 'y_compact_before', 'y_materialized_before')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_round(rows, round_number):
    if Counter(tuple(row[key] for key in FIELDS) for row in rows) != Counter({key: 1 for key in CASES}):
        raise RuntimeError('Incomplete or repeated comparison case matrix')
    for case in {tuple(row[key] for key in FIELDS[:-1]) for row in rows}:
        positions = [int(row['position']) for row in rows if tuple(row[key] for key in FIELDS[:-1]) == case]
        if sorted(positions) != [1, 2, 3]:
            raise RuntimeError('Repeated representation position within one case')
    for row in rows:
        if int(row['round']) != round_number or int(row['rows']) != 1000000 or int(row['repetitions']) <= 0:
            raise RuntimeError('Invalid round, row count or repetition count')
        if any(not math.isfinite(float(row[k])) or float(row[k]) <= 0 for k in ('cpu', 'wall')):
            raise RuntimeError('Invalid timing interval')
        if int(row['position']) not in (1, 2, 3):
            raise RuntimeError('Invalid representation position')
        for prefix in ('compact', 'materialized', 'y_compact', 'y_materialized'):
            if row[prefix + '_before'] != row[prefix + '_after']:
                raise RuntimeError('Source representation changed')
        compact = row['representation'] == 'compact'
        if (row['compact_before'] != str(compact).upper()
                or row['y_compact_before'] != str(compact).upper()
                or row['materialized_before'] != 'FALSE'
                or row['y_materialized_before'] != 'FALSE'):
            raise RuntimeError('Unexpected input representation')
        if row['native_qualified'] != str(row['representation'] != 'ordinary').upper():
            raise RuntimeError('Native comparison was not qualified')
        for key in ('result_hash', 'input_hash', 'y_hash', 'metadata_x', 'metadata_y'):
            value = row[key]
            if len(value) != 64 or any(c not in '0123456789abcdef' for c in value):
                raise RuntimeError('Invalid full-result or source hash')


def validate_all(rows, rounds):
    for variant in ('baseline', 'candidate'):
        for number in range(1, rounds + 1):
            validate_round([row for row in rows if row['variant'] == variant and int(row['round']) == number], number)
    if len(rows) != 2 * rounds * len(CASES):
        raise RuntimeError('Unexpected observations outside the requested matrix')
    expected_orders = Counter({order: rounds // 6 for order in itertools.permutations(REPRESENTATIONS)})
    for variant in ('baseline', 'candidate'):
        for case in {key[:-1] for key in CASES}:
            orders = []
            for number in range(1, rounds + 1):
                selected = sorted((row for row in rows if row['variant'] == variant and int(row['round']) == number
                                   and tuple(row[key] for key in FIELDS[:-1]) == case), key=lambda row: int(row['position']))
                orders.append(tuple(row['representation'] for row in selected))
            if Counter(orders) != expected_orders:
                raise RuntimeError('Representation permutations are unbalanced')
    for case in CASES:
        selected = [row for row in rows if tuple(row[key] for key in FIELDS) == case]
        if len({tuple(row[key] for key in RESULT_FIELDS) for row in selected}) != 1:
            raise RuntimeError('Result, metadata or source differs across builds or rounds')
        for variant in ('baseline', 'candidate'):
            if Counter(int(row['position']) for row in selected if row['variant'] == variant) != Counter({1: rounds // 3, 2: rounds // 3, 3: rounds // 3}):
                raise RuntimeError('Representation positions are unbalanced')
    # Missing-bearing bare R has a different contract. All typed cases, and
    # missing-free bare controls, must still have identical logical results.
    for threads, missing, operation, _ in CASES:
        selected = [row for row in rows if (row['threads'], row['missing'], row['operation']) == (threads, missing, operation)
                    and (missing == 'FALSE' or row['representation'] != 'ordinary')]
        if len({row['result_hash'] for row in selected}) != 1:
            raise RuntimeError('Equivalent representations disagree')


def inventory(build, variant):
    path = HERE.parent / 'native-operations' / 'run.py'
    spec = importlib.util.spec_from_file_location('native_build_records', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # Experiment roles differ from the original clean-build receipt labels.
    receipt = json.loads((build / 'build-receipt.json').read_text())
    return module.inventory(build, receipt['variant'])


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def write_csv(path, rows):
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def summarize(rows):
    summary = []
    for threads in ('0', '1'):
        for missing in ('FALSE', 'TRUE'):
            for operation in ('pair_less', 'scalar_less', 'pair_equal'):
                result = dict(threads=threads, missing=missing, operation=operation)
                for variant in ('baseline', 'candidate'):
                    for representation in REPRESENTATIONS:
                        selected = [row for row in rows if (row['variant'], row['threads'], row['missing'], row['operation'], row['representation']) == (variant, threads, missing, operation, representation)]
                        for metric in ('cpu', 'wall'):
                            result[f'{variant}_{representation}_{metric}'] = statistics.median(float(row[metric]) / int(row['repetitions']) for row in selected)
                    result[variant + '_compact_typed_cpu'] = result[variant + '_compact_cpu'] / result[variant + '_typed_double_cpu']
                    result[variant + '_compact_bare_cpu'] = result[variant + '_compact_cpu'] / result[variant + '_ordinary_cpu']
                result['compact_cpu_speedup'] = result['baseline_compact_cpu'] / result['candidate_compact_cpu']
                summary.append(result)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=6)
    args = parser.parse_args()
    if args.rounds < 6 or args.rounds % 6:
        parser.error('Rounds must be a positive multiple of six')
    found = shutil.which('Rscript')
    if found is None:
        parser.error('Rscript was not found on PATH')
    rscript = Path(found).resolve(strict=True)
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    builds = {'baseline': args.baseline.resolve(), 'candidate': args.candidate.resolve()}
    worker = Path(__file__).with_name('worker.R')

    def execution_runtime():
        details = subprocess.check_output([str(rscript), '--vanilla', '-e', 'cat(R.home(), \"\\n\", R.version.string, sep=\"\")'], text=True).splitlines()
        home = Path(details[0])
        runtime = home / 'bin' / 'exec' / 'R'
        return {'R_runtime_sha256': digest(runtime), 'Rscript_sha256': digest(rscript), 'R_version': details[1]}

    controllers = {'comparison_controller': Path(__file__).resolve(), 'worker': worker,
                   'build_validation': HERE.parent / 'native-operations' / 'run.py',
                   'build_recorder': HERE.parent / 'r-file-readers' / 'record-builds.py'}

    def binding():
        return {'builds': {variant: inventory(build, variant) for variant, build in builds.items()},
                'execution': execution_runtime(),
                'controllers': {name: digest(path) for name, path in controllers.items()}}

    before = binding()
    if any(before['builds'][variant]['receipt']['toolchain']['R_runtime_sha256'] != before['execution']['R_runtime_sha256'] for variant in builds):
        raise RuntimeError('Build and execution R runtimes differ')
    write_json(out / 'provenance-before.json', before)
    patch = []
    for name in sorted(set(before['builds']['baseline']['source']) | set(before['builds']['candidate']['source'])):
        if before['builds']['baseline']['source'].get(name) == before['builds']['candidate']['source'].get(name):
            continue
        old = builds['baseline'] / 'source' / name
        new = builds['candidate'] / 'source' / name
        patch.extend(difflib.unified_diff(old.read_text().splitlines(keepends=True) if old.exists() else [],
                                         new.read_text().splitlines(keepends=True) if new.exists() else [],
                                         fromfile='a/' + name, tofile='b/' + name))
    (out / 'source.patch').write_text(''.join(patch))
    write_json(out / 'protocol.json', {
        'rounds': args.rounds, 'cases_per_build_round': len(CASES),
        'host': platform.platform(), 'machine': platform.machine(), 'logical_cpus': os.cpu_count(),
        'R': before['execution']['R_version'],
        'order': 'Alternate build order in fresh R processes; rotate and reverse representations across six rounds. Fixed case order.',
        'interval': 'Repeated public comparisons, output allocation and automatic GC included. Construction, explicit GC, calibration, separate native qualification and full value/metadata/state hashing excluded.',
        'repetitions': 'At least 50 ms calibration; fixed count targets 300 ms retained CPU interval.',
        'limits': 'One host; warm million-row retained float columns, X chunks 8191 rows and Y chunks 16385 rows. Missing-bearing bare R retains NA propagation and has a different contract. Threads 0 means automatic scheduling. No claim for readers, temporal inputs, arbitrary imported bytes or arbitrary chunk geometry.'})
    rows = []
    for number in range(1, args.rounds + 1):
        for variant in (('baseline', 'candidate') if number % 2 else ('candidate', 'baseline')):
            result = out / f'{number:02}-{variant}.csv'
            with (out / f'{number:02}-{variant}.log').open('w') as stream:
                subprocess.run([str(rscript), '--vanilla', str(worker), str(builds[variant] / 'library'), str(number), str(result)], stdout=stream, stderr=subprocess.STDOUT, check=True)
            with result.open(newline='') as stream:
                batch = list(csv.DictReader(stream))
            validate_round(batch, number)
            rows.extend(dict(variant=variant, **row) for row in batch)
            print(f'Completed round {number}: {variant}', flush=True)
    after = binding()
    write_json(out / 'provenance-after.json', after)
    write_csv(out / 'raw.csv', rows)
    if before != after:
        raise RuntimeError('Build or controller changed during timing')
    validate_all(rows, args.rounds)
    summary = summarize(rows)
    write_csv(out / 'summary.csv', summary)
    write_json(out / 'completion.json', {'observations': len(rows), 'exact_results': True, 'provenance_unchanged': True,
               'source_patch_sha256': digest(out / 'source.patch'),
               'candidate_max_compact_typed_cpu': max(row['candidate_compact_typed_cpu'] for row in summary),
               'candidate_max_missing_free_compact_bare_cpu': max(row['candidate_compact_bare_cpu'] for row in summary if row['missing'] == 'FALSE')})


if __name__ == '__main__':
    main()
