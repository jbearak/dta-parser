#!/usr/bin/env python3
"""Independent replay of frozen reciprocal216 artifacts and current identities."""
import csv, hashlib, importlib.util, json, math, statistics, subprocess, sys
from collections import Counter
from decimal import Decimal
from pathlib import Path
E=Path('<work>'); O=E/'screen-v1'; Q=E/'qualification-v1'; C=E/'controller'
REPO=Path('<private-work>/dta-long-float-add-blocks')
BUILDS={'baseline':Path('<baseline-build>'),'candidate':E/'candidate'}
PINS={'baseline':'7003eba901671797ee91fffc97f08e28a1f7f515','candidate':'f219bf72bbc882cc4c090ded870470ab9c5e2099'}
STRATA=[(1024,'none'),(2048,'none'),(4096,'none'),(16384,'none'),(1000000,'none'),(1000000,'sparse'),(1000000,'prefix256'),(1000000,'random_half'),(1000000,'all_tags')]
REPS=['compact','typed_double']
def ok(x,m):
 if not x: raise RuntimeError(m)
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def obj(p): return json.loads(Path(p).read_text())
def csvs(p):
 with Path(p).open(newline='') as f:return list(csv.DictReader(f))
def num(s):
 d=Decimal(s);ok(d.is_finite() and d>=0 and d==d.to_integral_value(),'invalid integer');return int(d)
def key(r):return num(r['rows']),r['pattern'],r['representation']
H=['input_hash','rank_hash','result_hash','missing_hash','metadata_hash','result_metadata_hash','cleared_hash']
F=H+['mutation_checked','input_missing','zero_observed','result_missing','result_storage']+[s+'_before' for s in ['compact','materialized','retained','chunks']]
expected={(n,p,r) for n,p in STRATA for r in REPS}
records={}
for path,phase,rounds in [(Q,'qualify',1),(O,'measure',6)]:
 done=obj(path/'completion.json');before=obj(path/'provenance-before.json')
 ok(done['phase']==phase and done['observations']==36*rounds and done['rounds']==rounds and done['exact_results'] is True and done['provenance_unchanged'] is True,'completion')
 ok(before==obj(path/'provenance-after.json'),'before after')
 for name,digest in done['artifacts'].items():ok(sha(path/name)==digest,'artifact '+name)
 raw=csvs(path/'raw.csv');rebuilt=[]
 for rnd in range(1,rounds+1):
  for role in (['baseline','candidate'] if rnd%2 else ['candidate','baseline']):
   worker=csvs(path/f'{rnd:02}-{role}.csv')
   ok(Counter(key(r) for r in worker)==Counter({k:1 for k in expected}),'matrix')
   indices=list(range(9));indices=indices[(rnd-1)%9:]+indices[:(rnd-1)%9]
   if rnd%2==0:indices.reverse()
   order=[]
   for pos,i in enumerate(indices,1):
    reps=REPS if (rnd+i)%2 else REPS[::-1]
    order.extend((*STRATA[i],rep,pos,j) for j,rep in enumerate(reps,1))
   ok([(*key(r),num(r['pattern_position']),num(r['position'])) for r in worker]==order,'order')
   for r in worker:
    n,p,rep=key(r);calls=num(r['repetitions']);ok(calls>0 and (phase!='qualify' or calls==1),'repetitions')
    ok(r['phase']==phase and num(r['round'])==rnd and r['operation']=='reciprocal' and num(r['operation_position'])==1 and num(r['threads'])==1,'operation')
    ok(num(r['native_calls'])==(calls if n>=2048 else 0) and num(r['qualification_calls'])==int(n>=2048),'native')
    for metric in ['cpu','wall']:ok(math.isfinite(float(r[metric])) and (float(r[metric])>0 if phase=='measure' else float(r[metric])==0),'clock')
    missing={'none':0,'sparse':1003,'prefix256':256,'random_half':500000,'all_tags':1000000}[p]
    zeros=num(r['zero_observed']);grid=range(8847,n+1,10001)
    if p=='random_half':ok(zeros<=len(grid),'random zeros')
    else:ok(zeros==(0 if p=='all_tags' else sum(p!='sparse' or i<13 or (i-13)%997!=0 for i in grid)),'grid zeros')
    ok(num(r['input_missing'])==missing and num(r['result_missing'])==missing+zeros,'missing policy')
    ok(r['mutation_checked']=='TRUE' and r['result_storage']==('float' if rep=='compact' else 'double'),'result/cache')
    for s in ['compact','materialized','retained','chunks']:ok(r[s+'_before']==r[s+'_after'],'source state')
    ok(r['compact_before']==str(rep=='compact').upper() and r['materialized_before']=='FALSE' and num(r['retained_before'])==num(r['chunks_before'])==0,'layout')
    for h in H:ok(len(r[h])==64 and set(r[h])<=set('0123456789abcdef'),'hash shape')
   rebuilt.extend(dict(variant=role,**r) for r in worker)
 ok(raw==rebuilt,'raw worker identity')
 for k in expected:
  g=[r for r in raw if key(r)==k];ok(len({tuple(r[f] for f in F) for r in g})==1,'case stable')
  if phase=='measure':
   for role in PINS:ok(Counter(num(r['position']) for r in g if r['variant']==role)==Counter({1:3,2:3}),'positions')
 for n,p in STRATA:
  g=[r for r in raw if key(r)[:2]==(n,p)]
  ok(len({tuple(r[f] for f in ['input_hash','rank_hash','input_missing','zero_observed','missing_hash','result_missing']) for r in g})==1,'cross representation inputs/masks')
 records[phase]=raw
ok(obj(Q/'provenance-after.json')==obj(O/'provenance-before.json'),'qualification bindings')
qual={key(r):tuple(r[f] for f in F) for r in records['qualify']}
for r in records['measure']:ok(tuple(r[f] for f in F)==qual[key(r)],'timing qualification semantic match')
raw=records['measure'];computed=[]
for n,p in STRATA:
 s=dict(rows=n,pattern=p);groups={}
 for role in PINS:
  for rep in REPS:
   group=sorted([r for r in raw if r['variant']==role and key(r)==(n,p,rep)],key=lambda r:num(r['round']));groups[role,rep]=group
   for m in ['cpu','wall']:
    vals=[float(r[m])/num(r['repetitions']) for r in group]
    s[f'{role}_{rep}_{m}']=statistics.median(vals);s[f'{role}_{rep}_{m}_min']=min(vals);s[f'{role}_{rep}_{m}_max']=max(vals)
 for rep in REPS:
  for m in ['cpu','wall']:
   s[f'{rep}_{m}_speedup']=s[f'baseline_{rep}_{m}']/s[f'candidate_{rep}_{m}']
   s[f'{rep}_{m}_paired_speedup']=statistics.median((float(a[m])/num(a['repetitions']))/(float(b[m])/num(b['repetitions'])) for a,b in zip(groups['baseline',rep],groups['candidate',rep]))
 for role in PINS:s[f'{role}_compact_typed_cpu']=s[f'{role}_compact_cpu']/s[f'{role}_typed_double_cpu']
 computed.append(s)
actual=csvs(O/'summary.csv');ok(len(actual)==9,'summary length')
for a,b in zip(actual,computed):
 ok(set(a)==set(b),'summary fields')
 for k,v in b.items():ok(a[k]==v if isinstance(v,str) else math.isclose(float(a[k]),v,rel_tol=1e-12,abs_tol=1e-15),'summary '+k)
before=obj(O/'provenance-before.json')
paths={'controller':C/'run.py','worker':C/'worker.R','validation':C/'core.py','protocol_tests':C/'test-run.py','build_validation':REPO/'benchmarks/native-operations/run.py','build_recorder':REPO/'benchmarks/r-file-readers/record-builds.py','build_recorder_parent':REPO/'benchmarks/io-optimization/record-builds.py'}
ok({k:sha(p) for k,p in paths.items()}==before['controllers'],'current controllers')
spec=importlib.util.spec_from_file_location('verified_build_records',paths['build_validation']);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
for role,build in BUILDS.items():
 old=before['builds'][role];ok(old['receipt']['base_commit']==PINS[role] and old['receipt']['source_patch_sha256']==hashlib.sha256(b'').hexdigest(),'source pin')
 ok(module.inventory(build,old['receipt']['variant'])==old,'current full build '+role)
execution=before['execution'];launcher=Path(execution['Rscript']);details=subprocess.check_output([str(launcher),'--vanilla','-e','cat(R.home(),"\\n",R.version.string,sep="")'],text=True).splitlines()
ok(len(details)==2 and sha(launcher)==execution['Rscript_sha256'] and sha(Path(details[0])/'bin/exec/R')==execution['R_runtime_sha256'] and details[1]==execution['R_version'],'current worker runtime')
for role in PINS:ok(before['builds'][role]['receipt']['toolchain']['R_runtime_sha256']==execution['R_runtime_sha256'],'build runtime')
result={'status':'PASS','observations':len(raw),'summaries':len(computed),'qualification_observations':len(records['qualify']),'source_commits':PINS,'checks':['Complete worker/raw matrix and balanced execution order','All whole-result/source/metadata/storage/native/missing/cache records match across builds and qualification','Independent all summary extrema/medians/paired speedups/control ratios replay','Completion artifacts and qualification/timing before-after identities','Current controllers, complete source/installed/DLL build receipts and exact worker runtime'], 'scope':'Independent artifact replay plus current full build/runtime verification. Does not rerun R operations or prove hashes independently of the reviewed full worker oracle. Source class metadata and binary32/binary64 result hashes compare within representations; inputs/ranks/missing masks compare across representations. Compiler identity is build-time receipt evidence.', 'cpu_intervals_s':[min(float(r['cpu']) for r in raw),max(float(r['cpu']) for r in raw)],'wall_intervals_s':[min(float(r['wall']) for r in raw),max(float(r['wall']) for r in raw)],'summary':computed,'artifact_sha256':{str(p.relative_to(E)):sha(p) for d in [Q,O] for p in d.iterdir() if p.is_file()},'audit_sha256':sha(__file__)}
(E/'independent-audit.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');print(json.dumps({k:v for k,v in result.items() if k not in ['summary','artifact_sha256']},indent=2))
