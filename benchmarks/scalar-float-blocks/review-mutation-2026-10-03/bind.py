from pathlib import Path
import csv,hashlib,json,re,subprocess
root=Path('<scalar-block-checkout>');e=Path('<scalar-block-evidence>')
commit='2cb76c06e91cd5129ef9497a9b28ed08fe809eeb';parent='81aa42687930f8f149d2d8735c8e02a780a016dc'
def need(ok,msg):
 if not ok:raise RuntimeError(msg)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def git(*args):return subprocess.check_output(['git',*args],cwd=root)
need(git('rev-parse','HEAD').decode().strip()==commit,'Wrong test commit')
changes=git('diff','--name-only',parent,commit).decode().splitlines()
expected=['r-package/dtatools/tests/testthat/test-native-arithmetic-parity.R','r-package/dtatools/tools/native-test-manifest.json']
need(changes==expected,'Not a test-only delta')
need(git('diff','2e512880b15ea5ef8d56c65a4916af3ad71fb928',commit,'--','r-package/dtatools/R','r-package/dtatools/src')==b'','Measured runtime source changed')
for path in expected:need((root/path).read_bytes()==git('show',commit+':'+path),'Working test source changed')
record={'status':'PASS','test_commit':commit,'parent_commit':parent,'measured_runtime_commit':'2e512880b15ea5ef8d56c65a4916af3ad71fb928','combined_runtime_commit':'7003eba901671797ee91fffc97f08e28a1f7f515','scope':'Post-run identity binding for a test-only review follow-up. Each run used the committed test source and a previously qualified installed library. This does not relabel historical timing/full-suite/archive evidence, and is not a new full-suite or conformance run.','changed_files':{path:sha(root/path) for path in expected},'builds':{},'focused':{},'input_sha256':{}}
for label,build,csvname,logname in [('measured',e/'candidate-v2','review-mutation-focused.csv','review-mutation-focused.log'),('combined',Path('<combined-integration-evidence>/combined-build'),'review-mutation-combined-focused.csv','review-mutation-combined-focused.log')]:
 receipt=json.loads((build/'build-receipt.json').read_text())
 want=record['measured_runtime_commit'] if label=='measured' else record['combined_runtime_commit']
 need(receipt['base_commit']==want and receipt['exit_code']==0 and receipt['pre_post_source_equal'] is True,'Build receipt differs')
 for path,digest in receipt['installed_inventory'].items():need(sha(build/'library/dtatools'/path)==digest,'Installed file changed')
 rows=list(csv.DictReader((e/csvname).open()));totals={'passed':0,'failed':0,'error':0,'skipped':0,'warning':0}
 for r in rows:
  need(r['error'] in ('TRUE','FALSE') and r['skipped'] in ('TRUE','FALSE'),'Invalid CSV boolean')
  for k in ('passed','failed','warning'):
   need(re.fullmatch(r'[0-9]+',r[k]) is not None,'Invalid nonnegative CSV count')
   totals[k]+=int(r[k])
  for k in ('error','skipped'):totals[k]+=r[k]=='TRUE'
 need(totals=={'passed':31442,'failed':0,'error':0,'skipped':0,'warning':0},'Focused test failure/count differs')
 expected_blocks={'scalar block proofs preserve ordinary tails and late whole-column promotion':1566,'scalar block proofs preserve imported exceptions after ordinary spans':2061}
 amended=[r for r in rows if r['test'] in expected_blocks]
 need(len(amended)==2 and {r['test']:int(r['passed']) for r in amended}==expected_blocks,'Amended block counts differ')
 record['focused'][label]={'totals':totals,'blocks':len(rows),'command':['Rscript','--vanilla',str(e/'focused.R'),str(build/'library'),str(root/'r-package/dtatools/tests/testthat'),str(e/csvname)]}
 record['builds'][label]={'commit':want,'receipt_variant':receipt['variant'],'receipt_sha256':sha(build/'build-receipt.json'),'installed_inventory':receipt['installed_inventory']}
 for name in (csvname,logname):record['input_sha256'][str(e/name)]=sha(e/name)
old=json.loads(git('show',parent+':r-package/dtatools/tools/native-test-manifest.json'));new=json.loads((root/expected[1]).read_text())
def blocks(m):return {(b['file'],b['test'],b.get('occurrence',1)):b for f in m['families'] for b in f['blocks']}
a,b=blocks(old),blocks(new);need(a.keys()==b.keys(),'Block set changed')
raised={}
for k in a:
 if a[k]!=b[k]:
  need({x:y for x,y in a[k].items() if x!='min_pass'}=={x:y for x,y in b[k].items() if x!='min_pass'},'Manifest policy changed')
  need(b[k]['min_pass']>a[k]['min_pass'],'Assertion minimum not raised')
  raised[k[1]]=[a[k]['min_pass'],b[k]['min_pass']]
need(sorted(raised.values())==[[1458,1566],[1931,2061]],'Unexpected minima')
record['raised_minima']=raised
for name in ('focused.R','review-mutation-manifest-refresh.log','review-mutation-manifest-tests.log'):
 record['input_sha256'][str(e/name)]=sha(e/name)
need('Ran 7 tests' in (e/'review-mutation-manifest-tests.log').read_text() and (e/'review-mutation-manifest-tests.log').read_text().rstrip().endswith('OK'),'Manifest guards failed')
record['script_sha256']=sha(__file__)
(e/'review-mutation-binding.json').write_text(json.dumps(record,indent=2,sort_keys=True)+'\n')
print('PASS: test-only delta;31442 assertions in each library;2 raised minima;7 manifest guards; runtime source and installed identities verified')
