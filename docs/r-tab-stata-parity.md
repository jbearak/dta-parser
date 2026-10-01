# tab() and Stata's tabulate

`tab()` and its exact alias `tabulate()` implement Stata's one-way and two-way
frequency tabulations and `tabulate, summarize()`. `tab1()`, `tab2()`, and
`tabi()` provide the multiple-variable and immediate forms. The reference
specifications are Stata's [one-way manual](https://www.stata.com/manuals/rtabulateoneway.pdf),
[two-way manual](https://www.stata.com/manuals/rtabulatetwoway.pdf), and
[summary-table manual](https://www.stata.com/manuals/rtabulatesummarize.pdf).

The compatibility target is the command's calculation and plain-text output,
with the R interfaces below for command syntax and side effects. It does not
include Stata's SMCL renderer, command prefixes such as `svy:`, or the separate
`collect` styling/export command language. A feature's native fixtures establish
parity for those cases, not every possible floating-point value or format.

## Calls and calculation sample

| Stata | R | Behavior |
| --- | --- | --- |
| `tabulate x` / `tabulate x y` | `tab(d, x)` / `tab(d, x, y)` | Frequency tables; direct vectors and `data = d` also work |
| `if`, `in` | `where = expression`, `rows = positions` | Evaluated within each group; `.n` and `.N` expose its row number/count |
| `by g:` | `by = g`, or a grouped data frame | List of tables with group keys; explicit `by` follows the package's first-appearance ordering |
| `fweight`, `aweight`, `iweight` | `weights = w, weight = "fweight"` (etc.) | Replication counts, normalized analytic weights, or raw importance-weight sums |
| `subpop(s)` | `subpop = s` | Zero excludes counts but retains categories, in one- and two-way tables; missing is nonzero |
| `missing` | `missing = TRUE` | Numeric `.`, `.a` through `.z` after observed values; string `""`/`NA` is one blank category sorted first |
| `nolabel` | `nolabel = TRUE` or `display = "value"` | Underlying codes displayed with the variable's format |
| `tab1 x y z` | `tab1(d, x, y, z)` | One table per variable, with common options |
| `tab2 x y z` | `tab2(d, x, y, z)` | All pairs; `firstonly = TRUE` limits pairs to the first variable |
| `tabi` | `tabi(matrix_of_counts)` | Immediate frequencies without expanding observations; default exact test for 2 by 2, Pearson otherwise |

The calculation sample jointly excludes missing category variables unless
`missing` is requested, and excludes zero/missing weights. Invalid weights are
checked on that sample. Analytic weights normalize to its observation count,
including subpopulation selection. Frequency weights must be integers.

## Statistics and display

| Stata options | R options | Behavior |
| --- | --- | --- |
| `sort` | `sort = TRUE` | One-way descending frequency, ties in value order |
| `rowsort`, `colsort` | same logical arguments | Descending two-way marginal frequencies; association measures follow the resulting order |
| `row column cell` | same logical arguments, or `percent = c("row", "column", "cell")` | Cell percentages in Stata's display order |
| `expected`, `cchi2`, `clrchi2` | same logical arguments | Expected counts and each cell's Pearson / likelihood-ratio contribution |
| `chi2`, `lrchi2` | same logical arguments | Independence tests without continuity correction |
| `exact[(#)]` | `exact = TRUE` or positive integer | Exact Fisher probabilities; one- and two-sided probabilities for 2 by 2; integer increases R FEXACT workspace |
| `gamma`, `taub`, `V` | same logical arguments | Ordinal measures with asymptotic standard errors; signed V for 2 by 2 |
| `all` | `all = TRUE` | All association measures except exact; explicitly setting a measure to FALSE suppresses it |
| `nofreq` | `nofreq = TRUE` or `freq = FALSE` | Suppress frequencies; without other cell statistics, the table is silent |
| `key`, `nokey` | `key = TRUE/FALSE`, `nokey = TRUE` | Force or suppress the cell key; default is automatic |
| `wrap` | `wrap = TRUE` | Keep frequency tables in one panel; summary tables follow their legacy panel layout |
| `plot` | `plot = TRUE` | One-way horizontal star plot |
| `nolog` | `nolog = TRUE` | Accepted; R's exact-test engine has no Stata enumeration progress log |

Association tests reject analytic and importance weights. Positive observed
margins determine test degrees of freedom; subpopulation zero categories remain
in the table and stored dimensions. Fisher uses R's deterministic FEXACT engine,
never a simulated substitute; resource exhaustion is an error. Its workspace
units and progress messages are implementation-specific.

## Summary tables

`tab(d, group, summarize = outcome)` and
`tab(d, row_group, column_group, summarize = outcome)` return means, standard
deviations, frequencies, and observation counts. `means`, `standard`, `freq`,
and `obs` select/suppress displayed statistics. Analytic and frequency weights
are supported. Missing outcomes are excluded from category discovery. Singleton
cells have zero standard deviation. Marginal means and deviations are calculated
from their observations, not averaged from cell summaries.

Summary results are `dta_tab_summary` data frames; cell and marginal arrays are
in `attr(result, "dta_tab_summary")$margins`. Subsetting returns an ordinary data
frame so the old table layout cannot be reused for a different result.

## Returned values and R adaptations

Frequency results remain `table` objects with class `dta_tab`. `as.table()`
removes reporting attributes, `as.data.frame()` includes percentages and expected
counts (and requested cell contributions), and arithmetic/subsetting returns
plain tables. `margin.table()` is not generic; its stale class has no layout
record and therefore prints as a plain table.

| Stata result or side effect | R return convention |
| --- | --- |
| `r(N)`, `r(r)`, `r(c)`, requested test results | `attr(result, "r")` using Stata's result names |
| `matcell()`, `matrow()`, `matcol()` | Set corresponding argument TRUE; matrix is in `attr(result, "r")` |
| `generate(stub)` | `generate = "stub"`; full-length byte indicator columns in `attr(result, "generated")`, with excluded rows missing |
| `collect` / named collection | `collect = TRUE` / a name; `attr(result, "collection")` contains a tidy table and stored results |
| `tabi ..., replace` | `replace = TRUE`; compact `row`, `col`, `pop` data in `attr(result, "data")` |

Reporting does not modify a caller's data or bind matrices into its environment.
R collections are returned data, with no global append/replace state or Stata
label/style-file interpreter. Those export/styling operations belong to consumers
of the returned data. This is an explicit R adaptation rather than a claim to
reproduce Stata's entire interactive environment.

Other R adaptations are retained: three or more variables give an ordinary
multidimensional table; unused R factor levels remain zero-count categories;
`NaN` can be distinct; `missing = "combine"` combines numeric missings;
`display = "both"` shows codes and labels. Duplicate labels print identically
to Stata, while R dimension names remain unique (for example `Same [1]`). Empty
samples return an empty result printing `no observations`, rather than Stata's
error code; a fully suppressed two-way table remains silent. Group keys follow package ordering. Wide frequency panels respect
R's console width and omit Stata's terminal page header.

## Native evidence

`tests/testthat/fixtures/tabulate*.do` and their `.log` outputs are checked-in
native oracles, replayed by `test-tab-stata-parity.R`, `test-tab-features.R`,
`test-tab-presentation.R`, `test-tab-association.R`, `test-tab-summary.R`, and
`test-tab-multiple.R`, `test-tab-grouped.R`, and `test-tab-indicators.R`. They cover the original 62 output cases plus weights,
selection, subpopulations, tests/standard errors, formatting options, summary
moments, and multiple/immediate forms. Numerical tests also cover missing tags,
zero margins, exact tails, generated observations, and grouped evaluation.

Regenerate a log with Stata, never by editing expected output:

```sh
cd r-package/dtatools/tests/testthat/fixtures
stata -q -b do tabulate-features.do
```

Add each new case to both the do-file and its R replay. Fixtures requiring Stata
19 collection commands are not used to infer a collection interpreter in R.
