from pathlib import Path
import csv, hashlib, json, subprocess
from datetime import datetime, timezone

repo=Path('/private/tmp/dta-direct-stage5-repair-guard')
root=Path('/private/tmp/dta-direct-stage5-validation/repair-guard')
out=Path(__file__).with_suffix('.json')
base='57309d40433a92d99849fefa155ae7b22b86b337'
source='622ffc194372d9882a78637077dff42f657b14a3'
def git(*args): return subprocess.check_output(['git',*args],cwd=repo)
def ident(path):
 p=Path(path);q=p.resolve(strict=True);s=q.stat();h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
assert git('rev-parse','HEAD').decode().strip()==source
assert not git('status','--porcelain')
paths=git('diff','--name-only',base,source).decode().splitlines()
assert paths==['r-package/dtatools/R/output-container.R']
old=git('show',base+':'+paths[0]);new=git('show',source+':'+paths[0])
assert new==old.replace(b'.repair_data_table_container <- function(data) {\n',b'.repair_data_table_container <- function(data) {\n    if (!inherits(data, "data.table")) return(data)\n',1)
assert new==(repo/paths[0]).read_bytes()
tree=git('rev-parse',source+':r-package/dtatools').decode().strip()
assert tree=='1733785140bd213d5bfb176db9258d6790595843'
records=[]
for name,mn,rn,expected in [
 ('candidate-01','output-manifest.json','completed-receipt.json','04b29e79d4bbb12b4375b5c48bdada59b527889bcbbf4646cedc975ba9661894'),
 ('full-01','manifest.json','receipt.json','85e923bd5b6a9e2666a75b2b8fb8de4f1fdb0b072d0c0e72312ee5b8c0f8715c')]:
 folder=root/name;r=json.loads((folder/rn).read_text());m=json.loads((folder/mn).read_text());e=json.loads((folder/'execution-result.json').read_text());b=json.loads((folder/'inputs-before.json').read_text())
 assert ident(folder/rn)['sha256']==expected and r['status']=='complete'
 assert r['manifest']==ident(folder/mn)
 assert not r.get('changed_inputs',r.get('changed_bound_inputs',[]))
 assert e['status']=='complete' and not e.get('changed_inputs',e.get('changed_bound_inputs',[]))
 commands=e.get('commands',e.get('records'))
 assert all(x.get('returncode',x.get('exit_code'))==0 for x in commands)
 assert len({x['path'] for x in m['products']})==len(m['products'])
 for x in m['products']:assert ident(x['path'])==x,x['path']
 assert {x['path'] for x in m['products']}=={str(p) for p in folder.rglob('*') if p.is_file()}-{str(folder/mn),str(folder/rn)}
 for x in b['inputs']:assert ident(x['path'])==x,x['path']
 if name=='candidate-01':
  assert r['revision']==source and r['package_tree']==tree and not e['generated_export_files']
  for x in b['export_inventory']:
   p=Path(x['path']);assert ident(p)=={k:v for k,v in x.items() if k not in ['git_mode','git_blob']}
   rel=p.relative_to(folder/'export').as_posix()
   assert p.read_bytes()==git('show',source+':'+rel),rel
   assert git('ls-tree',source,'--',rel).decode().split()[:2]==[x['git_mode'],'blob']
   assert git('rev-parse',source+':'+rel).decode().strip()==x['git_blob']
  assert (folder/'export'/paths[0]).read_bytes()==new
  archive=json.loads((folder/'built-source-before-install.json').read_text())
  assert ident(archive['path'])==archive
  install=(folder/'installed-identity.R').read_text()
  assert 'exports = 106L' in install and source in install and tree in install
 else:
  assert r['source_sha']==r['runner_sha']==source
  assert (folder/'source'/paths[0]).read_bytes()==new
  preflight=(folder/'preflight-identity.R').read_text()
  assert source in preflight and tree in preflight
  assert str(root/'candidate-01/library/dtatools/libs/dtatools.so') in preflight
 records.append(dict(name=name,receipt=ident(folder/rn),manifest=ident(folder/mn),products=len(m['products']),product_bytes=sum(x['bytes'] for x in m['products']),inputs=len(b['inputs']),input_bytes=sum(x['bytes'] for x in b['inputs']),commands=len(commands)))
rows=list(csv.DictReader((root/'full-01/tests.csv').open()))
totals={k:sum(int(r[k]) for r in rows) for k in ['failed','warning','passed']}
totals.update({k:sum(r[k]=='TRUE' for r in rows) for k in ['error','skipped']})
assert totals==dict(failed=0,warning=4,passed=16624,error=0,skipped=0)
warnings=[{k:r[k] for k in ['file','test','warning']} for r in rows if int(r['warning'])]
assert {r['file'] for r in warnings}=={'test-dibble.R'}
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='source_install_host_full_evidence_clear',base=base,source=source,package_tree=tree,reviewer_script=ident(__file__),source_file=ident(repo/paths[0]),records=records,test_rows=len(rows),totals=totals,warnings=warnings,assessment=[
 'Exactly one added guard. All remaining function statements, callers, package native code, exports and tests are byte-identical to the reviewed 57309 source.',
 'For objects without data.table inheritance, the previous ordinary-table predicate cannot match its required data.table/data.frame class sequence. Both versions therefore return the same input object without marker removal, capacity allocation or column mutation. The guard omits the repeated predicates and class/set-difference work.',
 'For objects with data.table inheritance, the existing version check, stray metadata marker removal and ordinary-table capacity repair execute unchanged. Subclass behavior and reader/metadata closing policies are preserved.',
 'The exact exported package, consumed built archive, installed package products and full-gate preflight are bound to source 622ffc19 and package tree 17337851. All 106 namespace exports remain. The 233 installer export records describe files, not public exports.',
 'The host full test results recalculate to 16624 passes, zero failures/errors/skips, and four established warnings.'
],limits=[
 'This is an isolated one-variable R source variant. Native interrupt patch 725974a is not integrated.',
 'No benchmark, profile, R probe or new test execution was performed by this reviewer. This review checks retained host evidence and source semantics; timing benefit remains to be measured.',
 'The host gate is not a new clean minimum-R, Windows, Rust or R CMD check qualification. The retained input scopes do not freeze the full OS dylib, SDK or Python runtime closures.'
])
with out.open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],records=[{k:r[k] for k in ['name','products','inputs']} for r in records],totals=totals,report=str(out))))
