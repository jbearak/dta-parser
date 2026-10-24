---
status: accepted
---

# Combine planned summary results without building them

After ADR 0061, `summarise(b, m = mean(b2), .by = caseid)` over the 42,739
women in the first 100,000 rows of the India 2021 DHS births file took
about 0.14 seconds. The plan's native call took about 60% of that, most of
it in garbage collection, since it builds a compact vector for each
group's result and a metadata copy of each. The steps after it then fold
the results' common type, cast each result to it and combine the casts,
and the mask captures each cast for later expressions to read. Each of
those steps builds another object per group.

When the summary has at least eight groups and is not a `reframe()`, the
plan now also takes the first group's result, which the loop built. When
that result is a compact vector with only its storage and class, and every
later group's result would be one too, the plan computes each later
result's value and storage without building it. The storage is the one
`.dta_computed()` gives the value, and the value is what the result's
compact vector would read back: the value rounded to float in float
storage, and system missing for a missing value.

For such results the R code's steps have a fixed outcome. The common type
is the storage `.dta_promote()` joins, and the compact combine constructs
the joined storage's vector from the results' values.
`summary_planned_combine()` builds that vector directly, while the checks
that `C_dtatools_summary_ptype_method()` and `summary_combine_compact()`
make before those native routes would pass: the vctrs reducers and
combiners, the package's helpers and methods, their dispatch and the
promotion are unchanged, and the global environment has no common type
method. The summary then installs the combined vector without group
results. The mask splits it into one value per group only when a later
expression reads it, so those values are slices of the combined vector
rather than metadata copies of each cast, with the same values and
attributes.

The plan builds the group results as before, under ADR 0061, when any
result would be a double, such as a long column's mean that is not whole
or a float sum past float's range, when the storages join at double, when
a check declines, and for fewer than eight groups, where the R code leaves
the common type and the combine to vctrs. The same summary now takes about
0.02 seconds.

`.shared_dta_ptype()`, `.dibble_summary_ptype()`, `.summary_combine()`,
`vctrs::vec_ptype_common()`, `vctrs::vec_cast_common()`, `vctrs::vec_c()`
and the package's common type and cast methods no longer run for these
summaries, and a traced one no longer sees them. Results, warnings and
errors are unchanged. The maintainer approved changing decisions that
block measured speedups on 2026-10-22.
