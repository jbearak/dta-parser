---
status: accepted
---

# Typed setters and Stata verbs bound the by-reference mutation surface

The package's by-reference mutation surface stops at the helpers that name
a Stata concept. It does not add a generic attribute setter on the model of
`data.table::setattr()`, and it does not add a low-level, loop-friendly cell
assigner on the model of `data.table::set()`. The two were recorded as
questions once the typed setters of ADR 0028 and the explicit mutation
semantics of ADRs 0029, 0030, and 0036 had landed and been used; this
decision closes both, and states what would reopen each.

## The generic attribute setter

A generic `set_dta_attr(data, variable, name, value)` was proposed to cover
every attribute in one function, including ones the package does not know
about. That function already exists under another name. `set_dta_metadata()`
takes `(x, ..., .metadata, variable)`, sets named attributes on a table or
on one column by reference on a dibble, allows custom bookkeeping
attributes, and refuses exactly what the proposal said a generic setter
should refuse. The column-level attributes `labels`, `value.label.name`,
and `format.stata` need a `variable` or a vector target, since a table has
no value labels or display format of its own. It refuses: the structural attributes `class`, `names`, `dim`,
`row.names`, `levels`, `tzone`, `units`, and `tsp`; runtime state; storage
declarations; and unknown attributes under the reserved `stata.`, `dta.`,
`dtatools.`, and dot prefixes. The attributes that carry invariants,
`labels` with `value.label.name`, `notes` with `stata.note.numbers`, are
validated as a bundle in that same call, so the pairs cannot drift. A second
spelling would be an alias with fewer checks. There is also no consumer
asking for one: the one large downstream project writes no raw
`attr(x, "...") <-` on package data.

## The loop-friendly assigner

A `set_dta_values(data, variable, value, rows = NULL)` was proposed for
the case `data.table::set()` serves: a per-row or per-cell write inside an
R loop, where `repl()`'s tidy-evaluation and Stata typing cost dominates.
The cost is real. On a table of 100,000 rows, from the
[cell-assignment benchmark](../../benchmarks/r-cell-assignment/results-2026-09-19.md),
whose runner records its source, toolchain, host, and correctness checks and
selects the row positionally on both sides:

| Call | Median | Allocation |
| --- | --- | --- |
| `repl(d, !!name := 2)` | 123 µs | 782 KB |
| `repl(d, x = 3, where = 5L)` | 110 µs | 280 B |
| `data.table::set(dt, j = "x", value = 2)` | 7.4 µs | 0 B |
| `data.table::set(dt, i = 5L, j = "x", value = 3)` | 1.8 µs | 0 B |
| 1,000 single-row `repl()` calls | 113 ms | 311 KB |
| 1,000 single-row `set()` calls | 2.0 ms | 24 KB |

So a per-row loop through `repl()` is about sixty times slower than
through `set()`, all of it the fixed cost of tidy evaluation, validation,
and the transaction that every `repl()` call pays whatever it writes. The
regime where that matters is the one nobody writes on this package's data:
the downstream project's loops run over a few dozen runtime column names,
each `gen(data, !!name := value)` or `repl(data, !!name := value)` a
whole-column write, and the fixed cost of such a loop totals under ten
milliseconds. Vectorised `repl()` with a `where` is the Stata idiom, and
translated scripts use it. A primitive that nothing calls would be a 109th
export on a hand-pinned export manifest, a third storage rule beside
`gen()`'s and `repl()`'s, and a place where a typo becomes a stray column
instead of the error Stata gives.

## What reopens each

The generic setter reopens if a downstream site appears that
`set_dta_metadata()` cannot express, or if a migration needs the same
rewrite at enough sites that a shorter spelling earns its place. The
assigner reopens if a consumer needs per-row or per-cell assignment in R
rather than a vectorised `repl()`, or if profiling shows the
tidy-evaluation cost of `gen()` and `repl()` dominating a loop over many
columns. If built, the assigner is a third primitive with one rule of its
own, as issue #184's comment specified: name or position, no tidy
evaluation, a single storage policy fixed up front, by reference on a
dibble, cheap per call, and creation of a missing column behind a separate
switch that is off by default. It is not "`gen()` if absent, else `repl()`",
which would pay the cost it exists to avoid and pick its typing rule by
whether the column happened to exist.

## Consequences

The mutation surface is the set in [mutation by
reference](../r-mutation-by-reference.md): the value verbs `gen()`,
`egen()`, `repl()`, and dibble `:=`; the structural verbs `keep_vars()`,
`drop_vars()`, `order_vars()`, `rename_vars()`, and `reorder_dta_rows()`;
and the typed metadata setters with `set_dta_metadata()` as their general
form. A future architecture review that proposes either primitive should
start from the reopening conditions above rather than from the analogy to
data.table. Issues #183 and #184 close on this record.
