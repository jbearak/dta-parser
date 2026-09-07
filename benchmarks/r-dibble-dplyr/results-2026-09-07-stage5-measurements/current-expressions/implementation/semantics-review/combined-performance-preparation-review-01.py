from pathlib import Path
from datetime import datetime, timezone
import ast, csv, hashlib, json, subprocess

validation=Path('/private/tmp/dta-direct-stage5-validation')
root=validation/'root-expression-performance';review=Path(__file__).parent
source='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
files={root/'compare-measurements-v4.py':'599d07b4abcb6b803dc37b9e70267abcf4a71aacd809eaca9b1a2bb1e0d9fb3c',validation/'run-stage5-owned-performance-v3.py':'f62c2544ebfd3414aa748dcbad97c3b7eb26a0c41b78e22958e841053be637f4',validation/'compare-heap-stage5-v3.py':'603ddca3f3c20bf90d1bda791d257752e733df9c2570aacdfbf99c6e2a9c50a6'}
for p,sha in files.items():assert ident(p)['sha256']==sha
old_source='57309d40433a92d99849fefa155ae7b22b86b337'
old=(validation/'run-stage5-owned-performance-v2.py').read_text()
wanted=old.replace(old_source,source).replace("'root-stage5-owned-performance'","'root-stage5-owned-performance-a2d8b6a'").replace('compare-heap-stage5-v2.py','compare-heap-stage5-v3.py').replace('implementation/candidate-final-03/library','implementation/candidate-combined-01/library')
assert wanted==(validation/'run-stage5-owned-performance-v3.py').read_text()
old=(validation/'compare-heap-stage5-v2.py').read_text()
assert old.replace(old_source,source).replace('implementation/candidate-final-03/library','implementation/candidate-combined-01/library')==(validation/'compare-heap-stage5-v3.py').read_text()
old=(root/'compare-measurements-v3.py').read_text()
wanted=old.replace(old_source,source)
wanted=wanted.replace('# These launch the same separately bound R command outside R timing. Preserve\n# the demonstrated difference; no other common input difference is allowed.','# Both measurements must use the same pinned launcher and separately bound R\n# command. All remaining common input identities must match as well.')
wanted=wanted.replace('/opt/homebrew/Cellar/python@3.14/3.14.7/Frameworks/Python.framework/Versions/3.14/bin/python3.14','/Users/jmb/.pyenv/versions/3.14.7/bin/python3.14').replace('bytes=34640','bytes=33816').replace('87d4df53fd91304be5bac391fb204643c36b7df2023c04a0953bcbc3bc3ad','unused')
wanted=wanted.replace('87d4df53fd91304be5bac391fb204643c36b7df2023c04a0953bcbc7d4fdf634','8e8f1b256a299fe22e6cfe0dad6801ae8f0c62c7cfef844fbc2db92c03cfe32d')
wanted=wanted.replace('used different pinned Python3.14.7 launchers.','used the same pinned Python3.14.7 launcher.').replace('The v2 rejection is preserved; this comparison permits only the recorded launcher distinction.','This comparison does not permit the different-launcher exception used for historical source57309.')
assert wanted==(root/'compare-measurements-v4.py').read_text()
probe=json.loads((review/'comparator-synthetic-04.json').read_text());assert len(probe['results'])==13
assert probe['original_source_sha256']==files[root/'compare-measurements-v4.py']
assert (review/'compare-measurements-reviewed-04.py').read_bytes()==(root/'compare-measurements-v4.py').read_bytes()
assert next(x for x in probe['results'] if x['case']=='historical_different_launcher_rejected')['error']['message']=='Unexpected orchestration Python binding'
old_guard=json.loads((review/'coordinator-final-source-review-01.json').read_text())
for p in [validation/'run-stage5-owned-performance-v2.py',validation/'compare-heap-stage5-v2.py']:
 previous=old_guard['files'][str(p)];assert {k:ident(p)[k] for k in previous}==previous
tree=ast.parse((validation/'run-stage5-owned-performance-v3.py').read_text())
names=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='NAMES' for t in n.targets))
runner_repo=Path('/private/tmp/dta-direct-stage4')
for name in names:
 p='benchmarks/r-dibble-dplyr/'+name
 assert (runner_repo/p).read_bytes()==subprocess.check_output(['git','show',source+':'+p],cwd=runner_repo)
output=validation/'root-stage5-owned-performance-a2d8b6a';assert not output.exists() and not output.is_symlink()
records=[]
for name,expected in [('candidate-a2d8b6a-qualify-01','3fb1d84382d368c12cb86dfcad856b3375d5e1c854ba700838bdb54439674569'),('candidate-a2d8b6a-write-qualify-01','8faabcabd13582d2979d511d428b4c56d27af7c37dd44f5d039566930e6f2940')]:
 folder=root/name;rp=root/(name+'-receipt.json');assert ident(rp)['sha256']==expected
 r=json.loads(rp.read_text());m=json.loads((folder/'manifest.json').read_text());b=json.loads((folder/'inputs-before.json').read_text());e=json.loads((folder/'execution-result.json').read_text())
 assert r['accepted'] and r['returncode']==e['returncode']==0 and not r['changed_inputs'] and not e['changed_inputs'] and r['namespace_coverage'] and e['namespace_coverage'] and r['integrity_error'] is None and e['integrity_error'] is None
 assert r['manifest']==ident(folder/'manifest.json') and b['source']==source
 for x in m['products']:assert ident(x['path'])==x,x['path']
 assert {x['path'] for x in m['products']}|{str(folder/'manifest.json')}=={str(p) for p in folder.iterdir()}
 for x in b['inputs']:assert ident(x['path'])==x,x['path']
 namespaces=list(csv.DictReader((folder/'namespaces.tsv').open(),delimiter='\t'));bound={x['resolved'] for x in b['inputs']}
 for ns in namespaces:assert str((Path(ns['path'])/'DESCRIPTION').resolve(strict=True)) in bound
 assert next(x['path'] for x in namespaces if x['name']=='dtatools')==str(validation/'implementation/candidate-combined-01/library/dtatools')
 assert b['case_set']==('write_qualify' if 'write' in name else 'qualify')
 records.append(dict(name=name,receipt=ident(rp),manifest=ident(folder/'manifest.json'),products=len(m['products']),input_bindings=len(b['inputs']),scope=b['scope']))
prior=json.loads((review/'root-driver-review-03.json').read_text())
for name in ['qualify-v6.R','qualify-v15.py','write-cases-v2.R','writes-v2.R','writes-v2.py']:
 p=root/name;expected=prior['files'][str(p)];assert {k:ident(p)[k] for k in expected}==expected
assert (review/'combined-benchmark-qualification-reader-02.log').read_text().startswith('PASS16 expression reference/oracle records,78 source-state matrices/348 stable rows,15 write qualification rows/600 expected before-after states')
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='combined_performance_preparation_source_and_tiny_evidence_clear',source=source,reviewer_script=ident(__file__),reviewed_sources=[ident(p) for p in files],source_assessment=[
 'Actual final expression comparator v4 changes only candidate identity, requires the identical pinned pyenv launcher for both sources, and corrects reporting wording. Exact metric schema, common driver/corpus/helper/runtime equality, source-specific package exclusion, receipt prebinding, four comparisons per grid case, arithmetic and strict greater-than10percent AND greater-than1ms diagnosis flags are unchanged.',
 'Thirteen pure Python fixture cases pass against a byte-identical frozen v4 source. They include threshold boundaries, changed data/schema/corpus/runtime/grid/source rejection, other-run audit rejection, authenticated failure finalization on a missing input directory, wrong/duplicate launcher rejection and rejection of the actual historical different-launcher identity.',
 'Actual owned coordinator v3 changes only candidate/runner revision, candidate library, fresh output path and heap-comparator link. Input/product/inventory guards, preguard before documented memory-manifest extension, completed-child freezing, output/failure receipts and execution scope remain exactly as reviewed v2.',
 'Actual heap comparator v3 changes only candidate/runner identity and library. The raw72-log runtime checks, five checkpoint derivations,36-case pairing, tracked-heap retained/release budgets and before/after input guards are unchanged. Prior eight pure coordinator helper cases apply by unchanged helper source; their inline-launcher provenance limit remains explicit.',
 'All eleven coordinator runner/helper files in the designated Stage4 worktree equal exact a2 Git blobs. The new root output is fresh at review. This is preparatory checking, not execution of any child workload.'
],synthetic=dict(cases=13,products=[ident(review/p) for p in ['comparator-synthetic-04.py','comparator-synthetic-04.json','compare-measurements-reviewed-04.py']],prior_guard_review=ident(review/'coordinator-final-source-review-01.json'),prior_guard_binding=ident(validation/'implementation/coordinator-guard-binding-01.json')),qualification=records,retained_record_reader=dict(command=['/opt/homebrew/Cellar/r/4.6.1/bin/Rscript','--vanilla',str(review/'combined-benchmark-qualification-reader-02.R'),str(root),str(review)],exit_code=0,products=[ident(review/p) for p in ['combined-benchmark-qualification-reader-02.R','combined-benchmark-qualification-reader-02.log','combined-benchmark-source-states-02.csv']]),qualification_assessment='The unchanged qualified drivers ran on exact combined a2 library. All16 expression reference/oracle records pass with78 source-state matrices/348 stable rows. All15 small write cases pass;600 retained before/after rows show expected private/shared starting states, target detachment or private reuse, and unchanged non-target backing. Input/product/receipt/namespace identities match. Source-bound executed checks cover manual values, metadata, aliases, capture isolation and native copy budgets; those payloads/counters are not separately rederived from a retained raw-value dump.',reviewer_attempt_history='Initial retained-state reader expected grouping key g first; actual unchanged fixture appends g. The original failed reader/log remains. Corrected reader checks the actual constructor order and passes; no evidence files changed.',limits=['No benchmark, allocation profile or owned/read child process was executed. R only parsed existing qualification records; synthetic Python data are artificial test fixtures, not measurement evidence.','This clears preparation for root-coordinated measurements. Final paired expression, write-cost, retained memory/RSS and owned/read results still require independent audits and assessment.','Same-source and cross-source comparisons remain separate; no overall acceptance follows from successful orchestration or synthetic checks.','Original rejected measurements, earlier driver versions and distinct package identities remain unchanged. Full OS/Python closure and prior inline-helper-launcher limitations remain explicit.'])
with (review/'combined-performance-preparation-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],source_files=3,synthetic_cases=13,qualification=records,expression_checks=16,write_checks=15,source_state_rows=348,write_state_rows=600)))
