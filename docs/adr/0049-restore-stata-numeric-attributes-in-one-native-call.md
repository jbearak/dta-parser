---
status: accepted
---

# Restore Stata numeric attributes in one native call

Every vctrs slice, cast, or combination of a Stata numeric restores its
attributes through `vec_restore.dta_numeric()`, which calls
`.restore_dta_metadata()`. That R function plans the attributes with
`.dta_attribute_plan()` and `.dta_classes_from()`, then sets them one at a
time in `.replace_dta_attributes()`. On a labelled column the restore took
about TODO microseconds. Verbs restore every column they slice, and grouped
verbs restore each column once per group.

`.restore_dta_metadata()` now starts with one native call that sets the same
attributes in the same order. The call declines, and the R code runs, for an
attribute the R code warns about, a storage or class vector it does not
recognize, an S4 object, and a data.table.

Until now, a native route that skipped package helpers ran only after it
proved them unchanged, so a traced or replaced helper still saw every call.
This call does not check. Proving the helpers and the base functions they
reach would cost most of what the call saves. A traced or replaced
`.dta_attribute_plan()`, `.dta_classes_from()`, or `.replace_dta_attributes()`
no longer sees the restores the call makes. The helpers still run for the
cases the call declines, and `gen()` still reaches `.dta_attribute_plan()`
directly. Load forces their lazy bindings, since the combine and summary
checks read those bindings without forcing them and no restore does any
more.

TODO numbers.

This replaces, for this restore, the practice that a native route proves
every R function it skips unchanged. The maintainer approved changing
decisions that block measured speedups on 2026-10-22.
