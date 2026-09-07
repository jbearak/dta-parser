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

records=[]
names=['candidate-622-wide-minimum-01', 'candidate-622-width-repeat-01']
for name in names:
    record,inputs=audit_products(name)
    assert inputs['source']=='622ffc194372d9882a78637077dff42f657b14a3'
    root_audit,_=audit_products(name.removesuffix('-01')+'-audit-01')
    grid=read_csv(ROOT/name/'grid.csv')
    minimum='minimum' in name
    expected={('64','retain')} if minimum else {(str(p),op) for p in [2,16,64] for op in ['retain','dependent']}
    assert {(x['columns'],x['operation']) for x in grid} == expected and len(grid)==len(expected)
    assert all(x['rows']==('12' if minimum else '100000') and x['kind']=='ungrouped' and x['groups']=='1' for x in grid)
    measurements=read_csv(ROOT/name/'measurements.csv')
    key=lambda row:tuple(row[k] for k in ['rows','columns','groups','kind','operation'])
    assert len(measurements)==len(grid)*2
    assert {(key(x),x['mode']) for x in measurements} == {(key(x),mode) for x in grid for mode in ['safe_reference','direct']}
    for row in measurements:
        assert int(row['iterations'])==7 and row['actual_input_columns']==row['columns']
        for field,value in row.items():
            if field.endswith('_bytes') or field=='median_ms': assert math.isfinite(float(value)) and float(value)>=0
    states=audit_state(name,grid)
    record.update(measurements=len(measurements),raw_samples=len(measurements)*7,state_rows=states,root_audit=root_audit)
    records.append(record)

profile,profile_inputs=audit_products('candidate-622-wide-profile-01')
assert profile_inputs['source']=='622ffc194372d9882a78637077dff42f657b14a3'
assert profile_inputs['profile_enabled'] and profile_inputs['profile_calls_per_mode']==2000
assert profile_inputs['requested_interval_seconds']==0.001
grid=read_csv(ROOT/'candidate-622-wide-profile-01/grid.csv')
assert grid==[dict(rows='12',columns='64',groups='1',kind='ungrouped',operation='retain')]
profile['state_rows']=audit_state('candidate-622-wide-profile-01',grid,True)
for mode in ['safe_reference','direct']:
    folder=ROOT/'candidate-622-wide-profile-01'
    assert (folder/(mode+'-source-before.rds')).read_bytes()==(folder/(mode+'-source-after.rds')).read_bytes()

report=dict(status='pass',scope='Current identities, completed inventories, state and CSV checks only. Raw RDS/profile calculations are a separate saved-data check; no measured operations run.',
            measurements=records,profile=profile)
with OUT.open('x') as stream: json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps(report))
