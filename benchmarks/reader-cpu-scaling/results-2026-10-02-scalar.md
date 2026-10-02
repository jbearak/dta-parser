# Scalar access follow-up, 2026-10-02

The retained change reduces CPU for generic `is.na()` scans of compact columns by 27–29% in the confirmation run. Reverse Arrow scalar scans improve by 28–31%. These are incremental gains over the earlier gather4-v2 candidate, which already includes the initial retained-span cache and reader improvements. They are not comparisons against release HEAD or native Stata.

The implementation is applied to the R package. It forwards known compact columns directly to their native getter, resolves metadata-wrapper state once per access, and caches the entire retained Arrow chunk instead of a suffix. It keeps the compact representation, missing tags, mutation isolation, materialization behavior, and fallback for other sources.

## Why the extra R call mattered

There was no interpreted R loop per cell. The extra work was in native R APIs. On the measured R 4.6.1 build, public `REAL_ELT()` requests an ALTREP vector's length for each element before dispatching its getter. The old metadata getter called `REAL_ELT(source, index)` again, adding a numeric-length callback and another dispatch. The compact getter already checks the index against its descriptor length, so the known-class branch can call it directly.

Base `is.na()` gets the length once and then calls the ALTREP getter directly. After this change, that path no longer performs an additional numeric-length callback per value. A C consumer that calls public `REAL_ELT()` still incurs the outer metadata-length lookup. This is an R API choice and an implementation cost, not a requirement to interpret R for every scalar.

The native scan probe also computes a checksum and missing/infinity counts, calls `R_finite()`, and maintains traversal state. Its time cannot be compared with `is.na()` as if both did identical work. The local library disassembly and bound binaries are documented in the published call-path evidence.

## Independent screen

The screen ran 256 fresh-process observations: 16 cases, four builds, and four balanced rounds. Each candidate changed one mechanism. CPU changes below are medians of round-paired ratios, not differences between separately pooled medians.

| Candidate | Observed CPU result | Decision |
| --- | --- | --- |
| Direct native forwarding | Generic masks improved 14–22%; native scans also improved | Retained |
| Resolve wrapper state once | Point estimates improved 4–9% across the screen | Retained |
| Cache whole retained chunk | Reverse Arrow scans improved 12–14%; forward scans stayed close to baseline | Retained |

No screen operation CPU or elapsed-time interval was entirely above baseline. The reverse-only prototype did have small positive point estimates on several DTA/forward cases. Its shared getter stack frame grew from 48 to 64 bytes. The combined confirmation, rather than the source argument alone, determines the retained result. These isolated percentages are not additive.

## Combined confirmation

The confirmation uses a separately built, source-bound combined candidate, with six balanced paired rounds and eight scans per timed interval. Each column has one million values. Input reads, package loading, explicit GC and qualification are outside the scalar timer. Automatic GC and operation output allocation remain inside. Exact qualification before the timer may populate the scalar cache. Only the last repetition's output is retained.

All 240 observations passed the lazy-state and exact-result checks. Mask checks cover the full logical vector; native scan checks cover same-order aggregate results plus selected values and their missing tags. They do not constitute a bitwise comparison of every decoded scalar. Native and R regression tests separately cover tags, temporal values, chunk boundaries and lifetimes.

CPU milliseconds per scan of one million values:

| Source | Storage | Current | Combined | Paired change | 95% interval |
| --- | --- | ---: | ---: | ---: | --- |
| DTA | byte | 13.94 | 10.19 | -27.1% | [-29.6%, -20.2%] |
| DTA | int | 14.12 | 10.25 | -26.7% | [-29.3%, -22.2%] |
| DTA | long | 14.38 | 10.50 | -27.3% | [-28.6%, -25.0%] |
| DTA | float | 14.00 | 10.00 | -29.1% | [-30.5%, -26.9%] |
| ARROW | byte | 14.44 | 10.50 | -27.8% | [-29.7%, -26.4%] |
| ARROW | int | 14.38 | 10.50 | -27.0% | [-28.2%, -25.3%] |
| ARROW | long | 14.50 | 10.44 | -28.0% | [-28.9%, -27.1%] |
| ARROW | float | 14.00 | 10.00 | -28.5% | [-31.3%, -23.6%] |

The other confirmation cases use a native scalar consumer with forward, reverse and deterministic coprime-stride traversal. The latter visits every position once without allocating a shuffled index vector.

| Source and native scan | Current ms | Combined ms | Paired change | 95% interval |
| --- | ---: | ---: | ---: | --- |
| DTA byte, forward | 26.81 | 21.69 | -19.4% | [-22.1%, -17.5%] |
| DTA float, permuted | 26.25 | 21.06 | -20.2% | [-21.3%, -18.9%] |
| Arrow byte, reverse | 30.19 | 21.69 | -28.1% | [-30.0%, -27.3%] |
| Arrow float, reverse | 30.38 | 20.94 | -30.9% | [-31.7%, -29.8%] |

All 20 operation CPU and elapsed-time paired intervals favor the combined candidate. Whole-process CPU and elapsed-time intervals also favor the combined build in every scalar case. Peak RSS has two small positive paired intervals, with point estimates of +0.02% and +0.03%. RSS includes both input tables, the reference table and all qualification work, not just the timed scalar operation.

## Reader controls

The reader controller ran 192 fresh-process observations: four fixtures, two file formats, read-only and read-plus-consume modes, two builds and six paired rounds. Both readers used dibble output and automatic threads. Fixtures cover ordinary doubles, compact numerics, mixed strings/numerics and a very wide table. All 16 reader/library/fixture qualification runs passed exact value, complete signature and consumption checks.

For consumption, the existing worker visits every column, casts numeric columns to doubles, sums their values and counts missing values. There is no R loop over individual elements. The change improves the generic scalar missing-value traversal after the cast.

The compact fixture has one million rows and 32 columns:

| Format and interval | Current seconds | Combined seconds | Paired change | 95% interval |
| --- | ---: | ---: | ---: | --- |
| DTA, read + consume CPU | 0.5705 | 0.4600 | -19.95% | [-20.91%, -18.69%] |
| DTA, read + consume elapsed | 0.5280 | 0.4175 | -21.51% | [-22.71%, -20.21%] |
| ARROW, read + consume CPU | 0.5465 | 0.4325 | -21.36% | [-22.78%, -18.49%] |
| ARROW, read + consume elapsed | 0.5070 | 0.3940 | -22.67% | [-24.19%, -20.02%] |

Consumption CPU alone improves by 22.9% for DTA and 23.0% for Arrow. Read-only CPU medians remain 75 ms for DTA and 46 ms for Arrow, with intervals crossing zero change. Loading is not where this optimization earns its gain.

Across all 16 reader cases, no read or total CPU/elapsed interval is entirely above baseline. Peak RSS has two positive intervals: compact Arrow read-plus-consume has a paired estimate of +0.041%, with medians 266.95 to 267.08 MiB; mixed DTA read-only has +0.529%, with medians 360.24 to 362.43 MiB. The compact descriptor layout and buffer widths are unchanged. These process-level RSS observations should not be presented as zero memory change.

## Validation and scope

The accepted build passes the full installed R suite: 36,830 assertions, zero failures, errors or skips, and seven warnings matching the previous gather4-v2 build by test and count. All 41 Rust bridge tests pass; Clippy with warnings denied and formatting checks pass. The installed package inventory and all 449 production source files match the measured accepted build. `git diff --check` passes. This follow-up did not rerun `R CMD check` or the full cross-language conformance matrix.

The internal whole-chunk lookup borrows from the same rooted immutable owner and preserves the existing region API. It performs no allocation or R callback. Cloned descriptors start with an empty cache; materialized and detached handles keep their existing behavior. Three-slot mutation views still synchronize missing counts before forwarding. Arbitrary foreign ALTREP sources inside a metadata-real proxy retain their fallback by inspection; public constructors do not create that exact state, so the added R tests do not claim to exercise it.

These are warm-filesystem measurements on one host, with R 4.6.1 and the recorded toolchain. Builds, tests and profiling were stopped during timed runs. There is no hardware isolation from unrelated system activity. Bootstrap intervals use paired rounds and are unadjusted across comparisons. Small unresolved effects should not be treated as portable guarantees.

The [screen summaries](results-2026-10-02-scalar/screen/paired-summary.csv), [confirmation summaries](results-2026-10-02-scalar/acceptance/paired-summary.csv), and [reader summaries](results-2026-10-02-scalar/reader-controls/paired-summary.csv) retain every comparison. The corresponding [scalar protocol](results-2026-10-02-scalar/acceptance/protocol.json) and [reader qualification](results-2026-10-02-scalar/reader-controls/qualification.json) define the intervals and equality checks.

The [native call-path evidence](results-2026-10-02-scalar/scalar-callpath.md), [incremental patch](results-2026-10-02-scalar/patches/combined-incremental.patch), [accepted build receipt](results-2026-10-02-scalar/builds/accepted/build-receipt.json), [reader build bindings](results-2026-10-02-scalar/builds/combined-bindings/build-bindings.json), and [validation record](results-2026-10-02-scalar/validation/final-validation.json) bind the implementation to the results.

Reproduction instructions are in the [controller README](results-2026-10-02-scalar/controllers/README.md). Private paths are replaced only through recorded transformations in the [source map](results-2026-10-02-scalar/publication-source-map.json). The [artifact manifest](results-2026-10-02-scalar/publication-manifest.json) records published hashes; input files and installed binaries are not published. Raw observations, installed inventories, source patches and before/after bindings remain available in the artifact directory.
