# Plan: dta_pmax and dta_pmin

Status: approved by Sonnet 5.5 (two rounds) and GPT-6.1 Terra (two
rounds); implemented.

## Problem

`pmax` and `pmin` are not generics, and ADR 0012 did not cover them.
Given a `dta_num`, which is a classed object, base R skips its C code
and runs an R loop. Where a row's running result is missing, that loop
copies in the next argument's value, so a row with no number gets the
last argument's code:

    x                          1   5   .   .   3
    y                          2  .a  .b   .   .
    pmax(x, y, na.rm = TRUE)   2   5  .b   .   3
    pmax(y, x, na.rm = TRUE)   2   5   .   .   3

It then copies every attribute of the first argument onto the result, so
`y`'s `.b` takes `x`'s value label for `.b`, and `d[, m] := pmax(x, y)`
keeps those labels on the new column. `docs/r.md` said `pmax()` gives
`.`, which holds only without `na.rm`. The R loop also costs about 29 ms
per call on two columns of a million rows, against 5 ms for base's C
code on plain doubles.

Calling base on the numbers alone (`unclass()`) takes the C code but
does not fix it: the C code also keeps a letter that depends on order,
and `unclass()` leaves the labels for it to copy.

## Design

```r
dta_pmax(..., na.rm = FALSE)
dta_pmin(..., na.rm = FALSE)
```

In `r/dtatools/R/dta_num.R`. Each argument's plain numbers (and names)
go to `base::pmax` or `base::pmin`, which run their C code; the result
goes through `stata_number()`, which arithmetic already uses: every
`NA`, `NaN` or infinite value becomes `.`, and the result is a new
`dta_num`, storage double, with no labels, label or format.

- **Arguments:** `dta_num`, double, integer, logical or `NULL`; R's
  `NA` and `NaN` are `.`. A string, factor, `Date`, any other classed
  value or anything with a `dim` is an error naming the function.
  `na.rm` must be `TRUE` or `FALSE`. No arguments is base's error.
- **`na.rm = FALSE`:** a row with any missing value is `.`, as in
  arithmetic.
- **`na.rm = TRUE`:** missing values are skipped; a row with none left
  is `.`.
- **Infinite values:** compared as numbers, and an infinite result is
  `.`, by ADR 0012's rule for results: `dta_pmin(1, Inf)` is 1,
  `dta_pmax(1, Inf)` is `.`.
- **Recycling, names, zero length, signed zero:** base's.
- The result is a `dta_num` even when no argument is one.

On the benchmark above a call takes about 8 ms: the copies of the
arguments and the pass in `stata_number()` over base's C code.

## Decisions from review

- **No new C or Rust.** Both reviewers preferred C in dtatools to Rust
  (Rust lives in dtaparser, ADR 0016, and would need a new callable and
  an ABI bump for semantics only dtatools has). Base's C code, reached
  by removing the class, gets within 3 ms of base on plain doubles, so
  a loop of our own would save little.
- **New names, no mask** (Terra; Sonnet preferred masking `pmax`). See
  ADR 0024.
- **Infinite arguments compared as numbers** (Terra; Sonnet would make
  them missing before comparing). Terra's rule is ADR 0012's and is
  what `stata_number()` already does.

## Docs

`?dta_pmax`; `docs/r.md`: the list of missing-value rules, its example,
the troubleshooting entry that wrongly said `pmax()` gives `.`, and the
API reference; `?dta_num` points to the new functions.

## Tests

In `r/dtatools/tests/testthat/test-stata-math.R`: the table above with
and without `na.rm`, for both functions; both argument orders and a
third argument of `.c`; `.a`, `.b`, `.z`, `NA` and `NaN` together; the
result's class, storage and missing attributes when the first argument
has labels; integer, logical and plain double arguments; recycling,
names from the first argument only, zero length; agreement with base
on random doubles; infinite values selected and passed over; each
refused argument and a bad `na.rm`; and `d[, m] := dta_pmax(x, y,
na.rm = TRUE)`.
