---
status: accepted
---

# Split a column into its groups in one native call

A grouped verb's data mask reads each column it needs once, splitting it into
one chunk per group. The mask called `.gather_dta_columns(list(value =
value), index)` for each group's rows. That R function decides, column by
column, whether a Stata numeric gather applies, with `vapply()` over
`.declared_dta_storage()` and `.dta_merge_has_compact_storage()`, then calls
`C_dtatools_gather_numeric_columns()` or `C_dtatools_gather_owned_discrete()`
and falls back to vctrs when both decline. For a one-column list the decision
and its bookkeeping cost more than the gather. Over the 42,739 women in the
first 100,000 rows of the India 2021 DHS births file, the reads took about a
fifth of `summarise(b, m = mean(b2), .by = caseid)`.

The mask now calls `.split_dta_column()` for grouped and `.by` reads. It makes
the R code's decision once for the column, with the same `.gather_dta_native()`
helper `.gather_dta_columns()` now uses, and `C_dtatools_split_column()` runs
the same native gathers for every group in one call. The chunks have the same
values, attributes and representation. The call returns `NULL` when the owned
discrete gather declines for a group, as it does for strings, for columns the
package does not own, for classes other than factors, and for rows with
attributes, and the R code then gathers every group itself. It returns `NULL`
before reading anything for an ALTREP column or row vector the package does
not own, whose reads can run R code, so the R code reads them as often as
before. The gathers run no R code otherwise, so redoing the groups the call
already gathered has no effect beyond time. A verdict of `NA`, which makes
the R code fail, also returns `NULL`, so the error comes from the R code.
Rowwise reads keep the R code.

When the split applies, the mask does not call `.gather_dta_columns()` for
the column, and the decision's helpers, `.declared_dta_storage()` and
`.dta_merge_has_compact_storage()`, and the base functions they call run once
per column read where they ran once per group. When the split declines, the
decision has already run once, and the R code then calls
`.gather_dta_columns()` for each group as before, so a traced or replaced
helper sees one more call per column read. This replaces, for these
reads, the practice that a native route proves every R function it skips
unchanged. The maintainer approved changing decisions that block measured
speedups on 2026-10-22.
