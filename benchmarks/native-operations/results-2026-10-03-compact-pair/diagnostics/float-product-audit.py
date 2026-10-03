import csv
import hashlib
import itertools
import json
import math
import statistics
from collections import Counter, defaultdict
from pathlib import Path

P = Path('<work>/float-product-timings')
D = Path('<work>/float-product-diagnostic')
OUT = Path('<independent-audit-work>/float-product-audit.json')
def require(ok, label):
    if not ok:
        raise RuntimeError(label)
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def read(name):
    return list(csv.DictReader((P / name).open(newline='')))
def close(value, target, label):
    require(math.isclose(float(value), target, rel_tol=1e-12, abs_tol=1e-14), label)

fields = ('width', 'missing', 'operation', 'representation')
reps = ('compact', 'typed_double', 'ordinary')
case_operations = {'int': ('scale_binary','mixed_add','mixed_multiply','mixed_subtract','mixed_divide'),
                   'float': ('scale_binary','scale_general','float_multiply'), 'long': ('long_float_add',)}
expected = {(width,missing,operation,rep) for width, operations in case_operations.items()
            for missing in ('FALSE','TRUE') for operation in operations for rep in reps}
rows, summary = read('raw.csv'), read('summary.csv')
require(len(rows) == 648 and len(summary) == 36, 'row counts')
rebuilt = []
for round_ in range(1, 7):
    for variant in ('baseline', 'candidate') if round_ % 2 else ('candidate', 'baseline'):
        batch = read(f'{round_:02}-{variant}.csv')
        rebuilt.extend(dict(variant=variant, **row) for row in batch)
        require(Counter(tuple(r[k] for k in fields) for r in batch) == Counter({k: 1 for k in expected}), 'unique matrix')
        require(all(int(r['round']) == round_ and int(r['n']) == 1000000 for r in batch), 'round/rows')
require(rows == rebuilt, 'worker/raw equality')
groups = defaultdict(list)
identity = ('result_sha256', 'missing_sha256', 'missing_count', 'result_storage',
            'input_sha256', 'y_sha256', 'compact_before', 'materialized_before',
            'y_compact_before', 'y_materialized_before')
for row in rows:
    groups[tuple(row[k] for k in fields)].append(row)
    require(int(row['iterations']) > 0, 'iterations')
    require(all(math.isfinite(float(row[k])) and float(row[k]) > 0 for k in ('cpu', 'wall')), 'intervals')
    require(float(row['native_calls']) == (0 if row['representation'] == 'ordinary' else int(row['iterations'])), 'native route')
    for prefix in ('compact', 'materialized', 'y_compact', 'y_materialized'):
        require(row[prefix + '_before'] == row[prefix + '_after'], 'source state')
    if row['representation'] == 'compact':
        require(row['compact_before'] == 'TRUE' and row['materialized_before'] == 'FALSE', 'compact admission')
    for key in ('result_sha256', 'missing_sha256', 'input_sha256', 'y_sha256'):
        require(len(row[key]) == 64 and set(row[key]) <= set('0123456789abcdef'), 'hash format')
for key, batch in groups.items():
    require(len(batch) == 12 and len({tuple(r[k] for k in identity) for r in batch}) == 1, 'stable result/source/metadata')
for variant in ('baseline', 'candidate'):
    for case in {k[:-1] for k in expected}:
        orders = []
        for round_ in range(1, 7):
            batch = sorted([r for r in rows if r['variant'] == variant and int(r['round']) == round_
                            and tuple(r[k] for k in fields[:-1]) == case], key=lambda r: int(r['order']))
            require([int(r['order']) for r in batch] == [1, 2, 3], 'per-round positions')
            orders.append(tuple(r['representation'] for r in batch))
        require(Counter(orders) == Counter(itertools.permutations(reps)), 'all six permutations')
summary_keys = {(v, *k[:-1]) for v in ('baseline', 'candidate') for k in expected}
require(Counter((r['variant'], *(r[k] for k in fields[:-1])) for r in summary) == Counter({k: 1 for k in summary_keys}), 'summary matrix')
for s in summary:
    case = tuple(s[k] for k in fields[:-1])
    values = {}
    for variant in ('baseline', 'candidate'):
        for rep in reps:
            batch = [r for r in groups[case + (rep,)] if r['variant'] == variant]
            values[variant, rep] = {int(r['round']): float(r['cpu']) / int(r['iterations']) for r in batch}
    v = s['variant']
    med = {rep: statistics.median(values[v, rep].values()) for rep in reps}
    for rep in reps:
        close(s[rep], med[rep], 'CPU medians')
    close(s['compact_typed_ratio'], med['compact'] / med['typed_double'], 'typed ratio')
    close(s['compact_ordinary_ratio'], med['compact'] / med['ordinary'], 'bare ratio')
    close(s['paired_compact_typed_ratio'], statistics.median(values[v, 'compact'][n] / values[v, 'typed_double'][n] for n in range(1, 7)), 'paired ratio')
    close(s['compact_speedup'], statistics.median(values['baseline', 'compact'].values()) / statistics.median(values['candidate', 'compact'].values()), 'speedup')
before, after, completion = [json.loads((P / name).read_text()) for name in ('provenance-before.json', 'provenance-after.json', 'completion.json')]
require(before['builds'] == after['builds'] and before['controllers'] == after['controllers'] and before['runtime'] == after['runtime'], 'provenance stability')
require(all(v['receipt']['toolchain']['R_runtime_sha256'] == before['runtime']['R_runtime_sha256'] for v in before['builds'].values()), 'actual worker runtime matches both receipts')
require(completion['worker_runtime_unchanged'], 'execution runtime completion')
require(completion['observations'] == 648 and all(completion[k] for k in ('exact_results', 'missing_cache_matches', 'source_state_unchanged', 'provenance_unchanged')), 'completion')
require(completion['source_patch_sha256'] == sha(P / 'source.patch'), 'source delta binding')
controller_paths = {name: D / name for name in ('general-run.py', 'general-worker.R')}
controller_paths['run.py'] = Path('<repo>/benchmarks/native-operations/run.py')
for name, digest in before['controllers'].items():
    require(sha(controller_paths[name]) == digest, 'current controller ' + name)
candidate = [s for s in summary if s['variant'] == 'candidate']
targets = [s for s in candidate if s['operation'] in ('mixed_multiply','float_multiply')]
require(len(targets)==4, 'four float multiplication targets')
known_builds={'baseline':Path('<work>/pair-prototype'),
              'candidate':Path('<work>/float-product-prototype')}
for role,path in known_builds.items():
    receipt=path/'build-receipt.json'
    require(json.loads(receipt.read_text())==before['builds'][role]['receipt'] and sha(receipt)==before['builds'][role]['receipt_sha256'], 'actual named receipt')
require(before['builds']['baseline']['receipt']['base_commit']=='f729c488f936040bff5dc6458393aba14dc77374', 'baseline source')
require(before['builds']['candidate']['receipt']['base_commit']=='54d2913069391c8d00d1079590194ab7d022b681', 'candidate source')
require(before['builds']['candidate']['receipt']['source_patch_sha256']=='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'clean candidate source')
require(before['R']==before['runtime']['R_version'], 'exact worker descriptive version')
patch=known_builds['baseline']/'source.patch'
require(sha(patch)==before['builds']['baseline']['receipt']['source_patch_sha256'], 'original baseline test patch hash')
require({line[6:] for line in patch.read_text().splitlines() if line.startswith('+++ b/')} == {'r-package/dtatools/tests/testthat/test-native-arithmetic-kernels.R','r-package/dtatools/tests/testthat/test-native-arithmetic-parity.R'}, 'baseline patch is declared tests only')
import importlib.util
spec=importlib.util.spec_from_file_location('verified_build_inventory',controller_paths['run.py'])
records=importlib.util.module_from_spec(spec);spec.loader.exec_module(records)
for role,path in known_builds.items():
    require(records.inventory(path,before['builds'][role]['receipt']['variant'])==before['builds'][role],'current complete source/installed/build inventory '+role)
paired=[]
for case in sorted({k[:-1] for k in expected}):
    values={v:{int(r['round']):float(r['cpu'])/int(r['iterations']) for r in groups[case+('compact',)] if r['variant']==v} for v in ('baseline','candidate')}
    paired.append(dict(zip(fields[:-1],case), median=statistics.median(values['baseline'][n]/values['candidate'][n] for n in range(1,7))))
report = dict(audit='Independent artifact recomputation; no builds, R or timing jobs', observations=648, summary_rows=36,
    checks=['worker/raw equality', 'complete matrix and all six permutations', 'result/storage/missing/source equality',
            'native route and unchanged source states', 'every CPU median, speedup and paired/control ratio',
            'before/after source/installed/controller equality and current controller hashes', 'completion/source-patch binding', 'current full named build/source/installed/DLL inventories'],
    case_speedups=[{k:s[k] for k in ('width','missing','operation','compact_speedup','compact_typed_ratio','compact_ordinary_ratio')} for s in candidate],
    runtime=before['runtime'],
    baseline_commit=before['builds']['baseline']['receipt']['base_commit'],
    candidate_commit=before['builds']['candidate']['receipt']['base_commit'],
    paired_speedups=paired, target_cases=4,
    all_case_typed_range=[min(float(s['compact_typed_ratio']) for s in candidate), max(float(s['compact_typed_ratio']) for s in candidate)],
    all_case_bare_range=[min(float(s['compact_ordinary_ratio']) for s in candidate), max(float(s['compact_ordinary_ratio']) for s in candidate)],
    all_case_speedup_range=[min(float(s['compact_speedup']) for s in candidate), max(float(s['compact_speedup']) for s in candidate)],
    binary_controls=[{k:s[k] for k in ('width', 'missing', 'compact_speedup', 'compact_typed_ratio')} for s in candidate if s['operation']=='scale_binary'],
    target_typed_range=[min(float(s['compact_typed_ratio']) for s in targets),max(float(s['compact_typed_ratio']) for s in targets)],
    target_speedup_range=[min(float(s['compact_speedup']) for s in targets),max(float(s['compact_speedup']) for s in targets)],
    controls=[{k:s[k] for k in ('width','missing','operation','compact_speedup')} for s in candidate if s not in targets],
    cpu_interval_range=[min(float(r['cpu']) for r in rows), max(float(r['cpu']) for r in rows)],
    wall_interval_range=[min(float(r['wall']) for r in rows), max(float(r['wall']) for r in rows)],
    caveats=['Calibration target is not the actual interval minimum.', 'Current complete source/installed inventories, compiler/build records and named DLLs independently reverified in the authorized setup window; no R or timing jobs.'],
    artifacts={name:sha(P / name) for name in ('raw.csv','summary.csv','protocol.json','provenance-before.json','provenance-after.json','completion.json','source.patch')})
OUT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps(report,indent=2,sort_keys=True))
