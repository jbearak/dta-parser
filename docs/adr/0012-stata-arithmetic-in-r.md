# Arithmetic, math and logic on dta_num follow Stata

ADR 0009 made comparisons follow Stata and left arithmetic as R's: a
plain double with every code as `NA`. That broke the next comparison:
`(x + 1) > 5` was `NA` for missing rows where Stata says true. And R's
`Inf`, `NaN`, `NA^0 == 1` and logic with `NA` have no Stata meaning.

The rule now: if either operand is a `dta_num`, the operation follows
Stata, and R's missing values on the other side (`NA` of any type,
`NaN`) mean `.`.

- Arithmetic and R's `Math` functions (`abs`, `round`, `log`, ...) are
  R's operations on the numbers, so `round(x, 1)` rounds to a digit
  (Stata's `round()` takes a unit) and `%%` is R's. Only missing values
  follow Stata: a missing operand, or a result Stata cannot hold (`NaN`,
  `±Inf`), gives `.`, never `.a`, even where R alone would give a
  number (`NA^0`, `1^NA`). The result is a new `dta_num` (storage
  double, no labels, label or format, as a Stata `generate` makes a new
  variable).
- `&`, `|` and `!` treat a value as true when it is nonzero or missing,
  and return an R logical without NAs. Strings and factors are an error.
- Comparisons are unchanged (ADR 0009).

Kept as R's, and so not Stata's:

- `mean` and R's `Summary` group (`sum`, `min`, `max`, ...): Stata
  has no single meaning for them (`summarize`, `egen` and `collapse`
  each skip missing values their own way).
- `cumsum` and the other cumulative functions turn every value after a
  missing one into `.`, where Stata's running `sum()` counts missing as 0.
- Mixing a `dta_num` with another class that has its own operators
  (`Date`, haven's `labelled`, factors) makes R warn and use its own
  rules; the result may keep the first operand's class.
- Finite values above Stata's largest double (about 8.99e307) stay
  numbers; Stata would hold them as missing.

The rules are general knowledge of Stata's missing values; no Stata
output or documentation was used. The least certain is that a function
of `.a` gives `.` rather than `.a`; dtatools follows what arithmetic does.
Each result costs one extra vectorised pass in R.
