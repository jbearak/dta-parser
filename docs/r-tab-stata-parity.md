# tab() and Stata's tabulate

`tab()` is dtatools' `tabulate`. This page is the compatibility matrix
[ADR 0001](./adr/0001-match-stata-tabulation-semantics.md) asks for: every
syntax form and option of Stata 19's one-way and two-way `tabulate`, how
far `tab()` matches it, and what each claim covers. The claims are checked
by `tests/testthat/test-tab-stata-parity.R`, which replays
`tests/testthat/fixtures/tabulate.do` in R and compares the printed lines
with `tabulate.log`, the output of that do-file under Stata 19 MP. A row
marked *matched* below means the printed text is identical, character for
character, on the cases in that log. See
[ADR 0042](./adr/0042-tab-prints-as-stata-tabulate-does.md) for the return
contract behind the table.

The result is a `table` of frequencies with class `dta_tab`. Printing it,
or calling `format()` on it, gives Stata's layout. `as.table()` gives the
plain frequency table, `as.data.frame()` adds the percentages and expected
frequencies as columns, and the usual `table` arithmetic, subsetting,
transposition, and `aperm()` work on it and return plain tables.
`margin.table()` is not generic and puts the class back on its own result;
that result has no layout behind it and prints as a plain table, and
`as.table()` strips the class when an exact plain table is needed.

## Syntax

| Stata | R | Status |
| --- | --- | --- |
| `tabulate x` | `tab(data, x)`, `tab(x)`, `data \|> tab(x)` | Matched |
| `tabulate x y` | `tab(data, x, y)` | Matched |
| `tabulate x y z` | `tab(data, x, y, z)` | R extension: Stata refuses more than two variables; `tab()` gives an R multidimensional table that prints as base R prints it |
| `tabulate x if exp` | `tab(data[which(exp), ], x)` | Matched; the row subset is R's |
| `tabulate x in range` | `tab(data[range, ], x)` | Matched; the row subset is R's |
| `tabulate x [weight]` | none | Planned; tracked separately |
| `tabulate x, subpop(v)` | none | Planned; tracked separately |
| `by g: tabulate x` | `tab(x, g)` or dplyr `group_map()` | Out of scope: use a two-way table |
| `tab1`, `tab2`, `tabi` | none | Planned; tracked separately |

## Result contents

| Stata | R | Status |
| --- | --- | --- |
| One-way `Freq.`, `Percent`, `Cum.`, `Total` | printed; `as.data.frame()` columns `Freq`, `percent`, `cum` | Matched |
| Two-way cell counts with row and column totals | printed; the table's values and `margin.table()` | Matched |
| Categories in value order | same | Matched |
| Value labels as category names | same, `display = "label"` | Matched |
| Two codes with the same label text | `Same [1]`, `Same [2]` | R divergence: Stata prints two identical `Same` rows; `tab()` appends the code so every row name is unambiguous, as `factor_from_labels()` does |
| `nolabel` | `display = "value"` | Matched |
| `missing`: numeric `.`, `.a` to `.z` after the observed values | `missing = TRUE` | Matched |
| `missing`: the empty string as the string missing | `missing = TRUE` | Matched: `""` and `NA_character_` are one blank category, sorted first |
| Missing excluded by default | `missing = FALSE` | Matched |
| R `NaN` as its own category | `missing = TRUE` | R extension: Stata has no `NaN`; it sorts after `.z` |
| One combined missing category | `missing = "combine"` | R extension: base R's `useNA` behavior |
| `[code] label` category names | `display = "both"` | R extension |
| `sort` | `sort = TRUE` | Matched: descending frequency, ties in value order, missing sorted with the rest |
| `sort` on a two-way table | error | Matched: Stata refuses it too |
| `row`, `column`, `cell` | `percent = c("row", "column", "cell")`, any subset | Matched, in Stata's fixed order whatever order is given |
| `expected` | `expected = TRUE` | Matched |
| `nofreq` | `freq = FALSE` | Matched with a percentage or `expected`; alone it is an error where Stata prints nothing |
| `row`, `column`, `cell`, `expected` on a one-way table | error | Matched: Stata refuses them too |
| `chi2`, `exact`, `gamma`, `lrchi2`, `taub`, `V` | none | Planned; tracked separately |
| `generate(stub)` | none | Planned; tracked separately |
| `matcell()`, `matrow()`, `matcol()` | `as.table()`, `dimnames()` | Matched in substance; there are no Stata matrices |
| `plot` | none | Out of scope |
| `wrap` | none | Out of scope: `tab()` wraps by console width, see below |
| `nokey` | none | Planned |
| `nolog`, `all`, `summarize()`, collection options | none | Out of scope for this page |

## Printed layout

| Element | Status |
| --- | --- |
| Stub width: longest level, or the string variable's storage width, within 11 to 39 (one-way) or 10 to 21 (two-way) | Matched |
| Header from the variable label, or the name without one, wrapped by word in the stub or centered over the columns; long words cut | Matched |
| Column levels cut to nine characters in ten-wide columns | Matched |
| Percentages to two decimals, expected frequencies to one, thousands separators in counts | Matched |
| Key box when more than one statistic is shown, followed by a blank line | Matched |
| Rules between rows when more than one statistic is shown | Matched |
| `no observations` for an empty table | Matched: Stata's message is an error return code, `tab()` prints it and returns the empty table |
| Panels when the table is wider than the console | Matched at `getOption("width")`; Stata splits at its own line size and shows a page-width header dtatools does not print |
| Zero-row categories from unused factor levels | R only: Stata cannot produce them; their percentages print as `.` |

## What the claim covers

*Matched* means the numbers and the printed text. `tab()` builds the
statistics from the frequency table with the same rounding Stata shows,
and the tests compare Stata's console lines with `format()`'s lines, so
layout drift is a test failure. The claim does not cover Stata's return
values, `r(N)` and the rest, and it does not cover the terminal
formatting Stata applies through SMCL, only the plain text.

*R extension* marks behavior Stata does not have. It never changes what a
matched call prints.

*Planned* marks Stata behavior with a natural place in `tab()` that is
not built. Each has, or will get, its own issue; none blocks a matched
claim above.

*Out of scope* marks Stata behavior that belongs to another R tool or has
no R counterpart.

## Regenerating the log

The log is Stata's output, so it is regenerated with Stata, never edited:

```sh
cd r-package/dtatools/tests/testthat/fixtures
stata -q -b do tabulate.do
```

A new case goes into the do-file and its R counterpart into the parity
test at the same position. The test checks that the do-file, the log,
and the R replay carry the same `tabulate` commands in the same order.
