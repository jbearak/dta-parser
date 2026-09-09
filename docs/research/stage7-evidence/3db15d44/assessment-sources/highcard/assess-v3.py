"""Read the completed bounded nesting runs; do not execute R or benchmark code."""
from collections import Counter
import argparse
import csv
from decimal import Decimal
import hashlib
import io
import json
import math
from pathlib import Path
import re
import statistics

V = Path('/private/tmp/dta-direct-stage7-validation')
P = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate_directory', type=Path)
parser.add_argument('candidate_source')
parser.add_argument('candidate_receipt_sha256')
parser.add_argument('output', type=Path)
parser.add_argument('--predecessor-directory', type=Path, required=True)
parser.add_argument('--predecessor-receipt-sha256', required=True)
args = parser.parse_args()
assert re.fullmatch('[0-9a-f]{40}', args.candidate_source)
assert re.fullmatch('[0-9a-f]{64}', args.candidate_receipt_sha256)
assert re.fullmatch('[0-9a-f]{64}', args.predecessor_receipt_sha256)
assert args.predecessor_directory.is_absolute()
assert args.predecessor_directory.resolve(strict=True) == args.predecessor_directory
assert args.candidate_directory.is_absolute()
assert args.candidate_directory.resolve(strict=True) == args.candidate_directory
assert args.output.is_absolute() and not args.output.exists() and not args.output.is_symlink()

def identity(path):
    return dict(path=str(path), bytes=path.stat().st_size,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())

def integer(value):
    number = Decimal(value)
    assert number.is_finite() and number == number.to_integral_value()
    return int(number)

runs = []
schemas = {}
for name, source, routes in [
    (args.predecessor_directory, '4d07d656dc95cd2cf5fae12c1dc08d6fae4f8d2c',
     ['public', 'predecessor_safe_reference']),
    (args.candidate_directory, args.candidate_source, ['public'])]:
    root = V / name
    receipt_path = root / 'receipt.json'
    expected_receipt = (args.predecessor_receipt_sha256
        if source == '4d07d656dc95cd2cf5fae12c1dc08d6fae4f8d2c'
        else args.candidate_receipt_sha256)
    assert identity(receipt_path)['sha256'] == expected_receipt
    receipt = json.loads(receipt_path.read_text())
    assert receipt['status'] == 'complete'
    manifest_path = Path(receipt['products']['path'])
    assert identity(manifest_path)['sha256'] == receipt['products']['sha256']
    manifest = json.loads(manifest_path.read_text())
    products = {r['path']: r for r in manifest['products']}
    consumed = []

    def read(relative):
        path = root / relative
        observed = identity(path)
        bound = products[str(path)]
        assert observed['bytes'] == bound['bytes'] and observed['sha256'] == bound['sha256']
        consumed.append(observed)
        return path.read_text()

    result = json.loads(read('result.json'))
    command = json.loads(read('command-result.json'))
    assert result['status'] == 'complete' and result['inputs_unchanged']
    assert result['source_sha'] == source
    assert command['returncode'] == 0 and command['error'] is None
    assert hashlib.sha256(read('source/selected-workload.R').encode()).hexdigest() == \
        '6dc65c585647b3abbe97540b19d5d92e5cf39c2b366a4ac3ec71872d22212d98'
    assert read('results/complete.txt').strip() == 'complete'
    rows = list(csv.DictReader(io.StringIO(read('results/operations.csv'))))
    expected = {(str(g), w, r) for g in [1024, 4096]
                for w in ['group_nest', 'nest_by'] for r in routes}
    assert {(r['groups'], r['workload'], r['route']) for r in rows} == expected
    assert len(rows) == len(expected)
    series = []
    for row in rows:
        assert integer(row['rows']) == 2 * integer(row['groups'])
        assert integer(row['payload_columns']) == 1
        assert row['values_groups_source'] == 'TRUE' and integer(row['iterations']) == 7
        stem = '-'.join(row[k] for k in ['groups', 'workload', 'route'])
        times = list(csv.DictReader(io.StringIO(read('results/' + stem + '-times.csv'))))
        assert [integer(r['iteration']) for r in times] == list(range(1, 8))
        samples = [float(r['seconds']) for r in times]
        assert all(math.isfinite(x) and x > 0 for x in samples)
        median = 1000 * statistics.median(samples)
        assert math.isclose(median, float(row['median_ms']), rel_tol=1e-10, abs_tol=1e-8)
        gc_fields = set(times[0]) - {'iteration', 'seconds'}
        assert gc_fields == {'level0', 'level1', 'level2'}
        assert sum(integer(r[k]) for r in times for k in gc_fields) == integer(row['gc_count'])
        sizes = []
        stack_bytes = Counter()
        stack_events = Counter()
        for line in read('results/' + stem + '-Rprofmem.log').splitlines():
            match = re.fullmatch(r'([0-9]+) :(.*)', line)
            if match:
                size = int(match[1])
                sizes.append(size)
                stack_bytes[match[2]] += size
                stack_events[match[2]] += 1
            else:
                assert line.startswith('new page:'), line
        assert sum(sizes) == integer(row['warm_r_allocated_bytes'])
        assert max([0] + sizes) == integer(row['warm_r_largest_allocation_bytes'])
        schema = read('results/' + stem + '-schemas.R')
        schemas[(source, row['groups'], row['workload'], row['route'])] = schema
        series.append(dict(summary=row, raw_times=times, profile_events=len(sizes),
            largest_stack_buckets=[dict(stack=k, bytes=n, events=stack_events[k])
                                  for k, n in stack_bytes.most_common(8)]))
    runs.append(dict(source=source, directory=str(root), receipt=identity(receipt_path),
        manifest=identity(manifest_path), consumed=consumed, series=series))

predecessor, candidate = runs
comparisons = []
for after in candidate['series']:
    a = after['summary']
    for before in predecessor['series']:
        b = before['summary']
        if (a['groups'], a['workload']) != (b['groups'], b['workload']):
            continue
        assert schemas[(candidate['source'], a['groups'], a['workload'], 'public')] == \
            schemas[(predecessor['source'], b['groups'], b['workload'], b['route'])]
        delta = float(a['median_ms']) - float(b['median_ms'])
        ratio = float(a['median_ms']) / float(b['median_ms'])
        comparisons.append(dict(groups=integer(a['groups']), workload=a['workload'],
            reference_route=b['route'], before_ms=float(b['median_ms']),
            after_ms=float(a['median_ms']), delta_ms=delta, median_ratio=ratio,
            investigation_flag=delta > 1 and ratio > 1.1,
            before_R_bytes=integer(b['warm_r_allocated_bytes']),
            after_R_bytes=integer(a['warm_r_allocated_bytes']), schemas_identical=True))
assert len(comparisons) == 8
scaling = []
for run in runs:
    rows = [x['summary'] for x in run['series']]
    for workload, route in sorted({(r['workload'], r['route']) for r in rows}):
        small = next(r for r in rows if r['groups'] == '1024' and
                     (r['workload'], r['route']) == (workload, route))
        large = next(r for r in rows if r['groups'] == '4096' and
                     (r['workload'], r['route']) == (workload, route))
        scaling.append(dict(source=run['source'], workload=workload, route=route,
            groups_ratio=4, rows_ratio=4,
            median_ratio=float(large['median_ms']) / float(small['median_ms']),
            R_allocation_ratio=integer(large['warm_r_allocated_bytes']) /
                               integer(small['warm_r_allocated_bytes'])))
report = dict(assessor=identity(Path(__file__).resolve()), runs=runs,
    comparisons=comparisons, scaling=scaling,
    scope='All12 series/84 raw samples/12 complete allocation profiles and8 cross-source schema pairs checked. Receipt identities supplied before assessor execution and checked; selected manifest links verified. Receipts were observed after benchmark completion. Independent R value/group checks recorded, not replayed. Public predecessor is a weaker foreign-write control. No RSS, native allocation, retained heap, runtime closure or asymptotic proof. Profile stacks identify observed call stacks, not exclusive source-line or CPU causes.')
output = args.output
with output.open('x') as stream:
    json.dump(report, stream, indent=2)
    stream.write('\n')
print(json.dumps(dict(output=identity(output), comparisons=comparisons, scaling=scaling), indent=2))
