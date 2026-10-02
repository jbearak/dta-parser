#!/usr/bin/env python3
"""Compare two installed source builds in an exclusive timing window."""
import argparse
from collections import Counter
import csv
import difflib
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys

HERE = Path(__file__).resolve().parent

OPERATIONS = ('is_tagged_missing', 'missing_tag', 'anyNA', 'dta_total',
              'dta_row_total', 'mean', 'range', 'summ', 'dta_match', 'dta_in',
              'multiply', 'divide', 'add')
EXPECTED_CASES = {
    (format, width, operation, representation)
    for format in ('dta', 'arrow')
    for width in ('byte', 'int', 'long', 'float')
    for operation in OPERATIONS
    for representation in ('compact', 'ordinary')
} | {
    (format, width, operation, 'typed_double')
    for format in ('dta', 'arrow')
    for width in ('byte', 'int', 'long', 'float')
    for operation in ('multiply', 'divide', 'add')
} | {
    (format, width, 'anyNA_late', representation)
    for format in ('constructed', 'retained')
    for width in ('byte', 'int', 'long', 'float')
    for representation in ('compact', 'ordinary')
}


def validate_round(rows, round_number):
    fields = ('format', 'width', 'operation', 'representation')
    counts = Counter(tuple(row[key] for key in fields) for row in rows)
    if counts != Counter({key: 1 for key in EXPECTED_CASES}):
        raise RuntimeError('worker results do not contain the complete unique case matrix')
    if any(int(row['round']) != round_number or int(row['iterations']) <= 0
           or int(row['rows']) != 1000000 for row in rows):
        raise RuntimeError('worker round, repetitions or input row count is invalid')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(build, variant):
    # The existing clean-build recorder checks the Git base, complete source
    # inventory, compiler inputs/log, and built/installed DLL equality. Merely
    # hashing a source tree beside a DLL would also accept a stale binary.
    path = HERE.parent / 'r-file-readers' / 'record-builds.py'
    spec = importlib.util.spec_from_file_location('native_operation_build_records', path)
    records = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(records)
    receipt, patch, receipt_sha256 = records.verified_receipt(build, variant)
    return {'source': receipt['source_inventory'],
            'installed': receipt['installed_inventory'],
            'receipt': receipt, 'receipt_sha256': receipt_sha256}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def write_csv(path, rows):
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=6)
    args = parser.parse_args()
    if args.rounds < 6 or args.rounds % 6:
        parser.error('rounds must be a positive multiple of six to balance build and arithmetic order')
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    builds = {'baseline': args.baseline.resolve(), 'candidate': args.candidate.resolve()}
    fixtures = args.fixtures.resolve()
    worker = HERE / 'worker.R'
    before = {name: inventory(build, name) for name, build in builds.items()}
    inputs = {name: digest(fixtures / ('compact.' + name)) for name in ('dta', 'arrow', 'rds')}
    controllers = {p.name: digest(p) for p in (Path(__file__).resolve(), worker)}
    write_json(out / 'provenance-before.json', {'builds': before, 'fixtures': inputs,
               'controllers': controllers, 'platform': platform.platform(),
               'machine': platform.machine(), 'logical_cpus': os.cpu_count(),
               'R': subprocess.check_output(['R', '--version'], text=True).splitlines()[0]})
    # Preserve the exact source delta, including new modules and tests.
    old = builds['baseline'] / 'source'
    new = builds['candidate'] / 'source'
    patch = []
    for name in sorted(set(before['baseline']['source']) | set(before['candidate']['source'])):
        if before['baseline']['source'].get(name) == before['candidate']['source'].get(name):
            continue
        a = (old / name).read_text().splitlines(keepends=True) if (old / name).exists() else []
        b = (new / name).read_text().splitlines(keepends=True) if (new / name).exists() else []
        patch.extend(difflib.unified_diff(a, b, fromfile='a/' + name, tofile='b/' + name))
    (out / 'source.patch').write_text(''.join(patch))
    write_json(out / 'protocol.json', {
        'rounds': args.rounds,
        'baseline': 'Git commit ' + before['baseline']['receipt']['base_commit'],
        'baseline_commit': before['baseline']['receipt']['base_commit'],
        'candidate_commit': before['candidate']['receipt']['base_commit'],
        'interval': 'Preloaded public operation repetitions; explicit GC, reader calls, source construction, qualification and result hashing excluded; automatic GC and result allocation included.',
        'order': 'Alternate build order each round; fixed case order. Two-representation order alternates; arithmetic rotates and reverses compact/typed-double/ordinary order in balanced six-round cycles.',
        'repetitions': 'Untimed calibration runs for at least 20 ms and chooses a fixed count targeting at least 150 ms per retained interval; initial counts can exceed this target for slow operations.',
        'synthetic_control': 'anyNA_late uses one million ones with only the final row missing, constructed and retained in 8192-row chunks.',
        'source': 'Source delta and SHA256 inventories of source, installed R code, DLLs, fixtures and controllers retained.',
        'limits': 'One host, deterministic million-row fixtures, warm repeated operations. Arithmetic adds dta_double controls to distinguish typed result policy from bare arithmetic. Does not measure ingestion or promise ordinary-double parity for every operation.',
    })
    rows = []
    for round_number in range(1, args.rounds + 1):
        order = ['baseline', 'candidate'] if round_number % 2 else ['candidate', 'baseline']
        for variant in order:
            result = out / f'{round_number:02}-{variant}.csv'
            log = out / f'{round_number:02}-{variant}.log'
            command = ['Rscript', '--vanilla', str(worker), str(builds[variant] / 'library'),
                       str(fixtures), str(round_number), str(result)]
            with log.open('w') as stream:
                subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=True)
            with result.open(newline='') as stream:
                observations = list(csv.DictReader(stream))
            validate_round(observations, round_number)
            rows.extend(dict(variant=variant, **row) for row in observations)
            print(f'Completed round {round_number}: {variant}', flush=True)
    after = {name: inventory(build, name) for name, build in builds.items()}
    write_json(out / 'provenance-after.json', {'builds': after,
               'fixtures': {name: digest(fixtures / ('compact.' + name)) for name in inputs},
               'controllers': {p.name: digest(p) for p in (Path(__file__).resolve(), worker)}})
    if before != after or inputs != {name: digest(fixtures / ('compact.' + name)) for name in inputs}:
        raise RuntimeError('build or fixture changed during timing')
    if controllers != {p.name: digest(p) for p in (Path(__file__).resolve(), worker)}:
        raise RuntimeError('controller changed during timing')
    write_csv(out / 'raw.csv', rows)
    # Complete-result hashes and output storage must agree between builds.
    groups = {}
    for row in rows:
        case = '-'.join(row[k] for k in ('format', 'width', 'operation'))
        groups.setdefault((case, row['representation']), []).append(row)
    for key, observations in groups.items():
        if len({(r['result_sha256'], r['full_result_sha256'], r['result_storage']) for r in observations}) != 1:
            raise RuntimeError(f'result or storage differs across builds/rounds: {key}')
    for row in rows:
        if (row['variant'] == 'candidate' and row['representation'] in {'compact', 'typed_double'}
                and row['operation'] in {'multiply', 'divide', 'add'}
                and int(float(row['native_scalar_calls'])) != int(row['iterations'])):
            raise RuntimeError(f"arithmetic kernel was not used: {row['format']}/{row['width']}/{row['operation']}")
    summary = []
    for key in sorted(groups):
        observations = groups[key]
        values = {}
        for variant in builds:
            selected = [r for r in observations if r['variant'] == variant]
            values[variant] = {metric: statistics.median(float(r[{'cpu': 'cpu_seconds', 'wall': 'elapsed_seconds'}[metric]]) / int(r['iterations']) for r in selected)
                               for metric in ('cpu', 'wall')}
        summary.append(dict(case=key[0], representation=key[1],
            baseline_cpu=values['baseline']['cpu'], candidate_cpu=values['candidate']['cpu'],
            baseline_wall=values['baseline']['wall'], candidate_wall=values['candidate']['wall'],
            cpu_speedup=values['baseline']['cpu'] / values['candidate']['cpu']
                if values['candidate']['cpu'] else None))
    write_csv(out / 'summary.csv', summary)
    write_json(out / 'completion.json', {'observations': len(rows), 'exact_results': True,
               'provenance_unchanged': True, 'source_patch_sha256': digest(out / 'source.patch')})


if __name__ == '__main__':
    main()
