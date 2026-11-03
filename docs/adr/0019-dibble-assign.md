# A dibble takes `:=` in `[`, returning a new dibble

ADR 0022 retires this form: `d[i, name := value]` is now an error that
points to `d[i, name] := value` (ADR 0021).

Plan 0001 left data manipulation (`gen`, `replace`) out of the dibble.
The user later asked for data.table's syntax for making and recoding
columns, so `[.dibble` now handles `d[i, name := value, by = g]` and
hands every other `[` to tibble.

It follows Stata where data.table and Stata differ: `i` uses the
`dta_num` comparisons (a missing age is above 35), a `dta_num` in `i`
is true where nonzero or missing, a new string column is `""` outside
`i`, a changed column keeps its labels and format, and storage widens
so `save_dta` can write the new values (`Inf` and `NaN` become `.`,
string `NA` becomes `""`). In `` `:=`(a = , b = ) `` each
column is made in turn, as consecutive `generate`s are; in data.table,
`b` would see the old `a`. It follows data.table where the syntax
implies it: the value sees only the rows `i` picks, so `.N` and `x[1]`
count within them, where Stata's `_N` and `x[1]` see the whole group.

## Considered options

- **Change `d` in place, as data.table does.** R's data frames are
  copied on change, so this would mean rebinding `d` in the caller's
  environment, which breaks inside functions and pipes and surprises
  any other name bound to the same dibble. `d <- d[...]` costs one
  shallow copy of the column list.
- **Use data.table itself.** `as.data.table(d)[...]` already keeps
  `dta_num` columns and Stata's comparisons, and `as_dibble()` converts
  back, but new columns lose their storage and the user would carry a
  dependency and two conversions per recode.
- **`gen()` and `replace()` functions.** Closer to Stata's words, but
  not the syntax asked for.

## Consequences

- A tibble subclass now has its own `[`. Only a `j` written as a `:=`
  call takes the new path; tests check that tibble's `[` is unchanged
  otherwise.
- `d[i, x := v]` on its own line, as a data.table user would write it,
  leaves `d` unchanged: at the console it prints the result, in a
  function or test it does nothing. The docs say so first.
