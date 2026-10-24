---
status: accepted
---

# Admit a compact mean on its methods

`mean()` of a compact Stata numeric runs `mean.dta_numeric()`, which since
ADR 0054 computes the mean in one call to `C_dtatools_mean_computed()` once
`C_dtatools_mean_admitted()` admits the call. That admission checks that
`na.rm` settles without running R code, that the `mean()` generic and
`mean.default()` are the frozen copies in `.numeric_mean_dependencies`, and
that no `mean.double()` or `mean.numeric()` method, and no other
`mean.default()`, is registered or visible from the method's frame or the
global environment. It also checks that 18 base functions `mean.default()`
calls, from `isTRUE()` to `UseMethod()`, are unchanged in the base
environment and namespace. That last check took about half of the
admission's 1.6 microseconds, which a grouped verb spends once per group.

`C_dtatools_mean_computed()` now makes its own admission, and
`mean.dta_numeric()` calls it before the full one. It checks the flag, the
generic and the methods as before, but not the 18 base functions. The R
code, which runs for every value the call declines, keeps the full
admission.

A traced or replaced base function that `mean.default()` calls, such as
`isTRUE()` or `is.na()`, no longer sees or changes the mean of a compact
Stata numeric. A replaced or traced `mean()` or `mean.default()`, and a
`mean.double()` or `mean.numeric()` method, still take the call. This
extends the change of practice in ADR 0053. The maintainer approved
changing decisions that block measured speedups on 2026-10-22.
