from pathlib import Path
import csv,hashlib,importlib.util,json,re,subprocess
root=Path('<nullable-interrupt-repository>');e=Path('<nullable-interrupt-evidence>')
commit='afb0cf4fbb327186cff5ee6d591566af9b5ce84d';parent='11bcecc4'
failed=Path('<scalar-block-evidence>/pr-298-macos-native-artifact/native-check/evidence/native/console.log')
def need(ok,msg):
 if not ok:raise RuntimeError(msg)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def git(*args):return subprocess.check_output(['git','--no-replace-objects',*args],cwd=root)
need(git('rev-parse','HEAD').decode().strip()==commit,'Wrong source')
parent=git('rev-parse',parent).decode().strip()
expected=['r-package/dtatools/src/dtatools-internal.h','r-package/dtatools/src/init.c','r-package/dtatools/src/r-bridge.c','r-package/dtatools/tests/testthat/test-arrow-nullable-strings.R','r-package/dtatools/tools/native-test-manifest.json']
need(git('diff','--name-only',parent,commit).decode().splitlines()==expected,'Unexpected source scope')
for path in expected:
 need((root/path).read_bytes()==git('show',commit+':'+path),'Working source differs from qualified commit: '+path)
need(git('diff',parent,commit,'--','r-package/dtatools/src/numeric-arithmetic*.h')==b'','Arithmetic source changed')
recorder=root/'benchmarks/native-operations/run.py';spec=importlib.util.spec_from_file_location('records',recorder);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
b=module.inventory(e/'candidate','baseline');need(b['receipt']['base_commit']==commit,'Wrong clean build')
rows=list(csv.DictReader((e/'focused.csv').open()))
for row in rows:
 need(all(re.fullmatch('[0-9]+',row[k]) for k in ('passed','failed','warning')),'Malformed count')
 need(row['error'] in ('TRUE','FALSE') and row['skipped'] in ('TRUE','FALSE'),'Malformed status')
 need(row['file']=='test-arrow-nullable-strings.R' and row['failed']=='0' and row['warning']=='0' and row['error']=='FALSE' and row['skipped']=='FALSE','Failed focused block')
counts={row['test']:int(row['passed']) for row in rows}
want={'nullable Arrow strings preserve sliced validity and unequal chunks':24,'nullable Arrow strings keep their output rooted during collection':4,'nullable Arrow string allocation errors clean up before the next read':3,'nullable Arrow read cancellation remains an interrupt':5}
need(len(rows)==4 and counts==want,'Wrong focused matrix/counts')
command=['python3','scripts/test_native_manifest.py']
guard=subprocess.run(command,cwd=root,text=True,capture_output=True)
(e/'manifest-guards.log').write_text(guard.stdout+guard.stderr)
need(guard.returncode==0 and 'Ran 7 tests' in guard.stderr and guard.stderr.rstrip().endswith('OK'),'Manifest guards failed')
need('Expected `completed` to be FALSE.' in failed.read_text() and '`actual`:   TRUE' in failed.read_text(),'Failed CI symptom differs')
result={'status':'PASS','source_commit':commit,'parent_commit':parent,'changed_files':{p:sha(root/p) for p in expected},'scope':'Targeted qualification of a deterministic replacement for a pre-existing flaky nullable Arrow cancellation test. It adds a private one-shot control at an existing native polling checkpoint. This is not a new arithmetic benchmark, full-suite run or source-archive conformance run. Historical measured arithmetic remains 2e512880b15ea5ef8d56c65a4916af3ad71fb928; its arithmetic headers are unchanged.','failed_ci':{'pull_request':298,'job_id':111173324583,'observed_failure':'The read completed before the delayed SIGINT was caught. The interrupt-class check passed, but completed was TRUE.','console_original_sha256':sha(failed)},'build_receipt_sha256':b['receipt_sha256'],'source_inventory':b['source'],'installed_inventory':b['installed'],'focused':{'assertions':36,'blocks':4,'counts':counts,'failed':0,'error':0,'skipped':0,'warning':0,'command':['Rscript','--vanilla','<evidence>/focused.R','<evidence>/candidate/library','<evidence>/focused.csv'],'cwd':'<repository>','launch_scope':'Explicit post-run description of the executed command; source and installed identities reverified afterward. No contemporaneous R launcher receipt is claimed.'},'manifest_guards':{'command':command,'cwd':'<repository>','exit_code':guard.returncode,'passed':7,'script_sha256':sha(root/'scripts/test_native_manifest.py')},'input_sha256':{n:sha(e/n) for n in ('focused.R','focused.csv','focused.log','manifest-guards.log','bind-and-publish.py')},'verified_build_recorder_sha256':sha(recorder)}
(e/'binding.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
out=root/'benchmarks/scalar-float-blocks/review-interrupt-2026-10-03';out.mkdir(exist_ok=False)
files={'binding.json':e/'binding.json','focused.R':e/'focused.R','focused.csv':e/'focused.csv','focused.log':e/'focused.log','manifest-guards.log':e/'manifest-guards.log','bind-and-publish.py':e/'bind-and-publish.py','failed-ci-console.log':failed}
replacements={str(e):'<nullable-interrupt-evidence>',str(root):'<nullable-interrupt-repository>','<scalar-block-evidence>':'<scalar-block-evidence>'}
def redact(t):
 for old,new in replacements.items():t=t.replace(old,new)
 return t
source_map={}
for name,path in files.items():
 text=redact(path.read_text());need(re.search(r'/(?:private/tmp|Users)/[A-Za-z0-9_]',text) is None,'Private path remains')
 # These selected records contain no environment identity records at all.
 need(re.search(r'"(?:LOGNAME|USER)"\s*:',text) is None,'Identity field unexpectedly included')
 (out/name).write_text(text)
 source_map[name]={'source':redact(str(path)),'original_sha256':sha(path),'published_sha256':sha(out/name)}
(out/'source-map.json').write_text(json.dumps(source_map,indent=2,sort_keys=True)+'\n')
(out/'manifest.json').write_text(json.dumps({'scope':'Separate targeted test-fix evidence. Original hashes bind private records; this manifest and source map bind redacted publication copies. Historical205 artifacts are unchanged.','files':{p.name:sha(p) for p in out.iterdir() if p.is_file()}},indent=2,sort_keys=True)+'\n')
print('PASS clean source-bound build;36 focused assertions;7 manifest guards;separate publication')
