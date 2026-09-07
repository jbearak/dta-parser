from pathlib import Path
from datetime import datetime,timezone
import csv,hashlib,json,re,subprocess
root=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance')
review=Path('/private/tmp/dta-direct-stage5-validation/implementation/semantics-review')
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=hashlib.sha256(q.read_bytes()).hexdigest())
def check(row):assert ident(row['path'])==row,row['path']
old=json.loads((review/'read-control-final-preparation-review-01.json').read_text())
for row in old['sources']:
 if row['path'].endswith('read-control-v1.c'):check(row)
check(old['macho']['identity'])
r1=(root/'read-control-v1.R').read_text();r2=(root/'read-control-v2.R').read_text();tiny=(root/'read-control-tiny-check-v1.R').read_text()
marker='records <- states <- list()\n';assert r1.split(marker)[1]==r2.split(marker)[1]
prefix=r2.split(marker)[0];assert tiny.startswith(prefix)
assert 'bench::mark(' not in tiny and 'atomic_profile(' not in tiny
assert (root/'read-control-v3.py').read_text()==(root/'read-control-v2.py').read_text().replace("script = ROOT / 'read-control-v1.R'","script = ROOT / 'read-control-v2.R'")
assert ident(root/'read-control-v2.R')['sha256']=='d62d62c92ea403ece6fb90a9d023f4a34d70536ffa9ad88ae026092d296ed9ef'
assert ident(root/'read-control-v3.py')['sha256']=='7d4d620948718e595fb110291417b98a798ea449fd7a131a8fa28bb09a614428'
all_inputs={};runs=[]
for name in ['baseline-ec10-read-control-v2-01','baseline-ec10-read-fixture-diagnostic-01','candidate-a2d8b6a-read-fixture-diagnostic-01','baseline-ec10-read-tiny-check-01','candidate-a2d8b6a-read-tiny-check-01']:
 d=root/name;p=root/(name+'-receipt.json');r=json.loads(p.read_text());check(r['manifest']);m=json.loads((d/'manifest.json').read_text());ib=json.loads((d/'inputs-before.json').read_text())
 failed=name=='baseline-ec10-read-control-v2-01'
 assert r['accepted']==(not failed) and r['returncode']==int(failed) and r['changed_inputs']==[] and r['integrity_error'] is None
 assert r['namespace_coverage']==r['dll_coverage']==(not failed)
 assert ib['source']==('ec10a6ac34602f3bd691e8043019c1b479babda4' if name.startswith('baseline') else 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9')
 assert ib['runner_source']=='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
 for product in m['products']:check(product)
 assert {p.name for p in d.iterdir() if p.is_file()}=={Path(x['path']).name for x in m['products']}|{'manifest.json'}
 paths={x['path']:x for x in ib['inputs']};assert len(paths)==len(ib['inputs']);resolved={x['resolved'] for x in ib['inputs']}
 for row in ib['inputs']:
  if row['path'] in all_inputs:assert row==all_inputs[row['path']]
  all_inputs[row['path']]=row
 if not failed:
  for row in csv.DictReader((d/'namespaces.tsv').open(),delimiter='\t'):assert str((Path(row['path'])/'DESCRIPTION').resolve()) in resolved,row
  for row in csv.DictReader((d/'dlls.tsv').open(),delimiter='\t'):
   if row['name']=='base' and row['path']=='base':continue
   assert str(Path(row['path']).resolve()) in resolved,row
  assert str((root/'native-read-control-build-v5-01/dta_read_control.so').resolve()) in resolved
 log=(d/'execution.log').read_text()
 assert not any(p.name.startswith('raw-timing') for p in d.iterdir())
 if failed:assert 'identical(as.character(x), values) is not TRUE' in log and len(m['products'])==4
 if 'tiny-check' in name:
  assert len(m['products'])==6 and log.count('Checking tiny native control')==8 and log.rstrip().endswith('PASS eight tiny constructor/native controls; no timing or profiling')
  assert len(ib['inputs'])==(48425 if name.startswith('baseline') else 48426)
 runs.append(dict(name=name,receipt=ident(p),accepted=r['accepted'],products=len(m['products']),inputs=len(ib['inputs']),command=ib['command'],namespace_coverage=r['namespace_coverage'],dll_coverage=r['dll_coverage']))
for row in all_inputs.values():check(row)
for name,sha in [('baseline-ec10-read-tiny-check-01','5ef010b81d42c5b8146468a91afb127cee8b1593be48a1c4c4801985cfbb8e2d'),('candidate-a2d8b6a-read-tiny-check-01','28c23f05271c74a0b1cf19ecc7e2c450f7f4bc167a7338332c335fed9d366f1e')]:assert ident(root/(name+'-receipt.json'))['sha256']==sha
records=list(csv.DictReader((review/'read-control-fixture-records-01.csv').open()));assert len(records)==16
assert sum(x['original_predicate']=='FALSE' for x in records)==4
assert all(x['case'] in ['missing_first','missing_last'] and x['container']=='table_column' for x in records if x['original_predicate']=='FALSE')
assert 'PASS 16 saved fixture observations; both sources identical' in (review/'read-control-fixture-record-reader-01.log').read_text()
policies={}
for source in ['ec10a6ac34602f3bd691e8043019c1b479babda4','a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9']:
 text=subprocess.check_output(['git','show',source+':r-package/dtatools/R/mutate-data.R'],cwd='/private/tmp/dta-direct-stage5').decode()
 section=text[text.index('.normalize_untyped_column <- function'):text.index('# Types every untyped column of a data frame')]
 assert 'text[is.na(text)] <- ""' in section and 'kept[c("names", "class", "stata.string.storage")] <- NULL' in section and '.generated_column(column, NULL, row_count, caller)' in section
 policies[source]=dict(normalizer_sha256=hashlib.sha256(section.encode()).hexdigest(),normalizer=section)
assert len({x['normalizer_sha256'] for x in policies.values()})==1
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='corrected_control_fixture_and_tiny_evidence_clear',reviewer_script=ident(__file__),sources=[ident(root/x) for x in ['read-control-v1.R','read-control-v2.R','read-control-v2.py','read-control-v3.py','read-control-fixture-diagnostic-v1.R','read-control-fixture-diagnostic-v1.py','read-control-tiny-check-v1.R','read-control-tiny-check-v1.py']],runs=runs,distinct_current_inputs_rehashed=len(all_inputs),policies=policies,unchanged_c_and_dll=True,measured_loop_exact_v1_bytes=True,tiny_prefix_exact_corrected_R=True,saved_observations=records,reader=[ident(review/x) for x in ['read-control-fixture-record-reader-01.R','read-control-fixture-record-reader-01.log','read-control-fixture-records-01.csv']],assessment=[
'Original baseline v2-runtime/v1-R control remains failed before any timing: identical(as.character(x), values) was false. Its four products, failed receipt, input inventory and namespace/DLL-coverage false flags remain unchanged. Candidate control was not run in that attempt.',
'Both exact-source fixture observations retain eight ordinary/table combinations. Independent saved-RDS reading confirms identical observations across ec10 and a2. Only the table-column missing-first/last cases differ from raw input: NA is empty string, declaration is recomputed from str12 to str1; ordinary NA values remain NA. Empty and nonmissing declared values preserve str12.',
'Actual ec10 and a2 source normalizers are byte-identical in the relevant function and explicitly replace declared-string NA with empty string and recompute stale storage. The corrected acceptance oracle separately defines raw and stored values/storage. It is justified by existing constructor policy and observations, not a weakened timed-operation predicate.',
'The C source, accepted DLL and all measured loops/profile/state/timing/metadata code are unchanged. Runtime v3 only selects the corrected R filename, preserving the reviewed build/namespace/DLL/input guards. The correction is confined to the untimed tiny constructor/native checks.',
'The tiny-check R prefix exactly matches corrected read-control-v2.R and contains no bench timing or allocation profiler call. Both retained tiny runs pass all eight constructor/native combinations and four explicit storage checks with six products each, 48425/48426 inputs and namespace/DLL coverage true.',
'Diagnostic and tiny drivers retain the corrected v2 identity chain. All five runs current bound inputs/products were rehashed, including the original failure; no runtime receipt is relabeled. The saved-RDS reader used base R only and executed no constructor, C/native call, profile or benchmark.',
'This establishes tiny fixture correctness and preparation for the unchanged bounded declared-character anyNA control. The observations do not explain the remaining base-R timing costs, establish an exclusive cause, or qualify full-matrix/overall Stage5 acceptance.'
],limits='Actual source and retained fixture/tiny evidence audit. No fixture, benchmark, native-control loop or profiler rerun by reviewer. Saved-RDS-only reader executed with its source/output identities retained; original run provenance remains separately bound.')
with (review/'read-control-fixture-correction-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],distinct_inputs=len(all_inputs),runs=len(runs),saved_observations=16,report=ident(review/'read-control-fixture-correction-review-01.json'))))
