# Plan: recode dibble columns with `d[i, name] <- value`

Status: approved by Sonnet 5.5 and GPT-6.1 Terra (round 2, after one
round of changes); implemented.

## Problem

Plan 0010 gave dibbles data.table's `:=`, which returns a new dibble
(ADR 0019), so every recode is written `d <- d[i, name := value]`. The
user asked for a form without `d <-`. They suggested
`d$z[x == y] := v` and, after discussion, chose `d[x == y, z] <- v`
instead (ADR 0020 records why the other forms were rejected).

R runs `d[x == y, z] <- v` as `` d <- `[<-`(d, x == y, z, value = v) ``.
A `[<-.dibble` method receives `i` and `j` as promises, so
`substitute()` gives `x == y` and `z` unevaluated, both at the console
and inside a function (checked with a toy class before writing this).
R evaluates `value` in the caller before the call.

## Design

`[<-.dibble(x, i, j, ..., value)`:

1. If `nargs() != 4` (so `d[i] <- v`, or extra arguments) or `j` is
   missing (`d[i, ] <- v`), call `NextMethod()`: tibble's `[<-`.
2. Read `j`, unevaluated, as one column name:
   - a single string: that name;
   - `(expr)`: `expr` evaluated in the caller, which must give one
     non-empty string (a symbol is an error, unlike in `:=`);
   - a bare symbol: that name, unless it is not a column of `x` but
     names a non-function variable visible from the caller, which is an
     error (see "Bare names");
   - anything else (a number, `c("a", "b")`, a call): `NextMethod()`.
   A function's name (`c`, `sum`) is a column name like any other.
3. `value` `NULL` with `i` given is an error; `d[, name] <- NULL` drops
   the column. A one-column data frame value is unwrapped to its
   column, as tibble accepts `d[1, "x"] <- tibble(x = 5)`.
4. Rows: `i` evaluated among the columns, by the same code as `:=`
   (`eval_columns` + `assign_rows`): Stata comparisons, a `dta_num` is
   true where nonzero or missing, logical `NA` picks no row, numbers are
   row numbers. Without `i`, every row. Row numbers past `nrow(d)` are
   an error that says to write `d[nrow(d) + 1, ] <- list(...)`: tibble
   would add rows, but `:=` has no way to fill the other columns as
   Stata would, and falling back to tibble would evaluate `i` a second
   time, in the caller.
5. Assign by the same code as `:=`: one step whose value is already
   evaluated, no `by`. Conversion, widening, labels, `Inf`/`NaN` to
   `.`, string `NA` to `""`, sort order: all as in plan 0010.

`[.dibble`'s body after parsing its arguments moves into
`assign_columns(x, rows, steps, by, env)`, shared by both methods. A
step may carry `evaluated = TRUE`, and then `group_value` uses its
value as given. When `i` picks no rows, an unevaluated value of a new
column is still tried once on zero rows for its type (errors give `.`,
as in 0010); an evaluated value is not wrapped in that `tryCatch`, and
for an existing column, which stays as it is, its length is still
checked against zero rows, so a value of the wrong length is reported
in both cases. As with `:=`, when no rows are picked the value's type
is not checked against an existing column (`d[x > 100, s] <- 1` on a
string `s` does nothing).

### Value length

`value` is recycled from length 1 or must have one element per row `i`
picks, as tibble's `[<-` requires and as `:=` does for its value.
`vctrs::vec_recycle` reports any other length. A value with one element
per row of `d` while `i` picks fewer rows is therefore an error, not
subset by `i` (base R's `d$z[cond] <- d$w[cond]` style needs the
subset written out).

### Bare names

In tibble, `d[i, nm] <- v` reads `nm` as a variable holding a column
name, the usual loop idiom. In `:=`, a bare name is the column itself.
`d[x == y, z] <- v` needs the second reading. To avoid silently making
a column named `nm` in old loop code, a bare name that is not a column
but is bound (to anything but a function) in the caller's scope is an
error that says to write `(nm)` or `"nm"`. A bare name that is a column
means the column, even if a variable shares its name. The error applies
wherever the column name arrives in a variable: loops, `Reduce()`, and
helpers such as `function(d, col, v) { d[d$x > 1, col] <- v; d }`.
Base R's own objects count too: a new column `pi`, `T` or `letters`
must be written `"pi"`.

## What changes for existing code

- `i` in a two-index `[<-` with one named column now sees columns
  before the caller's variables. Code that uses a variable named like a
  column (`for (i in 1:3) d[i, "x"] <- 0` with a column `i`) changes
  meaning. dtatools itself has no such call; dibbles are fixtures in one
  testthat suite.
- Helpers that take a column name and write `d[i, col] <- v` stop
  with the bare-name error until they write `(col)`.
- `d[nrow(d) + 1, "x"] <- v`, which tibble answers by adding a row, is
  an error; `d[nrow(d) + 1, ] <- list(...)` still reaches tibble.
- Values are converted and storage widens, where tibble stored values as
  given (a byte column given 0.5 kept storage `byte` and could not be
  written).
- `$<-`, `[[<-`, `d[i] <- v`, numeric and multi-column `j` are
  unchanged.

## Tests

In `tests/testthat/test-assign.R`:

- equivalence with `:=` (`e[x == .d, x] <- .r` gives `d[x == .d, x := .r]`
  identically), new columns, widening, labels kept, strings, `"name"`
  and `(nm)`, one-column data-frame value, logical `NA` in `i`, no rows
  picked, `d[, name] <- NULL`;
- inside a function and on a nested target (`l$d[...] <- `), and the
  original `d` unchanged outside the function;
- row numbers (negative, several), a `dta_num` `i`, a function's name
  as `j`, dropping an absent column, a zero-row dibble;
- errors: bare variable name (in a helper too), numbers into a string
  column, `NULL` with `i`, wrong value length (with rows, and with none
  for new and existing columns), `(expr)` giving several names, a
  symbol or a number, rows past the end; a column hiding a caller
  variable of the same name in `i` and `j`;
- other forms reach tibble: numeric `j`, `d["y"] <- list(...)`,
  several columns with `i` evaluated in the caller, adding a row with
  `d[nrow(d) + 1, ] <- list(...)`; `dplyr::rows_update()` on a dibble.

The docs test runs every R block in `docs/r.md`, so the new example
there is executed.

## Docs

- `?"dibble-assign"`: title, intro and a section on `<-`, with
  `value` documented and an example.
- `?dibble`: which assignments convert values.
- `docs/r.md`: a paragraph and example under "Make and change columns";
  the exports list.
- ADR 0020.

## Out of scope

`by` and several columns in the `<-` form; `$<-` and `[[<-`; a
`d$z[x == y] := v` form.
