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

candidate='candidate-a2d8b6a-measure-01'
baseline='baseline-f622-measure-02'
candidate_record,candidate_inputs=audit_products(candidate)
candidate_audit,_=audit_products(candidate+'-audit-01')
baseline_record,baseline_inputs=audit_products(baseline)
baseline_audit,_=audit_products(baseline+'-audit')
assert candidate_inputs['source']=='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
grid=read_csv(ROOT/candidate/'grid.csv')
assert grid==read_csv(ROOT/baseline/'grid.csv') and len(grid)==25
keys=['rows','columns','groups','kind','operation']
key=lambda row:tuple(row[x] for x in keys)
measurements=read_csv(ROOT/candidate/'measurements.csv')
assert len(measurements)==50
assert {(key(x),x['mode']) for x in measurements}=={(key(x),mode) for x in grid for mode in ['direct','safe_reference']}
states=read_csv(ROOT/candidate/'source-states.csv')
assert len(states)==3456
phases=['before_oracle','before_profile','before_timing','after_timing']
grouped=collections.defaultdict(list)
for row in states: grouped[(key(row),row['mode'],row['phase'])].append(row)
assert len(grouped)==200
for item in grid:
    columns={'x','s'}|{f'p{i}' for i in range(3,int(item['columns'])+1)}
    if item['kind'] in ['grouped','by']: columns.add('g')
    for mode in ['direct','safe_reference']:
        backings=collections.defaultdict(set)
        for phase in phases:
            rows=grouped[(key(item),mode,phase)]
            assert len(rows)==len(columns) and {x['column'] for x in rows}==columns
            for row in rows:
                assert row['type']==('character' if row['column']=='s' else 'double')
                assert row['owned']=='TRUE' and row['exposed']=='FALSE' and row['depth']=='1'
                assert float(row['bytes'])==int(item['rows'])*8
                assert row['handle_shared']=='TRUE' and row['backing_private']=='FALSE'
                backings[row['column']].add(row['backing'])
        assert all(len(x)==1 for x in backings.values())

folder=ROOT/'expression-comparison-a2d8b6a-01'
receipt_path=folder/'completed-receipt.json'
receipt=json.loads(receipt_path.read_text())
assert receipt['status']=='complete' and not receipt['changed_inputs']
assert identity(folder/'manifest.json')==receipt['manifest']
products=json.loads((folder/'manifest.json').read_text())['products']
assert {str(x) for x in folder.iterdir()}=={x['path'] for x in products}|{str(folder/'manifest.json'),str(receipt_path)}
assert all(identity(x['path'])==x for x in products)
bound=json.loads((folder/'inputs.json').read_text())
assert all(identity(x['path'])==x for x in bound['inputs'])
for path,files in bound['inventories'].items():
    assert sorted(str(x) for x in Path(path).iterdir() if x.is_file())==files
assert all(identity(x['path'])==x for x in bound['common_measurement_inputs'].values())
launchers=list(bound['orchestration_launchers'].values())
assert len(launchers)==2 and launchers[0]==launchers[1] and identity(launchers[0]['path'])==launchers[0]
assert bound['measurement_command']==candidate_inputs['command']==baseline_inputs['command']
result=json.loads((folder/'result.json').read_text())
assert result['status']=='complete' and result['failure'] is None and not result['changed_inputs']
reference_rows=read_csv(ROOT/baseline/'measurements.csv')
tables={'baseline':{(key(x),x['mode']):x for x in reference_rows},'candidate':{(key(x),x['mode']):x for x in measurements}}
pairs={
    'candidate_direct_vs_baseline_direct':('baseline','direct','candidate','direct'),
    'candidate_direct_vs_baseline_reference':('baseline','safe_reference','candidate','direct'),
    'candidate_direct_vs_candidate_reference':('candidate','safe_reference','candidate','direct'),
    'candidate_reference_vs_baseline_reference':('baseline','safe_reference','candidate','safe_reference'),
}
comparisons=read_csv(folder/'comparisons.csv')
assert len(comparisons)==100 and {(key(x),x['comparison']) for x in comparisons}=={(key(x),p) for x in grid for p in pairs}
flags=[]
def close(a,b): return math.isclose(float(a),float(b),rel_tol=1e-12,abs_tol=1e-10)
for row in comparisons:
    rs,rm,ms,mm=pairs[row['comparison']]
    ref=tables[rs][(key(row),rm)];measured=tables[ms][(key(row),mm)]
    before=float(ref['median_ms']);after=float(measured['median_ms'])
    assert close(row['reference_ms'],before) and close(row['measured_ms'],after)
    assert close(row['delta_ms'],after-before) and close(row['time_ratio'],after/before)
    flag=after/before>1.1 and after-before>1
    assert row['investigate_time_regression']==str(flag)
    for field in ref:
        if not field.endswith('_bytes'): continue
        assert close(row['reference_'+field],ref[field]) and close(row['measured_'+field],measured[field])
        assert close(row['delta_'+field],float(measured[field])-float(ref[field]))
    if flag: flags.append(row)
assert len(flags)==1 and flags[0]['comparison']=='candidate_reference_vs_baseline_reference'
assert key(flags[0])==('1000000','16','1','ungrouped','pipeline_five')
assessment=json.loads((folder/'assessment.json').read_text())
assert assessment['status']=='requires_assessment' and len(assessment['flags'])==1
assert key(assessment['flags'][0])==key(flags[0]) and assessment['flags'][0]['comparison']==flags[0]['comparison']
report=dict(status='pass',measurement=candidate_record,raw_audit=candidate_audit,baseline=baseline_record,baseline_raw_audit=baseline_audit,state_rows=3456,
            comparisons=100,comparison_products=len(products),comparison_inputs=len(bound['inputs']),common_inputs=len(bound['common_measurement_inputs']),
            comparison_receipt_sha256=identity(receipt_path)['sha256'],flags=assessment['flags'],
            scope='Completed full measurement and arithmetic integrity only. Raw samples checked separately from saved RDS. One reference-only flag requires diagnosis; no overall performance acceptance.')
with OUT.open('x') as stream: json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps(report))
