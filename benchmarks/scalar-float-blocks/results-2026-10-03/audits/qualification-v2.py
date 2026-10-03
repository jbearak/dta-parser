#!/usr/bin/env python3
"""Independent saved-artifact replay; no package tests or measurements."""
import csv,hashlib,importlib.util,itertools,json,subprocess
from pathlib import Path
ROOT=Path('<scalar-block-checkout>')
OUT=Path('<scalar-block-evidence>/qualification-v2')
HERE=Path(__file__).resolve().parent

def need(ok,message):
    if not ok: raise RuntimeError(message)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def load(path):return json.loads(path.read_text())
def rows(path):return list(csv.DictReader(path.open()))
pre=load(OUT/'provenance-before.json');post=load(OUT/'provenance-after.json');complete=load(OUT/'completion.json')
need(pre==post,'Provenance changed')
need(complete['phase']=='qualify' and complete['rounds']==1 and complete['observations']==120 and complete['exact_results'] is True and complete['provenance_unchanged'] is True,'Incomplete qualification')
for name,digest in complete['artifacts'].items():need(sha(OUT/name)==digest,'Changed artifact '+name)
paths={'controller':ROOT/'benchmarks/scalar-float-blocks/run.py','worker':ROOT/'benchmarks/scalar-float-blocks/worker.R','validation':ROOT/'benchmarks/scalar-float-blocks/core.py','protocol_tests':ROOT/'benchmarks/scalar-float-blocks/test-run.py','build_validation':ROOT/'benchmarks/native-operations/run.py','build_recorder':ROOT/'benchmarks/r-file-readers/record-builds.py','build_recorder_parent':ROOT/'benchmarks/io-optimization/record-builds.py'}
need({key:sha(path) for key,path in paths.items()}==pre['controllers'],'Current controllers changed')
spec=importlib.util.spec_from_file_location('records',paths['build_validation']);records=importlib.util.module_from_spec(spec);spec.loader.exec_module(records)
builds={'baseline':Path('<arithmetic-evidence>/integration-candidate'),'candidate':Path('<scalar-block-evidence>/candidate-v2')}
commits={'baseline':'dbcf75cbfe589b5ac2a78166d1e436faa7bbb896','candidate':'2e512880b15ea5ef8d56c65a4916af3ad71fb928'}
for role,build in builds.items():
 receipt=load(build/'build-receipt.json');actual=records.inventory(build,receipt['variant'])
 need(actual==pre['builds'][role] and receipt['base_commit']==commits[role] and (build/'source.patch').read_bytes()==b'','Current build differs '+role)
exe=pre['execution'];launcher=Path(exe['Rscript']);need(sha(launcher)==exe['Rscript_sha256'],'Launcher changed')
details=subprocess.check_output([str(launcher),'--vanilla','-e','cat(R.home(),"\\n",R.version.string,sep="")'],text=True).splitlines()
need(sha(Path(details[0])/'bin/exec/R')==exe['R_runtime_sha256'] and details[1]==exe['R_version'],'Actual worker runtime changed')
patterns=['none','sparse','random_half','clustered_half','prefix256','suffix256','all_tags'];ops=['add','subtract','multiply','divide'];counts=[0,1003,500000,500000,256,256,1000000]
expected=[]
for pi,pattern in enumerate(patterns):
 for oi,op in enumerate(ops):
  reps=['compact','typed_double']
  if pattern=='none':reps=list(itertools.permutations(['compact','typed_double','ordinary']))[oi%6]
  elif (1+pi+oi)%2==0:reps.reverse()
  for ri,rep in enumerate(reps):expected.append((pattern,op,rep,pi+1,oi+1,ri+1))
raw=rows(OUT/'raw.csv');rebuilt=[]
for role in ('baseline','candidate'):
 batch=rows(OUT/('01-'+role+'.csv'));need(len(batch)==60,'Wrong worker matrix')
 observed=[(r['pattern'],r['operation'],r['representation'],int(r['pattern_position']),int(r['operation_position']),int(r['position'])) for r in batch]
 need(observed==expected,'Worker order or cases differ')
 for row in batch:
  rep=row['representation'];ordinary=rep=='ordinary';count=counts[patterns.index(row['pattern'])]
  need(row['phase']=='qualify' and int(row['round'])==1 and int(row['rows'])==1000000 and int(row['threads'])==1,'Wrong shape')
  need(int(row['repetitions'])==1 and float(row['cpu'])==float(row['wall'])==0,'Qualification contains clocks')
  need(int(row['native_calls'])==int(row['qualification_calls'])==(0 if ordinary else 1),'Native route differs')
  need(int(row['input_missing'])==int(row['result_missing'])==count,'Missing count differs')
  need(row['result_storage']=={'compact':'float','typed_double':'double','ordinary':''}[rep],'Storage differs')
  for field in ('input_hash','rank_hash','result_hash','missing_hash','metadata_hash','result_metadata_hash'):need(len(row[field])==64 and set(row[field])<=set('0123456789abcdef'),'Bad hash')
  for field in ('compact','materialized','retained','chunks'):need(row[field+'_before']==row[field+'_after'],'Source state changed')
  need(row['compact_before']==str(rep=='compact').upper() and row['materialized_before']=='FALSE' and int(row['retained_before'])==int(row['chunks_before'])==0,'Unexpected source state')
 rebuilt.extend(dict(variant=role,**r) for r in batch)
need(raw==rebuilt,'Raw rows differ from workers')
a,b=rows(OUT/'01-baseline.csv'),rows(OUT/'01-candidate.csv');need(a==b,'Cross-build qualified rows differ')
for pattern in patterns:
 selected=[r for r in a if r['pattern']==pattern];need(len({(r['input_hash'],r['rank_hash']) for r in selected})==1,'Input values differ across representations')
for op in ops:
 selected=[r for r in a if r['pattern']=='none' and r['operation']==op and r['representation']!='compact'];need(len({(r['result_hash'],r['missing_hash']) for r in selected})==1,'Typed/bare no-missing results differ')
result={'status':'PASS','rows':120,'cases_per_build':60,'counts_independently_checked':dict(zip(patterns,counts)),'commits':commits,'current_full_build_inventories_verified':True,'actual_worker_runtime_rechecked':True,'controller_sha256':pre['controllers'],'input_sha256':{p.name:sha(p) for p in OUT.iterdir() if p.is_file()},'audit_script_sha256':sha(Path(__file__)),'scope':'Read-only saved qualification audit and current source/library/runtime identity replay; no measurements or fresh numerical operations. Binary64/float oracle, tag collapse, width-specific results and ordering were independently source-reviewed.'}
(HERE/'scalar-block-v2-qualification-audit.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
print('PASS120 rows; matrix/order, missing/native/storage/source checks, full build/runtime/controller bindings')
