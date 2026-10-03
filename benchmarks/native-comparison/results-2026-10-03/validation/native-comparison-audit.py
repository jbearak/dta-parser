import csv
import hashlib
import itertools
import json
import math
import statistics
from collections import Counter, defaultdict
from pathlib import Path

P = Path('<private-evidence>/paired-v1')
OUT = Path('<independent-audits>/native-comparison-audit.json')
def require(ok, label):
    if not ok:
        raise RuntimeError(label)
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def read(name):
    return list(csv.DictReader((P / name).open(newline='')))
def close(actual, expected, label):
    require(math.isclose(float(actual), expected, rel_tol=1e-12, abs_tol=1e-14), label)

fields = ('threads', 'missing', 'operation', 'representation')
reps = ('compact', 'typed_double', 'ordinary')
expected = set(itertools.product(('0','1'), ('FALSE','TRUE'), ('pair_less','scalar_less','pair_equal'), reps))
rows, summary = read('raw.csv'), read('summary.csv')
require(len(rows) == 432 and len(summary) == 12, 'row counts')
rebuilt = []
for number in range(1,7):
    for variant in ('baseline','candidate') if number % 2 else ('candidate','baseline'):
        batch = read(f'{number:02}-{variant}.csv')
        rebuilt.extend(dict(variant=variant, **row) for row in batch)
        require(Counter(tuple(r[k] for k in fields) for r in batch) == Counter({k:1 for k in expected}), 'matrix')
        require(all(int(r['round']) == number and int(r['rows']) == 1000000 for r in batch), 'round/shape')
require(rows == rebuilt, 'worker/raw equality')
groups = defaultdict(list)
identity = ('result_hash','input_hash','y_hash','metadata_x','metadata_y','compact_before',
            'materialized_before','y_compact_before','y_materialized_before')
for row in rows:
    groups[tuple(row[k] for k in fields)].append(row)
    require(int(row['repetitions']) > 0 and all(math.isfinite(float(row[m])) and float(row[m]) > 0 for m in ('cpu','wall')), 'timing')
    for key in ('result_hash','input_hash','y_hash','metadata_x','metadata_y'):
        require(len(row[key]) == 64 and set(row[key]) <= set('0123456789abcdef'), 'hash')
    for prefix in ('compact','materialized','y_compact','y_materialized'):
        require(row[prefix+'_before'] == row[prefix+'_after'], 'source state')
    is_compact = str(row['representation'] == 'compact').upper()
    require(row['compact_before'] == row['y_compact_before'] == is_compact, 'compact source')
    require(row['materialized_before'] == row['y_materialized_before'] == 'FALSE', 'source materialization')
    require(row['native_qualified'] == str(row['representation'] != 'ordinary').upper(), 'native eligibility')
for key, batch in groups.items():
    require(len(batch) == 12 and len({tuple(r[k] for k in identity) for r in batch}) == 1, 'stable full results/source/metadata')
for variant in ('baseline','candidate'):
    for case in {k[:-1] for k in expected}:
        orders = []
        for number in range(1,7):
            batch = sorted((r for r in rows if r['variant'] == variant and int(r['round']) == number
                            and tuple(r[k] for k in fields[:-1]) == case), key=lambda r:int(r['position']))
            require([int(r['position']) for r in batch] == [1,2,3], 'positions')
            orders.append(tuple(r['representation'] for r in batch))
        require(Counter(orders) == Counter(itertools.permutations(reps)), 'six permutations')
for case in {k[:-1] for k in expected}:
    batch = [r for r in rows if tuple(r[k] for k in fields[:-1]) == case
             and (case[1] == 'FALSE' or r['representation'] != 'ordinary')]
    require(len({r['result_hash'] for r in batch}) == 1, 'equivalent-representation oracle')
require(Counter(tuple(r[k] for k in fields[:-1]) for r in summary) == Counter({k[:-1]:1 for k in expected}), 'summary matrix')
for s in summary:
    case = tuple(s[k] for k in fields[:-1])
    for variant in ('baseline','candidate'):
        for rep in reps:
            batch = [r for r in groups[case+(rep,)] if r['variant'] == variant]
            for metric in ('cpu','wall'):
                close(s[f'{variant}_{rep}_{metric}'], statistics.median(float(r[metric])/int(r['repetitions']) for r in batch), 'CPU/wall medians')
        close(s[variant+'_compact_typed_cpu'], float(s[variant+'_compact_cpu'])/float(s[variant+'_typed_double_cpu']), 'typed ratio')
        close(s[variant+'_compact_bare_cpu'], float(s[variant+'_compact_cpu'])/float(s[variant+'_ordinary_cpu']), 'bare ratio')
    close(s['compact_cpu_speedup'], float(s['baseline_compact_cpu'])/float(s['candidate_compact_cpu']), 'speedup')
before,after,completion = [json.loads((P/name).read_text()) for name in ('provenance-before.json','provenance-after.json','completion.json')]
require(before == after, 'unchanged complete provenance')
require(completion['exact_results'] and completion['provenance_unchanged'] and completion['observations'] == len(rows), 'completion')
require(completion['source_patch_sha256'] == sha(P/'source.patch'), 'source patch binding')
require(all(build['receipt']['toolchain']['R_runtime_sha256'] == before['execution']['R_runtime_sha256'] for build in before['builds'].values()), 'actual execution/build runtime binding')
base=Path('<workspace>/benchmarks')
paths={'comparison_controller':base/'native-comparison/run.py',
       'worker':base/'native-comparison/worker.R',
       'build_validation':base/'native-operations/run.py',
       'build_recorder':base/'r-file-readers/record-builds.py'}
for name,digest in before['controllers'].items():
    require(sha(paths[name]) == digest, 'current controller '+name)
for field in ('candidate_max_compact_typed_cpu','candidate_max_missing_free_compact_bare_cpu'):
    key = 'candidate_compact_typed_cpu' if 'typed' in field else 'candidate_compact_bare_cpu'
    batch = summary if 'typed' in field else [s for s in summary if s['missing']=='FALSE']
    close(completion[field], max(float(s[key]) for s in batch), 'completion max ratio')
tradeoff=[]
for s in summary:
    if s['threads'] != '0': continue
    serial=next(r for r in summary if r['threads']=='1' and r['missing']==s['missing'] and r['operation']==s['operation'])
    tradeoff.append(dict(missing=s['missing'],operation=s['operation'],
        auto_cpu_ms=1000*float(s['candidate_compact_cpu']),serial_cpu_ms=1000*float(serial['candidate_compact_cpu']),
        auto_wall_ms=1000*float(s['candidate_compact_wall']),serial_wall_ms=1000*float(serial['candidate_compact_wall']),
        auto_compact_typed_cpu=float(s['candidate_compact_typed_cpu'])))
report=dict(audit='Independent read-only artifact recomputation; no R/build/timing jobs',observations=len(rows),summary_rows=len(summary),
    checks=['worker/raw equality','complete case matrix and all six permutations','every CPU/wall median and ratio',
            'full result/source/metadata hashes and unchanged state','separate native eligibility',
            'same-contract representation agreement','before/after full binding and exact Rscript execution/build runtime equality',
            'current controller hashes, source patch and completion ratio bindings'],
    candidate_thread_tradeoff=tradeoff,
    baseline_candidate_tradeoff=[dict(threads=s['threads'],missing=s['missing'],operation=s['operation'],
        compact_cpu_speedup=float(s['baseline_compact_cpu'])/float(s['candidate_compact_cpu']),
        compact_wall_ratio=float(s['candidate_compact_wall'])/float(s['baseline_compact_wall']),
        typed_double_cpu_speedup=float(s['baseline_typed_double_cpu'])/float(s['candidate_typed_double_cpu']),
        typed_double_wall_ratio=float(s['candidate_typed_double_wall'])/float(s['baseline_typed_double_wall']),
        bare_cpu_ratio=float(s['candidate_ordinary_cpu'])/float(s['baseline_ordinary_cpu'])) for s in summary],
    cpu_interval_range=[min(float(r['cpu']) for r in rows),max(float(r['cpu']) for r in rows)],
    wall_interval_range=[min(float(r['wall']) for r in rows),max(float(r['wall']) for r in rows)],
    caveats=['Native qualification proves eligibility, not a per-timed-call entry counter.',
             'Missing-bearing ordinary R has different NA propagation semantics.',
             'Retained constructor adapter uses one fixed mismatched chunk geometry; no reader/decompression workload.'],
    artifacts={name:sha(P/name) for name in ('raw.csv','summary.csv','protocol.json','provenance-before.json','provenance-after.json','completion.json','source.patch')})
OUT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps(report,indent=2,sort_keys=True))
