# Direct dibble epic progress

Starting main: `5ad44406f9b80db81789dcf7b7e1756c28502559`.
Issue: https://github.com/jbearak/dta-parser/issues/172, still open.
Contract: [implementation plan](dibble-result-performance.md), with the user's
authorized sequential PR, independent-review and CI process. Implementation PRs
require substantive CodeRabbit review. Under the user's September 8 update,
evidence-only PRs use the dedicated evidence reviewer and do not require
CodeRabbit. Its documentation-coverage warning is always nonblocking. The
original orchestration prompt was supplied outside the repository; its operative
decisions are recorded in that plan.

## Stages 1 through 5 complete, Stage 6 active

Stage 5 [PR #205](https://github.com/jbearak/dta-parser/pull/205) merged normally
at 2026-09-08 12:29:53 UTC as
`b2751d2dbf195557021cc5c5aa2d87a20cae69a7`. Root verified both parents, the full
tree against reviewed head `f3b8b984c6a9ea5a0f062eee70e392bb567e5042`, all 16
successful checks and completed substantive CodeRabbit review with no remaining
actionable findings. The package tree is
`0c8de843cc29760286322ede0804ad5622cf2def`, identical to qualified f9. Its exact
host install, full tests and package gates passed; R check retains three warnings
and two notes, and its test suite reports 16,822 passes and four established
warnings. The separate Haven conformance run retains one loopback capability
skip. The correction-specific clean R 4.6.0 run reports 1,303 passes and one
memory-profiling capability skip. Earlier a2 performance/native evidence keeps
its original source identity.

Stage 6 is active on `codex/direct-dibble-row-operations` in
`/private/tmp/dta-direct-stage6`. Main subsequently advanced to
`235b6354f9b1f5878417255d3a20bc6501e69035` through the 0.8.0 version update and
[PR #208](https://github.com/jbearak/dta-parser/pull/208)'s macOS binary linkage
change. The unpublished Stage 6 commits were rebased onto that exact main.
Their row-operation and qualification-launcher changes remain intact; the
shared DESCRIPTION change retains both version 0.8.0 and the Stage 6 stringi
suggestion. The rebased package tree is
`e812870e38317facc0a7c349cd3fa2b0515244e6`.

Stage 6 owns direct filter/filter_out, arrange, distinct, slice and all five
slice helpers, reusing the shared evaluator and batch gatherer. A private native
accumulator preserves complete predicate evaluation and TRUE-only conjunction,
then applies filter_out inversion. It replaces the large temporary R buffers
identified in the first candidate. The predecessor test draft has 28
blocks; its first run exposed five draft expectation/instrumentation failures,
which remain preserved. The corrected draft passes 730 assertions on exact f9
with no failures, errors, unhandled warnings or skips. These are baseline
expectations, not Stage 6 candidate acceptance.

Before the rebase, exact source `6f9b6f327492f9b17702922c1341cd927644248e`
passed fresh host installation, 17,623 full-suite assertions, package and native
gates, and 5,955 assertions on the selected clean R 4.6.0 lane. Both reviewers
cleared the host and minimum installation, full-test and package records within
their scopes. The host suite has four
established warnings; package check has three warnings and two notes. Minimum
tests have four established warnings and four capability skips, including the
new allocation test on an R build without memory profiling. The host allocation
witness passed its unchanged budget. The first memory-smoke R child passed its
functional checks, but its time launcher failed on a sandbox-denied system
query. That failed attempt has no accepted RSS result and no candidate child.
A separate approved time/true capability probe succeeded; a fresh smoke remains
required.

Those 6f results retain their original 0.7.1 source and installed-library
identities. They do not qualify the rebased 0.8.0 artifact. Fresh installation,
host/minimum/package/native and Rust qualification remain pending for the new
source, including the new macOS linkage check on installed and binary DLLs.
The changed Cargo manifests and lockfiles also end the prior exact-input reuse
of the 057 full Rust gate. Final whole-row timings, the original ec10 owned
comparison and isolated row-memory qualification remain pending. The rejected
057 performance results remain preserved. The three original whole-filter flags
are one-million-row, eight-column cases and remain mandatory Stage 6 work;
twelve base-R read costs remain visible for final assessment. Stages 7–9 and
final actual downstream renv validation remain required, and issue #172 stays open.

The following Stage 5 paragraphs retain their historical checkpoint status.

Stage 4 [PR #195](https://github.com/jbearak/dta-parser/pull/195) merged normally
at 2026-09-07 15:23:12 UTC as
`f622f1ddba04b2bb7ac07415faccf2b417aab0e6`. Root verified the remote merge,
its exact match to final reviewed head `443e548ac3280d279587ad5024d200cf15ccedb0`,
all 15 passing CI checks and completed substantive CodeRabbit review. The package
tree remains `f88005766aee9b9dd5827b33a3930feff6672008`, identical to qualified
`c8ca0a4`. The receipt is retained at
`/private/tmp/dta-direct-stage4-validation/pr195-verified-normal-merge.json`.

Stage 5 is active in [PR #205](https://github.com/jbearak/dta-parser/pull/205),
on `codex/direct-dibble-expression-engine` in
`/private/tmp/dta-direct-stage5-source-pr`. Its base is verified PR #207 merge
`9d3de66b5f59da66dace7da704ad1d5d5df28ce0`. The implementation
covers a shared expression evaluator, direct mutate/transmute and computed
grouping, including rowwise/ungroup assembly. The standalone helper proof passes
35 bounded cases on real dplyr 1.2.1 under R 4.6.1 and qualified clean R 4.6.0.
It proves context feasibility, not production evaluation, ownership or capture
parity. The implemented evaluator retains obsolete-mask errors for deferred
reads and types each expression before dependent expressions. Both independent
combined-source reviews and exact-source host/minimum integration gates pass.
External latest-head review, CI and normal merge still gate Stage 5 completion.
The twelve base-R read costs remain open for final assessment, and the three
filter timing flags remain mandatory Stage 6 work. Stages 6 through 9 and the
final actual downstream renv validation remain required; issue #172 stays open.

At the September 8 review-correction checkpoint, source
`f9b531f862cec2a77c6f043bb64be15d4b51b824`, package tree
`0c8de843cc29760286322ede0804ad5622cf2def`, fixes three confirmed findings.
The dplyr version guard now compares numeric components. The interrupt helper
drains child stderr and retains its latest 100 lines for timeout diagnostics.
Both Python qualification runners finalize failures during setup. New tests
reproduce the original defects, and both independent reviewers cleared the
actual corrections and retained evidence. Eight public grouping observations
contradict the reported `.data` label defect; no grouping change was needed.
The historical preparation count is independently verified as 27 unique inputs,
and that review thread is resolved without rewriting executed scripts.

Fresh f9 installation and full host tests pass 16,822 assertions with no
failures, errors or skips and four established warnings. Fresh clean R 4.6.0
installation and the two changed test files pass 1,303 assertions with no
failures, errors or warnings and one existing memory-profiling capability skip.
The new version and stderr regressions pass in both runs. Seven injected Python
setup cases and the three existing integrity test methods pass in normal and
optimized Python. The f9 package phase and latest-head external/CI gates are
still pending at this checkpoint. These corrective runs do not replace or
relabel the a2 performance, native and broader minimum-runtime records below.

Evidence PRs #201 through #204, #206 and #207 have merged normally. The original
source assembly and publication checkpoints below retain their historical
revision labels. The active publication is PR #205; the old unpublished
assembly descriptions are not its current status. Local correction records are
under `/private/tmp/dta-direct-stage5-validation`, including
`pr205-setup-finalization-01`, `pr205-package-observations-01`,
`implementation/*-pr205-f9b531f-01` and
`root-r460-integration/candidate-f9b531f-v1*`.

The first Stage 5 exact source checkpoints are `27d700d` and `985e26b`.
Both installed from Git archives through a bound, tracked installer; these are
validation candidates, not merged acceptance results. Two independent reviews
found and fixed duplicate unpacked names, warning aggregation, persistent-key
deletion, rowwise data-frame columns, symbol-result metadata, caller labels,
renamed ungroup selectors, custom row names and expired-mask payload retention.
Weak references retain cleanup access without owning superseded uncaptured
column generations. Exact-source focused/full/package checks are underway.

Final source review also restored repeated interrupted-promise warnings after
mask expiry and preserved validated group ordering when mutate/transmute leave
grouping keys unchanged. Independent probes compare nine expired reads and
eight payload-lifetime cases. The original exact `985e26b` focused run passed
7,608 assertions with four established warnings, then failed in its namespace
reporter; that failed record remains retained. The reporter fix and subsequent
source changes required fresh exact-installed qualification.

Those earlier local gates passed on package source `57309d4`; its fresh
Git-archive installation and corrected package checks are preserved in the
[qualification archive](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-qualification/README.md).
Its R checks pass 16,624 assertions with no failures or skips and the four
established test warnings. The three R check warnings and two notes retain their
prior categories; a new NEWS parser sub-note found during review was fixed and
the earlier record remains unchanged. Full installed tests, five fresh Cargo
gates, unchanged native mutation gates, 18 atomic allocation cases, rename
allocation, interoperability, pinned roxygen, source/binary archive and NOTICE
checks passed. NAMESPACE remains identical with 106 exports.

The paired expression matrix later reproduced overhead in two 64-column cases.
Three paired width repeats confirmed both cases. A 12-row, 64-column retain
case preserved its signal, excluding payload size as the main cause of that
retain overhead. The dependent case was not separately minimized. Ordinary sampling profiles
identified eager setup costs in table repair checks on atomic columns and in
rebuilding the name set for each column. Separate exact source `622ffc19` adds
only the non-data.table repair guard. Source `ad976f7a` then replaces mask-name
union with membership-guarded append and adds a public remove/re-add/capture
test. The latter full suite passes 16,632 assertions without failures or skips
and with the four established warnings. Its unchanged six-case width loop
clears the combined greater-than-10-percent and greater-than-1-ms diagnosis
threshold against its same-source safe reference. These bounded measurements
retain their original libraries and do not qualify a later combined source.

A macOS CI failure on the unchanged Stage 4 package also exposed a limit of the
fixed-delay generation interrupt test. An induced one-second signal delay
reproduced its failure pattern after generation had already committed. The
original CI timing was not logged, so its cause remains unproven. Separately
reviewed source `725974a` replaces that timing assumption with a private native
checkpoint after staged generation and before installation. Native interrupts
and real POSIX SIGINT both exercise seven named cases, checking unchanged
values, names, aliases, reference state and dictionary caches, then a successful
retry. The control is consumed once at native entry; helper cleanup also
disarms it when R validation fails before entry. Focused/full and deliberately
delayed readiness checks pass on that separate source.

The three source changes are integrated in package source
`a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9`, package tree
`b08c77d91bdce67032f13aced90c29d068d6e95a`. Both independent combined-source
reviews and the following exact-source gates pass:

- Host installed full tests and package checks: 16,750 assertions, no failures
  or skips, four established test warnings. R check retains three warnings and
  two notes in the established categories. All 16 package commands, including
  conformance, interoperability, roxygen and source/binary NOTICE/export checks,
  pass. The 106 exports remain unchanged.
- Five fresh Cargo gates pass, including 278 tests and the existing 11 package
  test-exclusion warnings. Native preflight, mutation, 18 atomic allocation
  cases and rename allocation pass. The 410 retained native metrics agree
  between log and report; no inferred dynamic assertion count is claimed.
- Clean R 4.6.0 installation and integration pass: eight behavior cases, four
  helper expansion forms, and 8,859 focused assertions, including 187 expression
  assertions. Two Arrow and one profiler capability skips, plus four established
  warnings, remain explicit. This is not minimum-runtime profiling acceptance.
- The full expression matrix retains 50 series and 350 raw samples per source.
  All 100 comparisons recalculate with zero candidate-direct flags against predecessor
  or same-source safe reference. One safe-reference pipeline flag did not recur
  in three paired repeats; the original flagged observation remains retained.
- Paired expression writes retain 40 series and 280 samples with no same-mode
  timing flags. Eight isolated memory runs and the broader owned matrices pass
  their value, metadata, alias, allocation and retained-memory checks. Live
  vector heap, cumulative allocation and process RSS remain separate metrics.

Both independent reviewers audited these retained outputs and their exact
source, runner, library and input bindings. The native atom runner observes
nonpackage prose head `ea031bec`; its two consumed helper files equal a2 and
are bound. Every installed package and runtime result retains its own source
identity. The original older installs, failed attempts and measured variants
remain unchanged. Public provenance refs preserve the combined, mask-name and
native-interrupt source histories.

The original ec10-to-a2 matrix still has twelve base-R read flags and three
Stage 6 filter flags. Three fresh read pairs reproduce all twelve at one million
rows, and a one-column minimization retains them. Character anyNA and three
logical/factor/ordered nonmissing-count controls show that pre-extraction keeps
the measured gap while matched rooted pointer scans remove the between-source
difference. Their compiled Elt loops do not isolate a base getter's absolute
cost or prove one cause for all twelve. The [read-cost disposition](../research/stage5-base-r-read-costs.md)
records the measured limits, primary R paths and unproved implementation options.
The separate fresh Arrow write flag did not recur in three paired repeats.
No overall read-performance acceptance or irreducibility claim is made.

The minimum evidence merged normally in PR #200 as
`220ac07a33323398f4b78d4cb23fd9ba9bd808be`; its package tree is unchanged. Helper
evidence PR #201 at `b2e5c47` has all 15 CI checks passing. At the 2026-09-07
23:29 UTC checkpoint, full CodeRabbit review `5135750178` has identified two
archive issues: current repeat-command guidance and a missing file-mode check.
Those fixes and subsequent latest-head gates remain required before normal
merge. The documentation coverage warning is nonblocking. Evidence archives
and the implementation retain focused external review scopes. Stage 5 remains active until its normal implementation
merge; stages 6 through 9 and final downstream validation remain required.

The earlier exact clean R 4.6.0 evaluator source `4900dc8` passes 179 expression
assertions without failures, skips or warnings. Its broader focused run passes
4,960 assertions with three classified Arrow/profmem capability skips and four
known warnings. Both reviewers verified that NEWS is the only package byte
difference between this source and `57309d4`; the earlier runtime results keep
their original identities. An optional clean-runtime NEWS parse probe lacks
commonmark and remains a retained setup failure, separate from the successful
host parser and final package checks.

The [diagnostic archive](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-diagnostics/README.md)
preserves prior implementation failures and source-review reproductions.
Both independent reviews clear the historical qualification and combined-host
inclusions, all five measurement/diagnosis bundles, and the plain read-disposition
proof archive. The assembled 247-path measurement evidence passed both actual
diff reviews and is committed as `d152775b1c7fa3824d922f794b3913e37addbffb`,
unpublished pending its preceding normal merges. The final implementation
assembly has 209 changed paths and retains the tested a2 package tree and gate
helpers; its actual assembled-diff reviews are in progress. Earlier prose
snapshots remain unchanged in the proof archive. External substantive review,
CI and normal merge remain required before Stage 5 completes.

The [preparation archive](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-preparation/README.md)
preserves the 181-file selective minimum preview and both complete indexed
helper proofs. Production and evidence will use focused review scopes. ADR 0034
records the explicit dplyr 1.2.1 minimum correction and the bounded older-binary
limits. It also records two intended corrections from the delegated wrapper:
unnamed across follows real dplyr expansion order/setup counts, and within-call
captures retain their original generation and group. Post-call deferred reads
still fail with the obsolete-mask error. Grouped computed operations preserve
dataset attributes through the shared finalizer. No optional-dependency or
complete-epic claim follows from this work.

The following Stage 4 record retains its historical premerge status and evidence.

The original evidence and additive review supplement merged as
[PR #196](https://github.com/jbearak/dta-parser/pull/196) and
[PR #197](https://github.com/jbearak/dta-parser/pull/197). The review-fix diagnosis
and local qualification then merged as
[PR #198](https://github.com/jbearak/dta-parser/pull/198), followed by paired
benchmark evidence in [PR #199](https://github.com/jbearak/dta-parser/pull/199).
The implementation [PR #195](https://github.com/jbearak/dta-parser/pull/195)
remains open. Its actual
34-file review at `75b0c54` found an incomplete native-runner output guard and
an unnecessary first-write copy in fresh unnamed string construction. A width
conversion lifetime comment also reproduced: Latin-1 scans retained temporary
R conversion buffers until the enclosing native call returned.

The fixes are committed and qualified at
`c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe`, package tree
`f88005766aee9b9dd5827b33a3930feff6672008`. Both nested source reviews are clean.
The [new report](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage4-review-fix.md)
and [indexed archive](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage4-review-fix/README.md)
retain exact-source local qualification, independent constructor and temporary
memory red/green probes, and fresh paired baseline/candidate measurements.
All 16,445 full-suite assertions pass without failures or skips. The unchanged
159 native assertions and 15 readiness checks, 18 atomic allocation cases,
rename allocation, 219 independent R cases and strict isolated downstream
log/state parity pass. Five fresh Cargo gates bind all 1,950 input files before
and after each command and retain the actual verified 27-member package. No
historical workspace reuse argument qualifies this new source.

The later [output-content qualification](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage4-output-integrity/README.md)
adds a full before/after digest for one fresh isolated c8 run, preserving the
earlier metadata-only records. The [comparison-identity audit](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage4-comparison-integrity/README.md)
verifies the unchanged measured comparison inputs, with 87 synthetic guard
cases. These supplements do not retroactively strengthen historical checks,
retest performance, or complete the actual fertility renv restoration gate.

The fresh paired matrix retains exactly fifteen read flags: twelve base-R
operations and three delegated filters. The Stage 6 filter criterion below
remains required; these results do not establish broad read-performance or
integrated epic acceptance. Internal promise ordering, names dispatch and
conservative dictionary/foreign fallbacks remain covered. Useful ownership,
temporary-memory and runner documentation was added to active code; the two
Python driver changes have identical ASTs after removing docstrings. The later
two preflight helper docstrings are likewise executable-AST equivalent; archived
c8 executions retain their original input hash. CodeRabbit could not provide
the function list underlying its advisory 20.15% report, and this work neither
invents that inventory nor changes the configured threshold. Aggregate CodeRabbit
documentation warnings are always nonblocking under the user's instruction.

The four established test warnings, eleven existing Cargo package warnings,
three R check warnings and two notes remain disclosed. The earlier dated reports
and historical artifacts retain their exact bytes. Both independent evidence
and supplement reviews are clean. Latest-head substantive CodeRabbit/CI and
normal merge still gate Stage 4. Stages 5 through 9
and the final actual downstream renv install/test/original-lock restore remain
required; issue #172 stays open.

Stage 3 merged normally as [PR #194](https://github.com/jbearak/dta-parser/pull/194)
at 2026-09-07 02:14:48 UTC, producing
[`ec10a6ac34602f3bd691e8043019c1b479babda4`](https://github.com/jbearak/dta-parser/commit/ec10a6ac34602f3bd691e8043019c1b479babda4).
Root verified that its tree exactly matches reviewed head
`aa72adc490383934f32732653fce73d54195dc9d`. All 16 checks passed, including
Windows package and interoperability checks. CodeRabbit completed substantive
review `5127382991`, run `4c8772f2-896c-4674-bde5-6c96e308a611`, on that exact
head. All seven threads are resolved. The final provenance claim received
[explicit withdrawal](https://github.com/jbearak/dta-parser/pull/194#discussion_r3946004031)
after both independent round 22 reviews and the reviewer checked the unchanged
historical manifest blobs. No historical evidence was relabeled. The separate
docstring metric remains advisory under its unchanged review configuration.
The final audit and merge proof are retained in
`/private/tmp/dta-direct-stage3-validation/final-aa72adc-external/manifest.json`
and `stage3-merge-verification.json` in the same validation directory.

Stage 4 is active on `codex/direct-dibble-owned-atoms`, in the isolated
`/private/tmp/dta-direct-stage4` worktree based on that merge. It extends owned
backing to ordinary strings, logicals and integer/factor columns, with reusable
storage facts, writable-pointer handling and transactional invalidation.
The implementation agent has both nested independent actual-diff review roles,
`storage_review` and `api_review`, under `/root/stage4_implementation`. Root owns paired benchmarks and independent acceptance. Stages 5
through 9 and final integrated/downstream validation remain required; issue #172
stays open. Stage 4 implementation is in progress; no Stage 4 acceptance result is claimed
yet. Root's exact merged baseline install is in
`/private/tmp/dta-direct-stage4-validation/baseline-library`. The working library
and focused logs are under the same validation directory. The new atom suite
passes its current representation, pointer, storage-fact, alias, ingress,
serialization and callback-row cases. These development builds are not measured
source identities.

The first nested storage review found stale subset facts across foreign index
callbacks and unrooted native row/writer payloads. The fix discards subset facts
for callback-capable indices, roots exact ordinary allocations and compact
numeric descriptors, and checks consumed rows against their original bounds.
A further dictionary lifetime review found that materialization can explicitly
free a descriptor even when the original ALTREP is rooted. The candidate adds
call-local native descriptor pins with a Rust reference count; qualification of
this fix is underway. No column/table registry or table back-pointer is added.
The API review requested broader export, factor, borrowed-representation and
serialization coverage, now present in `test-owned-atoms.R`. Public factor
replacement restrictions remain unchanged.

The full development run (`working-install-9.log` and `full-working-9.log`
in the validation directory) passes all R tests, including the new callback,
missingness-counter and export cases. It retains the four established warnings:
factor conversion, temporal comparison methods, and two tibble row-name
warnings. The earlier five failures in a borrowed-string fixture are corrected
by installing and proving an actual foreign slot through the native interface,
while separately preserving the public capture-isolation check and every
stale-width/missing-value expectation. The intermediate run 8 exposed only an
incorrect test assumption that R's string `anyNA` calls `STRING_NO_NA`; the test
now invokes that public native API directly and separately checks `anyNA`.

Legacy transactions now capture unknown ALTREP operands before native reader
retention, journaling and writes. Their original-target checks also cover
replacement-length, row and declared-width callbacks. The revised regressions
and existing rollback suite pass. Both the Rust workspace (278 tests,
formatting, Clippy, documentation and packaging) and isolated bridge (18 tests,
formatting and check) pass. Exact committed-source gates remain required.

Root owns the new `owned-atomic` benchmark family and its guarded Python driver.
Development smoke at 8/40 rows passed 206 operation/read cases, 126 post-read
selector checks and 18 public write cases. The driver CLI guard suite passed 87
cases under ordinary Python, `-O` and `PYTHONOPTIMIZE=1`; these are runner checks,
not full-size allocation/timing acceptance. The exact-source pair, required local
gates, final nested reviews, PR and latest-head external review/CI remain pending.
Both nested reviews clear the benchmark executable files committed as
`b259ad5a521dbb867a0b8563e3a0c2262e298671`. Root completed the exact merged
Stage 3 baseline: 206 atomic operation/read cases, 126 post-read selectors,
18 writes and 30 isolated memory processes. A fresh existing owned-double
baseline also passes 46 operation/read cases, 30 post-read selectors, six writes,
four snapshot/where rows and six isolated memory processes. The successful
atomic memory retry used permitted system access for peak RSS; the earlier
sandbox-denied attempt remains preserved separately. Durable
review reports and exact diff identities are under
`/private/tmp/dta-direct-stage4-validation`; package acceptance remains pending.

The first committed package candidate, `7d56080f3e97bc4d73a848e363d729767b9629c0`,
passed the exact local gates and original 159 native assertions plus 15 readiness
checks. The required R check retained the established three warnings and two
notes. The native atom supplement exposed a large-factor fixture using a foreign
R metadata wrapper; runner-only commit `80e636e` adds genuine ordinary factor
construction and explicit ownership preconditions without changing budgets.
Its corrected full supplement was pending at that point and subsequently passed
on `e343b3b`, as recorded below.

The [initial Stage 4 report](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage4.md)
and 157 immutable evidence artifacts are committed as `ca6b678e`. Both nested
reviews clear their presentation and identities. The full atomic pair passes
its measured correctness, allocation and memory checks but has 43 read regressions;
it is not accepted. The paired existing owned-double matrix has no flagged
read regression. Root's additional 219 R comparisons pass their preserved
oracles. Later tests exposed an owned-string Arrow writer callback error and
foreign constructor aliasing outside the original matrix. Those failures remain
preserved separately; they do not relabel the original measurements.

Read fixes now cache rooted gather pointers, avoid copying already UTF-8 owned
strings during DTA planning, retain exact string writer allocations, and adopt
fresh Arrow atomic buffers. Internal string metadata restoration preserves owned
handles and facts. Explicit string construction captures borrowed values before
removing incoming metadata and validates the actual captured values after
callbacks. New tests include large vectors, foreign data.table mutation in both
directions, encoded attribute names and public names replacement dispatch.
Development measurements put string row subsets below the baseline and DTA/Arrow
writes near it after eliminating avoidable scans and copies. A separate gather
probe found the native discrete loop faster than ordinary subset, while repeated
base subscript validation inside vctrs added table cost. A narrowly qualified
whole-batch route now reuses the shared planner's validated locations for its
vctrs policy. Base-frame and foreign/callback fallbacks retain their prior order.
Focused metadata, padding and alias tests pass; final paired measurements and
the remaining per-element read costs are still under investigation.

A separate getter experiment compared record lookup, direct payload lookup,
typed access and an R-managed external-pointer cache. The retained cache roots
its ordinary allocation and facts together and removes one lookup per element.
It does not change the data2 transaction state. Header-only development rebuilds
initially reused an old object; that failed identity check is recorded in
`working-17-stale-object-disclosure.json`. Explicit header dependencies now force
recompilation. Exact archive qualifications were unaffected.

Known factor deep duplication now returns a fresh ordinary integer copy, and
public logical subsets return their fresh ordinary result directly. Private
table gathering still adopts its fresh buffers. Development measurements put
ordered-factor range at 2.615 ms against 2.753 ms on the baseline, with the same
R allocation. Logical mean falls from the initial 9.90 ms to 3.876 ms, against
1.84 ms on the baseline. The current 30-case development read matrix has no
gather or writer flags. Ten missingness/coercion cases still add 1.8–2.4 ms per
million values, with unchanged R allocation. Logical mean and integer coercion
also retain about 2 ms of additional element-dispatch cost. These are unresolved
acceptance costs, not a clean final result. Working build 20 and its focused
tests are development evidence; final exact-source paired measurements remain
required. The separate heap supplement reports Ncells as well as Vcells so the
new record representation cannot hide header allocation.

Reviewed source `976cc40` passed a fresh archive installation, standard full R
check with the established three warnings and two notes, interoperability,
roxygen and source/binary NOTICE checks. Root's 219-case and downstream baseline
comparisons also passed. Its original native runner then failed the unchanged
dictionary replacement timing bound. A retained diagnostic run reached the
strict four-times-fill boundary, and paired allocation profiles found two
additional 2,000,048-byte dictionary buffers in the new attribute helper's
fallback. Source `976cc40` is therefore not accepted. The fix keeps declined R
attribute assignment in its original caller frame; development profiling removes
both extra buffers. No native assertion or numerical budget changed. Final
review, fresh source qualification and paired performance acceptance remain
required for this follow-up.
The corrected working build 21b passes the unchanged 159 native assertions and
15 readiness checks. Dictionary replacement takes 32 ms against a 12 ms fill
reference and allocates 44,017,136 bytes, matching the earlier allocation.
Those logs are explicitly development evidence, separate from `976cc40`'s
failed exact run.

Both follow-up reviews are clean at `e343b3b56a8529e9ee0ac40f8bd88beebcd2be15`,
package tree `f12a2a1dd430636a33b7f6e953023d90d1ff2589`. A fresh archive install
passes every local gate, including the unchanged 159 native assertions and 15
readiness checks, all 18 integer/factor allocation cases, and the saved rename
gate. Exact R check retains the established three warnings and two notes. The
final bridge has 18 passing tests. The earlier core workspace reuse argument
based on three Git objects was insufficient to establish the commands' working
inputs; the fresh five-gate qualification below supersedes that claim. Guarded
replays fail on `7d56080` and pass on
the final source for the writer callback and foreign constructor defects.
The [qualification archive](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage4/qualification/README.md)
records exact identities, original failures and gate scopes. The
[diagnosis archive](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage4/diagnosis/README.md)
retains prototype source, raw profiles, corrected fixtures and stale-build
disclosure. Both nested evidence reviews clear the 252-file qualification and
diagnosis snapshot, including the 247 original copied artifacts. Later filter
diagnosis and its staged disposition have a separate review scope.


The [review supplement](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage4-review-supplement/README.md)
is submitted as [PR #197](https://github.com/jbearak/dta-parser/pull/197) at
`0bb559e80af119264f87c4fcd06a65287230db0d`. Its
[fresh workspace manifest](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage4-review-supplement/workspace-gates/manifest.json)
records formatting, Clippy, 278 tests, documentation and verified packaging from
a clean detached checkout of exact `e343b3b`. Full 1,060-file byte/mode inventories
and empty status including ignored files match before and after all five
commands. Packaging used no `--allow-dirty` and retains eleven existing warnings
about excluded test targets. The verified crate and its 27 members have separate
identities. This new qualification replaces the insufficient historical workspace
binding; the original proof, logs and dated report remain unchanged. The three
R check warnings and two notes remain part of the earlier exact R qualification.

The supplement also supplies 29 missing review inputs, restores executable
copies of sixteen command fixtures, and qualifies explicit-library diagnostic
replay without upgrading historical development logs. Both nested reviews clear
its final 161-file scope. The local normal merge `3323149695552dbddb62af60ad8c1027f911cef0`
adds the supplement to the implementation branch and leaves package tree
`f12a2a1dd430636a33b7f6e953023d90d1ff2589` unchanged. This is local ancestry,
not a completed main merge. Implementation [PR #195](https://github.com/jbearak/dta-parser/pull/195),
historical evidence [PR #196](https://github.com/jbearak/dta-parser/pull/196) and
the supplement still require their substantive external review, CI and normal
merge gates. Fresh merged-main installation and tests in the actual fertility
renv, followed by restoration from the original lockfile, remain final epic
obligations.

The exact `e343b3b` atomic matrix passes its value, allocation and memory guards.
Both the original and fresh baseline comparisons flag the same 15 reads at one
million rows. Twelve involve per-element missingness, aggregation or coercion work; three
are `filter()` on logical, factor and ordered-factor tables. The filter predicate
does not read source columns, so those three costs require a separate diagnosis
of delegated slicing and result capture. The later
[21-case diagnosis](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage4/diagnosis/filter-planning/filter-planning-diagnosis-findings.md)
measures owned snapshot slicing at 4.68–4.78 ms, ordinary slicing at 1.37–1.41 ms,
and the existing validated batch at 1.60–1.64 ms. Predicate overhead is comparable;
logical closure adds a 16 MB capture, while factor closure captures no payload.
The initial failed benchmark-result setup and sampling/trace limitations remain
preserved. No package change follows this diagnosis.

Root's remaining owned-double and heap matrices pass, with no owned-double read
threshold flags. Stage 4 storage may advance on its correctness, allocation,
native and memory qualification, while the three filter regressions remain an
explicit required Stage 6 criterion before epic acceptance. The twelve
per-element costs remain visible measured tradeoffs, with no claim of broad
read-performance acceptance or universally negligible slowdown. Stage 4's final
external review/CI and normal merge gates are still pending across the focused
PRs; all subsequent stages and final integrated performance qualification remain
required.

### Stage 3 accepted qualification

Stage 3 implementation and local acceptance use source
`08b086ccd338d394420112cf9f550d355e94cb24`. The
[measured report](../../benchmarks/r-dibble-dplyr/results-2026-09-06-stage3.md)
retains the exact Stage 2 baseline, rejected first candidate and earlier
`45f2ba4` qualification. The corrected final operation pair and all twelve
isolated memory runs pass with complete four-file runner identities. No final
operation exceeds both read-regression thresholds. The earlier historical
matrix and all original evidence retain their measured source labels.

The exact native runner passes every original 159 assertion and all 15 added
provenance/readiness conditions. Original budgets remain unchanged. Repeated
generation at 400 and 1,600 columns takes 0.122 and 0.816 seconds and profiles
3,256 and 12,856 R bytes above the original 1,000-byte threshold. The saved rename
allocation gate passes, with its largest dibble allocation at 40,056 bytes and
summed recorded allocations at 80,112 bytes.
Root's 237 ownership/compatibility cases and 30 separate before/after read-backing
checks pass. Independent API and storage reviews close the actual source,
tests and benchmark fixtures. Both round 20 reviews also verify all 201 evidence
artifacts, report calculations, provenance and unchanged historical records.

The final source archive passes the complete R suite with 15,482 assertions,
four established test warnings and no failures or skips. Required conformance
passes 22 TypeScript fixtures with 32,085 cell comparisons, ten deterministic
native cases, the fixture oracle and a fresh R build/check. The standard check
has the established three warnings and two notes. The earlier `45f2ba4`
`--as-cran` check returned no errors, five warnings and four notes; it is a separate check
mode, not a clean or same-mode baseline result. Its extra diagnostics include
the unavailable `checkbashisms` tool and inherited undeclared test imports.

Rust and vendor sources are unchanged from the earlier passing formatting,
Clippy, 278 workspace tests, documentation, packaging, isolated bridge checks
and 17 bridge tests. The same applies to all 32 archive/vendor unit checks,
vendor integrity, Rust source-hash checks and the corpus framework. On final
source, Haven conformance passes without skips with permitted loopback access;
Haven 2.5.5 helper and labelled 2.16.0 interoperability pass. Pinned roxygen2
8.1.0 leaves manuals unchanged. Earlier blocked or skipped attempts remain
retained as diagnostics rather than acceptance evidence.

Fresh source and macOS binary archives contain the same NOTICE as their
installed packages. All 106 exports are unchanged. Every one of the 832 original
git-export files remains byte-identical after checking. The provenance driver
now tests both owned-double runners and passes 28 rejection/no-output cases,
seven usage counterchecks, matching output, locale/copy and runner dependency
identity checks. Full logs
and artifact hashes are under
`/private/tmp/dta-direct-stage3-validation/checks-08b086c/`.

The downstream comparison on exact source is byte-identical to the preserved
Stage 2 output: 499 tests, the same four existing integration failure blocks
and two skips, with no column-reallocation warning. All 454 tracked/untracked
source hashes, branch/HEAD/status/diff and the ignored output file's size and
mtime remain unchanged. This closes Stage 3 compatibility comparison; it does
not turn that downstream suite into a passing suite or replace the final
integrated epic validation.

The original evidence and reproduction instructions are retained in commit
`53571eb92d3c4296e0d95b1824724dee5c8fa68a`. Corrected source is committed as
`08b086c`; reviewed final evidence is published as
`4172613921597b4be11b7b44ebe5c5fd1fe01a94`.
The final guarded reproduction update is `aa72adc`. PR #194 and its latest-head
external gates completed as recorded above. The qualification below preserves
its original source labels.

### Stage 3 external-review corrections

Windows CI on `6140a05` builds the package but terminates during its tests.
The reviewed diagnostics-only head `86d1db1` retains the full failed output and
locates exit status 3 at the first native append interrupt injection. The
preceding error-injection case restores all state successfully. A bounded local
subprocess reproduction confirms that CRT `SIGINT` delivery terminates R when
its usual POSIX handler is absent.

The correction enters R's documented native interrupt handler in the
two armed test controls and retains their disarm order and fallback errors.
The older native-write rollback matrix now also runs on Windows; separate
POSIX asynchronous signal tests are unchanged. The focused owned-column,
owned-read and mutation suite passes. The complete working suite passes 15,482
assertions with four established warnings and no failures or skips. Both
independent round 19 reviews close the native, test, documentation and benchmark
corrections. Exact-source checks pass. On published head `4172613`, Windows
job `101592812344` passes the package build/check that previously terminated,
and its failure-only diagnostic steps are skipped. All jobs on `4172613` later
passed, including Windows interoperability. All jobs on final head `aa72adc`
also passed before the normal merge.

External review also prompted explicit writable access to the private ordinary
string-view copy, while preserving allocation-free reads from its ordinary
source. The temporary view does not support direct element assignment or escape
into public evaluation. Independent native and public callback probes preserve
source and snapshot isolation. Serialization's writable exposure is the
materializing fallback explicitly allowed by the handoff; version 2/3 byte,
metadata, tag, alias and retained-pointer comparisons pass, and restored values
contain no live owned state. Permanent tests now cover both serialization
versions. CodeRabbit [acknowledged and resolved this finding](https://github.com/jbearak/dta-parser/pull/194#discussion_r3945814759),
accepting the later-copy cost as a Stage 3 tradeoff. No custom serialized class
format is introduced.

The saved rename checker now also checks summed recorded allocation while
retaining its original maximum-event bound and profiling threshold. Runner
identity includes the sourced shared `helpers.R`; a regression test changes
only that file in a copied runner and verifies that its identity changes.
Historical measurements retain their original identities. CodeRabbit
[agreed to preserve that history](https://github.com/jbearak/dta-parser/pull/194#discussion_r3945821144).
Fresh corrected baseline/candidate measurements pass with identities checked
against committed runner bytes and the actual runtime records. Both final
round 20 reviews are clean. The qualified head and three follow-up replies are
published. CodeRabbit resolved the allocation, serialization and internal
string-view findings. It later [verified the complete new runner identities](https://github.com/jbearak/dta-parser/pull/194#discussion_r3945997284)
and resolved that finding too.

The substantive review of `4172613` raised two further evidence issues. The
report now names the nine earlier owned-run directories and distinguishes the
three `historical-*` manifests, which already record `helpers.R`. The archived
Python execution driver uses integrity assertions that Python optimization can
disable. All 201 indexed artifacts, including that actual execution driver,
remain unchanged. The separate reusable driver uses explicit exceptions and
exclusive log creation. Its synthetic CLI suite passes 51 success and rejection
cases under normal execution, `-O` and `PYTHONOPTIMIZE=1`, including source
mismatch, subprocess failure, malformed identities and preservation of existing
output. These checks do not run timed R workloads. Both independent round 21
reviews are clean. The measured R runners and package source remain unchanged.
CodeRabbit [accepted the guarded reproduction driver](https://github.com/jbearak/dta-parser/pull/194#discussion_r3945997064)
and the historical-directory distinction. The final conflated provenance claim
was withdrawn as recorded in the merge entry above.

CodeRabbit [confirmed that its docstring metric is advisory](https://github.com/jbearak/dta-parser/pull/194#issuecomment-5563799860):
its active configuration uses warning mode and does not fail commit status. It
identified no concrete missing documentation or unmet merge requirement. No
review threshold or configuration changed.

### Earlier Stage 3 checkpoints

The working native runner round 9 passes every original
159 condition plus 15 provenance/readiness conditions, with no bound changes. On working
DLL `c3a298572b15a23671572d51b5778951`, 400 and 1,600 repeated generations take
0.123 and 0.855 seconds and profile 3,256 and 12,856 bytes above the original
1,000-byte threshold. These are modified-build diagnostics, not committed-source
qualification. The runner logs and Markdown are retained under
`/private/tmp/dta-direct-stage3-validation/native-runner-working-round9.*`.

The repeated-generation repair uses bounded native shape validation, direct
already-evaluated scalar generation and genuinely private resizable names.
A temporary length-only names value lets the public setter release the removed
attribute cell's reference before resizing. An unwind journal restores shape,
attribute order, names privacy and reference-state identity. ADR 0032 records
its small attribute allocations and catastrophic cleanup-allocation limitation.
Independent reviews closed names loss, a foreign class callback, a journal root
mistake and conservative copying caused by detached attribute cells. Storage
round 13 and the API reviewer inspect the final names fixes; root's 219 exact-baseline
compatibility cases and 18 strict reuse/copy/capture cases pass. Permanent tests
include 36 immediate-privacy rollback combinations and 60 private appends.

A final API probe then found method dispatch on an attributed `.env[[literal]]`
member during scalar eligibility checking. Both direct-read recognizers now
decline attributed or ALTREP literal members before generic operations; public
generation and replacement regression tests pass. Independent API round 11
and storage round 15 reviews close the fix, and native round 9 passes after
that final R change. The installed R database hash is
`af0a8331d16b5fefc4d90ee18b4f49df`; its unchanged DLL hash alone cannot identify
the R-only fix. Exact-source provenance will bind both before release.

Initial source commit `6dcb9af279237402eedd7ca4147bfb8ecdc76337` has a fresh
provenance-validated installation. Root's 237 behavior cases, the full owned
operation/read matrix, historical double matrix, and six isolated memory cases
pass their correctness and preservation guards. Performance does not pass.
Controlled ABBA repeats confirm seven read regressions: range and filter at
100,000 and 1,000,000 rows, and integer coercion, arithmetic and arithmetic
mutation at 1,000,000 rows. Exact pre-fix results and manifests remain under
`/private/tmp/dta-direct-stage3-validation/root-owned-repeat-*6dcb9af`.

Read fixes are in progress. The measured causes include repeated owned scalar
dispatch during validation and repeated writable pointer requests in base
range's argument concatenation. An independent ordinary range snapshot and
rooted native read/conversion paths are being qualified against the same
baseline behavior and performance gates. Complete checks on the final exact
source, final evidence reviews and PR remain pending. Nothing in this checkpoint
closes Stage 3 or substitutes a working build for qualification.

The corrected working DLL `bde1e78a7bb52f2a6284110364a47f72` and R database
`df00ab77aceccc2a628d9ebbe0edbf93` pass the new focused read suite and all 237
root compatibility/ownership checks. Independent API round 14 and storage
round 16 reviews inspect the final source, permanent tests and attribution
without remaining findings. Their bounded comparisons cover coercion warning
and argument behavior, constructor and missingness dispatch, range results,
pointer writes, aliases and callback collection. A diagnostic twelve-iteration
run reports 1,000,000-row filter at 27.16 ms and 50.10 MB allocated, arithmetic
at 18.42 ms, range at 6.50 ms and integer conversion at 0.57 ms. These working
measurements are feedback, not the final source-bound paired acceptance.
The complete working R suite passes 15,478 assertions with the four recorded
baseline warnings, no failures, errors or skips. Pinned roxygen2 8.1.0 leaves
the manual pages unchanged. Logs are `read-fix2-full-suite.log` and
`read-fix2-roxygen.log` in the same validation directory.

Stage 2 merged normally as [PR #193](https://github.com/jbearak/dta-parser/pull/193)
at 2026-09-06 18:20:48 UTC, producing
[`fd069a36832ed7c1bdedeed52a4281ecabb36e25`](https://github.com/jbearak/dta-parser/commit/fd069a36832ed7c1bdedeed52a4281ecabb36e25).
Root verified that its tree exactly matches reviewed head
`fc130fd722ec9428f451339fd77a689c7c6ad2ac`. All 16 checks passed; CodeRabbit
completed run `072b0e19-c200-4cb8-862d-f2bc14f1ea1d` with no actionable findings,
and all three threads are resolved. The withdrawn singleton/drop claim has
[explicit acknowledgment](https://github.com/jbearak/dta-parser/pull/193#discussion_r3944777128).
The retained evidence is in `/private/tmp/dta-direct-stage2-validation/`, under
`root-final-fc130fd` and `final-fc130fd-external/manifest.json`.

Stage 3 is active on `codex/direct-dibble-owned-doubles`, in the isolated
`/private/tmp/dta-direct-stage3` worktree based on that exact merge. It owns
ordinary-double capture, backing forks, native adoption and private writes,
including complete compact mutation/rollback qualification. Stages 4 through 9
remain pending. A fresh exact-source baseline installation reproduces both
prerequisites: 5,000,048 bytes copied on each sparse compact write, and a column
alias exported during private-seam expression evaluation changing unexpectedly.
Logs and the isolated library are in `/private/tmp/dta-direct-stage3-validation`.
The working implementation has owned double capture/forks, native adoption after
R/Rust/DTA/Arrow fills, read-only access, and staged numeric table transactions.
The development focused suite reached 1,816 passing assertions with no warnings
after native Stata-double RHS validation removed unnecessary scalar capture.
This is working-build evidence, not exact-source release qualification. The log
is `owned-ingress-green-1816.log` in the validation directory.

Correctness review round 1 found three actionable defects: a foreign ALTREP
callback could escape after the fused sharing guard; fallback prototype creation
forced repeated plain-double payload copies; and fused no-op/error work leaked
an original compact ownership claim. The independent reviewer inspected and
reran all fixes, closing those findings against development DLL MD5
`d9d238fa05de97c4c459b74692f56f06`, with a further direct fused-slot check against
`b8ad95063403c946e2416af1007783f6`. Actual callback preparation now precedes the
effective guard; native empty prototypes avoid sharing target values; working
compact captures do not revoke original claims. Retained red/fixed probes are
`review-fused-callback`, `review-fused-noop-claim` and `review-plain-private`.
The earlier root length-method escape and its comparison fallback variant also
have retained red/green evidence. These closures do not approve the final diff.

The next working full R suite passed 14,179 assertions with the four existing
warnings and no failures or skips (`working-full-suite.log`). A new independent
API review then found that constructor capture split identical owned-double
slots. Permanent constructor/conversion tests reproduced the changed explicit
write behavior; capture now reuses one handle per normalized input handle. The
focused ownership, row and reference suite passed 1,217 assertions, including
foreign-double ingress and public export tests, without warnings or skips.

Root's foreign-index callback probe also exposed an incorrect subset after the
callback detached the source and invoked GC. The permanent test reproduced
`c(11,12,13)` instead of `c(1,2,3)` before the fix. Owned subsetting now roots the
exact payload; compact subsetting freezes its descriptor and retains the raw
payload through index callbacks. Combined operand-callback tests cover new
aliases followed by no-match, error and interrupt paths. Separate native and
public materialized partial-write tests exercise journal restoration and
discarding detached work. A genuine noncanonical-NaN comparison decline tests
the remaining R fallback and isolation after its error and a later valid write.

Two attempts to resume the original correctness reviewer failed at the review
service with an automated cybersecurity classification. Exact requests and
returned errors are retained in `review-service-status.md`; neither failure is
an approval. A fresh independent numeric reviewer is reviewing the actual diff,
and the API reviewer is reviewing its fixes. Both final reviews remain required.

At that review point, migration of the native runner's 159 assertions and the
ordinary-string sparse-write prerequisite were unresolved. The resume update
below records their subsequent fixes and remaining qualification work. Final
checks, measurements and PR gates are pending. Stages 4 through 9 remain pending.

Resume review and implementation update, 2026-09-06: two new independent agents
reviewed the actual Stage 3 diff. The grouped Date proxy finding now has a
permanent red/green regression. A second review found that an unread captured
mutation environment could observe later writes, and that restoring an empty
mask parent broke deferred base/lexical lookup. Arbitrary expressions now receive
complete snapshot column lists; only literal values, direct symbol reads and
literal `.env` members bypass creation of a data mask. Root's independently
constructed shared/private delayed-capture matrices match the exact Stage 2
baseline in all 144 cases. A separate 30-case private active-binding matrix
matches baseline across numeric, logical, integer and string columns. These
results use development DLL `1b3591a6c153969f8976f8bfdc7bdd0a` and are not final
source-bound qualification.

The shared ordinary-string prerequisite now uses temporary internal read handles
whose source references are released after preflight/evaluation. Exposed masks
retain ordinary physical handles, and direct column reads receive an isolated
copy. Public string columns keep their ordinary representation; shared ordinary
string ownership remains Stage 4. Plain atomic table writes stage operands before
the late physical sharing check, closing the independent integer RHS callback
finding. The legacy direct-vector paths still retain journaled after-write
interrupt coverage. Three consecutive private string writes now keep the same
physical handle without the former 800,048-byte copies on a 100,000-row probe.
The latest working full suite passes with the four established warnings. A
further API review found a full string copy per group in the Date isolation fix.
The reviewed fix uses the common exposure boundary; independent measurements
show 12.94, 12.50 and 12.53 MB for 1, 10 and 100 groups, instead of growth with
group count.

The first native-runner fixture migration assigns column preparation before
generation and measures borrowed first capture separately from proven private
writes. The original first native-generated patch remains cold, and the shared
proxy, dictionary and foreign integer ALTREP fixtures retain their original
alias cases. The original 159 assertion expressions remain unchanged and in
order; a root-provided AST comparison confirms this. The sparse dictionary RHS
handle is acquired before timing, with all cache/source checks preserved. A
separate arbitrary-expression snapshot measurement must disclose its full
changed-column cost. Runner execution, complete timing/retained/peak evidence,
source-bound builds, full required gates and both final independent reviews
remain pending. No assertion bound has been weakened and no PR is open.

Further native-runner diagnostics found full R temporaries in numeric promotion
validation. A selected-value native fit scan preserves all five Stata numeric
storage boundaries and missing-value rules without those temporaries. Independent
reviews passed 500 and 1,175 paired fit cases, including fallback classes. Review
also found mutable foreign row indices and unrooted generic target handles.
The fixed fit loop checks each consumed row bound, and remaining detached generic
transactions root and revalidate the original handle and ALTREP state after
callbacks. Both findings were independently reproduced and closed against DLL
`b77634597474c97704b2ef9af4401041`.

The runner now precomputes the second proxy row index before timing. Its
near-unique dictionary target explicitly uses `read_arrow(output = "tibble")`
to retain the ordinary character representation required by the unchanged
value assertions. The default reader now produces typed dibbles; exact Stage 2
baseline evidence confirms the same class mismatch there. A later allocation
failure traced to decoding a full dictionary target solely for its empty cast
prototype. Known unclassed dictionary prototypes now use attributes alone; the
full changed-column destination remains measured. A further readiness check
confirmed that an ordinary R `data.frame(text = rep.int("", n))` enters shared,
so its first isolation capture is now measured before the private sparse RHS
kernel. Both reviewers accepted the actual migration. It retains physical
plain-string privacy checks and reports the first-capture cost separately.

The corresponding integer/logical cast prototype now also avoids old target
reads, and generic ALTREP full replacements allocate their result without
reading overwritten values. Bounded independent foreign ALTREP probes cover
prototype, full/sparse replacement, callbacks, alias preservation and interrupted
detached work; permanent tests retain the callback-count distinction. Working
native-runner round 7 passes all preceding original checks and reaches only the
last repeated-generation scaling gate. That gate remains failed: 400 appends
allocate 10.22 MB in 0.151 seconds, while 1,600 allocate 188.66 MB in 1.866 seconds.
Repeated whole-table preflight/view creation, name validation/lookup and append
names reconstruction account for the growth. The shared structural prerequisite
is under investigation; neither the allocation nor time bound has been relaxed.
This is development evidence only. Exact-source builds and final reviews remain
pending.

Source audit: Stage 3 studied R 4.6.1 ALTREP, garbage-collection and reference-count
interfaces, including `memory.c`, `subscript.c`, `subset.c` and `Defn.h`, as
reference only. No additional upstream implementation was copied or adapted in
this stage. Existing installed NOTICE and README attribution retain their pinned
Stage 1/2 adaptations and full required licenses. Final archives still require
NOTICE verification.

The entries below retain earlier implementation and review history; their
then-pending statements do not override the confirmed merge state above.

Branch `codex/direct-dibble-columns`, implemented in an isolated worktree. Direct select, rename and relocate share result
context/finalization and a private validated constructor. Ordinary payloads still
copy. Eligible string results reuse the existing generation kernel to validate
width and copy once; exact value/attribute identity is checked before reuse.
Stale declarations, missing values and unsupported encodings retain the prior
safe normalization path. No native source differs from starting main.

The initial package source `95685536` and benchmark head `c1e145bf` passed two
independent code reviews and 5,100 independent selector comparisons. Full check
passed 12,570 assertions and examples with four existing test warnings; R CMD
check reported three baseline native/vendor warnings and two notes. Conformance,
Haven/labelled interoperability, roxygen, archive checks, installed NOTICE and
macOS binary NOTICE checks passed. These are initial-prototype results, not
validation of the revised implementation.

The correctness reviewer kept the required reference allocation gate open.
Diagnosis proved the identical starting-main failure, but baseline evidence
does not count as a passing gate. The new native scanner was removed. A working
build of the R-only revision passes the 130 MB rename gate at 128,044,928 bytes;
its roughly 133 ms string timings miss the host-specific 60 ms target.
Measured package source `be9eac34b2d52efa664b9f0eb9f6e0d9e8e41c9c` passed a fresh
isolated build/install, full conformance and R check, Haven interoperability,
roxygen, six archive checks and installed/binary NOTICE verification. R CMD
check retains three baseline warnings and two notes. The new selector/encoding
suite passed 568 assertions without warnings or skips. Both independent
reviewers approved the R-only code and gate applicability, then passed another
3,600 selector comparisons and metadata/encoding/GC/error probes. Final paired timing measurements are complete: string rename 223.55 to
129.63 ms and 640.05 to 128.04 MB; declared character 137.89 to 122.18 ms and
256.05 to 128.04 MB. The separate direct comparison measures roughly 131 ms.
The portable allocation gate passes; the 60 ms host target is not met. Two
pipeline timing outliers disappeared in matched isolated repeats. Complete
[results](../../benchmarks/r-dibble-dplyr/results-2026-09-06-stage1.md) distinguish
cumulative allocation, retained memory and whole-process peak RSS. Final report
reviews approved `f493e2241a20127d0b94825669184512f02f573c` with no unresolved
actionable findings. [PR #192](https://github.com/jbearak/dta-parser/pull/192) is
open. CodeRabbit completed its
review of `75b7d7e`. Its benchmark-library and temporary-reference findings were
fixed; the benchmark now rejects an empty requested library instead of falling
back to a global installation. A new public grouping assertion raises the
selector suite to 579 passes without warnings or skips. Production R/native
code is unchanged. Both independent local fix and memory-evidence reviews are clean. Fresh
latest-head CI/CodeRabbit results are required before merge.
The next CodeRabbit review, on `ba9481f`, requested full table-level attribute
comparisons. Those assertions exposed a row-name regression in the direct
methods. The fix restores the baseline selector policy, with separate tests for
dataset notes, custom metadata, ungrouped, grouped and rowwise row names.
Both independent reviewers then caught missing grouped metadata coverage and
legacy-overlay row-name handling. Both fixes are complete in production source
`9f2f98859f48bea3ff36bc8b7befc3bd0d26e0a9`, with 1,144 exact-install selector
assertions and no failures, warnings or skips. The portable rename allocation
gate still measures 128,044,928 bytes for ordinary and declared strings. Source
archive checks, six archive tests and exact installed/binary NOTICE verification
pass. Full R check and examples pass, with 13,214 assertions, four existing
test warnings and the same three R CMD check warnings and two notes. Both
independent final evidence reviews are clean, with all actionable findings
closed. The full timing matrix remains attributed to `be9eac34`; the follow-up changes structural metadata
and row-name policy, not column storage or string validation. No native source
has changed.
Stage 1 merged normally as [PR #192](https://github.com/jbearak/dta-parser/pull/192)
on 2026-09-06, at `c8173b2af7105596f8a59e28e61a9bdd49fa8c3f`. All 16 CI
checks and completed latest-head CodeRabbit review passed, with all findings
closed. Root independently confirmed that the merged tree matches reviewed
head `6c6e59cd28106f406604c98b1d6cc8c30b9a23af` exactly.

Attribution: pinned dplyr selector/group policies and tests were adapted;
dtplyr was studied only. Installed NOTICE includes exact revisions, destinations,
modifications and full MIT notices. DESCRIPTION credits the copyright holder;
README links the detailed notice. Historical 2026-09-05 artifacts retain their
original dates and revision labels.

Stage 2 is active on `codex/direct-dibble-rows`, in an isolated worktree based
on that merge. It owns shared batch row gathering, package-owned grouping
validation and rebuilding, ordinary bracket slicing, and dplyr row/reconstruction
hooks. Entry points retain their separate indexing and grouping policies.
Direct expression `slice()` remains Stage 6 work; full vctrs/bind integration
remains Stage 8 work. This stage must preserve metadata, Stata typing, container
classes, assigned capacity preparation and symmetric later-write isolation.
Serialized grouped fixtures must work through package-native consumers without
loading dplyr. Stage 9 still owns Imports changes and genuinely absent-dplyr CI.

Next: implement those shared modules without native changes, run focused and
full gates, complete two independent actual-diff reviews and fix reviews, then
open a focused PR for latest-head CI and substantive CodeRabbit review. Root
will independently verify gates and perform the normal merge.

## Native ownership prerequisite and pending stages

The unchanged reference allocation runner fails at its first sparse-write budget
on starting main, the initial prototype and final package source `be9eac34`:
5,000,048 bytes per call. The original
runner remains unchanged. Its numerical budgets and isolation/rollback guarantees must be qualified
before any later PR with native changes merges, and before the epic completes.
An independent read-only audit found obsolete bare `gen()` fixtures and
unknown borrowed first-write assumptions. Stage 3 must review assigned fixture
preparation and separate capture measurements from strict private-write gates.
No threshold changes or passing byte-identical historical runner are claimed. First-write capture cannot safely skip
ambiguous aliases; current monolithic backing would copy the changed column.
A second reproduction shows that entry-time sharing proof can become stale when
an evaluated expression exports a column alias. Both reproductions and the
required dependency repair are recorded in the [plan](dibble-result-performance.md).
Neither finding is closed by the R-only stage 1 revision.

Stage 2 is active as recorded above. Stages 3 through 9 remain pending: owned
doubles; owned strings/logicals/integers; expression engine; filter/order/distinct/
slice families; summaries/callbacks; joins/binding/hooks; independent recoding
and optional dplyr configuration. Reconcile the ownership prerequisite before
the first native change. Issue 172 closes only after the complete absence and
compatibility matrix passes.

The fertility_surveys migration is managed by root in its existing `test/mics`
working tree. Preserve its user edits and rerun the downstream suite against
the final epic default branch.

## CodeRabbit follow-up

The grouping warning was checked against the real current implementation:
`grouped_df(..., character())` returns no groups attribute, so the existing
assignment clears it. The new public test locks down `select(data, g = x)` when
it shadows the only omitted grouping key. CodeRabbit [withdrew the finding](https://github.com/jbearak/dta-parser/pull/192#issuecomment-5559556941)
after evaluating this evidence.

The data.table minimum in the test matches DESCRIPTION and ADR 0030's supported
minimum of 1.18.2.1; lowering it would admit unsupported containers. Stable native
condition classes are a later native-stage improvement. This R-only stage uses
only the existing width error and R-translated bytes error, and propagates other
errors. CodeRabbit [explicitly withdrew both summary nitpicks](https://github.com/jbearak/dta-parser/pull/192#issuecomment-5559541437)
on 2026-09-06 after checking DESCRIPTION, ADR 0030 and the unchanged native
source tree. All applicability responses have substantive acknowledgment. Any native implementation still has the recorded
allocation and alias-escape prerequisites.

CodeRabbit's second review requested structural-aware table-level attribute
comparisons. The expanded suite compares all public attributes and separately
asserts notes, note numbers and custom metadata for ungrouped, grouped and
rowwise select, rename and relocate. Preserving grouped dataset metadata is an
intentional improvement over dplyr delegation, which could discard it.
Row-name expectations retain the old policy: select/relocate reset them; plain
rename preserves them, including legacy generated/structural overlays;
grouped/rowwise rename resets them. Independent review checked 144 metadata
cases and a separate 36-case row-name matrix, then reviewed the fixes.

The stricter minimum-version preflight found that pristine dplyr 1.1.0 and
1.2.0 sources fail compilation under R 4.6.1 because removed promise APIs are
used before dtatools runs. These are not runtime compatibility results. Current
dplyr 1.2.1 works. Stages 5 and 9 must qualify an installable supported minimum.

## Stage 2 implementation and validation in progress

Shared modules now own grouping validation, key extraction, sorted grouping and
factor expansion, row gathering, ordinary base/tibble reference-frame brackets,
and the dplyr row/reconstruction hooks. Native source and the 106 existing
exports are unchanged. Plain data.table bracket expressions retain their own
container method; row gathering is direct through `slice_dta_rows()`.
A fresh installed build passes 1,930 focused row, bracket, gather and selector
assertions with no failures, warnings or skips. Serialized grouped fixtures
pass in a fresh process that confirms dplyr remains unloaded through package
brackets, slicing, gen, egen and regrouping. The early development-load bracket
subprocess failures came from the stale global installation; all 162 bracket
assertions now pass against the fresh package. Full checks, conformance,
interoperability, benchmarks and two independent actual-diff reviews remain
in progress. Exact Stage 1 hook evidence confirms that padded string rows keep
vctrs row names through the shared finalizer; using public `as_dibble()` as the
oracle would reset those names and would not represent that public path.
Provenance now includes the pinned dplyr factor-expansion and row-hook policies
adapted in this stage. The installed NOTICE retains the full license.

The first committed Stage 2 candidate, `f1e0dfa`, failed the full standard
conformance check with two class-order failures, 13,736 passing assertions,
14 test warnings, three check warnings and three notes. The extra check note
identified an unqualified utility call. Fixes preserve grouping-class placement,
remove synthetic base named-argument warnings and qualify that call. An extra
`--as-cran` run failed the same tests and reported mode-specific dependency and
native diagnostics; it is separate evidence from the standard check baseline.
Fresh installed full checks of the fixes are still required.

Independent API review exposed base fallback differences for named vectors,
matrices and nested columns, and a separate base drop-policy mismatch. Corrected
fixtures explicitly assert reference dispatch. The old 1,280-case evaluation
sweep used unmarked reserved frames and is withdrawn as direct-path evidence.
Corrected working-source sweeps pass 18,144 reference edge cases, 390 fallback
cases and 640 evaluation-order cases. A further 1,440-case custom/Stata metadata
matrix passes after restoring base's supplied-column attribute policy and
sharing the existing table/column metadata restoration routine. These are
working-source review results, not substitutes for the final installed checks.

Grouping reconstruction now honors `dplyr.legacy_locale` through public vctrs
ordering proxies and base order. Its dplyr-owned lifecycle notification is not
incorporated. NOTICE records this adaptation and the base R 4.6.1 subsetting
control-flow adaptation, with the exact upstream copyright and complete
GPL-2-or-later COPYING text. DESCRIPTION and README carry the new attribution.
The package remains GPL-3; no native source or export has changed.

Candidate `24b1025` passed standard conformance, R package checks and examples
with the original three check warnings and two notes. Fresh installed focused
checks, interoperability, roxygen, six archive tests, exact source/installed/
macOS binary NOTICE and the 106-export comparison passed. Its retained full
installed suite passed 13,831 assertions with five warnings; that mode's warning
count is being compared against the same-mode baseline before attribution.
The second review's corrected 2,560-case evaluation sweep then exposed 304
metadata-wrapper force-order differences. The fix plans the wrapper's selected
indices before underlying method argument matching and delays column validation
until after the row expression where tibble requires it. All 2,560 working-source
cases pass, with explicit reference-class preconditions. Final installed gates
remain required for this fix.

Exact baseline comparison identified the fifth installed-suite warning as a
Stage 2 regression: reconstruction changed automatic row names into explicit
integer names, which Arrow then reported as dropped metadata. New row planning
and reconstruction now carry `.row_names_info(..., 0L)`, preserving that
bookkeeping as well as visible names. The join/Arrow probe is warning-free.
The legacy-locale review also found interleaved NA/NaN prefixes during factor
expansion. Expansion now follows contiguous runs, matching the upstream
VectorExpander policy. Both fixes have committed regression coverage and remain
subject to final independent review and fresh installed validation.

Root's independent baseline probe identified the same automatic-row-name loss
in Stage 1 plain rename: original pre-epic names were automatic, but the shared
context had expanded them. The raw row-name repair therefore covers the common
context for selectors too. Plain rename preserves automatic or custom names;
select and relocate retain their established reset policy. Regression tests
assert the compact bookkeeping directly, alongside the existing visible-name
and full-attribute comparisons.

Package source `544af28` passed both independent fix reviews, fresh standard
conformance and full R check: 13,903 assertions, no failures or skips, the four
baseline test warnings, three check warnings and two notes. Focused checks,
interoperability, roxygen, source and binary archives, installed NOTICE and the
106-export comparison passed. Independent review also confirmed metadata
force order, raw row-name policies, grouping ties and symmetric write isolation.

The first complete paired row benchmark used identical runner `da40094` with
fresh Stage 1 and `544af28` libraries. It found substantial row-gather gains but
also grouped reconstruction/mutation and wide-helper regressions. Controlled
repeats confirmed repeated class restoration in key validation and repeated
source-membership hashing in finalization. The current R-only fixes cast group
keys at their original cardinality before expanding equality proxies, validate
partitions with linear counts, and batch source membership. All input and
output validation and isolation rules remain. Two independent fix reviews and
fresh checks and measurements are required for this revision; earlier timings
do not qualify it. Discarded benchmark attempts exposed shared-oracle and
compact-key serialization effects; the accepted runner freezes an independent
oracle, checks source values and representation after every operation, and uses
an explicitly ordinary-double group key. Compact row fixtures remain separate.

Production `c6696c9` passed fresh standard conformance and full R check with
13,953 assertions, no failures or skips, the four original test warnings,
three check warnings and two notes. The focused suite passed 3,984 assertions
without warnings or skips. Haven/labelled interoperability, pinned roxygen,
six archive tests, source and macOS binary NOTICE, and the 106-export comparison
also passed; native source remains identical to the merged Stage 1 base.
Both independent reviewers inspected the optimization fixes. Correctness
review compared 111 key-validator and 735 partition fixtures against the prior
exact installation, plus 80 alias/cache/serialization cases and eight context
corners. API review independently compared 66 validator cases, including
custom record equality proxies and additional temporal and cast combinations.
The reviewed memory runner checks the actual supplied dibble's public slots
and attributes against frozen bytes, retaining independent comparison data.
Final paired timing, retained-memory and process-peak measurements passed their
fixture and preservation guards. The complete 96-case matrix resolves the
initial grouped and wide-table regressions. One small grouped-reconstruction
case remains slower by about 1.2–1.4 ms in controlled repeats because the supplied
template is now validated; its allocation decreases. The final report records
that cost, compact-index allocation growth, all raw measurements and the
still-missed inherited 60 ms string-rename target. The portable 130 MB gate
passes at 128,044,648 bytes. See the
[Stage 2 report](../../benchmarks/r-dibble-dplyr/results-2026-09-06-stage2.md).
Both final independent evidence reviews are clean at `b74bc21`, including the
reported performance costs, derived evidence formatting and repeat-process
boundaries. [PR #193](https://github.com/jbearak/dta-parser/pull/193) is open.
Latest-head CI and substantive CodeRabbit review remain required before merge;
Stage 2 remains active until that merge completes.

CodeRabbit completed its first review of `b74bc21` with two findings. It
explicitly withdrew the proposed base singleton/drop reorder after exact
R 4.6.1 and separate baseline/candidate direct-reference probes confirmed the
existing NULL-versus-error behavior. The provenance finding adds a fresh git
archive installer and shared preflight binding for all five SOURCE_SHA runners.
The sidecar records the source revision and installed-file hashes; checks run
before output. A locale-ordering issue found during independent fix review uses
radix ordering. Historical measured libraries and runner labels remain intact;
new installation/guard tests are separate evidence. Final fix reviews and
latest-head external gates are still required before merge.

The provenance follow-up at `bbed948` passed both independent reviews and
matching smoke runs. CodeRabbit requested tighter test diagnostics because a
broad SOURCE_SHA match could accept a usage error. The test now requires each
mode's exact guard diagnostic and separately rejects all five runners' usage
errors as guard evidence. The previously withdrawn base singleton/drop claim
remains closed; its stale summary wording is being corrected with the reviewer.
Package source and the original measured evidence are unchanged.
