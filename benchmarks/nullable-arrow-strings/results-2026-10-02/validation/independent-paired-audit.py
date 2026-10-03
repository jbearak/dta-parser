from pathlib import Path
from collections import Counter
from itertools import product, permutations
from statistics import median
import csv, hashlib, json, math

ROOT=Path('<private-evidence>/paired-v1')
OUT=Path('<independent-audit>/nullable-paired-audit.json')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,msg):
    if not ok:raise ValueError(msg)
def close(a,b):return math.isclose(float(a),float(b),rel_tol=1e-10,abs_tol=1e-10)
def rows(p):
    with p.open(newline='') as f:return list(csv.DictReader(f))
raw=rows(ROOT/'raw.csv');summary=rows(ROOT/'summary.csv')
before=json.loads((ROOT/'binding-before.json').read_text());after=json.loads((ROOT/'binding-after.json').read_text());completion=json.loads((ROOT/'completion.json').read_text())
require(len(raw)==504 and len(summary)==84,'count')
require(completion['observations']==504 and completion['rounds']==6,'completion matrix')
for key in ('full_results_exact','raw_encoding_exact','bindings_unchanged','timings_collected'):require(completion[key] is True,key)
for name,digest in completion['artifacts'].items():require(sha(ROOT/name)==digest,'artifact '+name)
for key in ('builds','fixtures','controllers','runtime'):require(before[key]==after[key],'binding '+key)
for name,digest in before['controllers'].items():require(sha(Path(name))==digest,'current controller '+name)
for role,binding in before['builds'].items():
    require(binding['receipt']['toolchain']['R_runtime_sha256']==before['runtime']['R_runtime_sha256'],'actual runtime '+role)
    require(binding['receipt']['exit_code']==0 and binding['receipt']['pre_post_source_equal'] is True,'clean build '+role)
ids=['finite']+[f'{c}-{n}' for c,n in product(('low','high'),('zero','one','sparse'))]
variants=('baseline','candidate');threads=('0','1');modes=('read','scalar','full')
expected=Counter(product(ids,threads,modes));hashes=('values_sha256','metadata_sha256','encoding_sha256','consumption_sha256')
times=[k for k in raw[0] if k.endswith('_seconds')]
for variant,round_ in product(variants,range(1,7)):
    rr=[r for r in raw if r['variant']==variant and int(r['round'])==round_]
    require(Counter((r['id'],r['threads'],r['mode']) for r in rr)==expected,'matrix')
    require(sorted(int(r['ordinal']) for r in rr)==list(range(1,43)),'ordinals')
for round_,ordinal in product(range(1,7),range(1,43)):
    rr=[r for r in raw if int(r['round'])==round_ and int(r['ordinal'])==ordinal]
    require([r['variant'] for r in rr]==list(variants if round_%2 else reversed(variants)),'alternating paired build order')
    require(len({(r['id'],r['threads'],r['mode'],r['null_position']) for r in rr})==1,'paired same case')
for variant,card,thread,mode in product(variants,('low','high'),threads,modes):
    orders=[]
    for round_ in range(1,7):
        rr=[r for r in raw if r['variant']==variant and int(r['round'])==round_ and r['id'].startswith(card+'-') and r['threads']==thread and r['mode']==mode]
        require(sorted(int(r['null_position']) for r in rr)==[1,2,3],'positions')
        orders.append(tuple(r['id'].split('-')[1] for r in sorted(rr,key=lambda r:int(r['null_position']))))
    require(Counter(orders)==Counter(permutations(('zero','one','sparse'))),'six permutations')
for fixture in ids:
    rr=[r for r in raw if r['id']==fixture]
    require(len({tuple(r[k] for k in hashes) for r in rr})==1,'all semantic hashes '+fixture)
for row in raw:
    require(row['phase']=='measure' and row['variant'] in variants,'phase')
    require(int(row['rows'])==250000 and int(row['columns'])==4,'shape')
    nulls=1 if row['id'].endswith('-one') else 251 if row['id'].endswith('-sparse') else 0
    require(int(row['expected_na_per_column'])==nulls,'null count')
    require(int(row['dictionary_columns_after_workflow'])==(4 if row['id'].endswith('-zero') else 0),'representation')
    require(all(row[k]=='TRUE' for k in ('values_exact','metadata_exact','raw_encoding_exact','consumption_exact')),'qualified')
    require(all(len(row[k])==64 and all(c in '0123456789abcdef' for c in row[k]) for k in hashes),'hash shape')
    require(all(math.isfinite(float(row[k])) and float(row[k])>=0 for k in times),'timing finite')
    require(all(float(row[k])>0 for k in ('read_cpu_seconds','read_wall_seconds','total_cpu_seconds','total_wall_seconds')),'positive intervals')
    for unit in ('cpu','wall'):require(close(float(row[f'read_{unit}_seconds'])+float(row[f'consume_{unit}_seconds']),row[f'total_{unit}_seconds']),'component sum')
    if row['mode']!='full':require(all(float(row[k])==0 for k in ('second_cpu_seconds','second_wall_seconds','second_gc_cpu_seconds')),'second traversal absent')
    else:require(float(row['second_cpu_seconds'])>0 and float(row['second_wall_seconds'])>0,'second traversal positive')
    require(float(row['gc_cpu_seconds'])<=float(row['total_cpu_seconds'])+.01,'GC bound')
    require(float(row['second_gc_cpu_seconds'])<=float(row['second_cpu_seconds'])+.01,'second GC bound')
    filename=f"{int(row['round']):02}-{int(row['ordinal']):02}-{row['variant']}-{row['id']}-{row['threads']}-{row['mode']}.csv"
    worker=rows(ROOT/filename)
    require(len(worker)==1 and all(row[k]==v for k,v in worker[0].items()),'worker '+filename)
require(Counter((r['variant'],r['id'],r['threads'],r['mode']) for r in summary)==Counter(product(variants,ids,threads,modes)),'summary matrix')
for row in summary:
    rr=[r for r in raw if all(r[k]==row[k] for k in ('variant','id','threads','mode'))]
    for metric in times:
        vv=[float(r[metric]) for r in rr]
        for prefix,fn in [('median',median),('min',min),('max',max)]:require(close(row[prefix+'_'+metric],fn(vv)),'summary '+metric)
ratios=[]
for fixture,thread,mode in product(ids,threads,modes):
    group={v:sorted([r for r in raw if r['variant']==v and r['id']==fixture and r['threads']==thread and r['mode']==mode],key=lambda r:int(r['round'])) for v in variants}
    record=dict(id=fixture,threads=thread,mode=mode)
    for metric in ('read_cpu_seconds','read_wall_seconds','total_cpu_seconds','total_wall_seconds'):
        b=[float(r[metric]) for r in group['baseline']];c=[float(r[metric]) for r in group['candidate']]
        record[metric]={'baseline_median':median(b),'candidate_median':median(c),'speedup':median(b)/median(c),'paired_median_speedup':median(x/y for x,y in zip(b,c))}
    ratios.append(record)
nullable=[r for r in ratios if r['id'].endswith(('-one','-sparse'))]
controls=[r for r in ratios if r not in nullable]
report=dict(status='PASS',independent=True,observations=504,summaries=84,rounds=6,
    artifacts={n:sha(ROOT/n) for n in ('raw.csv','summary.csv','completion.json','binding-before.json','binding-after.json','protocol.json')},
    controllers=before['controllers'],runtime=before['runtime'],
    checks=['complete paired case/round matrix','alternating paired build order','all six null permutations','every worker CSV agrees','full values/NA/encoding/metadata/consumption hashes','exact representation diagnostics','every timing median/min/max','CPU/wall sums and GC bounds','completion hashes','unchanged source/library/fixture/controller/runtime records','current controller hashes','execution runtime matches both builds'],
    read_cpu_interval_range=[min(float(r['read_cpu_seconds']) for r in raw),max(float(r['read_cpu_seconds']) for r in raw)],
    nullable_read_cpu_speedup_range=[min(r['read_cpu_seconds']['speedup'] for r in nullable),max(r['read_cpu_seconds']['speedup'] for r in nullable)],
    nullable_full_cpu_speedup_range=[min(r['total_cpu_seconds']['speedup'] for r in nullable if r['mode']=='full'),max(r['total_cpu_seconds']['speedup'] for r in nullable if r['mode']=='full')],
    control_read_cpu_speedup_range=[min(r['read_cpu_seconds']['speedup'] for r in controls),max(r['read_cpu_seconds']['speedup'] for r in controls)],
    ratios=ratios,
    limits=['Single fresh-process reads have millisecond resolution; medians do not improve individual resolution.','Filesystem cache is uncontrolled, not a cold-disk measurement.','Current large fixture and installed files were not independently rehashed during this light audit; controller before/after bindings agree.','No RSS or universal workload claim.'])
OUT.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ('status','observations','summaries','read_cpu_interval_range','nullable_read_cpu_speedup_range','nullable_full_cpu_speedup_range','control_read_cpu_speedup_range')},indent=2))
print(json.dumps([r for r in ratios if r['mode']=='full' and r['id'] in ('low-zero','low-one','high-zero','high-one')],indent=2))
