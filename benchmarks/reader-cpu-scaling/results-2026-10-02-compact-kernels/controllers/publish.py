"""Publish completed compact-kernel measurements and their source bindings."""
import csv, hashlib, importlib.util, json, re, shutil
from pathlib import Path
ROOT=Path('<compact-work>')
REPO=Path('<repository>')
OUT=REPO/'benchmarks/reader-cpu-scaling/results-2026-10-02-compact-kernels'
REPORT=OUT.with_suffix('.md')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def require(v,msg):
 if not v:raise RuntimeError(msg)
def read(p):return json.loads(p.read_text())
replacements=[(str(REPO),'<repository>'),(str(ROOT),'<compact-work>'),('<scalar-work>','<scalar-work>'),('<reader-work>','<reader-work>'),('<user-home>','<user-home>')]
def clean(s):
 for a,b in replacements:s=s.replace(a,b)
 s=re.sub(r'/private/(?:tmp|var/folders)/[^\s"\'`<>]+','<private-path>',s)
 return s
artifacts={}; mappings=[]
def copy(src,name):
 data=src.read_bytes()
 try: published=clean(data.decode()).encode()
 except UnicodeDecodeError: raise RuntimeError('Binary artifact not permitted: '+name)
 artifacts[name]=published
 mappings.append(dict(artifact=name,source_sha256=hashlib.sha256(data).hexdigest(),published_sha256=hashlib.sha256(published).hexdigest(),transformation='none' if data==published else 'private absolute paths replaced with documented placeholders'))
def add(name,value):artifacts[name]=(json.dumps(value,indent=2,sort_keys=True)+'\n').encode()
plan=read(ROOT/'publication-plan.json')
require(plan['ready'],'publication pending')
validation=read(ROOT/'final-validation.json')
require(validation['production_source_matches_accepted_build'],'source mismatch')
require(validation['full_r_suite']['failed']==0 and validation['full_r_suite']['error']==0,'tests failed')
spec=importlib.util.spec_from_file_location('records',REPO/'benchmarks/r-file-readers/record-builds.py')
records=importlib.util.module_from_spec(spec);spec.loader.exec_module(records)
for role,path in plan['builds'].items():
 p=Path(path);records.verified_receipt(p,'candidate')
 copy(p/'build-receipt.json',f'builds/{role}/build-receipt.json')
 copy(p/'source.patch',f'builds/{role}/source.patch')
for stage,path in plan['stages'].items():
 p=Path(path)
 before=read(p/'provenance-before.json');after=read(p/'provenance-after.json')
 require(before==after,'stage bindings changed: '+stage)
 completion=read(p/'completion.json')
 require(completion['bindings_matched'] and completion['exact_validation'],'qualification failed')
 raw=list(csv.DictReader((p/'raw.csv').open()))
 require(len(raw)==completion['observations'],'row count differs')
 require(all(r['exact']=='TRUE' and r['lazy_before']=='TRUE' and r['lazy_after']=='TRUE' for r in raw),'inexact or materialized')
 for name in ('raw.csv','summary.csv','parity.csv','paired-summary.csv','protocol.json','completion.json','provenance-before.json','provenance-after.json','jobs.json'):
  if (p/name).exists():copy(p/name,f'{stage}/{name}')
for item in plan['files']:copy(Path(item['source']),item['destination'])
copied_sources={item['source_sha256'] for item in mappings}
for stage,path in plan['stages'].items():
 before=read(Path(path)/'provenance-before.json')
 for label,record in before['files'].items():
  if label!='probe_dll':require(record['sha256'] in copied_sources,'measured source not published: '+stage+'/'+label)
 for record in before['builds'].values():require(record['receipt_sha256'] in copied_sources,'measured receipt not published')
copy(ROOT/'final-validation.json','validation/final-validation.json')
copy(ROOT/'publication-plan.json','publication-plan.json')
copy(Path(__file__),'controllers/publish.py')
add('publication-source-map.json',mappings)
add('publication-manifest.json',dict(artifacts={name:hashlib.sha256(data).hexdigest() for name,data in sorted(artifacts.items())},report_sha256=sha(REPORT),note='Input binaries and installed libraries excluded. Original and published hashes retained in source map. Compiler assembly excerpts omit debug tables.'))
require(not OUT.exists(),'output already exists')
for name,data in artifacts.items():
 p=OUT/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
manifest=read(OUT/'publication-manifest.json')
require(all(sha(OUT/name)==digest for name,digest in manifest['artifacts'].items()),'published hash differs')
require(sha(REPORT)==manifest['report_sha256'],'report hash differs')
print(json.dumps(dict(artifacts=len(artifacts),all_hashes_verified=True)))
