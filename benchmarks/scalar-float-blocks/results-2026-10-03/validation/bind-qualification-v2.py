#!/usr/bin/env python3
"""Bind scalar qualification to immutable source and the installed libraries."""
from collections import Counter
import csv, hashlib, importlib.util, json, shutil, subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=Path('<scalar-block-checkout>')
BUILDS={'baseline':Path('<arithmetic-evidence>/integration-candidate'),'candidate':HERE/'candidate-v2'}
COMMITS={'baseline':'dbcf75cbfe589b5ac2a78166d1e436faa7bbb896','candidate':'2e512880b15ea5ef8d56c65a4916af3ad71fb928'}
def require(value,message):
    if not value: raise RuntimeError(message)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
spec=importlib.util.spec_from_file_location('scalar_acceptance',HERE/'acceptance-controller/general-run.py')
run=importlib.util.module_from_spec(spec);spec.loader.exec_module(run)
records={role:run.RECORDS.inventory(build,json.loads((build/'build-receipt.json').read_text())['variant']) for role,build in BUILDS.items()}
for role,record in records.items():
    require(record['receipt']['base_commit']==COMMITS[role],'Wrong source commit')
    require((BUILDS[role]/'source.patch').read_bytes()==b'','Source snapshot has a patch')
    for name,digest in record['source'].items():
        blob=subprocess.check_output(['git','show',COMMITS[role]+':r-package/dtatools/'+name],cwd=ROOT)
        require(hashlib.sha256(blob).hexdigest()==digest,'Immutable Git blob differs: '+name)
runtime=run.worker_runtime(Path(shutil.which('Rscript')).resolve(strict=True))
require({r['receipt']['toolchain']['R_runtime_sha256'] for r in records.values()}=={runtime['R_runtime_sha256']},'Worker/build runtime mismatch')
qual={role:list(csv.DictReader((HERE/('original-'+role+('-v2' if role=='candidate' else '')+'-qualification.csv')).open())) for role in BUILDS}
for role,rows in qual.items():
    require(Counter(tuple(r[k] for k in run.FIELDS) for r in rows)==Counter({k:1 for k in run.EXPECTED}),'Incomplete untimed matrix')
    for row in rows:
        require(row['cpu']=='NA' and row['wall']=='NA' and row['iterations']=='1','Qualification contains timings')
        require(row['native_calls']==('0' if row['representation']=='ordinary' else '1'),'Wrong native route')
require(qual['baseline']==qual['candidate'],'Before/after semantic qualification differs')
full=list(csv.DictReader((HERE/'candidate-v2-full.csv').open()))
for row in full:
    for key in ('error','skipped'):require(row[key] in ('TRUE','FALSE'),'Malformed full-suite boolean')
    for key in ('passed','failed','warning'):require(row[key].isascii() and row[key].isdigit(),'Malformed full-suite count')
totals={key:sum(int(row[key]) if key in ('passed','failed','warning') else row[key]=='TRUE' for row in full) for key in ('passed','failed','error','skipped','warning')}
require(not any(totals[k] for k in ('failed','error','skipped')),'Full suite failed or skipped')
package=BUILDS['candidate']/'source';manifest=json.loads((package/'tools/native-test-manifest.json').read_text())
for entry in [*manifest['helpers'],*manifest['fixtures'],*(e for f in manifest['families'] for e in f['files'])]:require(sha(package/entry['path'])==entry['sha256'],'Manifest source hash mismatch')
seen=Counter();observed={}
for row in full:
    key=(row['file'],row['test']);seen[key]+=1;observed[key+(seen[key],)]=row
blocks=[b for family in manifest['families'] for b in family['blocks']]
require(len(blocks)==len(full),'Manifest block count differs')
for block in blocks:
    row=observed[(block['file'],block['test'],block.get('occurrence',1))]
    require(int(row['passed'])>=block['min_pass'],'Observed assertions below manifest minimum')
    if block['skip']=='forbid':require(int(row['warning'])==block['warnings'],'Unexpected manifest warnings')
require('R package conformance: PASS' in (HERE/'candidate-v2-conformance.log').read_text(),'Required packaged conformance did not pass')
archive=json.loads((HERE/'candidate-v2-conformance.json').read_text())
require(archive['source_commit']==COMMITS['candidate'],'Wrong conformance source commit')
for key in ('checked_source_matches_clean_export','clean_export_matches_source_commit','exact_packaged_source_inventory','expected_hashes_from_committed_blobs','repository_environment_overrides_removed','required_conformance_passed'):
    require(archive[key] is True,'Conformance binding is not an exact PASS: '+key)
require(archive['source_archive_sha256']==sha(HERE/'candidate-v2-conformance.tar.gz'),'Retained archive hash differs')
inputs=[Path(__file__).resolve(),HERE/'candidate-v2-full.csv',HERE/'candidate-v2-full.log',HERE/'candidate-v2-focused.csv',HERE/'baseline-focused.csv',HERE/'candidate-v2-conformance.log',HERE/'candidate-v2-conformance.json',HERE/'candidate-v2-codegen-binding.json',HERE/'work-count-red.log',HERE/'work-count-green.log',HERE/'original-baseline-qualification.csv',HERE/'original-candidate-v2-qualification.csv']
result={'status':'PASS','scope':'Untimed scalar qualification only; no performance claim.','commits':COMMITS,'builds':records,'runtime':runtime,'full_suite':{'totals':totals,'blocks':len(blocks)},'original_cases_per_build':len(qual['candidate']),'archive_binding_sha256':sha(HERE/'candidate-v2-conformance.json'),'input_sha256':{str(p):sha(p) for p in inputs}}
(HERE/'qualification-v2-binding.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
print(json.dumps({'status':'PASS','full_suite':totals,'blocks':len(blocks),'original_cases_per_build':len(qual['candidate'])}))
