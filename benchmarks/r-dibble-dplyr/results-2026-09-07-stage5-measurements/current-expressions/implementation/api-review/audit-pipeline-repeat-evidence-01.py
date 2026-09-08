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


records=[];tables={};total_states=0
sources={'baseline':'f622f1ddba04b2bb7ac07415faccf2b417aab0e6','candidate':'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'}
for repeat in range(1,4):
    for role,source in sources.items():
        name=f'{role}-pipeline-repeat-{repeat:02d}'
        record,inputs=audit_products(name)
        audit_record,_=audit_products(name+'-audit-01')
        assert inputs['source']==source and inputs['case_set']=='pipeline_repeat'
        assert inputs['command'][-1]==str(ROOT/'pipeline-repeat-v1.R')
        grid=read_csv(ROOT/name/'grid.csv')
        assert len(grid)==1 and grid[0]==dict(rows='1000000',columns='16',groups='1',kind='ungrouped',operation='pipeline_five')
        total_states+=audit_state(name,grid)
        rows=read_csv(ROOT/name/'measurements.csv')
        assert len(rows)==2 and {r['mode'] for r in rows}=={'safe_reference','direct'}
        for row in rows:
            assert all(row[k]==v for k,v in grid[0].items()) and row['iterations']=='7'
            for k,v in row.items():
                if k.endswith('_bytes') or k=='median_ms': assert math.isfinite(float(v)) and float(v)>=0
        tables[(role,repeat)]={r['mode']:r for r in rows}
        records.append(dict(measurement=record,raw_audit=audit_record))
assert total_states==768
folder=ROOT/'pipeline-repeats-a2d8b6a-01'
plan=json.loads((folder/'plan.json').read_text());result=json.loads((folder/'result.json').read_text());receipt=json.loads((folder/'receipt.json').read_text())
def small_identity(path):
    item=identity(path)
    return {k:item[k] for k in ['path','resolved','sha256']}
assert receipt=={name:small_identity(folder/(name+'.json')) for name in ['plan','result']}
assert all(small_identity(x['path'])==x for x in plan['inputs'])
assert plan['environment_overrides']=={'DTA_EXPRESSION_ITERATIONS':'7'}
assert len(plan['commands'])==6 and result['complete'] and not result['changed_inputs'] and result['failure'] is None
assert [x['command'] for x in result['commands']]==plan['commands'] and all(x['returncode']==0 for x in result['commands'])
for index,command in enumerate(plan['commands']):
    role=['baseline','candidate'][index%2];repeat=index//2+1
    assert command[0]=='/Users/jmb/.pyenv/versions/3.14.7/bin/python3.14' and command[1]==str(ROOT/'pipeline-repeat-v1.py')
    assert command[2]==sources[role] and command[4]==f'{role}-pipeline-repeat-{repeat:02d}' and command[5]=='pipeline_repeat'
assessment_path=ROOT/'pipeline-repeat-assessment-a2d8b6a-01.json'
assessment=json.loads(assessment_path.read_text())
assert len(assessment['records'])==6 and len(assessment['input_bindings'])==18
assert all(identity(x['path'])['sha256']==x['sha256'] for x in assessment['input_bindings'])
for record in assessment['records']:
    repeat=record['repeat'];mode=record['mode']
    before=float(tables[('baseline',repeat)][mode]['median_ms']);after=float(tables[('candidate',repeat)][mode]['median_ms'])
    for field,value in [('baseline_ms',before),('candidate_ms',after),('delta_ms',after-before),('ratio',after/before)]:
        assert math.isclose(record[field],value,rel_tol=1e-12,abs_tol=1e-10)
    assert record['flag']==(after/before>1.1 and after-before>1) and record['flag'] is False
report=dict(status='pass',runs=records,series=12,raw_samples_expected=84,state_rows=total_states,coordinator_receipt=identity(folder/'receipt.json'),
            assessment=identity(assessment_path),comparisons=assessment['records'],
            audit_drivers={x:identity(ROOT/x) for x in ['audit-pipeline-repeat.py','audit-pipeline-repeat.R']},
            scope='Saved completed evidence and arithmetic only. Raw samples independently checked by separate saved-RDS-only R calculator. Reference flag does not recur in three pairs; no causal or overall acceptance claim.')
with OUT.open('x') as stream:json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps(dict(status='pass',runs=6,series=12,state_rows=total_states,comparisons=assessment['records'])))
