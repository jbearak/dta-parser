import csv
import hashlib
import itertools
import json
import math
import statistics
from collections import Counter, defaultdict
from pathlib import Path

P = Path('<decode-evidence>/paired-v1')
ROOT = Path('<decode-checkout>/benchmarks')
OUT = Path('<independent-audit>/compact-decode-audit.json')
def require(ok, label):
    if not ok:
        raise RuntimeError(label)
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):
    return list(csv.DictReader(path.open(newline='')))
def close(actual, expected, label):
    require(math.isclose(float(actual), expected, rel_tol=1e-10, abs_tol=1e-10), label)

fields = ('n', 'width', 'backing', 'density')
widths = dict(byte=1, int=2, long=4, float=4)
expected = set(itertools.product(('1000000',), widths,
                                ('constructed', 'retained'), ('none','sparse','dense')))
rows, intervals, summary = [read(P / name) for name in ('raw.csv', 'intervals.csv', 'summary.csv')]
require((len(rows), len(intervals), len(summary)) == (288, 2431, 24), 'row counts')
rebuilt, rebuilt_intervals = [], []
for round_ in range(1, 7):
    for variant in ('baseline', 'candidate') if round_ % 2 else ('candidate', 'baseline'):
        batch = read(P / f'{round_:02}-{variant}.csv')
        batch_intervals = read(P / f'{round_:02}-{variant}.csv.intervals.csv')
        rebuilt.extend(dict(variant=variant, **row) for row in batch)
        rebuilt_intervals.extend(dict(variant=variant, **row) for row in batch_intervals)
        require(Counter(tuple(r[k] for k in fields) for r in batch) == Counter({k: 1 for k in expected}), 'complete matrix')
        require(all(int(r['round']) == round_ and r['phase'] == 'timing' for r in batch), 'round/phase')
require(rows == rebuilt and intervals == rebuilt_intervals, 'worker aggregate equality')
interval_groups = defaultdict(list)
for row in intervals:
    key = (row['variant'], row['round'], *(row[k] for k in fields))
    interval_groups[key].append(row)
    require(all(math.isfinite(float(row[m])) and float(row[m]) >= 0 for m in
                ('cpu_seconds', 'elapsed_seconds', 'gc_cpu_seconds')), 'interval values')
groups = defaultdict(list)
for row in rows:
    case = tuple(row[k] for k in fields)
    groups[case].append(row)
    batch = interval_groups[(row['variant'], row['round'], *case)]
    batches, size, n, iterations = [int(row[k]) for k in ('batches', 'batch_size', 'n', 'iterations')]
    require(Counter(int(r['batch']) for r in batch) == Counter(range(1, batches + 1)), 'batch sequence')
    require(iterations == batches * size and all(int(r['handles']) == size for r in batch), 'handle counts')
    require(size==32 and row['sharing']=='aliased', 'batch bound and shared input')
    require(int(row['missing_count'])=={'none':0,'sparse':62,'dense':843750}[row['density']], 'missing density')
    for metric in ('cpu_seconds', 'elapsed_seconds', 'gc_cpu_seconds'):
        close(row[metric], sum(float(r[metric]) for r in batch), 'interval sums')
    require(min(float(row[k]) for k in ('cpu_seconds', 'elapsed_seconds')) >= .15, 'aggregate duration')
    for metric, zero in (('cpu_seconds', 'zero_cpu_batches'), ('elapsed_seconds', 'zero_wall_batches')):
        values = [float(r[metric]) for r in batch]
        close(row['min_batch_' + metric], min(values), 'min interval')
        close(row['max_batch_' + metric], max(values), 'max interval')
        require(int(row[zero]) == sum(v == 0 for v in values), 'zero intervals')
    copy = 0
    require(float(row['compact_copy_bytes'])==float(row['timed_compact_copy_bytes'])==0, 'zero copy totals')
    require(all(float(r['compact_copy_bytes']) == copy * size for r in batch), 'per-batch copies')
    require(float(row['compatibility_bytes']) == 0, 'no compatibility copies')
    require(float(row['compact_payload_bytes']) == n * widths[row['width']] and float(row['double_payload_bytes']) == 8 * n, 'payload bytes')
    require(row['source_sha256'] == row['result_sha256'], 'source/result hash')
    require(all(row[k] == 'TRUE' for k in ('alias_independent','source_unmaterialized_before','source_unmaterialized_after','targets_unmaterialized_before','targets_materialized_after')), 'ownership results')
    chunks = math.ceil(n / (257 if n == 4096 else 8191)) if row['backing'] == 'retained' else 0
    require(int(row['retained_chunks']) == chunks, 'retained chunks')
    require(float(row['r_profiled_allocation_bytes']) >= float(row['r_largest_allocation_bytes']) >= 8 * n, 'allocation lower bound')
for case, batch in groups.items():
    require(len(batch) == 12 and len({(r['source_sha256'], r['result_sha256']) for r in batch}) == 1, 'stable hashes')
    for variant in ('baseline', 'candidate'):
        selected = [r for r in batch if r['variant'] == variant]
        require(Counter(int(r['round']) for r in selected) == Counter(range(1, 7)), 'round balance')
        require(Counter(int(r['order']) for r in selected) == Counter({1:2,2:2,3:2}), 'density positions')
        require(Counter(int(r['backing_order']) for r in selected)==Counter({1:3,2:3}), 'backing positions')
for width in widths:
    for density in ('none','sparse','dense'):
        require(len({r['result_sha256'] for r in rows if r['width']==width and r['density']==density})==1, 'backing value equality')
for variant in ('baseline','candidate'):
    for round_ in range(1,7):
        batch=[r for r in rows if r['variant']==variant and int(r['round'])==round_]
        order=tuple(itertools.permutations(('none','sparse','dense')))[round_-1]
        for row in batch:
            require(int(row['order'])==order.index(row['density'])+1, 'exact density permutation')
            backings=('constructed','retained') if round_%2 else ('retained','constructed')
            require(int(row['backing_order'])==backings.index(row['backing'])+1, 'exact backing order')
require(Counter(tuple(r[k] for k in fields) for r in summary) == Counter({k: 1 for k in expected}), 'summary matrix')
for s in summary:
    batch = groups[tuple(s[k] for k in fields)]
    for variant in ('baseline', 'candidate'):
        selected = [r for r in batch if r['variant'] == variant]
        for metric in ('cpu_seconds', 'elapsed_seconds', 'gc_cpu_seconds'):
            close(s[variant + '_' + metric], statistics.median(float(r[metric]) / int(r['iterations']) for r in selected), 'per-call median')
        for metric in ('compact_copy_bytes', 'r_profiled_allocation_bytes', 'r_largest_allocation_bytes', 'peak_vcell_bytes', 'live_vcell_delta_bytes'):
            close(s[variant + '_' + metric], statistics.median(float(r[metric]) for r in selected), 'memory median')
        for metric in ('cpu_seconds', 'elapsed_seconds'):
            for name, fun in (('min', min), ('max', max)):
                key = name + '_batch_' + metric
                close(s[variant + '_' + key], fun(float(r[key]) for r in selected), 'summary interval range')
        for key in ('batches', 'zero_cpu_batches', 'zero_wall_batches'):
            require(int(s[variant + '_' + key]) == sum(int(r[key]) for r in selected), 'batch count summaries')
    close(s['cpu_speedup'], float(s['baseline_cpu_seconds']) / float(s['candidate_cpu_seconds']), 'CPU ratio')
    close(s['wall_speedup'], float(s['baseline_elapsed_seconds']) / float(s['candidate_elapsed_seconds']), 'wall ratio')
    for metric,label in (('cpu_seconds','cpu'),('elapsed_seconds','wall')):
        values={v:{int(r['round']):float(r[metric])/int(r['iterations']) for r in batch if r['variant']==v} for v in ('baseline','candidate')}
        pairs=[values['baseline'][r]/values['candidate'][r] for r in range(1,7)]
        for stat,fn in (('median',statistics.median),('min',min),('max',max)):
            close(s[label+'_paired_'+stat+'_speedup'],fn(pairs),'paired speedup')
before, after, completion = [json.loads((P / name).read_text()) for name in
                            ('provenance-before.json', 'provenance-after.json', 'completion.json')]
for key in ('builds', 'controllers', 'probe', 'runtime'):
    require(before[key] == after[key], 'stable provenance ' + key)
for name, digest in before['controllers'].items():
    require(sha(ROOT / name) == digest, 'current controller ' + name)
for name, digest in completion['artifacts'].items():
    require(sha(P / name) == digest, 'completion hash ' + name)
known_builds={'baseline':Path('<materialization-evidence>/candidate-integration-v3'),
              'candidate':Path('<decode-evidence>/candidate-v1')}
for role,path in known_builds.items():
    receipt=path/'build-receipt.json'
    require(json.loads(receipt.read_text())==before['builds'][role]['receipt'] and sha(receipt)==before['builds'][role]['receipt_sha256'],'original named receipt')
    require(before['builds'][role]['receipt']['toolchain']['R_runtime_sha256']==before['runtime']['R_runtime_sha256'],'build/worker runtime')
require(before['probe']['receipt']['toolchain']['R_runtime_sha256']==before['runtime']['R_runtime_sha256'],'probe/worker runtime')
probe=Path('<materialization-evidence>/probe-v2')
require(json.loads((probe/'receipt.json').read_text())==before['probe']['receipt'] and sha(probe/'receipt.json')==before['probe']['receipt_sha256'],'original probe receipt')
require(sha(probe/'materialization_probe.c')==before['probe']['receipt']['source_sha256'] and sha(probe/'materialization_probe.so')==before['probe']['receipt']['binary_sha256'],'current small probe source/binary')
require(completion['observations']==288 and completion['rounds']==6 and all(completion[k] for k in ('exact_results','first_materialization_only','provenance_unchanged','source_unchanged')),'completion')
report=dict(audit='Independent artifact recomputation; no R, builds or measurements',observations=len(rows),intervals=len(intervals),summary_rows=len(summary),
    checks=['worker/raw and worker/interval identity','complete matrix, density permutations, backing/build balance',
    'every interval sum/range/count and CPU/wall/GC/memory median','every speedup and paired ratio',
    'all zero-copy/ownership/value/density observations','before/after package/probe/runtime/controller equality',
    'original named build receipts, actual execution runtime and current controllers','completion artifact hashes'],
    cpu_speedup_range=[min(float(s['cpu_speedup']) for s in summary),max(float(s['cpu_speedup']) for s in summary)],
    case_speedups=[{k:s[k] for k in ('width','backing','density','cpu_speedup','wall_speedup','cpu_paired_median_speedup')} for s in summary],
    cpu_batch_range=[min(float(r['cpu_seconds']) for r in intervals),max(float(r['cpu_seconds']) for r in intervals)],
    wall_batch_range=[min(float(r['elapsed_seconds']) for r in intervals),max(float(r['elapsed_seconds']) for r in intervals)],
    aggregate_cpu_range=[min(float(r['cpu_seconds']) for r in rows),max(float(r['cpu_seconds']) for r in rows)],
    zero_cpu_batches=sum(float(r['cpu_seconds'])==0 for r in intervals),zero_wall_batches=sum(float(r['elapsed_seconds'])==0 for r in intervals),
    caveats=['Aliased first DATAPTR materialization only; no ingestion or ordinary-double parity claim.',
    'Rprofmem logged bytes and Vcells high-water overlap and are not process RSS.',
    'Current large binaries are not rehashed in this lightweight audit; captured inventories agree.'],
    artifacts={name:sha(P/name) for name in ('raw.csv','intervals.csv','summary.csv','protocol.json','provenance-before.json','provenance-after.json','completion.json','source.patch')})
OUT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps(report,indent=2,sort_keys=True))
