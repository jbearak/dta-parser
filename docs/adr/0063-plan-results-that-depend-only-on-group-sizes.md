---
status: accepted
---

# Plan results that depend only on group sizes

After ADR 0062, a grouped summary of one column's `mean()`, `min()`,
`max()` or `sum()` skips the group loop for every group after the first.
Expressions whose results depend only on the groups' sizes still ran the
loop: `n()`, `row_number()` and a literal number. Over the 42,739 women in
the first 100,000 rows of the India 2021 DHS births file,
`summarise(b, n = n(), .by = caseid)` took about 0.30 seconds,
`summarise(b, k = 2.5, .by = caseid)` 0.24 and
`mutate(b, r = row_number(), .by = caseid)` 0.25, most of it in the loop's
steps for each group. `count()` and `tally()` summarise
`dplyr::n()`.

Before the second group, `.summary_planned()` now passes such an expression
to `.size_planned()`:

- `n()`, called bare or as `dplyr::n()`, in a grouped `summarise()`,
  `reframe()` or `mutate()`, and `row_number()` without arguments in a
  grouped `mutate()`. dplyr 1.2.1 defines `n()` as
  `peek_mask()$get_current_group_size()`, which reaches the mask's helper
  through `context_peek()`, `context_peek_bare()` and base's `%||%`, and
  `row_number()` as `seq_len(n())`. `C_dtatools_size_plan_admitted()`
  checks that the function the call finds, and each of those, has the
  formals and body the package recorded from dplyr 1.2.1 when it was built,
  dplyr's namespace or, for `%||%`, base's, and no attributes, which a
  traced function carries. The records hold no environment, so reading
  them loads no namespace, and they are NULL when the package was built
  without dplyr 1.2.1. The lookup follows R's: from the quosure's
  environment for a bare call, and through dplyr's export table, as the
  `::` primitive reads it, for a qualified one, whose `::` must be the
  primitive. The primitives these functions call, `$`, `[[`, `seq_len()`,
  `missing()`, `is.null()`, `if` and `{`, must be base's from dplyr's
  namespace. No binding on the walks may be a promise or an active binding,
  and no column may carry the name R looks up. dplyr's context must hold
  this mask's helpers. None of the closures may be being debugged.
- A literal double or integer scalar in a grouped `summarise()` or
  `reframe()`. A `mutate()` already recycles a literal to the whole table
  before it chops it. A literal calls nothing, so it needs no admission.

An expression or call head with a class declines before anything reads
it, here and in the summary plan of ADR 0061, since its `[[` and
`length()` methods would run R code the loop does not. The native call
declines an ALTREP literal before it measures one, since its Length method
could run R code too.

`C_dtatools_size_plan()` repeats the admission and builds each later
group's result as the loop would. For `mutate()`, that is the group's size,
or its rows' positions in the group, which the loop then combines. For a
summary, the result is typed as `.retyped_column()` types a new column's
value, through `C_dtatools_typed_column_fast()` and
`C_dtatools_typed_scalar_fast()`, then measured and captured. It declines,
and the loop goes on, for a literal those calls leave to the R code, such
as `NA_real_`, for a `mutate()` with an empty group, whose results the
loop recycles itself, and for a group whose rows have a class or are
ALTREP. The loop measures each group's rows in turn, and a `length()`
method or an ALTREP Length method could run R code, so the plan declines
before it reads them. The summary plan of ADR 0061 now checks a
`mutate()`'s groups the same way, instead of with `lengths()`. The `n()`
summary now takes about 0.07 seconds, the literal's 0.06 and the
`mutate()` 0.02.

As in ADR 0061, the plan does not prove what it skips. A traced or replaced
`mask$with_group()`, `rlang::eval_tidy()`, `.retyped_column()`,
`.capture_dibble_nested()` or the mask's `get_current_group_size()` no
longer sees a planned expression's groups. A function R finds first under
the same name, and a traced, replaced or debugged one of the recorded
dplyr functions, still take the loop. The maintainer approved changing
decisions that block measured speedups on 2026-10-22.
