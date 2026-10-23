---
status: accepted
---

# Type typed and scalar results in one native call

A grouped `summarise()` types each group's result with `.retyped_column()`.
With no prior column of the result's name, that calls `.typed_column()`. A
Stata numeric, temporal or factor result, or a bare logical, is typed already,
and `.typed_column()` returns it after `.dta_typed_column()` says so. A bare
integer or double scalar, such as `n()` or a constant, passes through
`.dta_typed_column()`, `.is_unmaterialized_dictstring()`,
`.dta_untypable_column()`, `.generated_numeric_class_supported()`,
`.normalize_untyped_column()` and `.generated_column()` before
`.generated_column()` hands it to `C_dtatools_generate_scalar()`, which builds
a long from an integer and a double from a double. Those R calls cost more
than the native call they lead to, once per group.

`.retyped_column()` now calls `C_dtatools_typed_column_fast()` first. It
returns a Stata numeric, temporal or factor value, and a bare logical, as it
is. For a bare integer or double scalar that `.generated_column()` would hand
to `C_dtatools_generate_scalar()`, under the same range checks, it makes that
call with the storage the R code names. It returns `NULL`, and the R code
types the value as before, for anything else: S4 objects, strings, other
classes, vectors longer than one, values with attributes, ALTREP values,
integers beyond Stata's long range, and missing, infinite or very large
doubles. A value with a prior column keeps `.promoted_column()`.

The call reads the row count from `.retyped_column()`'s frame, and forces it
only for a scalar it types, after the checks that `.generated_column()` makes
first. The call sites pass `length(value)` as a promise. `.typed_column()`
never forced it for a typed value, and on a classed value `length()` looks
for a method for each class, which cost more per group than the call saved.
On a foreign ALTREP vector it runs the provider's code, which the R code runs
only after its own checks.

The call does not prove the helpers it skips. A traced or replaced
`.typed_column()`, `.dta_typed_column()`, `.dta_untypable_column()`,
`.generated_numeric_class_supported()`, `.normalize_untyped_column()` or
`.generated_column()`, or a base function they call such as `inherits()`,
`typeof()` or `is.object()`, no longer sees the values the call covers. This
replaces, for these values, the practice that a native route proves every R
function it skips unchanged. The maintainer approved changing decisions that
block measured speedups on 2026-10-22.
