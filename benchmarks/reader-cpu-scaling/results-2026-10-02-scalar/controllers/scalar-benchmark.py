#!/usr/bin/env python3
"""Private scalar-access benchmark. Execute only in an exclusive window."""
import argparse
import csv
import fnmatch
import importlib.util
import json
import math
import os
from pathlib import Path
import platform
import random
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(os.environ['DTATOOLS_SCALAR_WORK'])
REPO = Path(os.environ['DTATOOLS_REPO'])
HARNESS = REPO / 'benchmarks/r-file-readers'
BUILDS = {'current': Path(os.environ['DTATOOLS_DECODE_WORK']) / 'candidate-gather4-v2',
          'dispatch': ROOT / 'candidate-dispatch-v2', 'reverse': ROOT / 'candidate-reverse',
          'sourcecheck': ROOT / 'candidate-sourcecheck'}
METRICS = ('operation_cpu', 'operation_wall', 'operation_user', 'operation_system',
           'cpu_per_scan', 'wall_per_scan', 'cpu_ns_per_value', 'wall_ns_per_value',
           'process_cpu', 'process_wall', 'process_user', 'process_system', 'maxrss_bytes')

def require(value, message):
    if not value:
        raise RuntimeError(message)

def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def json_write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')

def csv_write(path, rows):
    if not rows:
        return
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

def cases():
    result = []
    for fmt in ('dta', 'arrow'):
        for kind in ('byte', 'int', 'long', 'float'):
            operations = ('mask', 'sequential', 'reverse', 'permuted') if kind in ('byte', 'float') else ('mask',)
            for representation in ('proxy', 'direct', 'plain'):
                for operation in operations:
                    # A typed direct mask can dispatch an S3 bulk method;
                    # it is not evidence about the scalar callback path.
                    if representation == 'direct' and operation == 'mask':
                        continue
                    result.append(dict(id=f'{fmt}-{kind}-{representation}-{operation}', format=fmt,
                        kind=kind, representation=representation, operation=operation,
                        screen=representation == 'proxy' and kind in ('byte', 'float')))
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, default=ROOT / 'screen')
    parser.add_argument('--variants', default='current,sourcecheck,dispatch,reverse')
    parser.add_argument('--cases', default='screen', help='screen, all, or comma-separated case IDs/globs')
    parser.add_argument('--rounds', type=int, default=4)
    parser.add_argument('--reps', type=int, default=4)
    parser.add_argument('--reference', default='current')
    parser.add_argument('--fixtures', type=Path, default=Path(os.environ['DTATOOLS_SCALAR_FIXTURES']))
    parser.add_argument('--list-cases', action='store_true')
    args = parser.parse_args()
    available = cases()
    if args.list_cases:
        print('\n'.join(case['id'] + (' [screen]' if case['screen'] else '') for case in available))
        return
    variants = args.variants.split(',')
    require(len(set(variants)) == len(variants) and all(v in BUILDS for v in variants), 'Unknown/duplicate variant')
    require(args.rounds > 0 and args.rounds % 2 == 0 and args.reps > 0, 'Rounds must be positive/even and reps positive')
    require(args.reference in variants, 'Reference variant must be included')
    require(sys.platform in ('darwin', 'linux'), 'Unsupported wait4 RSS units')
    selected = [case for case in available if args.cases == 'all' or
                (args.cases == 'screen' and case['screen']) or
                any(fnmatch.fnmatchcase(case['id'], pattern) for pattern in args.cases.split(','))]
    require(selected, 'No cases match')
    # Filter diagnostic overrides before runtime capture and all children.
    cleared = sorted(k for k in os.environ if k.startswith(('DIAGNOSTIC_ARROW_', 'DTATOOLS_EXPERIMENT_', 'DTA_READ_PERF_')))
    for key in cleared:
        del os.environ[key]
    bench = load_module('scalar_reader_helpers', HARNESS / 'run.py')
    recorder = load_module('scalar_build_recorder', HARNESS / 'record-builds.py')
    rscript = str(Path(shutil.which('Rscript')).resolve())
    output = args.work.resolve()
    output.mkdir(parents=True, exist_ok=False)
    jobs = output / 'private-jobs'
    jobs.mkdir()
    libraries = {v: BUILDS[v] / 'library' for v in variants}
    fixture_files = {name: args.fixtures.resolve() / ('compact.' + name) for name in ('dta', 'arrow', 'rds')}
    bound_files = {'controller': Path(__file__).resolve(), 'worker': ROOT / 'scalar-worker.R',
        'probe_source': ROOT / 'scalar-access-probe.c', 'probe_dll': ROOT / 'scalar_access_probe.so',
        'probe_build_receipt': ROOT / 'scalar-probe-build.json', 'probe_check_receipt': ROOT / 'scalar-probe-check.json',
        'helpers': HARNESS / 'run.py', 'recorder': HARNESS / 'record-builds.py', 'runtime': HARNESS / 'runtime.R'}
    probe_receipt = json.loads(bound_files['probe_build_receipt'].read_text())
    require(probe_receipt['returncode'] == 0, 'Probe build was unsuccessful')
    for key in ('probe_source', 'probe_dll'):
        require(bench.sha(bound_files[key]) == probe_receipt['files'][str(bound_files[key])],
                'Probe artifact differs from build receipt')
    require(json.loads(bound_files['probe_check_receipt'].read_text())['returncode'] == 0,
            'Probe correctness checks failed')

    def bindings():
        proofs = {v: recorder.verified_receipt(BUILDS[v], 'candidate') for v in variants}
        return dict(builds={v: dict(receipt=p[0], receipt_sha256=p[2]) for v, p in proofs.items()},
            installed={v: bench.inventory(libraries[v]) for v in variants},
            inputs={k: dict(path=str(p), bytes=p.stat().st_size, sha256=bench.sha(p)) for k, p in fixture_files.items()},
            files={k: dict(path=str(p), sha256=bench.sha(p)) for k, p in bound_files.items()},
            runtime={v: bench.runtime(rscript, libraries[v]) for v in variants},
            rscript=dict(path=rscript, sha256=bench.sha(rscript)),
            host=dict(platform=platform.platform(), machine=platform.machine(), logical_cpus=os.cpu_count()),
            thread_environment={k: os.environ.get(k) for k in ('OMP_NUM_THREADS', 'OMP_THREAD_LIMIT',
                'OPENBLAS_NUM_THREADS', 'ARROW_NUM_THREADS', 'VECLIB_MAXIMUM_THREADS', 'MKL_NUM_THREADS')})

    before = bindings()
    for variant in variants:
        require(before['installed'][variant] == before['builds'][variant]['receipt']['installed_inventory'],
                'Installed inventory differs from receipt')
        (output / (variant + '.patch')).write_bytes((BUILDS[variant] / 'source.patch').read_bytes())
    json_write(output / 'provenance-before.json', before)
    json_write(output / 'protocol.json', dict(variants=variants, reference=args.reference,
        comparison_boundary='all builds are source-bound candidate receipts; current is previous gather4-v2 candidate',
        cases=selected, rounds=args.rounds, internal_reps=args.reps,
        plain_reps='max(configured reps, 128) for masks; max(configured reps, 16) for scalar scans',
        order='case and variant rotations, each followed by exact reversed setting order; balanced pairwise precedence',
        interval='configured repetitions retaining only the latest result, with plain-control minima; load/GC/reference/exact pre/post validation outside; automatic GC and operation outputs inside',
        interpretation='operation metrics total all repetitions; whole-process metrics include both input reads and exact qualification',
        cache='warm filesystem; fresh R process for every observation; one exact validation operation precedes the timer and may populate a scalar span cache',
        permutation='deterministic coprime stride; all positions once; no index-vector allocation',
        cleared_environment=cleared, command=sys.argv))

    records = []
    for pair in range(args.rounds // 2):
        case_shift = (pair * max(1, len(selected) // (args.rounds // 2))) % len(selected)
        case_order = selected[case_shift:] + selected[:case_shift]
        settings = []
        for i, case in enumerate(case_order):
            shift = (pair + i) % len(variants)
            variant_order = variants[shift:] + variants[:shift]
            settings.extend((case, variant) for variant in variant_order)
        for flip in (False, True):
            round_number = pair * 2 + 1 + int(flip)
            for position, (case, variant) in enumerate(reversed(settings) if flip else settings, 1):
                key = f'{round_number:02}-{case["id"]}-{variant}'
                reps = max(args.reps, 128 if case['operation'] == 'mask' else 16) if case['representation'] == 'plain' else args.reps
                command = [rscript, '--vanilla', str(ROOT / 'scalar-worker.R'), str(libraries[variant]),
                    str(args.fixtures.resolve()), str(ROOT / 'scalar_access_probe.so'), case['format'], case['kind'],
                    case['representation'], case['operation'], str(reps)]
                log = jobs / (key + '.log')
                started = time.monotonic()
                with log.open('w') as stream:
                    child = subprocess.Popen(command, env=bench.environment(libraries[variant]), stdout=stream, stderr=subprocess.STDOUT)
                    try:
                        _, status, usage = os.wait4(child.pid, 0)
                        elapsed = time.monotonic() - started
                        child.returncode = os.waitstatus_to_exitcode(status)
                    except BaseException:
                        child.kill()
                        child.wait()
                        raise
                require(child.returncode == 0, 'Worker failed: ' + key + '; see ' + str(log))
                fields = [line.split('\t') for line in log.read_text().splitlines() if line.startswith('SCALAR\t')]
                require(len(fields) == 1 and len(fields[0]) == 14, 'Invalid worker record: ' + key)
                fields = fields[0]
                wall, user, system = map(float, fields[1:4])
                require(all(math.isfinite(x) and x >= 0 for x in (wall, user, system)), 'Invalid clocks')
                require(int(fields[5]) == reps and fields[6:8] == ['1', '1'] and fields[13] == 'exact', 'Validation failure')
                rows = int(fields[4])
                require(rows > 0 and int(fields[12]) > 0, 'Empty fixture/selection')
                row = dict(round=round_number, position=position, case=case['id'], variant=variant,
                    operation_wall=wall, operation_user=user, operation_system=system, operation_cpu=user + system,
                    cpu_per_scan=(user + system) / reps, wall_per_scan=wall / reps,
                    cpu_ns_per_value=(user + system) * 1e9 / reps / rows, wall_ns_per_value=wall * 1e9 / reps / rows,
                    process_wall=elapsed, process_user=usage.ru_utime, process_system=usage.ru_stime,
                    process_cpu=usage.ru_utime + usage.ru_stime,
                    maxrss_bytes=usage.ru_maxrss if sys.platform == 'darwin' else usage.ru_maxrss * 1024,
                    rows=rows, reps=reps, lazy_before=True, lazy_after=True,
                    checksum=float(fields[8]), na_count=float(fields[9]), retained=int(fields[10]), chunks=int(fields[11]),
                    selected_count=int(fields[12]), exact_validation=True, command=command, log_sha256=bench.sha(log))
                records.append(row)
                with (output / 'raw.jsonl').open('a') as stream:
                    stream.write(json.dumps(row, sort_keys=True) + '\n')
            print('Completed scalar round', round_number, flush=True)

    summary = []
    paired = []
    draws = [random.Random(20261002 + draw).choices(range(args.rounds), k=args.rounds) for draw in range(10000)]
    for case in selected:
        groups = {v: {row['round']: row for row in records if row['case'] == case['id'] and row['variant'] == v} for v in variants}
        for variant, rows in groups.items():
            require(set(rows) == set(range(1, args.rounds + 1)), 'Incomplete rounds')
            group_reps = {row['reps'] for row in rows.values()}
            require(len(group_reps) == 1, 'Mixed repetition counts within case')
            summary.append(dict(case=case['id'], variant=variant, observations=len(rows), reps=group_reps.pop(),
                **{metric + '_median': statistics.median(row[metric] for row in rows.values()) for metric in METRICS}))
            if variant == args.reference:
                continue
            old = groups[args.reference]
            for metric in METRICS:
                ratios = [rows[i][metric] / old[i][metric] for i in range(1, args.rounds + 1)
                          if old[i][metric] > 0 and rows[i][metric] > 0]
                boots = sorted(statistics.median(ratios[j] for j in draw) for draw in draws) if len(ratios) == args.rounds else []
                paired.append(dict(case=case['id'], reference=args.reference, variant=variant, metric=metric,
                    pairs=args.rounds, resolved_pairs=len(ratios),
                    paired_percent_change=100 * (statistics.median(ratios) - 1) if boots else None,
                    lower95_percent=100 * (boots[249] - 1) if boots else None,
                    upper95_percent=100 * (boots[9749] - 1) if boots else None))
    csv_write(output / 'raw.csv', [{k: v for k, v in row.items() if k != 'command'} for row in records])
    csv_write(output / 'summary.csv', summary)
    csv_write(output / 'paired-summary.csv', paired)
    after = bindings()
    require(before == after, 'Pre/post bindings changed')
    json_write(output / 'provenance-after.json', after)
    json_write(output / 'completion.json', dict(observations=len(records), bindings_matched=True, exact_validation=True))
    print('Completed', len(records), 'fresh-process observations; bindings matched', flush=True)

if __name__ == '__main__':
    main()
