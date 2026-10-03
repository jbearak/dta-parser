import csv
import hashlib
import itertools
import json
import math
import statistics
from collections import Counter, defaultdict
from pathlib import Path

P = Path('/private/tmp/dta-double-pair-mask-evidence/adaptive-ordinary-timings-v1')
OUT = Path('/private/tmp/dta-grouping-development/double-adaptive-ordinary-audit.json')
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
require(json.loads((P/'protocol.json').read_text())['R'] == before['execution']['R_version'], 'exact worker version binding')
require(completion['exact_results'] and completion['provenance_unchanged'] and completion['observations'] == len(rows), 'completion')
require(completion['source_patch_sha256'] == sha(P/'source.patch'), 'source patch binding')
require(all(build['receipt']['toolchain']['R_runtime_sha256'] == before['execution']['R_runtime_sha256'] for build in before['builds'].values()), 'actual execution/build runtime binding')
base=Path('/private/tmp/dta-native-comparison-followup/benchmarks')
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
             'Retained constructor adapter uses one fixed mismatched chunk geometry; no reader/decompression workload.',
             'Current full named source/installed/compiler/DLL inventories independently reverified in the authorized setup window.'],
    artifacts={name:sha(P/name) for name in ('raw.csv','summary.csv','protocol.json','provenance-before.json','provenance-after.json','completion.json','source.patch')})
known_builds = {'baseline':Path('/private/tmp/dta-native-comparison-evidence/float-adaptive-prototype'),
                'candidate':Path('/private/tmp/dta-double-pair-mask-evidence/adaptive-prototype')}
commits={'baseline':'e265f7375171c45ddeb5efdc3d7c978a615c132d', 'candidate':'76b46d92b63862262ddfd7b88b4b58781b01309f'}
for role,path in known_builds.items():
    receipt=json.loads((path/'build-receipt.json').read_text())
    require(receipt == before['builds'][role]['receipt'], 'actual named receipt '+role)
    require(receipt['base_commit'] == commits[role] and receipt['source_patch_sha256'] == hashlib.sha256(b'').hexdigest(), 'named exact clean source '+role)
    require(sha(path/'build-receipt.json') == before['builds'][role]['receipt_sha256'], 'actual receipt hash '+role)
report['verified_named_builds']={role:dict(path=str(path),base_commit=before['builds'][role]['receipt']['base_commit']) for role,path in known_builds.items()}
report['paired_speedups']=[]
for case in sorted({k[:-1] for k in expected}):
    batch=groups[case+('compact',)]
    values={v:{int(r['round']):float(r['cpu'])/int(r['repetitions']) for r in batch if r['variant']==v} for v in ('baseline','candidate')}
    ratios=[values['baseline'][n]/values['candidate'][n] for n in range(1,7)]
    report['paired_speedups'].append(dict(zip(fields[:-1],case),median=statistics.median(ratios),minimum=min(ratios),maximum=max(ratios)))
report['candidate_max_compact_typed_cpu']=max(float(s['candidate_compact_typed_cpu']) for s in summary)
report['candidate_max_missing_free_compact_bare_cpu']=max(float(s['candidate_compact_bare_cpu']) for s in summary if s['missing']=='FALSE')
report['checks'].append('named e265 and adaptive-double clean receipts match recorded before/after evidence')
import importlib.util
spec=importlib.util.spec_from_file_location('double_mask_build_validation',paths['build_validation'])
records=importlib.util.module_from_spec(spec);spec.loader.exec_module(records)
for role,path in known_builds.items():
    require(records.inventory(path,before['builds'][role]['receipt']['variant'])==before['builds'][role],'current full source/installed/compiler/DLL inventory '+role)
require({line[6:] for line in (P/'source.patch').read_text().splitlines() if line.startswith('+++ b/')}=={'src/rust/src/double_compare.rs'},'single-module source delta')
qualification=Path('/private/tmp/dta-double-pair-mask-evidence')
q=json.loads((qualification/'adaptive-ordinary-qualification.json').read_text())
require(q['observations']==72 and q['result']=='PASS' and q['clocked'] is False and q['worker_sha256']==before['controllers']['worker'],'recorded untimed qualification')
for name,digest in q['artifacts'].items():require(sha(qualification/name)==digest,'qualification artifact '+name)
qualifications=[]
for variant in ('baseline','candidate'):
    qual=list(csv.DictReader((qualification/('adaptive-ordinary-'+variant+'-qualification.csv')).open(newline='')))
    require(Counter(tuple(r[k] for k in fields) for r in qual)==Counter({k:1 for k in expected}),'complete qualification matrix')
    for r in qual:
        require(float(r['cpu'])==float(r['wall'])==0 and int(r['repetitions'])==1,'no-clock qualification')
        target=groups[tuple(r[k] for k in fields)]
        require(all(tuple(r[k] for k in identity)==tuple(t[k] for k in identity) for t in target),'qualification matches timed semantic records')
    qualifications.append(qual)
require(qualifications[0]==qualifications[1],'byte-equivalent qualification observations')
report['checks'].extend(['current full named source/installed/compiler/DLL inventories', 'single-module source delta', 'complete no-clock prior qualification semantics match every timed case'])
report['all_representation_speedups']=[]
for case in sorted({k[:-1] for k in expected}):
    for rep in reps:
        batch=groups[case+(rep,)]
        values={(v,m):{int(r['round']):float(r[m])/int(r['repetitions']) for r in batch if r['variant']==v} for v in ('baseline','candidate') for m in ('cpu','wall')}
        item=dict(zip(fields[:-1],case),representation=rep)
        for metric in ('cpu','wall'):
            item[metric+'_median_speedup']=statistics.median(values['baseline',metric].values())/statistics.median(values['candidate',metric].values())
            item[metric+'_paired_median_speedup']=statistics.median(values['baseline',metric][n]/values['candidate',metric][n] for n in range(1,7))
        report['all_representation_speedups'].append(item)
OUT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps({k:report[k] for k in ('observations','summary_rows','cpu_interval_range','wall_interval_range','baseline_candidate_tradeoff')},indent=2))
