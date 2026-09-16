# Read selected columns

A projected read loads specified columns instead of every column in a file.
Both `read_dta()` and `read_arrow()` accept `col_select`, using tidyselect syntax.
This is useful when an analysis or test needs only a few variables from a wide
survey dataset.

## Known variables

Use `all_of()` when every requested variable must exist:

```r
variables <- c("caseid", "v005", "v012")
survey <- dtatools::read_dta(
  "survey.dta",
  col_select = tidyselect::all_of(variables)
)
```

For an existing `.arrow` dataset, use the same selection with
`dtatools::read_arrow("survey.arrow", col_select = tidyselect::all_of(variables))`.
Omit `col_select` to read all columns.

Use `any_of()` for a list of variables that may differ across surveys. It omits
requested names absent from a particular file:

```r
variables <- c("caseid", "v005", "v012", "survey_specific_variable")
survey <- dtatools::read_dta(
  "survey.dta",
  col_select = tidyselect::any_of(variables)
)
```

The selected columns retain their supported Stata types and metadata. DTA
stores observations as rows, so its reader still scans row blocks while
decoding only selected columns. Arrow stores columns separately and can also
avoid loading unselected column payloads.

## Test suites

A test of calculations involving a few variables can load just those inputs.
Use `n_max` as well when the test needs only a small number of observations:

```r
fixture <- dtatools::read_dta(
  "survey.dta",
  col_select = tidyselect::all_of(c("v005", "v012")),
  n_max = 100L
)
```

Choose the columns and observations that exercise the behavior under test.
`all_of()` makes a missing test input an error.

## Measured performance

The [development-reader report](research/reader-parity-implementation-status.md)
compares 30 scattered columns from the India dataset. In its six-read screen,
median DTA time was 0.272 seconds and verified Arrow time was 0.072 seconds,
versus 0.316 seconds for Stata. Those results were collected with opt-in
optimizations at source `9ac470bb`, before the optimizations became defaults;
they are not a timing promise for every projected read. The report includes
the controls and the modest regressions
against the preceding dtatools implementation.

The [September 12 default-reader benchmark](../benchmarks/reader-refresh/results-2026-09-12-defaults/README.md)
uses a different selection of 100 columns. It measured 0.235 seconds for
`read_dta()` and 0.482 seconds for Stata across 11 warm-cache runs. The R
selection included 100 absent names that `any_of()` omitted; Stata received
the known-present names. These older observations remain documented as
historical results, rather than current-version timing promises.
