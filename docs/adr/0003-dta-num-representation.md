# Numeric columns in R carry missing codes in the NaN payload

dtatools stores every numeric column as a double vector of class `dta_num`.
`.` is R's `NA_real_`. `.a` to `.z` are NA doubles with the letter in bits
32 to 39, the same layout haven's `tagged_na()` uses. We chose this because
the codes then survive anything that copies doubles: `c()`, `ifelse()`,
subsetting, vctrs and plain data frames. The downstream suite relies on
that, for example `c(NA, dtatools::.i)`. It also means that `read_dta`
agrees bit for bit with haven on values.

## Considered options

- **A separate integer vector of missing codes in an attribute.** Every
  base function that drops attributes (`c()`, `ifelse()`) would lose the
  codes.
- **Integer columns for byte/int/long.** R integers have one NA, so they
  cannot carry `.a` to `.z`. Every numeric storage type is double in R, and
  the `storage` attribute records the type the file used.

## Consequences

Base R treats every code as `NA`, so dtatools' own functions must read the
codes from the payload. They do so for plain doubles too, not just
`dta_num`.
