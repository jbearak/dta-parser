---
status: accepted
---

# Compare Stata numerics in one native call

`Ops.dta_numeric()` passes the six comparisons to `.dta_compare()`, which
checks the operands' temporal kinds and lengths and then calls
`.dta_compare_native()`. That function maps the operator to a code, settles
`getOption("dtatools.threads")`, and converts a length-one operand to the
kernel's value and rank with `.dta_compare_scalar()`, which calls
`as.double()` and, for a missing value, `.tab_missing_codes()`. For a Stata
numeric, `as.double()` runs `as.double.dta_numeric()`, which copies the vector
with `.dta_snapshot()`. It then calls `C_dtatools_dta_compare()` up to three
ways: with the right operand as the scalar, with the left one as the scalar
and the operator flipped, and with two vectors of one length. The first result
it gets is the comparison. `x == 2016` on three values of an int column took
about 4.6 microseconds, most of it in those R steps, and `filter(b, b2 ==
max(b2), .by = caseid)` makes one such comparison per group.

`Ops.dta_numeric()` now first calls `C_dtatools_compare_direct()`. It reads
`.Generic`, `e1` and `e2` from the method's frame. For the six comparisons, it
takes operands that are each a bare double, integer or logical vector without
attributes, or a Stata numeric with the package's classes, value labels
allowed, without names and not temporal. Their lengths must be equal or one,
and not zero. It reads a length-one operand's value and missing code as
`.dta_compare_scalar()` would find them, settles the thread option as
`.dta_compare_native()` does, and makes the same kernel calls in the same
order. It returns the first result, or declines, and the R code runs, when no
call returns one. It also declines while an operand is a promise that would
evaluate a call, and for a thread option with attributes or one that
`as.integer()` would turn into `NA` with a warning.

Results are unchanged. A traced or replaced `.dta_compare()`,
`.dta_compare_native()`, `.dta_compare_scalar()`, `.tab_missing_codes()`,
`as.double.dta_numeric()`, `.dta_snapshot()` or `.metadata_copy()` no longer
sees these comparisons, nor do the base functions they call, such as
`getOption()`, `length()` and `inherits()`, or a `length()` method defined for
the package's classes. Temporal values keep the R code, as does the fallback
of an ungrouped `mutate()`'s fused comparison, which calls `.dta_compare()`
directly. This extends the practice of ADR 0050 to comparisons. The maintainer
approved changing decisions that block measured speedups on 2026-10-22.
