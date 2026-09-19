---
status: accepted
---

# tab() returns a table that prints as Stata's tabulate does

`tab()` returns a `table` of frequencies with the class `dta_tab` in front
of `table`. The class carries a presentation record: the variables'
headers, the storage width of a string variable, and the `tabulate`
options given. `print()` and `format()` lay the table out as Stata 19
prints `tabulate`, and every other operation on the result, `as.table()`,
`as.data.frame()`, subsetting, arithmetic, and margins, gives a plain
`table` or a data frame. Percentages and expected frequencies are computed
from the frequencies when printed or converted; they are not stored.

## Why a subclass and not a new return value

ADR 0001 made Stata's `tabulate` the target. Issue #55 asked how the
result should carry the percentages, totals, and options `tabulate` shows.
Three shapes were considered.

A richer object, a list of matrices for frequencies, percentages, and
expected counts, would print faithfully but break every caller that
treated the result as a `table`, which is what `tab()` has returned since
#53 and what the package's own `codebook()` and tests do with it.

A separate presentation function, `tab()` unchanged and a `print_tab()`
beside it, keeps the table but means the Stata-shaped output is not what
you see when you type `tab(d, x)`, which is the whole reason a Stata user
reaches for it.

The subclass keeps both. The frequencies are the object, so `sum()`,
`margin.table()`, `prop.table()`, `[`, and `as.data.frame()` work as they
do on any table, and the tidy path `as.table()` is a one-line escape. The
presentation is a method, so printing is Stata's and nothing else changes.
The subclass is dropped on subsetting, arithmetic, `t()`, and `aperm()`,
because a row of a two-way table or a proportion is not a `tabulate` any
more and printing it as one would be wrong; `as.table()` does the dropping
so there is one place that defines what the plain result is. Base
`margin.table()` is not generic and restores the input's class on its own
result, so a margin keeps the class name; it carries no layout record, and
the printer falls back to base R's for any `dta_tab` without one, so the
stale name changes nothing that prints. Every fallback goes through the
same check, which also catches counts turned into doubles and category
names removed.

## Stata's options, Stata's checks

`sort`, `percent`, `expected`, and `freq` are `tabulate`'s `sort`, `row`
`column` `cell`, `expected`, and `nofreq`. They are checked as Stata checks
them: `sort` is refused on a two-way table and the two-way options on a
one-way table. One check is stricter. Stata's `nofreq` with nothing else
prints an empty table silently; `freq = FALSE` without `percent` or
`expected` is an error, since a call that shows nothing is a mistake.

## The string missing

Stata has one string missing, the empty string. Before this decision
`tab()` counted `""` as a category and `NA_character_` as R's missing,
which made a character variable read from a `.dta` file tabulate
differently from the same variable in Stata. Now `""` and `NA_character_`
are one category, excluded by default and shown as a blank level, sorted
first, under `missing = TRUE`. `missing = "combine"` gives the same for
strings, since there is only one string missing to combine.

## Three or more variables

Stata's `tabulate` takes one or two variables. `tab()` keeps accepting
more and returns an R multidimensional table, printed as base R prints it,
so nothing that worked before this decision stops working. The
[parity matrix](../r-tab-stata-parity.md) marks it an R extension.

## The measurement

The layout rules were measured on Stata 19 MP output over auto.dta rather
than inferred from the manual: stub widths and their limits, the cut on
column levels, header wrapping and centering, the blank line after the
key, the rules between rows when several statistics are shown, the panel
split. `tests/testthat/fixtures/tabulate.do` is the measurement and
`tabulate.log` its result; the parity test replays the do-file in R and
compares every printed line. A new layout rule is a new case in the
do-file, a regenerated log, and a matching R call.

## What is deferred

Weights, `subpop()`, `tab1`, `tab2`, `tabi`, the association tests,
`generate()`, and `nokey` are `tabulate` features with a natural place in
`tab()` and are tracked in their own issues. Each fits the shape here: a
weighted table is still a `table`, a test statistic is an attribute the
printer shows under the table, and none needs a different return value.
