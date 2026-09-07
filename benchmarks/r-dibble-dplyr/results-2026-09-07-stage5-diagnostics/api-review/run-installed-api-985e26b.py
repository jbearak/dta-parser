from pathlib import Path
import hashlib,json,os,subprocess,tarfile
root=Path('/private/tmp/dta-direct-stage5-validation/implementation/api-review')
install=Path('/private/tmp/dta-direct-stage5-validation/implementation/candidate-985e26b')
revision='985e26b42590da400466a40ea6a41e7032e96cf4'
script=root/'installed-api-985e26b.R'
helper=install/'export/benchmarks/r-dibble-dplyr/helpers.R'
runner=Path(__file__)
output=root/'installed-api-985e26b-output'
if output.exists():raise RuntimeError('Fresh output required')
output.mkdir()
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def record(path):return {'path':str(path),'bytes':path.stat().st_size,'sha256':sha(path)}
inputs=[runner,script,helper,install/'completed-receipt.json',*sorted((install/'library/dtatools').rglob('*'))]
inputs=[p for p in inputs if p.is_file()]
before=[record(p) for p in inputs]
with (output/'inputs-before.json').open('x') as f:json.dump(before,f,indent=2)
command=['/opt/homebrew/Cellar/r/4.6.1/bin/Rscript','--vanilla',str(script),str(install/'library'),revision,str(helper)]
with (output/'execution.log').open('x') as f:status=subprocess.run(command,stdout=f,stderr=subprocess.STDOUT,check=False).returncode
changed=[r['path'] for r in before if record(Path(r['path']))!=r]
notice=(install/'export/r-package/dtatools/inst/NOTICE').read_bytes()
archive=next((install/'build').glob('dtatools_*.tar.gz'))
with tarfile.open(archive) as tar:
    archived=tar.extractfile('dtatools/inst/NOTICE').read()
notice_matches=notice==archived==(install/'library/dtatools/NOTICE').read_bytes()
result={'revision':revision,'command':command,'exit_code':status,'changed_bound_files':changed,'source_and_installed_notice_match':notice_matches,'notice_sha256':hashlib.sha256(notice).hexdigest(),'source_archive':record(archive),'scope':'Bounded installed API and NOTICE-distribution check. Exact installer receipt supplies artifact source identity. Runtime and dependency closures are not newly frozen by this API probe; full package/minimum-runtime/performance/external gates remain separate.'}
with (output/'result.json').open('x') as f:json.dump(result,f,indent=2)
products=[record(p) for p in sorted(output.iterdir()) if p.is_file()]
with (output/'output-manifest.json').open('x') as f:json.dump(products,f,indent=2)
with (output/'receipt.json').open('x') as f:json.dump({'result':record(output/'result.json'),'manifest':record(output/'output-manifest.json')},f,indent=2)
if status or changed or not notice_matches:raise RuntimeError('Bounded API check failed; retained all outputs')
print(json.dumps(result,indent=2))
