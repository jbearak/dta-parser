---
status: accepted
---

# Compute small Stata arithmetic in one native call

`.dta_arith_base()` computes `+`, `-`, `*`, `/` and the other arithmetic
operators when an operand is a Stata numeric. Its R code captures each Stata
operand with `.dta_data()`, recycles the operands with
`vctrs::vec_recycle_common()`, applies the base operator, finds the positions
where either operand is missing with `.dta_read_is_na()`, makes them system
missing with `.collapse_missing()`, and builds the result with
`.dta_computed()`. Its native routes prove those helpers unchanged, so the
size gate of ADR 0050 leaves operands under 2,048 values to the R code. That
covers each group's operands in a grouped verb. `x + 1` on a three-value int
took about 10.3 microseconds, and `.dta_arith_base()` took about 40% of
`mutate(b, m = b2 + 1, .by = caseid)` over the 42,739 women in the first
100,000 rows of the India 2021 DHS births file.

`.dta_arith_base()` now first calls `C_dtatools_arithmetic_small()`. For `+`,
`-`, `*` and `/` on operands under the size gate, it takes the R code's steps:
it reads the values as `.dta_data()` does, recycles an operand of length one,
applies the operator, makes each position where either operand is missing
system missing, and builds the result with the code
`C_dtatools_computed_values()` uses. One operand must be a compact Stata
numeric with the package's classes, value labels allowed, or a canonical
double, and the other another or a bare double, integer or logical vector
without attributes. The call declines, and the R code runs, for other
operators, for operands with names or a subclass, for a bare operand with any
attribute, for unequal lengths other than one and for empty operands, while an
operand or the operator is a promise that would evaluate a call, while the
size gate's test hook is at 0, and when base binds the operator to anything
but the primitive in `.numeric_binary_dependencies`. As the R code does, it
forces the operator and then `minimum` after computing. `x + 1` on a
three-value int takes about 4.0 microseconds.

The call does not prove what it skips. For operands under 2,048 values, a
traced or replaced `.dta_data()`, `.metadata_view()`, `.dta_read_is_na()`,
`.collapse_missing()`, `.dta_computed()`, `vctrs::vec_recycle_common()`,
`getExportedValue()` or `suppressWarnings()` no longer sees the computation.
Neither does a `names()` method registered for the package's classes, which
`.dta_data()` calls. Operands of 2,048 values or more keep the proven native
routes and the R code, and the tests check those guarantees at that size.
Tests that checked them on smaller operands now use 2,048 values or lower the
size gate with its test hook. Since small arithmetic no longer runs the R
code, it no longer loads the helpers' lazy bindings either, so the first
operation on 2,048 values or more after only smaller ones takes the R code
once.

This extends ADR 0050 to arithmetic: for operands under the size gate, a
native route need not prove every R function it skips unchanged. The
maintainer approved changing decisions that block measured speedups on
2026-10-22.
