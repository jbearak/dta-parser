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
table. The original
[cell-assignment benchmark](../../benchmarks/r-cell-assignment/results-2026-09-19-set-dta-values.md)
measured 14.3 microseconds for a single-row numeric write, 22.1 for a
whole-column scalar fill, and 14.5 milliseconds for 1,000 row writes.
Those end-to-end measurements did not establish what caused the gap to
`data.table::set()`. The original attribution to unavoidable storage
checks and private views was a hypothesis, not a measured lower bound.

Where the shared row normalizer speaks of `where`, the assigner's errors
say `rows`, since that is the argument the caller wrote.

## Arguments run first, then the layout is read

The arguments are ordinary R values, but evaluating one can run caller
code: the argument expression itself, a method a classed vector runs
when vctrs proxies or casts it, or the element reads of an ALTREP object
from another package. That code can edit the same table by reference,
and a write whose column position was fixed before it ran would land in
the wrong column. So the assigner keeps the order every mutation verb
keeps: validate the table, check capacity for a new column, evaluate
every argument, and only then read the layout it writes into. The
column selector and the `create` flag are reduced to plain scalars, a
foreign ALTREP value is copied into an ordinary vector once, and the
value is cast to the target's storage against a private view of the
column, so that by the time the target is resolved for the write
nothing that remains to run can call back into R: the final resolution
is an attribute read, a name match, and an address comparison. A reorder during evaluation is
honoured, because the target is found again by name, and so is an
argument that replaces the column object while it is evaluated, such as
one that promotes the target's storage: the write lands in the column
the table holds once every argument has run. What is refused, with
nothing written, is a change the settled arguments can no longer be
trusted against: the target added or removed, the row count changed, or
the column object replaced after the value was cast against it, which a
method on the value's class can do.

## One storage rule

The target keeps its declared storage, and a value it cannot hold is an
error naming the storage that would, with nothing changed. This is the
`promote = FALSE` rule of `repl()`. `data.table::set()` also checks types
and ranges, but permits some lossy conversions with warnings. dtatools
also enforces Stata ranges, missing tags and declared storage. Keeping
storage fixed makes loop costs predictable: a
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

## Shared numeric scalar fast path

[Issue #263](https://github.com/jbearak/dta-parser/issues/263) moves eligible
replacement setup into native code and reuses the existing numeric patch
transaction. The table must have the exact ungrouped dibble class chain,
ordinary ASCII column names, at most 2,048 columns, and supported physical
columns with consistent lengths. Shape validation still checks every column:
a one-column write must not accept a malformed table. The sharing decision
reads only the target handle and its backing ownership.

For `set_dta_values()`, native inspection accepts literal arguments and
already evaluated bindings. It does not force delayed or active bindings.
The column selector must be a plain name or position, `create` must be
false, the value must be one ordinary unclassed logical, integer or double,
and rows must be null or ordinary unclassed numeric positions. The target
must be a supported non-temporal Stata numeric column. Compact and owned
double backing qualify; a materialized compact column qualifies for a
whole-column write. Other inputs decline without evaluating caller code
or writing, then use the existing path and its diagnostics.

`repl()` and dibble `:=` adapt their captured scalar literals and settled
bindings to the same native patch. Promotion first checks exact fit and
falls back to the existing promotion path when needed. Fixed float writes
still round to float. A callback-capable `promote` argument uses the general
path from the outset, so a speculative fit check cannot force it and then
evaluate the row and value bindings again on fallback. A promoted assignment
with no selected rows remains
a no-op. Expressions requiring a data mask retain their private views,
and fused comparison-and-patch calls retain their existing adapter.

The existing direct scalar generation path now accepts positional rows
and bracket selections. Bare numeric scalars reuse native generation with
a native attribute plan, also after general expression evaluation. Integers
still create long columns, doubles follow the generation option, and bare
logical values retain logical storage. Capacity and placement remain with
the existing append machinery. Calls needing capacity growth decline before
reading row or value bindings, because a growth warning can run a calling
handler that changes them. Attributed or foreign generation options use the
original validator and generator; a native decline never becomes a column.
A bracket evaluates its row selection once
and passes the same rows to every assignment, including new columns.

The shared patch transaction keeps one row offset and up to eight staged
value bytes on the stack. Larger plans retain their allocated staging and
cleanup. The native scratch counter reports heap allocation separately
from R allocation, staged bytes, and target payload copying. A private
single-row scalar write and a whole-column scalar fill need no native
scratch heap allocation; detaching shared backing can still allocate an
R-managed payload. The transaction validates before its first write and
preserves the existing interruption and ownership rules.
