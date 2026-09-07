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

def audit_products(name):
    folder = ROOT / name
    receipt_path = ROOT / (name + '-receipt.json')
    receipt = json.loads(receipt_path.read_text())
    assert receipt['accepted'] is True
    assert identity(folder/'manifest.json') == receipt['manifest']
    manifest = json.loads((folder/'manifest.json').read_text())
    products = manifest['products']
    assert len({x['path'] for x in products}) == len(products)
    assert {str(x) for x in folder.iterdir()} == {x['path'] for x in products} | {str(folder/'manifest.json')}
    assert all(identity(x['path']) == x for x in products)
    input_name = 'inputs.json' if '-audit' in name else 'inputs-before.json'
    inputs = json.loads((folder/input_name).read_text())
    assert all(identity(x['path']) == x for x in inputs['inputs'])
    result_name = 'result.json' if '-audit' in name else 'execution-result.json'
    result = json.loads((folder/result_name).read_text())
    assert result['returncode'] == 0 and not result['changed_inputs']
    if '-audit' in name:
        assert result['error'] is None
    else:
        assert result['namespace_coverage'] and result['integrity_error'] is None
    return dict(name=name, receipt_sha256=identity(receipt_path)['sha256'],
                manifest_sha256=receipt['manifest']['sha256'], products=len(products),
                bound_inputs=len(inputs['inputs'])), inputs

def audit_state(name, grid, profiled=False):
    folder = ROOT/name
    states = read_csv(folder/'source-states.csv')
    keys = ['rows','columns','groups','kind','operation']
    phases = ['before_checks','before_profile','after_profile','after_checks'] if profiled else ['before_oracle','before_profile','before_timing','after_timing']
    groups = collections.defaultdict(list)
    for row in states:
        key = tuple(grid[0][k] for k in keys) if profiled else tuple(row[k] for k in keys)
        groups[(key,row['mode'],row['phase'])].append(row)
    assert len(groups) == len(grid)*2*4
    for item in grid:
        key = tuple(item[k] for k in keys)
        columns = {'x','s'} | {f'p{i}' for i in range(3,int(item['columns'])+1)}
        for mode in ['safe_reference','direct']:
            backing = collections.defaultdict(set)
            for phase in phases:
                rows = groups[(key,mode,phase)]
                assert len(rows) == len(columns) and {r['column'] for r in rows} == columns
                for row in rows:
                    assert row['type'] == ('character' if row['column']=='s' else 'double')
                    assert row['owned']=='TRUE' and row['exposed']=='FALSE' and row['depth']=='1'
                    assert float(row['bytes']) == int(item['rows'])*8
                    assert row['handle_shared']=='TRUE' and row['backing_private']=='FALSE'
                    backing[row['column']].add(row['backing'])
            assert all(len(values)==1 for values in backing.values())
    return len(states)


import statistics,re
sources={'baseline-f622':'f622f1ddba04b2bb7ac07415faccf2b417aab0e6','candidate-a2d8b6a':'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'}
write_records=[];memory_records=[];write_tables={};memory_tables={}
write_cases=['retained_shared','computed_first','computed_shared','computed_private','full_replacement']
for prefix,source in sources.items():
 name=prefix+'-write-measure-01';rec,inp=audit_products(name)
 assert inp['source']==source and inp['case_set']=='write_measure' and inp['command'][-1]==str(ROOT/'writes-v2.R')
 rows=read_csv(ROOT/name/'write-measurements.csv');samples=read_csv(ROOT/name/'write-samples.csv');states=read_csv(ROOT/name/'write-states.csv')
 assert len(rows)==20 and len(samples)==140 and len(states)==6800
 key=lambda r:(r['rows'],r['mode'],r['case'])
 expected={(str(n),m,c) for n in [100000,1000000] for m in ['direct','safe_reference'] for c in write_cases}
 assert {key(r) for r in rows}==expected
 groups=collections.defaultdict(list)
 for r in samples:groups[key(r)].append(r)
 sg=collections.defaultdict(dict)
 for row in states:
  k=(row['rows'],row['mode'],row['case'],row['iteration'],row['phase'])
  assert row['column'] not in sg[k];sg[k][row['column']]=row
  t='character' if row['column']=='s' else 'logical' if row['column']=='d' else 'double'
  assert row['type']==t and row['depth']=='1' and row['exposed']=='FALSE'
  assert float(row['bytes'])==int(row['rows'])*(4 if t=='logical' else 8)
 assert len(sg)==340
 expected_columns={'x','s',*('p'+str(i) for i in range(3,17)),'a','b','c','d'}
 for k,v in sg.items():assert set(v)==expected_columns
 def pair(n,mode,case,iteration,phase):
  old=sg[(str(n),mode,case,str(iteration),phase+'_before')];new=sg[(str(n),mode,case,str(iteration),phase+'_after')]
  target='s' if case=='retained_shared' else 'a'
  assert all(old[c]['backing']==new[c]['backing'] for c in expected_columns-{target})
  assert new[target]['handle_shared']=='FALSE' and new[target]['backing_private']=='TRUE'
  if case=='computed_private':assert old[target]['handle_shared']=='FALSE' and old[target]['backing_private']=='TRUE' and old[target]['backing']==new[target]['backing']
  else:assert old[target]['backing']!=new[target]['backing']
  return 0 if case=='full_replacement' else (float(old[target]['bytes']) if old[target]['handle_shared']=='TRUE' or old[target]['backing_private']=='FALSE' else 0)
 for mode in ['direct','safe_reference']:
  for case in write_cases:pair(12,mode,case,0,'qualify')
 for row in rows:
  n,mode,case=key(row);s=groups[key(row)]
  assert len(s)==7 and {r['iteration'] for r in s}==set(map(str,range(1,8)))
  times=[float(r['elapsed_ms']) for r in s];assert all(math.isfinite(x) and x>0 for x in times)
  assert row['iterations']=='7' and math.isclose(float(row['median_ms']),statistics.median(times),rel_tol=1e-12,abs_tol=1e-10)
  copy=pair(n,mode,case,0,'profile');assert float(row['native_mutation_target_copy_bytes'])==copy
  if case=='full_replacement':assert float(row['native_old_journal_bytes'])==0
  for i in range(1,8):pair(n,mode,case,i,'timing')
  for k,v in row.items():
   if k.endswith('_bytes'):assert math.isfinite(float(v)) and float(v)>=0
  assert float(row['r_largest_allocation_bytes'])<=float(row['r_allocated_bytes'])
 write_tables[prefix]={key(r):r for r in rows};write_records.append(dict(**rec,series=20,samples=140,states=6800))
 for size,n in [('100k',100000),('1m',1000000)]:
  for tag,mode in [('direct','direct'),('safe','safe_reference')]:
   name=f'{prefix}-memory-{size}-{tag}-01';rec,inp=audit_products(name)
   assert inp['source']==source and inp['case_set']=='memory' and inp['command']==['/usr/bin/time','-l','/opt/homebrew/Cellar/r/4.6.1/bin/Rscript','--vanilla',str(ROOT/'memory.R')]
   rows=read_csv(ROOT/name/'retained.csv');assert len(rows)==3 and [r['calls'] for r in rows]==['0','5','50']
   for row in rows:
    assert row['rows']==str(n) and row['mode']==mode and row['maximum_backing_depth']=='1'
    for k in ['n_cells_used','v_cells_used','gc_used_megabytes_rounded']:assert math.isfinite(float(row[k])) and float(row[k])>0
   log=(ROOT/name/'execution.log').read_text();assert 'PASS fifty-call retained state and values' in log
   rss=re.findall(r'^\s*(\d+)\s+maximum resident set size\s*$',log,re.M);assert len(rss)==1
   memory_records.append(dict(**rec,rows=n,mode=mode,checkpoints=rows,whole_process_maximum_rss_bytes=int(rss[0])))
comparisons=[]
for key,row in write_tables['baseline-f622'].items():
 before=float(row['median_ms']);after=float(write_tables['candidate-a2d8b6a'][key]['median_ms'])
 comparisons.append(dict(rows=key[0],mode=key[1],case=key[2],baseline_ms=before,candidate_ms=after,ratio=after/before,delta_ms=after-before,flag=after/before>1.1 and after-before>1))
report=dict(status='pass',write_runs=write_records,memory_runs=memory_records,paired_write_comparisons=comparisons,
 scope='Bound completed inputs/products, source-declared millisecond samples/medians, profiled copy budgets and saved write transitions. Memory saved RDS states are checked separately. Runtime return zero retains value/meta/alias assertions, not independent saved payload values. No workload rerun, RSS/allocation conflation or overall performance acceptance.')
with OUT.open('x') as stream:json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps(dict(status='pass',write_runs=2,write_series=40,write_samples=280,write_states=13600,memory_runs=8,write_flags=[x for x in comparisons if x['flag']],rss=[dict(name=x['name'],bytes=x['whole_process_maximum_rss_bytes']) for x in memory_records])))
