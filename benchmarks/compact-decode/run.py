#!/usr/bin/env python3
"""Compare compact decoding with shared inputs and fresh DATAPTR_RO results."""
import argparse
from collections import Counter
import csv
import difflib
from decimal import Decimal, InvalidOperation
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

HERE = Path(__file__).resolve().parent
MATERIAL_PATH = HERE.parent / 'compact-materialization/run.py'
SPEC = importlib.util.spec_from_file_location('materialization_records', MATERIAL_PATH)
MATERIAL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MATERIAL)
NATIVE, PROBE = MATERIAL.NATIVE, MATERIAL.PROBE
FIELDS = ('n', 'width', 'backing', 'density')
WIDTHS = dict(byte=1, int=2, long=4, float=4)
DENSITIES = ('none', 'sparse', 'dense')
PERMUTATIONS = tuple(itertools.permutations(DENSITIES))
EXPECTED = {('1000000', width, backing, density) for width in WIDTHS
            for backing in ('constructed', 'retained') for density in DENSITIES}
MISSING_COUNTS = dict(none=0, sparse=62, dense=843750)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def integer(value):
    try:
        number = Decimal(value)
    except InvalidOperation as error:
        raise RuntimeError("Invalid integer observation") from error
    require(number.is_finite() and number == number.to_integral_value(),
            "Invalid integer observation")
    return int(number)


def runtime_binding():
    launcher = shutil.which('Rscript')
    require(launcher is not None, 'Rscript is unavailable')
    launcher = os.path.abspath(launcher)
    home = Path(subprocess.check_output([launcher, '--vanilla', '-e', 'cat(R.home())'],
                                        text=True).strip())
    return dict(Rscript_launcher=launcher, Rscript_launcher_sha256=NATIVE.digest(Path(launcher)),
                R_runtime_sha256=NATIVE.digest(home / 'bin/exec/R'))


def inventory(build):
    receipt = json.loads((build / 'build-receipt.json').read_text())
    return NATIVE.inventory(build, receipt['variant'])


def validate_round(rows, round_number, phase):
    require(Counter(tuple(row[k] for k in FIELDS) for row in rows) ==
            Counter({case: 1 for case in EXPECTED}), 'Incomplete or duplicated matrix')
    for row in rows:
        require(row['phase'] == phase and integer(row['round']) == round_number, 'Wrong phase or round')
        require(row['sharing'] == 'aliased' and integer(row['batch_size']) == 32, 'Wrong ownership or batch policy')
        require(integer(row['missing_count']) == MISSING_COUNTS[row['density']], 'Wrong missing density')
        require(integer(row['order']) == PERMUTATIONS[(round_number - 1) % 6].index(row['density']) + 1,
                'Wrong density permutation')
        backings = ('constructed', 'retained') if round_number % 2 else ('retained', 'constructed')
        require(integer(row['backing_order']) == backings.index(row['backing']) + 1, 'Wrong backing order')
        n = integer(row['n'])
        require(integer(row['compact_payload_bytes']) == n * WIDTHS[row['width']] and
                integer(row['double_payload_bytes']) == 8 * n, 'Wrong payload accounting')
        require(all(float(row[k]) == 0 for k in ('compact_copy_bytes', 'compatibility_bytes',
                                                 'timed_compact_copy_bytes')), 'Unexpected input copy')
        require(integer(row['retained_chunks']) == (math.ceil(n / 8191) if row['backing'] == 'retained' else 0),
                'Wrong retained geometry')
        for key in ('source_sha256', 'result_sha256'):
            require(len(row[key]) == 64 and all(c in '0123456789abcdef' for c in row[key]), 'Malformed value hash')
        require(row['source_sha256'] == row['result_sha256'], 'Value bits changed')
        require(all(row[k] == 'TRUE' for k in ('alias_independent', 'source_unmaterialized_before',
            'source_unmaterialized_after', 'targets_unmaterialized_before',
            'targets_materialized_after')), 'Ownership check failed')
        for key in ('r_profiled_allocation_bytes', 'r_largest_allocation_bytes',
                    'r_profiled_allocations', 'peak_vcell_bytes'):
            require(math.isfinite(float(row[key])) and float(row[key]) > 0, 'Invalid allocation observation')
        require(float(row['r_profiled_allocation_bytes']) >= float(row['r_largest_allocation_bytes']) >= 8 * n,
                'Profile does not include the double output')
        require(math.isfinite(float(row['live_vcell_delta_bytes'])), 'Nonfinite live heap observation')
        if phase == 'qualification':
            require(all(float(row[k]) == 0 for k in ('iterations', 'batches', 'cpu_seconds',
                'elapsed_seconds', 'gc_cpu_seconds')), 'Qualification unexpectedly collected times')
            continue
        iterations, batches = integer(row['iterations']), integer(row['batches'])
        require(0 < batches <= 1000 and iterations == batches * 32, 'Wrong first-result count')
        for key in ('cpu_seconds', 'elapsed_seconds'):
            require(math.isfinite(float(row[key])) and float(row[key]) >= .15, 'Invalid retained interval')
        require(math.isfinite(float(row['gc_cpu_seconds'])) and
                0 <= float(row['gc_cpu_seconds']) <= float(row['cpu_seconds']) + .01, 'Invalid GC observation')


def validate_intervals(rows, intervals, round_number):
    grouped = {}
    for interval in intervals:
        key = tuple(interval[k] for k in FIELDS)
        require(key in EXPECTED and integer(interval['round']) == round_number, 'Unknown interval')
        require(interval['sharing'] == 'aliased' and integer(interval['handles']) == 32 and
                float(interval['compact_copy_bytes']) == 0, 'Interval contract changed')
        for metric in ('cpu_seconds', 'elapsed_seconds', 'gc_cpu_seconds'):
            require(math.isfinite(float(interval[metric])) and float(interval[metric]) >= 0, 'Invalid interval')
        require(float(interval['gc_cpu_seconds']) <= float(interval['cpu_seconds']) + .01, 'GC exceeds CPU')
        grouped.setdefault(key, []).append(interval)
    require(set(grouped) == EXPECTED, 'Incomplete interval matrix')
    for row in rows:
        batch = grouped[tuple(row[k] for k in FIELDS)]
        require(Counter(integer(r['batch']) for r in batch) == Counter(range(1, integer(row['batches']) + 1)),
                'Missing or duplicated batch')
        for metric in ('cpu_seconds', 'elapsed_seconds', 'gc_cpu_seconds'):
            require(math.isclose(sum(float(r[metric]) for r in batch), float(row[metric]),
                                 rel_tol=1e-10, abs_tol=1e-10), 'Interval sum differs')
        for metric, zero in (('cpu_seconds', 'zero_cpu_batches'), ('elapsed_seconds', 'zero_wall_batches')):
            values = [float(r[metric]) for r in batch]
            for name, expected in (('min', min(values)), ('max', max(values))):
                require(math.isclose(float(row[name + '_batch_' + metric]), expected,
                    rel_tol=1e-10, abs_tol=1e-10), 'Interval range differs')
            require(integer(row[zero]) == sum(v == 0 for v in values), 'Zero interval count differs')


def validate_results(rows, rounds):
    grouped = {}
    for row in rows:
        grouped.setdefault(tuple(row[k] for k in FIELDS), []).append(row)
    require(set(grouped) == EXPECTED, 'Incomplete aggregate matrix')
    for batch in grouped.values():
        require(len(batch) == 2 * rounds, 'Wrong aggregate count')
        require(len({(r['source_sha256'], r['result_sha256'], r['retained_chunks']) for r in batch}) == 1,
                'Sources or results differ across builds/rounds')
        for variant in ('baseline', 'candidate'):
            selected = [r for r in batch if r['variant'] == variant]
            require(Counter(integer(r['round']) for r in selected) == Counter(range(1, rounds + 1)),
                    'Missing or repeated build round')
            if rounds > 1:
                require(Counter(integer(r['order']) for r in selected) ==
                        Counter({position: rounds // 3 for position in (1, 2, 3)}), 'Unbalanced density positions')
                require(Counter(integer(r['backing_order']) for r in selected) ==
                        Counter({1: rounds // 2, 2: rounds // 2}), 'Unbalanced backing positions')
    for width in WIDTHS:
        for density in DENSITIES:
            require(len({r['result_sha256'] for r in rows
                         if r['width'] == width and r['density'] == density}) == 1,
                    'Backing changed values')
    return grouped


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('baseline', 'candidate', 'probe', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=6)
    parser.add_argument('--qualify-only', action='store_true')
    args = parser.parse_args()
    require(args.rounds >= 6 and args.rounds % 6 == 0, 'Use six rounds or a multiple of six')
    rounds = 1 if args.qualify_only else args.rounds
    phase = 'qualification' if args.qualify_only else 'timing'
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    builds = {v: getattr(args, v).resolve() for v in ('baseline', 'candidate')}
    probe = args.probe.resolve()
    before = {v: inventory(build) for v, build in builds.items()}
    probe_before, runtime_before = PROBE.verify(probe), runtime_binding()
    require(len({before[v]['receipt']['toolchain']['R_runtime_sha256'] for v in builds} |
                {probe_before['receipt']['toolchain']['R_runtime_sha256'], runtime_before['R_runtime_sha256']}) == 1,
            'Probe, builds and worker runtime differ')
    controllers = (Path(__file__).resolve(), HERE / 'worker.R', MATERIAL_PATH,
        HERE.parent / 'compact-materialization/probe.c', HERE.parent / 'compact-materialization/build-probe.py',
        HERE.parent / 'native-operations/run.py', HERE.parent / 'r-file-readers/record-builds.py',
        HERE.parent / 'r-file-readers/build-snapshot.py', HERE.parent / 'io-optimization/record-builds.py')
    hashes = {str(p.relative_to(HERE.parent)): NATIVE.digest(p) for p in controllers}
    NATIVE.write_json(output / 'provenance-before.json', dict(builds=before, probe=probe_before,
        runtime=runtime_before, controllers=hashes, platform=platform.platform(), machine=platform.machine()))
    patch = []
    for name in sorted(set(before['baseline']['source']) | set(before['candidate']['source'])):
        if before['baseline']['source'].get(name) == before['candidate']['source'].get(name):
            continue
        paths = [builds[v] / 'source' / name for v in ('baseline', 'candidate')]
        content = [p.read_text().splitlines(keepends=True) if p.exists() else [] for p in paths]
        patch.extend(difflib.unified_diff(*content, fromfile='a/' + name, tofile='b/' + name))
    (output / 'source.patch').write_text(''.join(patch))
    NATIVE.write_json(output / 'protocol.json', dict(rounds=rounds, phase=phase, cases_per_build_round=24,
        interval='One shared external DATAPTR_RO probe forces 32 fresh metadata handles per batch. Every handle allocates and decodes its own double result. Includes output allocation and automatic GC; source/handle construction, checks, explicit GC, profiling and destruction are excluded.',
        input='One million rows; byte/int/long/float; constructed or retained 8191-row chunks. All timed handles alias one rooted compact source. No-null, 62 scattered missing values, or 843750 missing values with all 27 tags. The source stays compact and unchanged throughout.',
        repetitions='32 outputs total 256000000 bytes plus at most 4000000 shared compact source bytes. Sum independent intervals until CPU and wall each reach 150 ms; every individual interval, including zero durations, is retained. This threshold does not improve timer resolution.',
        order='Fresh process per build/round; alternate paired build order and backing positions. Six rounds cover all six missing-density permutations.',
        correctness='Full source bits before each batch and full result bits for every fresh target afterward. State checks reject pre-materialized targets; independent mutation verifies the rooted source remains unchanged.',
        memory='Separate single-call allocation profile and Vcells live/high-water deltas overlap; they are not RSS. Exact compact/compatibility copy counters must stay zero in both builds.',
        scope='Aliased first materialization only. Retained test adapters do not measure Arrow ingestion. No private-input, tiny-vector, temporal-throughput, or ordinary-double parity claim.'))
    rows, intervals = [], []
    for round_number in range(1, rounds + 1):
        order = ('baseline', 'candidate') if round_number % 2 else ('candidate', 'baseline')
        for variant in order:
            path = output / f'{round_number:02}-{variant}.csv'
            command = [runtime_before['Rscript_launcher'], '--vanilla', str(HERE / 'worker.R'),
                       str(builds[variant] / 'library'), str(probe), str(round_number), str(path),
                       variant, 'qualify' if args.qualify_only else 'measure']
            with (output / f'{round_number:02}-{variant}.log').open('w') as log:
                subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
            with path.open(newline='') as stream:
                observed = list(csv.DictReader(stream))
            validate_round(observed, round_number, phase)
            rows.extend(dict(variant=variant, **row) for row in observed)
            if not args.qualify_only:
                with Path(str(path) + '.intervals.csv').open(newline='') as stream:
                    observed_intervals = list(csv.DictReader(stream))
                validate_intervals(observed, observed_intervals, round_number)
                intervals.extend(dict(variant=variant, **row) for row in observed_intervals)
            print(f'Completed round {round_number}: {variant}, {len(observed)} observations', flush=True)
    after = {v: inventory(build) for v, build in builds.items()}
    probe_after, runtime_after = PROBE.verify(probe), runtime_binding()
    hashes_after = {str(p.relative_to(HERE.parent)): NATIVE.digest(p) for p in controllers}
    NATIVE.write_json(output / 'provenance-after.json', dict(builds=after, probe=probe_after,
        runtime=runtime_after, controllers=hashes_after))
    require(before == after and probe_before == probe_after and runtime_before == runtime_after and
            hashes == hashes_after, 'Build, probe, runtime or controller changed')
    grouped = validate_results(rows, rounds)
    NATIVE.write_csv(output / 'raw.csv', rows)
    artifacts = ['raw.csv', 'protocol.json', 'source.patch']
    if not args.qualify_only:
        NATIVE.write_csv(output / 'intervals.csv', intervals)
        summary = []
        for key, batch in sorted(grouped.items()):
            row = dict(zip(FIELDS, key))
            for variant in builds:
                selected = [r for r in batch if r['variant'] == variant]
                for metric in ('cpu_seconds', 'elapsed_seconds', 'gc_cpu_seconds'):
                    row[variant + '_' + metric] = statistics.median(float(r[metric]) / integer(r['iterations'])
                                                                   for r in selected)
                for metric in ('compact_copy_bytes', 'r_profiled_allocation_bytes', 'r_largest_allocation_bytes',
                               'peak_vcell_bytes', 'live_vcell_delta_bytes'):
                    row[variant + '_' + metric] = statistics.median(float(r[metric]) for r in selected)
                for metric in ('cpu_seconds', 'elapsed_seconds'):
                    row[variant + '_min_batch_' + metric] = min(float(r['min_batch_' + metric]) for r in selected)
                    row[variant + '_max_batch_' + metric] = max(float(r['max_batch_' + metric]) for r in selected)
                for metric in ('batches', 'zero_cpu_batches', 'zero_wall_batches'):
                    row[variant + '_' + metric] = sum(integer(r[metric]) for r in selected)
            row['cpu_speedup'] = row['baseline_cpu_seconds'] / row['candidate_cpu_seconds']
            row['wall_speedup'] = row['baseline_elapsed_seconds'] / row['candidate_elapsed_seconds']
            for metric, label in (('cpu_seconds', 'cpu'), ('elapsed_seconds', 'wall')):
                pairs = []
                for number in range(1, rounds + 1):
                    selected = {r['variant']: float(r[metric]) / integer(r['iterations'])
                                for r in batch if integer(r['round']) == number}
                    pairs.append(selected['baseline'] / selected['candidate'])
                row[label + '_paired_median_speedup'] = statistics.median(pairs)
                row[label + '_paired_min_speedup'] = min(pairs)
                row[label + '_paired_max_speedup'] = max(pairs)
            summary.append(row)
        NATIVE.write_csv(output / 'summary.csv', summary)
        artifacts.extend(('intervals.csv', 'summary.csv'))
    NATIVE.write_json(output / 'completion.json', dict(observations=len(rows), rounds=rounds, phase=phase,
        exact_results=True, source_unchanged=True, first_materialization_only=True, provenance_unchanged=True,
        artifacts={name: NATIVE.digest(output / name) for name in artifacts}))
    print(f'Complete: {len(rows)} qualified compact decode observations', flush=True)


if __name__ == '__main__':
    main()
