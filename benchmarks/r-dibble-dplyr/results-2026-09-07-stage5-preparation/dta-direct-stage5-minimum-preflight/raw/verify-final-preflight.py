"""Verify pristine sources and bind final isolated runtime/build evidence."""
from pathlib import Path
import hashlib,json,subprocess,tarfile,datetime
root=Path('/private/tmp/dta-direct-stage5-minimum-preflight')
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def source_archive(archive,base):
 count=0
 with tarfile.open(archive) as tar:
  for member in tar:
   if not member.isfile(): continue
   expected=tar.extractfile(member).read();path=base/member.name
   if path.read_bytes()!=expected: raise RuntimeError(f'Source changed: {path}')
   count+=1
 return count
sources={}
sources['R-4.6.0']=source_archive(root/'r46-source/R-4.6.0.tar.gz',root/'r46-source')
for item in json.loads((root/'manifests/dplyr-clean-git-archives.json').read_text()):
 sources['dplyr-'+item['version']]=source_archive(root/item['archive'],root/'dplyr-clean-pristine'/item['version'])
expected_header='6075da78d762507f235b3c654ba9434dd05193bd17dea13714204416f0a4757c'
if sha(root/'r460-clean-install/lib/R/include/Rinternals.h')!=expected_header:
 raise RuntimeError('Installed R header mismatch')
for suffix in ['before','after']:
 p=root/f'logs/r460-clean-loaded-library-{suffix}.log'
 if 'PASS: exactly one loaded libR, from the isolated clean R4.6.0:' not in p.read_text():
  raise RuntimeError(f'Missing loaded-runtime guard: {p}')
installs=json.loads((root/'manifests/r460-clean-dplyr-installs.json').read_text())
if len(installs)!=7: raise RuntimeError('Incomplete release matrix')
for x in installs:
 if x['exit_code']!=(0 if x['version']=='1.2.1' else 1): raise RuntimeError(x)
 if sha(root/x['log'])!=x['log_sha256']: raise RuntimeError('Install log changed')
 if x['version']=='1.2.1' and (x['smoke_exit_code']!=0 or sha(root/x['smoke_log'])!=x['smoke_sha256']): raise RuntimeError('Smoke mismatch')
files={}
for directory in ['r460-clean-install','r460-clean-dependencies','r460-clean-dplyr-libraries/1.2.1']:
 for path in sorted((root/directory).rglob('*')):
  if path.is_file(): files[str(path.relative_to(root))]=sha(path)
previous=json.loads((root/'manifests/final-installed-files.json').read_text())
if files!=previous: raise RuntimeError('Previously qualified installed files changed')
binary_archive=root/'downloads/binary-preflight/dplyr-cran-r43-1.1.4.tgz'
binary_sha='f78dbdaaeebed0c314b54a8c632fcba5952954ada924286eceeadbec691c9876'
if sha(binary_archive)!=binary_sha: raise RuntimeError('Older binary archive changed')
binary_original_count=source_archive(binary_archive,root/'older-binary-r43-library')
binary_log=(root/'logs/older-binary-r43-on-r460-smoke.log').read_text()
if binary_log.count('PASS: exactly one loaded libR, from the isolated clean R4.6.0:')!=2:
 raise RuntimeError('Older binary single-runtime guards missing')
if 'Symbol not found: _R_shallow_duplicate_attr' not in binary_log:
 raise RuntimeError('Older binary loader result changed')
(root/'manifests/final-installed-files.json').write_text(json.dumps(files,indent=2)+'\n')
logs={str(p.relative_to(root)):sha(p) for p in sorted((root/'logs').glob('*.log')) if p.name != 'final-preflight-verification.log'}
recipes={str(p.relative_to(root)):sha(p) for p in root.glob('*.py')}
recipes.update({str(p.relative_to(root)):sha(p) for p in root.glob('*.R')})
recipes.update({str(p.relative_to(root)):sha(p) for p in (root/'runtime-clean-probe').glob('*') if p.is_file()})
result={'time_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'qualified_runtime':'R4.6.0 revision89956, specific external-library paths, exactly one loaded libR before and after dplyr',
 'qualified_pristine_source_installable_dplyr_minimum_in_declared_range':'1.2.1',
 'binary_scope':'One official R4.3 dplyr1.1.4 binary fails to load on the clean R4.6.0; this does not prove all older installed versions unusable.',
 'older_binary_original_files_unchanged':binary_original_count,
 'older_binary_disposition_sha256':sha(root/'manifests/older-binary-disposition.json'),
 'source_original_files_unchanged':sources,
 'installed_Rinternals_sha256':expected_header,
 'installed_file_count':len(files),'installed_files_manifest_sha256':sha(root/'manifests/final-installed-files.json'),
 'r460_matrix':installs,'log_sha256':logs,'recipe_sha256':recipes,
 'runtime_limit':'Minimal source build without graphics frontends, ICU, recommended packages or memory profiling; no performance or full dtatools adapter claim.',
 'rejected_initial_attempt':'manifests/initial-runtime-disposition.json'}
(root/'manifests/final-qualification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'sources':sources,'installed_files':len(files),'release_results':[(x['version'],x['exit_code'],x.get('smoke_exit_code')) for x in installs],'guards':'PASS'},indent=2))
