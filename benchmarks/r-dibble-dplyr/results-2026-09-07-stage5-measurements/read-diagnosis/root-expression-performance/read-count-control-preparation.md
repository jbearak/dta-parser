# Logical and factor nonmissing-count controls

The six preceding character-control runs passed. Both independent audits verified
48 series, 336 raw samples and 192 unchanged source states. Pre-extracting a
character column retained the public `anyNA` cost difference. The matched native
pointer scans removed the between-source difference. Native `STRING_ELT` scans
had different absolute costs from base R, so those timings cannot identify the
latency of an isolated base getter or explain all twelve open read costs.

This extension tests the same predictions on logical, factor and ordered data.
It uses the original one-column fixtures at 100,000 and 1,000,000 rows, with 25%
NA values. For each fixture it compares `sum(!is.na(table$c01))`, the same public
operation on a pre-extracted column, a typed public `LOGICAL_ELT` or `INTEGER_ELT`
full scan, and a rooted public `DATAPTR_RO` full scan. All four must return the
same integer count as the independent ordinary fixture. The native controls
are matched scans; they are not allocation-equivalent implementations of the
whole public R operation. Their separate untimed count-and-visit results count
only the diagnostic native loop.

`read-count-control-v1.c` accesses only public R APIs. Its native pointer stays
inside a bounded call, its input remains rooted, and no allocation, callback or
write occurs during the pointer scan. The routine accepts logical or integer
inputs of at most one million elements. The production package, original
character control, and all historical rejected attempts remain unchanged.

`build-read-count-control-v1.py` changes only the C source path and usage text
from the accepted character-control builder. The build at
`native-read-count-control-build-v1-01` passed with receipt
`13a64e286d65a0fc233ec5df24fc1fbe439ea13681f8ba51a938d303be320b08`.
It retains the same compiler/header/SDK/library scope and limits.
`read-count-control-v1.py` changes only the R driver path and scope text from
the reviewed character runtime v3, retaining its accepted-build bindings.

The separate `read-count-tiny-check-v1` runs the exact new untimed prefix with
no profiling or timing. Its 24 cases cover all three types, empty/nonmissing/
all-missing/mixed values, and ordinary/table columns. They check values, result
types, attributes, and native visit counts. Both exact sources pass:

- ec10 receipt `8a68e63121b4f908dacbba79e9fafc1eb6e75d5293342e0704b83a01914cbce4`
- a2 receipt `259cbd153f9cdfd42b7008c723bcfd2b24c640ed5277d1f385a5bde6c28b3d90`

The 24-series measurement driver remains unexecuted. Both independent source,
build and tiny-output reviews and a coordinated quiet window are required
before timing. No production optimization or final performance acceptance is
claimed.
