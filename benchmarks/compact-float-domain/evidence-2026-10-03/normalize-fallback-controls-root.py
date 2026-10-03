"""Replay the retained descriptive control normalization after complete audits."""
from pathlib import Path
import csv, hashlib, json, statistics
p=Path(__file__).resolve().parent
out={'status':'PASS','scope':'Descriptive per-round compact candidate/baseline costs normalized by matched typed controls. Not a significance test.','panels':{},'input_sha256':{}}
for panel in ('strict','unknown'):
    audit=json.loads((p/f'{panel}-fallback-independent-audit-root.json').read_text())
    if audit['status']!='PASS' or audit['observations']!=(696 if panel=='strict' else 144):
        raise RuntimeError('Complete panel audit required')
    f=p/f'{panel}-fallback-screen-v1/raw.csv'
    rows=list(csv.DictReader(f.open()))
    idx={tuple(r[k] for k in ('layout','pattern','operation','variant','representation','round')):r for r in rows}
    result=[]
    def cpu(key):
        r=idx[key]
        return float(r['cpu'])/int(r['repetitions'])
    for case in sorted({tuple(r[k] for k in ('layout','pattern','operation')) for r in rows}):
        costs=[(cpu(case+('candidate','compact',str(n)))/cpu(case+('baseline','compact',str(n))))/(cpu(case+('candidate','typed_double',str(n)))/cpu(case+('baseline','typed_double',str(n)))) for n in range(1,7)]
        result.append(dict(zip(('layout','pattern','operation'),case))|{'normalized_cost':statistics.median(costs),'slower_rounds':sum(x>1 for x in costs),'round_costs':costs})
    out['panels'][panel]=result
    out['input_sha256'][str(f.relative_to(p))]=hashlib.sha256(f.read_bytes()).hexdigest()
expected=(json.dumps(out,indent=2,sort_keys=True)+'\n').encode()
if expected!=(p/'fallback-control-normalization-root.json').read_bytes():
    raise RuntimeError('Retained normalization differs from independent replay')
print('PASS retained normalization: 32 cases, all per-round costs and slower-round counts')
