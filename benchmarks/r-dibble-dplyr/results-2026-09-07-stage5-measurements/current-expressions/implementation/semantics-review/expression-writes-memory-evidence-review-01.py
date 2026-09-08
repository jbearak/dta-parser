from pathlib import Path
from datetime import datetime,timezone
import json,csv,hashlib,math,itertools,re,statistics
root=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance');review=Path(__file__).parent
sources={'baseline-f622':'f622f1ddba04b2bb7ac07415faccf2b417aab0e6','candidate-a2d8b6a':'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'}
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
def csvread(p):return list(csv.DictReader(p.open()))
def audit(name):
 p=root/name;rid=ident(root/(name+'-receipt.json'));r=json.loads(Path(rid['path']).read_text());m=json.loads((p/'manifest.json').read_text());b=json.loads((p/'inputs-before.json').read_text());e=json.loads((p/'execution-result.json').read_text())
 assert r['accepted'] and r['manifest']==ident(p/'manifest.json') and e['returncode']==0 and e['namespace_coverage'] and e['integrity_error'] is None and not e['changed_inputs']
 for x in m['products']:assert ident(x['path'])==x
 assert {x['path'] for x in m['products']}|{str(p/'manifest.json')}=={str(x) for x in p.iterdir()}
 for x in b['inputs']:assert ident(x['path'])==x
 ns=list(csv.DictReader((p/'namespaces.tsv').open(),delimiter='\t'));bindings={x['path']:x for x in b['inputs']};bound={x['resolved'] for x in b['inputs']}
 assert len(bindings)==len(b['inputs'])
 for x in ns:assert str((Path(x['path'])/'DESCRIPTION').resolve(strict=True)) in bound
 package=[x['path'] for x in ns if x['name']=='dtatools'];assert len(package)==1;package=package[0]
 for tree in [Path(package),Path('/opt/homebrew/Cellar/r/4.6.1/lib/R')]:assert {str(x) for x in tree.rglob('*') if x.is_file()}=={x for x in bindings if x.startswith(str(tree)+'/')}
 assert ident(Path(rid['path']))==rid
 return dict(name=name,receipt=rid,manifest=ident(p/'manifest.json'),products=len(m['products']),inputs=len(b['inputs'])),b,{k:v for k,v in bindings.items() if not k.startswith(package+'/')}
cases=['retained_shared','computed_first','computed_shared','computed_private','full_replacement'];modes=['safe_reference','direct'];columns=['x','s']+[f'p{i}' for i in range(3,17)]+list('abcd')
write_runs=[];write_values={};write_common=None;write_states=0
for source in sources:
 name=source+'-write-measure-01';p=root/name;record,b,common=audit(name);write_runs.append(record);assert b['source']==sources[source] and b['case_set']=='write_measure'
 if write_common is None:write_common=common
 else:assert common==write_common
 measurements=csvread(p/'write-measurements.csv');samples=csvread(p/'write-samples.csv');states=csvread(p/'write-states.csv');assert len(measurements)==20 and len(samples)==140 and len(states)==6800
 key=lambda x:(int(x['rows']),x['mode'],x['case'])
 assert {key(x) for x in measurements}==set(itertools.product([100000,1000000],modes,cases))
 state_map={}
 for x in states:
  k=(*key(x),int(x['iteration']),x['phase'],x['column']);assert k not in state_map;state_map[k]=x
  assert x['column'] in columns and x['depth']=='1' and x['exposed']=='FALSE' and float(x['bytes'])==int(x['rows'])*(4 if x['column']=='d' else 8) and x['type']==('character' if x['column']=='s' else 'logical' if x['column']=='d' else 'double')
 expected=set()
 for mode,case in itertools.product(modes,cases):
  for n,stage,iteration in [(12,'qualify',0)]+[(n,stage,i) for n in [100000,1000000] for stage,iterations in [('profile',[0]),('timing',range(1,8))] for i in iterations]:
   for direction,column in itertools.product(['before','after'],columns):expected.add((n,mode,case,iteration,stage+'_'+direction,column))
   target='s' if case=='retained_shared' else 'a'
   for column in columns:
    before=state_map[(n,mode,case,iteration,stage+'_before',column)];after=state_map[(n,mode,case,iteration,stage+'_after',column)]
    if column!=target:assert before['backing']==after['backing']
    else:
     private=case=='computed_private';assert (before['handle_shared'],before['backing_private'])==(('FALSE','TRUE') if private else ('TRUE','FALSE'))
     assert after['handle_shared']=='FALSE' and after['backing_private']=='TRUE'
     assert (before['backing']==after['backing'])==private
 assert set(state_map)==expected
 for row in measurements:
  selected=[x for x in samples if key(x)==key(row)];assert len(selected)==7 and {int(x['iteration']) for x in selected}==set(range(1,8)) and row['iterations']=='7'
  values=[float(x['elapsed_ms']) for x in selected];assert all(math.isfinite(x) and x>0 for x in values)
  assert math.isclose(statistics.median(values),float(row['median_ms']),rel_tol=1e-12,abs_tol=1e-12)
  n,mode,case=key(row);target='s' if case=='retained_shared' else 'a';before=state_map[(n,mode,case,0,'profile_before',target)]
  expected_copy=0 if case in ['computed_private','full_replacement'] else float(before['bytes'])
  assert float(row['native_mutation_target_copy_bytes'])==expected_copy and float(row['native_old_journal_bytes'])==0
  for k,v in row.items():
   if k.endswith('_bytes'):assert math.isfinite(float(v)) and float(v)>=0 and float(v).is_integer()
  assert float(row['r_largest_allocation_bytes'])<=float(row['r_allocated_bytes'])
  write_values[(source,*key(row))]=row
 assert len((p/'execution.log').read_text().splitlines())==20 and all(x.startswith('MEASURED ') for x in (p/'execution.log').read_text().splitlines())
 write_states+=len(states)
write_comparisons=[]
for n,mode,case in itertools.product([100000,1000000],modes,cases):
 a=write_values[('baseline-f622',n,mode,case)];z=write_values[('candidate-a2d8b6a',n,mode,case)];x=float(a['median_ms']);y=float(z['median_ms']);ratio=y/x;delta=y-x
 write_comparisons.append(dict(rows=n,mode=mode,case=case,baseline_ms=x,candidate_ms=y,delta_ms=delta,ratio=ratio,flag=ratio>1.1 and delta>1,allocation_deltas={k:float(z[k])-float(a[k]) for k in a if k.endswith('_bytes')}))
mem_runs=[];mem_common=None;memory=[]
for source,size,mode in itertools.product(sources,['100k','1m'],['direct','safe']):
 name=f'{source}-memory-{size}-{mode}-01';p=root/name;record,b,common=audit(name);mem_runs.append(record);assert b['source']==sources[source] and b['case_set']=='memory'
 if mem_common is None:mem_common=common
 else:assert common==mem_common
 rows=csvread(p/'retained.csv');assert len(rows)==3 and [int(x['calls']) for x in rows]==[0,5,50];n=100000 if size=='100k' else 1000000
 for x in rows:
  assert int(x['rows'])==n and x['mode']==('safe_reference' if mode=='safe' else 'direct') and x['maximum_backing_depth']=='1'
  assert int(x['n_cells_used'])>0 and int(x['v_cells_used'])>0 and float(x['gc_used_megabytes_rounded'])>0
 log=(p/'execution.log').read_text();assert log.startswith('PASS fifty-call retained state and values\n')
 rss=re.findall(r'^\s*(\d+)\s+maximum resident set size$',log,re.M);footprint=re.findall(r'^\s*(\d+)\s+peak memory footprint$',log,re.M);assert len(rss)==len(footprint)==1
 delta_n=int(rows[2]['n_cells_used'])-int(rows[1]['n_cells_used']);delta_v=int(rows[2]['v_cells_used'])-int(rows[1]['v_cells_used'])
 memory.append(dict(source=source,rows=n,mode=mode,checkpoints=rows,post5_to50_ncells=delta_n,post5_to50_vcells=delta_v,post5_to50_heap_bytes_64bit=delta_n*56+delta_v*8,maximum_resident_set_size_bytes=int(rss[0]),peak_memory_footprint_bytes=int(footprint[0])))
reader=csvread(review/'expression-memory-retained-states-01.csv');assert len(reader)==768 and len({x['run'] for x in reader})==8
assert 'PASS eight processes, 48 checkpoint objects, 768' in (review/'expression-memory-record-reader-01.log').read_text()
# Bind unchanged sources to the earlier full preparation evidence.
prep=json.loads((review/'combined-performance-preparation-review-01.json').read_text())
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='expression_writes_and_memory_retained_evidence_clear',reviewer_script=ident(__file__),sources=[ident(root/n) for n in ['writes-v2.R','writes-v2.py','write-cases-v2.R','memory.R','memory.py','cases-v10.R']],write_runs=write_runs,write_counts=dict(series=40,samples=280,states=write_states),write_common_inputs=len(write_common),write_comparisons=write_comparisons,memory_runs=mem_runs,memory_common_inputs=len(mem_common),memory=memory,memory_reader=[ident(review/n) for n in ['expression-memory-record-reader-01.R','expression-memory-record-reader-01.log','expression-memory-retained-states-01.csv']],assessment='All two write runs and eight isolated expression-memory processes have authentic completed input/product chains and exact shared source/driver/runtime/Python bindings outside each installed package. Forty write medians recalculate from280 saved ms samples; 13600 full column states cover separate tiny setup, profile and seven fresh timed pairs for both sources. Shared targets detach, private computed targets keep backing, unwritten backing remains unchanged, and profiled target-copy/old-journal budgets recalculate. Eight memory processes retain three GC checkpoints and six state objects each; 768 states are unexposed depth one, original and unwritten backing stays fixed, and computed x is separate. R heap N/V-cell counts and rounded MB remain distinct from macOS whole-process maximum RSS and peak footprint.',limits=['Write timing samples are retained as already converted numeric ms, not raw bench_time objects. Their medians are independently reconstructed; conversion uses the unchanged bench::system_time real-seconds path. Per-timed-write native deltas and value/metadata oracle objects are checked during bound execution but are not separately saved; profiling summaries and before/after states are retained.','The computed_first case is observed shared in every retained prestate; no exclusive-state claim is inferred from its name. True computed_private is separately verified unshared/private. All setup, state inspections and postwrite value checks are outside each timed action.','Memory checkpoints labeled0,5,50 count public mutation calls: each pipeline wrapper invokes five mutations, with10wrappercalls in total. The first checkpoint includes startup/fixture and diagnostic objects. Post5-to50 growth includes retained state-report bookkeeping, not just package objects.','Derived heap bytes use56-byte Ncells and8-byte Vcells for this64-bit host and are labeled separately from R rounded GC MB. Maximum RSS and macOS peak footprint cover the entire one-shot process, including startup/fixtures/GC/checks; they are not operation-only peaks or cumulative allocation.','No full-source runtime snapshot, payload oracle replay or memory profiler event reconstruction is claimed. Rprofmem/native fields overlap. External OS/Homebrew/full Python closure remains excluded.','No workloads, fixtures, timings, writes, profiling or package tests rerun. This evidence review does not clear remaining owned-operation comparisons, historicalec10 flags, Arrow diagnosis or overall Stage5 acceptance.'])
with (review/'expression-writes-memory-evidence-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],write_series=40,write_samples=280,write_states=write_states,write_flags=sum(x['flag'] for x in write_comparisons),memory_processes=8,memory_states=768)))
