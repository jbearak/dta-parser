"""Bind completed archive-wide and focused integration qualification; no tests."""
import csv,hashlib,json,os,re,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent;WORK=HERE.parent
REPO=Path('<private-tmp>/dta-long-float-addition');BUILD=WORK/'publication-build-v1'
PIN='958082e4e9eb3fd78be6a81f1e70b6fabca27d9f'
PARENT='62fe0a17b3007e8359e75e9dcdb33c1e685bd64f'
MEASURED='3de25ecca674a3ffed3618223a011f499383bd57'
def need(c,m):
 if not c:raise RuntimeError(m)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
git_env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
def git(*args):return subprocess.check_output(['git','--no-replace-objects',*args],cwd=REPO,env=git_env)
inputs={}
def bind(p):inputs[str(p)]=sha(p)
need(git('rev-parse','HEAD').decode().strip()==PIN,'Integration HEAD changed')
need(git('status','--porcelain').strip()==b'','Integration checkout changed')
receipt=read(BUILD/'build-receipt.json')
need(receipt['base_commit']==PIN and receipt['exit_code']==0 and receipt['pre_post_source_equal'] is True,'Wrong or failed clean build')
need((BUILD/'source.patch').read_bytes()==b'','Build has source patch')
for folder,key in ((BUILD/'source','source_inventory'),(BUILD/'library/dtatools','installed_inventory')):
 actual={p.relative_to(folder).as_posix():sha(p) for p in folder.rglob('*') if p.is_file()}
 need(actual==receipt[key],'Build inventory changed: '+key)
for name,digest in receipt['source_inventory'].items():
 need(hashlib.sha256(git('show',PIN+':r-package/dtatools/'+name)).hexdigest()==digest,'Build source not immutable commit: '+name)
bind(BUILD/'build-receipt.json');bind(BUILD/'source.patch');bind(BUILD/'input-record.json')
expected_delta={
 'r-package/dtatools/src/numeric-arithmetic-general.h',
 'r-package/dtatools/src/numeric-arithmetic-pair-long-float.h',
 'r-package/dtatools/src/numeric-arithmetic-pair.h',
 'r-package/dtatools/tests/testthat/test-native-arithmetic-parity.R',
 'r-package/dtatools/tests/testthat/test-arithmetic-payload-lifetime.R',
 'r-package/dtatools/tools/native-test-manifest.json'}
need(set(git('diff','--name-only',PARENT,PIN,'--','r-package/dtatools').decode().splitlines())==expected_delta,'Unexpected integration package delta')
for name in ('numeric-arithmetic-pair-long-float.h','numeric-arithmetic-pair.h'):
 path='r-package/dtatools/src/'+name
 need(git('show',MEASURED+':'+path)==git('show',PIN+':'+path),'Measured pair implementation changed')
archive=read(HERE/'conformance.json')
need(archive['source_commit']==PIN,'Wrong checked source archive')
for flag in ('checked_source_matches_clean_export','clean_export_matches_source_commit','exact_packaged_source_inventory','expected_hashes_from_committed_blobs','repository_environment_overrides_removed','required_conformance_passed'):
 need(archive[flag] is True,'Archive gate missing: '+flag)
need(sha(HERE/'conformance.tar.gz')==archive['source_archive_sha256'],'Checked archive changed')
launch=read(HERE/'conformance-command.json')
need(launch['commit']==PIN and launch['exit_code']==0 and launch['cwd']==str(HERE/'conformance-export'),'Wrong conformance launch')
for file,key in (('conformance-gate.sh','wrapper_sha256'),('validate-conformance-archive.py','validator_sha256')):
 need(sha(HERE/file)==launch[key],'Conformance controller changed');bind(HERE/file)
need(sha(HERE/'conformance-export/scripts/conformance.sh')==launch['original_script_sha256'],'Original conformance source changed')
routs=list((HERE/'conformance-preserved').glob('*.Rcheck/tests/testthat.Rout'))
need(len(routs)==1,'Missing or ambiguous complete archive test output')
text=routs[0].read_text()
counts=re.findall(r'\[ FAIL (\d+) \| WARN (\d+) \| SKIP (\d+) \| PASS (\d+) \]',text)
need(len(counts)==2 and len(set(counts))==1,'Missing or inconsistent archive suite summaries')
failed,warnings,skipped,passed=map(int,counts[0])
need(failed==0 and skipped==0 and warnings==7 and passed>=104518,'Incomplete/failed archive suite')
# test_check is unmodified and selects the complete package tests. This is not
# a claim of per-family native-profile runner telemetry.
need((BUILD/'source/tests/testthat.R').read_text()=='library(testthat)\nlibrary(dtatools)\n\ntest_check("dtatools")\n','Archive test entry differs')
manifest=read(BUILD/'source/tools/native-test-manifest.json')
for family in manifest['families']:
 for entry in family['files']:
  need(sha(BUILD/'source'/entry['path'])==entry['sha256'],'Native manifest file differs')
focused=WORK/'publication-focused-v1';fc=read(focused/'completion.json')
need(fc['status']=='PASS' and fc['source_commit']==PIN and fc['test_source_head']==PIN and fc['before_after_equal'] is True,'Focused integration failed')
need(fc['blocks']==37 and fc['totals']=={'passed':34288,'failed':0,'warning':0},'Focused integration matrix differs')
with (focused/'focused.csv').open(newline='') as stream:rows=list(csv.DictReader(stream))
need(len(rows)==37 and len({(r['file'],r['test']) for r in rows})==37,'Focused block matrix incomplete')
for row in rows:
 need(all(re.fullmatch('[0-9]+',row[key]) for key in ('passed','failed','warning')),'Invalid focused count')
 need(row['failed']=='0' and row['warning']=='0' and row['error']=='FALSE' and row['skipped']=='FALSE','Focused failure or skip')
need(sum(int(row['passed']) for row in rows)==34288,'Focused assertion count differs')
for file,digest in fc['artifacts'].items():need(sha(focused/file)==digest,'Focused bound artifact changed')
need(read(focused/'before.json')==read(focused/'after.json'),'Focused identity changed')
guards=read(HERE/'guards.json');need(guards['status']=='PASS' and guards['source_commit']==PIN,'Guard source differs')
need(guards['runner_sha256']==sha(HERE/'run-guards.py'),'Guard runner changed')
files=('benchmarks/long-float-addition/test-run.py','benchmarks/long-float-addition/test-work-count.py','scripts/test_native_manifest.py','scripts/test_arithmetic_dependencies.py')
need(set(guards['files'])==set(files) and len(guards['commands'])==8,'Guard matrix incomplete')
for name in files:need(guards['files'][name]==sha(REPO/name),'Guard source changed')
expected=[([*mode,file]) for file in files for mode in ([],['-O'])]
need([r['command'][1:] for r in guards['commands']]==expected,'Guard modes differ')
for row in guards['commands']:
 need(row['returncode']==0 and row['cwd']==str(REPO) and sha(HERE/row['log'])==row['log_sha256'],'Guard failed or log changed');bind(HERE/row['log'])
probe=read(WORK/'publication-structural-v1/receipt.json')
need(probe['commit']==PIN and probe['cases']==162 and probe['exit_code']==0 and probe['semantic_failures']==0 and probe['work_failures']==0 and probe['require_proved'] is True and probe['source_before_after_equal'] is True,'Current-source structural gate failed')
for name,key in (('work-count.py','controller_sha256'),('work-count.c','probe_sha256')):
 need(sha(REPO/'benchmarks/long-float-addition'/name)==probe[key],'Structural source changed')
for name,digest in probe['artifact_sha256'].items():need(sha(WORK/'publication-structural-v1'/name)==digest,'Structural artifact changed')
for p in (HERE/'conformance.json',HERE/'conformance.log',HERE/'conformance-command.json',routs[0],HERE/'guards.json',HERE/'run-guards.py',WORK/'publication-structural-v1/receipt.json',focused/'completion.json',focused/'focused.csv',focused/'before.json',focused/'after.json'):
 bind(p)
record=dict(status='PASS',integration_commit=PIN,parent_commit=PARENT,measured_commit=MEASURED,package_delta=sorted(expected_delta),archive_suite=dict(passed=passed,failed=failed,warnings=warnings,skipped=skipped),focused_blocks=37,focused_assertions=34288,guards=8,structural_cases=162,input_sha256=inputs,binder_sha256=sha(Path(__file__)),scope='Clean integrated build, complete retained-archive testthat suite with zero skips, exact native-manifest source hashes, focused installed tests and current-header structural/protocol gates. The archive suite is not a separate per-family native-profile telemetry run. Measured3de performance bindings remain separate.')
(HERE/'integration-binding.json').write_text(json.dumps(record,indent=2,sort_keys=True)+'\n')
print('PASS combined integration binding',record['archive_suite'])
