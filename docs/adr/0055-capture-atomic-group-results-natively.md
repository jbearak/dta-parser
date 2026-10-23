---
status: accepted
---

# Capture atomic group results natively

A grouped `summarise()` captures each group's result with
`.capture_dibble_nested()`, so later writes cannot reach it. For an atomic
vector, the usual result, that function checks `is.environment()`,
`is.function()` and `typeof()` twice, then calls `.metadata_copy()`, which
copies the vector with `C_dtatools_metadata_copy()` and passes the copy to
`.repair_data_table_container()`, which returns it unless it inherits from
data.table. That took about 1.2 microseconds per group, against 0.3 for the
copy. Each group's result is also typed against the column of the same name,
if the mask has one. A closure, created once per group, checked
`name %in% mask$helpers$current_vars()` for it.

`.capture_dibble_nested()` now calls `C_dtatools_capture_atomic()` first. For
a logical, integer, double, complex, character or raw vector, it returns
`C_dtatools_metadata_copy()` of the vector, which is what the R code
returns. It returns `NULL`, and the R code runs, for anything else: lists
and data frames, environments, functions and other reference types, S4
objects, objects whose class names data.table, and objects whose class
vector is ALTREP, whose reads could run a provider's code that the R code
would then run again.

`summarise()` now checks once per expression, before its groups run,
whether the expression's name is a column of the mask. The mask's columns
change only when results are installed, after the groups run, so the answer
is the same for every group. A data frame result, whose columns each take
their own name, keeps the check in each group.

Results are unchanged. For atomic values, a traced or replaced
`.metadata_copy()` or `.repair_data_table_container()`, or a traced base
`is.environment()`, `is.function()` or `typeof()`, no longer sees the
capture, and a traced `%in%` sees one call per expression instead of one per
group. The initial-capture test that replaces or traces each helper now
expects `.metadata_copy()` to see no calls, since all its columns are
atomic. This extends the practice of ADR 0050. The maintainer approved
changing decisions that block measured speedups on 2026-10-22.
