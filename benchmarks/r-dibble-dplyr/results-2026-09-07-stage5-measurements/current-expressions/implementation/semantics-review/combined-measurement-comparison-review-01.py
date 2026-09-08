import collections,csv,hashlib,json,math,subprocess
from datetime import datetime,timezone
from pathlib import Path
root=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance')
review=Path('/private/tmp/dta-direct-stage5-validation/implementation/semantics-review')
name='candidate-a2d8b6a-measure-01';run=root/name

def identity(path):
 resolved=path.resolve(strict=True);s=resolved.stat();h=hashlib.sha256()
 with resolved.open('rb') as f:
  for block in iter(lambda:f.read(8*1024*1024),b''):h.update(block)
 return dict(path=str(path),resolved=str(resolved),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
def audit_products(name):
 folder=root/name;receipt=root/(name+'-receipt.json');receipt_before=identity(receipt);r=json.loads(receipt.read_text());m=json.loads((folder/'manifest.json').read_text())
 assert r['accepted'] and r['manifest']==identity(folder/'manifest.json')
 for row in m['products']:assert identity(Path(row['path']))==row,row['path']
 assert {row['path'] for row in m['products']}|{str(folder/'manifest.json')}=={str(p) for p in folder.iterdir()}
 assert identity(receipt)==receipt_before
 return dict(receipt=receipt_before,manifest=identity(folder/'manifest.json'),products=len(m['products']),bytes=sum(row['bytes'] for row in m['products']))
measurement=audit_products(name);audit=audit_products(name+'-audit-01')
assert measurement['receipt']['sha256']=='57d80de9edcf11505a6035bea8f2d32bdebfc23b87ade47a1210ea5b8de36d23'
assert audit['receipt']['sha256']=='01b04cb204cde1f82e4db471d2ffa14a88dbd37381db7c79018691991833d76e'
before=json.loads((run/'inputs-before.json').read_text());audit_before=json.loads((root/(name+'-audit-01')/'inputs.json').read_text())
for obj in [before,audit_before]:
 for row in obj['inputs']:assert identity(Path(row['path']))==row,row['path']
measurement['input_bindings_verified']=len(before['inputs']);audit['input_bindings_verified']=len(audit_before['inputs'])
assert before['source']=='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
inputs={row['path']:row for row in before['inputs']}
for file in ['measure-v4.R','measure-v4.py','cases-v10.R']:assert str(root/file) in inputs
bound={row['resolved'] for row in before['inputs']}
for row in csv.DictReader((run/'namespaces.tsv').open(),delimiter='\t'):
 assert str((Path(row['path'])/'DESCRIPTION').resolve(strict=True)) in bound
library=Path('/private/tmp/dta-direct-stage5-validation/implementation/candidate-combined-01/library/dtatools')
packages=['dplyr','cli','generics','glue','lifecycle','magrittr','pillar','R6','rlang','tibble','tidyselect','vctrs','utf8','pkgconfig','withr','data.table','bench','profmem']
for tree in [Path('/opt/homebrew/Cellar/r/4.6.1/lib/R'),library,*[Path('/opt/homebrew/lib/R/4.6/site-library')/p for p in packages]]:
 assert {str(p) for p in tree.rglob('*') if p.is_file()} == {p for p in inputs if p.startswith(str(tree)+'/')}
for helper in ['helpers.R','owned-double-helpers.R']:
 p=Path('/private/tmp/dta-direct-stage4/benchmarks/r-dibble-dplyr')/helper
 assert p.read_bytes()==subprocess.check_output(['git','show',before['source']+':benchmarks/r-dibble-dplyr/'+helper],cwd='/private/tmp/dta-direct-stage4')
execution=json.loads((run/'execution-result.json').read_text());audit_result=json.loads((root/(name+'-audit-01')/'result.json').read_text())
assert execution['returncode']==audit_result['returncode']==0 and not execution['changed_inputs'] and not audit_result['changed_inputs'] and execution['namespace_coverage'] and execution['integrity_error'] is None and audit_result['error'] is None
lines=(run/'execution.log').read_text().splitlines();assert len(lines)==100 and sum(s.startswith('RUN ') for s in lines)==sum(s.startswith('MEASURED ') for s in lines)==50
assert not any('warning' in s.lower() or 'error' in s.lower() for s in lines)
readcsv=lambda p:list(csv.DictReader(p.open()))
grid=readcsv(run/'grid.csv');rows=readcsv(run/'measurements.csv');states=readcsv(run/'source-states.csv');rawrows=readcsv(review/'combined-measurement-raw-review-01.csv')
keys=['rows','columns','groups','kind','operation'];key=lambda row:tuple(row[k] for k in keys)
expected={(*key(g),m) for g in grid for m in ['safe_reference','direct']}
assert len(grid)==25 and len(rows)==50 and {(*key(r),r['mode']) for r in rows}==expected
for row in rows:
 assert int(row['actual_input_columns'])==int(row['columns'])+(row['kind'] in ['grouped','by'])
 assert int(row['iterations'])==7 and int(row['gc_count'])>=0
 for field,value in row.items():
  if field.endswith('_bytes') or field=='median_ms':
   value=float(value);assert math.isfinite(value) and value>=0
   if field.endswith('_bytes'):assert value==int(value)
 assert float(row['r_largest_allocation_bytes'])<=float(row['r_allocated_bytes'])
expected_states=set()
for g in grid:
 columns=['x','s']+[f'p{i}' for i in range(3,int(g['columns'])+1)]+(['g'] if g['kind'] in ['grouped','by'] else [])
 for m in ['safe_reference','direct']:
  for phase in ['before_oracle','before_profile','before_timing','after_timing']:
   for col in columns:expected_states.add((*key(g),m,phase,col))
assert len(states)==len(expected_states)==3456
assert {(*key(r),r['mode'],r['phase'],r['column']) for r in states}==expected_states
backing={}
for row in states:
 assert row['owned']=='TRUE' and row['exposed']=='FALSE' and row['depth']=='1' and float(row['bytes'])==int(row['rows'])*8
 assert row['type']==('character' if row['column']=='s' else 'double')
 assert row['handle_shared']=='TRUE' and row['backing_private']=='FALSE'
 k=(*key(row),row['mode'],row['column']);backing.setdefault(k,set()).add(row['backing'])
assert all(len(values)==1 for values in backing.values())
assert len(rawrows)==350 and len({(r['case'],r['mode']) for r in rawrows})==50
for row in rawrows:assert float(row['seconds'])>0
raw_command=['/opt/homebrew/Cellar/r/4.6.1/bin/Rscript','--vanilla',str(review/'baseline-measure02-raw-review-01.R'),str(run),str(review/'combined-measurement-raw-review-01.csv')]
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='clear_for_combined_expression_measurement_records',measurement=measurement,root_audit=audit,source=before['source'],matrix=dict(cases=25,modes=['safe_reference','direct'],measurement_rows=50,raw_series=50,raw_samples=350,iterations=7,gc_filter=False),state=dict(rows=3456,phases=4,coverage='Every fixture column in both modes at every required phase; owned TRUE, depth 1, unexposed, expected backing bytes; same backing address before and after. All observed handles shared and backing_private FALSE.'),independent_raw_check=dict(command=raw_command,exit_code=0,products=[identity(review/file) for file in ['baseline-measure02-raw-review-01.R','combined-measurement-raw-review-01.csv','combined-measurement-raw-review-01.log']],scope='Reads RDS records only, no fixture construction or measured operations. Fourth sorted value of each seven-sample series times 1000 equals the plain numeric RDS median and CSV median; allocation and GC fields equal.'),reviewed_sources=[identity(root/p) for p in ['measure-v4.R','measure-v4.py','cases-v10.R','audit-measurement.R','audit-measurement.py']],source_findings=[],source_assessment='Fixture creation, independent value/metadata/capture checks, safe-reference full snapshot parity, GC and owned-state inspection occur outside timed operation. Capture sink resets each call. v4 uses explicit millisecond summary with raw seconds cross-check, saves all series, replicates state metadata rows explicitly, and turns unexpected warnings into errors. Profile output checked separately; post-timing source values and backing state checked. Root audit authenticates original products and recalculates 50 raw series; independent review additionally verifies full state matrix and current declared input tree inventories.',limits=['Combined candidate a2d8b6a only; this verifies its completed measurement records and does not accept the pending performance comparison or overall Stage 5 performance.','25 deterministic cases, two modes, seven measured iterations each on one externally coordinated host run; timings are not confidence intervals or cross-platform/minimum-R measurements.','Safe reference uses the installed expression typing and safe closure, omitting the redundant old second retyping pass only for the explicitly checked corpus. Grouped/rowwise fixtures omit dataset labels; preservation correction has separate behavior evidence.','Fixture values and result metadata checks ran before timing and around a separate profile operation. Timed outputs are not all retained for post hoc value reconstruction. State inspection itself yields shared R handles, so these are shared-source read/evaluate costs, not exclusive/private write costs.','bench allocation is retained as a raw RDS summary and equals CSV. Rprofmem and native counters are separate profile-run summaries; temporary Rprofmem event logs were deleted by the unchanged helper, so their event totals cannot be independently reconstructed. Rprofmem, bench and native allocation counters overlap and must not be added. None is retained memory or process RSS.','Audit programs use an idle-file snapshot contract and a separate receipt, not an external authenticity anchor or concurrent mutation monitor. Python/OS/Homebrew external library closures remain unfrozen.','Rejected baseline01 and unused unit-error drafts remain historical, excluded from this acceptance.'])
# Independently compare the exact common historical input set, including Python.
baseline_root=root/'baseline-f622-measure-02'
baseline_inputs=json.loads((baseline_root/'inputs-before.json').read_text())
def package_dir(folder):
 paths=[r['path'] for r in csv.DictReader((folder/'namespaces.tsv').open(),delimiter='\t') if r['package']=='dtatools']
 assert len(paths)==1;return paths[0]
def common(obj,package):return {r['path']:r for r in obj['inputs'] if not r['path'].startswith(package+'/')}
baseline_common=common(baseline_inputs,package_dir(baseline_root));candidate_common=common(before,package_dir(run))
assert baseline_common==candidate_common and len(candidate_common)==3347
assert before['command']==baseline_inputs['command'] and (baseline_root/'grid.csv').read_bytes()==(run/'grid.csv').read_bytes()
old=json.loads((review/'candidate-measure01-review-03.json').read_text())
for row in old['reviewed_sources']:assert identity(Path(row['path']))==row
comparison=root/'expression-comparison-a2d8b6a-01'
comparison_receipt=identity(comparison/'completed-receipt.json');cr=json.loads((comparison/'completed-receipt.json').read_text());cm=json.loads((comparison/'manifest.json').read_text());ci=json.loads((comparison/'inputs.json').read_text());ce=json.loads((comparison/'result.json').read_text());assessment=json.loads((comparison/'assessment.json').read_text())
assert cr['status']==ce['status']=='complete' and not cr['changed_inputs'] and not ce['changed_inputs'] and ce['failure'] is None
assert cr['manifest']==identity(comparison/'manifest.json')
for row in cm['products']:assert identity(Path(row['path']))==row
assert {r['path'] for r in cm['products']}=={str(p) for p in comparison.iterdir()}-{str(comparison/'manifest.json'),str(comparison/'completed-receipt.json')}
for row in ci['inputs']:assert identity(Path(row['path']))==row
for path,paths in ci['inventories'].items():assert set(paths)=={str(p) for p in Path(path).iterdir()}
assert ci['candidate_source']==before['source'] and ci['baseline_source']==baseline_inputs['source']
assert identity(root/'compare-measurements-v4.py')['sha256']=='599d07b4abcb6b803dc37b9e70267abcf4a71aacd809eaca9b1a2bb1e0d9fb3c'
comparisons=readcsv(comparison/'comparisons.csv');assert len(comparisons)==100
baseline_rows=readcsv(baseline_root/'measurements.csv');baseline_map={(*key(r),r['mode']):r for r in baseline_rows};candidate_map={(*key(r),r['mode']):r for r in rows}
pairings={'candidate_direct_vs_baseline_direct':(baseline_map,'direct',candidate_map,'direct'),'candidate_direct_vs_candidate_reference':(candidate_map,'safe_reference',candidate_map,'direct'),'candidate_reference_vs_baseline_reference':(baseline_map,'safe_reference',candidate_map,'safe_reference'),'baseline_direct_vs_baseline_reference':(baseline_map,'safe_reference',baseline_map,'direct')}
assert {(*key(r),r['comparison']) for r in comparisons}=={(*key(g),pair) for g in grid for pair in pairings}
close=lambda x,y:math.isclose(float(x),float(y),rel_tol=1e-12,abs_tol=1e-12)
flags=[]
for row in comparisons:
 a,amode,z,zmode=pairings[row['comparison']];a=a[(*key(row),amode)];z=z[(*key(row),zmode)];x=float(a['median_ms']);y=float(z['median_ms'])
 assert close(row['reference_ms'],x) and close(row['measured_ms'],y) and close(row['delta_ms'],y-x) and close(row['time_ratio'],y/x)
 flagged=y/x>1.1 and y-x>1;assert row['investigate_time_regression']==str(flagged)
 if flagged:flags.append({k:row[k] for k in keys+['comparison','reference_ms','measured_ms','delta_ms','time_ratio']})
 for field in [x for x in a if x.endswith('_bytes')]:
  assert close(row['reference_'+field],a[field]) and close(row['measured_'+field],z[field]) and close(row['delta_'+field],float(z[field])-float(a[field]))
assert len(flags)==1 and flags[0]['comparison']=='candidate_reference_vs_baseline_reference' and flags[0]['operation']=='pipeline_five' and flags[0]['rows']=='1000000' and flags[0]['columns']=='16' and flags[0]['kind']=='ungrouped'
assert assessment['status']=='requires_assessment' and assessment['comparisons']==100 and len(assessment['flags'])==1
for k,v in assessment['flags'][0].items():assert close(flags[0][k],v) if isinstance(v,(int,float)) else flags[0][k]==v
result['pair_preparation']=dict(exact_common_bindings_including_python=len(candidate_common),same_r_command=True,same_grid_bytes=True,python=ci['orchestration_launchers'],scope='Exact common driver/corpus/helper/R/dependency/Python bindings match; only the recorded installed dtatools directories differ. Historical different-launcher exception is not used.')
result['comparison']=dict(receipt=comparison_receipt,manifest=identity(comparison/'manifest.json'),products=len(cm['products']),inputs=len(ci['inputs']),inventories=len(ci['inventories']),source=identity(root/'compare-measurements-v4.py'),independently_recalculated_rows=len(comparisons),pairings=list(pairings),candidate_direct_flags=0,flags=flags,assessment='All 100 timing and allocation differences/ratios and strict >10% plus >1 ms flags independently match bound measurement CSVs. No candidate-direct flag in this one matrix run. The one safe-reference pipeline flag remains requires_assessment; it is not a proved repeatable regression or waived result.')
result['reviewer_script']=identity(Path(__file__))
result['reviewer_attempt_history']='Uses previously qualified read-only raw RDS reader; no measurement, fixture creation, profiling or tests rerun.'
result['limits'][0]='Combined a2d8b6a records and their one full-matrix comparison only; the one safe-reference pipeline diagnosis flag still requires assessment. These records do not replace pending owned-operation/write-cost/retained-memory/RSS evidence or overall Stage5 acceptance.'
out=review/'combined-measurement-comparison-review-01.json'
with out.open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],measurement_products=measurement['products'],measurement_inputs=measurement['input_bindings_verified'],root_audit_products=audit['products'],root_audit_inputs=audit['input_bindings_verified'],state_rows=len(states),series=50,samples=350,comparisons=100,candidate_direct_flags=0,reference_flags=1)))
