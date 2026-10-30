# dtaparser keeps `.a` to `.z` in doubles, and integers become doubles to hold them

Plan 0006 had dtaparser read every missing value as a bare `NA`, so the
reason an answer is missing (`.d` "don't know", `.r` "refused") was
lost. An R double can keep it at no cost to R's rules: haven's tagged
NA is R's `NA` with the letter in bits 32 to 39, so `is.na()` is TRUE
and `x > 5` is `NA`, and `haven::na_tag()` gives the letter back. The
bridge already writes that layout for dtatools (ADR 0003).

So dtaparser's float, double, `Date` and `POSIXct` columns keep the
letters. A byte, int or long column is read as integers until a chunk
holds `.a` to `.z`; the bridge then allocates a double column, copies
the rows read so far and fills the rest as tagged doubles. A column
pays double's memory only when it uses extended missing values, and
only once.

Value labels on `.a` to `.z` stay in the `labels` attribute as tagged
NAs. A factor's codes are integers and cannot hold the letters, so with
`factors = TRUE` they become plain `NA`, as before, and `read_dta`
warns once, naming the columns; `factors = FALSE` keeps them, and
`warn_extended_missing = FALSE` silences the warning.

## Considered options

- **Every numeric column a double, as haven does.** Stable types, but
  twice the memory of integers for every byte, int and long column,
  most of which hold no extended missing values.
- **Double when the column's value labels name `.a` to `.z`.** The type
  would follow the file's layout rather than its rows, but an unlabelled
  `.a` in an integer column would still be lost.
- **Labelled missing values as factor levels**, as haven's
  `as_factor()` does. A "Don't know" level would count as an answer in
  `table()` and models; left to the user with `factors = FALSE`.

## Consequences

- A byte, int or long column's type depends on the rows read: integer
  for the first thousand rows (`n_max`), double for the whole file. R
  combines the two to double, keeping the letters.
- Factor level text for unlabelled values follows the file's storage
  type, not the R type, so a long column that became double still has
  `"100000"`, not `"1e+05"`.
- A set that labels only missing values no longer disappears: the
  column keeps its numbers and its `labels`, and is not a factor.
