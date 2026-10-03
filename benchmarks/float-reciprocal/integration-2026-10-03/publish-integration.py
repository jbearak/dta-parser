from pathlib import Path
import hashlib,json,re,importlib.util
W=Path(__file__).resolve().parent
R=Path('<repository>')
OUT=R/'benchmarks/float-reciprocal/integration-2026-10-03'
spec=importlib.util.spec_from_file_location('privacy',W/'publish.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
b=json.loads((W/'integration-binding.json').read_text())
m.require(b['status']=='PASS' and b['source_commit']=='c5d5aebc5a70fde0bfa67816e1ab2e44bd812b92' and b['focused_totals']==dict(passed=58433,failed=0,error=0,skipped=0,warning=0) and b['focused_blocks']==51,'Failed integration binding')
for path,digest in b['input_sha256'].items():m.bound(Path(path),digest)
m.require(not OUT.exists(),'Existing integration publication')
files=['integration-binding.json','integration-focused.R','integration-focused.csv','integration-focused.log','integration-manifest.log','bind-integration.py','publish-integration.py']
source_map=[];pending={}
for f in files:
 raw=(W/f).read_bytes();s=raw.decode()
 if f.endswith('.json'):
  x=json.loads(s);m.identities(x);s=m.encoded(x).decode()
 for old,new in [(str(W),'<work>'),(str(R),'<repository>'),(str(Path.home()),'<user>')]:s=s.replace(old,new)
 s=re.sub(r'/(?:private/)?tmp/([^/\s\"\'<>]+)',r'<private-work>/\1',s)
 s=re.sub(r'/(?:private/)?var/folders/[^\s\"\'<>]+','<temporary>',s)
 m.require(not re.search(r'/(?:Users|home)/[^/]+/',s),'Unredacted user path')
 data=s.encode();pending[f]=data;source_map.append(dict(artifact=f,source_sha256=hashlib.sha256(raw).hexdigest(),published_sha256=hashlib.sha256(data).hexdigest()))
pending['source-map.json']=m.encoded(source_map)
pending['manifest.json']=m.encoded({f:hashlib.sha256(v).hexdigest() for f,v in pending.items()})
OUT.mkdir()
for name,data in pending.items():(OUT/name).write_bytes(data)
print('Published',len(pending),'integration files')
