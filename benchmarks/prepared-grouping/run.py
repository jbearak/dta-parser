#!/usr/bin/env python3
"""Measure qualified grouping operations from two clean source-bound builds."""
import argparse
from collections import Counter
import csv
from decimal import Decimal, InvalidOperation
import difflib
import importlib.util
import itertools
import math
import os
from pathlib import Path
import platform
import statistics
import subprocess

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('native_operations', HERE.parent / 'native-operations/run.py')
NATIVE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NATIVE)
FIELDS = ('n', 'width', 'key_count', 'layout', 'representation')
EXPECTED = {
    (str(n), width, str(keys), layout, representation)
    for n in (100000, 1000000)
    for width in (('byte', 'int', 'long', 'float') if n == 100000 else ('int', 'float'))
    for keys in ((1, 4) if n == 100000 else (1,))
    for layout in ('random', 'sorted')
    for representation in ('compact', 'typed_double', 'ordinary')
}


def exact_nonnegative_integer(text):
    try:
        value = Decimal(text)
    except InvalidOperation as error:
        raise RuntimeError('invalid integer field') from error
    if (not value.is_finite() or value < 0 or value > 2**63 - 1 or
            value != value.to_integral_value()):
        raise RuntimeError('integer field must be finite, nonnegative and exact')
    return int(value)


def validate_round(rows, round_number, variant):
    observed = Counter(tuple(row[k] for k in FIELDS) for row in rows)
    if observed != Counter({key: 1 for key in EXPECTED}):
        raise RuntimeError('worker case matrix is incomplete, duplicated, or unexpected')
    for row in rows:
        if row['phase'] != 'timing' or int(row['round']) != round_number or int(row['iterations']) <= 0:
            raise RuntimeError('invalid worker round or repetitions')
        if any(not math.isfinite(float(row[k])) or float(row[k]) <= 0
               for k in ('cpu_seconds', 'elapsed_seconds')):
            raise RuntimeError('invalid retained interval')
        key_bytes = 8 * int(row['n']) * int(row['key_count'])
        if exact_nonnegative_integer(row['key_cache_bytes']) != key_bytes:
            raise RuntimeError('incorrect key-cache accounting')
        if variant == 'candidate' and (exact_nonnegative_integer(row['scalar_values']) != 0 or
                exact_nonnegative_integer(row['prepared_values']) != key_bytes // 8 or
                exact_nonnegative_integer(row['prepared_bytes']) != key_bytes):
            raise RuntimeError('candidate did not prepare exactly one value per row and key')
    for case in {tuple(row[k] for k in FIELDS[:-1]) for row in rows}:
        orders = [int(row['order']) for row in rows if tuple(row[k] for k in FIELDS[:-1]) == case]
        if sorted(orders) != [1, 2, 3]:
            raise RuntimeError('invalid representation positions')


def validate_balance(rows, rounds):
    expected_orders = Counter({order: rounds // 6 for order in
        itertools.permutations(('compact', 'typed_double', 'ordinary'))})
    for variant in ('baseline', 'candidate'):
        for case in {tuple(row[k] for k in FIELDS[:-1]) for row in rows}:
            selected = [row for row in rows if row['variant'] == variant and
                        tuple(row[k] for k in FIELDS[:-1]) == case]
            orders = []
            for round_number in range(1, rounds + 1):
                batch = sorted((row for row in selected if int(row['round']) == round_number),
                               key=lambda row: int(row['order']))
                orders.append(tuple(row['representation'] for row in batch))
            if Counter(orders) != expected_orders:
                raise RuntimeError('representation permutations are not balanced')


def validate_results(rows):
    # Compare all result bits and public metadata, not sample checksums.
    groups = {}
    for row in rows:
        groups.setdefault(tuple(row[k] for k in FIELDS), []).append(row)
    identity = ('result_sha256', 'metadata_sha256', 'result_storage',
                'source_sha256', 'ranks_sha256', 'source_state_sha256')
    for key, observations in groups.items():
        if len({tuple(row[k] for k in identity) for row in observations}) != 1:
            raise RuntimeError(f'qualification differs across builds or rounds: {key}')
    return groups


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=6)
    args = parser.parse_args()
    if args.rounds < 6 or args.rounds % 6:
        parser.error('rounds must be a positive multiple of six')
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    builds = {name: getattr(args, name).resolve() for name in ('baseline', 'candidate')}
    before = {name: NATIVE.inventory(build, name) for name, build in builds.items()}
    controllers = (Path(__file__).resolve(), HERE / 'worker.R', HERE.parent / 'native-operations/run.py',
                   HERE.parent / 'r-file-readers/record-builds.py')
    controller_hashes = {str(path.relative_to(HERE.parent)): NATIVE.digest(path) for path in controllers}
    NATIVE.write_json(out / 'provenance-before.json', dict(builds=before,
        controllers=controller_hashes, platform=platform.platform(), machine=platform.machine(),
        logical_cpus=os.cpu_count(), R=subprocess.check_output(['R', '--version'], text=True).splitlines()[0]))
    patch = []
    for name in sorted(set(before['baseline']['source']) | set(before['candidate']['source'])):
        if before['baseline']['source'].get(name) == before['candidate']['source'].get(name):
            continue
        paths = [builds[v] / 'source' / name for v in ('baseline', 'candidate')]
        contents = [p.read_text().splitlines(keepends=True) if p.exists() else [] for p in paths]
        patch.extend(difflib.unified_diff(*contents, fromfile='a/' + name, tofile='b/' + name))
    (out / 'source.patch').write_text(''.join(patch))
    NATIVE.write_json(out / 'protocol.json', dict(rounds=args.rounds, cases_per_build=len(EXPECTED),
        baseline_commit=before['baseline']['receipt']['base_commit'],
        candidate_commit=before['candidate']['receipt']['base_commit'],
        interval='Repeated public dta_group_id calls; dispatch, allocation, automatic GC included. Construction, oracle, explicit GC, qualification, calibration, hashes and memory diagnostic excluded.',
        inputs='Deterministic constructed columns, system missing plus .a/.z. Sorted and random cases share the same samples. Compact sources use contiguous constructor storage.',
        order='Alternate builds. Rotate and reverse three representations over six rounds. Fixed width/key/layout order.',
        calibration='At least 25 ms untimed calibration, fixed repetitions targeting 150 ms retained interval.',
        memory='Exact 8*n*k prepared-key payload plus separate single-call R Vcells high-water increase. The latter includes result/sort/scratch allocations, excludes node and external allocator memory, and is not process RSS.',
        limits='One host, warm constructed operations, missing=TRUE, autotype=FALSE, label=FALSE. No reader timing, mixed string keys, foreign ALTREP, or process-peak claim.'))
    rows = []
    for round_number in range(1, args.rounds + 1):
        for variant in (('baseline', 'candidate') if round_number % 2 else ('candidate', 'baseline')):
            result = out / f'{round_number:02}-{variant}.csv'
            command = ['Rscript', '--vanilla', str(HERE / 'worker.R'), str(builds[variant] / 'library'),
                       str(round_number), str(result)]
            with (out / f'{round_number:02}-{variant}.log').open('w') as log:
                subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
            with result.open(newline='') as stream:
                observed = list(csv.DictReader(stream))
            validate_round(observed, round_number, variant)
            rows.extend(dict(variant=variant, **row) for row in observed)
            print(f'Completed round {round_number}: {variant}', flush=True)
    after = {name: NATIVE.inventory(build, name) for name, build in builds.items()}
    hashes_after = {str(path.relative_to(HERE.parent)): NATIVE.digest(path) for path in controllers}
    NATIVE.write_json(out / 'provenance-after.json', dict(builds=after, controllers=hashes_after))
    if before != after or controller_hashes != hashes_after:
        raise RuntimeError('build or controller changed during measurements')
    NATIVE.write_csv(out / 'raw.csv', rows)
    validate_balance(rows, args.rounds)
    groups = validate_results(rows)
    summary = []
    for key, observed in sorted(groups.items()):
        row = dict(zip(FIELDS, key))
        for variant in builds:
            selected = [r for r in observed if r['variant'] == variant]
            for metric in ('cpu_seconds', 'elapsed_seconds'):
                row[variant + '_' + metric] = statistics.median(float(r[metric]) / int(r['iterations']) for r in selected)
            row[variant + '_peak_vcell_bytes'] = statistics.median(float(r['peak_vcell_bytes']) for r in selected)
        row['cpu_speedup'] = row['baseline_cpu_seconds'] / row['candidate_cpu_seconds']
        row['key_cache_bytes'] = exact_nonnegative_integer(observed[0]['key_cache_bytes'])
        summary.append(row)
    NATIVE.write_csv(out / 'summary.csv', summary)
    NATIVE.write_json(out / 'completion.json', dict(observations=len(rows), exact_results=True,
        provenance_unchanged=True, source_patch_sha256=NATIVE.digest(out / 'source.patch')))


if __name__ == '__main__':
    main()
