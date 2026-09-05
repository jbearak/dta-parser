# Extended generation

`egen()` creates one column by reference. Its value functions also work in
dibble `:=` assignments, ordinary R expressions, and pipelines. All eight
functions use Stata's missing-value rules, including tagged missings.

```r
library(dtatools)
d <- dibble(household = c(1, 1, 2), x = c(2, 8, NA), y = c(3, NA, NA))
egen(d, peak = dta_max(x), by = household)
```

The helpers also work with `gen()`. On a new target without filtering,
`gen(d, peak = dta_max(x), by = household)`, the `egen()` call above, and
`d[, peak := dta_max(x), by = household]` give the same result. R helpers
are available independently of the command; unlike Stata, there is no
separate function language reserved for `egen()`.

`egen()` follows `gen()` target capture and accepts grouping, filtering,
storage, and column-placement arguments. It rejects an existing target.
`:=` creates or replaces its target. Both mutate by reference, so aliases see
the change; make an explicit copy when you need an independent dataset.
When column capacity must grow, dtatools warns and rebinds the target; earlier
aliases retain the old table. The same [capacity rules](./r-mutation-by-reference.md)
apply to `gen()`, `egen()`, and `:=`.

## Equivalent forms

These forms calculate the same values when no row filter is supplied.
Run each form on a fresh copy, or use distinct target names.

| Calculation | `gen()` | `egen()` | `:=` |
| --- | --- | --- | --- |
| Mean | `gen(d, avg = dta_mean(x), by = household)` | `egen(d, avg = dta_mean(x), by = household)` | `d[, avg := dta_mean(x), by = household]` |
| Minimum | `gen(d, low = dta_min(x), by = household)` | `egen(d, low = dta_min(x), by = household)` | `d[, low := dta_min(x), by = household]` |
| Maximum | `gen(d, high = dta_max(x), by = household)` | `egen(d, high = dta_max(x), by = household)` | `d[, high := dta_max(x), by = household]` |
| Total | `gen(d, total = dta_total(x), by = household)` | `egen(d, total = dta_total(x), by = household)` | `d[, total := dta_total(x), by = household]` |
| Row maximum | `gen(d, row_high = dta_row_max(x, y))` | `egen(d, row_high = dta_row_max(x, y))` | `d[, row_high := dta_row_max(x, y)]` |
| Row total | `gen(d, row_sum = dta_row_total(x, y))` | `egen(d, row_sum = dta_row_total(x, y))` | `d[, row_sum := dta_row_total(x, y)]` |
| Group identifier | `gen(d, id = dta_group_id(household, x))` | `egen(d, id = dta_group_id(household, x))` | `d[, id := dta_group_id(household, x)]` |
| First observation in group | `gen(d, tag = dta_group_tag(household, x))` | `egen(d, tag = dta_group_tag(household, x))` | `d[, tag := dta_group_tag(household, x)]` |

`dta_mean()`, `dta_min()`, and `dta_max()` ignore missing values and return
missing when no observed values remain. Totals treat missings as zero;
`missing = TRUE` makes an all-missing total missing instead. Row functions
apply those rules separately to each row. Numeric functions return doubles
without rounding to Stata float precision. Assignment applies the generation
storage default or the requested type.

Multi-column helpers accept vectors or a list or data frame of columns.
They do not interpret column-selection expressions. Inject runtime names
inside a mutation expression using the existing tidy injection support:

```r
cols <- c("x", "y")
egen(d, widest = dta_row_max(!!!rlang::syms(cols)))
d[, combined := dta_row_total(!!!rlang::syms(cols))]
```

## Filtering and pipelines

`egen()` filters the calculation sample before evaluating its expression.
`gen()` and dibble `:=` evaluate their expressions on the full group.
`gen()` creates a complete new column with the calculated values in selected
rows and system missing, displayed as `.`, in excluded rows. For `:=`,
selected rows receive the result; excluded rows are system missing for a new
column and retain their previous values for an existing column.

For this dataset, the calculation difference is visible without grouping:

```r
d <- dibble(x = c(2, 8), eligible = c(TRUE, FALSE))
egen(d, selected_total = dta_total(x), where = eligible)
# selected_total: 2, .
d[eligible, full_total := dta_total(x)]
# full_total: 10, .
d[eligible, explicit_total := dta_total(x[eligible])]
# explicit_total: 2, .
```

For grouped totals of eligible income, put the filter inside the helper's
argument as well as outside the assignment:

```r
d <- dibble(household = c(1, 1, 2, 2), income = c(2, 8, 5, 9),
    eligible = c(TRUE, FALSE, TRUE, FALSE))
d[eligible, total := dta_total(income[eligible]), by = household]
# total: 2, ., 5, .
```

The inner `income[eligible]` selects the calculation inputs within each
household. The outer `eligible` selects the rows that receive that total.
If `total` already exists, its excluded rows keep their previous values.
The equivalent new-column command is
`egen(d, total = dta_total(income), where = eligible, by = household)`.

Excluded rows receive missing for ordinary `egen()` results and zero for a
direct `dta_group_tag()` result. Group tags mark the first eligible row of
each group. Group identifiers number sorted distinct tuples, not their order
of appearance. By default, missing components exclude a tuple; use
`missing = TRUE` to include missing numeric codes and empty strings.

The command returns its input invisibly, so it can be piped:

```r
out <- dibble(household = c(1, 1, 2), x = c(2, 8, 5)) |>
    egen(total = dta_total(x), by = household) |>
    egen(average = dta_mean(x), by = household, type = "double")
```

## Labels and compatibility decisions

Group labels belong to the result variable as resolved code-to-text
mappings. A label-table name is a serialization hint. It does not establish
a mutable registry shared with other variables. This follows
[ADR 0016](adr/0016-own-resolved-value-label-mappings.md) and supersedes
issue #93's earlier shared-registry requirement. See
[ADR 0027](adr/0027-compose-egen-with-value-functions.md) for the accepted
interface and storage decisions.

```r
egen(d, household_id = dta_group_id(household,
    label = TRUE, label_name = "household_codes", autotype = TRUE))
```

`label = TRUE` joins the components' value labels, falling back to their
values. `truncate` limits each labelled or string component's display width.
`autotype = TRUE` chooses byte, int, long, or double storage to fit the group
codes. Tags use byte storage.

The API uses ordinary R functions such as `dta_max()` in both forms.
`egen()` does not make base `max()` behave like Stata's `egen max()`.
The older command grammar proposed in #91 is superseded by the established
`gen()` conventions. This migration covers the seven source helpers plus
mean; it does not claim full Stata `egen` coverage.

One measured Stata 18 difference is intentional. With only missing inputs,
Stata's `rowmax()` can return the final input's extended missing tag.
`dta_row_max()` returns system missing, retaining the migrated helper's
documented contract. Numeric values still match the Stata fixture.

Long group and tag descriptions use the same rule: a description wider than
80 display columns moves to a note and the variable label becomes
`see notes`. Stata 18's tag helper instead adds notes based on byte length
and keeps a variable label truncated to 80 Unicode characters. The shared
display-width rule is intentional, including for multibyte variable names.

## Source audit and fixture

The source audit used tracked files in `~/repos/fertility_surveys` at
`b361a6b1bbbae4d4c6328e59e8e3200d4e915a84`. It found seven local R helpers:
`egen_max`, `egen_min`, `egen_total`, `egen_rowmax`, `egen_rowtotal`,
`egen_group`, and `egen_tag`. Their dataset-mutating interfaces become
`egen()` plus the corresponding value functions above. Updating
fertility_surveys itself is a separate migration.

Active tracked Stata calls exercise these shapes:

| Source location | Shape represented in this migration |
| --- | --- |
| `mics/bh_vars/cm_birth.do:248-250` | Multi-column `group()`, grouped `max()` |
| `mics/bh_vars/cm_birth.do:290` | Explicit byte storage and Boolean maximum |
| `mics/bh_vars/cm_birth.do:375` | `by` prefix, explicit double minimum |
| `mics/bh_vars/cm_lastbirth.do:114` | Grouped total of `!missing(...)` |
| `dhs/bh_vars/bh_birth_order.do:68-77` | `bysort`, long storage, Boolean totals |
| `dhs/year_recodes.do:156,245,320,368` | `rowmax()` with a runtime varlist |
| `checks/mics/cm_birth_qc.do:82` | `rowtotal()` of indicator columns |
| `checks/dhs/cm_birth_cm_lastbirth.do:94,108` | Group tags, including `if` filtering |
| `dhs/survey_checks.do:55-56` | Ungrouped maximum and minimum |

The reproducible [Stata script](../conformance/stata/egen/egen.do) generates
the packaged [CSV fixture](../r-package/dtatools/inst/extdata/egen_stata18.csv).
The checked-in [execution log](../conformance/stata/egen/egen.log) records
Stata 18.0, revision 15 May 2023, running on Apple Silicon. The executable
was `/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp`. This is a
Stata 18 baseline; Stata 19 was not available for this run.

Run the script from the repository root using the command in its header.
The fixture covers grouped aggregates, Boolean expressions, row functions,
system and tagged missing values, filtered totals and tags, sorted group
codes, Unicode group labels, optional autotype, explicit storage and float
rounding. R differential tests consume the generated CSV without requiring
Stata during package checks.

Additional fixtures check cancellation and input-order effects in total,
mean, and row total, plus fixed and exponential numeric group-label
formatting and Unicode variable-description widths. The numeric-label
fixture also saves a DTA file so decimal CSV parsing cannot change an exact
whole double into a nearby fractional value. Numeric sums accumulate in input order using double precision,
matching the measured Stata 18 results. Thus `dta_total(c(1e16, 1, -1e16))`
is zero, while `dta_total(c(1e16, -1e16, 1))` is one. Explicit double storage
preserves the calculated result; it does not recover precision lost during
summation.
