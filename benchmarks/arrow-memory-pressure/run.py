#!/usr/bin/env python3
"""Compare small Arrow reads while an unrelated retained dataset remains live."""
import argparse
from collections import Counter
import csv
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import platform
import statistics
import subprocess

HERE = Path(__file__).resolve().parent
ORDERS = [('none', '63', '65'), ('63', '65', 'none'), ('65', 'none', '63'),
          ('65', '63', 'none'), ('none', '65', '63'), ('63', 'none', '65')]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def write_csv(path, rows):
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def validate_rows(rows):
    expected = {(r, v, c, s) for r in range(1, 7) for v in ('baseline', 'candidate')
                for c in ('none', '63', '65') for s in ('double', 'float')}
    actual = Counter((int(r['round']), r['variant'], r['condition'], r['storage']) for r in rows)
    if actual != Counter({key: 1 for key in expected}):
        raise RuntimeError('observations must cover every case exactly once per round')
    for row in rows:
        repetitions = 200 if row['variant'] == 'baseline' and row['condition'] == '65' else 2000
        cpu = float(row['cpu'])
        if int(row['repetitions']) != repetitions or not math.isfinite(cpu) or cpu <= 0:
            raise RuntimeError('invalid repetition count or CPU interval')
        if row['variant'] == 'candidate' and float(row['gc_attempts']) != 0:
            raise RuntimeError('candidate repeated a forced collection')
    for condition in ('none', '63', '65'):
        for storage in ('double', 'float'):
            selected = [r for r in rows if r['condition'] == condition and r['storage'] == storage]
            if len({r['signature'] for r in selected}) != 1 or len({r['held_signature'] for r in selected}) != 1:
                raise RuntimeError('result or retained input signature differs across builds or rounds')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    builds = {name: getattr(args, name).resolve() for name in ('baseline', 'candidate')}
    fixtures = args.fixtures.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    spec = importlib.util.spec_from_file_location('build_records', HERE.parent / 'native-operations/run.py')
    records = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(records)
    files = [HERE / name for name in ('run.py', 'worker.R', 'prepare.R')]
    files += [fixtures / name for name in ('retained-63.arrow', 'retained-65.arrow',
                                         'tiny-double.arrow', 'tiny-float.arrow', 'tiny-reference.rds')]

    def binding():
        return {'builds': {name: records.inventory(build, name) for name, build in builds.items()},
                'files': {path.name: sha(path) for path in files}, 'platform': platform.platform()}

    before = binding()
    write_json(output / 'provenance-before.json', before)
    write_json(output / 'protocol.json', {
        'rounds': 6, 'condition_order': ORDERS,
        'build_order': 'baseline first in odd rounds; candidate first in even rounds',
        'storage_order': 'double first in odd rounds; float first in even rounds',
        'repetitions': '2000 per interval, except baseline 65 MiB uses 200 due to forced GC cost',
        'interval': 'Public read calls include dispatch, file I/O, verification, allocations and automatic/forced GC. Setup, warm read, explicit GC, qualification and hashing excluded.',
        'threads': 1, 'checksums': True, 'fresh_process_per_observation': True,
        'controls': 'No retained storage, 63 MiB and 65 MiB. Tiny ordinary-double and compact-float results.',
        'limits': 'One warm-cache host; repeated eight-row reads. No throughput or memory-bound claim for arbitrary file sizes or cold storage.',
    })
    rows = []
    for round_no, conditions in enumerate(ORDERS, 1):
        variants = ['baseline', 'candidate'] if round_no % 2 else ['candidate', 'baseline']
        storages = ['double', 'float'] if round_no % 2 else ['float', 'double']
        for condition in conditions:
            for storage in storages:
                for variant in variants:
                    repetitions = 200 if variant == 'baseline' and condition == '65' else 2000
                    prefix = output / f'{round_no:02}-{condition}-{storage}-{variant}'
                    with prefix.with_suffix('.log').open('w') as log:
                        subprocess.run(['Rscript', '--vanilla', str(HERE / 'worker.R'),
                                        str(builds[variant] / 'library'), str(fixtures), condition, storage,
                                        str(repetitions), str(prefix.with_suffix('.csv')), variant],
                                       stdout=log, stderr=subprocess.STDOUT, check=True)
                    batch = list(csv.DictReader(prefix.with_suffix('.csv').open(newline='')))
                    if len(batch) != 1:
                        raise RuntimeError('worker must produce exactly one observation')
                    row = batch[0]
                    if (row['condition'], row['storage'], int(row['repetitions'])) != (condition, storage, repetitions):
                        raise RuntimeError('worker returned a different case')
                    if float(row['cpu']) <= 0:
                        raise RuntimeError('worker CPU interval must be positive')
                    rows.append({'round': round_no, 'variant': variant, **row})
        print(f'Completed round {round_no}: 12 qualified observations', flush=True)
    after = binding()
    write_json(output / 'provenance-after.json', after)
    if before != after:
        raise RuntimeError('build, controller or fixture changed during measurement')
    validate_rows(rows)
    summaries = []
    for condition in ('none', '63', '65'):
        for storage in ('double', 'float'):
            selected = [r for r in rows if r['condition'] == condition and r['storage'] == storage]
            values = {f'{variant}_{metric}': statistics.median(float(r[metric]) / int(r['repetitions'])
                      for r in selected if r['variant'] == variant)
                      for variant in builds for metric in ('cpu', 'wall', 'gc_cpu')}
            summaries.append({'condition': condition, 'storage': storage, **values,
                              'cpu_speedup': values['baseline_cpu'] / values['candidate_cpu']})
    write_csv(output / 'raw.csv', rows)
    write_csv(output / 'summary.csv', summaries)
    write_json(output / 'completion.json', {'observations': len(rows), 'source_bindings_unchanged': True,
               'full_numeric_values_storage_and_signatures_match': True,
               'candidate_forced_attempts': sum(float(r['gc_attempts']) for r in rows if r['variant'] == 'candidate')})


if __name__ == '__main__':
    main()
