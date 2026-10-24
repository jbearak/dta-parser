---
status: accepted
---

# Scan summary chunks' attributes natively

A grouped `summarise()` finds the common type of each expression's results
in `.dibble_summary_ptype()`. When `.summary_ptype_settles()` proves that
only the first chunk with each distinct set of attributes can change that
type, vctrs folds only those chunks. `.summary_ptype_kept()` finds them,
and it runs up to twice per expression: once for the proof and once for
the call to vctrs. It looped over the chunks in R, calling `attributes()`
on each and comparing the result with `identical()` to each set seen so
far.

`.summary_ptype_kept()` now calls `C_dtatools_summary_ptype_kept()` first,
which returns what the R loop returns, `NULL` included. It reads each
chunk's attributes with `R_mapAttrib()`. For `NULL`, an atomic vector or a
list, `attributes()` returns them in that stored order with those values,
unless they include row names, dimensions or dimnames, which it reads
through `getAttrib()`. The call compares two sets as `identical()` compares
the lists `attributes()` returns, with its default flags: the names first,
then each value through `R_compute_identical()`. Like the R loop, it never
records a chunk without attributes as a seen set, since assigning `NULL` to
a list element adds nothing, so every such chunk counts as a first. It
returns `FALSE`, and the R loop runs, when `chunks` is not a plain list,
when a chunk is another type or has row names, dimensions, dimnames or more
than 16 attributes, and when the R loop's integer sums would overflow.

The call does not prove the functions it skips. A traced or replaced
`identical()` or `vapply()` no longer sees the chunks the call scans. This
extends the change of practice in ADR 0053 to these calls. The maintainer
approved changing decisions that block measured speedups on 2026-10-22.
