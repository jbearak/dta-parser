# Local-reader performance, September 13, 2026

Avoiding unnecessary source-adapter loading removes the small-file performance
gap in this corpus. All 1,812 comparable files now read faster than haven's
measurements. Previously, 343 were slower. Their total dtatools read
time falls from 149.222 to 55.101 seconds, a 63.1% reduction.

I recommend shipping this change. It removes fixed setup costs without changing
the native decoder, thread policy, buffer size, or Arrow verification default.
The largest relative gains occur on small files, with smaller improvements on
larger first reads. Memory improvements are not uniform across all workloads.

## What caused the gap

All 343 previous losses were below 10 MB, and 253 were below 1 MB. A real
350-byte DTA file repeatedly took 56 to 57 ms, versus haven's 15 ms.
Reading zero observations still took 56 ms. Repeated reads in the same R process
took about 0.3 ms, pointing to first-call setup rather than row decoding.

Profiling located most samples in `.resolve_dta_source()` and namespace loading.
An ordinary local path called `readr::datasource()`, loading readr and its
dependencies. The implicit-extension check also loaded `tools`. Preloading
readr separately removed roughly 40 ms; disabling R's JIT did not help.
The production fix avoids this work on the read path. It does not move it into
package loading or benchmark warmup.

The resolver checks six bytes of a regular local file for DTA or Arrow content.
Recognized files go directly to the existing native reader. Compression is
detected by content through the existing fallback, so an archive renamed to
`.dta` still decompresses. URLs, raw inputs, connections, source objects and
literal-data inputs retain the adapter path. The local extension predicate
preserves `tools::file_ext()` semantics without loading its namespace.

Some legacy survey files contain nonzero values in an unused header byte. An
initial candidate missed those files; the final probe ignores that byte, as the
parser does. Fresh-child regression tests cover this case and both readers.

## Paired measurements

Each row uses ten fresh processes per version, alternating old/new order five
times in each direction. The warm filesystem cache, input bytes and workers are
the same. Wall and CPU clocks cover the first reader call; whole-process CPU
also includes startup. R's clocks resolve about 1 ms here, so tiny medians should
be read at that precision. Peak RSS is the whole process with its result live.

| Input | Old/new wall, ms | Old/new CPU, ms | Old/new peak RSS, MB |
| --- | ---: | ---: | ---: |
| NSFG, 350 bytes, 1 row, 2 columns | 57 / 2 | 57.5 / 2 | 117.4 / 97.9 |
| MICS, 39 KB, 166 rows, 3 columns | 57 / 2 | 57 / 2 | 117.5 / 98.1 |
| MICS, 499 KB, 4,732 rows, 66 columns | 58 / 3 | 58 / 3 | 119.0 / 98.5 |
| NSFG, 1.2 MB, 22,995 rows, 7 columns | 57 / 3 | 57 / 2 | 118.4 / 98.1 |
| NSFG, 98.7 MB, 22,995 rows, 3,560 columns | 147 / 98 | 239 / 189 | 261.4 / 255.4 |
| Synthetic Arrow, 69 KB, 1,000 rows, 8 columns | 43 / 26 | 43 / 26 | 99.2 / 98.8 |
| Synthetic Arrow, 8.7 MB, 1,000 rows, 1,024 columns | 63 / 44 | 74 / 55.5 | 118.9 / 121.1 |

For the 350-byte file, whole-process CPU falls from 207.5 to 151.3 ms, confirming
that the read-clock saving is not displaced startup work. The wide Arrow
fixture's peak increases by about 2.2 MB. The gain is primarily time and CPU;
this change is not a universal memory reduction.

Warm batches also improve. Each of ten fresh processes per version performs
one untimed read, collects garbage, then times 500 reads together. Per-call wall
and CPU medians for the 350-byte DTA decrease from 260 to 214 microseconds, a
17.7% reduction. Small Arrow decreases from 260 to 236 microseconds. On the
499 KB DTA, wall time decreases only from 1.344 to 1.317 ms. These batch timings
include any garbage collection during the measured loop; their process peaks
are not single-read RSS measurements.

[All paired observations](paired-observations.csv),
[medians and ranges](paired-summary.csv), [input identities](paired-inputs.csv),
and [reproduction instructions](../README.md).

## Survey corpus

One fresh-process read was attempted for every original inventory entry.
1,821 of 1,823 succeed; the same two malformed files fail. All 1,812 historically
comparable files retain their dimensions. The eleven historically excluded
entries remain outside these totals. Measurement identities are recorded in
the provenance artifact.

| Corpus | Files | Old/new dtatools wall, s | New dtatools CPU, s | Haven wall, s | Stata wall, s | New maximum RSS, GB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| DHS | 641 | 69.286 / 39.546 | 82.029 | 2727.051 | 68.806 | 5.232 |
| MICS | 949 | 60.056 / 6.647 | 13.148 | 216.732 | 1.155 | 0.241 |
| NSFG | 222 | 19.880 / 8.908 | 14.584 | 234.588 | 0.885 | 0.552 |

Corpus CPU decreases from the preceding 199.363 to 109.761 seconds. These are
sums of read-call times; RSS is the largest single-file process peak, not a
batch sum. MICS maximum RSS rises from the preceding 0.231 to 0.241 GB, despite
the reductions on repeated small DTA cases. A corpus pass has one observation
per file and should not be treated as a universal performance guarantee.

| Input size | Files | Previously slower than haven | Now slower | Old/new dtatools median, ms |
| --- | ---: | ---: | ---: | ---: |
| Below 100 KB | 28 | 28 | 0 | 58 / 2 |
| 100 KB to 1 MB | 250 | 225 | 0 | 60 / 4 |
| 1 to 10 MB | 755 | 90 | 0 | 64 / 7 |
| 10 to 100 MB | 695 | 0 | 0 | 91 / 47 |
| 100 MB and above | 84 | 0 | 0 | 175.5 / 117.5 |

[Totals by release](corpus-summary.csv), [size bins](corpus-size-bins.csv),
and [file counts](corpus-statistics.json).

## India DHS, ten fresh reads per reader

The 5.2 GB DTA contains 724,115 rows and 5,972 columns. Arrow reads use the same
5.6 GB conversion, with checksum verification enabled. DTA/Arrow order
alternates across ten rounds. There is no warmup or added pre-read garbage
collection. Read-call clocks exclude startup but include first-call reader work.
The comparison includes ten observations each for haven and Stata.

| Reader | Wall median, s | Wall range, s | CPU median, s | Peak RSS median, GB |
| --- | ---: | ---: | ---: | ---: |
| `read_dta()` | 0.7560 | 0.754 to 0.771 | 5.4230 | 5.231 |
| `read_arrow()` | 0.5610 | 0.557 to 0.585 | 4.5850 | 10.274 |
| haven | 488.2040 | 413.645 to 529.616 | Unavailable | 35.107 |
| Stata `use` | 0.5015 | 0.468 to 0.503 | Unavailable | 5.256 |

The preceding dtatools wall medians were 0.8195 and 0.5980 seconds. These decrease
by 7.7% and 6.2%; CPU time and peak memory are effectively unchanged. Stata's
median remains faster than either reader. Arrow takes 25.8% less wall
time than DTA while using about twice its peak memory. These large-file timings
do not imply improved decoder scaling; the native read architecture is unchanged.

[Every current observation](india-10x-observations.csv),
[comparator observations](india-retained-observations.csv), and
[comparison](india-comparison.csv).

## Source and validation

Baseline source is `d2012d89`; measured candidate source is `49e0145f`. The host
is the same Apple M4 Max with 16 CPUs and 128 GiB RAM, macOS 26.6.2, R 4.6.1,
and dtatools 0.9.0. Existing libraries and Stata installation are unchanged.
Measurements ran sequentially, without concurrent builds or tests. Each phase
checks source, installed package files, workers and inputs before and after
execution. [Provenance](provenance.json) records their identities without
private survey paths or values. Later documentation and test-hardening changes
do not change the measured reader implementation.

Input-source tests cover first-call namespace loading, legacy headers, implicit
extensions, compressed DTA and Arrow content, Unicode and symlink paths,
caller ownership, malformed files and cleanup after errors or interrupts.
The repository Haven conformance suite also covers raw data, connections,
compression with renamed suffixes, and loopback URLs.
