from collections import Counter
import csv,hashlib,importlib.util,json,os,subprocess
from pathlib import Path
W=Path(__file__).resolve().parent
R=Path('<repository>')
C='c5d5aebc5a70fde0bfa67816e1ab2e44bd812b92'
P='2b18bda398ba0b850238cb4dc9f0a81e069b236b'
F='50e448283231cde1432fa6b30d5d3f6bd0441618'
def need(ok,msg):
 if not ok:raise RuntimeError(msg)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
def git(*args):return subprocess.check_output(['git','--no-replace-objects',*args],cwd=R,env=env)
spec=importlib.util.spec_from_file_location('reciprocal_integration_inventory',R/'benchmarks/native-operations/run.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
record=module.inventory(W/'integration-candidate','baseline')
need(record['receipt']['base_commit']==C and record['receipt']['source_patch_sha256']==hashlib.sha256(b'').hexdigest(),'Wrong clean integration build')
for name,digest in record['source'].items():
 blob=git('show',C+':r-package/dtatools/'+name)
 need(hashlib.sha256(blob).hexdigest()==digest and sha(R/'r-package/dtatools'/name)==digest,'Current source/build/blob mismatch: '+name)
expected={'src/numeric-arithmetic-float-reciprocal.h','src/numeric-arithmetic-general.h','tests/testthat/test-arithmetic-payload-lifetime.R','tests/testthat/test-native-arithmetic-parity.R','tools/native-test-manifest.json'}
changed=git('diff','--name-only',P,C,'--','r-package/dtatools').decode().splitlines()
need({p.removeprefix('r-package/dtatools/') for p in changed}==expected,'Broadened package delta')
header=R/'r-package/dtatools/src/numeric-arithmetic-float-reciprocal.h'
need(header.read_bytes()==git('show',F+':r-package/dtatools/src/'+header.name),'Accepted float header changed')
parent_headers={}
for path in (R/'r-package/dtatools/src').glob('numeric-arithmetic*.h'):
 if path.name in ('numeric-arithmetic-general.h','numeric-arithmetic-float-reciprocal.h'):continue
 need(path.read_bytes()==git('show',P+':r-package/dtatools/src/'+path.name),'Parent arithmetic header changed')
 parent_headers[path.name]=sha(path)
general=(R/'r-package/dtatools/src/numeric-arithmetic-general.h').read_text()
for fragment in ('#include "numeric-arithmetic-float-reciprocal.h"\n','    arithmetic_float_reciprocal_proof reciprocal_proof;\n    if (arithmetic_float_reciprocal_prove(\n            left, right, length, operation, output->kind, &reciprocal_proof))\n        return arithmetic_float_reciprocal_write(&reciprocal_proof, length, output);\n'):
 need(general.count(fragment)==1,'Nonunique float integration site');general=general.replace(fragment,'')
need(general.encode()==git('show',P+':r-package/dtatools/src/numeric-arithmetic-general.h'),'Parent producer differs beyond float dispatch')
rows=list(csv.DictReader((W/'integration-focused.csv').open()))
for row in rows:
 for k in ('passed','failed','warning'):need(row[k].isascii() and row[k].isdigit(),'Invalid focused count')
 for k in ('error','skipped'):need(row[k] in ('TRUE','FALSE'),'Invalid focused status')
totals={k:sum(int(r[k]) if k in ('passed','failed','warning') else r[k]=='TRUE' for r in rows) for k in ('passed','failed','error','skipped','warning')}
need(all(totals[k]==0 for k in ('failed','error','skipped','warning')),'Focused suite failed')
manifest=json.loads((R/'r-package/dtatools/tools/native-test-manifest.json').read_text())
for entry in [*manifest['helpers'],*manifest['fixtures'],*(e for family in manifest['families'] for e in family['files'])]:need(sha(R/'r-package/dtatools'/entry['path'])==entry['sha256'],'Manifest source mismatch')
seen=Counter();observed={}
for row in rows:
 pair=row['file'],row['test'];seen[pair]+=1;observed[pair+(seen[pair],)]=row
files={r['file'] for r in rows};need(files=={'test-native-arithmetic-kernels.R','test-native-arithmetic-parity.R','test-arithmetic-payload-lifetime.R'},'Wrong focused files')
blocks=[b for family in manifest['families'] for b in family['blocks'] if b['file'] in files]
need(len(blocks)==len(rows),'Incomplete focused manifest coverage')
for block in blocks:
 row=observed[(block['file'],block['test'],block.get('occurrence',1))]
 need(int(row['passed'])>=block['min_pass'] and int(row['warning'])==block['warnings'],'Focused obligation failed')
need('Ran 7 tests' in (W/'integration-manifest.log').read_text() and (W/'integration-manifest.log').read_text().rstrip().endswith('OK'),'Manifest guards incomplete')
paths=[Path(__file__),W/'integration-focused.R',W/'integration-focused.csv',W/'integration-focused.log',W/'integration-manifest.log']
result={'status':'PASS','source_commit':C,'parent_integer_pr_head':P,'accepted_final_test_source':F,'accepted_runtime_header_sha256':sha(header),'parent_arithmetic_headers_unchanged':parent_headers,'exact_package_delta':sorted(expected),'build':record,'focused_blocks':len(rows),'focused_totals':totals,'manifest_source_and_block_checks':True,'manifest_guard_count':7,'input_sha256':{str(p):sha(p) for p in paths},'post_run_launch_record':{'cwd':str(R),'command':['Rscript','--vanilla',str(W/'integration-focused.R'),str(W/'integration-candidate/library'),str(W/'integration-focused.csv'),str(R/'r-package/dtatools/tests/testthat')],'scope':'Transparently recorded after completion from the actual tool invocation, not a contemporaneous launch receipt.'},'scope':'Source-bound stacked integration build and focused three-file tests. No new timing, full-suite or archive-conformance claim; full conformance remains bound to final50e before stacking.'}
(W/'integration-binding.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');print('PASS',totals,'blocks',len(rows))
