---
status: accepted
---

# Compute small Stata numeric results in one native call

`.dta_computed()` turns the bare double result of arithmetic, a summary such
as `mean()`, or a math function into a Stata numeric. It makes computational
NaN, infinite and out-of-range values system missing, takes the first storage
at or above the operand's that holds every value, and builds the vector. A
native route does the same work after proving that every R function it skips
is unchanged. Those proofs cost more than the R code saves on small inputs, so
a size gate leaves results under 2,048 values to the R code. That covers each
group's result in a grouped verb. The R code calls `.tab_missing_codes()`,
`.encode_dta_temporal()`, `.dta_storage_candidates()`, `.invalid_dta_observed()`
once per candidate storage, and `.construct_dta_numeric_trusted()`, which took
about 9 microseconds for the mean of one group of an int column.

`.dta_computed()` now calls `C_dtatools_computed_values()` for a result the
native route leaves to it because of its size. The call takes the R code's
steps in order and builds the vector with the constructors the R code calls,
so the result has the same values, attributes and representation. It declines,
and the R code runs, for a result that is not a double, is ALTREP, or has
attributes such as names, and for a temporal encoding, a minimum that is not
one of the five storage names, and a missing value whose tag byte is not `.a`
through `.z`. The R code reads the result before it forces `temporal` and then
`minimum`, so the call forces each only after everything before it qualifies.
A logical result therefore still returns without forcing either. `mean()` of
a three-value int falls from about 14.7 to 8.1 microseconds, and
`summarise(b, m = mean(b2), .by = caseid)` on the first 100,000 rows of the
India 2021 DHS births file, with 42,739 women, from 2.01 to 1.66 seconds.

The call does not prove what it skips. For results under 2,048 values, a
traced or replaced `.tab_missing_codes()`, `.encode_dta_temporal()`,
`.dta_storage_candidates()`, `.invalid_dta_observed()` or
`.construct_dta_numeric_trusted()` no longer sees the computation. Neither do
traced or replaced base functions the R code calls, such as `length()`,
`is.finite()` or `abs()`, a replaced `.Machine`, or a `names<-` method
registered for the package's classes, which the R code calls to set no names.
Results of 2,048 values or more keep the proven native route and the R code,
and the tests check those guarantees at that size. Tests that checked them on
smaller inputs now use 2,048 values.

This replaces, for results under the size gate, the practice that a native
route proves every R function it skips unchanged. The maintainer approved
changing decisions that block measured speedups on 2026-10-22.
