# dtaparser exports `:=` for data frames under R's rules; dtatools adds the dibble method

ADR 0032 moves `:=` and `colon_equals()` from dtaparser to datakit; the
rules here are unchanged.

A do-file translated to R reads best line by line, and
`d[i, name, by = g] := value` (ADR 0021) keeps the shape of a
`generate`, `replace ... if` or `bysort` line. Only dibbles had it, and
using dtatools for the syntax brings Stata's comparisons into an R
analysis and the cost of `dta_num` arithmetic. So dtaparser now exports
`:=`. It takes the left side apart (target, `i`, name, `by`) and calls
an exported S3 generic, `colon_equals()`, whose methods evaluate `i`
and the value among the columns. dtaparser's data-frame method follows
R's rules; dtatools registers a method for dibbles with its Stata rules
and re-exports dtaparser's `:=`. There is one `:=`, so attaching both
packages in either order gives the same function.

The data-frame method:

- `NA` in `i` selects no row, as in data.table and `dplyr::filter()`.
- A new column is `NA` on the rows `i` leaves out. `NaN` and `Inf` stay
  as they are.
- A column widens when it cannot hold the new values: logical to
  integer to double, as Stata promotes storage on `replace`, so
  `gen x = .` followed by `replace x = 1.5 if c` translates directly.
  An integer column given whole numbers stays integer, and `.a` to `.z`
  make it double, which keeps their letters.
- A factor column takes labels: a string that is a level, or a factor,
  matched by label, never by code. A string that is not a level is an
  error naming the levels, so a misspelt label cannot add a category; a
  number is an error that suggests the label. `NA` is allowed.
- `by` groups as `vctrs` does, so all `NA`s are one group.
- The result keeps the input's class (tibble or data.frame). A
  data.table is an error that points to its own `dt[i, name := value]`.

## Considered options

- **Leave tibbles to data.table and dplyr.** data.table needs the data
  converted first, and dplyr turns each line into a
  `mutate(case_when(...))`, which is no longer line by line.
- **`:=` in dtatools only, accepting tibbles.** The same line would
  follow Stata's rules on one class and R's on another, inside one
  package that exists for Stata's rules.
- **A separate `:=` in each package.** Whichever was attached last
  would run, and with dtaparser attached after dtatools a dibble would
  get R's rules.
- **Add the level when a label is new.** Matches Stata accepting an
  unlabelled code, but turns a typo into a new category.

## Consequences

- dtaparser imports vctrs and grows from a reader into a reader with
  one data-manipulation function; ADR 0016's split still holds, since
  everything Stata-specific stays in dtatools.
- The two methods each keep a copy of the code that evaluates
  expressions among the columns (about forty lines), since sharing it
  would mean exporting internals from dtaparser.
- dtaparser and dtatools are 2.0.0: dtatools needs dtaparser's `:=`,
  and ADR 0026 changed `read_dta()`'s default.
- `d[i, name] <- value` stays dibble-only: R picks `[<-` by class, and
  a tibble's is tibble's.
- `i` is plain R, so `region == 1` on a factor compares with the level
  text and matches nothing, without an error. `:=` cannot see this;
  the docs say to compare with labels.
- rlang and data.table's `:=` still mask ours when attached later
  (ADR 0021); now that applies to dtaparser too.
