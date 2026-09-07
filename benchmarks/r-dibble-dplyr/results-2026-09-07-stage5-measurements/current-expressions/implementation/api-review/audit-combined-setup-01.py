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
    input_name = 'inputs.json' if name.endswith('-audit') else 'inputs-before.json'
    inputs = json.loads((folder/input_name).read_text())
    assert all(identity(x['path']) == x for x in inputs['inputs'])
    result_name = 'result.json' if name.endswith('-audit') else 'execution-result.json'
    result = json.loads((folder/result_name).read_text())
    assert result['returncode'] == 0 and not result['changed_inputs']
    if name.endswith('-audit'):
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
for name,kind in [('candidate-a2d8b6a-qualify-01','qualify'),('candidate-a2d8b6a-write-qualify-01','write_qualify')]:
    record,inputs=audit_products(name)
    assert inputs['source']=='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9' and inputs['case_set']==kind
    records.append(record)
folder=ROOT/'candidate-a2d8b6a-write-qualify-01'
qualified=read_csv(folder/'qualification.csv')
assert len(qualified)==15 and all(x['passed']=='TRUE' for x in qualified)
expected_cases={'retained_shared','computed_first','computed_shared','computed_private','full_replacement'}
assert {(x['mode'],x['case']) for x in qualified}=={(mode,case) for mode in ['direct','legacy','safe_reference'] for case in expected_cases}
states=read_csv(folder/'write-states.csv')
assert len(states)==600
columns=['x','s']+[f'p{i}' for i in range(3,17)]+['a','b','c','d']
for item in qualified:
    phases={phase:[x for x in states if x['mode']==item['mode'] and x['case']==item['case'] and x['phase']==phase] for phase in ['qualify_before','qualify_after']}
    for rows in phases.values():
        assert [x['column'] for x in rows]==columns
        assert all(x['rows']=='12' and x['iteration']=='0' and x['depth']=='1' and x['exposed']=='FALSE' for x in rows)
        assert all(int(x['bytes'])==12*(4 if x['type']=='logical' else 8) for x in rows)
    before={x['column']:x for x in phases['qualify_before']};after={x['column']:x for x in phases['qualify_after']}
    target='s' if item['case']=='retained_shared' else 'a'
    assert all(before[x]['backing']==after[x]['backing'] for x in columns if x!=target)
    assert after[target]['handle_shared']=='FALSE' and after[target]['backing_private']=='TRUE'
    private=item['case']=='computed_private'
    assert (before[target]['backing']==after[target]['backing'])==private
    assert before[target]['handle_shared']==('FALSE' if private else 'TRUE')
    assert before[target]['backing_private']==('TRUE' if private else 'FALSE')
report=dict(status='pass',runs=records,write_cases=15,write_state_rows=600,scope='Completed setup qualification and state evidence only; no timing or allocation-profile acceptance.')
with OUT.open('x') as stream: json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps(report))
