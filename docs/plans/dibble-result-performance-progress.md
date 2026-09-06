# Direct dibble epic progress

Starting main: `5ad44406f9b80db81789dcf7b7e1756c28502559`.
Issue: https://github.com/jbearak/dta-parser/issues/172, still open.
Contract: [implementation plan](dibble-result-performance.md), with the user’s
authorized sequential PR, independent-review, CI and CodeRabbit process. The
original orchestration prompt was supplied outside the repository; its operative
decisions are recorded in that plan.

## Stage 1 complete, Stage 2 active

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
