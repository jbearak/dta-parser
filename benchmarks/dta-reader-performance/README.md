# Applying Arrow's batch filling to the DTA reader

This report retains the original batching and automatic-thread experiments.
The later [adaptive-default results](../reader-refresh/results-2026-09-12-defaults/README.md)
record the production policy and its latest benchmark refresh.

## Original automatic-thread results

The final reader changes also remove the fixed eight-worker cap from
`threads = 0` in `read_dta()` and `read_arrow()`. Automatic mode uses CPUs
available to the process, limited by useful work. Small selections remain
serial. Explicit positive limits and the `dtatools.threads` option continue
to override automatic mode. The 8 MiB buffer is unchanged.

A full dtatools-only rerun measured commit
`92020d4d3d0457ac7191e929a6b1736e3571b884` on the same machine and inputs.
The India results below use the original four-tool worker protocol, with ten
fresh reads per dtatools reader. Haven and Stata retain their existing ten-run
observations; their benchmarks were not rerun.

| Reader | Earlier median | Current median | Current median peak RSS |
| --- | ---: | ---: | ---: |
| `read_dta()` | 1.8465 s | 0.821 s | 5.236 GB |
| `read_arrow()` | 0.6945 s | 0.5995 s | 10.280 GB |
| haven, retained | 488.204 s | 488.204 s | 35.107 GB |
| Stata native `use`, retained | 0.5015 s | 0.5015 s | 5.256 GB |

DTA read time fell 55.5% and Arrow 13.7%, with peak RSS effectively unchanged.
DTA's new range was 0.816 to 0.829 seconds; Arrow's was 0.595 to 0.605.
Stata remains the fastest full reader in these comparisons. The full corpus
rerun completed all 1,812 comparable files with matching dimensions. DHS total
time fell from 79.494 to 69.748 seconds, MICS from 62.108 to 60.532, and NSFG
from 20.889 to 19.800. The [documentation PR](https://github.com/jbearak/dta-parser/pull/225)
contains the full corpus, warm-read, memory and projection report.

More workers did not help India's 100-column projection. Its automatic-mode
median increased from 0.248 to 0.263 seconds. A matched control on the same
new code measured 0.250 seconds at eight workers and 0.262 in automatic mode.
A subsequent sweep measured ten reads per selection method at each limit:

| Workers | `any_of()` median | `all_of()` median |
| ---: | ---: | ---: |
| 1 | 0.422 s | 0.423 s |
| 2 | 0.235 s | 0.234 s |
| 4 | 0.236 s | 0.2355 s |
| 8 | 0.250 s | 0.2495 s |
| 12 | 0.258 s | 0.257 s |
| 16 | 0.262 s | 0.2625 s |

The coordinator still reads full row blocks for this projection. It overlaps
input reading with decoding, and dispatches each block to every worker and
collects their acknowledgements. With far fewer selected values, decoding can
keep up with input reading at a smaller worker count. Further decoding gains
then need not shorten the read, while coordination increases. Shared cache
and memory traffic may contribute too. This machine has 12 performance cores
and four efficiency cores, which may also limit scaling; the sweep does not
separately measure these causes or pin threads to cores.

Keep automatic use of available CPUs as the default, and document explicit
limits for workloads that benefit. On this machine, `threads = 2L` was best
for the narrow projection. The full-file tuning below benefited through
twelve workers, with little further gain at sixteen. Automatic mode exposes
available CPU capacity; it does not predict the fastest count for every read.

All requested conformance suites were rerun. All 280 Rust core tests and 21
R bridge tests passed, as did clippy, 22 immutable TypeScript fixtures with
32,085 cell comparisons, ten deterministic native gates, and the full R
package tests and examples. R CMD check completed with three warnings about
zstd's macOS target, vendored Makefiles and Rust's `_abort` symbol, plus two
notes. Haven conformance passed with no skips, including the URL input test;
labelled and haven-helper interoperability also passed. All GitHub test lanes
passed at the measured source commit, including the six native R lanes.
The native test manifest now records the added parallel compact-byte R test
and the updated test-file hash.

- [India observations](results-2026-09-12-auto/india-10x-observations.csv), [summary](results-2026-09-12-auto/india-10x-summary.csv), [retained comparison](results-2026-09-12-auto/india-comparison.csv) and [provenance](results-2026-09-12-auto/india-10x-provenance.json)
- [Eight versus automatic summary](results-2026-09-12-auto/projection-threads-summary.csv), [observations](results-2026-09-12-auto/projection-threads-observations.csv) and [provenance](results-2026-09-12-auto/projection-threads-provenance.json)
- [Projection thread sweep](results-2026-09-12-auto/projection-thread-sweep-summary.csv), [observations](results-2026-09-12-auto/projection-thread-sweep-observations.csv), [provenance](results-2026-09-12-auto/projection-thread-sweep-provenance.json) and [hardware/source context](results-2026-09-12-auto/projection-control-context.json)
- [Conformance record](results-2026-09-12-auto/validation.json)

The projection controls warm each configuration, reverse order on alternate
rounds and run GC before timed calls. All configurations produced the same
full data signature, `724115:100:c26c3f60ffc3eaf0`, outside timing. Input,
worker and installation hashes matched before and after. The
[reader-refresh driver in PR #225](https://github.com/jbearak/dta-parser/blob/codex/refresh-reader-benchmarks/benchmarks/reader-refresh/projection-threads.R)
reproduces both controls. The current India trials exclude startup but include
first-call setup, without inserting an explicit GC before the timed call.
They use a different worker protocol from the batching experiment below.

## Batch filling isolated at eight workers

A compact-byte batch fill cut the India survey's median `read_dta()` time
from **1.826 to 0.895 seconds (51.0%)**, with peak RSS unchanged at about
**5.23 GB**. This comparison uses ten fresh processes per configuration on
the same input and machine. The final candidate has no profiling probes or
experimental environment switches.

| Input | Current reader | Batch fill | Read-time reduction | Current / batch peak RSS |
| --- | ---: | ---: | ---: | ---: |
| India, 5.2 GB, 5,972 columns | 1.826 s | 0.895 s | 51.0% | 5.230 / 5.231 GB |
| Synthetic 100 MB, 40 columns | 0.088 s | 0.087 s | 1.1%; effectively unchanged at this timer resolution | 0.322 / 0.322 GB |
| Synthetic 1 GB, 40 columns | 0.260 s | 0.251 s | 3.5% | 0.706 / 0.706 GB |

All entries are medians; percentages use unrounded times. India's ranges were
1.790 to 1.849 seconds before and 0.888 to 0.899 after. Both columns in the
table use `threads = 0`, which then selected eight workers. The separate
explicit `threads = 16` trials measured the batch candidate at 0.800 seconds
for India, with a range of 0.797 to 0.812, 0.082 seconds for synthetic 100 MB
and 0.2405 seconds for synthetic 1 GB. All three explicit-16 configurations
have ten observations in the [final summary](results-2026-09-12/final-summary.csv).
The subsequent automatic-thread update removes that limit from both readers;
`threads = 0` uses available CPUs, subject to selection size and useful work.

Recommend shipping the batch fill with the 8 MiB buffer and automatic use of
available CPUs. Users can limit workers through the `threads` argument or the
`dtatools.threads` option. The synthetic results show why the batch change is a
workload-dependent improvement, not a general twofold speed claim. The tables
above isolate batching at the old eight-worker default; the 16-worker results
showed further gains on all three inputs on this machine.

## What transfers from Arrow

India contains 5,518 byte, 367 int, 76 long, two double and nine string
columns. Its byte columns hold **3,995,666,570 values**. Previously, every one
of those byte values passed through output-column dispatch, storage-kind and
row-bound checks, and a missing-counter update.

Arrow's compact-column filler chooses the output kind before its value loop
and accumulates missing counts locally. The DTA change applies that pattern:
validate the complete source and destination ranges once, gather the strided
byte values directly into the compact R backing, then update the column's
missing count once per batch. It uses the existing format-specific missing
classifier and preserves the raw byte representation.

This is an optional batch method on `DtaColumnSink`; the default declines it.
The R compact-byte sink implements it. Other storage types and consumers keep
the existing callbacks. The serial path retains its existing interruption
checks. Parallel workers still operate only on owned native storage, with
coordinator cancellation and bounded 8 MiB row blocks as before.

The initial phase measurements identified decoding as the main cost:

| First read in a diagnostic process | Scalar DTA | Batch DTA | Arrow |
| --- | ---: | ---: | ---: |
| Allocate output | 0.199 s | 0.194 s | 0.197 s, including labels |
| Read and decode DTA rows | 1.601 s | 0.564 s | — |
| Read Arrow buffers / fill output | — | — | 0.167 / 0.239 s |
| DTA labels and finish / Arrow finalization | 0.033 s | 0.033 s | 0.008 s |

These probes support the mechanism; they are not the clean-build benchmark.
They omit some R wrapper work, and the stages are not identical across formats.
The logs retain the first and two subsequent reads. Initial allocation costs
were similar, while batching substantially reduced DTA's decode phase.

Some format differences remain. DTA stores rows, so R's column vectors still
need a strided gather. Arrow already stores contiguous columns. Both readers
already use compact numeric backing, and both build deferred strings through
the same `RStringData` builder; Arrow does not reuse an on-disk R dictionary.
The batch fill therefore closes much of the gap without making the two input
layouts equivalent.

## Alternatives measured

The screening round used three fresh processes per configuration, in a
seeded shuffled order, with an instrumented build and the original stock
installation:

| Configuration | India median |
| --- | ---: |
| Stock installation | 1.809 s |
| Instrumented build, changes disabled | 1.785 s |
| Byte batch only | 0.894 s |
| Contiguous weighted column groups only | 1.870 s |
| Byte batch plus contiguous groups | 0.895 s |

Contiguous groups did not improve the result, so the existing least-loaded
column assignment remains. The instrumented baseline differs slightly from
stock; the final ten-run comparison above uses a clean candidate and a fresh
stock control to avoid attributing that difference to batching.

A second three-run sweep retained batching and changed one setting at a time:

| Worker count, 8 MiB buffer | 2 | 4 | 8 | 12 | 16 |
| --- | ---: | ---: | ---: | ---: | ---: |
| India median seconds | 1.654 | 1.151 | 0.894 | 0.818 | 0.813 |

| Buffer MiB, automatic workers | 1 | 2 | 4 | 8 (control above) | 16 | 32 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| India median seconds | 0.991 | 0.916 | 0.902 | 0.894 | 0.963 | 1.045 |

The existing 8 MiB buffer was best in this sweep. Larger blocks increased
both read time and peak RSS; the 32 MiB variant reached 5.281 GB. Extra
workers helped this wide input, but they are an independent tuning choice.

## Relation to the four-tool comparison

Before any compilation or experimental timing, a separate ten-run India
baseline measured all four tools: current `read_dta()` 1.8465 seconds,
`read_arrow()` 0.6945 seconds, haven 488.204 seconds and Stata `use` 0.5015
seconds. The [complete four-tool report](https://github.com/jbearak/dta-parser/pull/225)
includes ranges and the original observations.

That repeated baseline corrects the earlier single observation: Stata was
faster than Arrow in every trial. The optimized DTA reader still takes longer
than those Arrow and Stata medians, while retaining roughly half Arrow's peak
memory. The four-tool and optimization cohorts use different R worker wrappers;
use the matched 1.826-to-0.8945 comparison to estimate the code change's effect.
The experimental worker explicitly runs a full GC before timing each read.

## Method, validation and reproduction

Measurements were made on September 12, 2026, on the same Apple M4 Max
(16 cores, 128 GB), macOS 26.6.2 and R 4.6.1 installation. Stock dtatools
0.9.0 was built from `cf0c80d72191491d42db51d5882a9d7f9d16194e`, the
direct-dibble merge. The candidate measured in the tables above changed only the compact-byte read
path. Its measured source is retained in commit
`53e388f19707620ad24ce215b3862da7c07c9c47`; subsequent automatic-thread
measurements are recorded separately.
Input data and dependency libraries were retained; Arrow files were not
regenerated. Haven and Stata were each run exactly ten times in the separate
baseline and were not run again for these experiments.

Each final trial used a fresh R process, loaded the designated isolated
package, performed a full GC, then timed one reader call. The result remained
live through exit. `wait4()` measured whole-process peak RSS in decimal GB.
Filesystem caches were warm. Startup is excluded, while first-call reader
setup is included. All 90 final reads ran sequentially: ten rounds across
three inputs and three configurations. Order was reversed on alternating
rounds. The screening and tuning rounds each used three observations per
configuration. All timed trials are retained, including variants that did not
improve performance. No compilation or other benchmark ran concurrently.

Input, installation and worker hashes matched before and after each phase.
The final runner also bound its own source and plan. Separate untimed
qualification processes produced identical full data signatures for stock,
batch-default and batch-16 on all three inputs. India's signature was
`724115:5972:e404e6f1cf51f55a`. Signature computation is excluded from the
reported timing and RSS measurements. The historical runner did not enforce
qualification before timing, and the retained records do not establish that
order. The current reproduction runner requires it. Complete separate
signature records for every screening and tuning variant were not retained.

The batch kernel passes exhaustive byte-pattern checks across legacy and
modern missing layouts, strided source ranges, output guard bytes, invalid
ranges and accumulated missing counts. The complete Rust core and R bridge
tests pass, as do the R `read-dta`, `reader-dibble` and `owned-reads` suites,
including a serial/parallel/eager comparison for missing values and row
windows. Rust clippy and formatting checks pass.

- [Final observations](results-2026-09-12/final-observations.csv) and [summary](results-2026-09-12/final-summary.csv)
- [Screening observations](results-2026-09-12/screen-observations.csv) and [summary](results-2026-09-12/screen-summary.csv)
- [Tuning observations](results-2026-09-12/tuning-observations.csv) and [summary](results-2026-09-12/tuning-summary.csv)
- [Input, source and installation provenance](results-2026-09-12/provenance.json)
- [Historical baseline metadata](results-2026-09-12/baseline.md) and [execution manifest](results-2026-09-12/execution-manifest.json), recovered from retained records without rerunning measurements
- [Full data signatures](results-2026-09-12/signatures.json)
- Diagnostic phase logs: [scalar DTA](results-2026-09-12/profile-dta.log), [batch DTA](results-2026-09-12/profile-bulk.log), [Arrow](results-2026-09-12/profile-arrow.log)
- [Initial hypotheses](INVESTIGATION.md) and [isolated debug patch](debug/README.md)

To reproduce, install the base and candidate into separate R libraries.
Copy the [plan template](results-2026-09-12/final-plan-template.json) and
replace its `${...}` strings with actual library and input paths; the runner
does not expand environment variables. Then run from the repository root:

```sh
python3 benchmarks/dta-reader-performance/run.py /tmp/reader-plan.json /tmp/reader-results
```

The current runner requires a variant named `stock`. It first reads every
case with every variant in separate qualification processes and compares full
data signatures to stock. Only after all signatures and file bindings match
does it start timed processes. Qualification clocks and RSS never enter the
observation table. Timed calls still check dimensions and reject signature
output. The runner clears inherited `DTA_READ_PERF_*` and
`DTATOOLS_EXPERIMENT_*` flags, then applies explicit variant flags; it reserves
the library path and signature switch for its own controls.

Each new output directory contains `baseline.md`, `run-metadata.json`, the
plan, before/after file bindings, child logs and `jobs.jsonl` with execution
order, exact child commands and exit codes. A failed qualification leaves a
failure record and starts no timed processes. The historical tuning plan did
not contain stock; add a stock control when reproducing it with this runner.
The historical runner remains available at the measured source commit above.
Its hash in the historical provenance describes those old measurements and
has not been replaced with the current runner's hash.

The runner's sequencing and failure checks use a small fake executable:

```sh
python3 -m unittest discover -s benchmarks/dta-reader-performance -p 'test_*.py' -v
```

The original India input is private. The synthetic inputs are the existing
Stata-first-save fixtures identified by SHA-256 in the provenance file.
The debug patch retains the discarded variants and phase probes solely for
reproduction in a separate checkout; production reader source contains none
of their switches or logging.
