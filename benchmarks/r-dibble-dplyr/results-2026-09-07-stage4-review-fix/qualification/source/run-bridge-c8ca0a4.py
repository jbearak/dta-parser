import pathlib,subprocess,hashlib,json,os,time,tarfile
v=pathlib.Path('/private/tmp/dta-direct-stage4-validation');source=v/'source-c8ca0a4';out=v/'checks-c8ca0a4';src=source/'r-package/dtatools/src'
manifest=json.loads((v/'source-c8ca0a4-manifest.json').read_text())
vendor=src/'rust/vendor.tar.gz'
if hashlib.sha256(vendor.read_bytes()).hexdigest()!=manifest['files']['r-package/dtatools/src/rust/vendor.tar.gz']:raise RuntimeError('Vendor identity changed')
if (src/'rust/v').exists():raise RuntimeError('Vendor destination already exists')
with tarfile.open(vendor) as archive:archive.extractall(src/'rust',filter='data')
env=os.environ.copy();env['CARGO_TARGET_DIR']=str(v/'bridge-target-c8ca0a4')
records=[]
for name,command in [('fmt',['cargo','fmt','--manifest-path','rust/Cargo.toml','--','--check']),('check',['cargo','check','--manifest-path','rust/Cargo.toml','--config','rust/cargo-config.toml','--locked','--offline','--all-targets']),('tests',['cargo','test','--manifest-path','rust/Cargo.toml','--config','rust/cargo-config.toml','--locked','--offline','--all-targets'])]:
 for file,item in manifest['entries'].items():
  if hashlib.sha256((source/file).read_bytes()).hexdigest()!=item['sha256']:raise RuntimeError('Changed tracked bridge input: '+file)
 path=out/('bridge-'+name+'.log');start=time.monotonic()
 with path.open('x') as log: result=subprocess.run(command,cwd=src,env=env,stdout=log,stderr=subprocess.STDOUT)
 records.append(dict(name=name,command=command,cwd=str(src),seconds=time.monotonic()-start,exit_code=result.returncode,log=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
 (out/'bridge-gates.json').write_text(json.dumps({'source_sha':manifest['source_sha'],'vendor_archive_sha256':hashlib.sha256(vendor.read_bytes()).hexdigest(),'preparation':'Extracted the exact tracked vendor archive before Cargo, as package configuration does. Generated vendor files are separate from tracked source identity.','commands':records},indent=2)+'\n')
 print(name,result.returncode,flush=True)
 if result.returncode:raise RuntimeError('Bridge gate failed')
for file,item in manifest['entries'].items():
 if hashlib.sha256((source/file).read_bytes()).hexdigest()!=item['sha256']:raise RuntimeError('Changed tracked bridge input: '+file)
