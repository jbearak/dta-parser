"""Read-only completed-artifact audit; no R or measured operation is launched."""
from pathlib import Path
import collections
import csv
import hashlib
import json
import math

ROOT = Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance')
OUT = Path(__file__).with_suffix('.json')
CACHE = {}

def identity(path):
    path = Path(path)
    target = path.resolve(strict=True)
    info = target.stat()
    key = (str(target), info.st_size, info.st_mtime_ns, info.st_mode)
    if key not in CACHE:
        CACHE[key] = hashlib.sha256(target.read_bytes()).hexdigest()
    return dict(path=str(path), resolved=str(target), bytes=info.st_size,
                mode=oct(info.st_mode & 0o777), sha256=CACHE[key])

def read_csv(path):
    with path.open() as stream:
        return list(csv.DictReader(stream))


import statistics
sources={'baseline-ec10':'ec10a6ac34602f3bd691e8043019c1b479babda4','baseline-f622':'f622f1ddba04b2bb7ac07415faccf2b417aab0e6','candidate-a2d8b6a':'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'}
assert identity(ROOT/'atomic-read-repeat-v2.R')['sha256']=='639550d5652b3ad5c4eb92aecd21d6fcf9958e931c5ae6015f153eb5cfcfbc33'
assert identity(ROOT/'atomic-read-repeat-v2.py')['sha256']=='ccc852b766fc3797696c35638accc36482e3557d3f3e6853c4c58e78c056c6f4'
selected={'declared_character':['any_na','nonmissing_count'],'logical':['nonmissing_count','coercion_character','coercion_integer','mean'],'factor':['any_na','nonmissing_count','coercion_character'],'ordered':['any_na','nonmissing_count','coercion_character']}
records=[];tables={};names=[];receipt_map={}
for case,tag,count,width,ns,baseline in [('reads_repeat','read-repeat',24,8,[100000,1000000],'baseline-ec10'),('arrow_repeat','arrow-repeat',1,8,[100000],'baseline-f622'),('reads_minimum','read-minimum',12,1,[1000000],'baseline-ec10')]:
 for repeat in range(1,2 if case=='reads_minimum' else 4):
  for prefix in [baseline,'candidate-a2d8b6a']:
   name=f'{prefix}-{tag}-v2-{repeat:02d}';names.append(name);folder=ROOT/name
   receipt_path=ROOT/(name+'-receipt.json');receipt=json.loads(receipt_path.read_text());receipt_map[name]=identity(receipt_path)
   manifest=json.loads((folder/'manifest.json').read_text());inputs=json.loads((folder/'inputs-before.json').read_text());result=json.loads((folder/'execution-result.json').read_text())
   assert receipt['accepted'] and receipt['returncode']==0 and not receipt['changed_inputs'] and receipt['namespace_coverage'] and receipt['integrity_error'] is None
   assert receipt['manifest']==identity(folder/'manifest.json') and result['returncode']==0 and not result['changed_inputs'] and result['namespace_coverage'] and result['integrity_error'] is None
   assert all(identity(x['path'])==x for x in manifest['products'])
   assert set(str(x) for x in folder.iterdir())=={x['path'] for x in manifest['products']}|{str(folder/'manifest.json')}
   assert all(identity(x['path'])==x for x in inputs['inputs'])
   assert inputs['source']==sources[prefix] and inputs['runner_source']==sources['candidate-a2d8b6a'] and inputs['case_set']==case
   assert inputs['command'][2]==str(ROOT/'atomic-read-repeat-v2.R') and inputs['command'][-3:]==[sources[prefix],inputs['mode'],'7']
   bound={x['resolved'] for x in inputs['inputs']}
   with (folder/'namespaces.tsv').open() as stream: namespaces=list(csv.DictReader(stream,delimiter='\t'))
   assert all(str((Path(x['path'])/'DESCRIPTION').resolve(strict=True)) in bound for x in namespaces)
   rows=read_csv(folder/'owned-atomic.csv');after=read_csv(folder/'owned-atomic-after-read.csv')
   assert len(rows)==len(after)==count
   key=lambda x:(x['kind'],x['operation'],int(x['rows']),int(x['columns']))
   expected={('logical','write_arrow',100000,8)} if case=='arrow_repeat' else {(kind,op,n,width) for kind,ops in selected.items() for op in ops for n in ns}
   assert {key(x) for x in rows}==expected
   assert {(x['kind'],x['after_operation'],int(x['rows'])) for x in after}=={x[:3] for x in expected}
   for row in rows:
    assert row['family']=='read' and row['iterations']=='7' and math.isfinite(float(row['median_ms'])) and float(row['median_ms'])>0
   if prefix=='candidate-a2d8b6a':
    for row in after:
     assert float(row['r_allocated_bytes'])<1000000
     assert all(float(v)==0 for k,v in row.items() if k.startswith('native_') or k.startswith('validation_'))
   tables[(tag,repeat,prefix)]={key(x):x for x in rows}
   records.append(dict(name=name,receipt=receipt_map[name],products=len(manifest['products']),inputs=len(inputs['inputs']),series=count,namespaces=len(namespaces)))
assessment_path=ROOT/'atomic-read-repeat-v2-root-assessment-01.json';assessment=json.loads(assessment_path.read_text())
assert len(assessment['runs'])==14 and len(assessment['comparisons'])==87
for name,entry in assessment['runs'].items():
 assert name in names
 # Inspect all explicitly recorded receipt/CSV hashes via their associated paths below.
comparisons=[]
for tag,count,width,ns,baseline in [('read-repeat',24,8,[100000,1000000],'baseline-ec10'),('arrow-repeat',1,8,[100000],'baseline-f622'),('read-minimum',12,1,[1000000],'baseline-ec10')]:
 for repeat in range(1,2 if tag=='read-minimum' else 4):
  a=tables[(tag,repeat,baseline)];b=tables[(tag,repeat,'candidate-a2d8b6a')]
  for key,old in a.items():
   before=float(old['median_ms']);after=float(b[key]['median_ms']);kind,operation,rows,columns=key
   record=dict(case=tag,repeat=repeat,kind=kind,operation=operation,rows=rows,columns=columns,baseline_ms=before,candidate_ms=after,delta_ms=after-before,ratio=after/before,flag=after/before>1.1 and after-before>1)
   matches=[x for x in assessment['comparisons'] if all(x[k]==record[k] for k in ['case','repeat','kind','operation','rows','columns'])]
   assert len(matches)==1
   for k,v in record.items():
    if isinstance(v,float):assert math.isclose(matches[0][k],v,rel_tol=1e-12,abs_tol=1e-10)
    else:assert matches[0][k]==v
   comparisons.append(record)
flag_summary=[]
for tag in ['read-repeat','arrow-repeat','read-minimum']:
 for repeat in range(1,2 if tag=='read-minimum' else 4):
  subset=[r for r in comparisons if r['case']==tag and r['repeat']==repeat]
  flags=[r for r in subset if r['flag']]
  if tag=='read-repeat':assert len(flags)==12 and all(r['rows']==1000000 for r in flags)
  flag_summary.append(dict(case=tag,repeat=repeat,comparisons=len(subset),flags=len(flags)))
report=dict(status='pass',runs=records,total_series=174,expected_raw_samples=1218,total_comparisons=87,flag_summary=flag_summary,comparisons=comparisons,assessment=identity(assessment_path),
 scope='Current completed product/input/namespace integrity, CSV corpus/gates and independent arithmetic. Saved RDS raw samples/states checked separately. Original failures preserved separately; no irreducibility, cause or overall acceptance claim.')
with OUT.open('x') as stream:json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps(dict(status='pass',runs=14,series=174,comparisons=87,flags=flag_summary)))
