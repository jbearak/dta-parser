#!/usr/bin/env python3
"""Independent saved-artifact replay; no package tests or measurements."""
import csv,hashlib,importlib.util,itertools,json,subprocess,math,statistics
from pathlib import Path
ROOT=Path('<scalar-block-checkout>')
OUT=Path('<scalar-block-evidence>/screen-v1')
QUAL=OUT.parent/'qualification-v1'
HERE=Path(__file__).resolve().parent

def need(ok,message):
    if not ok: raise RuntimeError(message)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def load(path):return json.loads(path.read_text())
def rows(path):return list(csv.DictReader(path.open()))
pre=load(OUT/'provenance-before.json');post=load(OUT/'provenance-after.json');complete=load(OUT/'completion.json')
need(pre==post,'Provenance changed')
need(complete['phase']=='measure' and complete['rounds']==6 and complete['observations']==720 and complete['exact_results'] is True and complete['provenance_unchanged'] is True,'Incomplete qualification')
for name,digest in complete['artifacts'].items():need(sha(OUT/name)==digest,'Changed artifact '+name)
paths={'controller':ROOT/'benchmarks/scalar-float-blocks/run.py','worker':ROOT/'benchmarks/scalar-float-blocks/worker.R','validation':ROOT/'benchmarks/scalar-float-blocks/core.py','protocol_tests':ROOT/'benchmarks/scalar-float-blocks/test-run.py','build_validation':ROOT/'benchmarks/native-operations/run.py','build_recorder':ROOT/'benchmarks/r-file-readers/record-builds.py','build_recorder_parent':ROOT/'benchmarks/io-optimization/record-builds.py'}
need({key:sha(path) for key,path in paths.items()}==pre['controllers'],'Current controllers changed')
spec=importlib.util.spec_from_file_location('records',paths['build_validation']);records=importlib.util.module_from_spec(spec);spec.loader.exec_module(records)
builds={'baseline':Path('<arithmetic-evidence>/integration-candidate'),'candidate':Path('<scalar-block-evidence>/candidate-v1')}
commits={'baseline':'dbcf75cbfe589b5ac2a78166d1e436faa7bbb896','candidate':'9520f1105eb2556333642b9f591a6d3c9cf89bdc'}
for role,build in builds.items():
 receipt=load(build/'build-receipt.json');actual=records.inventory(build,receipt['variant'])
 need(actual==pre['builds'][role] and receipt['base_commit']==commits[role] and (build/'source.patch').read_bytes()==b'','Current build differs '+role)
exe=pre['execution'];launcher=Path(exe['Rscript']);need(sha(launcher)==exe['Rscript_sha256'],'Launcher changed')
details=subprocess.check_output([str(launcher),'--vanilla','-e','cat(R.home(),"\\n",R.version.string,sep="")'],text=True).splitlines()
need(sha(Path(details[0])/'bin/exec/R')==exe['R_runtime_sha256'] and details[1]==exe['R_version'],'Actual worker runtime changed')
patterns=['none','sparse','random_half','clustered_half','prefix256','suffix256','all_tags'];ops=['add','subtract','multiply','divide'];counts=[0,1003,500000,500000,256,256,1000000]
def expected_order(number):
 result=[]
 rotation=(number-1)%7;pattern_order=patterns[rotation:]+patterns[:rotation]
 if number%2==0:pattern_order=pattern_order[::-1]
 op_order=ops if number%2 else ops[::-1]
 for pi,pattern in enumerate(pattern_order):
  for oi,op in enumerate(op_order):
   reps=['compact','typed_double']
   if pattern=='none':reps=list(itertools.permutations(['compact','typed_double','ordinary']))[(number-1+ops.index(op))%6]
   elif (number+patterns.index(pattern)+ops.index(op))%2==0:reps.reverse()
   for ri,rep in enumerate(reps):result.append((pattern,op,rep,pi+1,oi+1,ri+1))
 return result
raw=rows(OUT/'raw.csv');rebuilt=[]
semantic=['input_hash','rank_hash','result_hash','missing_hash','metadata_hash','result_metadata_hash','input_missing','result_missing','result_storage','compact_before','materialized_before','retained_before','chunks_before']
qc=load(QUAL/'completion.json')
need(qc['phase']=='qualify' and qc['rounds']==1 and qc['observations']==120 and qc['exact_results'] is True and qc['provenance_unchanged'] is True,'Qualification incomplete')
for name,digest in qc['artifacts'].items():need(sha(QUAL/name)==digest,'Qualification artifact changed '+name)
qrows=rows(QUAL/'raw.csv');need(len(qrows)==120,'Wrong qualification row count')
qualified={(r['variant'],r['pattern'],r['operation'],r['representation']):r for r in qrows}
need(len(qualified)==120,'Repeated qualification cases')
need(load(QUAL/'provenance-before.json')==load(QUAL/'provenance-after.json')==pre,'Qualification identity differs')
for number in range(1,7):
 for role in (('baseline','candidate') if number%2 else ('candidate','baseline')):
  batch=rows(OUT/(f'{number:02}-'+role+'.csv'));need(len(batch)==60,'Wrong worker matrix')
  observed=[(r['pattern'],r['operation'],r['representation'],int(r['pattern_position']),int(r['operation_position']),int(r['position'])) for r in batch]
  need(observed==expected_order(number),'Worker order or cases differ')
  for row in batch:
   rep=row['representation'];ordinary=rep=='ordinary';count=counts[patterns.index(row['pattern'])];reps=int(row['repetitions'])
   need(row['phase']=='measure' and int(row['round'])==number and int(row['rows'])==1000000 and int(row['threads'])==1,'Wrong shape')
   need(reps>0 and all(math.isfinite(float(row[k])) and float(row[k])>0 for k in ('cpu','wall')),'Invalid timing interval')
   need(int(row['native_calls'])==(0 if ordinary else reps) and int(row['qualification_calls'])==(0 if ordinary else 1),'Native route differs')
   need(int(row['input_missing'])==int(row['result_missing'])==count,'Missing count differs')
   need(row['result_storage']=={'compact':'float','typed_double':'double','ordinary':''}[rep],'Storage differs')
   for field in ('input_hash','rank_hash','result_hash','missing_hash','metadata_hash','result_metadata_hash'):need(len(row[field])==64 and set(row[field])<=set('0123456789abcdef'),'Bad hash')
   for field in ('compact','materialized','retained','chunks'):need(row[field+'_before']==row[field+'_after'],'Source state changed')
   need(row['compact_before']==str(rep=='compact').upper() and row['materialized_before']=='FALSE' and int(row['retained_before'])==int(row['chunks_before'])==0,'Unexpected source state')
   q=qualified[role,row['pattern'],row['operation'],rep]
   need(all(row[k]==q[k] for k in semantic),'Result/source differs from untimed qualification')
  rebuilt.extend(dict(variant=role,**r) for r in batch)
need(raw==rebuilt and len(raw)==720,'Raw rows differ from workers')
for pattern in patterns:
 selected=[r for r in raw if r['pattern']==pattern]
 need(len({(r['input_hash'],r['rank_hash'],r['input_missing']) for r in selected})==1,'Equivalent input values differ')
for op in ops:
 selected=[r for r in raw if r['pattern']=='none' and r['operation']==op and r['representation']!='compact']
 need(len({(r['result_hash'],r['missing_hash']) for r in selected})==1,'Typed/bare no-missing outputs differ')
# Recompute every summary field, including median of paired per-call ratios.
expected=[]
for pattern,op in itertools.product(patterns,ops):
 result={'pattern':pattern,'operation':op};reps=['compact','typed_double']+(['ordinary'] if pattern=='none' else [])
 groups={}
 for role,rep in itertools.product(('baseline','candidate'),reps):
  group=sorted([r for r in raw if (r['variant'],r['pattern'],r['operation'],r['representation'])==(role,pattern,op,rep)],key=lambda r:int(r['round']))
  need([int(r['round']) for r in group]==list(range(1,7)),'Paired rounds differ')
  need(sorted(int(r['position']) for r in group)==sorted(list(range(1,len(reps)+1))*(6//len(reps))),'Representation order is unbalanced')
  groups[role,rep]=group
  for metric in ('cpu','wall'):result[f'{role}_{rep}_{metric}']=statistics.median(float(r[metric])/int(r['repetitions']) for r in group)
 for rep,metric in itertools.product(reps,('cpu','wall')):
  result[f'{rep}_{metric}_speedup']=result[f'baseline_{rep}_{metric}']/result[f'candidate_{rep}_{metric}']
  result[f'{rep}_{metric}_paired_speedup']=statistics.median((float(b[metric])/int(b['repetitions']))/(float(c[metric])/int(c['repetitions'])) for b,c in zip(groups['baseline',rep],groups['candidate',rep]))
 for role in ('baseline','candidate'):
  result[f'{role}_compact_typed_cpu']=result[f'{role}_compact_cpu']/result[f'{role}_typed_double_cpu']
  if pattern=='none':result[f'{role}_compact_ordinary_cpu']=result[f'{role}_compact_cpu']/result[f'{role}_ordinary_cpu']
 expected.append(result)
summary=rows(OUT/'summary.csv');need(len(summary)==len(expected)==28,'Summary matrix differs')
for actual,wanted in zip(summary,expected):
 need(actual['pattern']==wanted['pattern'] and actual['operation']==wanted['operation'],'Summary order differs')
 need({k for k,v in actual.items() if v!=''}==set(wanted),'Summary fields differ')
 for key,value in wanted.items():
  if isinstance(value,float):need(math.isclose(float(actual[key]),value,rel_tol=1e-12,abs_tol=1e-15),'Summary value differs: '+key)
result={'status':'PASS','rows':720,'summary_rows':28,'cases_per_build_round':60,'cpu_intervals':[min(float(r['cpu']) for r in raw),max(float(r['cpu']) for r in raw)],'wall_intervals':[min(float(r['wall']) for r in raw),max(float(r['wall']) for r in raw)],'counts_independently_checked':dict(zip(patterns,counts)),'commits':commits,'current_full_build_inventories_verified':True,'actual_worker_runtime_rechecked':True,'controller_sha256':pre['controllers'],'input_sha256':{p.name:sha(p) for p in OUT.iterdir() if p.is_file()},'audit_script_sha256':sha(Path(__file__)),'scope':'Read-only saved measurement audit and current source/library/runtime identity replay; no measurements or fresh numerical operations. Binary64/float oracle, tag collapse, width-specific results and ordering were independently source-reviewed.'}
(HERE/'scalar-block-screen-audit.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
print('PASS720 rows/28 summaries; all orders, qualified semantics, ratios and full build/runtime/controller bindings')
