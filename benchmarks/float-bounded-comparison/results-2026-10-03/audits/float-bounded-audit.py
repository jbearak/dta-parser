"""Independent recomputation; run only after exclusive measurements finish."""
import csv, hashlib, importlib.util, itertools, json, math, statistics, subprocess
from collections import Counter, defaultdict
from pathlib import Path

ROOT=Path('/private/tmp/dta-float-bounded-evidence')
OUT=Path('/private/tmp/dta-grouping-development/float-bounded-audit.json')
PANELS={'density':('random_half','clustered_half','all_tags'), 'pattern':('dense_prefix256','dense_suffix256','alternating64'), 'ordinary':('none','sparse')}
LAYOUTS=('plain','retained'); OPS=('pair_less','pair_equal'); REPS=('compact','typed_double')
FIELDS=('pattern','layout','operation','representation')
HASHES=('result_hash','input_hash','y_hash','metadata_x','metadata_y','rank_x_hash','rank_y_hash')
STATES=('compact','materialized','y_compact','y_materialized','retained','y_retained','chunks','y_chunks')
VALUE=('result_hash','input_hash','y_hash','rank_x_hash','rank_y_hash','x_missing','y_missing','pair_missing')
IDENTITY=HASHES+tuple(s+'_before' for s in STATES)+('x_missing','y_missing','pair_missing')
def need(ok,label):
 if not ok: raise RuntimeError(label)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return list(csv.DictReader(p.open(newline='')))
def close(a,b,label):need(math.isclose(float(a),b,rel_tol=1e-12,abs_tol=1e-14),label)
def counts(p):
 if p=='none':return 0,0,0
 if p=='sparse':
  a=set(range(13,1000001,997));b=set(range(19,1000001,991));return len(a),len(b),len(a|b)
 if p=='random_half':return 500000,500000,None
 v={'clustered_half':500000,'all_tags':1000000,'dense_prefix256':256,'dense_suffix256':256,'alternating64':500032}[p];return v,v,v

def audit_rows(directory,panel,rounds,phase):
 patterns=PANELS[panel];expected=set(itertools.product(patterns,LAYOUTS,OPS,REPS))
 rows=read(directory/'raw.csv');need(len(rows)==2*rounds*len(expected),'row count')
 rebuilt=[]
 for number in range(1,rounds+1):
  porder=tuple(itertools.permutations(patterns))[(number-1)%6] if len(patterns)==3 else (patterns if number%2 else patterns[::-1])
  oorder=OPS if number%2 else OPS[::-1]
  for variant in ('baseline','candidate') if number%2 else ('candidate','baseline'):
   batch=read(directory/f'{number:02}-{variant}.csv')
   need(Counter(tuple(r[k] for k in FIELDS) for r in batch)==Counter({k:1 for k in expected}),'matrix')
   wanted=[]
   for pp,p in enumerate(porder,1):
    lo=LAYOUTS if (number+patterns.index(p)+1)%2 else LAYOUTS[::-1]
    for lp,l in enumerate(lo,1):
     for op,o in enumerate(oorder,1):
      case=patterns.index(p)*4+LAYOUTS.index(l)*2+OPS.index(o)+1
      ro=REPS if (number+case)%2 else REPS[::-1]
      for rp,r in enumerate(ro,1):wanted.append((p,l,o,r,pp,lp,op,rp))
   need([(r['pattern'],r['layout'],r['operation'],r['representation'],int(r['pattern_position']),int(r['layout_position']),int(r['operation_position']),int(r['position'])) for r in batch]==wanted,'complete order')
   need(all(r['panel']==panel and int(r['round'])==number and r['phase']==phase and r['threads']=='1' and int(r['rows'])==1000000 for r in batch),'shape/phase')
   rebuilt.extend(dict(variant=variant,**r) for r in batch)
 need(rebuilt==rows,'exact worker/raw identity')
 groups=defaultdict(list)
 for r in rows:
  groups[tuple(r[k] for k in FIELDS)].append(r)
  need(int(r['repetitions'])>0,'reps')
  if phase=='qualify':need(int(r['repetitions'])==1,'qualification reps')
  for metric in ('cpu','wall'):
   x=float(r[metric]);need(math.isfinite(x) and (x>0 if phase=='measure' else x==0),'interval')
  need(r['native_qualified']=='TRUE','native eligibility')
  for h in HASHES:need(len(r[h])==64 and set(r[h])<=set('0123456789abcdef'),'hash')
  for s in STATES:need(r[s+'_before']==r[s+'_after'],'state stable')
  compact=r['representation']=='compact';retained=compact and r['layout']=='retained'
  need(r['compact_before']==r['y_compact_before']==str(compact).upper(),'compact state')
  need(r['materialized_before']==r['y_materialized_before']=='FALSE','unmaterialized state')
  need(int(r['retained_before'])==int(r['y_retained_before'])==int(retained),'retained state')
  need(int(r['chunks_before'])==(123 if retained else 0) and int(r['y_chunks_before'])==(62 if retained else 0),'chunk geometry')
  xm,ym,j=counts(r['pattern']);need(int(r['x_missing'])==xm and int(r['y_missing'])==ym,'missing marginals')
  need(500000<=int(r['pair_missing'])<=1000000 if j is None else int(r['pair_missing'])==j,'joint missing')
 for case,batch in groups.items():
  need(len({tuple(r[k] for k in IDENTITY) for r in batch})==1,'stable semantics across builds/rounds')
  if phase=='measure':
   for variant in ('baseline','candidate'):
    for pos in ('position','layout_position'):
     need(Counter(int(r[pos]) for r in batch if r['variant']==variant)==Counter({1:3,2:3}),'position balance')
 for p,o in itertools.product(patterns,OPS):
  need(len({tuple(r[k] for k in VALUE) for r in rows if r['pattern']==p and r['operation']==o})==1,'cross layout/representation oracle')
 return rows,groups

reports=[];bindings=[]
for panel in PANELS:
 p=ROOT/f'timing-{panel}-v1';q=ROOT/f'qualification-{panel}-v1'
 rows,groups=audit_rows(p,panel,6,'measure');qr,qgroups=audit_rows(q,panel,1,'qualify')
 for case in groups:need(tuple(groups[case][0][k] for k in IDENTITY)==tuple(qgroups[case][0][k] for k in IDENTITY),'qualification semantics')
 before=json.loads((p/'provenance-before.json').read_text());need(before==json.loads((p/'provenance-after.json').read_text()),'measurement binding')
 need(before==json.loads((q/'provenance-before.json').read_text())==json.loads((q/'provenance-after.json').read_text()),'qualification binding')
 bindings.append(before)
 for path,phase,n in [(p,'measure',len(rows)),(q,'qualify',len(qr))]:
  c=json.loads((path/'completion.json').read_text());need(c['phase']==phase and c['panel']==panel and c['observations']==n and c['rounds']==(6 if phase=='measure' else 1) and c['exact_results'] and c['provenance_unchanged'],'completion')
  for name,h in c['artifacts'].items():need(sha(path/name)==h,'completed artifact '+name)
  protocol=json.loads((path/'protocol.json').read_text());need(protocol['phase']==phase and protocol['panel']==panel and protocol['rounds']==c['rounds'] and protocol['cases_per_build_round']==len(groups),'protocol')
 need({x[6:] for x in (p/'source.patch').read_text().splitlines() if x.startswith('+++ b/')}=={'src/rust/src/float_compare.rs'},'single-module source delta')
 summary=read(p/'summary.csv');keys=('pattern','layout','operation')
 need(Counter(tuple(r[k] for k in keys) for r in summary)==Counter({k:1 for k in itertools.product(PANELS[panel],LAYOUTS,OPS)}),'summary matrix')
 for s in summary:
  case=tuple(s[k] for k in keys)
  values={(variant,rep,metric):{int(r['round']):float(r[metric])/int(r['repetitions']) for r in groups[case+(rep,)] if r['variant']==variant} for variant in ('baseline','candidate') for rep in REPS for metric in ('cpu','wall')}
  for variant in ('baseline','candidate'):
   for rep in REPS:
    for metric in ('cpu','wall'):close(s[f'{variant}_{rep}_{metric}'],statistics.median(values[variant,rep,metric].values()),'median')
   close(s[variant+'_compact_typed_cpu'],float(s[variant+'_compact_cpu'])/float(s[variant+'_typed_double_cpu']),'compact/typed ratio')
  for rep in REPS:
   for metric in ('cpu','wall'):
    close(s[f'{rep}_{metric}_speedup'],statistics.median(values['baseline',rep,metric].values())/statistics.median(values['candidate',rep,metric].values()),'speedup')
    close(s[f'{rep}_{metric}_paired_median_speedup'],statistics.median(values['baseline',rep,metric][n]/values['candidate',rep,metric][n] for n in range(1,7)),'paired ratio')
 reports.append(dict(panel=panel,observations=len(rows),qualification_observations=len(qr),summary=summary,cpu_interval=[min(float(r['cpu']) for r in rows),max(float(r['cpu']) for r in rows)],wall_interval=[min(float(r['wall']) for r in rows),max(float(r['wall']) for r in rows)],artifacts={n:sha(p/n) for n in ('raw.csv','summary.csv','completion.json','source.patch','provenance-before.json','provenance-after.json','protocol.json')}))
need(bindings[0]==bindings[1]==bindings[2],'all panels same binding');before=bindings[0]
controller=ROOT/'controller';repo=Path('/private/tmp/dta-float-bounded-fallback/benchmarks')
paths={'controller':controller/'run.py','worker':controller/'worker.R','validation':controller/'core.py','protocol_tests':controller/'test-run.py','build_validation':repo/'native-operations/run.py','build_recorder':repo/'r-file-readers/record-builds.py','build_recorder_parent':repo/'io-optimization/record-builds.py'}
need(set(paths)==set(before['controllers']),'controller keys')
for name,h in before['controllers'].items():need(sha(paths[name])==h,'current controller '+name)
spec=importlib.util.spec_from_file_location('independent_float_build_binding',paths['build_validation']);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
commits={'baseline':'bb135c1f274e0ddb5d37d29fdccdcf34b09f83f2','candidate':'847919ceb78bf08674fca9f9af02583449e590a6'}
for role,build in [('baseline',Path('/private/tmp/dta-double-pair-mask-evidence/bounded-prototype')),('candidate',ROOT/'candidate-v1')]:
 saved=before['builds'][role];need(saved['receipt']['base_commit']==commits[role] and saved['receipt']['source_patch_sha256']==hashlib.sha256(b'').hexdigest(),'exact source')
 need(module.inventory(build,saved['receipt']['variant'])==saved,'current source/installed/DLL inventories and build-time compiler receipt '+role)
 need(saved['receipt']['toolchain']['R_runtime_sha256']==before['execution']['R_runtime_sha256'],'exact runtime')
launcher=Path(before['execution']['Rscript']);need(sha(launcher)==before['execution']['Rscript_sha256'],'execution launcher')
rhome=Path(subprocess.check_output([str(launcher),'--vanilla','-e','cat(R.home())'],text=True))
need(sha(rhome/'bin/exec/R')==before['execution']['R_runtime_sha256'],'current exact worker runtime')
report=dict(result='PASS',observations=sum(r['observations'] for r in reports),qualification_observations=sum(r['qualification_observations'] for r in reports),panels=reports,checks=['Independent full matrix/order/worker identity','Whole value/result/rank hashes, metadata, missing counts, retained chunk states','All medians, ratios of medians and paired-round ratios','Complete final qualification bindings and artifacts','Current exact source/installed/DLL/runtime/controller inventories and recorded build-time compiler identity'],caveats=['One host; modern canonical values; threads1; fixed retained chunk geometry.','Native eligibility is not a per-timed-call count.','Pattern contrasts do not isolate branch prediction.'])
OUT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps(dict(result='PASS',observations=report['observations'],qualification_observations=report['qualification_observations'],output=str(OUT))))
