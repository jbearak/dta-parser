---
status: accepted
---

# Summarize one compact Stata numeric in one native call

`mean()` of a Stata numeric runs `mean.dta_numeric()`. It admits the call
with `C_dtatools_mean_admitted()`, captures the values with `.dta_data()`,
admits the call again because the capture can run a foreign ALTREP provider,
and computes the mean with `C_dtatools_numeric_mean()`. It then passes the
mean to `.collapse_missing()` and to `.dta_computed()` at the storage
`.declared_dta_storage()` reads. `min()`, `max()` and `sum()` run
`Summary.dta_numeric()`. It lists its inputs, filters the Stata numerics,
reduces their storages, captures each input with `.dta_data()`, and calls
the primitive through `do.call()` under `suppressWarnings()` before the same
two helpers. On a two-value int, `mean()` took about 8.6 microseconds and
`max()` 15.2, against 0.15 for `max()` of the bare values. Grouped verbs make
one such call per group.

After its admission, `mean.dta_numeric()` now calls
`C_dtatools_mean_computed()`. For an unmaterialized compact Stata numeric,
read directly or through metadata proxies, it forces `na.rm`, computes the
mean with `C_dtatools_numeric_mean()`, makes a missing or NaN mean system
missing, and builds the result with the code `C_dtatools_computed_values()`
uses. Capturing such a vector runs no R code, so the second admission would
see what the first saw. The admission has already shown that settling
`na.rm` runs no R code. The call reads `x` from the method's frame and
declines while it is still a promise, as in a direct call of the method,
since forcing it could run code that changes what the admission saw. S3
dispatch forces `x` before the method runs.

With one input, `Summary.dta_numeric()` now calls
`C_dtatools_summary_computed()` for `min()`, `max()` and `sum()`. The input
must be an unmaterialized compact Stata numeric itself, and `na.rm` must
settle to `TRUE` or `FALSE` without running R code, the check the range
admission makes. The R code's view of such a vector is a metadata proxy, and
the primitive calls the proxy's ALTREP method, which calls `numeric_min()`,
`numeric_max()` or `numeric_sum()` on the vector. The call uses the same
kernel, then makes a missing result system missing and builds the result as
for `mean()`.

Both calls return `NULL`, and the R code runs, for anything else. That
covers more than one input, `dta_double` values, which are not compact,
materialized vectors, other generics such as `prod()` and `range()`, and
vectors whose classes are not the ones the package gives a compact Stata
numeric, with `haven_labelled` when it carries value labels, or whose class
or names vector is ALTREP. The R code's capture calls `names()`, which
dispatches on the class, and sets the names on the captured values. A
subclass's `names()` method, or an ALTREP vector's provider code, would run
there and could change what the R code does next, such as defining a
`mean.numeric()` that the second admission would see. The summary call also
declines for metadata proxies, whose views the primitive reads by region
rather than through the method. It declines too for an empty vector, whose
`min()` and `max()` warn. So do `min()` and `max()` of a vector with no
observed value under `na.rm = TRUE`, where the method declines and the
primitive warns. The kernels now find such a vector from its exact missing
count instead of scanning it, which also saves the scan in the R code's
ALTREP method. Results, warnings and errors are unchanged. The size gate of
ADR 0050 still applies: with the test hook that sets it to zero, both calls
decline.

The calls do not prove what they skip. For the vectors they cover, a traced
or replaced `.dta_data()`, `.collapse_missing()`, `.declared_dta_storage()`,
`.dta_computed()` or `.dta_promote()` no longer sees the call. Neither do the
base functions the R code calls, such as `Filter()`, `vapply()`, `Reduce()`,
`lapply()`, `do.call()`, `suppressWarnings()` and `getExportedValue()`, or the
admissions inside `.dta_computed()`. A `mean.numeric()` or `mean.double()`
method defined in the global environment still takes over `mean()`, because
the first admission still runs. This extends the practice of ADR 0050 to
these summaries. The maintainer approved changing decisions that block
measured speedups on 2026-10-22.
