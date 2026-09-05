# Explicit mutation epic, issues #178–#181

The agreed design in the coordinating request supersedes the issue proposals and ADRs where they conflict. Baseline: `cb79170`, including PR #182, which already closed #178. A focused #178 follow-up PR completes metadata support under this epic's contract; it does not repeat that merged patch.

## Order and acceptance

1. **#178, explicit metadata mutation.** Complete note and characteristic helpers and provide an explicit by-reference setter for display formats and other supported metadata. Table setters operate on the supplied table, preserve capacity, and share one reference contract across supported table containers. They validate before mutation, protect structural/runtime attributes, and leave unrelated copies and source bookkeeping intact. Cover aliases, function calls, dataset/column scope, errors, and compact-column preservation. Preserve documented vector APIs. Document migration from nested attribute replacement. Include this plan in the PR.
2. **#180, replacement and reference state.** Ordinary `$<-`, `[[<-`, `[<-`, names/dimnames/row-name replacement, and nested attribute replacement copy and rebind while preserving typing and validation. Explicit helpers and dibble `:=` mutate the supplied table. Remove write redirection through `state$object`; separate type identity from bookkeeping validity. Copies and serialized tables have an isolated, tested repair path. Cover both mutation directions between originals/copies, unchanged-column sharing, base attributes, stale state, serialization, and growth. Supersede ADR 0023 and update contradictory examples, including function-local replacements.
3. **#179, capacity and repair.** Export inspectable capacity/readiness information. Establish a predictable preparation and growth policy that detects unsafe mutation before a partial commit and gives an actionable diagnostic. Assigned `reserve_columns()` repairs without changing another table's bookkeeping. Cover unprepared/full/copied/subset/serialized tables, function parameters, supported target expressions, alias separation, and complete physical columns. Document precisely when assignment is required; never restore proxy/overlay writes through an old object.
4. **#181, supported containers.** Prefer dibble, tibble, base data frame, and ordinary data.table support when reliable under the same explicit mutation contract. Audit all exported mutators, reject unsupported inputs before mutation, preserve existing container/column classes, and require explicit assigned conversion if a container cannot be supported. Cover aliases, preparation, copying/subsetting, metadata helpers, grouping restrictions, data.table bookkeeping, and downstream fixture/function examples. Update ADR 0025 and the container guide.

Metadata API availability precedes the replacement compatibility change. Reference-state ownership must be settled before capacity diagnostics can be reliable. The container audit uses those established semantics. Each PR starts from the latest merged `main` and passes independently.

## Per-PR gates

- Dedicated implementation agent in an isolated worktree and branch. That agent delegates two independent reviews: semantics/correctness and API/tests/docs/epic consistency.
- Review the actual diff. Fix every actionable finding and have reviewers inspect fixes until clean; repeat this loop after external feedback changes code.
- Run targeted regression tests, the full R build/check, generated-documentation and archive checks. Run conformance and interoperability checks for changed metadata/label/encoding behavior and native checks if their code changes. Record existing baseline warnings accurately.
- Push and open a focused PR describing behavior, compatibility, and validation. Inspect CI, CodeRabbit summary, inline comments, and review threads on the latest pushed SHA. Wait for every required CI check and a completed CodeRabbit review covering that SHA. Resolve actionable feedback with fresh review. Absence of review is a blocker, never approval.
- Use a normal protected PR merge, never a bypass. Confirm merge SHA and issue acceptance before proceeding from updated `main`. Existing #178 closure remains historical; its follow-up must satisfy the new acceptance criteria.

## Integrated acceptance

On merged `main`, rerun the package checks and an explicit matrix covering ordinary replacement alias isolation, function-local nested attributes, by-reference metadata and values, copied/shared bookkeeping in both directions, base serialization repair, capacity exhaustion, container preservation, and unsupported-input atomicity. Document PR/merge links and migration steps: use explicit metadata setters for caller mutation; return and assign ordinary replacement results; explicitly assign preparation/conversion and any operation documented to rebuild a table.

## Repository gates observed

No AGENTS.md applies in the repository or its ancestor directories. CONTRIBUTING.md and `.github/workflows/ci.yml` supply checks. The active main ruleset requires a PR and prohibits deletion/non-fast-forward updates; it requires zero approving GitHub reviews. The user's CI, CodeRabbit, and two-role local review gates remain mandatory regardless of that minimum.

## Downstream acceptance

The final merged SHA must run fertility_surveys branch `test/mics` R-backend
tests after an isolated renv install, with its prior installation restored.
Do not edit downstream source or its existing work. Inventory expected nested
attribute migration failures separately; any new failure or column-reallocation
warning is a regression to investigate. Report failing test names. The pinned
0.7.1 baseline had 497 tests, four existing failures in
test-integration-mics-output.R, two skips, and no reallocation warnings.

## Downstream evidence at #180

The AST inventory found 56 nested metadata writes in fertility_surveys, including
one multiline format assignment missed by the initial text count. It also found
two ordinary replacements in `last_preg_was_desired.R`: clearing a variable label
and narrowing a generated copy's string-storage attribute. Migrate the first
with `set_var_label(..., NULL)` and construct the new string column explicitly
with `gen(data, copy = dta_string(as.character(source)))` so its declaration has
the required width; generic metadata remains unable to alter storage.

The unchanged-source R suite against #180 ran 497 tests with 232 failing/error
tests, including the four pre-existing output checks, two skips, and no column
reallocation warnings. A diagnostic using temporary migrated script copies
reduced that to the same four pre-existing failures, with the same skips and no
reallocation warnings. No downstream source or lockfile was changed. The required
final installed-SHA suite and restore still follow all four merges.

## Capacity acceptance at #179

The public `column_capacity()` and `can_add_columns()` queries distinguish usable
slots, requested additions, and dibble type. Explicit helpers never rebuild or
rebind a mutation target. Generation and multi-column bracket assignment fail
before values, selection, bysort, or a partial capacity commit. Keep/drop validate column selections before checking the resulting size and
committing; a validated keep-all needs no resize. Same-size operations need no spare slots.
Assigned `reserve_columns()` repairs copies and serialized tables in isolation;
`copy_data()` returns prepared outputs across supported containers. Migration is
to assign preparation before calling translated functions that add/drop columns.

The #179 downstream diagnostic, using temporary migrated script copies and
unchanged fertility tests, again ran 497 tests with only the four pre-existing
integration-output failures, two skips, and zero column-reallocation warnings.
The keep/drop validation tests pass on unprepared fixtures. The downstream source,
worktree state, and lockfile remained unchanged. Final installed-SHA validation
still follows all four merges.


## Container acceptance at #181

All four ordinary containers retain one explicit mutation contract. Central entry
validation rejects unsupported subclasses before avoidable target/update effects,
with a working assigned `as_dibble()` conversion that discards those subclasses.
Metadata supports grouped and rowwise containers; generation/replacement supports
valid grouped containers; structural helpers require assigned ungrouping. Group
rows must match the table's physical row order, partition and distinct keys. The container guide
records every exported helper family, assigned utilities and read-only queries.

data.table's last-column drop clears stored row names to match its zero-row public
empty-table convention. Other supported containers retain n-row, zero-column tables.
All retain the preceding capacity, copy/rebind, metadata/runtime-name, alias and
serialization contracts. Final merged-default checks and downstream installed-SHA
validation still follow this PR's merge.


The #181 diagnostic against temporary migrated fertility scripts ran 497 tests
with the same four pre-existing integration-output failures, two skips and zero
column-reallocation warnings. Real downstream source, status and lockfile were
unchanged. The unchanged-source installed-final-SHA suite and renv restore remain
required after merge; this diagnostic does not replace them.
