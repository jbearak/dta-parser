# Direct dibble epic progress

Starting main: `5ad44406f9b80db81789dcf7b7e1756c28502559`.
Issue: https://github.com/jbearak/dta-parser/issues/172, still open.
Contract: [implementation plan](dibble-result-performance.md), with the user’s
authorized sequential PR, independent-review, CI and CodeRabbit process. The
original orchestration prompt was supplied outside the repository; its operative
decisions are recorded in that plan.

## Stage 1 PR open, external gates pending

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
No stage has merged yet.

Attribution: pinned dplyr selector/group policies and tests were adapted;
dtplyr was studied only. Installed NOTICE includes exact revisions, destinations,
modifications and full MIT notices. DESCRIPTION credits the copyright holder;
README links the detailed notice. Historical 2026-09-05 artifacts retain their
original dates and revision labels.

Next: inspect CI plus completed
CodeRabbit summaries and inline comments on the latest head. Address findings
with independent fix review before root performs the normal merge.

## Native ownership prerequisite and pending stages

The unchanged reference allocation runner fails at its first sparse-write budget
on starting main, the initial prototype and final package source `be9eac34`:
5,000,048 bytes per call. The original
runner remains unchanged. It must pass before any later PR with native changes
merges, and before the epic completes. First-write capture cannot safely skip
ambiguous aliases; current monolithic backing would copy the changed column.
A second reproduction shows that entry-time sharing proof can become stale when
an evaluated expression exports a column alias. Both reproductions and the
required dependency repair are recorded in the [plan](dibble-result-performance.md).
Neither finding is closed by the R-only stage 1 revision.

Stages 2 through 9 remain pending: shared row gathering and grouping; owned
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
