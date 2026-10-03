from pathlib import Path
import hashlib,json,re,shutil
W=Path(__file__).resolve().parent
C='50e448283231cde1432fa6b30d5d3f6bd0441618'
def require(ok,msg):
    if not ok: raise RuntimeError(msg)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
command=json.loads((W/'conformance-command.json').read_text())
archive=json.loads((W/'conformance.json').read_text())
require(command['commit']==C and command['exit_code']==0,'Conformance command failed')
require(archive['source_commit']==C and all(archive[k] is True for k in ('required_conformance_passed','expected_hashes_from_committed_blobs','checked_source_matches_clean_export','clean_export_matches_source_commit','exact_packaged_source_inventory')),'Archive binding failed')
require(sha(W/'conformance.tar.gz')==archive['source_archive_sha256'],'Archive changed')
for name,key in (('conformance-gate.sh','wrapper_sha256'),('validate-conformance-archive.py','validator_sha256'),('conformance-export/scripts/conformance.sh','original_script_sha256')):
    require(sha(W/name)==command[key],'Conformance controller changed')
log=(W/'conformance.log').read_text();require('R package conformance: PASS (current source built and checked with offline Cargo archive)' in log,'No required PASS marker')
require('Status: 3 WARNINGs, 2 NOTEs' in log,'Unexpected package check status')
source=W/'conformance-preserved/dtatools.Rcheck/tests/testthat.Rout'
text=source.read_text()
counts=re.findall(r'\[ FAIL ([0-9]+) \| WARN ([0-9]+) \| SKIP ([0-9]+) \| PASS ([0-9]+) \]',text)
require(len(counts)==2 and counts[0]==counts[1],'Missing/inconsistent final full-suite summaries')
failed,warnings,skipped,passed=map(int,counts[0]);require((failed,warnings,skipped,passed)==(0,7,0,103481),'Unexpected complete suite count')
out=W/'conformance-testthat.Rout'
if out.exists(): require(out.read_bytes()==source.read_bytes(),'Existing Rout copy changed')
else: shutil.copyfile(source,out)
files=['conformance-command.json','conformance.json','conformance.log','conformance-testthat.Rout','conformance-gate.sh','validate-conformance-archive.py','run-conformance.py','bind-conformance-suite.py']
record={'status':'PASS','source_commit':C,'counts':dict(failed=failed,warnings=warnings,skipped=skipped,passed=passed),'scope':'Post-run receipt binding the preserved full archived test output and original conformance command to its immutable archive validation; no new tests run. Two identical final summaries in testthat output represent one complete suite.','source_archive_sha256':archive['source_archive_sha256'],'packaged_source_files':len(archive['verified_files']),'explicit_buildignore_exclusions':len(archive['deliberately_excluded_by_buildignore']),'artifact_sha256':{f:sha(W/f) for f in files}}
(W/'conformance-suite-binding.json').write_text(json.dumps(record,indent=2)+'\n')
print('PASS',record['counts'],record['packaged_source_files'])
