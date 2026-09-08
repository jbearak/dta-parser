from pathlib import Path
from datetime import datetime, timezone
import csv, hashlib, json, re, subprocess

root=Path('/private/tmp/dta-direct-stage5-validation/root-r460-integration')
repo=Path('/private/tmp/dta-direct-stage5')
review=Path(__file__).parent
prefix='candidate-a2d8b6a-v1'
source='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
tree='b08c77d91bdce67032f13aced90c29d068d6e95a'
clean=Path('/private/tmp/dta-direct-stage5-minimum-preflight/r460-clean-install')
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
def git(*args):return subprocess.check_output(['git',*args],cwd=repo)
expected={
 prefix:'27df31274f66b218ba0f6637d39554169caf379e0914d297b55de71e12e10d63',
 prefix+'-behavior':'649143db58480da0dd32dbf9b84696d4112bb72fa4496ed17005e30b1109225e',
 prefix+'-observe':'4e53bc1de323446e8c60427d34155ed1cb0288959c3babf6ae15c6dc5c3455c5',
 prefix+'-focused':'6b233bae0a5f4b1d64c06d7eccb3a8d0d01a9e5b46ae637674658848f6013dd9'}
records=[]
for name,expected_sha in expected.items():
 folder=root/name;install=name==prefix;receipt=folder/'completed-receipt.json' if install else root/(name+'-receipt.json')
 assert ident(receipt)['sha256']==expected_sha
 r=json.loads(receipt.read_text());m=json.loads((folder/'output-manifest.json').read_text());b=json.loads((folder/'inputs-before.json').read_text());e=json.loads((folder/'execution-result.json').read_text())
 assert r['manifest']==ident(folder/'output-manifest.json')
 for x in m['products']:assert ident(x['path'])==x,x['path']
 excluded={str(folder/'output-manifest.json')}|({str(receipt)} if install else set())
 assert len({x['path'] for x in m['products']})==len(m['products'])
 assert {x['path'] for x in m['products']}=={str(p) for p in folder.rglob('*') if p.is_file()}-excluded
 for x in b['inputs']:assert ident(x['path'])==x,x['path']
 bound={x['resolved'] for x in b['inputs']}
 if install:bound.update(x['resolved'] for x in m['products'])
 if install:
  assert r['status']==e['status']=='complete' and r['revision']==b['revision']==source and r['package_tree']==b['package_tree']==tree
  assert not e['changed_bound_inputs'] and not e['generated_export_files'] and all(x['returncode']==0 for x in e['commands'])
  for x in b['export_inventory']:
   p=Path(x['path']);assert ident(p)=={k:v for k,v in x.items() if k not in ['git_mode','git_blob']}
   rel=p.relative_to(folder/'export').as_posix();assert p.read_bytes()==git('show',source+':'+rel)
   assert git('ls-tree',source,'--',rel).decode().split()[:2]==[x['git_mode'],'blob']
   assert git('rev-parse',source+':'+rel).decode().strip()==x['git_blob']
  archive=json.loads((folder/'built-source-before-install.json').read_text());assert ident(archive['path'])==archive
  installed=(folder/'installed-identity.R').read_text();assert source in installed and tree in installed
  assert 'exports106 and sequential Stata typing' in (folder/'finish-install.log').read_text()
  assert hashlib.md5((folder/'library/dtatools/libs/dtatools.so').read_bytes()).hexdigest() in installed
 else:
  assert r['accepted'] and r['returncode']==e['returncode']==0 and not r['changed_inputs'] and not e['changed_inputs'] and r['integrity_error'] is None and e['integrity_error'] is None
  assert b['source']==source and b['command'][0]==str(clean/'bin/Rscript')
  assert b['environment_overrides']['DTA_ORACLE_LIBRARY']==str(root/prefix/'library')
  if name.endswith('focused'):assert b['environment_overrides']['DTA_MINIMUM_TEST_FILTER']=='dibble|group|mutat|data-table|metadata|owned'
 libraries=b['environment_overrides']['DTA_MINIMUM_LIBRARIES'].split(':')
 for phase in ['before','after']:
  namespaces=list(csv.DictReader((folder/f'guard-namespaces-{phase}.tsv').open(),delimiter='\t'))
  images=(folder/f'loaded-images-{phase}.txt').read_text().splitlines()
  libR=[p for p in images if re.search(r'(^|/)libR[.]dylib$',p)]
  assert libR==[str(clean/'lib/R/lib/libR.dylib')]
  for ns in namespaces:
   assert any(ns['path'].startswith(p+'/') for p in libraries),ns
   assert str((Path(ns['path'])/'DESCRIPTION').resolve(strict=True)) in bound,ns
  if not install:
   assert e['runtime_coverage'][phase]==dict(namespaces=len(namespaces),images=len(images),libR=libR)
  if phase=='after' and not install:
   assert next(x['path'] for x in namespaces if x['name']=='dtatools')==str(root/prefix/'library/dtatools')
   assert next(x['path'] for x in namespaces if x['name']=='dplyr')=='/private/tmp/dta-direct-stage5-minimum-preflight/r460-clean-dplyr-libraries/1.2.1/dplyr'
 records.append(dict(name=name,receipt=ident(receipt),manifest=ident(folder/'output-manifest.json'),products=len(m['products']),product_bytes=sum(x['bytes'] for x in m['products']),bound_inputs=len(b['inputs']),input_bytes=sum(x['bytes'] for x in b['inputs']),runtime_coverage=e.get('runtime_coverage'),scope=b['scope']))
prior=json.loads((review/'root-driver-review-03.json').read_text())
driver=root/'check-candidate-v4.py';old=prior['files'][str(driver)]
assert {k:ident(driver)[k] for k in old}==old
issues=list(csv.DictReader((review/'combined-minimum-issues-01.csv').open()))
skip=[x for x in issues if 'expectation_skip' in x['classes']];warnings=[x for x in issues if 'expectation_warning' in x['classes']]
assert len(skip)==3 and len(warnings)==4
assert sorted(x['message'] for x in skip)==['Reason: R was built without memory profiling','Reason: {arrow} is not installed','Reason: {arrow} is not installed']
expr=list(csv.DictReader((review/'combined-minimum-expression-rows-01.csv').open()));assert len(expr)==22 and sum(int(x['passed']) for x in expr)==187
assert (review/'combined-minimum-record-reader-01.log').read_text().startswith('PASS retained8 public behavior cases,4 expansion shapes')
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='combined_clean_r460_install_and_bounded_integration_evidence_clear',source=source,package_tree=tree,reviewer_script=ident(__file__),records=records,public_behavior_cases=8,expansion_shapes=4,focused=dict(passed=8859,failed=0,errors=0,skips=3,known_warnings=4,filter='dibble|group|mutat|data-table|metadata|owned'),expression_only_subset=dict(test_rows=22,assertions=187,failures=0,errors=0,skips=0,warnings=0),capability_skips=skip,established_warnings=warnings,independent_reader=dict(command=['/opt/homebrew/Cellar/r/4.6.1/bin/Rscript','--vanilla',str(review/'combined-minimum-record-reader-01.R'),str(root),str(review)],exit_code=0,products=[ident(review/p) for p in ['combined-minimum-record-reader-01.R','combined-minimum-record-reader-01.log','combined-minimum-issues-01.csv','combined-minimum-expression-rows-01.csv']]),reviewed_driver=ident(driver),assessment='The expected exact-a2 install and all three check receipts match. All completed products, declared inputs,233 exported Git files, consumed archive and installed provenance are verified. Each before/after image list contains exactly the qualified cleanR4.6.0 libR and namespaces from declared clean libraries, including realdplyr1.2.1 and the exact combined package. Retained RDS and text records agree. Eight public oracles pass; four expansion/fallback forms preserve the explicit factory/event contract and across outputs read their common input values. Late captures retain obsolete-mask errors and three restarting-promise warnings. All8859 focused assertions pass, with three explicitly classified capability skips and four established warnings. The22 expression rows have187 assertions and no issues.',limits=['This is bounded cleanR4.6.0 integration under the recorded filter, not a complete minimum-runtime package check or profiler/allocation qualification.','Two Arrow-package cases and one memory-profiling case were skipped for recorded capabilities; host affected gates remain separate and necessary.','Runtime image checks observe the instrumented R processes before and after execution. They do not freeze OS shared-cache binaries or the fullPython closure and do not claim a complete process-tree image trace.','The reviewer host R process only read serialized results and guard records; it did not rerun any package oracle, expression, native signal, timing or profile operation.','All results retain a2 source and its clean-R DLL. ea031 is only a package-identical progress correction. Final combined package/native/performance and external gates remain separate.'])
result['reviewer_attempt_history']='The initial review script stopped because it expected the host installer exports field in the clean-runtime installed-identity record. The clean installer instead asserts106 exports and records that result in finish-install.log. The corrected review checks that actual recorded schema and the DLL hash. Attempt02 then stopped on the newly installed namespace being a product rather than a pre-install input. Attempt03 checks installer namespaces against its already verified inputs plus products; check-run namespaces still require prebound inputs. Original inputs and outputs were not changed.'
with (review/'combined-minimum-evidence-review-03.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],records=[{k:r[k] for k in ['name','products','bound_inputs']} for r in records],focused_passes=8859,expression_assertions=187,skips=3,warnings=4)))
