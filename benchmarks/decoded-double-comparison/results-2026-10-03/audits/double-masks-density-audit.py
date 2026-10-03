import csv
import hashlib
import itertools
import json
import math
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

P = Path(sys.argv[1])
OUT = Path('/private/tmp/dta-grouping-development/double-masks-density-audit.json')
DENSITIES = ('random_half', 'clustered_half', 'all_tags')
OPS = ('pair_less', 'pair_equal')
REPS = ('compact', 'typed_double')
FIELDS = ('density', 'operation', 'representation')
EXPECTED = set(itertools.product(DENSITIES, OPS, REPS))
def require(ok, label):
    if not ok: raise RuntimeError(label)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def read(name): return list(csv.DictReader((P / name).open(newline='')))
def close(actual, expected, label):
    require(math.isclose(float(actual), expected, rel_tol=1e-12, abs_tol=1e-14), label)

rows, summary = read('raw.csv'), read('summary.csv')
require(len(rows) == 144 and len(summary) == 6, 'row counts')
rebuilt=[]
for round_ in range(1, 7):
    for variant in ('baseline','candidate') if round_ % 2 else ('candidate','baseline'):
        batch=read(f'{round_:02}-{variant}.csv')
        require(Counter(tuple(r[k] for k in FIELDS) for r in batch)==Counter({k:1 for k in EXPECTED}), 'matrix')
        require(all(int(r['round'])==round_ and int(r['rows'])==1000000 and r['threads']=='1' and r['phase']=='measure' for r in batch), 'round/shape/phase')
        density_order=tuple(dict.fromkeys(r['density'] for r in batch))
        require(density_order==tuple(itertools.permutations(DENSITIES))[round_-1], 'density order')
        for dp,density in enumerate(density_order,1):
            selected=[r for r in batch if r['density']==density]
            op_order=tuple(dict.fromkeys(r['operation'] for r in selected))
            require(op_order==(OPS if round_%2 else tuple(reversed(OPS))), 'operation order')
            require(all(int(r['density_position'])==dp for r in selected),'density position')
            for op,operation in enumerate(op_order,1):
                pair=[r for r in selected if r['operation']==operation]
                require([int(r['position']) for r in pair]==[1,2] and all(int(r['operation_position'])==op for r in pair),'representation/operation positions')
        rebuilt.extend(dict(variant=variant,**r) for r in batch)
require(rebuilt==rows,'worker/raw identity and alternating builds')
identity=('result_hash','input_hash','y_hash','metadata_x','metadata_y','rank_x_hash','rank_y_hash',
          'compact_before','materialized_before','y_compact_before','y_materialized_before',
          'x_missing','y_missing','pair_missing')
groups=defaultdict(list)
for r in rows:
    groups[tuple(r[k] for k in FIELDS)].append(r)
    require(int(r['repetitions'])>0 and all(math.isfinite(float(r[m])) and float(r[m])>0 for m in ('cpu','wall')),'positive intervals')
    require(r['native_qualified']=='TRUE','native eligibility')
    for key in identity[:7]: require(len(r[key])==64 and set(r[key])<=set('0123456789abcdef'),'hash format')
    for prefix in ('compact','materialized','y_compact','y_materialized'):require(r[prefix+'_before']==r[prefix+'_after'],'source state')
    flag=str(r['representation']=='compact').upper()
    require(r['compact_before']==r['y_compact_before']==flag and r['materialized_before']==r['y_materialized_before']=='FALSE','source representation')
    marginal=1000000 if r['density']=='all_tags' else 500000
    require(int(r['x_missing'])==int(r['y_missing'])==marginal,'missing marginal')
    require(500000<=int(r['pair_missing'])<=1000000 if r['density']=='random_half' else int(r['pair_missing'])==marginal,'joint density')
for key,batch in groups.items():
    require(len(batch)==12 and len({tuple(r[k] for k in identity) for r in batch})==1,'stable semantics/state across builds/rounds')
    for variant in ('baseline','candidate'):
        require(Counter(int(r['position']) for r in batch if r['variant']==variant)==Counter({1:3,2:3}),'balanced representation positions')
for density,op in itertools.product(DENSITIES,OPS):
    selected=[r for r in rows if r['density']==density and r['operation']==op]
    require(len({tuple(r[k] for k in ('result_hash','input_hash','y_hash','rank_x_hash','rank_y_hash','x_missing','y_missing','pair_missing')) for r in selected})==1,'equivalent representation oracle')
require(Counter((s['density'],s['operation']) for s in summary)==Counter({k:1 for k in itertools.product(DENSITIES,OPS)}),'summary matrix')
ratios=[]
for s in summary:
    case=(s['density'],s['operation'])
    values={(variant,rep,metric):{int(r['round']):float(r[metric])/int(r['repetitions']) for r in groups[case+(rep,)] if r['variant']==variant} for variant in ('baseline','candidate') for rep in REPS for metric in ('cpu','wall')}
    for variant in ('baseline','candidate'):
        for rep in REPS:
            for metric in ('cpu','wall'):
                close(s[f'{variant}_{rep}_{metric}'],statistics.median(values[variant,rep,metric].values()),'CPU/wall median')
        close(s[variant+'_compact_typed_cpu'],float(s[variant+'_compact_cpu'])/float(s[variant+'_typed_double_cpu']),'compact/typed ratio')
    for rep in REPS:
        for metric in ('cpu','wall'):
            close(s[f'{rep}_{metric}_speedup'],statistics.median(values['baseline',rep,metric].values())/statistics.median(values['candidate',rep,metric].values()),'speedup')
            close(s[f'{rep}_{metric}_paired_median_speedup'],statistics.median(values['baseline',rep,metric][n]/values['candidate',rep,metric][n] for n in range(1,7)),'paired speedup')
    ratios.append({k:s[k] for k in ('density','operation','compact_cpu_speedup','compact_cpu_paired_median_speedup','compact_wall_speedup','candidate_compact_typed_cpu','typed_double_cpu_speedup')})
before,after,completion=[json.loads((P/name).read_text()) for name in ('provenance-before.json','provenance-after.json','completion.json')]
require(before==after,'complete before/after binding')
require(completion['phase']=='measure' and completion['observations']==144 and completion['rounds']==6 and completion['exact_results'] and completion['provenance_unchanged'],'completion')
for name,digest in completion['artifacts'].items():require(sha(P/name)==digest,'artifact '+name)
require(all(b['receipt']['toolchain']['R_runtime_sha256']==before['execution']['R_runtime_sha256'] for b in before['builds'].values()),'actual worker runtime matches receipts')
base=Path('/private/tmp/dta-native-comparison-followup/benchmarks')
paths={'density_controller':Path('/private/tmp/dta-double-pair-mask-evidence/density-controller/run.py'),
       'density_worker':Path('/private/tmp/dta-double-pair-mask-evidence/density-controller/worker.R'),
       'build_validation':base/'native-operations/run.py',
       'build_recorder':base/'r-file-readers/record-builds.py',
       'build_recorder_parent':base/'io-optimization/record-builds.py'}
for name,digest in before['controllers'].items():require(sha(paths[name])==digest,'current controller '+name)
commits={'baseline':'e265f7375171c45ddeb5efdc3d7c978a615c132d','candidate':'764c6f511afe2e7058ef481407b8fe872a705f68'}
for variant,build in (('baseline','/private/tmp/dta-native-comparison-evidence/float-adaptive-prototype'),('candidate','/private/tmp/dta-double-pair-mask-evidence/prototype')):
    receipt=Path(build)/'build-receipt.json'
    require(json.loads(receipt.read_text())==before['builds'][variant]['receipt'] and sha(receipt)==before['builds'][variant]['receipt_sha256'],'original named receipt')
    require(before['builds'][variant]['receipt']['base_commit']==commits[variant] and before['builds'][variant]['receipt']['source_patch_sha256']==hashlib.sha256(b'').hexdigest(),'exact original source')
qualification=Path('/private/tmp/dta-double-pair-mask-evidence/density-qualification-v2')
q=json.loads((qualification/'completion.json').read_text())
require(q['phase']=='qualify' and q['observations']==24 and q['exact_results'],'prior no-clock qualification')
require(json.loads((qualification/'provenance-after.json').read_text())==before,'identically bound qualification')
for name,digest in q['artifacts'].items():require(sha(qualification/name)==digest,'qualification artifact')
import importlib.util
spec=importlib.util.spec_from_file_location('double_mask_build_validation',paths['build_validation'])
records=importlib.util.module_from_spec(spec);spec.loader.exec_module(records)
known_builds={'baseline':Path('/private/tmp/dta-native-comparison-evidence/float-adaptive-prototype'),'candidate':Path('/private/tmp/dta-double-pair-mask-evidence/prototype')}
for role,path in known_builds.items():
    require(records.inventory(path,before['builds'][role]['receipt']['variant'])==before['builds'][role],'current full source/installed/compiler/DLL inventory '+role)
require({line[6:] for line in (P/'source.patch').read_text().splitlines() if line.startswith('+++ b/')}=={'src/rust/src/double_compare.rs'},'single-module source delta')
report=dict(audit='Independent artifact recomputation; no R/build/timing jobs',observations=len(rows),summary_rows=len(summary),
    checks=['full case matrix and worker/raw identity','six density permutations and balanced representation/build/operation orders',
    'full result/input/rank/metadata hashes and unchanged source states','missing marginals/joint rates and native eligibility',
    'equivalent representation oracle','every CPU/wall median, speedup, paired speedup and typed ratio',
    'before/after bindings, original clean receipts, current controllers and exact execution runtime','identically bound prior qualification and every completion artifact hash', 'current full named source/installed/compiler/DLL inventories and single-module source delta'],
    ratios=ratios,joint_missing_by_density={density:next(int(r['pair_missing']) for r in rows if r['density']==density) for density in DENSITIES},
    cpu_interval_range=[min(float(r['cpu']) for r in rows),max(float(r['cpu']) for r in rows)],
    wall_interval_range=[min(float(r['wall']) for r in rows),max(float(r['wall']) for r in rows)],
    caveats=['Native eligibility is not a per-timed-call entry counter.','Randomized and clustered cases have different joint missing rates.',
    'Constructed modern retained float inputs, threads1 and fixed mismatched chunk geometry only.','Current full named source/installed/compiler/DLL inventories independently reverified in the authorized setup window.'],
    artifacts={name:sha(P/name) for name in ('raw.csv','summary.csv','protocol.json','provenance-before.json','provenance-after.json','completion.json','source.patch')})
OUT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps({k:report[k] for k in ('observations','summary_rows','ratios','cpu_interval_range','wall_interval_range','joint_missing_by_density')},indent=2))
