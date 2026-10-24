---
status: accepted
---

# Plan a grouped summary of one column

A grouped `summarise()` evaluates each expression once per group. For each
group, `mask$with_group()` builds a data mask, `rlang::eval_tidy()`
evaluates the expression in it, `.retyped_column()` types the result,
`C_dtatools_chunk_size()` measures it and `.capture_dibble_nested()` copies
it. For `mean(b2)` of a compact Stata numeric, the expression itself takes
one native call since ADR 0054, so these steps cost most of the time:
`summarise(b, m = mean(b2), .by = caseid)` over the 42,739 women in the
first 100,000 rows of the India 2021 DHS births file took about 0.43
seconds, and `summarise(b, k = 2.5, .by = caseid)`, with nothing to compute,
took 0.27.

`.dibble_summary_columns()` now first passes each expression to
`.summary_planned()`. When the expression is `mean()`, `min()`, `max()` or
`sum()` of one column, with `na.rm` left out or given as a logical, and the
result does not replace a column, it asks `C_dtatools_summary_plan_admitted()`
whether each group's evaluation would end in the package method's native
result with no R code on the way:

- The generic R finds from the quosure's environment is base's, as the
  frozen copies have it, and no column carries its name.
- Dispatch on the class `dta_numeric` finds the frozen `mean.dta_numeric()`
  or, for the Summary group, no method for the generic itself and then the
  frozen `Summary.dta_numeric()`. The lookup follows `R_LookupMethod()`: the
  environments from the quosure's through its `topenv()`, then the base S3
  table, then every environment after.
- No binding on these walks is a promise or an active binding, which the
  lookup would run, and none of them is a missing argument where the call
  looks for its function.
- For the mean, the admission `C_dtatools_mean_computed()` makes holds.
- Neither the generic nor the method is being debugged.

Only then does it read the column's group chunks, as the first group's
evaluation would. `C_dtatools_summary_plan()` repeats the admission, since
reading the column can run R code, and computes each chunk's result with
the code the methods' native calls use, then measures and copies it as the
loop does. It returns the chunks and sizes the loop would build, and the
rest of the summary runs as before. It declines, and the loop runs, when
any chunk would leave its group to the R code: a column that is not
compact, such as a double, an empty group's or an all-missing group's
`min()` or `max()`, which warn, and a metadata proxy that `min()`, `max()`
or `sum()` reads another way. The same summary now takes about 0.12
seconds.

The plan does not prove what it skips. A traced or replaced
`mask$with_group()`, `rlang::eval_tidy()`, `.retyped_column()` or
`.capture_dibble_nested()` no longer sees a planned expression's groups,
and the mask keeps no binding set or data mask for them. A replaced or
traced generic or method, a method defined where R would find it first, and
a debugged generic or method still take the loop. The maintainer approved
changing decisions that block measured speedups on 2026-10-22.
