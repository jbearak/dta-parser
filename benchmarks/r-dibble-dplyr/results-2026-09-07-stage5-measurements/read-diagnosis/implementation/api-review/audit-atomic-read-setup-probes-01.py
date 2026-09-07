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


records=[]
for setup,accepted,expected in [('cold',False,(2191016,82104)),('warm',True,(83192,40112))]:
 name=f'candidate-a2d8b6a-read-setup-{setup}-01';folder=ROOT/name
 receipt_path=ROOT/(name+'-receipt.json');receipt=json.loads(receipt_path.read_text());manifest=json.loads((folder/'manifest.json').read_text());inputs=json.loads((folder/'inputs-before.json').read_text());result=json.loads((folder/'execution-result.json').read_text())
 assert receipt['manifest']==identity(folder/'manifest.json') and receipt['accepted']==accepted
 assert not receipt['changed_inputs'] and receipt['integrity_error'] is None and receipt['returncode']==(0 if accepted else 1)
 assert result['returncode']==receipt['returncode'] and not result['changed_inputs'] and result['integrity_error'] is None
 assert result['namespace_coverage']==accepted
 assert len(manifest['products'])==8 and all(identity(x['path'])==x for x in manifest['products'])
 assert {str(x) for x in folder.iterdir()}=={x['path'] for x in manifest['products']}|{str(folder/'manifest.json')}
 assert all(identity(x['path'])==x for x in inputs['inputs'])
 assert inputs['source']==inputs['runner_source']=='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9' and inputs['mode']=='candidate' and inputs['case_set']==('rename' if accepted else 'cold')
 bound={x['resolved'] for x in inputs['inputs']}
 with (folder/'namespaces.tsv').open() as stream:
  namespaces=list(csv.DictReader(stream,delimiter='\t'))
 for row in namespaces:assert str((Path(row['path'])/'DESCRIPTION').resolve(strict=True)) in bound
 metrics=read_csv(folder/'fork-metrics.csv');assert len(metrics)==1;metrics={k:float(v) for k,v in metrics[0].items()}
 assert (metrics['r_allocated_bytes'],metrics['r_largest_allocation_bytes'])==expected
 assert all(v==0 for k,v in metrics.items() if k.startswith('native_') or k.startswith('validation_'))
 log=(folder/'execution.log').read_text()
 if accepted:assert 'PASS allocation-only first-case probe rename' in log
 else:assert 'metrics[["r_allocated_bytes"]] < 1e+06 is not TRUE' in log
 records.append(dict(name=name,receipt=identity(receipt_path),accepted=accepted,products=8,inputs=len(inputs['inputs']),independently_verified_namespace_paths=len(namespaces),metrics=metrics))
report=dict(status='clear-for-diagnostic-interpretation',runs=records,new_driver_sources={name:identity(ROOT/name) for name in ['atomic-read-repeat-v2.R','atomic-read-repeat-v2.py']},
 interpretation='Cold reproduces the unchanged allocation gate and independent four-row rename warm-up passes it; restoring omitted original setup is supported. This does not isolate rename from setup/compilation in its dependencies, prove raw allocation provenance, establish timings or clear other performance flags. Cold failure remains failed qualification; reviewer separately checked its retained namespace coverage.')
with OUT.open('x') as stream:json.dump(report,stream,indent=2);stream.write('\n')
print(json.dumps(dict(status=report['status'],runs=[{k:x[k] for k in ['name','accepted','products','inputs','independently_verified_namespace_paths','metrics']} for x in records])))
