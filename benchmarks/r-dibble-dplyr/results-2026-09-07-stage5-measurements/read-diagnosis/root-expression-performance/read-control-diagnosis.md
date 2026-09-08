# Native read control preparation and fixture correction

The control compares the original declared-character `anyNA(table$c01)` with
`anyNA(column)` after extraction, a public `STRING_ELT` loop and a rooted public
`DATAPTR_RO` loop. It targets one column at 100,000 and 1,000,000 rows. Native
visit counts are separate untimed checks and do not count base R's reads.
The production package and its private backing are unchanged. Native pointers
stay inside each bounded call and never become R results.

Four rejected build attempts remain preserved beside accepted
`native-read-control-build-v5-01`. They record the missing explicit SDK,
Clang's replacement for its deprecated linker-path option, the narrow warning
exemption needed for standard R routine-registration casts, and macOS's required
libSystem linkage. V5 binds the source, compiler, linker, consumed headers,
SDK stubs and compiler runtime archive. It links no second libR. The first
failed discovery attempt did not persist its initial input identities; that
record cannot support a complete historical input-binding claim.

The initial runtime-v1 draft had an accepted-artifact identity gap between build
verification and runtime snapshotting. Runtime v2 fixes that chain and retains
eight passing temporary-artifact guard tests. The unexecuted v1 draft remains
available for review.

Root's first actual baseline run, `baseline-ec10-read-control-v2-01`, stopped
before profiling or timing in its untimed tiny fixture checks. It incorrectly
required a constructed table column to equal a raw `NA_character_` input.
Its failed receipt and all original source/output bytes remain unchanged.

The separate `read-control-fixture-diagnostic-v1` observed all four tiny cases
as ordinary values and table columns on both exact ec10 and a2 installations.
Only table columns constructed from NA inputs differed: NA became an empty
string and `str12` became `str1`. Ordinary inputs stayed unchanged. Public
`anyNA`, both native loops and native visit counts agreed with the actual
stored values. The two diagnostic receipts are
`3dcab58a6646085f3f4a9e58cb589b6b5624c51f55028c48e6a64cbc9222c230`
and `c98cc98e05648f7168b8298d2024decc79d5afff0c7943fbaf99755d88f09097`.

This is established constructor behavior. At ec10,
`r-package/dtatools/R/mutate-data.R` lines 2892–2915 reject a declared string
containing NA; lines 2955–2976 replace those values with empty strings and
recompute storage. A2 retains the same normalization policy. The observations
therefore identify a fixture-oracle error, not a native-loop defect.

`read-control-v2.R` supplies explicit independent raw and normalized stored-value
expectations, checks the expected storage attributes, and names each tiny case.
Its measured no-NA corpus and loop are unchanged. Runtime `read-control-v3.py`
changes only the R driver path from the reviewed v2 runtime. The separate
`read-control-tiny-check-v1` runs the exact corrected prefix without any
profiling or timing, using the same artifact guards. Both final source/evidence
reviews and a coordinated quiet window remain required for new control timings.
