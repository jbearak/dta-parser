"""Snapshot a selective read-diagnosis archive, retaining failed attempts."""
from pathlib import Path
import hashlib,json
ROOT=Path('/private/tmp/dta-direct-stage5-validation')
PERF=ROOT/'root-expression-performance'

def identity(p):
 b=p.read_bytes()
 return dict(bytes=len(b),mode=oct(p.stat().st_mode & 0o777),sha256=hashlib.sha256(b).hexdigest())

def related(name):
 return any(x in name for x in ['read-', 'read_', 'arrow-repeat'])

def review_related(name):
 return any(x in name for x in ['atomic-read-', 'native-control-', 'native-read-control-', 'native-count-', 'read-control-', 'read-count-'])

paths=set()
run_records=[]
for child in sorted(PERF.iterdir()):
 if not related(child.name):continue
 if child.is_file():paths.add(child)
 elif child.is_dir():
  paths.update(p for p in child.rglob('*') if p.is_file())
  receipt=PERF/(child.name+'-receipt.json')
  if not receipt.exists():receipt=child/'completed-receipt.json'
  if not receipt.exists():continue
  record=json.loads(receipt.read_text());verified=[]
  binding=record.get('manifest')
  if isinstance(binding,dict) and 'path' in binding:
   manifest=Path(binding['path']);assert all(identity(manifest)[k]==binding[k] for k in ('bytes','mode','sha256'))
   for product in json.loads(manifest.read_text())['products']:
    source=Path(product['path']);assert all(identity(source)[k]==product[k] for k in ('bytes','mode','sha256'))
    verified.append(str(source))
  run_records.append(dict(name=child.name,receipt=str(receipt),receipt_sha256=identity(receipt)['sha256'],original_accepted=record.get('accepted'),verified_products=len(verified),qualification='Original status retained, including failures and historical binding limits.'))
for role in ['api-review','semantics-review']:
 paths.update(p for p in (ROOT/'implementation'/role).iterdir() if p.is_file() and review_related(p.name))
# These external references retain their original absolute-path identities.
extras={Path('/private/tmp/dta-direct-stage5-read-cost-preparation.md'):'preparation/read-cost-source-note.md',Path('/private/tmp/dta-direct-stage5-read-cost-preparation.inputs.json'):'preparation/read-cost-source-inputs.json',ROOT/'test-bundle-evidence-v1.py':'test-bundle-evidence-v1.py',ROOT/'bundle-tests-v1-observed-result.json':'bundle-tests-v1-observed-result.json'}
files=[]
for source in sorted(paths):
 path=str(source.relative_to(ROOT))
 plain=source.suffix in ('.py','.R','.c','.h','.md') or 'disposition' in source.name or 'assessment' in source.name
 files.append(dict(source=str(source),path=path,presentation='plain' if plain else 'bundle',**identity(source)))
for source,path in extras.items():files.append(dict(source=str(source),path=path,presentation='plain',**identity(source)))
selection=dict(scope='DRAFT read repeats, setup failure diagnosis and public-API native controls. Original receipt status and source/runtime limits retained. Final count reviews, read-cost disposition and README still pending.',run_records=run_records,files=sorted(files,key=lambda x:x['path']))
out=ROOT/'read-diagnosis-selection-draft-01.json'
with out.open('x') as stream:stream.write(json.dumps(selection,indent=2)+'\n')
print(json.dumps(dict(files=len(files),plain=sum(x['presentation']=='plain' for x in files),bytes=sum(x['bytes'] for x in files),receipt_records=len(run_records),failed=[x['name'] for x in run_records if x['original_accepted'] is False])))
