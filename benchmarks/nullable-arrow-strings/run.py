#!/usr/bin/env python3
"""Fresh-process nullable Arrow string diagnostic, with full post-timing oracles."""
import argparse
from collections import Counter
import csv
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

HERE = Path(__file__).resolve().parent
KEYS = ('id', 'threads', 'mode')
IDS = tuple(f'{cardinality}-{nulls}' for cardinality in ('low', 'high')
            for nulls in ('zero', 'one', 'sparse')) + ('finite',)
MODES = ('read', 'scalar', 'full')
EXPECTED = set(itertools.product(IDS, ('0', '1'), MODES))
PERMUTATIONS = tuple(itertools.permutations(('zero', 'one', 'sparse')))
TIMES = ('read_cpu_seconds', 'read_wall_seconds', 'consume_cpu_seconds', 'consume_wall_seconds',
         'total_cpu_seconds', 'total_wall_seconds', 'gc_cpu_seconds', 'second_cpu_seconds',
         'second_wall_seconds', 'second_gc_cpu_seconds')
HASHES = ('values_sha256', 'metadata_sha256', 'encoding_sha256', 'consumption_sha256')


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def write_csv(path, rows):
    require(bool(rows), 'No rows to write')
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=tuple(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def inventory_fixtures(fixtures):
    return {p.name: sha(p) for p in sorted(fixtures.iterdir()) if p.is_file()}


def runtime_binding():
    launcher = shutil.which('Rscript')
    require(launcher is not None, 'Rscript is unavailable')
    # Query the launcher that executes workers; an unrelated R on PATH could
    # belong to a different installation despite a plausible R_HOME.
    home = Path(subprocess.check_output([launcher, '--vanilla', '-e', 'cat(R.home())'], text=True).strip())
    return dict(Rscript_launcher=os.path.abspath(launcher),
                R_runtime_sha256=sha(home / 'bin/exec/R'),
                Rscript_launcher_sha256=sha(Path(launcher)))


def schedule(round_number):
    null_order = PERMUTATIONS[(round_number - 1) % len(PERMUTATIONS)]
    card_order = ('low', 'high') if round_number % 2 else ('high', 'low')
    mode_offset = (round_number - 1) % 3
    mode_order = MODES[mode_offset:] + MODES[:mode_offset]
    thread_order = ('1', '0') if round_number % 2 else ('0', '1')
    for threads in thread_order:
        for mode in mode_order:
            # Finite controls alternate before and after each six-string block.
            if round_number % 2:
                yield dict(id='finite', threads=threads, mode=mode, null_position=0)
            for cardinality in card_order:
                for position, nulls in enumerate(null_order, 1):
                    yield dict(id=f'{cardinality}-{nulls}', threads=threads, mode=mode,
                               null_position=position)
            if not round_number % 2:
                yield dict(id='finite', threads=threads, mode=mode, null_position=0)


def validate_row(row, expected, phase):
    require(all(row[key] == expected[key] for key in KEYS), 'Worker returned a different case')
    require(row['phase'] == phase, 'Worker returned a different phase')
    require(int(row['rows']) == 250000 and int(row['columns']) == 4, 'Wrong input shape')
    expected_nulls = 1 if row['id'].endswith('-one') else 251 if row['id'].endswith('-sparse') else 0
    require(int(row['expected_na_per_column']) == expected_nulls, 'Wrong NA count')
    require(0 <= int(row['dictionary_columns_after_workflow']) <= 4, 'Impossible representation count')
    for key in ('values_exact', 'metadata_exact', 'raw_encoding_exact', 'consumption_exact'):
        require(row[key] == 'TRUE', 'Failed full public result check: ' + key)
    for key in HASHES:
        require(len(row[key]) == 64 and all(c in '0123456789abcdef' for c in row[key]), 'Malformed hash')
    for key in TIMES:
        require(math.isfinite(float(row[key])) and float(row[key]) >= 0, 'Negative or nonfinite timing')
    if phase == 'measure':
        require(min(float(row[k]) for k in ('read_cpu_seconds', 'read_wall_seconds',
                                           'total_cpu_seconds', 'total_wall_seconds')) > 0,
                'Nonpositive read/workflow timing')
        require(float(row['gc_cpu_seconds']) <= float(row['total_cpu_seconds']) + .01,
                'GC CPU exceeds workflow CPU beyond resolution allowance')
        if row['mode'] == 'full':
            require(min(float(row['second_cpu_seconds']), float(row['second_wall_seconds'])) > 0,
                    'Nonpositive second full traversal timing')
            require(float(row['second_gc_cpu_seconds']) <= float(row['second_cpu_seconds']) + .01,
                    'Second GC CPU exceeds traversal CPU beyond resolution allowance')
        else:
            require(all(float(row[k]) == 0 for k in ('second_cpu_seconds', 'second_wall_seconds',
                                                    'second_gc_cpu_seconds')),
                    'Unexpected second traversal')
        for unit in ('cpu', 'wall'):
            require(math.isclose(float(row[f'read_{unit}_seconds']) + float(row[f'consume_{unit}_seconds']),
                                 float(row[f'total_{unit}_seconds']), rel_tol=1e-10, abs_tol=1e-10),
                    'Read and consumption do not reproduce workflow total')
    else:
        require(all(float(row[k]) == 0 for k in TIMES), 'Qualification collected timings')


def validate_results(rows, rounds, variants, phase):
    require(len(rows) == rounds * len(variants) * len(EXPECTED), 'Wrong complete observation count')
    for variant in variants:
        for round_number in range(1, rounds + 1):
            selected = [r for r in rows if r['variant'] == variant and int(r['round']) == round_number]
            require(Counter(tuple(r[k] for k in KEYS) for r in selected) ==
                    Counter({case: 1 for case in EXPECTED}), 'Incomplete/duplicated build-round matrix')
            for cardinality, threads, mode in itertools.product(('low', 'high'), ('0', '1'), MODES):
                group = [r for r in selected if r['id'].startswith(cardinality + '-') and
                         r['threads'] == threads and r['mode'] == mode]
                require(sorted(int(r['null_position']) for r in group) == [1, 2, 3],
                        'Per-round null positions are incomplete')
    for fixture in IDS:
        selected = [r for r in rows if r['id'] == fixture]
        require(len({tuple(r[k] for k in HASHES) for r in selected}) == 1,
                'Full values, encodings, metadata, or consumption differs across executions')
    if phase == 'measure':
        for variant in variants:
            for key in EXPECTED:
                selected = [r for r in rows if r['variant'] == variant and tuple(r[k] for k in KEYS) == key]
                if key[0] != 'finite':
                    require(Counter(int(r['null_position']) for r in selected) ==
                            Counter({position: rounds // 3 for position in (1, 2, 3)}),
                            'Null positions are unbalanced')
            for cardinality, threads, mode in itertools.product(('low', 'high'), ('0', '1'), MODES):
                actual = []
                for round_number in range(1, rounds + 1):
                    group = [r for r in rows if r['variant'] == variant and int(r['round']) == round_number
                             and r['id'].startswith(cardinality + '-') and r['threads'] == threads
                             and r['mode'] == mode]
                    actual.append(tuple(r['id'].split('-')[1] for r in
                                        sorted(group, key=lambda row: int(row['null_position']))))
                require(Counter(actual) == Counter({order: rounds // 6 for order in PERMUTATIONS}),
                        'Complete null-order permutations are unbalanced')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repository', 'baseline', 'fixtures', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--candidate', type=Path)
    parser.add_argument('--rounds', type=int, default=6)
    parser.add_argument('--qualify-only', action='store_true')
    args = parser.parse_args()
    phase = 'qualify' if args.qualify_only else 'measure'
    rounds = 1 if args.qualify_only else args.rounds
    require(args.qualify_only or rounds >= 6 and rounds % 6 == 0, 'Use at least six balanced rounds')
    repository, fixtures = args.repository.resolve(), args.fixtures.resolve()
    recorder = repository / 'benchmarks/r-file-readers/record-builds.py'
    spec = importlib.util.spec_from_file_location('reader_recorder', recorder)
    records = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(records)
    builds = dict(baseline=args.baseline.resolve())
    if args.candidate:
        builds['candidate'] = args.candidate.resolve()
    def bind_build(build):
        # The diagnostic baseline may be a previously named candidate receipt.
        variant = json.loads((build / 'build-receipt.json').read_text())['variant']
        receipt, patch, receipt_hash = records.verified_receipt(build, variant)
        return dict(receipt=receipt, source_patch=patch, receipt_sha256=receipt_hash)
    before = {name: bind_build(build) for name, build in builds.items()}
    runtime = runtime_binding()
    require(all(binding['receipt']['toolchain']['R_runtime_sha256'] == runtime['R_runtime_sha256']
                for binding in before.values()), 'Builds do not use the execution R runtime')
    controllers = (Path(__file__).resolve(), HERE / 'worker.R', HERE / 'prepare.R', recorder,
                   repository / 'benchmarks/r-file-readers/build-snapshot.py',
                   repository / 'benchmarks/io-optimization/record-builds.py')
    controller_hashes = {str(path): sha(path) for path in controllers}
    fixture_hashes = inventory_fixtures(fixtures)
    require(all(f'{fixture}.{extension}' in fixture_hashes for fixture in IDS
                for extension in ('arrow', 'rds')), 'Required fixture or oracle is missing')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    write_json(output / 'binding-before.json', dict(builds=before, fixtures=fixture_hashes,
        controllers=controller_hashes, runtime=runtime, platform=platform.platform(),
        machine=platform.machine(), logical_cpus=os.cpu_count()))
    write_json(output / 'protocol.json', dict(phase=phase, rounds=rounds, variants=list(builds),
        cases_per_build_round=len(EXPECTED), workers='One fresh R process and one public read per case.',
        input='250000 rows, 4 UTF-8 columns; randomized 32-level or unique strings; zero/one/251 nulls per column. A finite four-double fixture is common control. Uncompressed checksummed files, verify=TRUE, threads=1 and automatic.',
        cache='No reference RDS or expected strings are loaded before timings. Filesystem cache is uncontrolled; these are fresh R-process/string-cache observations, not cold disk measurements.',
        workflows='Independent read-return, read plus first scalar per column, and read plus first full nchar(bytes)/is.na traversal. Full mode separately times a second traversal before reference loading.',
        timing='Single first-read intervals, not calibrated repeated reads. Includes public output allocation and automatic GC. Package loading, explicit preceding GC, all fixture generation and complete post-timing validation are excluded. Every raw CPU/wall/GC interval is retained; aggregate medians do not improve individual timer granularity.',
        order='All six zero/one/sparse permutations over six rounds; rotate workflow order, alternate thread/cardinality order and finite-control position. Alternate build order with paired candidate.',
        correctness='Full values, NA and empty positions, original public encoding flags, metadata, and complete traversal output checked against independent saved source after timings. Stable hashes are required across all builds/threads/workflows/rounds.',
        limits='One host and one fixture geometry. Representation counts are diagnostic, not a requirement to make nullable ALTREP columns. No process-RSS claim.'))
    rows = []
    for round_number in range(1, rounds + 1):
        variants = tuple(builds) if round_number % 2 else tuple(reversed(builds))
        for ordinal, case in enumerate(schedule(round_number), 1):
            for variant in variants:
                label = f'{round_number:02}-{ordinal:02}-{variant}-{case["id"]}-{case["threads"]}-{case["mode"]}'
                csv_path = output / (label + '.csv')
                with (output / (label + '.log')).open('w') as log:
                    subprocess.run([runtime['Rscript_launcher'], '--vanilla', str(HERE / 'worker.R'),
                        str(builds[variant] / 'library'), str(fixtures), case['id'], case['threads'],
                        case['mode'], phase, str(csv_path)], stdout=log, stderr=subprocess.STDOUT, check=True)
                observed = list(csv.DictReader(csv_path.open(newline='')))
                require(len(observed) == 1, 'Worker did not return exactly one observation')
                validate_row(observed[0], case, phase)
                rows.append(dict(round=round_number, variant=variant, ordinal=ordinal,
                                 null_position=case['null_position'], **observed[0]))
            print(f'Completed round {round_number} case {ordinal}/42: {case["id"]} threads={case["threads"]} {case["mode"]}', flush=True)
    after = {name: bind_build(build) for name, build in builds.items()}
    require(before == after and runtime == runtime_binding() and fixture_hashes == inventory_fixtures(fixtures)
            and controller_hashes == {str(path): sha(path) for path in controllers},
            'Build, runtime, fixture, or controller changed during diagnostic')
    write_json(output / 'binding-after.json', dict(builds=after, fixtures=fixture_hashes,
        controllers=controller_hashes, runtime=runtime))
    validate_results(rows, rounds, tuple(builds), phase)
    write_csv(output / 'raw.csv', rows)
    summary = []
    for variant in builds:
        for key in sorted(EXPECTED):
            selected = [r for r in rows if r['variant'] == variant and tuple(r[k] for k in KEYS) == key]
            row = dict(variant=variant, **dict(zip(KEYS, key)))
            for metric in TIMES:
                values = [float(r[metric]) for r in selected]
                for name, function in (('median', statistics.median), ('min', min), ('max', max)):
                    row[name + '_' + metric] = function(values)
            summary.append(row)
    write_csv(output / 'summary.csv', summary)
    write_json(output / 'completion.json', dict(phase=phase, observations=len(rows), rounds=rounds,
        full_results_exact=True, raw_encoding_exact=True, bindings_unchanged=True,
        timings_collected=phase == 'measure', artifacts={name: sha(output / name) for name in
            ('raw.csv', 'summary.csv', 'protocol.json', 'binding-before.json', 'binding-after.json')}))
    print(f'Complete: {len(rows)} fully qualified {phase} observations', flush=True)


if __name__ == '__main__':
    main()
