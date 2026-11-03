# Plan: labels as text for comparing and assigning labelled columns

Status: implemented.

## Problem

Plan 0016 made text an incompatible type for a `dtaparser_labelled`:
comparing with a label meant `val_label(x) == "Yes"`, and assigning one
meant looking up its code. A factor takes its labels directly
(`f == "Yes"`, `f[i] <- "No"`, ADR 0027's `d[i, f] := "No"`), and code
that compares with labels reads more clearly than code that compares
with codes. The user asked for the same on labelled columns.

## Text as a label

A string combined with or cast into a labelled column stands for the
code it labels:

- `vec_ptype2()` between the class and character is the class, with
  the labelled side's labels and double codes, since a label can name
  `.a` to `.z`, which only a double holds.
- `vec_cast()` from character looks each string up among the labels'
  text: a label of one code gives that code, `.a` to `.z` included;
  `NA` gives `NA`. A string that labels no code is an error naming it
  and the labels; so is one that labels two codes, since it names no
  one code. Into integer codes, a label of `.a` to `.z` is vctrs'
  lossy-cast error, as a tagged number is.

So `x[i] <- "No"`, `if_else(cond, "No", x)`, `case_when(cond ~ "Yes",
.default = x)` and `coalesce(x, "No")` work, and `d[i, x] := "Refused"`
works too, widening integer codes to double to hold `.r`, as it does
for `tagged_na("r")`.

## Comparing with text

`x == "Yes"` and `x != "Yes"` compare codes: the string becomes its
code and the comparison is the one on numbers. Two cases are errors,
from an `Ops` method on the class:

- **A label of a missing value.** `"Refused"` is `.r`, and `NA`
  compares as `NA`, so `x == "Refused"` would be `NA` on every row. The
  error says to write `is_tagged_na(x, "r")` or
  `val_label(x) == "Refused"`.
- **`<`, `>`, `<=`, `>=` with text.** Codes have an order, labels do
  not, so `x > "No"` is an error, as it is for an unordered factor.

Comparisons with numbers, and arithmetic, are unchanged.

## `%in%` with text

Base `%in%` and `match()` compare through `mtfrm()`, which gives the
codes, so `x %in% c("Yes", "No")` compares numbers with text and is
`FALSE` throughout, without an error. `mtfrm()` sees one side only, so
it cannot give codes for `x %in% c(1, 5)` and text for
`x %in% "Yes"`; codes are kept. The help page and `docs/r.md` say to
write `val_label(x) %in% c("Yes", "No")`, or `vctrs::vec_in()`, which
casts.

## Not in this change

- Text in arithmetic, which stays an error.
- Changing `mtfrm()`.
