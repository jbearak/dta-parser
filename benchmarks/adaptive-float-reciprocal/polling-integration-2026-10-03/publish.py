"""Publish a redacted, separate merge-qualification supplement."""
import hashlib,json,re
from pathlib import Path
P=Path(__file__).resolve().parent
OUT=Path('<PRIVATE_TMP>/dta-float-reciprocal-adaptive/benchmarks/adaptive-float-reciprocal/polling-integration-2026-10-03')
def sha(data):return hashlib.sha256(data).hexdigest()
def need(v,m):
 if not v:raise RuntimeError(m)
b=json.loads((P/'binding.json').read_text());need(b['status']=='PASS','Binding not passed')
for name,h in b['artifact_sha256'].items():need(sha((P/name).read_bytes())==h,'Bound artifact changed')
for name,h in b['source_inventory'].items():need(sha((P/'build/source'/name).read_bytes())==h,'Bound source changed')
files=list(b['artifact_sha256'])+['binding.json','publish.py']
# Preserve original whole-artifact hashes, while removing direct identity values/digests.
private_identity=[]
def scrub(value):
 if isinstance(value,dict):
  out={}
  for k,v in value.items():
   if k in ('USER','LOGNAME'):
    need(isinstance(v,dict) and set(v)=={'value','sha256'} and all(isinstance(x,str) for x in v.values()),'Unknown identity schema')
    private_identity.extend(v.values());out[k]={'value':'<REDACTED>','sha256':'<REDACTED>'}
   else:out[k]=scrub(v)
  return out
 if isinstance(value,list):return [scrub(v) for v in value]
 return value
need(not OUT.exists(),'Refusing publication overwrite')
OUT.mkdir(parents=True)
source_map={}
for name in files:
 data=(P/name).read_bytes()
 if name.endswith('.json'):data=(json.dumps(scrub(json.loads(data)),indent=2)+'\n').encode()
 text=data.decode().replace('<PRIVATE_TMP>','<PRIVATE_TMP>').replace('<USER_HOME>','<USER_HOME>')
 published=text.encode();target=OUT/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(published)
 source_map[name]={'source_sha256':sha((P/name).read_bytes()),'published_sha256':sha(published)}
for name in files:
 text=(OUT/name).read_text()
 # The publisher's own replacement literals describe the privacy rule, not a leaked path.
 if name!='publish.py':need('<PRIVATE_TMP>/' not in text and '/Users/' not in text,'Private path remains')
 if name.endswith('.json'):
  for value in private_identity:
   if len(value)>3 and not (value.startswith('<') and value.endswith('>')):
    need(value not in text,'Direct identity/digest remains')
(OUT/'publication-source-map.json').write_text(json.dumps(source_map,indent=2)+'\n')
manifest={str(p.relative_to(OUT)):sha(p.read_bytes()) for p in sorted(OUT.rglob('*')) if p.is_file()}
(OUT/'publication-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('PASS',len(manifest)+1,'artifacts')
