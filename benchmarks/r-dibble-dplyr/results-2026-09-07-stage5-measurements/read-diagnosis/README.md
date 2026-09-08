# Owned-column read costs and diagnostic controls

These records investigate twelve base-R read flags found when comparing the
Stage 3 source `ec10a6ac34602f3bd691e8043019c1b479babda4` with combined Stage 5
`a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9`. The broader owned-column matrix has a
separate archive. Its original flags remain unchanged.

Three fresh paired repeats retained all twelve flags at one million rows and
none at 100,000 rows. A one-column minimum retained all twelve, with increments
of about 2.0 to 2.4 ms. These cases read one selected column; the original
eight-column fixture does not imply eight million-element scans. The flags
cover declared-character missingness, logical missingness/coercion/mean, and
factor or ordered-factor missingness/character conversion. A flag requires both
an increase above 10% and an increase above 1 ms.

The separate logical Arrow-write flag compares Stage 4 `f622f1d` with `a2d8b6a`.
It did not recur in three fresh paired repeats. The original observation remains
in the broad matrix; these repeats do not establish its cause. The three
retained whole-filter flags require the direct row operations in Stage 6 and
are separate from this base-R read investigation.

The narrowed read driver initially omitted the full runner's tiny rename
warm-up. Its first candidate run failed the unchanged post-read allocation
gate. An allocation-only cold/warm contrast reproduced the failure at 2,191,016
R bytes and passed at 83,192 bytes after one independent four-row rename.
Restoring that warm-up corrected the driver. This contrast does not identify
one internal cause of setup allocation. The failed run and cold probe remain
rejected. The revised driver preserves the original allocation, ownership,
copy and validation-scan gates.

The character controls compare public `anyNA(table$c01)`, the same call on a
pre-extracted column, a native `STRING_ELT` scan, and a native rooted read-only
pointer scan. Across three paired runs, pre-extraction retains the public read
increment. At one million rows, public column medians are about 0.283 ms on ec10
and 2.62 ms on a2. The matched pointer scans are about 0.22 ms on both sources.
The native element scans have different absolute costs, about 1.09 and 5.68 ms.
They cannot be treated as measurements of base R's internal loop or an isolated
getter's latency.

The logical/factor/ordered controls use the original 25% missing fixtures and
compare `sum(!is.na(...))` with native element and rooted pointer counts. Across
three pairs, public table and pre-extracted column reads retain increments of
about 2 ms at one million rows. Native pointer scans are about 0.042 ms on both
sources. They avoid the public expression's intermediate mask allocations, so
their absolute cost is not an equivalent implementation of the whole expression.
Native visit counts are separate untimed checks of the diagnostic loops only.

Together these controls support investigating the per-element access path in
the tested missingness operations. Table lookup does not explain their measured
increments. Compiler opportunities differ between element and pointer scans,
and the controls do not separate all internal costs. They do not establish an
exclusive cause for all twelve reads, prove irreducibility, or constitute a
production fix. The twelve repeatable costs remain explicitly unresolved.

The native controls use public R APIs. Each pointer remains inside a bounded
call whose input is rooted; no allocation, callback or write occurs in the
pointer scan. The original source state records remain available. The accepted
DLL builds bind their compiler, linker, consumed headers, SDK stubs and runtime
archive, and link no second libR. Full external OS/compiler/Python closures
were not frozen.

Four failed character-control builds and the unexecuted first runtime draft
remain available. The first failed build did not preserve initial input
identities. The first actual character runtime failed before timing because
its tiny oracle expected raw NA strings to survive table construction. Both
exact package versions instead normalize those strings and their storage
width. Independent ordinary/stored expectations corrected the fixture oracle;
the measured no-NA character corpus stayed unchanged. Neither failure is
relabeled as successful evidence.

All original selected bytes and Unix modes appear in
[selection.json](selection.json). Drivers, native diagnostic source, reviewer
scripts, dispositions, assessments and this description remain plain files.
Repeated indexes, logs, saved states and raw samples are in `records.tar.gz`.
The selection retains the original receipt status, including every rejection.
Verify membership, bytes and modes without extracting filesystem paths:

```sh
python3 bundle-evidence-v1.py verify .
```

The original profilers removed their temporary allocation-event files.
Bench samples, aggregate allocation counters and saved source states remain;
there is no reconstruction of per-call native events or omitted payloads.
R and native allocation counters can overlap and must not be added. Read
controls do not supply separate retained-heap or whole-process RSS evidence.

The source-reading preparation and all reports retain their original dates,
source identities and scope. Historical pending statements describe their own
stage of work. Installed packages, R/runtime trees, the SDK, primary-source
copies and some review inputs are omitted. Absolute paths identify the original
environment. This selective archive is not a standalone replay bundle or a new
execution of its experiments. Local reviewers inspect the selected bytes; no
claim is made that an external review service inspects compressed contents.
