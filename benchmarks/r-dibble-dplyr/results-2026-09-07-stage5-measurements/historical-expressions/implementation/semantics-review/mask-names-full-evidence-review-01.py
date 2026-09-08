from pathlib import Path
from datetime import datetime, timezone
import collections, csv, hashlib, json, subprocess

root=Path('/private/tmp/dta-direct-stage5-validation/mask-names')
repo=Path('/private/tmp/dta-direct-stage5-mask-names')
review=Path(__file__).parent
source='ad976f7a6854be19db08549a3ef87373448fdfe9'
tree='bb894a45ef1a7b9a2dd11be94388c80121fae769'
folder=root/'full-01'
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
def git(*args):return subprocess.check_output(['git',*args],cwd=repo)
receipt=ident(folder/'receipt.json')
assert receipt['sha256']=='aff1dc2ff4f3b8ac716c51d2ed43d25833b37f5a546997713985e4e9e27a93bd'
r=json.loads((folder/'receipt.json').read_text());m=json.loads((folder/'manifest.json').read_text())
b=json.loads((folder/'inputs-before.json').read_text());e=json.loads((folder/'execution-result.json').read_text())
assert r['status']==e['status']=='complete' and not r['changed_inputs'] and not e['changed_inputs']
assert r['source_sha']==r['runner_sha']==b['source_sha']==b['runner_sha']==source
assert r['manifest']==ident(folder/'manifest.json')
assert all(x['exit_code']==0 for x in e['records']) and [x['label'] for x in e['records']]==['preflight','tests']
assert len({x['path'] for x in m['products']})==len(m['products'])
for x in m['products']:assert ident(x['path'])==x,x['path']
assert {x['path'] for x in m['products']}=={str(p) for p in folder.rglob('*') if p.is_file()}-{str(folder/'manifest.json'),str(folder/'receipt.json')}
for x in b['inputs']:assert ident(x['path'])==x,x['path']
assert git('rev-parse','HEAD').decode().strip()==source and not git('status','--porcelain')
assert git('rev-parse',source+':r-package/dtatools').decode().strip()==tree
for path in ['r-package/dtatools/R/dibble-expressions.R','r-package/dtatools/tests/testthat/test-dibble-expressions.R']:
 expected=git('show',source+':'+path)
 assert (repo/path).read_bytes()==(folder/'source'/path).read_bytes()==(root/'candidate-01/export'/path).read_bytes()==expected
preflight=(folder/'preflight-identity.R').read_text()
assert source in preflight and tree in preflight and str(root/'candidate-01/library/dtatools/libs/dtatools.so') in preflight
prior=json.loads((review/'mask-names-source-install-review-01.json').read_text())
assert prior['source']==source and prior['package_tree']==tree and prior['status']=='mask_names_source_install_evidence_clear'
assert prior['records'][0]['receipt']==ident(root/'candidate-01/completed-receipt.json')
rows=list(csv.DictReader((folder/'tests.csv').open()))
totals={k:sum(int(r[k]) for r in rows) for k in ['failed','warning','passed']}
totals.update({k:sum(r[k]=='TRUE' for r in rows) for k in ['error','skipped']})
assert totals==dict(failed=0,warning=4,passed=16632,error=0,skipped=0)
selected=[r for r in rows if r['test']=='removed and re-added column generations retain values and expire']
assert len(selected)==1 and selected[0]['passed']==selected[0]['nb']=='8' and selected[0]['warning']=='0'
old=list(csv.DictReader((root.parent/'repair-guard/full-01/tests.csv').open()))
keys=['file','context','test','nb','failed','skipped','error','warning','passed']
as_rows=lambda data:collections.Counter(tuple(r[k] for k in keys) for r in data)
assert as_rows(rows)==as_rows(old)+as_rows(selected)
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='mask_names_final_source_install_host_full_evidence_clear',source=source,package_tree=tree,reviewer_script=ident(__file__),prior_source_install_review=ident(review/'mask-names-source-install-review-01.json'),receipt=receipt,manifest=ident(folder/'manifest.json'),products=len(m['products']),product_bytes=sum(x['bytes'] for x in m['products']),bound_inputs=len(b['inputs']),bound_input_bytes=sum(x['bytes'] for x in b['inputs']),commands=e['records'],totals=totals,new_test=selected[0],unchanged_test_rows_match_622=True,assessment='All3032 completed full-gate products and58623 declared input identities match, with exact ad976f7a source, runner, exported tests and installed library preflight. Full CSV totals reproduce16632 passes, zero failures/errors/skips and four established warnings. All prior622 test result rows and assertion counts match exactly; the sole additional row is the eight-pass public remove/re-add/generation-expiry test. Together with the completed source/install review, this clears the isolated mask-name variant for the next bounded measurement.',limits=['This is host R4.6.1 full-test evidence, not a new minimum-R/Windows/R CMD check or native integration gate.','The repair guard is included from622; native interrupt patch725 remains separate. No timing benefit or full Stage5 performance acceptance is claimed.','No R, build, profile or benchmark operation was executed by this reviewer. Retained output/source/input identities and CSV results were read and rehashed.','OS dylibs, full SDK and Python runtime closures retain the documented binding limits.'])
with (review/'mask-names-full-evidence-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],products=result['products'],inputs=result['bound_inputs'],totals=totals,new_test_passes=8,all_other_test_rows_unchanged=True)))
