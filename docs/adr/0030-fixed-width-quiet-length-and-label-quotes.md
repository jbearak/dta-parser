# Numeric LENGTH and stray quotes in labels are read without a warning

Plan 0009 skipped every statement the converter does not run with a
warning, `LENGTH` included, and warned on each variable label read from
its first quote to its last. Every CDC setup from 2006-2010 to
2017-2019 ends with a `LENGTH` that sets numbers' lengths, and every
female respondent setup among them has labels with stray quotes: one in
2006-2010 and 2017-2019 (`RING = "... RING OR "NuvaRing"?"`), 98 in
each of 2011-2013, 2013-2015 and 2015-2017. So every read of the
2017-2019 files warned, and the caller could quiet it only by
suppressing the warning class, which also hides the warnings that
matter, such as a missing-value recode the converter did not run.

Neither warning reports a changed value:

- A `LENGTH` for numbers sets how many bytes SAS stores each one in.
  The converter keeps every number exactly as `INPUT` reads it, so the
  statement is skipped without a warning. A `LENGTH` with `$` sets a
  string's length, which can cut what `INPUT` reads, so it is still
  skipped with a warning.
- A label read from its first quote to its last is the text CDC meant,
  and it changes only the variable label. The `LabelQuotes` warning
  kind is removed.

## Considered options

- **Keep the warnings.** Callers of CDC's files have to suppress the
  class to read them quietly.
- **Skip every `LENGTH` silently.** Hides a string `LENGTH` that would
  cut values in SAS. No CDC setup has one, and keeping its warning costs
  one condition.

## Consequences

- CDC's 2017-2019 files read without a warning. The 2006-2010 to
  2015-2017 setups still warn about value labels Stata cannot hold:
  labels on ranges and character formats.
