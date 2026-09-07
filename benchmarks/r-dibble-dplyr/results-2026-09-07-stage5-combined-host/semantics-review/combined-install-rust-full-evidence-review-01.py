from pathlib import Path
from datetime import datetime, timezone
import collections, csv, hashlib, json, re, subprocess

root=Path('/private/tmp/dta-direct-stage5-validation/implementation')
repo=Path('/private/tmp/dta-direct-stage5')
review=Path(__file__).parent
source='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
tree='b08c77d91bdce67032f13aced90c29d068d6e95a'
def git(*args):return subprocess.check_output(['git',*args],cwd=repo)
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
assert git('rev-parse',source+':r-package/dtatools').decode().strip()==tree
assert git('rev-parse','ea031bec2df4d6711f1214b5dd3d00ebf029b3f1:r-package/dtatools').decode().strip()==tree
records=[]
for name,mn,rn,expected in [
 ('candidate-combined-01','output-manifest.json','completed-receipt.json','fe4d3dfdeba63d6401becb4f7f41383812b7545383c86a4c0abf17b3c290a38e'),
 ('rust-combined-01','manifest.json','receipt.json','d919155ad571711c265212474c82dd706046c3f437d26ba134626ba72e211b68'),
 ('full-combined-01','manifest.json','receipt.json','a8901fe26df3acdecaa4d1a151aa6f0d9f9f654a7f09bccdcb8fa7d6d5352cec')]:
 folder=root/name;receipt=ident(folder/rn);assert receipt['sha256']==expected
 r=json.loads((folder/rn).read_text());m=json.loads((folder/mn).read_text());b=json.loads((folder/'inputs-before.json').read_text());e=json.loads((folder/'execution-result.json').read_text())
 assert r['status']==e['status']=='complete' and not r.get('changed_inputs',r.get('changed_bound_inputs')) and not e.get('changed_inputs',e.get('changed_bound_inputs'))
 assert r['manifest']==ident(folder/mn)
 commands=e.get('commands',e.get('records'));assert all(x.get('returncode',x.get('exit_code'))==0 for x in commands)
 assert len({x['path'] for x in m['products']})==len(m['products'])
 for x in m['products']:assert ident(x['path'])==x,x['path']
 assert {x['path'] for x in m['products']}=={str(p) for p in folder.rglob('*') if p.is_file()}-{str(folder/mn),str(folder/rn)}
 for x in b['inputs']:assert ident(x['path'])==x,x['path']
 if name=='candidate-combined-01':
  assert r['revision']==b['revision']==source and r['package_tree']==b['package_tree']==tree and not e['generated_export_files']
  for x in b['export_inventory']:
   p=Path(x['path']);assert ident(p)=={k:v for k,v in x.items() if k not in ['git_mode','git_blob']}
   rel=p.relative_to(folder/'export').as_posix();assert p.read_bytes()==git('show',source+':'+rel)
   assert git('ls-tree',source,'--',rel).decode().split()[:2]==[x['git_mode'],'blob']
   assert git('rev-parse',source+':'+rel).decode().strip()==x['git_blob']
  archive=json.loads((folder/'built-source-before-install.json').read_text());assert ident(archive['path'])==archive
  installed=(folder/'installed-identity.R').read_text();assert 'exports = 106L' in installed and source in installed and tree in installed
 else:
  assert r['source_sha']==r['runner_sha']==b['source_sha']==b['runner_sha']==source
  preflight=(folder/'preflight-identity.R').read_text();assert source in preflight and tree in preflight
  dll=root/'candidate-combined-01/library/dtatools/libs/dtatools.so'
  assert str(dll) in preflight and hashlib.md5(dll.read_bytes()).hexdigest() in preflight
  for rel in ['R/dibble-expressions.R','R/output-container.R','src/init.c','tests/testthat/helper-generation-interrupt.R','tests/testthat/test-dibble-expressions.R','tests/testthat/test-mutate-data.R']:
   p='r-package/dtatools/'+rel;assert (folder/'source'/p).read_bytes()==git('show',source+':'+p)
 records.append(dict(name=name,receipt=receipt,manifest=ident(folder/mn),products=len(m['products']),product_bytes=sum(x['bytes'] for x in m['products']),bound_inputs=len(b['inputs']),input_bytes=sum(x['bytes'] for x in b['inputs']),commands=[dict(label=x['label'],command=x['command'],exit_code=x.get('returncode',x.get('exit_code'))) for x in commands]))
rust=root/'rust-combined-01'
summaries=re.findall(r'^test result: ok\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;', (rust/'tests.log').read_text(),re.M)
assert len(summaries)==14 and sum(int(x[0]) for x in summaries)==278 and all(all(int(n)==0 for n in x[1:]) for x in summaries)
warnings=lambda p:[line for line in p.read_text().splitlines() if line.startswith('warning:')]
package_warnings=warnings(rust/'package.log');assert len(package_warnings)==11 and package_warnings==warnings(root/'rust-final-01/package.log')
assert [x['label'] for x in records[1]['commands']]==['preflight','fmt','clippy','tests','docs','package']
for log in ['clippy.log','tests.log','docs.log']:assert not warnings(rust/log)
rows=list(csv.DictReader((root/'full-combined-01/tests.csv').open()))
totals={k:sum(int(r[k]) for r in rows) for k in ['failed','warning','passed']}
totals.update({k:sum(r[k]=='TRUE' for r in rows) for k in ['error','skipped']})
assert totals==dict(failed=0,warning=4,passed=16750,error=0,skipped=0)
names=['native generation interrupts leave reference state unchanged','POSIX interrupts reach an active native generation checkpoint','generation interrupt controls disarm after validation errors']
selected=[r for r in rows if r['test'] in names];assert len(selected)==3
assert {r['test']:int(r['passed']) for r in selected}==dict(zip(names,[67,67,6]))
capture=[r for r in rows if r['test']=='removed and re-added column generations retain values and expire'];assert len(capture)==1 and capture[0]['passed']=='8'
old=list(csv.DictReader((root.parent/'mask-names/full-01/tests.csv').open()))
keys=['file','context','test','nb','failed','skipped','error','warning','passed']
as_rows=lambda data:collections.Counter(tuple(r[k] for k in keys) for r in data if r['test'] not in names)
assert as_rows(rows)==as_rows(old)
old_interrupt=[r for r in old if r['test']==names[0]];assert len(old_interrupt)==1 and old_interrupt[0]['passed']=='22'
install_log=(root/'candidate-combined-01/install.log').read_text()
linker=[re.sub(r'^.*\) was built',') was built',x) for x in install_log.splitlines() if x.startswith('ld: warning:')]
baseline_linker=[re.sub(r'^.*\) was built',') was built',x) for x in (root.parent/'mask-names/candidate-01/install.log').read_text().splitlines() if x.startswith('ld: warning:')]
assert linker==baseline_linker
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='combined_exact_install_rust_host_full_evidence_clear',source=source,runner=source,package_tree=tree,reviewer_script=ident(__file__),source_review=ident(review/'combined-source-review-ea031-01.json'),records=records,rust=dict(gates=5,test_summaries=len(summaries),passed=278,failed=0,ignored=0,package_warning_count=11,package_warnings=package_warnings),full=dict(totals=totals,native_tests=selected,remove_readd_test=capture[0],all_other_rows_identical_to_ad976=True),install_linker_warning_count=len(linker),assessment='The exact combined installation, five Rust gates and full host R suite are independently bound to source/runner a2d8b6a and package tree b08. All completed products, manifests, expected receipts and declared input identities match. All234 exported Git file records and the consumed built source archive match. Public exports remain106. Full R results reproduce16750 passes with zero failures/errors/skips and four established warnings, including67 deterministic native checks,67 readiness/SIGINT checks,six disarm checks and eight remove/re-add/capture assertions. All other test result rows and assertion counts match ad976. Rust278 tests pass; the11 package warnings exactly match prior baseline warning text. Install linker warning categories/count match the prior ad976 installation.',limits=['The ea031 change is outside the package; these executions retain exact a2 source/runner identities.','This report does not clear pending combined R CMD check/package/native allocation or minimum-runtime gates, nor final performance, memory/write-cost, external review, CI or normal merge.','No tests, compilation, profiling or timing were rerun by this reviewer. Original products and declared input files were read and rehashed; retained CSV/log summaries were independently recalculated.','Full OS dylib, SDK and Python runtime closures remain outside the recorded input scope. Prior diagnostic variant results remain distinct.'])
with (review/'combined-install-rust-full-evidence-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],records=[{k:r[k] for k in ['name','products','bound_inputs']} for r in records],rust_tests=278,full=totals,install_linker_warnings=len(linker))))
