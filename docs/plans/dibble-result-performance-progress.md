# Direct dibble epic progress

Starting main: `5ad44406f9b80db81789dcf7b7e1756c28502559`.
Issue: https://github.com/jbearak/dta-parser/issues/172, still open.
Contract: [implementation plan](dibble-result-performance.md), plus the
user handoff `/tmp/dibble-direct-operations-handoff.3hgh3u_0.txt`.

## Stage 1 revision under review

Branch `codex/direct-dibble-columns`, isolated worktree
`/private/tmp/dta-direct-stage1`. Direct select, rename and relocate share result
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
Final package source `be9eac34b2d52efa664b9f0eb9f6e0d9e8e41c9c` passed a fresh
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
review is pending.
No PR has been opened or merged. CI and CodeRabbit are pending.

Attribution: pinned dplyr selector/group policies and tests were adapted;
dtplyr was studied only. Installed NOTICE includes exact revisions, destinations,
modifications and full MIT notices. DESCRIPTION credits the copyright holder;
README links the detailed notice. Historical 2026-09-05 artifacts retain their
original dates and revision labels.

Next: obtain both independent final-report reviews, then push/open the focused PR. Inspect CI plus completed
CodeRabbit summaries and inline comments on the latest head. Address findings
with independent fix review before root performs the normal merge.

## Native ownership prerequisite and pending stages

The unchanged reference allocation runner fails at its first sparse-write budget
on starting main and the initial prototype: 5,000,048 bytes per call. The original
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
