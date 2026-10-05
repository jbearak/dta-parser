#!/usr/bin/env python3
"""Twelve public reader workflows, six alternating pairs, exclusive CPU only.

Generate fixtures separately before starting this controller. This controller
does not install, build, regenerate data or alter package source. Reader calls
use a warm OS file cache; the fresh processes isolate package execution state.
"""
import argparse
import csv
import datetime
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess

HERE = Path(__file__).resolve().parent
FIXTURES = ('dense_float', 'sparse_int')
FORMATS = ('dta', 'arrow')
OPERATIONS = (0, 1, 5)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_inventory(root):
    return {str(path.relative_to(root)): sha(path)
            for path in sorted(root.rglob('*')) if path.is_file()}


def namespace_dll(library):
    files = [path for path in (library / 'dtatools/libs').rglob('dtatools.*')
             if path.is_file() and path.suffix.lower() in ('.so', '.dylib', '.dll')]
    require(len(files) == 1, 'Expected exactly one dtatools shared library')
    return files[0]


def build_binding(library, receipt_path):
    receipt = json.loads(receipt_path.read_text())
    require(receipt['exit_code'] == 0 and receipt['source_unchanged_during_build'],
            'Build did not qualify unchanged successful source')
    dll = namespace_dll(library)
    require(sha(dll) == receipt['dll_sha256'], 'Installed DLL differs from build receipt')
    source = Path(receipt['command'][-1]).resolve()
    inventory = receipt['source_inventory']
    require(all((source / path).is_file() and sha(source / path) == digest
                for path, digest in inventory.items()), 'Build source differs from receipt')
    return dict(receipt=str(receipt_path), receipt_sha256=sha(receipt_path),
                library=str(library), installed_inventory=tree_inventory(library / 'dtatools'),
                source=str(source), source_inventory=inventory,
                source_head=receipt.get('source_head'), dll_sha256=sha(dll))


def fixture_binding(directory):
    manifest = directory / 'fixtures.csv'
    with manifest.open(newline='') as stream:
        rows = list(csv.DictReader(stream))
    by = {(row['fixture'], row['format']): row for row in rows}
    require(len(rows) == 4 and set(by) == {(fixture, format) for fixture in FIXTURES for format in FORMATS},
            'Missing or duplicated immutable input file')
    files = {}
    for (fixture, format), row in by.items():
        path = directory / f'{fixture}.{format}'
        require(Path(row['path']).resolve() == path and row['rows'] == '1000000' and
                row['width'] == ('float' if fixture == 'dense_float' else 'int') and
                path.stat().st_size == int(row['bytes']), 'Fixture coordinate changed')
        files[path.name] = sha(path)
    return dict(directory=str(directory), manifest_sha256=sha(manifest),
                rows=rows, file_sha256=files)


def validate(rows, round_number, variant, mode, inputs):
    require(len(rows) == 12, 'Incomplete reader round')
    by = {(row['fixture'], row['format'], int(row['operations'])): row for row in rows}
    require(set(by) == {(fixture, format, count) for fixture in FIXTURES for format in FORMATS for count in OPERATIONS},
            'Missing or duplicated reader workflow')
    require({int(row['position']) for row in rows} == set(range(1, 13)), 'Invalid phase positions')
    files = {(row['fixture'], row['format']): row for row in inputs['rows']}
    for (fixture, format, operations), row in by.items():
        require(row['round'] == str(round_number) and row['variant'] == variant and
                row['mode'] == mode and row['rows'] == '1000000', 'Unexpected worker coordinate')
        iterations = int(row['repetitions'])
        require(iterations > 0 and int(row['qualification_calls']) == operations and
                int(row['native_calls']) == operations * (1 if mode == 'qualify' else iterations),
                'Incorrect native call count')
        cpu, wall = float(row['cpu']), float(row['wall'])
        require(math.isfinite(cpu) and math.isfinite(wall), 'Non-finite clocks')
        require((cpu > 0 and wall > 0) if mode == 'measure' else (cpu == 0 and wall == 0),
                'Invalid measured/qualification clocks')
        require(row['mutation_checked'] == row['automatic_gc_included'] == 'TRUE' and
                row['compact_before'] == row['compact_after'] == 'TRUE' and
                row['materialized_before'] == row['materialized_after'] == 'FALSE' and
                row['retained'] == ('TRUE' if format == 'arrow' else 'FALSE'),
                'Source, mutation/cache or GC qualification changed')
        require(row['mutation_source_compact'] == 'TRUE' and
                row['mutation_source_materialized'] == 'FALSE' and
                row['mutation_source_retained'] == ('TRUE' if format == 'arrow' and operations else 'FALSE'),
                'Unexpected source state after outside-clock alias mutation')
        require(int(row['mutation_source_chunks']) == (int(row['chunks']) if format == 'arrow' and operations else 0),
                'Unexpected retained chunks after outside-clock alias mutation')
        expected_flags = 0 if variant == 'baseline' or not operations else (7 if fixture == 'dense_float' else 4)
        require(int(row['mutation_source_flags']) == expected_flags, 'Unexpected post-mutation source facts')
        record = files[(fixture, format)]
        for field in ('width', 'input_hash', 'rank_hash', 'input_missing', 'zero_observed'):
            require(row[field] == record[field], 'Input file/oracle disagreement: ' + field)
        require(row['input_missing'] == ('500000' if fixture == 'dense_float' else '1003'),
                'Original fixture missing count changed')
        require(row['result_storage'] == ('int' if fixture == 'sparse_int' and operations == 0 else 'float'),
                'Output storage changed')
        require(int(row['result_missing']) == int(row['input_missing']) +
                (int(row['zero_observed']) if operations else 0), 'Missing/zero policy changed')
        if variant == 'baseline':
            require(all(row[field] == '0' for field in ('source_flags', 'source_maximum', 'source_minimum', 'source_zeros')),
                    'Baseline unexpectedly grants reader facts')
        else:
            require(row['source_flags'] == ('7' if fixture == 'dense_float' else '4') and
                    row['source_zeros'] == row['zero_observed'], 'Candidate reader facts incomplete')
            if fixture == 'sparse_int':
                require(row['source_maximum'] == row['source_minimum'] == '0', 'Integer granted FLOAT bounds')
        for field in ('input_hash', 'rank_hash', 'result_hash', 'missing_hash',
                      'source_metadata_hash', 'result_metadata_hash', 'cleared_hash'):
            require(len(row[field]) == 64, 'Missing oracle digest: ' + field)
        if fixture == 'dense_float':
            require(row['input_hash'] == 'b6b60ef8bb430be90e7239dd64b807cda383733b1048ca6748094e19e1003f06' and
                    row['rank_hash'] == '6d001f63d9ce5612a17ed6ff62e0d269d6d862dde318265b90a63af3b92b0706' and
                    row['zero_observed'] == '48', 'Original dense fixture changed')
    return by


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-library', type=Path, required=True)
    parser.add_argument('--candidate-library', type=Path, required=True)
    parser.add_argument('--baseline-receipt', type=Path, required=True)
    parser.add_argument('--candidate-receipt', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--generator', type=Path, default=HERE / 'reader-fixtures.R')
    parser.add_argument('--worker', type=Path, default=HERE / 'reader-worker.R')
    parser.add_argument('--public-workers-root', type=Path,
                        default=Path('/private/tmp/dta-compact-reader-facts/benchmarks/remaining-compact-kernels'))
    parser.add_argument('--target-cpu', type=float, choices=(0.15, 0.3), default=0.3)
    parser.add_argument('--qualify-only', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    worker, generator, controller = args.worker.resolve(), args.generator.resolve(), Path(__file__).resolve()
    libraries = {'baseline': args.baseline_library.resolve(), 'candidate': args.candidate_library.resolve()}
    receipts = {'baseline': args.baseline_receipt.resolve(), 'candidate': args.candidate_receipt.resolve()}
    directory = args.fixtures.resolve()
    public_workers = {name: (args.public_workers_root / name).resolve() for name in ('worker.R', 'dense-worker.R')}

    def binding():
        return dict(worker_sha256=sha(worker), generator_sha256=sha(generator), controller_sha256=sha(controller),
                    public_worker_sha256={name: sha(path) for name, path in public_workers.items()},
                    inputs=fixture_binding(directory),
                    builds={role: build_binding(libraries[role], receipts[role]) for role in libraries})

    before = binding()
    (output / 'before.json').write_text(json.dumps(before, indent=2) + '\n')
    mode = 'qualify' if args.qualify_only else 'measure'
    paired_fields = ('position', 'width', 'input_hash', 'rank_hash', 'input_missing', 'zero_observed',
                     'result_hash', 'missing_hash', 'result_missing', 'result_storage',
                     'source_metadata_hash', 'result_metadata_hash', 'cleared_hash', 'mutation_checked',
                     'compact_before', 'compact_after', 'materialized_before', 'materialized_after',
                     'retained', 'chunks', 'automatic_gc_included', 'qualification_calls',
                     'mutation_source_compact', 'mutation_source_materialized',
                     'mutation_source_retained', 'mutation_source_chunks')
    all_rows, commands, rounds = [], [], []
    paired_rounds = 1 if args.qualify_only else 6
    for round_number in range(1, paired_rounds + 1):
        order = ('baseline', 'candidate') if round_number % 2 else ('candidate', 'baseline')
        observed = {}
        for build_position, role in enumerate(order, 1):
            csv_path = output / f'{role}-round{round_number}.csv'
            log_path = output / f'{role}-round{round_number}.log'
            command = ['Rscript', str(worker), str(libraries[role]), str(round_number), str(csv_path),
                       role, mode, str(directory), str(args.target_cpu)]
            started = datetime.datetime.now(datetime.timezone.utc).isoformat()
            with log_path.open('w') as log:
                run = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, cwd=HERE)
            commands.append(dict(round=round_number, role=role, position=build_position, command=command,
                                 cwd=str(HERE), started_utc=started, exit_code=run.returncode))
            require(run.returncode == 0, 'Reader worker qualification failed: ' + str(log_path))
            with csv_path.open(newline='') as stream:
                rows = list(csv.DictReader(stream))
            observed[role] = validate(rows, round_number, role, mode, before['inputs'])
            all_rows.extend(dict(build=role, build_position=build_position, **row) for row in rows)
            require(binding() == before, 'Consumed worker, source, installed library or fixture changed')
        for key in observed['baseline']:
            require(all(observed['baseline'][key][field] == observed['candidate'][key][field]
                        for field in paired_fields), 'Paired semantic/state difference: ' + str(key))
        if not args.qualify_only:
            for fixture in FIXTURES:
                for format in FORMATS:
                    item = dict(round=round_number, fixture=fixture, format=format, build_order=list(order))
                    for clock in ('cpu', 'wall'):
                        ms = {role: {str(count): 1000 * float(observed[role][(fixture, format, count)][clock]) /
                                     int(observed[role][(fixture, format, count)]['repetitions'])
                                     for count in OPERATIONS} for role in libraries}
                        item[clock + '_ms'] = ms
                        item['reader_' + clock + '_cost_ratio'] = ms['candidate']['0'] / ms['baseline']['0']
                        item['reader_' + clock + '_delta_ms'] = ms['candidate']['0'] - ms['baseline']['0']
                        for count, name in ((1, 'one'), (5, 'five')):
                            item[name + '_operation_' + clock + '_workflow_speedup'] = ms['baseline'][str(count)] / ms['candidate'][str(count)]
                            item[name + '_operation_' + clock + '_workflow_saved_ms'] = ms['baseline'][str(count)] - ms['candidate'][str(count)]
                    rounds.append(item)
    if not args.qualify_only:
        for role in libraries:
            for fixture in FIXTURES:
                for format in FORMATS:
                    for count in OPERATIONS:
                        positions = [int(row['position']) for row in all_rows if row['build'] == role and
                                     row['fixture'] == fixture and row['format'] == format and int(row['operations']) == count]
                        require(len(set(positions)) == 6 and sum(positions) == 39 and
                                sum(position <= 6 for position in positions) == 3, 'Unbalanced phase positions')
    require(binding() == before, 'Final source/file/library binding changed')
    with (output / 'raw.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(all_rows[0]))
        writer.writeheader()
        writer.writerows(all_rows)
    fields = [name for name in rounds[0] if name.endswith(('_cost_ratio', '_delta_ms', '_workflow_speedup', '_workflow_saved_ms'))] if rounds else []
    summary = dict(status='PASS', mode=mode, paired_rounds=paired_rounds, observations=len(all_rows),
                   before_after_equal=True, before=before, commands=commands, rounds=rounds,
                   medians={fixture + '/' + format: {name: statistics.median(item[name] for item in rounds
                                                                          if item['fixture'] == fixture and item['format'] == format)
                                                    for name in fields}
                            for fixture in FIXTURES for format in FORMATS} if rounds else {},
                   scope='Original dense FLOAT/random_half and sparse INT million-row fixtures, each saved once as DTA and uncompressed profiled Arrow. Public reader-only/+one/+five same-source reciprocal workflows with threads=1. Six alternating fresh-process build pairs; each phase occupies six distinct positions with mean 6.5 and three positions per half. CPU and elapsed include all reader/result allocations and automatic GC. Exact input/output bits, storage, missing masks/cache mutation, facts, immutable sources and native calls qualified outside clocks. Input files, complete installed packages, build receipts/source inventories and private/public scripts bound before/after. Warm OS file cache; identical small workflow-list bookkeeping included. No cold-disk, parallel-worker, bare-construction or universal performance claim.',
                   artifact_sha256={path.name: sha(path) for path in output.iterdir() if path.is_file()})
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(dict(status='PASS', mode=mode, observations=len(all_rows), medians=summary['medians']), indent=2))


if __name__ == '__main__':
    main()
