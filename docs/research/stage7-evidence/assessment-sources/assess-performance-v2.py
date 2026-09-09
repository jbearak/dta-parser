"""Independently check retained Stage7 timings, profiles and scalar native states."""
import argparse
import csv
from decimal import Decimal
import hashlib
import io
import itertools
import json
import math
from pathlib import Path
import re
import statistics


def require(value, message):
    if not value:
        raise RuntimeError(message)


def integer(value):
    number = Decimal(value)
    require(number.is_finite() and number == number.to_integral_value(), "Expected exact integer CSV value")
    return int(number)


def identity(path):
    return dict(path=str(path), resolved=str(path.resolve(strict=True)),
                bytes=path.stat().st_size, mode=oct(path.stat().st_mode & 0o777),
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def assess(directory, expected_receipt, expected_source, routes):
    receipt_path = directory / 'receipt.json'
    require(identity(receipt_path)['sha256'] == expected_receipt, 'Receipt identity differs')
    receipt = json.loads(receipt_path.read_text())
    require(receipt['status'] == 'complete', 'Incomplete receipt')
    manifest_path = Path(receipt['products']['path'])
    require(identity(manifest_path) == receipt['products'], 'Manifest identity differs')
    manifest = json.loads(manifest_path.read_text())
    products = {row['path']: row for row in manifest['products']}
    require(len(products) == len(manifest['products']), 'Duplicate products')
    consumed = []

    def read(path):
        require(str(path) in products, 'Unlisted product: ' + str(path))
        before = identity(path)
        require(before == products[str(path)], 'Product identity differs: ' + str(path))
        data = path.read_text()
        require(identity(path) == before, 'Read product changed')
        consumed.append(before)
        return data

    require(identity(directory / 'result.json') == receipt['result'], 'Result identity differs')
    result = json.loads(read(directory / 'result.json'))
    require(result['status'] == 'complete' and result['inputs_unchanged'] and
            result['input_binding_complete'] and result['source_sha'] == expected_source,
            'Wrong or incomplete execution')
    base = directory / 'results'
    rows = list(csv.DictReader(io.StringIO(read(base / 'operations.csv'))))
    workloads = ['summarise_one', 'summarise_width', 'reframe_half',
                 'group_modify_identity', 'group_nest', 'nest_by']
    shapes = set(itertools.product([100000, 1000000], [8, 16], [16, 128], workloads))
    shapes.update((1000000, 8, 1, workload) for workload in workloads)
    expected = {shape + (route,) for shape in shapes for route in routes}
    observed = set()
    total_samples = total_profiles = total_states = 0
    state_counts = {}
    source_exposures = {}
    owned_backing_private = {}
    steps = ['initial', 'after_first_operation', 'after_first_validation',
             'after_warmed_operation', 'after_warmed_validation', 'before_timing',
             'after_timing', 'after_final_validation']
    for row in rows:
        key = (int(row['rows']), int(row['columns']), int(row['groups']),
               row['workload'], row['route'])
        require(key not in observed and key in expected, 'Duplicate or unexpected series')
        observed.add(key)
        require(row['values_metadata_groups_source'] == 'TRUE', 'A recorded assertion is false')
        stem = '-'.join(map(str, key))
        times = list(csv.DictReader(io.StringIO(read(base / (stem + '-times.csv')))))
        require([int(r['iteration']) for r in times] == list(range(1, 8)), 'Wrong samples')
        samples = [float(r['seconds']) for r in times]
        require(all(math.isfinite(x) and x > 0 for x in samples), 'Invalid time')
        require(math.isclose(statistics.median(samples) * 1000, float(row['median_ms']),
                             rel_tol=1e-12, abs_tol=1e-10), 'Median differs')
        require(int(row['iterations']) == 7, 'Wrong iteration count')
        require(sum(int(r[level]) for r in times for level in ['level0', 'level1', 'level2'])
                == int(row['gc_count']), 'GC count differs')
        total_samples += len(times)
        for phase, metric in [('first-input-call', 'first'), ('warmed-call', 'warm')]:
            lines = read(base / (stem + '-' + phase + '-Rprofmem.log')).splitlines()
            sizes = []
            for line in lines:
                match = re.match(r'^([0-9]+) :', line)
                require(match is not None or line.startswith('new page:'), 'Unknown Rprofmem row')
                if match:
                    sizes.append(int(match.group(1)))
            require(sum(sizes) == integer(row[metric + '_r_allocated_bytes']), 'Allocation sum differs')
            require(max(sizes, default=0) == integer(row[metric + '_r_largest_allocation_bytes']),
                    'Largest allocation differs')
            total_profiles += 1
        states = list(csv.DictReader(io.StringIO(read(base / (stem + '-states.csv')))))
        initial = {r['path']: r for r in states if r['step'] == 'initial'}
        require(len(initial) == key[1] + 1, 'Wrong initial source columns')
        require(set(r['step'] for r in states) == set(steps), 'Missing native checkpoint')
        paths_by_step = {}
        for state in states:
            checkpoint = (state['step'], state['path'])
            require(checkpoint not in paths_by_step, 'Duplicate native state')
            paths_by_step[checkpoint] = state
            state_key = '/'.join([row['route'], state['path'].split('/')[0],
                                  state['owned'], state['depth']])
            state_counts[state_key] = state_counts.get(state_key, 0) + 1
            if state['owned'] == 'TRUE':
                width = dict(logical=4, integer=4, double=8, character=8)[state['type']]
                require(int(state['depth']) == 1 and
                        integer(state['bytes']) == integer(state['length']) * width,
                        'Owned payload depth or byte count differs')
                private_key = '/'.join([row['route'], state['path'].split('/')[0],
                                        state['step'], state['backing_private']])
                owned_backing_private[private_key] = owned_backing_private.get(private_key, 0) + 1
            if state['path'].startswith('source/'):
                first = initial[state['path']]
                compact = state['path'] in ['source/c07', 'source/c15']
                require(state['owned'] == ('FALSE' if compact else 'TRUE'), 'Source backing kind differs')
                require(state['handle'] == first['handle'] and integer(state['length']) == key[0],
                        'Source handle or length differs')
                if compact:
                    require(int(state['depth']) in [0, 1] and
                            integer(state['bytes']) in [key[0] * 4, key[0] * 8], 'Compact state differs')
                else:
                    require(state['bytes'] == first['bytes'], 'Source bytes differ')
                exposure_key = '/'.join([row['route'], state['step'], state['exposed']])
                source_exposures[exposure_key] = source_exposures.get(exposure_key, 0) + 1
        for step in steps:
            require(set(path for current, path in paths_by_step if current == step and
                        path.startswith('source/')) == set(initial), 'Missing source state')
        total_states += len(states)
    require(observed == expected, 'Incomplete declared matrix')
    return dict(scope='Saved first/warm profiles, seven GC-inclusive whole-operation samples, and native state records. '
                      'Recorded semantic assertions are checked for completion; no independent payload replay. '
                      'R and native allocation observations overlap and are never summed. '
                      'This assessment alone does not qualify repeated memory, alias writes or stage-wide acceptance.',
                source=expected_source, receipt=identity(receipt_path), manifest=identity(manifest_path),
                series=len(rows), raw_samples=total_samples, profiles=total_profiles,
                state_rows=total_states, state_counts=state_counts, source_exposures=source_exposures,
                owned_backing_private=owned_backing_private,
                consumed_products=consumed, operation_rows=rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('receipt_sha')
    parser.add_argument('source_sha')
    parser.add_argument('output', type=Path)
    parser.add_argument('--routes', required=True)
    args = parser.parse_args()
    result = assess(args.directory.resolve(strict=True), args.receipt_sha,
                    args.source_sha, args.routes.split(','))
    result['assessment_source'] = identity(Path(__file__).resolve())
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(json.dumps({key: value for key, value in result.items()
                      if key not in ['consumed_products', 'operation_rows', 'owned_backing_private']}, indent=2))


if __name__ == '__main__':
    main()
