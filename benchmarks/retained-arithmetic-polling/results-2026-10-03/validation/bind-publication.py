#!/usr/bin/env python3
"""Bind the polling publication integration separately from measured e1b."""
import csv, hashlib, importlib.util, json, os, re, subprocess
from collections import Counter
from pathlib import Path
ROOT=Path('<publication-repository>')
WORK=Path('<work>')
COMMIT='58630e9914129b3f54197d7ac3207b75e8c10fe8'
PARENT='213ceeee5a0f7953bf0f13316e2207a766dcbb24'
MEASURED='e1b0278b1403b4d8fc2d9a2dfc0c4ddaa7cde3a2'
def need(ok,message):
    if not ok: raise RuntimeError(message)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(name):return json.loads((WORK/name).read_text())
def bound(path,digest):need(sha(path)==digest,'Changed artifact: '+str(path))
env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
def git(*args):return subprocess.check_output(['git','--no-replace-objects',*args],cwd=ROOT,env=env)
spec=importlib.util.spec_from_file_location('records',ROOT/'benchmarks/native-operations/run.py')
records=importlib.util.module_from_spec(spec);spec.loader.exec_module(records)
record=records.inventory(WORK/'publication-build-v1','baseline')
need(record['receipt']['base_commit']==COMMIT and record['receipt']['source_patch_sha256']==hashlib.sha256(b'').hexdigest(),'Wrong clean integration build')
for name,digest in record['source'].items():
    need(hashlib.sha256(git('show',COMMIT+':r-package/dtatools/'+name)).hexdigest()==digest,'Build differs from commit: '+name)
    bound(ROOT/'r-package/dtatools'/name,digest)
expected={'src/numeric-arithmetic-pair-long-float.h','tests/testthat/test-native-arithmetic-parity.R','tests/testthat/test-arithmetic-payload-lifetime.R','tools/native-test-manifest.json'}
changed={p.removeprefix('r-package/dtatools/') for p in git('diff','--name-only',PARENT,COMMIT,'--','r-package/dtatools').decode().splitlines()}
need(changed==expected,'Unexpected package delta')
header='src/numeric-arithmetic-pair-long-float.h'
need(git('show',MEASURED+':r-package/dtatools/'+header)==git('show',COMMIT+':r-package/dtatools/'+header),'Measured polling writer changed')
focused=read('publication-focused-v1/completion.json')
need(focused['status']=='PASS' and focused['source_commit']==COMMIT and focused['test_source_head']==COMMIT and focused['before_after_equal'] is True,'Focused binding failed')
for name,digest in focused['artifacts'].items():bound(WORK/'publication-focused-v1'/name,digest)
before=read('publication-focused-v1/before.json');after=read('publication-focused-v1/after.json')
need(before==after and before['build']==record,'Focused source/build binding changed')
rows=list(csv.DictReader((WORK/'publication-focused-v1/focused.csv').open()))
for row in rows:
    need(all(re.fullmatch(r'[0-9]+',row[k]) for k in ('passed','failed','warning')),'Malformed focused counts')
    need(row['error'] in ('TRUE','FALSE') and row['skipped'] in ('TRUE','FALSE'),'Malformed focused booleans')
    need(row['failed']=='0' and row['warning']=='0' and row['error']=='FALSE' and row['skipped']=='FALSE','Focused failure')
expected_tests=Counter()
for filename in ('test-native-arithmetic-parity.R','test-arithmetic-payload-lifetime.R'):
    source=(ROOT/'r-package/dtatools/tests/testthat'/filename).read_text()
    for title in re.findall(r'^test_that\("([^"\\]*)"',source,re.M):expected_tests[filename,title]+=1
need(len(rows)==focused['blocks']==39 and sum(int(r['passed']) for r in rows)==focused['totals']['passed']==34804,'Focused totals differ')
need(Counter((r['file'],r['test']) for r in rows)==expected_tests and all(n==1 for n in expected_tests.values()),'Incomplete/repeated focused test matrix')
manifest=json.loads((ROOT/'r-package/dtatools/tools/native-test-manifest.json').read_text())
for entry in [*manifest['helpers'],*manifest['fixtures'],*(e for f in manifest['families'] for e in f['files'])]:bound(ROOT/'r-package/dtatools'/entry['path'],entry['sha256'])
probe=read('publication-current-probe-v1/receipt.json')
need(probe['commit']==COMMIT and probe['exit_code']==0 and probe['require_proved'] is True and probe['cases']==18 and probe['semantic_failures']==0 and probe['work_failures']==0,'Current cadence guard failed')
for name,digest in probe['artifact_sha256'].items():bound(WORK/'publication-current-probe-v1'/name,digest)
for name,key in (('work-count.py','controller_sha256'),('work-count.c','probe_sha256'),('cadence.h','cadence_sha256')):bound(ROOT/'benchmarks/retained-arithmetic-polling'/name,probe[key])
archive=read('publication-conformance.json')
flags=('checked_source_matches_clean_export','clean_export_matches_source_commit','exact_packaged_source_inventory','expected_hashes_from_committed_blobs','repository_environment_overrides_removed','required_conformance_passed')
need(archive['source_commit']==COMMIT and all(archive[k] is True for k in flags),'Archive conformance binding failed')
bound(WORK/'publication-conformance.tar.gz',archive['source_archive_sha256'])
archive_tests=WORK/'publication-conformance-retained/dtatools.Rcheck/tests/testthat.Rout'
archive_check=WORK/'publication-conformance-retained/dtatools.Rcheck/00check.log'
results=re.findall(r'\[ FAIL ([0-9]+) \| WARN ([0-9]+) \| SKIP ([0-9]+) \| PASS ([0-9]+) \]',archive_tests.read_text())
need(results and set(results)=={('0','7','0','106933')},'Archive full-suite results differ')
inputs={str(p):sha(p) for p in (Path(__file__),WORK/'publication-focused-v1/completion.json',WORK/'publication-current-probe-v1/receipt.json',WORK/'publication-conformance.json',WORK/'publication-conformance.log',archive_tests,archive_check)}
result=dict(status='PASS',source_commit=COMMIT,parent_commit=PARENT,measured_candidate=MEASURED,exact_package_delta=sorted(expected),measured_writer_byte_identical=True,current_package_matches_clean_build=True,manifest_sources_match=True,build=record,focused_blocks=len(rows),focused_assertions=sum(int(r['passed']) for r in rows),structural_cases=18,archive_full_assertions=106933,archive_test_warnings=7,archive=archive,input_sha256=inputs,scope='Clean integration of the measured polling writer on fixed PR301, focused installed public arithmetic/lifetime tests, maintained actual-header cadence/span guard, and retained source-archive conformance. No new timing or separate full installed-suite claim.')
(WORK/'publication-binding.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
print('PASS',result['focused_assertions'],'focused assertions;',len(rows),'blocks;18 structural cases;retained archive bound')
