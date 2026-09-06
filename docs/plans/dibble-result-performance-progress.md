# Direct dibble epic progress

Starting main: `5ad44406f9b80db81789dcf7b7e1756c28502559`.
Issue: https://github.com/jbearak/dta-parser/issues/172.
Contract: [implementation plan](dibble-result-performance.md), plus the
user handoff `/tmp/dibble-direct-operations-handoff.3hgh3u_0.txt`.

Stage 1 is active on `codex/direct-dibble-columns`, worktree
`/private/tmp/dta-direct-stage1`. Its deliverable is the shared result finalizer
and direct select, rename, and relocate methods, with conservative isolation.
Acceptance includes selectors, grouping, metadata, stale storage repair,
source/result later-write isolation, accurate source attribution, a fresh
baseline at the starting revision, and at most 130 MB allocation for the
certified-valid 1M by 16 ordinary-string rename benchmark.
Implementation, independent reviews, local checks, PR, CI, CodeRabbit, and merge
are pending. No stage is merged yet.

Stages 2 through 9 remain pending in the plan order: shared row gathering and
grouping; owned doubles; owned strings/logicals/integers; expression engine;
filter/order/distinct/slice families; summaries/callbacks; joins/binding/hooks;
independent recoding and optional dependency configuration.

The fertility_surveys migration is also active in its existing `test/mics`
working tree. Preserve the user's existing Stata and fixture edits. Pin and
verify merged dtatools revisions there; rerun its downstream suite after the
final epic merge. Current artifacts: `/private/tmp/fertility-dibble-migration`.

Update this record with tested heads, reviewer findings and fix reviews,
check results including baseline warnings, attribution, measured results, PR
links, external review completion, merge SHA, and next step as work proceeds.
