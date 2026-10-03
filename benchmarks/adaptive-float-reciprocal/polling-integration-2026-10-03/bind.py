"""Verify the separate PR302/303 merge qualification; runs no tests/timings."""
import csv, hashlib, importlib.util, json, os, re, subprocess
from pathlib import Path
P=Path(__file__).resolve().parent
R=Path('<PRIVATE_TMP>/dta-float-reciprocal-adaptive')
SOURCE='b6f72b585fc7c050aab5f3332a72f58bf3fa0d20'
OURS='90a3e8a9bff34c45b19ae4401a07f087f79a8ef0'
INCOMING='c51e5f6debf463969417f2bd15e488ceff462d07'
BASE='213ceeee5a0f7953bf0f13316e2207a766dcbb24'
MEASURED='2ec57f24a14a646ae67fd2e0af4fb8ef1c549f52'
def need(v,m):
 if not v:raise RuntimeError(m)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
def git(*args):return subprocess.check_output(['git','--no-replace-objects',*args],cwd=R,env=env)
def blob(c,p):return git('show',c+':'+p)
need(git('show','-s','--format=%P',SOURCE).decode().strip().split()==[OURS,INCOMING],'Wrong merge parents')
package='r-package/dtatools/'
headers={'src/numeric-arithmetic-float-reciprocal.h':MEASURED,'src/numeric-arithmetic-pair-long-float.h':INCOMING}
for path,pin in headers.items():need(blob(SOURCE,package+path)==blob(pin,package+path),'Measured header changed')
tests=['tests/testthat/test-native-arithmetic-parity.R','tests/testthat/test-arithmetic-payload-lifetime.R']
for path in tests:
 base,ours,incoming=(blob(c,package+path) for c in (BASE,OURS,INCOMING))
 need(ours.startswith(base) and incoming.startswith(base),'Parent test prefixes changed')
 need(blob(SOURCE,package+path)==ours+incoming[len(base):],'Lost or modified appended test block')
expected=set(tests+['tools/native-test-manifest.json'])
for parent,header in [(OURS,'src/numeric-arithmetic-pair-long-float.h'),(INCOMING,'src/numeric-arithmetic-float-reciprocal.h')]:
 paths={x.removeprefix(package) for x in git('diff','--name-only',parent,SOURCE,'--',package).decode().splitlines()}
 need(paths==expected|{header},'Unexpected package delta')
merged=json.loads(blob(SOURCE,package+'tools/native-test-manifest.json'))
for parent in (OURS,INCOMING):
 old=json.loads(blob(parent,package+'tools/native-test-manifest.json'))
 for f in old['families']:
  mf=next(x for x in merged['families'] if x['id']==f['id'])
  need(all(b in mf['blocks'] for b in f['blocks']),'Parent manifest obligation lost')
for f in merged['families']:
 for entry in f['files']:need(hashlib.sha256(blob(SOURCE,package+entry['path'])).hexdigest()==entry['sha256'],'Manifest source hash mismatch')
# Imported historical artifacts and our measured evidence remain byte-identical.
for parent,folder in [(OURS,'benchmarks/adaptive-float-reciprocal/evidence'),(INCOMING,'benchmarks/retained-arithmetic-polling')]:
 need(not git('diff','--name-only',parent,SOURCE,'--',folder),'Historical evidence changed')
# Full clean build/installed inventory replay is delegated to the existing verified recorder.
recorder=R/'benchmarks/native-operations/run.py';spec=importlib.util.spec_from_file_location('records',recorder);records=importlib.util.module_from_spec(spec);spec.loader.exec_module(records)
i=records.inventory(P/'build','baseline')
need(i['receipt']['base_commit']==SOURCE and i['receipt']['source_patch_sha256']==hashlib.sha256(b'').hexdigest(),'Wrong clean build')
for rel,h in i['source'].items():
 need(hashlib.sha256(blob(SOURCE,package+rel)).hexdigest()==h and sha(R/package/rel)==h,'Current/build source differs from commit')
command=json.loads((P/'focused-command.json').read_text());done=json.loads((P/'focused-completion.json').read_text())
need(done['exit_code']==0 and done['before']==done['after']==command['before']==i,'Focused build binding changed')
need(all(done[k]==v for k,v in command.items()),'Focused command record changed')
need(command['source_commit']==SOURCE and command['cwd']==str(R),'Focused source/cwd changed')
need(command['command']==['Rscript','--vanilla',str(P/'focused-source.R'),str(P/'build/library'),str(P/'focused.csv'),str(R/package/'tests/testthat')],'Focused invocation changed')
for path,key in [('run-focused.py','controller_sha256'),('focused-source.R','test_runner_sha256')]:need(sha(P/path)==command[key],'Focused controller changed')
need(sha(recorder)==command['recorder_sha256'],'Recorder changed')
for name,key in [('focused.csv','csv_sha256'),('focused.log','log_sha256')]:need(sha(P/name)==done[key],'Focused output changed')
rows=list(csv.DictReader((P/'focused.csv').open()))
blocks={(Path(path).name,title) for path in tests for title in re.findall(r'test_that\("([^"\n]+)"',blob(SOURCE,package+path).decode())}
need(len(rows)==len(blocks)==42 and {(x['file'],x['test']) for x in rows}==blocks,'Focused block coverage changed')
for row in rows:
 need(all(re.fullmatch(r'[0-9]+',row[k]) for k in ('passed','failed','warning')),'Malformed focused count')
 need(row['failed']==row['warning']=='0' and row['error']==row['skipped']=='FALSE','Focused failure')
need(sum(int(x['passed']) for x in rows)==38640,'Focused assertion count changed')
for f in merged['families']:
 for block in f['blocks']:
  match=[r for r in rows if (r['file'],r['test'])==(block['file'],block['test'])]
  if match:need(len(match)==1 and int(match[0]['passed'])>=block['min_pass'],'Manifest minimum not met')
guards=json.loads((P/'guards.json').read_text())
need(len(guards)==4,'Guard matrix changed')
expected_commands={tuple(['python3']+(['-O'] if opt else [])+[script]) for script in ('scripts/test_native_manifest.py','scripts/test_arithmetic_dependencies.py') for opt in (False,True)}
need({tuple(g['command']) for g in guards}==expected_commands,'Guard command matrix')
for g in guards:
 need(g['exit_code']==0 and g['cwd']==str(R) and sha(R/g['command'][-1])==g['script_sha256'] and sha(P/g['log'])==g['log_sha256'],'Guard binding failed')
s=json.loads((P/'structural/receipt.json').read_text())
need(s['commit']==SOURCE and s['source_before_after_equal'] is True and s['require_proved'] is True,'Structural source binding')
need((s['exit_code'],s['cases'],s['semantic_failures'],s['work_failures'])==(0,18,0,0),'Structural gate failed')
for name,h in s['artifact_sha256'].items():need(sha(P/'structural'/name)==h,'Structural artifact changed')
for rel,h in s['source_sha256'].items():need(sha(R/'r-package/dtatools/src'/rel)==h,'Structural current source changed')
for name,key in [('work-count.py','controller_sha256'),('work-count.c','probe_sha256'),('cadence.h','cadence_sha256')]:need(sha(R/'benchmarks/retained-arithmetic-polling'/name)==s[key],'Structural controller changed')
files=['bind.py','run-focused.py','focused-source.R','focused.csv','focused.log','focused-command.json','focused-completion.json','run-guards.py','guards.json','build/build-receipt.json','build/input-record.json','structural/receipt.json','structural/work-count.csv','structural/work-count.log']+[g['log'] for g in guards]
result=dict(status='PASS',source_commit=SOURCE,parents=[OURS,INCOMING],measured_reciprocal_commit=MEASURED,header_source_sha256={p:hashlib.sha256(blob(SOURCE,package+p)).hexdigest() for p in headers},exact_append_only_test_union=True,parent_manifest_obligations_preserved=True,historical_evidence_unchanged=True,focused=dict(blocks=42,passed=38640,failed=0,error=0,skipped=0,warnings=0),structural=dict(cases=18,semantic_failures=0,work_failures=0),guards=dict(native_manifest=[8,8],arithmetic_dependencies=[1,1]),clean_build_receipt_sha256=i['receipt_sha256'],source_inventory=i['source'],installed_inventory=i['installed'],artifact_sha256={name:sha(P/name) for name in files},scope='Separate source-bound clean build, focused installed qualification and current-header polling proof for the PR302/303 merge. No new timing or full archive run; historical a937 archive and measured2ec results retain their original source attribution.')
(P/'binding.json').write_text(json.dumps(result,indent=2)+'\n');print('PASS integration42 blocks/38640 assertions/18 structural')
