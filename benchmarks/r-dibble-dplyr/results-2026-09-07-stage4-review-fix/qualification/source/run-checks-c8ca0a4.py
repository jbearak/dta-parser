import pathlib, subprocess, json, os, hashlib, datetime, time
v = pathlib.Path('/private/tmp/dta-direct-stage4-validation')
source = v / 'source-c8ca0a4'; out = v / 'checks-c8ca0a4'
lib = v / 'candidate-c8ca0a4-library'
sha = 'c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe'
manifest = json.loads((v/'source-c8ca0a4-manifest.json').read_text())
records = []
def guard():
    for name, item in manifest['entries'].items():
        path = source/name
        if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256'] or (path.stat().st_mode & 0o777) != int(item['mode'],8):
            raise RuntimeError('Exact source changed: '+name)
def run(name, command, cwd=source, env=None):
    guard(); start=time.monotonic(); path=out/(name+'.log')
    with path.open('x') as log: result=subprocess.run(command,cwd=cwd,env=env,stdout=log,stderr=subprocess.STDOUT)
    records.append(dict(name=name,command=command,cwd=str(cwd),source_sha=sha,seconds=time.monotonic()-start,exit_code=result.returncode,log=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    (out/'ancillary-current.json').write_text(json.dumps(records,indent=2)+'\n')
    print(name,result.returncode,flush=True)
    guard()
    if result.returncode: raise RuntimeError('Gate failed: '+name)
env=os.environ.copy();env['R_LIBS_USER']=str(lib)
for name,pattern in [('archive-tests','test_check_r_package_archive.py'),('vendor-tests','test_check_r_cargo_vendor.py'),('vendor-rebuild-tests','test_rebuild_r_vendor.py')]:
    run(name,['python3','-m','unittest','discover','-s','scripts','-p',pattern,'-v'])
for name,file in [('cargo-vendor','check-r-cargo-vendor.sh'),('rust-source-hash','test-rust-source-hash.sh')]: run(name,['sh','scripts/'+file])
for name,file in [('corpus-framework','benchmarks/r-corpus-performance/test-framework.R'),('haven-helper-interop','scripts/test-haven-helper-interop.R'),('labelled-interop','scripts/test-labelled-interop.R'),('haven-conformance','scripts/test-haven-conformance.R')]: run(name,['Rscript','--vanilla',file],env=env)
run('roxygen',['Rscript','--vanilla','-e','stopifnot(as.character(packageVersion("roxygen2")) == read.dcf("DESCRIPTION", "Config/roxygen2/version")[[1L]]); roxygen2::roxygenise(".", load_code="source")'],cwd=source/'r-package/dtatools')
run('r-build',['R','CMD','build',str(source/'r-package/dtatools')],cwd=out)
archive=out/'dtatools_0.7.1.tar.gz'
run('r-archive',['sh','scripts/check-r-package-archive.sh',str(archive)])
binary=out/'binary';binary.mkdir();(binary/'library').mkdir()
run('r-binary',['R','CMD','INSTALL','--build','--clean','--library='+str(binary/'library'),str(archive)],cwd=binary)
(out/'ancillary-gates.json').write_text(json.dumps({'source_sha':sha,'source_archive_manifest':str(v/'source-c8ca0a4-manifest.json'),'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'commands':records},indent=2)+'\n')
