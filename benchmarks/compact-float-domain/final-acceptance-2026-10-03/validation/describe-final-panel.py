#!/usr/bin/env python3
"""Describe all final cases and paired control movement after independent audit."""
from pathlib import Path
import csv, hashlib, json, statistics
ROOT=Path(__file__).resolve().parent
RAW=ROOT/'acceptance-v1/raw.csv'
AUDIT=ROOT/'acceptance-independent-audit.json'
def need(ok,message):
    if not ok:raise RuntimeError(message)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
audit=json.loads(AUDIT.read_text());need(audit['result']=='PASS' and audit['observations']==1224,'Complete independent audit required')
need(audit['artifacts']['raw.csv']==sha(RAW),'Audited raw data changed')
rows=list(csv.DictReader(RAW.open()))
keys=('width','missing','operation');roles=('baseline','candidate');reps=('compact','typed_double','ordinary')
index={tuple(r[k] for k in keys)+(r['variant'],r['representation'],int(r['round'])):r for r in rows}
need(len(index)==len(rows)==1224,'Incomplete or repeated observations')
cases=sorted({tuple(r[k] for k in keys) for r in rows});need(len(cases)==34,'Wrong case matrix')
result=[]
for case in cases:
    costs={(role,rep,rnd):float(index[case+(role,rep,rnd)]['cpu'])/int(index[case+(role,rep,rnd)]['iterations']) for role in roles for rep in reps for rnd in range(1,7)}
    med={(role,rep):statistics.median(costs[role,rep,rnd] for rnd in range(1,7)) for role in roles for rep in reps}
    item=dict(zip(keys,case))
    item.update(baseline_cpu_ms=med['baseline','compact']*1000,candidate_cpu_ms=med['candidate','compact']*1000,
        direct_speedup=med['baseline','compact']/med['candidate','compact'],
        paired_speedup=statistics.median(costs['baseline','compact',rnd]/costs['candidate','compact',rnd] for rnd in range(1,7)))
    for rep in ('typed_double','ordinary'):
        norm=[(costs['candidate','compact',rnd]/costs['baseline','compact',rnd])/(costs['candidate',rep,rnd]/costs['baseline',rep,rnd]) for rnd in range(1,7)]
        item[rep+'_ratio']=med['candidate','compact']/med['candidate',rep]
        item[rep+'_paired_ratio']=statistics.median(costs['candidate','compact',rnd]/costs['candidate',rep,rnd] for rnd in range(1,7))
        item[rep+'_control_normalized_cost']=statistics.median(norm)
        item[rep+'_normalized_slower_rounds']=sum(x>1 for x in norm)
        item[rep+'_normalized_round_costs']=norm
    result.append(item)
counts={rep:{'at_most_1_10':sum(r[rep+'_ratio']<=1.10 for r in result),'at_most_1_50':sum(r[rep+'_ratio']<=1.50 for r in result),'range':[min(r[rep+'_ratio'] for r in result),max(r[rep+'_ratio'] for r in result)]} for rep in ('typed_double','ordinary')}
report=dict(scope='Descriptive original34 final ratios and per-round compact candidate/baseline cost divided by matched control cost. Threshold counts1.10 and1.50 are descriptive, not statistical acceptance gates. No causal or universal parity claim.',source_commits=audit['source_commits'],input_sha256={'raw.csv':sha(RAW),'acceptance-independent-audit.json':sha(AUDIT)},counts=counts,results=result)
(ROOT/'final-panel-description.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
lines=['| Storage | Sparse missing | Operation | Compact CPU ms | Gain vs7003 | Paired gain | / typed doubles | / bare doubles |','| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |']
for r in result:
    lines.append('| '+ ' | '.join([r['width'],'yes' if r['missing']=='TRUE' else 'no',r['operation'],*(f'{r[k]:.3f}' for k in ('candidate_cpu_ms','direct_speedup','paired_speedup','typed_double_ratio','ordinary_ratio'))])+' |')
(ROOT/'final-panel-table.md').write_text('\n'.join(lines)+'\n')
completion=dict(status='PASS', generator_sha256=sha(Path(__file__)),
    inputs=report['input_sha256'], outputs={name:sha(ROOT/name) for name in ('final-panel-description.json','final-panel-table.md')},
    scope='Description and table generated together from independently audited1224 observations; descriptive statistics only.')
(ROOT/'final-panel-description-completion.json').write_text(json.dumps(completion,indent=2,sort_keys=True)+'\n')
print(json.dumps(counts,indent=2))
