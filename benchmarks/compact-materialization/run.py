#!/usr/bin/env python3
"""Measure first materialization with one source-bound external DATAPTR_RO probe."""
import argparse
from collections import Counter
import csv
import difflib
import importlib.util
import math
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess

HERE = Path(__file__).resolve().parent


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


NATIVE = module('native_operations', HERE.parent / 'native-operations/run.py')
PROBE = module('materialization_probe_builder', HERE / 'build-probe.py')
FIELDS = ('n', 'width', 'backing', 'sharing')
WIDTHS = dict(byte=1, int=2, long=4, float=4)
EXPECTED = {(str(n), width, backing, sharing)
            for n in (4096, 1000000) for width in WIDTHS
            for backing in ('constructed', 'retained') for sharing in ('private', 'aliased')}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def runtime_binding():
    rscript = shutil.which('Rscript')
    require(rscript is not None, 'Rscript is unavailable')
    # Bind the runtime selected by the same launcher used for workers. R on
    # PATH can belong to a different installation than Rscript.
    r_home = Path(subprocess.check_output(
        [rscript, '--vanilla', '-e', 'cat(R.home())'], text=True).strip())
    return dict(R_runtime_sha256=NATIVE.digest(r_home / 'bin/exec/R'),
                Rscript_launcher_sha256=NATIVE.digest(Path(rscript)))


def validate_round(rows, round_number, variant):
    require(Counter(tuple(row[k] for k in FIELDS) for row in rows) ==
            Counter({case: 1 for case in EXPECTED}), 'Incomplete, duplicated or unexpected case matrix')
    for row in rows:
        require(row['phase'] == 'timing' and int(row['round']) == round_number,
                'Wrong phase or round')
        iterations, batches, batch_size = (int(row[k]) for k in ('iterations', 'batches', 'batch_size'))
        require(iterations == batches * batch_size and min(iterations, batches, batch_size) > 0,
                'Invalid number of first materializations')
        require(batches <= 1000 and batch_size <= 1024, 'Batch limit exceeded')
        for key in ('cpu_seconds', 'elapsed_seconds'):
            require(math.isfinite(float(row[key])) and float(row[key]) >= .15,
                    'Retained timing is nonfinite or shorter than the minimum interval')
        require(math.isfinite(float(row['gc_cpu_seconds'])) and
                0 <= float(row['gc_cpu_seconds']) <= float(row['cpu_seconds']) + .01,
                'Invalid GC CPU observation')
        n = int(row['n'])
        compact_bytes = n * WIDTHS[row['width']]
        require(float(row['compact_payload_bytes']) == compact_bytes and
                float(row['double_payload_bytes']) == 8 * n, 'Wrong payload accounting')
        expected_copy = compact_bytes if (variant == 'baseline' and row['backing'] == 'constructed'
                                         and row['sharing'] == 'aliased') else 0
        require(float(row['compact_copy_bytes']) == expected_copy and
                float(row['timed_compact_copy_bytes']) == expected_copy * iterations,
                'Unexpected compact copy count')
        require(float(row['compatibility_bytes']) == 0, 'Retained source copied to compatibility backing')
        for key in ('r_profiled_allocation_bytes', 'r_largest_allocation_bytes',
                    'r_profiled_allocations', 'peak_vcell_bytes'):
            require(math.isfinite(float(row[key])) and float(row[key]) > 0,
                    'Invalid R allocation or vector-heap high-water observation')
        require(float(row['r_profiled_allocation_bytes']) >= float(row['r_largest_allocation_bytes']) >= 8 * n,
                'Profile does not include the materialized double allocation')
        require(math.isfinite(float(row['live_vcell_delta_bytes'])), 'Nonfinite live vector-heap delta')
        for key in ('source_sha256', 'result_sha256'):
            require(len(row[key]) == 64 and all(c in '0123456789abcdef' for c in row[key]),
                    'Malformed complete value hash')
        require(row['source_sha256'] == row['result_sha256'], 'Materialization changed value bits')
        require(all(row[key] == 'TRUE' for key in ('alias_independent', 'source_unmaterialized_before',
                                                  'source_materialized_after')), 'Ownership qualification failed')
        expected_chunks = math.ceil(n / (257 if n == 4096 else 8191)) if row['backing'] == 'retained' else 0
        require(int(row['retained_chunks']) == expected_chunks, 'Unexpected retained chunk geometry')
    for case in {tuple(row[k] for k in FIELDS[:-1]) for row in rows}:
        orders = [int(row['order']) for row in rows if tuple(row[k] for k in FIELDS[:-1]) == case]
        require(sorted(orders) == [1, 2], 'Invalid sharing positions')


def validate_results(rows, rounds):
    grouped = {}
    for row in rows:
        grouped.setdefault(tuple(row[k] for k in FIELDS), []).append(row)
    require(set(grouped) == EXPECTED, 'Incomplete aggregate matrix')
    for key, batch in grouped.items():
        require(len(batch) == rounds * 2, 'Wrong aggregate observation count')
        require(len({(r['source_sha256'], r['result_sha256'], r['retained_chunks']) for r in batch}) == 1,
                'Values or input geometry differs across builds or rounds')
        for variant in ('baseline', 'candidate'):
            selected = [r for r in batch if r['variant'] == variant]
            require(Counter(int(r['round']) for r in selected) == Counter(range(1, rounds + 1)),
                    'Repeated or missing build round')
            require(Counter(int(r['order']) for r in selected) == Counter({1: rounds // 2, 2: rounds // 2}),
                    'Private/aliased positions are not balanced')
    # Sharing and backing may change ownership but cannot change any value.
    for n in ('4096', '1000000'):
        for width in WIDTHS:
            require(len({r['result_sha256'] for r in rows if r['n'] == n and r['width'] == width}) == 1,
                    'Values differ across sharing or backing representations')
    return grouped


def validate_intervals(rows, intervals, round_number, variant):
    grouped = {}
    for interval in intervals:
        key = tuple(interval[k] for k in FIELDS)
        require(key in EXPECTED and int(interval['round']) == round_number, 'Unknown interval case or round')
        for metric in ('cpu_seconds', 'elapsed_seconds', 'gc_cpu_seconds'):
            require(math.isfinite(float(interval[metric])) and float(interval[metric]) >= 0,
                    'Nonfinite or negative individual interval')
        require(float(interval['gc_cpu_seconds']) <= float(interval['cpu_seconds']) + .01,
                'Individual GC interval exceeds CPU')
        grouped.setdefault(key, []).append(interval)
    require(set(grouped) == EXPECTED, 'Individual interval matrix is incomplete')
    for row in rows:
        batch = grouped[tuple(row[k] for k in FIELDS)]
        count = int(row['batches'])
        require(Counter(int(r['batch']) for r in batch) == Counter(range(1, count + 1)),
                'Missing or duplicated individual interval')
        require(all(int(r['handles']) == int(row['batch_size']) for r in batch),
                'Individual interval handle count differs')
        expected_copy = int(row['n']) * WIDTHS[row['width']] if (variant == 'baseline' and
            row['backing'] == 'constructed' and row['sharing'] == 'aliased') else 0
        require(all(float(r['compact_copy_bytes']) == expected_copy * int(r['handles']) for r in batch),
                'Individual interval copy count differs')
        for metric in ('cpu_seconds', 'elapsed_seconds', 'gc_cpu_seconds'):
            require(math.isclose(sum(float(r[metric]) for r in batch), float(row[metric]),
                                 rel_tol=1e-10, abs_tol=1e-10), 'Individual intervals do not reproduce aggregate')
        for metric, zero_key in (('cpu_seconds', 'zero_cpu_batches'), ('elapsed_seconds', 'zero_wall_batches')):
            values = [float(r[metric]) for r in batch]
            for label, value in (('min', min(values)), ('max', max(values))):
                require(math.isclose(value, float(row[label + '_batch_' + metric]), rel_tol=1e-10, abs_tol=1e-10),
                        'Individual interval range does not reproduce aggregate')
            require(sum(value == 0 for value in values) == int(row[zero_key]),
                    'Zero-duration interval count differs')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('baseline', 'candidate', 'probe', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=6)
    args = parser.parse_args()
    require(args.rounds >= 6 and args.rounds % 2 == 0, 'Use at least six, and an even number of rounds')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    builds = {name: getattr(args, name).resolve() for name in ('baseline', 'candidate')}
    probe = args.probe.resolve()
    before = {name: NATIVE.inventory(build, name) for name, build in builds.items()}
    probe_before = PROBE.verify(probe)
    runtime_before = runtime_binding()
    require(len({before[v]['receipt']['toolchain']['R_runtime_sha256'] for v in builds} |
                {probe_before['receipt']['toolchain']['R_runtime_sha256'],
                 runtime_before['R_runtime_sha256']}) == 1,
            'Probe, packages, and current R runtime differ')
    controllers = (Path(__file__).resolve(), HERE / 'worker.R', HERE / 'probe.c', HERE / 'build-probe.py',
        HERE.parent / 'native-operations/run.py', HERE.parent / 'r-file-readers/record-builds.py',
        HERE.parent / 'r-file-readers/build-snapshot.py', HERE.parent / 'io-optimization/record-builds.py')
    hashes = {str(p.relative_to(HERE.parent)): NATIVE.digest(p) for p in controllers}
    NATIVE.write_json(output / 'provenance-before.json', dict(builds=before, probe=probe_before, runtime=runtime_before,
        controllers=hashes, platform=platform.platform(), machine=platform.machine(),
        logical_cpus=os.cpu_count(), R=subprocess.check_output(['R', '--version'], text=True).splitlines()[0]))
    patch = []
    for name in sorted(set(before['baseline']['source']) | set(before['candidate']['source'])):
        if before['baseline']['source'].get(name) == before['candidate']['source'].get(name):
            continue
        paths = [builds[v] / 'source' / name for v in ('baseline', 'candidate')]
        content = [p.read_text().splitlines(keepends=True) if p.exists() else [] for p in paths]
        patch.extend(difflib.unified_diff(*content, fromfile='a/' + name, tofile='b/' + name))
    (output / 'source.patch').write_text(''.join(patch))
    NATIVE.write_json(output / 'protocol.json', dict(rounds=args.rounds, cases_per_build_round=len(EXPECTED),
        baseline_commit=before['baseline']['receipt']['base_commit'],
        candidate_commit=before['candidate']['receipt']['base_commit'],
        probe_source_sha256=probe_before['receipt']['source_sha256'],
        probe_binary_sha256=probe_before['receipt']['binary_sha256'],
        interval='Shared external C loop calls ordinary R DATAPTR_RO once per preconstructed fresh compact handle. Includes materialized result allocation and automatic GC. Construction, full checks, explicit GC, profiling and destruction are excluded.',
        repetitions='Fixed per-case batches of at most 1024 handles and about 64 MiB compact-plus-double payload; sum retained intervals until CPU and wall each reach 150 ms. Every request consumes a different unmaterialized handle. All individual proc.time() intervals are retained, including zeros, and their range and sums are independently verified; the aggregate threshold does not establish individual timer precision.',
        order='Fresh process per build/round. Alternate build order and private/aliased positions; fixed size/width/backing case order.',
        values='Deterministic exact finite values plus all 27 missing ranks. Source and result checked bitwise via nonmutating region reads, including every timed handle and its alias. Alias independence checked by later target mutation and alias materialization outside timing.',
        memory='Separate single-call diagnostics: exact compact-copy and retained-compatibility byte counters, Rprofmem logged allocation bytes, and gc() Vcells high-water increase above the pre-call live vector heap. Live Vcells delta is also reported. These metrics overlap and must not be added. They exclude external allocations and are not process RSS.',
        retained='Test adapter freezes constructor bytes into immutable retained chunks (257 rows for small input, 8191 for large); no Arrow reader or decompression is measured.',
        limits='One host and deterministic missing-bearing inputs. Private compact inputs are controls for decode/output allocation. All comparisons use the identical external pointer probe; no internal package test forcing route or ordinary-double no-op is timed.'))
    rows = []
    intervals = []
    for round_number in range(1, args.rounds + 1):
        for variant in (('baseline', 'candidate') if round_number % 2 else ('candidate', 'baseline')):
            path = output / f'{round_number:02}-{variant}.csv'
            command = ['Rscript', '--vanilla', str(HERE / 'worker.R'), str(builds[variant] / 'library'),
                       str(probe), str(round_number), str(path), variant, 'measure']
            with (output / f'{round_number:02}-{variant}.log').open('w') as log:
                subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
            with path.open(newline='') as stream:
                observed = list(csv.DictReader(stream))
            with Path(str(path) + '.intervals.csv').open(newline='') as stream:
                observed_intervals = list(csv.DictReader(stream))
            validate_round(observed, round_number, variant)
            validate_intervals(observed, observed_intervals, round_number, variant)
            rows.extend(dict(variant=variant, **row) for row in observed)
            intervals.extend(dict(variant=variant, **row) for row in observed_intervals)
            print(f'Completed round {round_number}: {variant}, {len(observed)} observations', flush=True)
    after = {name: NATIVE.inventory(build, name) for name, build in builds.items()}
    probe_after = PROBE.verify(probe)
    runtime_after = runtime_binding()
    hashes_after = {str(p.relative_to(HERE.parent)): NATIVE.digest(p) for p in controllers}
    NATIVE.write_json(output / 'provenance-after.json', dict(builds=after, probe=probe_after,
        runtime=runtime_after, controllers=hashes_after))
    require(before == after and probe_before == probe_after and hashes == hashes_after and
            runtime_before == runtime_after, 'Build, shared probe, runtime or controller changed during measurement')
    grouped = validate_results(rows, args.rounds)
    NATIVE.write_csv(output / 'raw.csv', rows)
    NATIVE.write_csv(output / 'intervals.csv', intervals)
    summary = []
    for key, batch in sorted(grouped.items()):
        row = dict(zip(FIELDS, key))
        for variant in builds:
            selected = [r for r in batch if r['variant'] == variant]
            for metric in ('cpu_seconds', 'elapsed_seconds', 'gc_cpu_seconds'):
                row[variant + '_' + metric] = statistics.median(float(r[metric]) / int(r['iterations']) for r in selected)
            for metric in ('compact_copy_bytes', 'r_profiled_allocation_bytes', 'r_largest_allocation_bytes',
                           'peak_vcell_bytes', 'live_vcell_delta_bytes'):
                row[variant + '_' + metric] = statistics.median(float(r[metric]) for r in selected)
            for metric in ('cpu_seconds', 'elapsed_seconds'):
                row[variant + '_min_batch_' + metric] = min(float(r['min_batch_' + metric]) for r in selected)
                row[variant + '_max_batch_' + metric] = max(float(r['max_batch_' + metric]) for r in selected)
            for metric in ('batches', 'zero_cpu_batches', 'zero_wall_batches'):
                row[variant + '_' + metric] = sum(int(r[metric]) for r in selected)
        row['cpu_speedup'] = row['baseline_cpu_seconds'] / row['candidate_cpu_seconds']
        row['wall_speedup'] = row['baseline_elapsed_seconds'] / row['candidate_elapsed_seconds']
        summary.append(row)
    NATIVE.write_csv(output / 'summary.csv', summary)
    NATIVE.write_json(output / 'completion.json', dict(observations=len(rows), rounds=args.rounds,
        exact_results=True, alias_independent=True, first_materialization_only=True,
        provenance_unchanged=True, artifacts={name: NATIVE.digest(output / name)
            for name in ('raw.csv', 'intervals.csv', 'summary.csv', 'protocol.json', 'source.patch')}))
    print(f'Complete: {len(rows)} qualified first-materialization observations', flush=True)


if __name__ == '__main__':
    main()
