#!/usr/bin/env python3
"""Bind focused actual-main integration separately from frozen measurements."""
from collections import Counter
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT=Path('<repo>')
WORK=Path('<work>')
COMMIT='7d3c017e1bd284d62be9cc22fcbb2f0d576dff20'
MAIN='5520a5518ea75cc0df2eaa4d003afad8b876c078'
MEASURED='3a02e6d13309441366a7a727fdc934f424ce66c6'
def need(ok,message):
    if not ok:raise RuntimeError(message)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
spec=importlib.util.spec_from_file_location('integration_records',ROOT/'benchmarks/native-operations/run.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
record=module.inventory(WORK/'integration-build','baseline')
need(record['receipt']['base_commit']==COMMIT and record['receipt']['source_patch_sha256']==hashlib.sha256(b'').hexdigest(),'Wrong clean build')
for name,digest in record['source'].items():
    blob=subprocess.check_output(['git','show',COMMIT+':r-package/dtatools/'+name],cwd=ROOT)
    need(hashlib.sha256(blob).hexdigest()==digest and sha(ROOT/'r-package/dtatools'/name)==digest,'Integrated source differs: '+name)
expected={'src/Makevars.rust','src/numeric-arithmetic-general.h','src/numeric-arithmetic-integer-reciprocal.h',
          'tests/testthat/test-arithmetic-payload-lifetime.R','tests/testthat/test-native-arithmetic-kernels.R','tools/native-test-manifest.json'}
changed=subprocess.check_output(['git','diff','--name-only',MAIN,COMMIT,'--','r-package/dtatools'],cwd=ROOT,text=True).splitlines()
need({p.removeprefix('r-package/dtatools/') for p in changed}==expected,'Broadened package delta')
headers={}
for path in (ROOT/'r-package/dtatools/src').glob('numeric-arithmetic*.h'):
    original=subprocess.check_output(['git','show',MEASURED+':r-package/dtatools/src/'+path.name],cwd=ROOT)
    need(path.read_bytes()==original,'Arithmetic header changed after measurement')
    headers[path.name]=sha(path)
rows=list(csv.DictReader((WORK/'integration-focused.csv').open(newline='')))
for row in rows:
    for key in ('error','skipped'):need(row[key] in ('TRUE','FALSE'),'Malformed result boolean')
    for key in ('passed','failed','warning'):need(row[key].isascii() and row[key].isdigit(),'Malformed result count')
totals={k:sum(int(r[k]) if k in ('passed','failed','warning') else r[k]=='TRUE' for r in rows) for k in ('passed','failed','error','skipped','warning')}
need(not any(totals[k] for k in ('failed','error','skipped','warning')),'Focused tests failed')
manifest=json.loads((ROOT/'r-package/dtatools/tools/native-test-manifest.json').read_text())
for entry in [*manifest['helpers'],*manifest['fixtures'],*(e for f in manifest['families'] for e in f['files'])]:
    need(sha(ROOT/'r-package/dtatools'/entry['path'])==entry['sha256'],'Manifest source mismatch')
seen=Counter();observed={}
for row in rows:
    pair=(row['file'],row['test']);seen[pair]+=1;observed[pair+(seen[pair],)]=row
files={r['file'] for r in rows}
need(files=={'test-native-arithmetic-kernels.R','test-arithmetic-payload-lifetime.R'},'Wrong focused files')
blocks=[b for f in manifest['families'] for b in f['blocks'] if b['file'] in files]
need(len(blocks)==len(rows),'Focused block coverage differs')
for block in blocks:
    row=observed[(block['file'],block['test'],block.get('occurrence',1))]
    need(int(row['passed'])>=block['min_pass'] and int(row['warning'])==block['warnings'],'Focused assertions/warnings differ')
probe=json.loads((WORK/'integration-work-count/receipt.json').read_text())
need(probe['commit']==COMMIT and probe['exit_code']==0 and probe['require_proved'] is True,'Structural guard failed')
for name,digest in probe['artifact_sha256'].items():need(sha(WORK/'integration-work-count'/name)==digest,'Changed structural artifact')
recorded={str(p):sha(p) for p in [Path(__file__),WORK/'integration-focused.R',WORK/'integration-focused.csv',WORK/'integration-focused.log',WORK/'integration-work-count/receipt.json']}
result=dict(status='PASS',source_commit=COMMIT,actual_main=MAIN,measured_candidate=MEASURED,
    exact_package_delta=sorted(expected),arithmetic_headers_match_measured=headers,
    build=record,focused_blocks=len(rows),focused_totals=totals,current_source_matches_clean_build=True,
    manifest_sources_match=True,work_count_cases=64,work_count_passed=True,input_sha256=recorded,
    scope='Clean actual-main integration and focused installed arithmetic/lifetime tests. No new measurements or new full-suite/source-archive conformance claim; those remain bound to measured3a02/build-only2c4669.')
(WORK/'integration-binding.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
print('PASS:',totals['passed'],'focused assertions in',len(rows),'blocks; clean main integration bound')
