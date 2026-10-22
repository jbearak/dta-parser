---
status: accepted
---

# Combine group results that share attributes in one pass

Grouped `mutate()` and `summarise()` on a dibble evaluate an expression once
per group and combine the results with vctrs. vctrs folds the results into a
common type with `vec_ptype2()`, one result at a time, and casts each result
to that type with `vec_cast()`. For Stata numerics both methods are the
package's own, and both reach the helpers that merge value labels and restore
attributes. A native combine already takes results that carry no Stata
metadata. It first proves that every method and helper it skips is unchanged,
so a traced or replaced one still sees every call. Results that keep a
variable label, value labels, or a display format took the vctrs path. Those
are what `first()`, `last()`, `nth()`, `lag()`, `lead()`, and indexing return
on a column that `read_dta()` reads. In `summarise(b, m = first(b2), .by =
caseid)` over the first 20,000 rows of the India 2021 DHS births file, the
folds and casts took about 70% of the time.

Until now a shortcut either called every R function the original path calls
or first proved that each function it skipped was unchanged. For these
results that proof would cover the whole label-merging graph, so they kept
paying for a fold and a cast per group.

The combiners now take a shorter path when every result has the same
attributes as the first. That first result must be a Stata numeric whose
first class is `dta_numeric`. It must not be temporal or have names, and it
must carry only Stata variable attributes, at least one of them besides its
storage. The combiners compute the common type of the first two results with
`vec_ptype_common()`. That type must have the results' own attributes in the
same order, and `vec_ptype2()` of the type and the third result must return
the type. Then the combiners take each result's payload, place them with
`list_unchop()`, and restore the type with `vec_restore()`. A fold that
signals an error, warning, or message sends the results down the vctrs path.
Two names for one value-label code therefore still warn once per fold.

The package's `vec_ptype2()` and `vec_cast()` methods read only attributes.
So every later fold sees the inputs of the fold checked and returns the same
type, and every cast returns its result unchanged. The combined vector is
identical to the one vctrs builds. `summarise()` keeps each group's result as
that group's binding for later expressions, where it had kept the cast, and
the two are identical.

The methods and their helpers now run two or three times per combine rather
than once per group. A traced method sees fewer calls. A replacement method
that reads values answers for the first three results only. The change gives
up both, for these results only. Results without Stata metadata keep the
native combine and its proofs, and all other results keep the vctrs path.

On the first 100,000 rows of the births file, with 42,739 women,
`summarise(b, m = first(b2), .by = caseid)` takes about TODO seconds rather
than TODO, and `mutate(b, m = lag(b2), .by = caseid)` about TODO rather than
TODO.

This replaces, for these results, the practice that a shortcut calls every R
function the original path calls or proves it unchanged. The maintainer
approved changing decisions that block measured speedups on 2026-10-22.
