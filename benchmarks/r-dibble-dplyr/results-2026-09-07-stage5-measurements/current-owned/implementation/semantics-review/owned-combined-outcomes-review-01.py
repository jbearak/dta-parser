from pathlib import Path
from datetime import datetime,timezone
import csv,json,hashlib,math,re,itertools
v=Path('/private/tmp/dta-direct-stage5-validation');root=v/'root-stage5-owned-performance-a2d8b6a';review=Path(__file__).parent
source='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9';f622='f622f1ddba04b2bb7ac07415faccf2b417aab0e6';ec10='ec10a6ac34602f3bd691e8043019c1b479babda4'
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=hashlib.sha256(q.read_bytes()).hexdigest())
def csvread(p):return list(csv.DictReader(p.open()))
def scalar(text,name):
 vals=re.findall(r'^'+re.escape(name)+r' ([-+0-9.eE]+)\s*$',text,re.M);assert len(vals)==1,name
 value=float(vals[0]);assert math.isfinite(value) and value.is_integer();return int(value)
def boolcsv(x):assert x in ['True','False'];return x=='True'
anchor=json.loads((review/'owned-combined-integrity-review-01.json').read_text());assert ident(root/'completed-receipt.json')==anchor['receipt']
for row in json.loads((root/'output-manifest.json').read_text())['products']:assert ident(row['path'])==row
sources={};outcomes={};memory_maps={}
for family in ['atomic','double']:
 for label in ['baseline','candidate']:
  folder=root/(family+'-'+label);manifest=json.loads((folder/'root-manifest.json').read_text());sources[(family,label)]=manifest
  filename='owned-'+family+'.csv';rows=csvread(folder/filename);keys=(['kind'] if family=='atomic' else [])+['family','operation','rows','columns'];key=lambda x:tuple(x[k] for k in keys)
  expected=set()
  kinds=['string','declared_character','logical','factor','ordered'] if family=='atomic' else ['double']
  reads_atomic=['any_na','nonmissing_count','coercion_character','export_data_frame','export_tibble','filter_half','row_subset','read_dta','write_dta','read_arrow','write_arrow']
  reads_double=['sum','mean','range','coercion_double','coercion_integer','export_data_frame','export_tibble','arithmetic','mutate_arithmetic','filter_half','row_subset','read_dta','write_dta','read_arrow','write_arrow']
  for kind in kinds:
   for n in ['100000','1000000']:
    for fam,op in itertools.product(['direct','safe_delegation'],['rename','select','relocate','pipeline_five']):expected.add(tuple(([kind] if family=='atomic' else [])+[fam,op,n,'16']))
    reads=reads_double if family=='double' else reads_atomic+(['byte_width'] if kind in ['string','declared_character'] else ['coercion_integer'])+(['sum','mean'] if kind=='logical' else ['range'] if kind=='ordered' else [])
    for op in reads:expected.add(tuple(([kind] if family=='atomic' else [])+['read',op,n,'8']))
  assert len(rows)==len(expected)==(206 if family=='atomic' else 46) and {key(x) for x in rows}==expected
  for x in rows:
   assert x['iterations']=='7' and float(x['median_ms'])>0 and float(x['gc_count'])>=0
   if label=='candidate' and x['family']=='direct' and x['operation']!='pipeline_five':
    assert float(x['r_allocated_bytes'])<1000000 and float(x['bench_allocated_bytes'])<1000000 and float(x['native_owned_capture_bytes'])==float(x['native_mutation_target_copy_bytes'])==0
    if family=='atomic' and x['kind'] in ['string','declared_character']:assert float(x['validation_scan_calls'])==float(x['validation_scanned_values'])==0
  after_name='owned-atomic-after-read.csv' if family=='atomic' else 'owned-after-read.csv';after=csvread(folder/after_name);assert len(after)==(126 if family=='atomic' else 30)
  if label=='candidate':
   for x in after:
    assert float(x['r_allocated_bytes'])<1000000 and float(x['native_owned_capture_bytes'])==float(x['native_mutation_target_copy_bytes'])==0
    if family=='atomic' and x['kind'] in ['string','declared_character']:assert float(x['validation_scan_calls'])==float(x['validation_scanned_values'])==0
  writes=csvread(folder/('owned-'+family+'-writes.csv'));assert len(writes)==(18 if family=='atomic' else 6)
  if label=='candidate':
   for x in writes:
    unit=4 if x.get('kind')=='logical' else 8;copy=int(x['rows'])*unit if x['operation']=='shared_sparse' else 0
    assert float(x['native_mutation_target_copy_bytes'])==copy
    if x['operation']=='full_replacement':assert float(x['native_old_journal_bytes'])==0
  log=(folder/'runner.log').read_text();assert ('All candidate atomic operation, value, metadata, alias, backing and scan checks passed.' if family=='atomic' and label=='candidate' else 'All '+label+' atomic operation, value, metadata, alias, backing and scan checks passed.' if family=='atomic' else 'All '+label+' owned-double checks passed.') in log
  outcomes[(family,label)]=dict(rows=rows,keys=keys,keyed={key(x):x for x in rows},after_read_rows=len(after),write_rows=len(writes))
  mem={}
  for case in manifest['memory_cases']:
   path=folder/case['file'];assert ident(path)['sha256']==case['sha256'] and case['exit_code']==0;text=path.read_text()
   assert re.findall(r'^source_sha (.*?)\s*$',text,re.M)==[manifest['source_sha']] and re.findall(r'^library (.*?)\s*$',text,re.M)==[manifest['library']] and re.findall(r'^mode (.*?)\s*$',text,re.M)==[label]
   rss=re.findall(r'^\s*(\d+)\s+maximum resident set size$',text,re.M);assert len(rss)==1
   metrics={k:scalar(text,k) for k in ['retained_with_source_vector_heap_bytes','excess_after_drop_result_bytes','released_with_last_result_bytes']}
   metrics['maximum_resident_set_size' if family=='atomic' else 'maximum_resident_set_size_bytes']=int(rss[0])
   assert metrics['excess_after_drop_result_bytes']==scalar(text,'vector_heap_bytes_after_drop_result')-scalar(text,'prefixture_vector_heap_bytes')
   assert metrics['released_with_last_result_bytes']==scalar(text,'vector_heap_bytes_after_drop_source')-scalar(text,'vector_heap_bytes_after_drop_result')
   if label=='candidate':assert metrics['retained_with_source_vector_heap_bytes']<1000000 and metrics['excess_after_drop_result_bytes']<1000000
   if family=='atomic':assert metrics==case['metrics']
   else:assert metrics['maximum_resident_set_size_bytes']==case['maximum_resident_set_size_bytes']
   k=tuple(([case['kind']] if family=='atomic' else [])+[case['operation'],str(case['rows'])]);assert k not in mem;mem[k]=metrics
  assert len(mem)==(30 if family=='atomic' else 6);memory_maps[(family,label)]=mem
comparison_reports=[]
for original in [False,True]:
 for family in ['atomic','double']:
  out=v/f'root-{family}-original-ec10-a2d8b6a-comparison-01' if original else root/(family+'-comparison');d=json.loads((out/'derivation.json').read_text());assert ident(v/('compare-'+family+'.py'))['sha256']==d['deriver_sha256']
  for k in ['baseline','candidate']:assert ident(d[k+'_manifest'])['sha256']==d[k+'_manifest_sha256']
  for name,h in d['files'].items():assert ident(out/name)['sha256']==h
  baseline_folder=Path(d['baseline_manifest']).parent;oldmanifest=json.loads(Path(d['baseline_manifest']).read_text());assert oldmanifest['source_sha']==(ec10 if original else f622)
  if family=='atomic':
   for name,h in oldmanifest['files'].items():assert ident(baseline_folder/name)['sha256']==h
  else:
   for name,entry in oldmanifest['outputs'].items():assert ident(baseline_folder/name)['sha256']==entry['sha256'] and len(csvread(baseline_folder/name))==entry['rows']
  for case in oldmanifest['memory_cases']:assert ident(baseline_folder/case['file'])['sha256']==case['sha256']
  new=outcomes[(family,'candidate')];keys=new['keys'];key=lambda x:tuple(x[k] for k in keys);old={key(x):x for x in csvread(baseline_folder/('owned-'+family+'.csv'))};assert old.keys()==new['keyed'].keys()
  comparisons=csvread(out/'operation-comparison.csv');flags=json.loads((out/'investigate.json').read_text());flagged=[]
  for x in comparisons:
   a=old[key(x)];z=new['keyed'][key(x)]
   for field in ['median_ms','r_allocated_bytes','r_largest_allocation_bytes','bench_allocated_bytes']:
    assert float(x['baseline_'+field])==float(a[field]) and float(x['candidate_'+field])==float(z[field])
   delta=float(z['median_ms'])-float(a['median_ms']);ratio=float(z['median_ms'])/float(a['median_ms']);assert math.isclose(float(x['median_delta_ms']),delta,rel_tol=1e-12,abs_tol=1e-12) and math.isclose(float(x['median_ratio']),ratio,rel_tol=1e-12)
   assert boolcsv(x['investigate'])==(delta>1 and ratio>1.1)
   if boolcsv(x['investigate']):flagged.append(x)
  assert len(comparisons)==len(old) and {key(x) for x in flagged}=={key(x) for x in flags}
  if not original:
   memrows=csvread(out/'memory-comparison.csv');mkeys=(['kind'] if family=='atomic' else [])+['operation','rows'];assert len(memrows)==len(memory_maps[(family,'baseline')])
   for x in memrows:
    k=tuple(x[t] for t in mkeys)
    for label in ['baseline','candidate']:
     for metric,value in memory_maps[(family,label)][k].items():assert int(float(x[label+'_'+metric]))==value
  comparison_reports.append(dict(family=family,baseline='original_ec10' if original else 'paired_f622',derivation=ident(out/'derivation.json'),pairs=len(comparisons),flags=flags,memory_comparison=ident(out/'memory-comparison.csv'),scope='Historical original ec10 medians are retained CSV summaries; no fresh-run equivalence or causal inference.' if original else 'Fresh paired f622/a2 exact runner; one host matrix.'))
assert [len(x['flags']) for x in comparison_reports]==[1,0,15,0]
heap_maps={};heap_rechecked=0
for label in ['baseline','candidate']:
 folder=root/('heap-'+label);manifest=json.loads((folder/'root-manifest.json').read_text());expected=set(itertools.product(['double','string','declared_character','logical','factor','ordered'],[100000,1000000],['rename','pipeline_five','pipeline_50']));observed={}
 for case in manifest['cases']:
  path=folder/case['file'];assert ident(path)['sha256']==case['sha256'] and case['exit_code']==0;text=path.read_text()
  for name,value in [('source_sha',manifest['source_sha']),('library',manifest['library']),('mode',label),('kind',case['kind']),('operation',case['operation']),('rows',str(case['rows']))]:assert re.findall(r'^heap_'+name+r' (.*?)\s*$',text,re.M)==[value]
  records=re.findall(r'^heap_checkpoint (\w+) header_cells (\d+) vector_bytes (\d+) header_reported_mb ([0-9.eE+]+)\s*$',text,re.M);assert [x[0] for x in records]==['prefixture','prior','after_result','after_drop_source','after_drop_result']
  points={name:dict(header_cells=int(n),vector_bytes=int(nv),header_reported_mb=float(mb)) for name,n,nv,mb in records}
  possible=[size for size in range(1,1025) if all(abs(math.ceil(10*p['header_cells']*size/1024**2)/10-p['header_reported_mb'])<1e-9 for p in points.values())];assert possible==[56] and scalar(text,'heap_header_bytes_per_cell')==56
  for p in points.values():p['tracked_heap_bytes']=p['header_cells']*56+p['vector_bytes']
  metrics={'header_bytes_per_cell':56}
  for metric,a,b,field in [('retained_header_cells','after_result','prior','header_cells'),('excess_header_cells_after_drop_result','after_drop_result','prefixture','header_cells'),('retained_tracked_heap_bytes','after_result','prior','tracked_heap_bytes'),('excess_tracked_heap_bytes_after_drop_result','after_drop_result','prefixture','tracked_heap_bytes'),('released_tracked_heap_bytes_with_last_result','after_drop_source','after_drop_result','tracked_heap_bytes')]:metrics[metric]=points[a][field]-points[b][field];assert metrics[metric]==scalar(text,'heap_'+metric)
  assert metrics==case['metrics'] and points==case['checkpoints']
  if label=='candidate':assert metrics['retained_tracked_heap_bytes']<1000000 and metrics['excess_tracked_heap_bytes_after_drop_result']<1000000
  key=(case['kind'],case['rows'],case['operation']);assert key not in observed;observed[key]=metrics;heap_rechecked+=1
 assert set(observed)==expected;heap_maps[label]=observed
heaprows=csvread(root/'heap-comparison/heap-comparison.csv');assert len(heaprows)==36
for x in heaprows:
 key=(x['kind'],int(x['rows']),x['operation'])
 for label in ['baseline','candidate']:
  for metric,value in heap_maps[label][key].items():assert int(x[label+'_'+metric])==value
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='owned_combined_outcomes_audited_flags_retained',reviewer_script=ident(__file__),outer_integrity_review=ident(review/'owned-combined-integrity-review-01.json'),current_receipt=ident(root/'completed-receipt.json'),matrices=[dict(family=f,label=l,operation_rows=len(x['rows']),after_read_rows=x['after_read_rows'],write_rows=x['write_rows']) for (f,l),x in outcomes.items()],comparisons=comparison_reports,vector_memory_logs=72,heap_logs=heap_rechecked,heap_pairs=36,assessment='Both exact fresh atomic206-row and double46-row matrices have complete expected grids, seven iterations, successful unchanged gates, candidate selector/after-read copy/scan budgets and18atomic+6double write-profile budgets. All252paired f622/a2 operations and252originalec10/a2 operations independently recalculate. Paired atomic retains one logical100k Arrow flag; originalec10 atomic retains15flags; both double comparisons have0. Fresh72vector-memory logs match recorded hashes/runtime/metrics and release/excess arithmetic; retained-vector deltas are recorded summaries. All72heap logs independently reconstruct all five checkpoints, infer56-byte header cells from roundedMB, and match36paired heap rows. Candidate vector and total tracked-heap retained/excess budgets remain below1MB.',limits=['Originalec10 records predate the fresh f622/a2 pair and represent a different storage implementation. Their15flags are retained diagnosis obligations, not attributed solely toStage5. Twelve base-R flags were repeated by separatev2 diagnostics; threefilter_half flags are outside that selected repeat.','Original matrix raw per-iteration timing samples and raw Rprofmem event files are not retained. Medians/allocations are source-bound CSV summaries; arithmetic can be reproduced, not their original raw sample medians. Atomic final write roundtrips are checked; inherited double read loop checks warm-up file roundtrips and source preservation, with no claim of independent final timed-file verification.','Prior/after-result vector-cell counters are not printed by vector-memory logs, so retained_with_source is a bound summary. Excess/released vector bytes are independently recomputed from printed counters. Separate heap logs do retain all five full checkpoints.','Memory accounting is specific: tracked R heap includes live header cells plus vector heap, excludes native external allocation/unused capacity; RSS is whole-process and includes startup, fixtures and validation. Native/Rprofmem allocation fields overlap and must not be added. Negative postrelease excess is retained honestly as GC difference.','Current f622Arrow flag is not erased by this audit. Separate repeated Arrow diagnosis may support its disposition; all original rows stay unchanged. No overall acceptance, irreducibility or exclusive internal-cause claim.','No workload, profiler, fixture or tests rerun. Read-only parsing/recalculation and artifact identity checks only.'])
with (review/'owned-combined-outcomes-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],fresh_operation_pairs=252,historical_operation_pairs=252,vector_memory_logs=72,heap_logs=72,fresh_atomic_flags=1,historical_atomic_flags=15)))
