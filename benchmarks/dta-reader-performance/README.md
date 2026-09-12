# Applying Arrow's batch filling to the DTA reader

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
1.790–1.849 seconds before and 0.888–0.899 after. With an explicit
`threads = 16`, the candidate's India median was 0.800 seconds
(0.797–0.812). The default remains automatic, capped at eight workers.

Recommend shipping the batch fill while retaining the current thread and
buffer defaults. The main gain transfers from Arrow's conversion loop and
does not require additional resident memory. The synthetic results show why
this is a workload-dependent improvement, not a general twofold speed claim.
On this machine, users prioritizing India read time can also request 16
threads. That setting needs broader hardware evidence before becoming a
global default.

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
direct-dibble merge. The candidate changes only the compact-byte read path.
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
reported timing and RSS measurements.

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

The original India input is private. The synthetic inputs are the existing
Stata-first-save fixtures identified by SHA-256 in the provenance file.
The debug patch retains the discarded variants and phase probes solely for
reproduction in a separate checkout; production reader source contains none
of their switches or logging.
