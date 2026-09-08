"""Pure synthetic comparison checks; no R or benchmark operations."""
import contextlib,csv,hashlib,importlib.util,io,json,shutil,sys,tempfile
from pathlib import Path
review=Path('/private/tmp/dta-direct-stage5-validation/implementation/semantics-review')
source=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance/compare-measurements-v4.py')
frozen=review/'compare-measurements-reviewed-04.py'
with frozen.open('xb') as f:f.write(source.read_bytes())
spec=importlib.util.spec_from_file_location('comparison_review',frozen);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
actual=source.parent/'baseline-f622-measure-02'
grid=list(csv.DictReader((actual/'grid.csv').open()))
fields=list(next(csv.DictReader((actual/'measurements.csv').open())))
results=[]
def jsonwrite(p,v):p.write_text(json.dumps(v,indent=2)+'\n')
def csvwrite(p,rows):
 with p.open('w',newline='') as f:w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
def complete(root,name,extra=None):
 folder=root/name;products=[module.identity(p) for p in sorted(folder.iterdir()) if p.name!='manifest.json']
 jsonwrite(folder/'manifest.json',dict(products=products,excluded_self='manifest.json'))
 jsonwrite(root/(name+'-receipt.json'),dict(accepted=True,manifest=module.identity(folder/'manifest.json'),**(extra or {})))
def measure(root,name,sha,helper,grid_override=None):
 folder=root/name;folder.mkdir();g=grid if grid_override is None else grid_override
 package=root/(name+'-library')/'dtatools';package.mkdir(parents=True);(package/'DESCRIPTION').write_text('Package: dtatools\n')
 common=[module.identity(p) for p in module.REQUIRED_COMMON]+[module.identity(root/'Rscript')]
 jsonwrite(folder/'inputs-before.json',dict(source=sha,case_set='measure',command=[str(root/'Rscript'),'--vanilla',str(root/'measure-v4.R')],inputs=common+[module.LAUNCHERS[sha],module.identity(package/'DESCRIPTION')]))
 (folder/'namespaces.tsv').write_text('name\tpath\ndtatools\t'+str(package)+'\n')
 csvwrite(folder/'grid.csv',g)
 rows=[]
 for i,item in enumerate(g):
  for mode in module.MODES:
   row={**item,'mode':mode,'actual_input_columns':str(int(item['columns'])+(item['kind'] in ['by','grouped'])),'median_ms':'10','iterations':'7','gc_count':'0'}
   for field in fields:
    if field.endswith('_bytes'):row[field]='100'
   if i==0 and name=='candidate' and mode=='direct':row['median_ms']='12.1'
   if i==1:row['median_ms']='22' if name=='candidate' and mode=='direct' else '20'
   if i==2:row['median_ms']='2' if name=='candidate' and mode=='direct' else '1'
   rows.append({field:row[field] for field in module.SCHEMA})
 csvwrite(folder/'measurements.csv',rows)
 complete(root,name,dict(returncode=0,changed_inputs=[],namespace_coverage=True,integrity_error=None))
def audit(root,name,run):
 folder=root/name;folder.mkdir()
 products=json.loads((root/run/'manifest.json').read_text())['products']
 jsonwrite(folder/'inputs.json',dict(inputs=products+[module.identity(root/run/'manifest.json'),module.identity(root/(run+'-receipt.json'))]))
 jsonwrite(folder/'result.json',dict(returncode=0,error=None,changed_inputs=[],measurements=50))
 (folder/'execution.log').write_text('SYNTHETIC: no raw sample execution\n')
 complete(root,name)
def execute(case,mutate=None,hook=False):
 with tempfile.TemporaryDirectory(prefix='comparator-review-',dir=review) as td:
  root=Path(td);module.ROOT=root
  module.REQUIRED_COMMON=[root/name for name in ['measure-v4.py','measure-v4.R','cases-v10.R','helpers.R','owned-double-helpers.R']]
  for path in [*module.REQUIRED_COMMON,root/'Rscript']:path.write_text('synthetic bound common input\n')
  helper=root/'cases-v10.R';helper.write_text('fixture version A\n')
  measure(root,'baseline',module.BASELINE,helper)
  if case=='different_corpus_rejected':helper.write_text('different fixture values, same grid\n')
  measure(root,'candidate',module.CANDIDATE,helper)
  audit(root,'baseline-audit','baseline');audit(root,'candidate-audit','candidate')
  if mutate:mutate(root)
  old_csv=module.write_csv
  if hook:
   def changing_csv(path,rows):
    old_csv(path,rows);(root/'baseline').rename(root/'baseline-moved')
   module.write_csv=changing_csv
  old_argv=sys.argv;sys.argv=[str(frozen),'baseline','baseline-audit','candidate','candidate-audit','output'];error=None
  try:
   with contextlib.redirect_stdout(io.StringIO()):module.main()
  except BaseException as exc:error=dict(type=type(exc).__name__,message=str(exc))
  finally:sys.argv=old_argv;module.write_csv=old_csv
  output=root/'output';summary=dict(case=case,error=error,completed_receipt_exists=(output/'completed-receipt.json').exists(),result_exists=(output/'result.json').exists())
  if (output/'completed-receipt.json').exists():summary['receipt']=json.loads((output/'completed-receipt.json').read_text())
  if (output/'assessment.json').exists():
   assessment=json.loads((output/'assessment.json').read_text());summary['comparison_rows']=assessment['comparisons'];summary['flags']=len(assessment['flags'])
   if case=='valid_pair_threshold_boundaries':
    assert assessment['comparisons']==100 and len(assessment['flags'])==2
    assert all(float(x['delta_ms'])>1 and float(x['time_ratio'])>1.1 for x in assessment['flags'])
  if case=='different_corpus_rejected':
   assert error and error['type']=='RuntimeError' and 'Different driver, corpus, helper or common runtime bindings' in error['message'] and not output.exists()
   summary['fixed']='Different bound cases-v10.R identities now rejected before output creation.'
  elif case=='missing_bound_directory_retains_failure_receipt':
   assert error and error['type']=='RuntimeError' and summary['completed_receipt_exists'] and summary['result_exists']
   assert summary['receipt']['status']=='failed' and any('inventory_error' in r for r in summary['receipt']['changed_inputs'])
   assert module.identity(output/'manifest.json')==summary['receipt']['manifest']
   for row in json.loads((output/'manifest.json').read_text())['products']:assert module.identity(Path(row['path']))==row
   summary['fixed']='Missing input directory records invalidation and retains authenticated failed result/manifest/receipt.'
  elif case=='valid_pair_threshold_boundaries':
   assert error is None
   assert json.loads((output/'inputs.json').read_text())['orchestration_launchers']==module.LAUNCHERS
   assert 'same pinned Python3.14.7 launcher' in json.loads((output/'assessment.json').read_text())['orchestration_difference']
  elif case in ['unexpected_launcher_identity_rejected','historical_different_launcher_rejected']:assert error and error['message']=='Unexpected orchestration Python binding' and not output.exists()
  else:assert error is not None and not output.exists()
  results.append(summary)
def rebind_candidate(root):
 complete(root,'candidate',dict(returncode=0,changed_inputs=[],namespace_coverage=True,integrity_error=None))
 shutil.rmtree(root/'candidate-audit');(root/'candidate-audit-receipt.json').unlink();audit(root,'candidate-audit','candidate')
def wrong_launcher(root):
 p=root/'candidate/inputs-before.json';d=json.loads(p.read_text());next(r for r in d['inputs'] if r['path']==module.LAUNCHERS[module.CANDIDATE]['path'])['sha256']='0'*64;jsonwrite(p,d);rebind_candidate(root)
def historical_launcher(root):
 p=root/'candidate/inputs-before.json';d=json.loads(p.read_text())
 row=next(r for r in d['inputs'] if r['path']==module.LAUNCHERS[module.CANDIDATE]['path'])
 row.update(path='/opt/homebrew/Cellar/python@3.14/3.14.7/Frameworks/Python.framework/Versions/3.14/bin/python3.14',resolved='/opt/homebrew/Cellar/python@3.14/3.14.7/Frameworks/Python.framework/Versions/3.14/bin/python3.14',bytes=34640,mode='0o755',sha256='87d4df53fd91304be5bac391fb204643c36b7df2023c04a0953bcbc7d4fdf634')
 jsonwrite(p,d);rebind_candidate(root)
def extra_launcher(root):
 p=root/'candidate/inputs-before.json';d=json.loads(p.read_text());d['inputs'].append(module.LAUNCHERS[module.BASELINE]);jsonwrite(p,d);rebind_candidate(root)
def metric_schema(root):
 p=root/'candidate/measurements.csv';rows=list(csv.DictReader(p.open()));rows=[{**r,'new_metric_bytes':'0'} for r in rows];csvwrite(p,rows);rebind_candidate(root)
def common_runtime(root):
 p=root/'candidate/inputs-before.json';d=json.loads(p.read_text());next(r for r in d['inputs'] if r['path']==str(root/'Rscript'))['sha256']='f'*64;jsonwrite(p,d);rebind_candidate(root)
def wrong_source(root):
 p=root/'candidate/inputs-before.json';d=json.loads(p.read_text());d['source']=module.BASELINE;jsonwrite(p,d);rebind_candidate(root)
def grid_mismatch(root):
 p=root/'candidate/grid.csv';g=list(csv.DictReader(p.open()));g.reverse();csvwrite(p,g);rebind_candidate(root)
def duplicate_mode(root):
 p=root/'candidate/measurements.csv';rows=list(csv.DictReader(p.open()));rows[0]=rows[1];csvwrite(p,rows);rebind_candidate(root)
def wrong_audit(root):
 shutil.rmtree(root/'candidate-audit');(root/'candidate-audit-receipt.json').unlink();audit(root,'candidate-audit','baseline')
assert module.LAUNCHERS[module.BASELINE]==module.LAUNCHERS[module.CANDIDATE]
execute('valid_pair_threshold_boundaries')
execute('different_corpus_rejected')
execute('changed_product_rejected',lambda root:(root/'candidate/measurements.csv').write_text('changed'))
execute('wrong_source_rejected',wrong_source)
execute('metric_schema_rejected',metric_schema)
execute('different_runtime_rejected',common_runtime)
execute('unexpected_launcher_identity_rejected',wrong_launcher)
execute('extra_launcher_not_exempted',extra_launcher)
execute('historical_different_launcher_rejected',historical_launcher)
execute('different_grid_order_rejected',grid_mismatch)
execute('duplicate_mode_rejected',duplicate_mode)
execute('audit_for_other_run_rejected',wrong_audit)
execute('missing_bound_directory_retains_failure_receipt',hook=True)
out=review/'comparator-synthetic-04.json'
jsonwrite(out,dict(scope='Thirteen synthetic Python cases only. Uses the exact v4 launcher constants as fake historical input records; does not execute either launcher; no R, source fixtures, or measured workload executed. Fake receipts are test fixtures, never qualification evidence.',reviewed_source=module.identity(frozen),original_source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),results=results))
print(json.dumps(dict(cases=len(results),fixed_findings=[x['case'] for x in results if 'fixed' in x],report=str(out))))
