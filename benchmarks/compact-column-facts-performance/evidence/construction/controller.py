#!/usr/bin/env python3
"""Compare compact construction plus zero/one/five operations in paired processes.

Run only with an exclusive CPU timing slot. No builds, dependency installs or
source edits occur here. Every semantic assertion runs outside worker clocks.
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
            'Build receipt did not qualify unchanged successful source')
    dll = namespace_dll(library)
    require(sha(dll) == receipt['dll_sha256'],
            'Installed library does not match build receipt')
    source = Path(receipt['command'][-1]).resolve()
    inventory = receipt['source_inventory']
    require(all((source / path).is_file() and sha(source / path) == digest
                for path, digest in inventory.items()),
            'Build source copy differs from its receipt')
    return dict(receipt=str(receipt_path), receipt_sha256=sha(receipt_path),
                library=str(library), installed_inventory=tree_inventory(library / 'dtatools'),
                source=str(source), source_inventory=inventory,
                source_head=receipt.get('source_head'), dll_sha256=sha(dll))


def validate(rows, round_number, variant, mode):
    require(len(rows) == 6, 'Missing or duplicate workflow phase')
    result = {(row['fixture'], int(row['operations'])): row for row in rows}
    require(set(result) == {(fixture, count) for fixture in FIXTURES for count in OPERATIONS},
            'Unexpected fixture/phase keys')
    require({int(row['position']) for row in rows} == set(range(1, 7)),
            'Phase positions are incomplete')
    for (fixture, operations), row in result.items():
        require(row['round'] == str(round_number) and row['variant'] == variant and
                row['mode'] == mode and row['rows'] == '1000000', 'Unexpected coordinate')
        repetitions = int(row['repetitions'])
        require(repetitions > 0 and int(row['qualification_calls']) == operations and
                int(row['native_calls']) == operations * (1 if mode == 'qualify' else repetitions),
                'Incorrect native work count')
        cpu, wall = float(row['cpu']), float(row['wall'])
        require(math.isfinite(cpu) and math.isfinite(wall), 'Non-finite clock record')
        if mode == 'measure':
            require(cpu > 0 and wall > 0, 'Invalid clock record')
        else:
            require(float(row['cpu']) == 0 and float(row['wall']) == 0, 'Qualification ran clocks')
        require(row['mutation_checked'] == row['automatic_gc_included'] == 'TRUE' and
                row['compact_before'] == row['compact_after'] == 'TRUE' and
                row['materialized_before'] == row['materialized_after'] == 'FALSE',
                'Source, cache, mutation, or GC qualification changed')
        require(row['input_missing'] == ('500000' if fixture == 'dense_float' else '1003'),
                'Original fixture missing count changed')
        require(row['result_storage'] == ('int' if fixture == 'sparse_int' and operations == 0 else 'float'),
                'Constructor/result storage changed')
        require(int(row['result_missing']) == int(row['input_missing']) +
                (int(row['zero_observed']) if operations else 0), 'Missing/zero policy changed')
        for field in ('input_hash', 'rank_hash', 'result_hash', 'missing_hash',
                      'source_metadata_hash', 'result_metadata_hash', 'cleared_hash'):
            require(len(row[field]) == 64, 'Missing oracle digest: ' + field)
        if fixture == 'dense_float':
            require(row['input_hash'] == 'b6b60ef8bb430be90e7239dd64b807cda383733b1048ca6748094e19e1003f06' and
                    row['rank_hash'] == '6d001f63d9ce5612a17ed6ff62e0d269d6d862dde318265b90a63af3b92b0706' and
                    row['zero_observed'] == '48', 'Original dense fixture changed')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-library', type=Path, required=True)
    parser.add_argument('--candidate-library', type=Path, required=True)
    parser.add_argument('--baseline-receipt', type=Path, required=True)
    parser.add_argument('--candidate-receipt', type=Path, required=True)
    parser.add_argument('--worker', type=Path, default=HERE / 'construction-worker.R')
    parser.add_argument('--public-workers-root', type=Path,
                        default=Path('/private/tmp/dta-compact-float-facts/benchmarks/remaining-compact-kernels'))
    parser.add_argument('--target-cpu', type=float, choices=(0.15, 0.3), default=0.3)
    parser.add_argument('--qualify-only', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    worker = args.worker.resolve()
    controller = Path(__file__).resolve()
    libraries = {'baseline': args.baseline_library.resolve(),
                 'candidate': args.candidate_library.resolve()}
    receipts = {'baseline': args.baseline_receipt.resolve(),
                'candidate': args.candidate_receipt.resolve()}
    public_workers = {name: (args.public_workers_root / name).resolve()
                      for name in ('worker.R', 'dense-worker.R')}
    before = dict(worker_sha256=sha(worker), controller_sha256=sha(controller),
                  public_worker_sha256={name: sha(path) for name, path in public_workers.items()},
                  builds={role: build_binding(libraries[role], receipts[role]) for role in libraries})
    (output / 'before.json').write_text(json.dumps(before, indent=2) + '\n')
    mode = 'qualify' if args.qualify_only else 'measure'
    paired_fields = ('position', 'pattern', 'width', 'input_hash', 'rank_hash', 'input_missing',
                     'zero_observed', 'result_hash', 'missing_hash', 'result_missing', 'result_storage',
                     'source_metadata_hash', 'result_metadata_hash', 'cleared_hash', 'mutation_checked',
                     'compact_before', 'compact_after', 'materialized_before', 'materialized_after',
                     'automatic_gc_included', 'qualification_calls')
    all_rows, commands, rounds = [], [], []
    for round_number in range(1, 7):
        order = ('baseline', 'candidate') if round_number % 2 else ('candidate', 'baseline')
        observed = {}
        for build_position, role in enumerate(order, 1):
            csv_path = output / f'{role}-round{round_number}.csv'
            log_path = output / f'{role}-round{round_number}.log'
            command = ['Rscript', str(worker), str(libraries[role]), str(round_number),
                       str(csv_path), role, mode, str(args.target_cpu)]
            started = datetime.datetime.now(datetime.timezone.utc).isoformat()
            with log_path.open('w') as log:
                run = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, cwd=HERE)
            commands.append(dict(round=round_number, role=role, position=build_position,
                                 command=command, cwd=str(HERE), started_utc=started,
                                 exit_code=run.returncode))
            require(run.returncode == 0, 'Worker qualification failed: ' + str(log_path))
            with csv_path.open(newline='') as stream:
                rows = list(csv.DictReader(stream))
            observed[role] = validate(rows, round_number, role, mode)
            all_rows.extend(dict(build=role, build_position=build_position, **row) for row in rows)
            require(sha(worker) == before['worker_sha256'] and sha(controller) == before['controller_sha256'],
                    'Worker or controller changed during experiment')
            require(build_binding(libraries[role], receipts[role]) == before['builds'][role],
                    'Installed library, build source or receipt changed during experiment')
        for key in observed['baseline']:
            require(all(observed['baseline'][key][field] == observed['candidate'][key][field]
                        for field in paired_fields), 'Paired semantic/state difference: ' + str(key))
        if not args.qualify_only:
            for fixture in FIXTURES:
                cpu_ms = {role: {str(count): 1000 * float(observed[role][(fixture, count)]['cpu']) /
                                       int(observed[role][(fixture, count)]['repetitions'])
                                 for count in OPERATIONS} for role in libraries}
                rounds.append(dict(round=round_number, fixture=fixture, build_order=list(order),
                    cpu_ms=cpu_ms,
                    constructor_cost_ratio=cpu_ms['candidate']['0'] / cpu_ms['baseline']['0'],
                    constructor_delta_ms=cpu_ms['candidate']['0'] - cpu_ms['baseline']['0'],
                    one_operation_workflow_speedup=cpu_ms['baseline']['1'] / cpu_ms['candidate']['1'],
                    one_operation_workflow_saved_ms=cpu_ms['baseline']['1'] - cpu_ms['candidate']['1'],
                    five_operation_workflow_speedup=cpu_ms['baseline']['5'] / cpu_ms['candidate']['5'],
                    five_operation_workflow_saved_ms=cpu_ms['baseline']['5'] - cpu_ms['candidate']['5']))
    for role in libraries:
        for fixture in FIXTURES:
            for count in OPERATIONS:
                positions = [int(row['position']) for row in all_rows
                             if row['build'] == role and row['fixture'] == fixture and int(row['operations']) == count]
                require(sorted(positions) == list(range(1, 7)), 'Unbalanced phase positions')
    after = dict(worker_sha256=sha(worker), controller_sha256=sha(controller),
                 public_worker_sha256={name: sha(path) for name, path in public_workers.items()},
                 builds={role: build_binding(libraries[role], receipts[role]) for role in libraries})
    require(before == after, 'Consumed library, source, controller, worker or receipt changed')
    with (output / 'raw.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(all_rows[0]))
        writer.writeheader()
        writer.writerows(all_rows)
    summary = dict(status='PASS', mode=mode, paired_rounds=6, observations=len(all_rows),
                   before_after_equal=True, before=before, commands=commands, rounds=rounds,
                   medians={fixture: {field: statistics.median(item[field] for item in rounds if item['fixture'] == fixture)
                                      for field in ('constructor_cost_ratio', 'constructor_delta_ms',
                                                    'one_operation_workflow_speedup', 'one_operation_workflow_saved_ms',
                                                    'five_operation_workflow_speedup', 'five_operation_workflow_saved_ms')}
                            for fixture in FIXTURES} if rounds else {},
                   phase_cpu_ms_medians={fixture: {role: {str(count): statistics.median(item['cpu_ms'][role][str(count)]
                                                                     for item in rounds if item['fixture'] == fixture)
                                                        for count in OPERATIONS} for role in libraries}
                                         for fixture in FIXTURES} if rounds else {},
                   scope='Original million-row dense random_half FLOAT and sparse INT fixtures. Compact construction plus zero, one or five reverse divisions on the same source; all allocations and automatic GC included in CPU clocks. Exact binary64/binary32 values, storage, missing masks/count-cache mutation, source state and native calls qualified outside clocks. Six alternating fresh-process build pairs, each phase in every position once. No bare-construction, reader, import or universal parity claim. Identical workflow-list bookkeeping is included for both builds.',
                   artifact_sha256={path.name: sha(path) for path in output.iterdir() if path.is_file()})
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(dict(status='PASS', mode=mode, observations=len(all_rows), medians=summary['medians']), indent=2))


if __name__ == '__main__':
    main()
