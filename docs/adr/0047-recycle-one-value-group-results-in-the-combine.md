---
status: accepted
---

# Recycle one-value group results in the combine

A grouped `mutate()` on a dibble evaluates its expression once per group, and
a result with one value fills all of its group's rows. The data mask recycled
such a result with `vctrs::vec_recycle()` as soon as the group returned it,
one R call per group. For a Stata numeric that call reaches the package's
`vec_proxy()` and `vec_restore()` methods. In `mutate(b, m = mean(b2), .by =
caseid)` over the 42,739 women in the first 100,000 rows of the India 2021 DHS
births file, the calls took about a fifth of the time.

The mask now keeps a one-value result as it is when the result is a bare
atomic vector, or a Stata numeric whose first class is `dta_numeric` and that
is not temporal. `list_unchop()` recycles a size-one piece to its positions,
and the native combiners now do the same, so the column is identical. The
package's proxy and restore methods for Stata numerics change nothing that a
later group's expression can read. Running them once at the combine, or not
at all when the native combine proves them unchanged, gives the same values.
A traced method sees fewer calls.

Results of other classes still recycle at once, because their methods may
have effects that a later group's expression reads. A data frame also
recycles at once, since the mask's copy of it shares its columns with any
later write to the original. A lone group's result recycles at once because a
lone group skips the combiners. So does an empty group's result, such as
`max()` of nothing, which must not reach a cast.

This replaces, for these results, the practice that a shortcut calls every R
function the original path calls or proves it unchanged. The maintainer
approved changing decisions that block measured speedups on 2026-10-22.
