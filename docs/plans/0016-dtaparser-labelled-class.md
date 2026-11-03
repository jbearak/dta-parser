# Plan: a labelled class in dtaparser, so labels survive dplyr

Status: approved by Sonnet 5.5 (two rounds) and GPT-6.1 Terra (two
rounds), with the letter-keeping equality proxy dropped after their second
reviews; implemented.

## Problem

With `factors = FALSE`, the default since ADR 0026, `read_dta()` and
`read_fixed_width()` return a labelled column as a plain integer or
double with a `labels` attribute. dplyr combines columns through vctrs,
and vctrs treats an attribute on an unclassed vector as incidental. With
dplyr 1.2.1, `bind_rows()`, `case_when()` and `if_else()` each return
the column without its `labels`, so after stacking two files
`val_label()` is `NA` on every row. A factor keeps its levels through
the same calls because its class tells vctrs how to combine it, but a
factor cannot hold `.a` to `.z` (ADR 0017).

dtaparser kept its columns unclassed (ADR 0017, plan 0013) on the
assumption that attributes travel with a column. They do in base R
subsetting; they do not in vctrs, which is how dplyr and tidyr combine
columns. The user decided that dtaparser's readers should return a
class that keeps the labels, in 2.0.0, which already breaks 1.x code
(ADR 0026).

## The class

`dtaparser_labelled`, built with `vctrs::new_vctr()` (vctrs is in
Imports already). Its data is the column's integer or double vector,
`.a` to `.z` as tagged NAs. Two attributes:

- `labels`: a named double vector of codes, `.a` to `.z` among them as
  tagged NAs, as today. Always double, even on integer data, since a
  label on `.a` needs a double.
- `label`: the variable label or `NULL`.

`vec_ptype_abbr()` is `"int+lbl"` or `"dbl+lbl"` by the data's type;
`vec_ptype_full()` is `dtaparser_labelled<integer>` or `<double>`.

One export makes one:

```r
with_labels(x, labels, label = NULL)
```

`x` is an integer or double vector, or a `dtaparser_labelled`, whose
data is used and whose labels and variable label are replaced (the
variable label kept when `label` is `NULL`). `labels` is a named
integer or double vector: no repeated code (a tagged NA counts by its
letter), no plain `NA` or `NaN` code (Stata cannot label `.`), and no
empty or `NA` name. Anything else is an error naming what is wrong.
Downstream code sets its own labels with it, such as
`with_labels(codes, c(No = 0, Yes = 1, tagged_na(c(Refused = "r"))))`.

### Readers

With `factors = FALSE`, every column that has a `labels` attribute
today comes back as a `dtaparser_labelled` with the same data and
attributes. It is made in `read_dta()` after `C_dta_read`, so
`read_fixed_width()` gets it too. With `factors = TRUE`, labelled
columns are factors as before, and a column labelled only on missing
values, which stays a number either way, is a `dtaparser_labelled`.
Unlabelled columns, dates and strings do not change.

### Missing values and text

Every missing value, plain or `.a` to `.z`, is `NA` to `is.na()`,
comparisons and arithmetic, as R's rules say. They are not large
numbers.

- `as.character(x)` gives each non-missing value's label, the number
  as `as.character()` gives it where the value has no label, and `NA`
  for every missing value, labelled or not. `val_label(x)` gives the
  text of missing values, which says why each is missing.
- `format()` and printing show the code and its label, `1 [Yes]`, the
  code alone where there is no label, and `NA(r) [Refused]` or `NA(r)`
  for `.r`, so a tibble shows both and unlabelled codes stand out.

### Factors and tables

`factor()`, `as.factor()` and `table()` are not generics; they work
through `unique()`, `order()` and `as.character()`. With
`as.character()` as above:

- Levels are the non-missing values present, in code order, by their
  text; unlabelled values by their number.
- Every missing value is `NA`, so no missing reason is a level.
  `table(x, useNA = "ifany")` counts them together as `NA`;
  `table(val_label(x)[is.na(x)])` counts them by reason.
- Two codes with the same text share a level, as `factors = TRUE`
  already does. An unlabelled number whose text equals another code's
  label (code 1 labelled `"2"`, and an unlabelled 2) also shares a
  level; this is noted on the help page.
- `factor(x, levels = ...)` matches `as.character(x)` against
  `levels`.

The survey package treats the class as numeric, since it is a double
or integer: `svymean(~x, design)` averages the codes. Proportions need
`svymean(~factor(x), design, na.rm = TRUE)`. The help page and
`docs/r.md` say so, and a test shows both.

### Comparisons, matching and grouping

- Comparing with a plain number works: `x == 1`, `x > 0`, `x %in%
  c(1, 5)`, `match(1, x)`. `mtfrm()` gives the data, so `%in%` and
  `match()` compare codes, not text.
- The equality and ordering proxy is the data, vctrs' default. So
  `is.na()`, `dplyr::coalesce()`, `tidyr::replace_na()` and
  `tidyr::drop_na()` see every missing value, and `order()`,
  `vec_order()` and `arrange()` agree: numbers in order, then missing
  values. The cost is that `unique()`, `duplicated()`, `distinct()`,
  `count()` and `group_by()` put every missing value in one group, as
  they do for any double. To count by reason, group on the reason:
  `count(d, reason = val_label(x))`. A proxy that kept the letter would
  keep reasons apart, but vctrs calls a row missing only when every
  proxy field is, so `is.na()` and `coalesce()` would miss them; a
  silently unfilled `coalesce()` costs more than a grouping step.

### Arithmetic and summaries

A computed number has no label. Arithmetic (`x + 1`, `-x`, `x * y`)
and math (`abs()`, `round()`, `cumsum()`, `log()`) give the plain
integer or double they give on the data. One `vec_math()` method on
the data covers math, `sum()`, `prod()`, `mean()` and the other
`Summary` functions except three: vctrs has its own `min()`, `max()`
and `range()` for its classes, which keep the class, so dtaparser
defines those on the data too. `median()`, `quantile()` and `summary()`
get methods on the data, since vctrs does not implement them. All give
plain numbers. Whether a
letter survives arithmetic is the hardware's, and is not promised.

### Combining (vctrs)

The rules are associative, so the result of `bind_rows()` does not
depend on how inputs are grouped.

- **Two labelled columns** combine to one whose `labels` are the union
  of both, numbers in order and then `.a` to `.z` by letter. A code, or
  a letter, with different text in the two is an error naming the code
  and both texts. The same text on two codes is allowed. Pooling raw
  columns from files whose label spellings differ therefore errors by
  design; relabel with `with_labels()` first.
- The variable label is the first non-`NULL` one in the inputs.
- Integer and double data combine to double.
- **A labelled column and a plain integer, double or all-`NA`
  logical** combine to a labelled column with the labelled side's
  labels. So `if_else(cond, x, 99)` and `c(x, 2)` keep the labels; the
  new value may be unlabelled. The labels still describe the old codes,
  so `case_when(x == 1 ~ 2, .default = x)` can leave a label on a code
  whose meaning changed; the help page warns, and a test shows it.
- **Anything else** (character, factor, other logicals) is vctrs'
  incompatible-type error. (Plan 0017 lets text stand for its label's
  code.) A comparison with text goes through
  `val_label(x) == "Yes"`.

### Casting

- To double: the data, letters kept. To integer: the data when it is
  whole numbers with no `.a` to `.z`, otherwise vctrs' lossy-cast
  error. `as.numeric(x)`, `as.double(x)` and `vctrs::vec_data(x)` give
  the plain vector with no attributes; `unclass(x)` keeps `labels` and
  `label`.
- Labelled to labelled, as `[<-` and `vec_assign()` do: the value's
  labels must agree with the target's, and any it has that the target
  lacks are an error, since the cast would drop them. Double data into
  an integer target follows the integer rule above.
- Plain numbers into a labelled column cast in as the target's type.

### `:=` and `[<-`

`replaced()` in `assign.R` widens only unclassed columns
(`!is.object(old)`), so a labelled column gets its own branch: the data
widens as an unclassed column would (integer to double for 2.5 or for
`.a` to `.z`), and the class, labels and variable label are kept, with
a labelled value's labels combined by the rules above. This covers
`d[i, x] := value` and `d[i, x, by = g] := value`. A new labelled
column made by `:=` keeps the value's labels. `x[i] <- value` is
vctrs' `[<-`, which casts into the existing type and does not widen; a
fractional value into integer data is an error there.

### Base R functions

- `dplyr::if_else()` and `case_when()` keep the class; base
  `ifelse()` drops attributes and gives a plain vector, which the docs
  say.
- `rbind()` and `merge()` on data frames, `saveRDS()` and `readRDS()`
  keep the class and letters; the tests check each. Read back without
  dtaparser loaded, the column falls back to vctrs' defaults until
  dtaparser is loaded.
- `dplyr::recode()` has no method; `case_match()` is the way, as the
  docs say.

### Accessors

`na_tag()`, `is_tagged_na()`, `var_label()`, `val_labels()` and
`val_label()` work on the class unchanged, since the data is a double
or integer and the attributes are the same. Tests run each on real
instances: read from a file, made with `with_labels()`, and after
`bind_rows()`.

## Names

`dtaparser_labelled` names the class after the package, as
`dtaparser_extended_missing` names its warning class, so it is not
taken for haven's `haven_labelled` or labelled's classes, whose
methods differ. `with_labels()` is a new name: haven's and labelled's
`labelled()` make their own classes, and dtaparser taking the name
would make a bare `labelled()` depend on attach order (ADR 0023's
problem). haven's `as_factor()` does not know this class; `factor()`
does.

A short ADR, `docs/adr/0028-dtaparser-labelled-class.md`, records the
class and the reversal: ADR 0017's and plan 0013's "no class" gives way
for labelled columns; ADR 0023's accessors keep their names.

## What breaks

dtaparser 2.0.0 breaks 1.x code already (ADR 0026). This adds:

- A labelled column read with `factors = FALSE` is an object:
  `is.object(x)` and `inherits()` change, `identical()` against a plain
  vector fails, and code that checks `class(x) == "numeric"` sees the
  class. `is.double()`, `is.integer()` and `is.numeric()` do not
  change.
- `as.character(x)` gives labels where it gave numbers.
- Under `factors = TRUE`, a column labelled only on missing values is
  the class where it was a plain number.

The DESCRIPTION title and description, the `factors` paragraphs of
`read_dta()` and `read_fixed_width()`, the `val_labels()` page's note
on factors, ADR 0026's description of `factors = FALSE`, and README's
R row are updated to match.

## Docs

- A help page for `with_labels()` and the class: missing values,
  factors and survey, comparisons, arithmetic, combining, casting, with
  examples.
- `read_dta()`, `read_fixed_width()` and `val_labels()` help, and
  DESCRIPTION, as above.
- `docs/r.md`, "Plain R types: dtaparser": the table row for value
  labels, a short block showing `bind_rows()` keeping labels and
  `factor()` for a survey estimate, and the API reference.

## Tests

`r/dtaparser/tests/testthat/test-labelled.R`. Expected labels are the
ones the tests write; letters are checked with `na_tag()`. A reader
test also compares labels with `haven::read_dta()` on the same fixture.

- **Readers:** `factors = FALSE` on a labelled column gives the class
  with the file's labels; unlabelled, date and string columns do not
  change; `factors = TRUE` gives factors, and a column labelled only on
  missing values is the class.
- **`with_labels()`:** a valid call; relabelling a labelled column;
  errors for a repeated code, a repeated letter, a plain `NA` code,
  unnamed or `NA` names, and non-numeric `x`.
- **Text and factors:** `as.character()` with a plain `NA` first and
  with a tagged NA first gives the same levels; `factor()`,
  `as.factor()` and `table()` have no missing reason as a level and
  levels in code order; shared text shares a level; `format()` and a
  tibble print.
- **Survey:** `svymean(~factor(x), na.rm = TRUE)` gives the shares of
  the answers, also on a `subset()` of the design, and `svymean(~x)`
  the mean of the codes.
- **Comparisons and grouping:** `x == 1`, `x == 1L` on integer data,
  `x == y` for two labelled columns with equal and unequal values,
  `x > 0`, `%in%`, `match()`, `dplyr::filter(x %in% ...)`; the
  contents of `sort()`, `order()` and `arrange()`; `count()` grouping
  every missing value together, and `count(reason = val_label(x))`
  apart.
- **Missing values:** `is.na()`, `coalesce(x, 0)`,
  `tidyr::replace_na()` and `tidyr::drop_na()` on plain and tagged
  missing values.
- **Arithmetic:** `x + 1`, `-x`, `abs()`, `cumsum()`, `sum()`,
  `mean()`, `min()`, `max()` and `range()` with and without `na.rm`,
  `median()`, `quantile()` and `summary()` give plain numbers.
- **Combining:** `bind_rows()`, `case_when()` and `if_else()` keep
  labels and letters; consistent different labels give the union, the
  same whichever order and grouping of three inputs; a conflicting code
  or letter is an error naming it; integer with double gives double;
  the variable-label rule across three inputs; the `case_when()`
  relabel hazard.
- **Casting:** `as.numeric()` and `vec_data()` give plain vectors with
  letters; `unclass()` keeps the attributes; a lossy cast to integer
  and a labelled value with labels the target lacks are errors.
- **`:=`:** 2.5 and `.a` into an integer-backed column widen to double
  and keep class, labels and letters, with and without `by`.
- **Base R:** `ifelse()` gives a plain vector; `rbind()`, `merge()`,
  `saveRDS()`/`readRDS()` keep the class and letters.
- **Accessors** on read, constructed and combined instances.

Each new test is broken once and seen to fail.

## Release

dtaparser 2.0.0 is on main and not yet released; this joins it. A
separate PR releases 2.0.0 for both packages, as for 1.3.0. dtatools
reads through dtaparser's C callables (ADR 0016), not `read_dta()`, so
its `dta_num` columns do not change.

## Not in this change

- Methods for haven's or labelled's functions (`haven::as_factor()`,
  `labelled::to_factor()`).
- `as.logical()` on the class; `as.logical(vec_data(x))` does it.
- Labelled character columns: Stata has none.
- Changing dtatools' `dta_num`.
