from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, subprocess

repo=Path('/private/tmp/dta-direct-stage5')
review=Path(__file__).parent
base='f74f15f98be26a0fc0d7d73a144e5f6319af2c5f'
initial='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
source='ea031bec2df4d6711f1214b5dd3d00ebf029b3f1'
def git(*args):return subprocess.check_output(['git',*args],cwd=repo)
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat()
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=hashlib.sha256(q.read_bytes()).hexdigest())
assert git('rev-parse','HEAD').decode().strip()==source and not git('status','--porcelain')
expected=['CONTRIBUTING.md','docs/adr/0034-evaluate-dibble-expressions-with-call-local-group-context.md','docs/plans/dibble-result-performance-progress.md','r-package/dtatools/NEWS.md','r-package/dtatools/R/dibble-expressions.R','r-package/dtatools/R/output-container.R','r-package/dtatools/src/init.c','r-package/dtatools/tests/testthat/helper-generation-interrupt.R','r-package/dtatools/tests/testthat/test-dibble-expressions.R','r-package/dtatools/tests/testthat/test-mutate-data.R']
paths=git('diff','--name-only',base,source).decode().splitlines();assert paths==expected
for p in paths:assert (repo/p).read_bytes()==git('show',source+':'+p)
package_tree=git('rev-parse',source+':r-package/dtatools').decode().strip()
assert package_tree==git('rev-parse',initial+':r-package/dtatools').decode().strip()=='b08c77d91bdce67032f13aced90c29d068d6e95a'
assert git('diff','--name-only',initial,source).decode().splitlines()==['docs/plans/dibble-result-performance-progress.md']
variants={'R/output-container.R':'622ffc19','R/dibble-expressions.R':'ad976f7a','tests/testthat/test-dibble-expressions.R':'ad976f7a','src/init.c':'725974a','tests/testthat/helper-generation-interrupt.R':'725974a','tests/testthat/test-mutate-data.R':'725974a'}
variant_records=[]
for rel,commit in variants.items():
 p='r-package/dtatools/'+rel
 blob=git('rev-parse',source+':'+p).decode().strip()
 assert blob==git('rev-parse',commit+':'+p).decode().strip()
 variant_records.append(dict(path=p,reviewed_variant=git('rev-parse',commit).decode().strip(),git_blob=blob))
assert not git('diff',base,source,'--','r-package/dtatools/NAMESPACE','r-package/dtatools/DESCRIPTION','r-package/dtatools/R/dibble-dplyr-context.R','benchmarks/r-dibble-dplyr/run-expression-checks.py','benchmarks/r-dibble-dplyr/expression-checks.R')
assert subprocess.run(['git','diff','--check',base,source],cwd=repo,capture_output=True).returncode==0
progress=(repo/'docs/plans/dibble-result-performance-progress.md').read_text()
assert 'dependent case was not separately minimized' in progress
reports=['repair-guard-source-evidence-review-01.json','mask-names-source-install-review-01.json','mask-names-full-evidence-review-01.json','native-generation-fix-review-01.json','native-generation-final-evidence-review-01.json','width-profile-evidence-review-01.json','repair-guard-measurement-review-01.json','mask-names-measurement-review-01.json']
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='combined_actual_source_and_documentation_clear',reviewed_base=base,initial_combined=initial,final_combined=source,package_tree=package_tree,reviewer_script=ident(__file__),changed_files=[ident(repo/p) for p in paths],variant_blob_checks=variant_records,prior_bounded_reviews=[ident(review/p) for p in reports],assessment=[
 'The actual combined diff was read in context, including all changed R/C code, helper and public tests, native generation protection/return paths, metadata-copy callers, mask cleanup and four documentation files. Exact variant blob equality supplements that review; it is not its sole basis.',
 'The non-data.table early return occurs after C_dtatools_metadata_copy has produced the isolated metadata handle. It preserves all copying, markers, captured values and ordinary-table capacity repair. It does not bypass ownership copying or native validation.',
 'Mask name history preserves unique first-seen scalar character names. Removing and re-adding a name leaves one expiry promise while every generation retains its own metadata copy and weak cleanup reference. The current-column order, old capture values, group IDs, delayed obsolete-read warnings and release of generation values/chunks/groups/rows remain unchanged.',
 'The native control remains private and unarmed by default. Both generation entry points copy and reset it before validation. Numeric compact, numeric double and character checkpoints keep staged values protected and private before return/install; no table slot or reference state is committed by the checkpoint. Existing polling loops and ordinary zero-mode installation policies are unchanged.',
 'The native control is armed only by the private test paths. Metadata-copy and name-history changes do not arm it or share its state. Real native errors/interrupts still unwind through existing evaluator/context cleanup; the two R changes add no callback, persistent group root or delayed source handle.',
 'The seven-case helper tests preserve the original compact numeric/character/dictionary cases and add double first/existing cases, alias/reference/cache checks and successful retries. POSIX readiness precedes SIGINT, with bounded waits. Native entry and scoped R validation unwind both disarm the control.',
 'The added public test checks removed/re-added captured generations during the call, both post-call obsolete reads and the shared interrupted-promise warning, final output order and isolation after a later input write.',
 'CONTRIBUTING describes the private readiness procedure. ADR and NEWS describe the setup changes without relabeling prior measured libraries. The corrected progress text confines the12-row minimization to retain and explicitly states dependent was not separately minimized. Both distinct source variants, unproven original CI cause and pending combined qualification retain their scopes.',
 'NAMESPACE, DESCRIPTION, optional dplyr adapter and qualification runners are unchanged in this combined delta. The final progress-only correction has the same package tree as a2d8b6a; gates running with exact a2 identities must retain those original source/runner identities.'
],resolved_findings=[
 dict(kind='documentation_scope',initial_source=initial,issue='Initial progress text could imply that the12-row retain witness minimized both flagged cases and excluded payload size as the main cause for both.',fix_source=source,resolution='Actual corrected diff distinguishes three width repeats for both cases from the12-row retain-only minimization and states dependent was not separately minimized.'),
 dict(kind='status_clarification',issue='Diagnostics evidence branch is based on helper head805cc079 while progress says PR201 remains unmerged.',resolution='Parent confirmed root current20:01 capture has15CI passes but no substantive review and a rate-limited uncompleted CodeRabbit action. Diagnostics branch is stacked and unpublished, so the existing no-merge claim is consistent. No external action was taken by this reviewer.')
],limits=[
 'Source and documentation clearance only. Fresh combined exact installation/full/package/Rust/native and minimum-runtime evidence remain subject to their separate reviews. This report does not mark those gates complete.',
 'Earlier57309,622,ad976 and725 measurements and tests keep their exact source/library identities. None is relabeled as a result for the combined native DLL or final package tree.',
 'Full performance, memory/write-cost acceptance, external substantive review, CI and normal merge remain pending. The bounded width observations alone do not satisfy them.',
 'No tests, builds, R operations, profiling or timing runs were performed for this review. No production or documentation files were edited by this reviewer.'
])
with (review/'combined-source-review-ea031-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],source=source,package_tree=package_tree,files=len(paths),exact_variant_blobs=len(variants),report=str(review/'combined-source-review-ea031-01.json'))))
