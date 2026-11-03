# Plan: make and recode dibble columns with data.table's `:=`

Status: approved by Sonnet 5.5 and GPT-6.1 Terra (round 4, after
three rounds of changes); implemented.

## Problem

Plan 0001 left data manipulation (`gen`, `replace`) out of the dibble.
The user now wants data.table's syntax for making and recoding
columns: `d[i, x := value, by = g]`. dtatools exists for one testthat
suite, whose fixtures and expected results are dibbles; recoding them
today means `d$x[cond] <- v`, which neither applies Stata's rules to
`cond` nor converts `v` as `dibble()` does.

data.table itself already works on a dibble's columns:
`as.data.table(d)[age > 30, kids := 0]` keeps `dta_num`, uses its
comparisons in `i` and keeps `.r` when assigned, and `as_dibble()`
converts back. But a column made on a subset is a plain double, and a
byte column given 0.5 keeps storage `byte`, so `save_dta` refuses it.

The user chose (asked in this session) a native `[.dibble` that
returns a new dibble, over changing `d` in place, documenting the
round trip, or a bridge to data.table.

## Design

`[.dibble(x, i, j, ..., by)`. When `j`, unevaluated, is a call to
`:=`, the method assigns; otherwise it calls `NextMethod()`, so every
other `[` is tibble's. `by` without `:=` is an error, and so is `:=` in
`i` (`d[x := 1]`, missing its comma). With `:=`, any argument besides
`i`, `j` and `by` (data.table's `keyby`, `on`, or `drop`) is an error
rather than ignored.

### Syntax

- `j`: `name := value`, or `` `:=`(a = v1, b = v2) ``. The name may be
  a symbol, a string, or `(expr)` evaluated in the caller to one
  string. Steps run by position, so a name may come twice
  (`` `:=`(z = 1, z = z + 1) ``). A value that evaluates to `NULL`,
  literal or not, drops the column, as in data.table; not with `i` or
  `by`.
- `i`: evaluated with `rlang::eval_tidy` over the columns (caller's
  environment behind them, so `.a` to `.z` and local variables work).
  A logical selects rows (`NA` selects none, as in data.table; length 1
  is recycled); a `dta_num` is true where nonzero or missing, as in
  Stata's `if x`; anything else goes through `vctrs::vec_as_location()`
  (positive or negative row numbers; `NA` is an error).
- `by`: `g`, `"g"`, `c("g", "h")`, `.(g, h)`, `list(g, h)`, or a
  variable holding names; `NULL` is no grouping. Groups come from `vctrs::vec_group_loc()` on
  the `by` columns of the selected rows, so `.`, `.a`, ..., `.z` are
  each their own group (the vctrs proxies are Stata's keys).

### Semantics

- Each value is evaluated over the selected rows (per group with
  `by`), as data.table does. Each step builds one environment in which
  every column is an active binding that slices it to the current rows
  on first use and keeps the slice for that group; each group only sets
  the rows, as dplyr's data mask does. So every column is found however
  the expression looks it up (a name, `.data[[v]]`, `get()`, `glue`),
  before the caller's variables, and an expression pays only for the
  columns it uses. `.data` is a pronoun over them and `.N` the number of
  rows the expression sees; they hide columns of those names, as in
  data.table. Assigning to a column inside a value (`x <<- 0`) is an
  error; a local (`x <- x + 1`) is fine and leaves the column. (Round 2: binding only the names written in
  the expression let `get("x")` read the caller's `x`; and promises made
  in a loop must force their arguments.)
- This differs from Stata, where `if` chooses the rows that change but
  `_n`, `_N` and `x[1]` still see the whole `by` group; and `bysort`
  sorts, where `:=` keeps the row order. Following data.table here is
  deliberate: the syntax is data.table's, and `i` already decides which
  rows are seen. The docs say so next to the `.N` example.
- When `i` picks no rows, an existing column is left as it is (value
  not evaluated, sort order kept). A new column needs the value's type,
  so the value is evaluated once on zero rows, warnings suppressed
  (`max()` of nothing); if that fails (`x[[1]]`, `if (x > 1)`), the
  column is `.`. With `by` and no rows there are no groups. A literal
  `NULL` is still an error with `i`, whether or not it picks rows.
- A value is converted as `dibble()` converts a column (`dta_column`):
  logical, integer, double to `dta_num`; `Date` to `%td`; factor to
  character; other classes an error. It is recycled from length 1 with
  `vctrs::vec_recycle()`; any other length is an error naming the
  column. `Inf`, `-Inf` and `NaN` become `.` (as `dta_num`
  arithmetic does) and string `NA` becomes `""`, so every result can be
  written. A value of only logical `NA`s has no type yet: it becomes
  `""` in a string column (or alongside string groups) and `.`
  otherwise. Groups' values are combined into one vector with the
  attributes of the first group that has a type and the widest storage
  of any group, so group order cannot change the storage (long with
  float is double: float rounds integers past 2^24); groups that are
  all logical `NA` stay untyped until the column decides; mixed types
  go to `vctrs::list_unchop()`, which reports them. A `NULL` in some
  groups is an error.
- Several columns are made in turn: in `` `:=`(a = 1, b = a + 1) ``,
  `b` sees the new `a`, as consecutive Stata `generate`s and dplyr's
  `mutate()` do. (data.table evaluates every right side first.) `i`
  and the groups are computed once, before the first.
- A new column starts as `.` or `""` for strings, Stata's missing
  string, then takes the value on the selected rows. It takes the
  value's attributes, as `dibble()` and dplyr's `mutate()` do: `b := a`
  copies `a`'s labels, `b := a + 1` has none (arithmetic drops them),
  and `b := dta_num(..., labels = )` keeps the ones given. Stata's
  `generate` copies none; keeping them lets a value carry labels.
- An existing column keeps its own attributes (labels, label, format,
  label set), as `replace` does; only its storage may change.
  Strings into a numeric column, or numbers into a string column, are
  errors.
- Storage widens to hold the new values, with the writer's bounds:
  byte, int, long widen to the narrowest of int and long that holds
  the integers, else to double (for non-integers too: double loses no
  digits, where float would round); float stays
  float within float's range, else double. New columns go through the
  same rule from the value's storage, so a byte from a logical in one
  group widens when another group gives 0.5.
- A `by` column cannot be changed.
- The data frame's attributes (`label`, `notes`, `timestamp`,
  `characteristics`, `sort_order`) are kept. If a sort key changes or
  is dropped, the sort order ends before it.
- The result is returned visibly; `x` itself is not changed. A line
  `d[i, x := v]` whose result is not assigned does nothing; R cannot
  detect it, so the help page and `docs/r.md` say so first.

### Not in this plan

data.table's `.I`, `.SD`, `keyby`, `on`, `c("a", "b") := list(...)`,
and `j` without `:=` (data.table's `d[, .(mean(x)), by = g]`).

## Docs

- `?"dibble-assign"` (roxygen in `R/assign.R`); `?dibble` points to it.
- `docs/r.md`: a "Make and change columns" section with Stata
  equivalents in comments, and a line in the API reference.
- ADR 0019 records the scope change and the options rejected.

## Tests

`tests/testthat/test-assign.R`. Round 3 added: grouped all-`NA` into
string and new columns, with and without `i`; long with float groups
written and read back; zero-row values that fail; literal `NULL` with
an `i` that picks nothing; `<<-` and local assignment. Round 2 added: expressions over
several columns (with and without `i` and `by`, `.data`, `.data[[v]]`);
`get()` and `eval()` finding columns before, and without, a caller's
variable of the same name, grouped too; storage independent of group
order; logical-`NA` groups in string and numeric columns; no rows
picked leaving columns, sort order and warnings alone. Round 1 added: unknown arguments and
`:=` in `i`; no selected rows with and without `by`, new and existing,
numeric and string; repeated names; evaluated `NULL`; `Inf`, `NaN` and
string `NA`, written and read back; `.N` and `seq_len(.N)` with `i` and
`by`; `.data`; a call from a function with local variables; a type
clash across groups; labels on new columns; `by = NULL`. Speed is
measured, not tested (a wall-clock bound loose enough for CI would not
catch the first draft): 2.2 s for 50,000 groups of 21 columns using
two, from 17.6 s in the first draft. From the first draft: rows chosen by Stata comparisons,
logical `NA`, row numbers, negative row numbers and a `dta_num` in `i`;
new columns `.` and `""` elsewhere; labels kept and each widening
step; strings/numbers mismatches; a widened column written by
`save_dta` and read back; `by` with `.a`, `.b` and `.` as separate
groups, `.N`, `seq_len(.N)`, every `by` form; several columns in turn;
names as strings and `(nm)`; `NULL`; length errors; attributes and the
sort order; tibble's `[` unchanged without `:=`. The docs test runs
the `docs/r.md` example.

## Proof for the PR

The dtatools suite (including the docs test) with dtaparser and
dtatools built from this branch.
