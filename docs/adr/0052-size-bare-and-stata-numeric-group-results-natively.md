---
status: accepted
---

# Size bare and Stata numeric group results natively

A grouped `summarise()` or `mutate()` checks each group's result with
`vctrs::obj_is_vector()` and `vctrs::vec_size()`. For an S3 object, both find
and call its `vec_proxy()` method, and for a Stata numeric that is
`vec_proxy.dta_numeric()`, whose R code copies the vector without its
attributes. `summarise()` then checked every group's size again in a second
loop, which set the mask's current group before each check. Over the 42,739
women in the first 100,000 rows of the India 2021 DHS births file, the two
vctrs calls took about 165 milliseconds for the groups' means, and the native
call that replaces them 8.

The verbs now call `C_dtatools_chunk_size()` on each group's result first. It
returns the length, which is the size vctrs reports, for a bare logical,
integer, double, complex, character, raw or list vector, and for a Stata
numeric whose class is `dta_numeric`, one of `dta_byte` through `dta_double`,
`vctrs_vctr` and `double`, and nothing else. It returns `NULL`, and vctrs
checks the result as before, for other classes, including temporal and string
columns, for S4 objects, values with a `dim` attribute, long vectors, and
ALTREP vectors the package does not own, whose reads can run R code.
`summarise()` keeps the sizes it got. When every group's result for an
expression is known to have size one, it skips the second loop and leaves the
mask at the last group, as the loop did. A failing check still reports the
same message for the same group. `summarise(b, m = mean(b2), .by = caseid)`
falls from about 1.22 to 0.93 seconds, and `summarise(b, n = n(), .by =
caseid)` from 0.87 to 0.61.

The call does not dispatch. For the results it covers, a
`vec_proxy.dta_numeric()` defined in the global environment, which vctrs
calls before the package's method, and a replaced `vctrs::obj_is_vector()` or
`vctrs::vec_size()` no longer see these checks. Tracing the package's method
in its namespace never reached them, since vctrs calls the copy that
registration put in its method table.

This replaces, for these checks, the practice that a native route proves
every R function it skips unchanged. The maintainer approved changing
decisions that block measured speedups on 2026-10-22.
