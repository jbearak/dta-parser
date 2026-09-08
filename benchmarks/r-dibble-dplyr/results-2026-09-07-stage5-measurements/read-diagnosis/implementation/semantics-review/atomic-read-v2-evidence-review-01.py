from pathlib import Path
from datetime import datetime,timezone
import json,csv,hashlib,math,itertools,collections
root=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance');review=Path(__file__).parent;a2='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9';ec10='ec10a6ac34602f3bd691e8043019c1b479babda4';f622='f622f1ddba04b2bb7ac07415faccf2b417aab0e6'
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
def csvread(p):return list(csv.DictReader(p.open()))
assessment_file=root/'atomic-read-repeat-v2-root-assessment-01.json';assessment_id=ident(assessment_file);assessment=json.loads(assessment_file.read_text());runs=[];common=None;values={};historical=[]
def audit(name,accepted=True):
 p=root/name;rid=ident(root/(name+'-receipt.json'));r=json.loads(Path(rid['path']).read_text());m=json.loads((p/'manifest.json').read_text());b=json.loads((p/'inputs-before.json').read_text());e=json.loads((p/'execution-result.json').read_text())
 assert r['accepted']==accepted and r['manifest']==ident(p/'manifest.json') and not e['changed_inputs'] and not r['changed_inputs'] and e['integrity_error'] is None and e['returncode']==(0 if accepted else 1)
 for x in m['products']:assert ident(x['path'])==x
 assert {x['path'] for x in m['products']}|{str(p/'manifest.json')}=={str(x) for x in p.iterdir()}
 for x in b['inputs']:assert ident(x['path'])==x
 assert ident(Path(rid['path']))==rid
 return dict(name=name,receipt=rid,manifest=ident(p/'manifest.json'),products=len(m['products']),inputs=len(b['inputs']),accepted=accepted),b
selected={'declared_character':['any_na','nonmissing_count'],'logical':['nonmissing_count','coercion_character','coercion_integer','mean'],'factor':['any_na','nonmissing_count','coercion_character'],'ordered':['any_na','nonmissing_count','coercion_character']}
for name,entry in assessment['runs'].items():
 p=root/name;record,b=audit(name);runs.append(record);assert record['receipt']['sha256']==entry['receipt_sha256'] and record['manifest']==entry['manifest']
 assert b['runner_source']==a2 and b['source']==(a2 if name.startswith('candidate') else ec10 if name.startswith('baseline-ec10') else f622) and b['mode']==('candidate' if name.startswith('candidate') else 'baseline')
 assert b['command'][2]==str(root/'atomic-read-repeat-v2.R') and b['command'][4]==str(p) and b['command'][5:]==[b['source'],b['mode'],'7']
 ns=list(csv.DictReader((p/'namespaces.tsv').open(),delimiter='\t'));bindings={x['path']:x for x in b['inputs']};bound={x['resolved'] for x in b['inputs']}
 for x in ns:assert str((Path(x['path'])/'DESCRIPTION').resolve(strict=True)) in bound
 package=[x['path'] for x in ns if x['name']=='dtatools'];assert len(package)==1;package=package[0];assert str(Path(b['command'][3])/'dtatools')==package
 for tree in [Path(package),Path('/opt/homebrew/Cellar/r/4.6.1/lib/R'),Path('/opt/homebrew/lib/R/4.6/site-library')]:assert {str(x) for x in tree.rglob('*') if x.is_file()}=={x for x in bindings if x.startswith(str(tree)+'/')}
 c={k:v for k,v in bindings.items() if not k.startswith(package+'/')}
 if common is None:common=c
 else:assert c==common
 rows=csvread(p/'owned-atomic.csv');after=csvread(p/'owned-atomic-after-read.csv');assert len(rows)==len(after)
 case=b['case_set'];count={'reads_repeat':24,'reads_minimum':12,'arrow_repeat':1}[case];assert len(rows)==count
 expected={('logical','write_arrow',100000,8)} if case=='arrow_repeat' else {(kind,op,n,1 if case=='reads_minimum' else 8) for kind,ops in selected.items() for op in ops for n in ([1000000] if case=='reads_minimum' else [100000,1000000])}
 key=lambda x:(x['kind'],x['operation'],int(x['rows']),int(x['columns']))
 assert {key(x) for x in rows}==expected and len({key(x) for x in rows})==count
 for x in rows:
  assert x['family']=='read' and x['iterations']=='7' and int(float(x['gc_count']))>=0 and float(x['median_ms'])>0
  for k,v in x.items():
   if k.endswith('_bytes') and v!='NA':assert math.isfinite(float(v)) and float(v)>=0
  values[(name,*key(x))]=x
 if name.startswith('candidate'):
  for x in after:
   assert float(x['r_allocated_bytes'])<1000000 and float(x['native_owned_capture_bytes'])==float(x['native_mutation_target_copy_bytes'])==0
   if x['kind']=='declared_character':assert float(x['validation_scan_calls'])==float(x['validation_scanned_values'])==0
 text=(p/'execution.log').read_text();assert text.rstrip().endswith(f'PASS {count} {b["mode"]} {case} bounded read cases') and 'Warning' not in text and 'Execution halted' not in text
assert len(runs)==14
comparisons=[]
for x in assessment['comparisons']:
 case=x['case'];i=x['repeat'];prefix='baseline-f622' if case=='arrow-repeat' else 'baseline-ec10';baseline=f'{prefix}-{case}-v2-{i:02d}';candidate=f'candidate-a2d8b6a-{case}-v2-{i:02d}';key=(x['kind'],x['operation'],x['rows'],x['columns']);a=values[(baseline,*key)];z=values[(candidate,*key)];av=float(a['median_ms']);zv=float(z['median_ms']);delta=zv-av;ratio=zv/av
 for field,value in [('baseline_ms',av),('candidate_ms',zv),('delta_ms',delta),('ratio',ratio)]:assert math.isclose(x[field],value,rel_tol=1e-12,abs_tol=1e-12)
 assert x['flag']==(delta>1 and ratio>1.1);comparisons.append(x)
assert len(comparisons)==87
counts={}
for case in ['read-repeat','arrow-repeat','read-minimum']:
 for i in ([1] if case=='read-minimum' else [1,2,3]):
  group=[x for x in comparisons if x['case']==case and x['repeat']==i];flags=[x for x in group if x['flag']];counts[f'{case}-{i}']=dict(pairs=len(group),flags=len(flags),flagged_rows=sorted({x['rows'] for x in flags}))
for i in [1,2,3]:assert counts[f'read-repeat-{i}']==dict(pairs=24,flags=12,flagged_rows=[1000000])
reader=csvread(review/'atomic-read-v2-raw-records-02.csv');states=csvread(review/'atomic-read-v2-states-02.csv');assert len(reader)==1218 and len(states)==3672 and len({(x['run'],x['index']) for x in reader})==174
assert 'PASS 14 runs,174 series,1218 saved seconds samples,3672 stable saved state facts' in (review/'atomic-read-v2-record-reader-02.log').read_text()
preparation=json.loads((review/'atomic-read-setup-evidence-v2-review-01.json').read_text())
for x in preparation['v2_sources']:assert ident(x['path'])==x
for name in ['candidate-a2d8b6a-read-repeat-01','candidate-a2d8b6a-read-setup-cold-01']:
 rec,b=audit(name,False);historical.append(rec)
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='v2_atomic_read_arrow_repeat_evidence_clear_regressions_remain',reviewer_script=ident(__file__),sources=preparation['v2_sources'],runs=runs,exact_common_driver_runtime_python_inputs=len(common),series=174,samples=1218,saved_state_facts=3672,reader=[ident(review/n) for n in ['atomic-read-v2-record-reader-02.R','atomic-read-v2-record-reader-02.log','atomic-read-v2-raw-records-02.csv','atomic-read-v2-states-02.csv']],assessment_source=assessment_id,independently_recalculated_pairs=87,counts=counts,comparisons=comparisons,preserved_failures=historical,observed_state_sharing=sorted({(x['run'].split('-')[0],x['depth'],x['handle_shared'],x['backing_private']) for x in states}),assessment='All14 successful v2 children match the exact cleared source and helper/runtime/package input identities and full current product inventories. Own RDS reader recalculates174 medians from1218positive raw second samples, verifies numeric ms plus allocation/GC summaries, and checks3672saved state facts with stable backing across all three prephases. ec10 has ordinary depth-zero storage; f622/a2 are depth one. All87 comparison formulas and strict thresholds match root assessment. All three24-pair read repeats retain exactly12flags, all at1Mrows and none100k. Arrow and one-column comparison counts remain explicitly reported, and original v1/cold failures stay failed and unchanged.',limits=['Scope is the selected12base-R kind/operation pairs, one logical Arrow write, and one-column1M-row diagnostic. It excludes the three historical filter_half flags. Repeated read regressions remain diagnosis obligations; no irreducibility, causal or overall acceptance claim.','The first reviewer state reader assumed every saved backing was shared/privateFALSE, which is stronger than the original gate and false for some facts. It stopped before writing outputs. Corrected reader validates the actual original invariants—bytes/depth/no exposure/stable backing—and retains observed sharing flags without forcing them. Both reader sources/logs preserved.','Post-timing objects and raw Rprofmem events are not retained. Successful original value/metadata/roundtrip/post-read-selector checks are evidenced by source-bound execution; recorded prephase states and raw bench summaries are independently auditable.','v2 restores an independent4rowrename warm-up and narrows original read history. This is a bounded diagnostic, not full historical execution replay. Baseline depth-zero storage is not relabeled owned.','Runtime/Python/installed package visible trees are bound; external OS/Homebrew/full Python closures remain excluded. All workloads were root-run during a quiet window; reviewer read only saved files.'])
with (review/'atomic-read-v2-evidence-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],runs=14,series=174,samples=1218,states=3672,counts=counts)))
