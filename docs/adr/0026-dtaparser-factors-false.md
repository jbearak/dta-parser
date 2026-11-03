# dtaparser reads labelled columns as numbers unless asked for factors

`dtaparser::read_dta()` made every column with value labels a factor by
default. A factor's codes are integers, so `.a` to `.z` in such a column
became plain `NA`, and the reason a value is missing was lost with only
a warning (ADR 0017). The user decided that losing information by
default costs more than labels by default buy. `factors` now defaults to
`FALSE` in `read_dta()` and `read_fixed_width()`: a labelled column
keeps its numbers, with `.a` to `.z` as tagged NAs, and a `labels`
attribute that `val_labels()` and `val_label()` read. `factors = TRUE`
gives factors as before, with the warning.

## Considered options

- **Keep `TRUE` and the warning.** Labels by default, which reads better
  in analysis code, but the loss happens by default, and a warning in a
  long script is easy to miss.
- **A factor unless the column's value labels name `.a` to `.z`.** No
  labelled missing value would be lost, and the type would follow the
  file's labels, not the rows read. But an unlabelled `.a` in a factor
  column would still become `NA`, and whether a column is a factor
  would depend on something the user has to look up.

## Consequences

- Code written for dtaparser 1.x that relies on factors must pass
  `factors = TRUE`.
- `read_fixed_width()` no longer needs its own rule (`FALSE` only with
  `recodes = "tagged"`); both readers share one default.
- Translating a do-file, comparing with labels (`region == "South"`)
  is easier to read and harder to get wrong than with codes, so the
  docs suggest `factors = TRUE` there when no column holds `.a` to `.z`
  that matter.
