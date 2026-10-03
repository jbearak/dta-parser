import csv,hashlib,itertools,json,math,statistics
from collections import Counter,defaultdict
from decimal import Decimal
from pathlib import Path
P=Path(__file__).resolve().parent
read=lambda name:list(csv.DictReader((P/name).open()))
digest=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
def require(ok,msg):
    if not ok: raise RuntimeError(msg)
raw=read('raw.csv'); summary=read('summary.csv')
fields=('n','width','key_count','layout','representation')
expected={(str(n),w,str(k),l,r) for n in (100000,1000000) for w in (('byte','int','long','float') if n==100000 else ('int','float')) for k in ((1,4) if n==100000 else (1,)) for l in ('random','sorted') for r in ('compact','typed_double','ordinary')}
require(len(raw)==720 and len(summary)==60,'row counts')
rebuilt=[]
for round_ in range(1,7):
    for variant in ('baseline','candidate') if round_%2 else ('candidate','baseline'):
        rows=read(f'{round_:02}-{variant}.csv'); rebuilt.extend(dict(variant=variant,**r) for r in rows)
        require(Counter(tuple(r[k] for k in fields) for r in rows)==Counter({k:1 for k in expected}),'case matrix')
        require(all(r['round']==str(round_) and r['phase']=='timing' for r in rows),'round/phase')
require(rebuilt==raw,'raw concatenation')
groups=defaultdict(list)
for r in raw:
    groups[tuple(r[k] for k in fields)].append(r)
    require(int(r['iterations'])>0,'repetitions')
    require(all(math.isfinite(float(r[k])) and float(r[k])>0 for k in ('cpu_seconds','elapsed_seconds')),'interval')
    cache=8*int(r['n'])*int(r['key_count'])
    require(Decimal(r['key_cache_bytes'])==cache,'cache bytes')
    if r['variant']=='candidate':
        require(Decimal(r['prepared_bytes'])==cache and Decimal(r['prepared_values'])==cache//8 and Decimal(r['scalar_values'])==0,'route counters')
    require(all(len(r[k])==64 and set(r[k])<=set('0123456789abcdef') for k in ('result_sha256','metadata_sha256','source_sha256','ranks_sha256','source_state_sha256')),'hash fields')
identity=('result_sha256','metadata_sha256','result_storage','source_sha256','ranks_sha256','source_state_sha256')
for case,rows in groups.items():
    require(len(rows)==12 and len({tuple(r[k] for k in identity) for r in rows})==1,'stable semantics')
for variant in ('baseline','candidate'):
    for case in {k[:-1] for k in expected}:
        orders=[]
        for round_ in range(1,7):
            rows=sorted((r for r in raw if r['variant']==variant and int(r['round'])==round_ and tuple(r[k] for k in fields[:-1])==case),key=lambda r:int(r['order']))
            require([int(r['order']) for r in rows]==[1,2,3],'positions')
            orders.append(tuple(r['representation'] for r in rows))
        require(Counter(orders)==Counter(itertools.permutations(('compact','typed_double','ordinary'))),'balance')
for s in summary:
    rows=groups[tuple(s[k] for k in fields)]
    for variant in ('baseline','candidate'):
        sub=[r for r in rows if r['variant']==variant]
        for metric in ('cpu_seconds','elapsed_seconds'):
            value=statistics.median(float(r[metric])/int(r['iterations']) for r in sub)
            require(math.isclose(float(s[variant+'_'+metric]),value,rel_tol=1e-14),'median')
        require(float(s[variant+'_peak_vcell_bytes'])==statistics.median(float(r['peak_vcell_bytes']) for r in sub),'memory median')
    require(math.isclose(float(s['cpu_speedup']),float(s['baseline_cpu_seconds'])/float(s['candidate_cpu_seconds']),rel_tol=1e-14),'speedup')
before=json.loads((P/'provenance-before.json').read_text()); after=json.loads((P/'provenance-after.json').read_text()); completion=json.loads((P/'completion.json').read_text())
require(before['builds']==after['builds'] and before['controllers']==after['controllers'],'provenance stability')
require(completion['observations']==720 and completion['exact_results'] and completion['provenance_unchanged'],'completion')
require(completion['source_patch_sha256']==digest(P/'source.patch'),'source patch binding')
root=Path('<repo>/benchmarks')
for name,sha in before['controllers'].items(): require(digest(root/name)==sha,'current controller '+name)
report=dict(audit='Independent read-only artifact recomputation; no builds or measurements',observations=len(raw),summary_rows=len(summary),checks=['worker/raw equality','complete unique matrix','all six representation orders','full semantic/source hashes across builds/rounds','exact route/memory counters','all per-call CPU/wall medians, memory medians and speedups','before/after source and installed inventory equality','current controller hashes','source patch completion binding'],cpu_interval_seconds=[min(float(r['cpu_seconds']) for r in raw),max(float(r['cpu_seconds']) for r in raw)],speedup_range=[min(float(s['cpu_speedup']) for s in summary),max(float(s['cpu_speedup']) for s in summary)],artifacts={name:digest(P/name) for name in ('raw.csv','summary.csv','protocol.json','provenance-before.json','provenance-after.json','completion.json','source.patch')})
(P/'independent-audit.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
# Recompute the later case-ratio table independently from the raw observations.
ratio_path = P.parent / 'validation' / 'ratio-summary.csv'
if not ratio_path.is_file():
    ratio_path = Path('<validation>/ratio-summary.csv')
ratio_rows = list(csv.DictReader(ratio_path.open()))
require(len(ratio_rows) == 20, 'ratio table row count')
for summary_row in ratio_rows:
    key = tuple(summary_row[name] for name in fields[:-1])
    selected = [row for row in raw if tuple(row[name] for name in fields[:-1]) == key]
    medians = {}
    for variant in ('baseline', 'candidate'):
        for representation in ('compact', 'typed_double', 'ordinary'):
            batch = [row for row in selected if row['variant'] == variant and row['representation'] == representation]
            medians[variant, representation] = statistics.median(float(row['cpu_seconds']) / int(row['iterations']) for row in batch)
            require(math.isclose(medians[variant, representation], float(summary_row[variant + '_' + representation + '_cpu_seconds']), rel_tol=1e-14), 'ratio table CPU median')
            require(float(summary_row[variant + '_' + representation + '_peak_vcell_bytes']) == statistics.median(float(row['peak_vcell_bytes']) for row in batch), 'ratio table memory median')
        for representation in ('typed_double', 'ordinary'):
            require(math.isclose(float(summary_row[variant + '_compact_over_' + representation]), medians[variant, 'compact'] / medians[variant, representation], rel_tol=1e-14), 'ratio table control ratio')
            pairs = []
            for round_number in range(1, 7):
                paired = {row['representation']: float(row['cpu_seconds']) / int(row['iterations']) for row in selected if row['variant'] == variant and int(row['round']) == round_number}
                pairs.append(paired['compact'] / paired[representation])
            require(math.isclose(float(summary_row[variant + '_paired_compact_over_' + representation]), statistics.median(pairs), rel_tol=1e-14), 'ratio table paired control ratio')
    require(math.isclose(float(summary_row['compact_cpu_speedup']), medians['baseline', 'compact'] / medians['candidate', 'compact'], rel_tol=1e-14), 'ratio table compact speedup')
report['checks'].append('20-case ratio summary: all CPU/memory medians, compact/typed and compact/ordinary ratios, paired-round ratios and compact speedups')
report['ratio_summary_sha256'] = digest(ratio_path)
report['compact_speedup_range'] = [min(float(row['compact_cpu_speedup']) for row in ratio_rows), max(float(row['compact_cpu_speedup']) for row in ratio_rows)]
(P / 'independent-audit.json').write_text(json.dumps(report, indent=2) + '\n')
print('Ratio-table extension passed')
