"""Independent artifact audit. Run only after exclusive timing is terminal."""
import argparse,csv,hashlib,importlib.util,itertools,json,math,shutil,statistics,subprocess
from collections import Counter,defaultdict
from pathlib import Path
A=argparse.ArgumentParser();A.add_argument('--timing',type=Path,required=True);A.add_argument('--candidate',type=Path,required=True)
args=A.parse_args();P=args.timing;E=Path('<private-tmp>/dta-long-float-add-audit');Q=E/'qualification-v1';D=E/'screen-controller';REPO=Path('<private-tmp>/dta-long-float-add-blocks')
PANELS={'plain':['none','sparse','random_half','prefix256','suffix256','all_tags'],'retained':['none','sparse','random_half','prefix256','suffix256'],'short':['none','sparse']}
OPS=['long_float','float_long'];FIELDS=('layout','pattern','operation','representation');N=1000000
REPS=lambda p:['compact','typed_double','ordinary'] if p=='none' else ['compact','typed_double']
CASES={(l,p,o,r) for l,ps in PANELS.items() for p in ps for o in OPS for r in REPS(p)}
BUILDS={'baseline':Path('<private-tmp>/dta-native-integration-final-evidence/combined-build'),'candidate':args.candidate}
COMMITS={'baseline':'7003eba901671797ee91fffc97f08e28a1f7f515','candidate':'387227cdb8a174feccb24e5f52745177c5af3f95'}
HASHES=('input_hash','rank_hash','result_hash','missing_hash','metadata_hash','result_metadata_hash')
COUNTS=('long_missing','float_missing','overlap','result_missing')
STATES=tuple(a+'_'+b for a in ('long','float') for b in ('compact','materialized','retained','chunks'))
SEMANTICS=HASHES+COUNTS+('result_storage','mutation_checked','cleared_hash')+tuple(k+'_before' for k in STATES)
def need(ok,s):
 if not ok:raise RuntimeError(s)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return list(csv.DictReader(p.open(newline='')))
def close(x,y):need(math.isclose(float(x),y,rel_tol=1e-12,abs_tol=1e-14),'summary statistic')
def rotated(xs,n):
 xs=list(xs);i=(n-1)%len(xs);xs=xs[i:]+xs[:i];return xs if n%2 else xs[::-1]
def validate(batch,n,phase):
 need(Counter(tuple(r[k] for k in FIELDS) for r in batch)==Counter({c:1 for c in CASES}),'complete58-case matrix')
 order=[]
 for lp,l in enumerate(rotated(PANELS,n),1):
  for pp,p in enumerate(rotated(PANELS[l],n),1):
   for op,o in enumerate(OPS if n%2 else OPS[::-1],1):
    reps=REPS(p)
    if len(reps)==3:reps=list(itertools.permutations(reps))[(n-1+OPS.index(o)+list(PANELS).index(l))%6]
    elif (n+PANELS[l].index(p)+OPS.index(o)+list(PANELS).index(l))%2==0:reps=reps[::-1]
    order.extend(((l,p,o,r),(lp,pp,op,rp)) for rp,r in enumerate(reps,1))
 need([(tuple(r[k] for k in FIELDS),tuple(int(r[k]) for k in ('layout_position','pattern_position','operation_position','position'))) for r in batch]==order,'exact layout/pattern/operand/representation order')
 xs=set(range(13,N+1,997));ys=set(range(19,N+1,991))
 known={'none':(0,0,0),'sparse':(len(xs),len(ys),len(xs&ys)),'prefix256':(0,256,0),'suffix256':(0,256,0),'all_tags':(N,N,N)}
 for r in batch:
  need(r['phase']==phase and int(r['round'])==n and int(r['rows'])==N and int(r['threads'])==1,'phase/geometry')
  count=int(r['repetitions']);need(count>0,'positive repetitions');native=r['representation']!='ordinary'
  need(int(r['native_calls'])==(count if native else 0) and int(r['qualification_calls'])==int(native),'native route both builds')
  need(r['result_storage']==('double' if native else '') and r['mutation_checked']==str(native).upper(),'storage/cache mutation')
  need(count==1 if phase=='qualify' else True,'untimed single call')
  for k in ('cpu','wall'):
   v=float(r[k]);need(math.isfinite(v) and (v==0 if phase=='qualify' else v>0),'clock')
  a,b,c=map(lambda k:int(r[k]),COUNTS[:3]);need(0<=c<=min(a,b),'missing overlap bounds')
  need((a,b,c)==known[r['pattern']] if r['pattern'] in known else (a,b)==(N//2,N//2),'independent input counts')
  need(int(r['result_missing'])==a+b-c,'missing union')
  for side in ('long','float'):
   retained=r['representation']=='compact' and r['layout']!='plain'
   size={'retained':{'long':8191,'float':16385},'short':{'long':7,'float':11}}.get(r['layout'],{}).get(side,1)
   expect={'compact':int(r['representation']=='compact'),'materialized':0,'retained':int(retained),'chunks':math.ceil(N/size) if retained else 0}
   for k,v in expect.items():need(int(r[side+'_'+k+'_before'])==v==int(r[side+'_'+k+'_after']),'captured source state')
  for k in HASHES+(('cleared_hash',) if native else ()):
   need(len(r[k])==64 and set(r[k])<=set('0123456789abcdef'),'full hashes')
  need(native or r['cleared_hash']=='','bare cache claim')
def directory(path,phase,rounds):
 completion=json.loads((path/'completion.json').read_text());need(completion['phase']==phase and completion['rounds']==rounds and completion['observations']==116*rounds and completion['exact_results'] is True and completion['provenance_unchanged'] is True,'completion')
 before=json.loads((path/'provenance-before.json').read_text());need(before==json.loads((path/'provenance-after.json').read_text()),'unchanged bindings')
 protocol=json.loads((path/'protocol.json').read_text());need(protocol['phase']==phase and protocol['rounds']==rounds and protocol['cases_per_build_round']==58,'protocol geometry')
 names={'provenance-before.json','provenance-after.json','protocol.json','source.patch','raw.csv'}|{f'{n:02}-{v}.csv' for n in range(1,rounds+1) for v in BUILDS}
 if phase=='measure':names.add('summary.csv')
 need(set(completion['artifacts'])==names,'complete completion artifact set')
 for name,h in completion['artifacts'].items():need(sha(path/name)==h,'bound artifact '+name)
 rows=[]
 for n in range(1,rounds+1):
  for v in ('baseline','candidate') if n%2 else ('candidate','baseline'):
   batch=read(path/f'{n:02}-{v}.csv');validate(batch,n,phase);rows.extend(dict(variant=v,**r) for r in batch)
 need(rows==read(path/'raw.csv'),'worker/raw identity and exact paired build order')
 return rows,before
rows,before=directory(P,'measure',6);qualified,qbefore=directory(Q,'qualify',1);need(before==qbefore,'qualification and measurement identical binding')
qmap={(r['variant'],*(r[k] for k in FIELDS)):tuple(r[k] for k in SEMANTICS) for r in qualified}
for r in rows:need(tuple(r[k] for k in SEMANTICS)==qmap[r['variant'],*(r[k] for k in FIELDS)],'qualified full semantics')
for case in CASES:
 g=[r for r in rows if tuple(r[k] for k in FIELDS)==case]
 need(len({tuple(r[k] for k in SEMANTICS) for r in g})==1,'stable semantics across builds/rounds')
 for v in BUILDS:need(Counter(int(r['position']) for r in g if r['variant']==v)==Counter({p:6//len(REPS(case[1])) for p in range(1,len(REPS(case[1]))+1)}),'balanced representation positions')
for pattern in PANELS['plain']:
 g=[r for r in rows if r['pattern']==pattern]
 need(len({tuple(r[k] for k in HASHES[:4]+COUNTS) for r in g})==1,'equivalent inputs/results across geometry/operand order/representation')
 need(len({r['cleared_hash'] for r in g if r['representation']!='ordinary'})==1,'equivalent full cleared values')
summary=read(P/'summary.csv');need(Counter((r['layout'],r['pattern'],r['operation']) for r in summary)==Counter({(l,p,o):1 for l,ps in PANELS.items() for p in ps for o in OPS}),'26 summary cases')
for s in summary:
 batch=[r for r in rows if all(r[k]==s[k] for k in FIELDS[:3])]
 values={(v,rep,m):{int(r['round']):float(r[m])/int(r['repetitions']) for r in batch if r['variant']==v and r['representation']==rep} for v in BUILDS for rep in REPS(s['pattern']) for m in ('cpu','wall')}
 for (v,rep,m),nums in values.items():close(s[f'{v}_{rep}_{m}'],statistics.median(nums.values()))
 for rep in REPS(s['pattern']):
  for m in ('cpu','wall'):
   b=values['baseline',rep,m];c=values['candidate',rep,m]
   close(s[f'{rep}_{m}_speedup'],statistics.median(b.values())/statistics.median(c.values()))
   close(s[f'{rep}_{m}_paired_speedup'],statistics.median(b[n]/c[n] for n in range(1,7)))
 for v in BUILDS:
  for rep,label in [('typed_double','typed')]+([('ordinary','ordinary')] if s['pattern']=='none' else []):close(s[f'{v}_compact_{label}_cpu'],statistics.median(values[v,'compact','cpu'].values())/statistics.median(values[v,rep,'cpu'].values()))
paths={'controller':D/'run.py','worker':D/'worker.R','validation':D/'core.py','protocol_tests':D/'test-run.py','build_validation':REPO/'benchmarks/native-operations/run.py','build_recorder':REPO/'benchmarks/r-file-readers/record-builds.py','build_recorder_parent':REPO/'benchmarks/io-optimization/record-builds.py'}
need(set(paths)==set(before['controllers']),'controller set')
for k,p in paths.items():need(sha(p)==before['controllers'][k],'current controller '+k)
spec=importlib.util.spec_from_file_location('independent_long_float_build_records',paths['build_validation']);records=importlib.util.module_from_spec(spec);spec.loader.exec_module(records)
for role,path in BUILDS.items():
 saved=before['builds'][role];need(saved['receipt']['base_commit']==COMMITS[role] and saved['receipt']['variant']=='baseline','exact build source/receipt role')
 need((path/'source.patch').read_bytes()==b'' and records.inventory(path,'baseline')==saved,'current full source/installed/DLL inventory')
 need(saved['receipt']['toolchain']['R_runtime_sha256']==before['execution']['R_runtime_sha256'],'build and worker runtime identity')
launcher=Path(shutil.which('Rscript')).resolve(strict=True);info=subprocess.check_output([str(launcher),'--vanilla','-e','cat(R.home(), R.version.string, sep=intToUtf8(10L))'],text=True).splitlines()
need(before['execution']==dict(Rscript=str(launcher),Rscript_sha256=sha(launcher),R_runtime_sha256=sha(Path(info[0])/'bin/exec/R'),R_version=info[1]),'current R launcher/runtime')
report=dict(status='PASS',observations=len(rows),qualification_observations=len(qualified),summary_rows=len(summary),source_commits=COMMITS,summary=summary,cpu_interval_range=[min(float(r['cpu']) for r in rows),max(float(r['cpu']) for r in rows)],wall_interval_range=[min(float(r['wall']) for r in rows),max(float(r['wall']) for r in rows)],scope='Independent complete matrices/orders/states/native routes/oracle identities/missing-union counts/cache clearing, all CPU and wall statistics, whole completion artifact bindings and current source/installed/runtime/controller inventories. Public/kernel qualification is separately bound. No new throughput population is inferred.',auditor_sha256=sha(Path(__file__)),timing_completion_sha256=sha(P/'completion.json'),qualification_completion_sha256=sha(Q/'completion.json'))
out=P.parent/'screen-independent-audit.json';out.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps({k:report[k] for k in ('status','observations','qualification_observations','summary_rows')}))
