# Reader benchmarks after byte batching and automatic threads

The updated `read_dta()` read India in **0.821 seconds**, down from 1.8465
seconds in the earlier ten-run baseline, a 55.5% reduction. `read_arrow()`
fell from 0.6945 to 0.5995 seconds, a 13.7% reduction. Peak memory was
effectively unchanged for both readers.

Only dtatools benchmarks were rerun. Haven and native Stata retain their
recorded observations on the same computer, OS, libraries and Stata version.
The [earlier four-tool report](../results-2026-09-12/india-10x.md) remains the
source for their India results. Stata is still faster than both R readers.

The measured dtatools 0.9.0 build is commit
`92020d4d3d0457ac7191e929a6b1736e3571b884` from
[PR #226](https://github.com/jbearak/dta-parser/pull/226). It includes direct
dibble construction, compact-byte batch filling, and automatic use of available
CPUs. Both readers use their default dibble output. `threads = 0` now uses
the CPUs available to the process, subject to selection size and useful work,
with no fixed eight-worker cap. Small selections still use the serial path.
Positive `threads` values limit workers; `threads = 1` requests serial reading.
The default R argument remains `getOption("dtatools.threads", 0L)` and the
buffer remains 8 MiB.

Measurements were made on September 12, 2026, on an Apple M4 Max with 16 cores
and 128 GB RAM, macOS 26.6.2 and R 4.6.1. Installed dependencies include tibble
3.3.1, vctrs 0.7.3, rlang 1.3.0 and tidyselect 1.2.1. The retained comparators
used haven 2.5.5 and Stata/MP 18. Arrow inputs were kept unchanged.

## India, ten fresh reads per dtatools reader

India 2021 DHS women has 724,115 rows and 5,972 columns. The source DTA is
5.196 GB and the retained uncompressed Arrow conversion is 5.560 GB.

| Reader | Measurement | Median read time | Range | Median peak RSS |
| --- | --- | ---: | ---: | ---: |
| `dtatools::read_dta()` | Current rerun | 0.821 s | 0.816 to 0.829 s | 5.236 GB |
| `dtatools::read_arrow()` | Current rerun | 0.5995 s | 0.595 to 0.605 s | 10.280 GB |
| `haven::read_dta()` | Retained September 12 ten-run baseline | 488.204 s | 413.645 to 529.616 s | 35.107 GB |
| Stata native `use` | Retained September 12 ten-run baseline | 0.5015 s | 0.468 to 0.503 s | 5.256 GB |

Each observation uses a fresh process and a warm filesystem cache. Elapsed
time covers only the reader call, excluding application startup but including
first-call setup. The existing four-tool workers are unchanged. No explicit
full GC was added before the timed call. DTA and Arrow alternate order across
ten rounds; the retained four-tool baseline rotated order across four tools.
All 20 new reads succeeded with the expected dimensions.

Peak RSS is the maximum resident memory of the whole process, including the
runtime, native allocations and result retained through exit. GB means 10^9
bytes. Arrow verification is enabled. Arrow takes 27.0% less read time than
DTA here, at roughly twice the peak RSS. DTA now takes 1.64 times the retained
Stata median, down from 3.68 times before these changes.

The current-versus-earlier dtatools difference includes batching and removal
of the automatic worker cap. The separate
[batch experiment](https://github.com/jbearak/dta-parser/blob/codex/dta-reader-performance/benchmarks/dta-reader-performance/README.md)
isolated the batch change at eight workers and measured a 51.0% India
improvement. Its worker performs a full GC before timing, so its absolute
times belong to a different protocol.

## Full survey corpus

All 1,823 inventoried files were attempted in separate R processes. Dtatools
successfully read 1,821. The same 1,812 files qualify for comparison as in the
original three-reader run, and all still read with matching dimensions. Two
MICS inputs fail to read; nine further files remain excluded because haven
rejected them in the original run. Every file's size and modification time
matched the original inventory before and after the rerun.

Times below are sums over common files. Peak RSS is the largest process peak
within each corpus. Haven and Stata retain their August 24 observations.

| Corpus | Files | Input GB | Current dtatools s | Earlier September 12 dtatools s | Retained haven s | Retained Stata s | dtatools peak RSS GB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| DHS | 641 | 46.903 | 69.748 | 79.494 | 2,727.051 | 68.806 | 5.235 |
| MICS | 949 | 3.690 | 60.532 | 62.108 | 216.732 | 1.155 | 0.232 |
| NSFG | 222 | 5.772 | 19.800 | 20.889 | 234.588 | 0.885 | 0.559 |

These totals are 39.1, 3.6 and 11.8 times faster than retained haven. Stata's
retained total is lower for all three corpora, with DHS now close. Across the
1,812 common files, dtatools was faster than haven on 1,458, tied on five and
slower on 349. For the 1,534 files larger than 1 MB, the counts are 1,434, five
and 95. Dtatools was faster on every DHS file.

Against the initial September 12 refresh, total read time fell by 12.3% for
DHS, 2.5% for MICS and 5.2% for NSFG. The older August dtatools totals were
93.152, 29.341 and 19.130 seconds. MICS and NSFG remain slower than those older
builds, which preceded several reader changes. These historical comparisons
do not isolate a single implementation change. The
[format-level CSV](corpus-summary.csv) retains all corpus and comparator RSS
values as well as read times.

## Warm DTA and Arrow reads

Each method uses its own process, one untimed warmup, then 11 timed synthetic
reads or five timed India reads. Full GC occurs between reads. These medians
are separate from the first-call India comparison above.

| Input | `read_dta()` median, range | Verified `read_arrow()` median, range | Unverified `read_arrow()` median, range |
| --- | ---: | ---: | ---: |
| Synthetic 100 MB, 231,956 by 40 | 0.041 s, 0.040 to 0.045 | 0.023 s, 0.022 to 0.026 | 0.023 s, 0.022 to 0.025 |
| Synthetic 1 GB, 2,320,123 by 40 | 0.159 s, 0.158 to 0.162 | 0.074 s, 0.070 to 0.082 | 0.072 s, 0.070 to 0.081 |
| India, 724,115 by 5,972 | 0.567 s, 0.521 to 0.579 | 0.314 s, 0.292 to 0.387 | 0.304 s, 0.290 to 0.330 |

The earlier September 12 medians were 0.047, 0.193 and 1.547 seconds for DTA,
and 0.024, 0.088 and 0.398 seconds for verified Arrow. Disabling verification
does not show a consistent benefit across inputs. Keep verification enabled.

The retained Arrow files predate preservation of value-label table names,
declared string widths and some variable notes. India's Arrow file lacks notes
on 116 variables returned by the current DTA reader. Untimed qualification
verified matching dimensions, column names and content signatures after
excluding those metadata fields from the comparison. The signatures cover
all values in order, numeric storage types, labels, formats, remaining notes
and characteristics. All three pairs passed. Timed reads use the original
files and default readers; the exclusions apply only to output comparison.

Synthetic inputs are the retained Stata-first-save fixtures. The older
synthetic haven/native Stata matrix used different fixtures with different
row counts, so its times are not attached to these inputs.

## Projected reads

The original worker performs 11 timed reads after warmups on unchanged
projection inputs and name lists. Synthetic cases return ten columns from a
100-name union; India returns 100 columns from a 200-name union. Stata retains
its August 28 medians.

| Input shape | `read_dta(any_of(union))` | `read_dta(all_of(present))` | Stata full `use`, inspect, `keep` | Stata direct projected `use` |
| --- | ---: | ---: | ---: | ---: |
| Tall, 500,000 by 100 | 0.014 s | 0.014 s | 0.016 s | 0.028 s |
| Wide, 50,000 by 1,000 | 0.013 s | 0.013 s | 0.017 s | 0.015 s |
| Tall-wide, 250,000 by 500 | 0.025 s | 0.025 s | 0.039 s | 0.041 s |
| India, 724,115 by 5,972 | 0.263 s | 0.263 s | 0.552 s | 0.482 s |

India's `any_of()` median increased from 0.248 to 0.263 seconds, a 6.0%
regression. Its current range is 0.262 to 0.282 seconds. The new median is
still 52.4% below the retained Stata full-load workflow and 45.4% below direct
Stata projection. Direct Stata projection requires known-present names and
errors on absent names. The synthetic projection medians are unchanged.

### Why more workers slowed the projection

A matched control with the same new reader code measured 0.250 seconds at
eight workers and 0.262 seconds in automatic mode, for both selection methods.
Each setting had ten timed reads. This reproduces the slowdown when changing
only the thread limit, so the extra workers account for it in this control.

A subsequent sweep measured ten reads per method at each explicit limit:

| Workers | `any_of()` median | `all_of()` median |
| ---: | ---: | ---: |
| 1 | 0.422 s | 0.423 s |
| 2 | 0.235 s | 0.234 s |
| 4 | 0.236 s | 0.2355 s |
| 8 | 0.250 s | 0.2495 s |
| 12 | 0.258 s | 0.257 s |
| 16 | 0.262 s | 0.2625 s |

Both controls used one process, one warmup per configuration, GC before each
timed call, and reversed configuration order on alternating rounds. Untimed
full data signatures matched across every configuration. Input, worker and
installed-library hashes also matched before and after. All observations,
including the slower settings, are retained.

The [DTA block reader](https://github.com/jbearak/dta-parser/blob/92020d4d3d0457ac7191e929a6b1736e3571b884/r-package/dtatools/src/dta-tools/src/file.rs#L2050)
uses one coordinator to read full row blocks, even when selecting only 100
columns. It overlaps each input read with decoding the preceding block, then
collects acknowledgements from all workers before dispatching the next block.
The projection decodes far fewer values than a full read, while traversing
the same row payload. Once decoding keeps pace with the coordinator, making
decoding faster need not reduce elapsed time. Each additional worker still
adds dispatch and acknowledgement work for every block.

That makes coordinator throughput and synchronization plausible limits for
this projection. Shared cache and memory traffic can also limit scaling.
The local CPU inventory reports 12 performance cores and four efficiency
cores; unequal core speeds are another possible constraint when work waits
for every worker. These timings do not separately measure those contributions
or pin workers to particular cores.

The full India read behaves differently. The earlier three-read tuning sweep
measured 0.894 seconds at eight workers, 0.818 at twelve and 0.813 at sixteen.
It has enough decoding work to benefit beyond eight, with little further gain
past twelve. There is no single best worker count for both workloads. For
this narrow projection, an explicit `threads = 2L` was fastest in the new sweep.

## Recommendation

Ship compact-byte batching and automatic use of available CPUs. Keep the
8 MiB buffer, which was best in the separate India buffer sweep. Use
`read_dta()` for direct imports and when memory matters; use `read_arrow()`
for repeated full reads when a converted copy is appropriate and its extra
memory fits. Keep Arrow verification enabled. Select only needed columns with
`col_select`; this remains faster than a full India read despite the small
projection regression. Users can tune `threads` for their own workloads or
set `options(dtatools.threads = 8L)` to limit workers across a session.

For the 100-column India projection, use `threads = 2L` if read time is the
priority on this machine. Treat that as a measured workload-specific setting,
not a new global default. Automatic mode now exposes the available CPU
capacity, but it does not estimate the fastest thread count for every query.

These results support a large gain on India's byte-heavy full read. They do
not show a universal improvement from adding threads. Native Stata remains
the fastest full reader in its retained India trials. Conversion time and
metadata requirements also matter when choosing Arrow. The retained India
conversion took 1.367 seconds on August 29 and was not rerun. The experimental
Arrow profile has no cross-version stability promise.

## Conformance rerun

All 280 Rust core tests and 21 R bridge tests passed. Clippy passed with
warnings denied. Fixture conformance passed for 22 immutable TypeScript
fixtures with 32,085 cell comparisons, followed by all ten deterministic
native gates. The current R package was built, checked for its offline Cargo
archive, and checked with its full test suite and examples.

R CMD check completed without test failures, with three warnings and two
notes. The warnings concern zstd's macOS build target, GNU make extensions in
vendored Makefiles and Rust's `_abort` symbol. The notes concern a vendored
CITATION file and a generated C file without a final newline. These are
recorded rather than described as a clean package check.

The haven conformance suite passed, including the local HTTP input test,
with no skips. The labelled and haven-helper interoperability suites also
passed. This final rerun used `NOT_CRAN=true` and allowed the loopback test
server after the sandbox had prevented that test in the first run. Haven was
used for correctness comparisons only; its benchmark was not rerun.
See the [validation record](validation.json) for commands and log hashes.
All GitHub test lanes also passed at the measured reader commit, including
the six native R lanes and package checks on Linux, macOS and Windows.

## Reproduction and records

The [reader-only drivers](../README.md) bind the source commit, package tree,
installed library, workers and inputs before and after each phase. Source
and installed hashes stayed unchanged. Corpus identity uses the original
relative paths, sizes and modification times; the named read and projection
inputs also have SHA-256 hashes. No compilation, conformance tests or other
benchmarks overlapped timed reads. Private survey paths, values and per-file
corpus records remain in ignored local output.

- [India comparison with retained haven and Stata](india-comparison.csv), [new observations](india-10x-observations.csv), [summary](india-10x-summary.csv) and [provenance](india-10x-provenance.json)
- [Corpus summary by format](corpus-summary.csv) and [comparison counts](corpus-statistics.json)
- [Warm-read summary](warm-read-summary.csv) and [observations](warm-read-observations.csv)
- [Projection summary](projection-summary.csv) and [observations](projection-observations.csv)
- [Eight versus automatic summary](projection-threads-summary.csv), [observations](projection-threads-observations.csv), [provenance](projection-threads-provenance.json) and [original worker](projection-threads-worker.R)
- [Thread sweep summary](projection-thread-sweep-summary.csv), [observations](projection-thread-sweep-observations.csv), [provenance](projection-thread-sweep-provenance.json) and [source/library/hardware context](projection-control-context.json)
- [Input sizes and hashes](read-inputs.csv) and [source, installation and worker provenance](provenance.json)

The auxiliary [single-read spot CSV](spot-comparison.csv) contains one fresh
read each for India DTA, India Arrow and NSFG DTA with August 24 comparator
observations. It is retained for continuity with the original corpus report.
Use the ten-run India comparison above for the main four-reader comparison.
