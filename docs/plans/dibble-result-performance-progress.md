# Direct dibble epic progress

Starting main: `5ad44406f9b80db81789dcf7b7e1756c28502559`.
Issue: https://github.com/jbearak/dta-parser/issues/172, still open.
Contract: [implementation plan](dibble-result-performance.md), plus the
user handoff `/tmp/dibble-direct-operations-handoff.3hgh3u_0.txt`.

## Stage 1: local gates complete, external gates pending

Branch `codex/direct-dibble-columns`, isolated worktree
`/private/tmp/dta-direct-stage1`. Direct select, rename and relocate share result
context/finalization and a private validated constructor. Ordinary payloads still
copy, and current string values receive one bounded-allocation native scan.
No source address is trusted as ownership or permanent validity evidence.

Tested package source: `95685536e8b12c70aa252cd3842efad131204216`.
Both independent reviewers were clean through benchmark head
`c1e145bf5d5cc0a29d7a11cdad71ff7685a81516`. They inspected correctness, aliases,
capacity, serialization, native GC, API compatibility, documentation and notices;
5,100 independent selector comparisons passed. Final documentation/evidence review
is pending. No PR has been opened or merged yet. CI and CodeRabbit are pending.

Local validation passed 500 new selector assertions, 3,718 focused assertions,
12,570 full package assertions, examples, roxygen, archive tests, required shared
conformance and Haven/labelled interoperability. Four existing test warnings
remain. R CMD check ended with the baseline three native/vendor warnings and two
notes. The source archive, installed library and macOS binary `.tgz` all contain
byte-identical NOTICE. Release binary verification is part of the workflow.

Fresh baseline and candidate measurements, commands, limitations and complete
raw results are in the [stage 1 report](../../benchmarks/r-dibble-dplyr/results-2026-09-06-stage1.md).
A 1M by 16 ordinary-string rename allocates 128.078 MB, below the 130 MB gate,
versus baseline 640.049 MB. Final timing comparisons ranged from 52.56 to 63.14 ms;
the host-specific 60 ms target was not met in every run. No repeatable regression
above 10% and 1 ms remained after the double-filter repeat check. Historical
2026-09-05 measurements and revision labels are retained unchanged.

The unchanged reference-mutation allocation runner fails identically on baseline
and candidate at its first sparse-write allocation assertion: 5,000,048 bytes
per call. It is **not a passing gate**. The report and minimized reproducer preserve
the evidence. This pre-existing sharing/copy issue is an explicit blocker for
ownership stage 3 and final epic acceptance. Stage 1 changes no write path and
introduces no new failure there; the original gate must pass before that later
acceptance can be closed. No check or sharing safeguard was weakened.

Attribution: pinned dplyr selector/group policies and tests were adapted;
dtplyr was studied only. The installed NOTICE includes exact revisions, local
destinations, modifications and full MIT notices. DESCRIPTION credits the
incorporated copyright holder; the package README links the detailed notice.

Next: review the final evidence delta, push and open the focused PR, then wait
for required CI and CodeRabbit's completed latest-head review. Resolve actionable
feedback with another independent fix review. Root merges only after all gates
pass and updates this record with PR/merge links and merged-default verification.

## Pending stages

Stages 2 through 9 remain pending in order: shared row gathering and grouping;
owned doubles; owned strings/logicals/integers; expression engine;
filter/order/distinct/slice families; summaries/callbacks; joins/binding/hooks;
independent recoding and optional dplyr configuration. Stage 3 must also resolve
the recorded unchanged reference allocation failure. No stage is merged yet.
Issue 172 closes only after the complete absence-and-compatibility matrix passes.

The fertility_surveys migration remains a coordinated downstream task in its
existing `test/mics` working tree, managed by root. Preserve its existing user
edits and rerun its downstream suite against the final epic default branch.
