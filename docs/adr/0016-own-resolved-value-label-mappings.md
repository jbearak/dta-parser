---
status: accepted
---

# Own resolved value-label mappings

`dtatools` treats the resolved code-to-text mapping on each variable as authoritative. Stata instead stores named value-label definitions at dataset scope and assigns variables to them. Imported table names can survive in R as serialization hints, but `dtatools` does not maintain a live shared registry whose name can override a variable's mapping.

This intentionally changes one Stata merge edge case. When master and using define different mappings under the same table name, Stata retains the master's definition. A using-only variable can then display unrelated labels, which can silently misdirect a later label-based recode. `dta_merge()` keeps that variable's resolved using mapping. Writers may preserve an unambiguous imported name hint or synthesize independent definitions, but they never substitute one variable's mapping for another merely because the names match.

Exact Stata ports should treat an unintended same-name, different-definition collision as a source-data bug and rename or reassign the Stata definition before merging. Public authoring APIs for a dataset-level registry are not needed to reproduce this accidental collision.
