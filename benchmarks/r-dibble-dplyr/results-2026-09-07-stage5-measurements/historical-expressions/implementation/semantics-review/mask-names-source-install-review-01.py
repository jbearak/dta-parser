from pathlib import Path
import csv, hashlib, json, subprocess
from datetime import datetime, timezone

repo=Path('/private/tmp/dta-direct-stage5-mask-names')
root=Path('/private/tmp/dta-direct-stage5-validation/mask-names')
out=Path(__file__).with_suffix('.json')
base='622ffc194372d9882a78637077dff42f657b14a3'
source='ad976f7a6854be19db08549a3ef87373448fdfe9'
def git(*args): return subprocess.check_output(['git',*args],cwd=repo)
def ident(path):
 p=Path(path);q=p.resolve(strict=True);s=q.stat();h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
assert git('rev-parse','HEAD').decode().strip()==source
assert not git('status','--porcelain')
paths=git('diff','--name-only',base,source).decode().splitlines()
assert paths==['r-package/dtatools/R/dibble-expressions.R','r-package/dtatools/tests/testthat/test-dibble-expressions.R']
old=git('show',base+':'+paths[0]);new=git('show',source+':'+paths[0])
assert new==old.replace(b'        state$names <- union(state$names, name)',b'        if (!name %in% state$names) state$names <- c(state$names, name)',1)
assert git('diff','--numstat',base,source,'--',paths[1]).decode().split()[:2]==['21','0']
assert (repo/paths[1]).read_bytes()==git('show',source+':'+paths[1])
assert new==(repo/paths[0]).read_bytes()
tree=git('rev-parse',source+':r-package/dtatools').decode().strip()
assert tree=='bb894a45ef1a7b9a2dd11be94388c80121fae769'
records=[]
for name,mn,rn,expected in [('candidate-01','output-manifest.json','completed-receipt.json','660c67a3bb9e9e3ed18beed9e0baca4878b548a136adf26c860f40b16a87eac3')]:
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
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='mask_names_source_install_evidence_clear',base=base,source=source,package_tree=tree,reviewer_script=ident(__file__),source_files=[ident(repo/p) for p in paths],records=records,assessment=[
 'The actual production diff replaces one union call only. The additional21 test lines introduce a public remove/re-add/capture-expiry regression. No native, grouping, result assembly, reference marker or batching code changes.',
 'state$names starts as an empty plain character vector. add() is called only from the input names(columns) loop and later names(pending) loop, each passing a scalar character name. Input column names are validated for missing, empty and duplicate names before initialization.',
 'Given the maintained unique character history, the membership guard and append preserve union first-seen ordering and leave overwrites unchanged. The membership operator returns a scalar nonmissing logical for these internal names.',
 'remove() still deletes only state$current. Every old name remains in state$names, and a re-add leaves one first-seen history entry. forget() therefore still installs the same one expired promise per historical name, including a name removed again before call exit.',
 'Every add still creates and tracks a distinct generation before and after the history update. Existing captures keep their generation and fixed group; cleanup releases all reachable generation payloads through the unchanged weak-reference list.',
 'The actual new public test reads old and re-added x generations during the call, removes x again, checks output names and values, then requires both late captures to error and the second read to retain its restarting-promise warning. A later source write leaves the returned after column unchanged.',
 'The exact installer receipt, all products/inputs,233 exported Git files, consumed built source archive and installed provenance match ad976f7a and package tree bb894a45. Public namespace exports remain106.'
],limits=[
 'This report clears source and the retained host installation. The separate full test gate is still pending review and no performance benefit is claimed.',
 'This source stacks only the mask-name change over622 repair guard. The native interrupt patch725 remains separate.',
 'No new test, R probe, profile or benchmark was executed by this reviewer. OS/SDK/full Python closure limits remain those of the retained installer.'
])
with out.open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],records=[{k:r[k] for k in ['name','products','inputs']} for r in records],report=str(out))))
