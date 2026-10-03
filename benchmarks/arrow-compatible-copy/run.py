#!/usr/bin/env python3
"""Paired fresh-process public Arrow compatible-transfer screen."""
import argparse
from collections import Counter
import csv
from decimal import Decimal
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

HERE = Path(__file__).resolve().parent
TARGETS = ('payload_f64', 'semantic_f64', 'integer_i32')
CONTROLS = ('nullable_f64', 'nullable_i32', 'widen_f32', 'compact_i16')
IDS = TARGETS + CONTROLS
MODES = ('read', 'full')
THREADS = ('1', '16')
KEYS = ('id', 'threads', 'mode')
CASES = set(itertools.product(IDS, THREADS, MODES))
HASHES = ('values_sha256', 'metadata_sha256', 'types_sha256', 'consumption_sha256', 'state_sha256')
TIMES = ('read_cpu_seconds', 'read_wall_seconds', 'consume_cpu_seconds',
         'consume_wall_seconds', 'total_cpu_seconds', 'total_wall_seconds', 'gc_cpu_seconds')
COMMITS = {'baseline': '9e6977a426f56b50044bf6d62c108c2d1e3548ed',
           'candidate': '9ee3916ca078cb46f49f932b7cbb3ded70a6a99f'}
ROUTES = {'payload_f64': 'PayloadDouble', 'semantic_f64': 'SemanticDouble',
          'integer_i32': 'Integer', 'nullable_f64': 'SemanticDouble',
          'nullable_i32': 'Integer', 'widen_f32': 'SemanticDouble',
          'compact_i16': 'ProfiledCompact'}


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def integer(value):
    number = Decimal(str(value))
    require(number.is_finite() and number == number.to_integral_value(), 'Nonintegral count')
    return int(number)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def write_csv(path, rows):
    require(bool(rows), 'Empty CSV')
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=tuple(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def read_csv(path):
    with path.open(newline='') as stream:
        return list(csv.DictReader(stream))


def schedule(number):
    target_order = tuple(itertools.permutations(TARGETS))[(number - 1) % 6]
    control_order = CONTROLS if number % 2 else tuple(reversed(CONTROLS))
    ids = target_order + control_order if number % 2 else control_order + target_order
    threads = THREADS if number % 2 else tuple(reversed(THREADS))
    modes = MODES if number % 2 else tuple(reversed(MODES))
    return list(itertools.product(ids, threads, modes))


def variants(number, ordinal):
    # Workflow order also reverses every round. Using ordinal parity here
    # would cancel that reversal and pin a given workflow to one build first.
    return ('baseline', 'candidate') if number % 2 else ('candidate', 'baseline')


def validate_row(row, case, phase):
    require(tuple(row[k] for k in KEYS) == case, 'Worker case differs')
    require(row['phase'] == phase, 'Worker phase differs')
    require(integer(row['rows']) == 2000000 and integer(row['columns']) == 8, 'Wrong dimensions')
    expected_na = 28 if row['id'] in TARGETS[:2] else 32 if row['id'] in (
        'nullable_f64', 'nullable_i32', 'compact_i16') else 0
    require(integer(row['expected_na_per_column']) == expected_na, 'Wrong missing count')
    require(row['route'] == ROUTES[row['id']], 'Wrong expected route declaration')
    require(row['profile'] == str(row['id'] != 'semantic_f64').upper(), 'Wrong profile mode')
    require(row['retained'] == str(row['id'] == 'compact_i16').upper(), 'Wrong retained state')
    compact = row['id'] == 'compact_i16'
    require(integer(row['compact_columns']) == integer(row['retained_columns']) == (8 if compact else 0)
            and integer(row['chunks_per_column']) == (31 if compact else 0), 'Wrong native ownership/geometry')
    for key in HASHES:
        require(len(row[key]) == 64 and all(c in '0123456789abcdef' for c in row[key]),
                'Invalid semantic hash')
    for metric in TIMES:
        value = float(row[metric])
        require(math.isfinite(value) and value >= 0, 'Invalid timing interval')
    if phase == 'qualify':
        require(all(float(row[k]) == 0 for k in TIMES), 'Qualification collected clocks')
    else:
        require(min(float(row['read_cpu_seconds']), float(row['read_wall_seconds'])) > 0,
                'Nonpositive read interval')
        if row['mode'] == 'full':
            require(min(float(row['consume_cpu_seconds']), float(row['consume_wall_seconds'])) > 0,
                    'Nonpositive full consumption interval')
        else:
            require(float(row['consume_cpu_seconds']) == float(row['consume_wall_seconds']) == 0,
                    'Read-only case collected consumption clocks')
        for unit in ('cpu', 'wall'):
            require(math.isclose(float(row[f'read_{unit}_seconds']) +
                                float(row[f'consume_{unit}_seconds']),
                                float(row[f'total_{unit}_seconds']),
                                rel_tol=1e-10, abs_tol=1e-10), 'Workflow totals disagree')
        require(float(row['gc_cpu_seconds']) <= float(row['total_cpu_seconds']) + .01,
                'GC CPU exceeds process CPU beyond timer allowance')


def validate_all(rows, rounds, phase):
    require(len(rows) == rounds * len(CASES) * 2, 'Incomplete observation count')
    expected_order = []
    for number in range(1, rounds + 1):
        for ordinal, case in enumerate(schedule(number), 1):
            for variant in variants(number, ordinal):
                expected_order.append((number, ordinal, variant, case))
    for row, expected in zip(rows, expected_order):
        number, ordinal, variant, case = expected
        require((integer(row['round']), integer(row['ordinal']), row['variant']) ==
                (number, ordinal, variant), 'Execution order differs')
        validate_row(row, case, phase)
    for number in range(1, rounds + 1):
        for variant in COMMITS:
            selected = [r for r in rows if integer(r['round']) == number and r['variant'] == variant]
            require(Counter(tuple(r[k] for k in KEYS) for r in selected) ==
                    Counter({case: 1 for case in CASES}), 'Duplicated or omitted case')
    for fixture in IDS:
        selected = [r for r in rows if r['id'] == fixture]
        require(len({tuple(r[k] for k in HASHES) for r in selected}) == 1,
                'Complete semantic values/state disagree across executions')
    if phase == 'measure':
        for case in CASES:
            positions = Counter()
            for number in range(1, rounds + 1):
                ordinal = schedule(number).index(case) + 1
                positions[variants(number, ordinal)[0]] += 1
            require(positions == Counter({'baseline': rounds // 2, 'candidate': rounds // 2}),
                    'Unbalanced paired build positions')
        orders = [tuple(dict.fromkeys(case[0] for case in schedule(number) if case[0] in TARGETS))
                  for number in range(1, rounds + 1)]
        require(Counter(orders) == Counter({order: rounds // 6 for order in itertools.permutations(TARGETS)}),
                'Target permutations differ')


def runtime_binding():
    launcher = shutil.which('Rscript')
    require(launcher is not None, 'Rscript unavailable')
    launcher = str(Path(launcher).absolute())
    home = Path(subprocess.check_output([launcher, '--vanilla', '-e', 'cat(R.home())'], text=True).strip())
    return dict(launcher=launcher, launcher_sha256=sha(Path(launcher)),
                R_runtime_sha256=sha(home / 'bin/exec/R'))


def worker_name(row):
    return (f'{integer(row["round"]):02}-{integer(row["ordinal"]):02}-{row["variant"]}-' +
            '-'.join(row[k] for k in KEYS) + '.csv')


def validate_workers(directory, rows):
    expected = {worker_name(row) for row in rows}
    require({path.name for path in directory.glob('*.csv')} - {'raw.csv', 'summary.csv'} == expected,
            'Worker CSV inventory differs')
    for row in rows:
        worker = {key: value for key, value in row.items() if key not in ('round', 'ordinal', 'variant')}
        require(read_csv(directory / worker_name(row)) == [worker], 'Worker and aggregate rows differ')


def summarize(rows):
    result = []
    for key in sorted(CASES):
        record = dict(zip(KEYS, key))
        paired = {variant: sorted([r for r in rows if tuple(r[k] for k in KEYS) == key and
                                  r['variant'] == variant], key=lambda r: integer(r['round']))
                  for variant in COMMITS}
        for variant, selected in paired.items():
            for metric in TIMES:
                values = [float(r[metric]) for r in selected]
                for label, function in (('median', statistics.median), ('min', min), ('max', max)):
                    record[f'{variant}_{label}_{metric}'] = function(values)
        for metric in ('read_cpu_seconds', 'read_wall_seconds', 'total_cpu_seconds', 'total_wall_seconds'):
            record[metric + '_speedup'] = (record['baseline_median_' + metric] /
                                           record['candidate_median_' + metric])
            ratios = [float(b[metric]) / float(c[metric]) for b, c in
                      zip(paired['baseline'], paired['candidate'])]
            for label, function in (('median', statistics.median), ('min', min), ('max', max)):
                record['paired_' + label + '_' + metric + '_speedup'] = function(ratios)
        result.append(record)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repository', 'baseline', 'candidate', 'fixtures', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--qualification', type=Path)
    parser.add_argument('--rounds', type=int, default=6)
    parser.add_argument('--qualify-only', action='store_true')
    args = parser.parse_args()
    phase = 'qualify' if args.qualify_only else 'measure'
    rounds = 1 if args.qualify_only else args.rounds
    require(args.qualify_only or rounds >= 6 and rounds % 6 == 0, 'Use six balanced rounds or a multiple')
    require(args.qualify_only or args.qualification is not None, 'Prior identical-bound qualification required')
    require(os.name != 'nt', 'This controller requires the Unix R runtime layout')
    repository, fixtures = args.repository.resolve(), args.fixtures.resolve()
    recorder = repository / 'benchmarks/r-file-readers/record-builds.py'
    spec = importlib.util.spec_from_file_location('compatible_records', recorder)
    records = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(records)
    builds = {role: getattr(args, role).resolve() for role in COMMITS}
    def bind(build, role):
        variant = json.loads((build / 'build-receipt.json').read_text())['variant']
        receipt, patch, receipt_hash = records.verified_receipt(build, variant)
        require(receipt['base_commit'] == COMMITS[role], 'Wrong compared source commit')
        require(not patch, 'Compared source is not the exact clean commit')
        return dict(receipt=receipt, receipt_sha256=receipt_hash)
    before = {role: bind(build, role) for role, build in builds.items()}
    runtime = runtime_binding()
    require(all(record['receipt']['toolchain']['R_runtime_sha256'] == runtime['R_runtime_sha256']
                for record in before.values()), 'Build and execution R runtimes differ')
    controllers = (Path(__file__).resolve(), HERE / 'worker.R', HERE / 'prepare.R', recorder,
                   repository / 'benchmarks/r-file-readers/build-snapshot.py',
                   repository / 'benchmarks/io-optimization/record-builds.py')
    controller_hashes = {str(path): sha(path) for path in controllers}
    fixture_hashes = {path.name: sha(path) for path in sorted(fixtures.iterdir()) if path.is_file()}
    require(all(f'{name}.rds' in fixture_hashes for name in IDS), 'Missing oracle file')
    binding = dict(builds=before, runtime=runtime, controllers=controller_hashes, fixtures=fixture_hashes)
    if args.qualification is not None:
        qualification = args.qualification.resolve()
        completed = json.loads((qualification / 'completion.json').read_text())
        require(completed['phase'] == 'qualify' and completed['observations'] == 56,
                'Qualification is incomplete')
        require(json.loads((qualification / 'binding-before.json').read_text()) == binding and
                json.loads((qualification / 'binding-after.json').read_text()) == binding,
                'Qualification used different bindings')
        for name, expected in completed['artifacts'].items():
            require(sha(qualification / name) == expected, 'Qualification artifact changed')
        qualified_rows = read_csv(qualification / 'raw.csv')
        validate_all(qualified_rows, 1, 'qualify')
        validate_workers(qualification, qualified_rows)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    write_json(output / 'binding-before.json', binding)
    patch = []
    for name in sorted(set(before['baseline']['receipt']['source_inventory']) |
                       set(before['candidate']['receipt']['source_inventory'])):
        left, right = builds['baseline'] / 'source' / name, builds['candidate'] / 'source' / name
        if left.exists() and right.exists() and sha(left) == sha(right):
            continue
        patch.extend(difflib.unified_diff(left.read_text().splitlines(keepends=True) if left.exists() else [],
            right.read_text().splitlines(keepends=True) if right.exists() else [],
            fromfile='a/' + name, tofile='b/' + name))
    (output / 'source.patch').write_text(''.join(patch))
    write_json(output / 'protocol.json', dict(phase=phase, rounds=rounds,
        observations=rounds * 56, rows=2000000, columns=8,
        host=platform.platform(), machine=platform.machine(), logical_cpus=os.cpu_count(),
        source_commits=COMMITS, route_declarations=ROUTES,
        input='Seven fixed route cases; uncompressed65536-row batches. Three changed routes and four unchanged nullable/widening/retained controls. Fixture creation is outside measurement.',
        workers='One public read per fresh R process, threads1/16, independent read-return and read-plus-first-full-consumption cases. Expected vectors load after timing.',
        consumption='Each column: sum(as.double(x),na.rm=TRUE) and complete is.na(x) vector. Full bitwise values, exact NA positions, types, metadata and compact state checked outside timing.',
        policy='verify=TRUE. Generic input lacks private checksums; profile=FALSE ignores checksums and metadata. Compare builds within a route; cross-route timings are not isolated classifier or checksum estimates.',
        order='All six target permutations; controls alternate before/after targets and reverse order. Thread/workflow order alternates; paired build order alternates and each case occupies both build positions three times.',
        timing='One first-read interval per worker, automatic GC included. Package load, explicit preceding GC, fixtures and complete validation excluded. Retain every CPU/wall/GC interval; six medians do not improve interval resolution.',
        limits='One host and geometry; filesystem cache uncontrolled. No ingestion zero-copy, process RSS or universal reader parity claim. Route declarations follow captured fixture metadata and source dispatch; direct Rust regressions qualify null-free and nullable copy branches. No phase clocks or new counters are present in either acceptance build.'))
    rows = []
    for number in range(1, rounds + 1):
        for ordinal, case in enumerate(schedule(number), 1):
            for variant in variants(number, ordinal):
                name = f'{number:02}-{ordinal:02}-{variant}-' + '-'.join(case)
                csv_path = output / (name + '.csv')
                with (output / (name + '.log')).open('w') as log:
                    subprocess.run([runtime['launcher'], '--vanilla', str(HERE / 'worker.R'),
                        str(builds[variant] / 'library'), str(fixtures), *case, phase, str(csv_path)],
                        stdout=log, stderr=subprocess.STDOUT, check=True)
                observed = read_csv(csv_path)
                require(len(observed) == 1, 'Worker returned wrong row count')
                validate_row(observed[0], case, phase)
                rows.append(dict(round=number, ordinal=ordinal, variant=variant, **observed[0]))
            print(f'Completed round{number} case{ordinal}/28: {case}', flush=True)
    after = dict(builds={role: bind(build, role) for role, build in builds.items()}, runtime=runtime_binding(),
        controllers={str(path): sha(path) for path in controllers},
        fixtures={path.name: sha(path) for path in sorted(fixtures.iterdir()) if path.is_file()})
    require(after == binding, 'Build/runtime/fixtures/controllers changed')
    write_json(output / 'binding-after.json', after)
    validate_all(rows, rounds, phase)
    write_csv(output / 'raw.csv', rows)
    validate_workers(output, rows)
    if phase == 'measure':
        write_csv(output / 'summary.csv', summarize(rows))
    artifacts = ['binding-before.json', 'binding-after.json', 'source.patch', 'protocol.json']
    artifacts.extend(path.name for path in sorted(output.glob('*.csv')))
    write_json(output / 'completion.json', dict(phase=phase, observations=len(rows), rounds=rounds,
        full_results_exact=True, bindings_unchanged=True, timings_collected=phase == 'measure',
        artifacts={name: sha(output / name) for name in artifacts}))


if __name__ == '__main__':
    main()
