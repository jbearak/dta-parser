# Plan: accessors for dtaparser's missing codes and labels

Status: approved by Sonnet 5.5 (two rounds) and GPT-6.1 Terra (two
rounds); implemented.

## Problem

dtaparser's `read_dta` and `read_fixed_width` keep three things from the
file that the package gives no way to read back:

- **Extended missing values.** `.a` to `.z` are haven's tagged NAs in
  double columns (ADR 0017). The only way to get the letter back is
  `haven::na_tag()`, which the docs and examples point to, though haven
  is only in Suggests. haven's `na_tag()` also stops on integers ("`x`
  must be a double vector"), and a dtaparser byte, int or long column
  is an integer unless the rows read hold `.a` to `.z`, so code that
  works on the whole file can fail on its first thousand rows.
- **Value labels.** With `factors = FALSE`, or when a column's labels
  are all on missing values, the column has a `labels` attribute.
  Reading it means `attr(x, "labels")`, and looking up the text of a
  value means matching it by hand. `match()` treats every NA alike, so
  `.a` and `.b` match each other: `match(tagged_na("a"), tagged_na("b"))`
  is 1.
- **Variable labels.** Each column's `label` attribute, read with
  `attr(x, "label")`.

The user wants accessors for these three in dtaparser.

## Exports

Five functions, in `r/dtaparser/R/accessors.R`. None adds a class or
changes what `read_dta` returns.

```r
na_tag(x)
is_tagged_na(x, tag = NULL)
var_label(x)
val_labels(x)
val_label(x, values = x)
```

**`na_tag(x)`.** A character vector as long as `x`: the letter of each
`.a` to `.z` (`"a"` to `"z"`), `NA` for everything else (numbers, and
`.`, which is a plain `NA`). Names of `x` are kept, so
`na_tag(val_labels(x))` pairs each letter with its text. A double with
a class (`Date`, `POSIXct`) is read by its numbers, as haven does, so a
date column's `.d` shows. An integer, logical or factor gives all `NA`:
none can hold a letter, and a byte, int or long column is an integer
only because the rows read held none (ADR 0017), so the same code must
work on a thousand rows and on the whole file. Anything else (character,
a list, a data frame) is an error, since passing one is a mistake.

Done in C: a `.Call` routine `dta_na_tag` in `init.c`, beside
`has_letters` and using the same test (low word 1954, letter in bits 32
to 39). It is registered as a routine, not a callable, so the ABI number
does not change.

**`is_tagged_na(x, tag = NULL)`.** `!is.na(na_tag(x))`, or, with `tag`
(a character vector of letters), whether the letter is one of them.
Takes the same `x` as `na_tag`, with the same errors. A `tag` that is
not lowercase single letters `a` to `z` is an error, since a typo such
as `"D"` or `".d"` would otherwise match nothing; so are
`character(0)` and `NA`.

**`var_label(x)`.** For a vector, `attr(x, "label", exact = TRUE)`:
a string, or `NULL`. For a data frame, a named list with each column's
label or `NULL`, as `labelled::var_label()` returns; `unlist()` gives a
named character vector of the labelled columns. The dataset's label is
not included; it stays `attr(df, "label")`.

**`val_labels(x)`.** For a vector, its `labels` attribute (the codes,
named by their text; `.a` to `.z` as tagged NAs) or `NULL`. For a data
frame, a named list of those, `NULL` for unlabelled columns. A factor
has no `labels` attribute (its levels are the labels, and its integer
codes are not the file's codes), so it gives `NULL`; the help page says
to read with `factors = FALSE` to keep the codes.

**`val_label(x, values = x)`.** The text of each of `values` under `x`'s
labels: a character vector as long as `values`, `NA` where a value has
no label. Numbers match by value; `.a` to `.z` match by letter, so
`.a` never matches `.b`; `.` matches nothing (Stata cannot label it).
With the default, `val_label(df$income)` gives each row's label, which
is how to see why each value is missing.

Checks run in this order. A list or data frame as `x` is an error.
Then, if `x` has no `labels` (a factor, a date, an unlabelled column),
the result is all `NA` whatever `values` is, so `lapply(df, val_label)`
works on any tibble dtaparser returns. Otherwise `values` must be a
double, integer or logical vector, with any class dropped; anything
else is an error.

Done in R with two `match()` calls, each leaving `NA` keys out of both
sides, since `match()` pairs `NA` with `NA`: the values that are not
`NA` against the codes that are not `NA`, then the letters of the
tagged values against the letters of the tagged codes. A `.` value
(letter `NA`) and a numeric code (letter `NA`) never meet.

## Names, and the packages that share them

The names are haven's (`na_tag`, `is_tagged_na`) and labelled's
(`var_label`, `val_labels`, `val_label`), so someone who knows those
packages knows what these do. They differ in these ways, each stated on
the help page:

- haven's `na_tag` and `is_tagged_na` stop on non-doubles; these give
  `NA` and `FALSE` for integers, logicals and factors. haven's
  `na_tag` drops names; this one keeps them.
- haven's `is_tagged_na` takes one `tag`, any string; this one takes
  several, and only letters.
- labelled's `val_labels` and `val_label` read only class
  `haven_labelled`: on a dtaparser column (no class, a `labels`
  attribute) they give `NULL`. So with labelled attached after
  dtaparser, a bare `val_labels(x)` silently gives `NULL`. labelled's
  `var_label` reads the `label` attribute, as this one does.
- labelled's `val_label(x, v, prefixed = FALSE)` looks up one value,
  named `v`, and gives `NULL` when it has no label; this one takes
  many, named `values` as in dtatools, defaults to `x`, gives `NA` for
  an unlabelled value and has no `prefixed`.

So code moves between these packages only for `var_label`, and for
`na_tag` and `is_tagged_na` on doubles with one tag.

dtatools exports `val_labels` and `val_label` too. Its `val_label`
gives the same text as dtaparser's on the same column. Its
`val_labels` wraps the codes in a `dta_num`; dtaparser's returns the
attribute, a plain double with the same values (a `dta_num`'s `labels`
attribute is stored that way too). With both attached, the one attached
last wins; each package's own code calls its own. A bare call can then
fail by order: `dtatools::val_label` has no default for `values`, so
`val_label(x)` errors when dtatools was attached last. The help pages
and the docs say to call these as `dtaparser::val_label` and
`dtatools::val_label` when both packages are loaded. Which function a
bare name finds is R's attach order, not this package's code, so the
tests do not repeat it for both orders. The choice of
names, and this masking, is recorded in a short ADR,
`docs/adr/0023-dtaparser-accessor-names.md`. The docs attach dtatools,
so their dtaparser examples call `dtaparser::val_labels` and so on, as
they already call `dtaparser::read_dta`.

## Docs and examples

- `read_dta`'s and `read_fixed_width`'s help pages point to `na_tag()`
  and `val_labels()` instead of `haven::na_tag()`, and ADR 0017 names
  `na_tag()` beside haven's.
- Two help pages: `na_tag.Rd` (`na_tag`, `is_tagged_na`) and
  `val_labels.Rd` (`var_label`, `val_labels`, `val_label`), with
  examples that read a small file made by `read_fixed_width`, the only
  way dtaparser alone makes a file.
- `docs/r.md`, "Plain R types: dtaparser": a block reading `survey.dta`
  with `factors = FALSE` and showing `dtaparser::na_tag`,
  `dtaparser::val_label` and `dtaparser::var_label`; the fixed-width
  section uses `dtaparser::na_tag` and `dtaparser::val_labels`; the API
  reference lists the five.
- README's R row mentions the accessors instead of haven.

## Tests

`r/dtaparser/tests/testthat/test-accessors.R`. Fixtures are written
with this library's writer (`write_fixture`), with `.a` to `.z` from
`haven::tagged_na()`. Expected letters come from `haven::na_tag()`, an
open-source reader, on the same doubles; other expected values are
the labels the test wrote.

- `na_tag` on a double column with `.`, `.a`, `.z` and numbers equals
  haven's; on a `Date` column with `.d`, `"d"`; names kept.
- A byte column whose first `.a` is in row 3: read with `n_max = 2` it
  is an integer and `na_tag` gives all `NA`; read whole it is a double
  and `na_tag` gives `"a"` in row 3.
- `na_tag` on a factor and a logical, all `NA`; on a character vector,
  a list and a data frame, an error. `is_tagged_na` with and without
  `tag`, with several tags; `tag = "D"`, `character(0)` and `NA` are
  errors.
- `val_label`: `.a` and `.b` with different labels give their own
  text; `.` gives `NA` in a column with both numeric and tagged codes
  (so `NA` keys never match); unlabelled numbers give `NA`; explicit
  `values`; a factor and an unlabelled column give all `NA` with the
  default `values`, and so does a `Date` column (`read_dta` drops a
  date column's labels); a character or list `values` is an error when
  `x` has labels and all `NA` when it has none; a data frame `x` is
  always an error.
- `val_labels` and `var_label` on vectors and on a tibble (named list,
  `NULL` entries; `unlist(var_label(df))` names only labelled columns).
- On `read_fixed_width(..., recodes = "tagged")` output, `val_label`
  gives each recoded code's text for its letter.
- In dtatools' tests, `dtaparser::val_label` and `dtatools::val_label`
  agree on a `dta_num` column, and `dtaparser::val_labels` gives the
  same numbers as `dtatools::val_labels`.
- dtatools' docs test checks that every dtatools export has a help page
  and is named in `docs/r.md`; a second loop does the same for
  `getNamespaceExports("dtaparser")`, which covers `read_dta` and
  `read_fixed_width` too. It does not catch an example that calls a
  bare `val_labels` meaning dtaparser's (it would get dtatools'); the
  examples' comments show the printed result, which would differ.

## Not in this change

- Setters (`var_label<-` and so on): dtaparser does not write files.
- A `tagged_na()` constructor or `.a` to `.z` objects: comparisons go
  through `is_tagged_na(x, "d")`. dtatools has `.a` to `.z` for its own
  rules.
- Accessors for the dataset label, notes and characteristics.
- Printing tagged NAs with their letter.
- Python and Julia, which have their own types for missing codes.
