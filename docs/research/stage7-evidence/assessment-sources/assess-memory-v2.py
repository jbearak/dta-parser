"""Assess saved memory products, with independent arithmetic and native-state checks."""
import argparse
from collections import Counter
import csv
from decimal import Decimal
import hashlib
import io
import itertools
import json
from pathlib import Path
import re


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def identity(path):
    return dict(path=str(path), resolved=str(path.resolve(strict=True)),
                bytes=path.stat().st_size, mode=oct(path.stat().st_mode & 0o777),
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def integer(value):
    number = Decimal(value)
    require(number.is_finite() and number == number.to_integral_value(), 'Invalid integer')
    return int(number)


def assess_case(directory, source, receipt_identity, rows, workload, route):
    receipt_path = directory / 'receipt.json'
    require(identity(receipt_path) == receipt_identity, 'Receipt changed')
    receipt = json.loads(receipt_path.read_text())
    require(receipt['status'] == 'complete', 'Incomplete receipt')
    manifest_path = Path(receipt['products']['path'])
    require(identity(manifest_path) == receipt['products'], 'Manifest changed')
    records = json.loads(manifest_path.read_text())['products']
    products = {record['path']: record for record in records}
    require(len(products) == len(records), 'Duplicate products')
    consumed = []

    def read(name):
        path = directory / name
        require(str(path) in products, 'Unlisted product: ' + name)
        before = identity(path)
        require(before == products[str(path)], 'Changed product: ' + name)
        value = path.read_text()
        require(identity(path) == before, 'Product changed during read')
        consumed.append(before)
        return value

    require(identity(directory / 'result.json') == receipt['result'], 'Result changed')
    result = json.loads(read('result.json'))
    require(result['status'] == 'complete' and result['error'] is None and
            result['inputs_unchanged'] and result['input_binding_complete'] and
            result['source_sha'] == source, 'Wrong execution')
    command = json.loads(read('command-result.json'))
    require(command['returncode'] == 0 and command['error'] is None, 'Child failed')
    require(command['command'][:2] == ['/usr/bin/time', '-l'], 'Wrong RSS command')
    rss = json.loads(read('whole-child-rss.json'))
    require((rss['rows'], rss['workload'], rss['route']) == (rows, workload, route),
            'Wrong RSS case')
    log = read('runner.log')
    matches = re.findall(r'^\s*(\d+)\s+maximum resident set size\s*$', log, flags=re.M)
    require(len(matches) == 1 and int(matches[0]) == rss['bytes'] > 0, 'RSS differs')
    require('PASS repeated-source memory workload and final independent value/schema/group/source checks' in log,
            'Missing final assertion marker')
    validation = list(csv.DictReader(io.StringIO(read('results/validation.csv'))))
    require(validation == [dict(rows=str(rows), columns='8', groups='128',
            workload=workload, route=route, calls='50', values_metadata_groups_source='TRUE')],
            'Wrong recorded validation')
    heap = list(csv.DictReader(io.StringIO(read('results/heap.csv'))))
    checkpoints = ['prefixture', '0_source_only', '5', '50', 'after_validation',
                   'source_released', 'result_released']
    require([row['checkpoint'] for row in heap] == checkpoints, 'Wrong heap checkpoints')
    for row in heap:
        require(integer(row['v_cells_used']) * 8 == integer(row['vector_heap_bytes']),
                'Heap byte arithmetic differs')
        require(integer(row['n_cells_used']) > 0, 'Invalid Ncells')
    heap_by = {row['checkpoint']: integer(row['vector_heap_bytes']) for row in heap}
    states = list(csv.DictReader(io.StringIO(read('results/states.csv'))))
    columns = ['g'] + ['c%02d' % i for i in range(1, 9)]
    expected_lengths = {'table/' + column: rows for column in columns}
    if workload == 'group_modify_identity':
        result_lengths = expected_lengths.copy()
    else:
        result_lengths = {'table/g': 128}
        for group in range(1, 129):
            group_size = (rows - group) // 128 + 1
            for column in columns[1:]:
                result_lengths['table/data[%d]/%s' % (group, column)] = group_size
        result_lengths.update({'table/data/ptype/' + column: 0 for column in columns[1:]})
    expected_keys = {(step, 'source', path) for step in ['0', '5', '50', 'after_validation']
                     for path in expected_lengths}
    expected_keys.update((step, 'result', path) for step in ['5', '50', 'after_validation']
                         for path in result_lengths)
    seen = set()
    initial = {}
    counts = Counter()
    exposures = Counter()
    private = Counter()
    for state in states:
        key = (state['checkpoint'], state['role'], state['path'])
        require(key in expected_keys and key not in seen, 'Unexpected or duplicate state')
        seen.add(key)
        lengths = expected_lengths if state['role'] == 'source' else result_lengths
        length = integer(state['length'])
        require(length == lengths[state['path']], 'Wrong native length')
        require(state['owned'] in ['TRUE', 'FALSE'], 'Wrong owned flag')
        counts['/'.join([state['role'], state['owned'], state['depth']])] += 1
        exposures['/'.join([state['checkpoint'], state['role'], state['exposed']])] += 1
        if state['owned'] == 'TRUE':
            width = dict(logical=4, integer=4, double=8, character=8)[state['type']]
            require(integer(state['depth']) == 1 and integer(state['bytes']) == length * width,
                    'Owned backing depth/bytes differ')
            private['/'.join([state['checkpoint'], state['role'], state['backing_private']])] += 1
        if state['role'] == 'source':
            if state['checkpoint'] == '0':
                initial[state['path']] = state
            first = initial[state['path']]
            compact = state['path'] == 'table/c07'
            require(state['owned'] == ('FALSE' if compact else 'TRUE'), 'Source kind differs')
            require(state['handle'] == first['handle'], 'Source handle changed')
            if compact:
                require(integer(state['depth']) in [0, 1] and
                        integer(state['bytes']) in [rows * 4, rows * 8], 'Compact state differs')
            else:
                require(integer(state['bytes']) == integer(first['bytes']), 'Source bytes changed')
    require(seen == expected_keys, 'Missing native states')
    return dict(rows=rows, workload=workload, route=route, calls=50,
                receipt=receipt_identity, manifest=receipt['products'],
                consumed_products=consumed, whole_child_rss_bytes=rss['bytes'],
                heap_rows=heap, vector_heap_5_to_50_bytes=heap_by['50'] - heap_by['5'],
                vector_heap_final_minus_prefixture_bytes=heap_by['result_released'] - heap_by['prefixture'],
                source_release_drop_bytes=heap_by['after_validation'] - heap_by['source_released'],
                result_release_drop_bytes=heap_by['source_released'] - heap_by['result_released'],
                native_state_rows=len(states), native_counts=dict(counts),
                exposure_counts=dict(exposures), owned_private_counts=dict(private))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('batch', type=Path)
    parser.add_argument('source')
    parser.add_argument('output', type=Path)
    parser.add_argument('--routes', required=True)
    args = parser.parse_args()
    batch = args.batch.resolve(strict=True)
    batch_result_identity = identity(batch / 'result.json')
    batch_result = json.loads((batch / 'result.json').read_text())
    require(batch_result['status'] == 'complete' and batch_result['inputs_unchanged'] and
            batch_result['error'] is None and batch_result['final_identity_error'] is None,
            'Incomplete batch')
    expected = set(itertools.product([100000, 1000000],
                   ['group_modify_identity', 'group_nest', 'nest_by'], args.routes.split(',')))
    commands = batch_result['records']
    require(len(commands) == len(expected), 'Wrong child count')
    launch_identity = identity(batch / 'launch.json')
    launch = json.loads((batch / 'launch.json').read_text())
    require([row['command'] for row in commands] == launch['commands'], 'Commands differ')
    cases = []
    observed = set()
    for record in commands:
        require(record['returncode'] == 0 and record['error'] is None, 'Batch child failed')
        command = record['command']
        directory = Path(command[8])
        require(directory.parent == batch and command[7] == args.source, 'Wrong child selection')
        rows = int(command[command.index('--rows') + 1])
        workload = command[command.index('--workload') + 1]
        route = command[command.index('--routes') + 1]
        key = (rows, workload, route)
        require(key in expected and key not in observed, 'Unexpected child matrix')
        observed.add(key)
        cases.append(assess_case(directory, args.source, identity(directory / 'receipt.json'),
                                 rows, workload, route))
    require(observed == expected, 'Incomplete child matrix')
    require(identity(batch / 'result.json') == batch_result_identity and
            identity(batch / 'launch.json') == launch_identity, 'Batch records changed')
    result = dict(source=args.source, batch_result=batch_result_identity, launch=launch_identity,
                  assessment_source=identity(Path(__file__).resolve()), cases=cases,
                  scope='Post-run receipt/product identity checks, exact heap arithmetic, raw macOS time RSS, '
                        'complete expected native state membership/length/depth/bytes and source handles. '
                        'Child receipt identities are observed now, not bound by the batch at completion. '
                        'Semantic assertions are recorded by R, not independently replayed here. '
                        'The 0/5/50 heap checkpoints precede their corresponding native inspection; after_validation follows it. ' 
                        'The warmed prefixture follows warm validation and state inspection. Earlier inspection may expose/materialize. '
                        'Whole-child RSS includes setup, repeated calls and final validation; it is not per-call peak. '
                        'Heap, native bytes and RSS overlap and must not be added. '
                        'No full runtime image closure or foreign-write isolation claim.')
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(json.dumps(dict(cases=len(cases), calls=sum(row['calls'] for row in cases),
                    state_rows=sum(row['native_state_rows'] for row in cases),
                    metrics=[{key: row[key] for key in ['rows', 'workload', 'route',
                        'whole_child_rss_bytes', 'vector_heap_5_to_50_bytes',
                        'vector_heap_final_minus_prefixture_bytes']} for row in cases],
                    output=identity(args.output)), indent=2))


if __name__ == '__main__':
    main()
