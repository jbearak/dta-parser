---
status: accepted
---

# set_dta_values() is the loop-friendly assigner

The package adds `set_dta_values(data, variable, value, rows = NULL,
create = FALSE)`, the by-reference cell assigner ADR 0041 declined, in
the shape that ADR and issue #184 specified for it: the column as a name
or position held in an ordinary R value, no tidy evaluation, one storage
rule fixed up front, by reference on a dibble, cheap per call, and
creation of a missing column behind a separate switch that is off by
default. This supersedes the assigner half of ADR 0041; the generic
attribute setter half stands.

## Why now

ADR 0041 said the assigner would reopen when a consumer needed per-row
assignment or profiling showed the tidy-evaluation cost of `repl()`
dominating a loop. Waiting for that moment means the person who hits it
is mid-migration with a loop that has just gone from milliseconds to
minutes and no way out but rewriting it as vectorised `repl()`, which is
sometimes possible and sometimes not. The cost of building the assigner
is small and its shape was already decided; the cost of not having it
falls entirely on whoever needs it first. The benchmark in ADR 0041 made
the gap concrete: sixty times per single-row write.

## What it is

`set_dta_values()` is `repl(promote = FALSE)` with every evaluation step
removed. It resolves the column by matching a string or checking a
position, normalizes `rows` as `where` is normalized once evaluated,
applies the same size rule to `value`, and commits through the same
replacement path `repl()` commits through, with the same native patch on
compact storage and the same detach of a column shared with another
table. A single-row write costs about ten microseconds on a compact
numeric column against over a hundred through `repl()`; the
[cell-assignment benchmark](../../benchmarks/r-cell-assignment/) records
both.

Where the shared row normalizer speaks of `where`, the assigner's errors
say `rows`, since that is the argument the caller wrote.

## One storage rule

The target keeps its declared storage, and a value it cannot hold is an
error naming the storage that would, with nothing changed. This is the
`promote = FALSE` rule of `repl()` and the rule `data.table::set()`
follows, and it is the only rule that makes sense inside a loop: a
promotion on iteration 4,000 of 10,000 would rebuild the whole column on
that iteration and silently change its type, so the caller who wanted a
wider column should declare it before the loop with `dta_int()`,
`dta_double()`, or `set_dta_metadata()`. Character `NA` is written as
`""`, Stata's string missing, as everywhere else in the package.

## Creating a column

`create = TRUE` adds a column that does not exist, filled with `value` at
`rows` and Stata missing elsewhere, at the storage `gen()` gives a value
of that kind. It is off by default so that a typo in a loop is an error,
as Stata's `replace` makes it, and not a stray column. A position cannot
create a column; there is nothing for the position to name. Growth past
the table's column capacity returns an isolated table that must be
assigned, as `gen()` does, because that is the only thing growth can do.

This is not "`gen()` if absent, else `repl()`". Both branches apply the
one storage rule above to an existing column, and the created column's
storage is `gen()`'s only because a new column has no declared storage
to keep.

## Grouped tables

A grouped dibble is written as an ungrouped one, and the groups are
rebuilt after the write, since the target may be a grouping key. There
is no `by`: a loop-friendly assigner that grouped would pay the group
plan on every call, and a caller who wants group-wise assignment has
`repl()`.

## Consequences

The mutation surface in [mutation by reference](../r-mutation-by-reference.md)
gains one primitive. `set_dta_values()` is the 109th export, pinned in the
native manifest and the benchmark guards. ADR 0041's reopening conditions
for the generic attribute setter are unchanged. Issue #184 closes on this
record.
