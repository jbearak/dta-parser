# Reader benchmarks with adaptive defaults — September 12, 2026

This run measures the production defaults: serial compact-byte batching and
workload-aware automatic worker selection. No experimental flag is required.
The recommendation is to ship these defaults and keep the 8 MiB buffer. The
clearest benefit is the India 100-column projection: automatic mode uses 10.8%
less wall time and 33.5% less CPU time than an explicit 16-worker limit in the
matched control. Full India reads and their peak memory are effectively
unchanged from the preceding available-CPU build.

The tiling and row-task experiments remain in their separate worktrees.
They are not part of this source or these measurements.

## Source and protocol

- Package source and full local validation: `03e054daac82806f01429c816fbb674b3b631d89`.
- Benchmark drivers and measurement checkout: `81e96101` (identical package tree).
- Host: Apple M4 Max, 16 CPUs (12 performance, four efficiency), 128 GiB RAM;
  macOS 26.6.2, R 4.6.1, dtatools 0.9.0.
- Only dtatools readers were timed. Haven and Stata measurements retain their
  original dates, inputs and values; neither comparator was rerun. The user
  confirmed the same machine, OS, libraries and Stata installation.
- Read-call wall time and user/system CPU clocks cover the same interval.
  CPU is summed across threads and can exceed wall time. CPU medians summarize
  each call's user-plus-system total; separately reported component medians
  need not sum to the median total. Comparator CPU values were not recorded.
- Fresh peak RSS is the child's whole-process high-water mark, including the
  runtime and retained result. Whole-process CPU is recorded separately from
  read-call CPU. Warm repeated-read process peaks are not presented as fresh RSS.
- The isolated installation, source package tree, workers and retained inputs
  were bound before and after each phase. Builds, tests and other benchmark
  phases did not run concurrently with timed reads. Later README/report edits
  do not change the measured reader implementation.

See the [driver instructions](../README.md) for commands and input requirements.
Private corpus paths and values stay outside the public report.

## India: ten fresh processes per reader

The input is the 5.2 GB India 2021 DHS women's file: 724,115 rows and 5,972
columns. Arrow reads use its retained 5.6 GB conversion, with verification on.
Each read uses a fresh process and a warm filesystem cache, without an added
pre-read GC or warmup. Startup is outside the read clock; first-call work inside
the reader is included. DTA/Arrow order alternates across ten rounds. The
retained September 12 four-tool baseline rotated all four tools.

| Reader | Wall median, s | Wall range, s | CPU median, s | Peak RSS median, GB |
| --- | ---: | ---: | ---: | ---: |
| `read_dta()` | 0.8195 | 0.816–0.826 | 5.4335 | 5.236 |
| `read_arrow()` | 0.5980 | 0.596–0.603 | 4.5705 | 10.279 |
| haven, retained | 488.2040 | 413.645–529.616 | Unavailable | 35.107 |
| Stata `use`, retained | 0.5015 | 0.468–0.503 | Unavailable | 5.256 |

The preceding dtatools medians were 0.8210 and 0.5995 seconds. Differences of
1.5 milliseconds do not establish an improvement. Arrow takes 27.0% less wall
time and 15.9% less CPU time than DTA here, using 1.96 times its peak RSS.
Stata remains fastest: DTA takes 1.63 times its retained median and Arrow 1.19
times. Use Arrow for repeated full reads when its additional memory fits;
use DTA to read the original file with the smaller peak.

[Current observations](india-10x-observations.csv),
[retained comparator observations](india-retained-observations.csv),
[comparison](india-comparison.csv), and [bindings](india-10x-provenance.json).

## Survey corpus

One current read in a fresh R process was attempted for each of 1,823 inventory
entries. All 1,812 historically comparable files still succeed with identical
dimensions. The eleven excluded files remain outside the totals. Two current
read errors are on files that all three archived readers also rejected.
Comparator records were copied unchanged and checked against the archived data.
Corpus input sizes and modification times match the original inventory before
and after reading. Times sum read calls; RSS is the maximum single-file peak.

| Corpus | Files | Input GB | Dtatools wall, s | Dtatools CPU, s | Prior dtatools wall, s | Retained haven wall, s | Retained Stata wall, s | Dtatools max RSS, GB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| DHS | 641 | 46.903 | 69.286 | 109.417 | 69.748 | 2727.051 | 68.806 | 5.237 |
| MICS | 949 | 3.690 | 60.056 | 64.893 | 60.532 | 216.732 | 1.155 | 0.231 |
| NSFG | 222 | 5.772 | 19.880 | 25.053 | 19.800 | 234.588 | 0.885 | 0.559 |

The changes from the preceding available-CPU run are small: DHS is 0.462 seconds
lower, MICS 0.476 lower, and NSFG 0.080 higher. Against retained haven totals,
DHS is 39.4 times faster, MICS 3.6 times and NSFG 11.8 times. Dtatools is faster
on 1,459 comparison files, tied on ten and slower on 343; it is faster on all
641 DHS files and on 1,435 of the 1,534 files larger than 1 MB. These are not
claims that every dataset or corpus improves. Against the older August dtatools
results, MICS remains slower than 29.3 seconds and NSFG slower than 19.1 seconds.

[Per-release totals and peak memory for all tools](corpus-summary.csv),
[file-count statistics](corpus-statistics.json), and [provenance](provenance.json).
Haven/Stata corpus measurements date from August 24.


## Warm repeated DTA/Arrow reads

The original protocol is preserved: one warmup, then 11 measured reads per
synthetic file and five for India, with full GC between reads. DTA and Arrow
values, names and shared metadata match before timing. The retained Arrow files
omit value-label names, declared string widths and some variable notes; those
known metadata differences are excluded from the equality check. Verification
remains enabled by default.

| Input | Reader | Wall median, s | Wall range, s | CPU median, s |
| --- | ---: | ---: | ---: | ---: |
| Synthetic 100 MB, 231,956 × 40 | read_dta | 0.041 | 0.040–0.045 | 0.132 |
| Synthetic 100 MB, 231,956 × 40 | read_arrow_verify | 0.023 | 0.022–0.027 | 0.075 |
| Synthetic 100 MB, 231,956 × 40 | read_arrow_noverify | 0.022 | 0.021–0.024 | 0.070 |
| Synthetic 1 GB, 2,320,123 × 40 | read_dta | 0.160 | 0.156–0.162 | 0.778 |
| Synthetic 1 GB, 2,320,123 × 40 | read_arrow_verify | 0.073 | 0.072–0.080 | 0.429 |
| Synthetic 1 GB, 2,320,123 × 40 | read_arrow_noverify | 0.070 | 0.068–0.080 | 0.394 |
| India, 724,115 × 5,972 | read_dta | 0.540 | 0.515–0.571 | 4.761 |
| India, 724,115 × 5,972 | read_arrow_verify | 0.302 | 0.291–0.340 | 3.182 |
| India, 724,115 × 5,972 | read_arrow_noverify | 0.301 | 0.293–0.330 | 3.120 |

The small checksum-off wall-time differences do not justify changing the
verification default. Keep checksums enabled. These warm process medians are
separate from the fresh-process India comparison; their broader ranges overlap
the previous warm results and do not establish a new full-read gain.

[Every warm observation](warm-read-observations.csv),
[summary including CPU components](warm-read-summary.csv), and
[input identities](read-inputs.csv).


## Projection and thread control

The main projection rerun uses the saved fixtures and 11 reads per selection
method after warmups. Synthetic cases return ten columns; India returns 100.
Stata retains its August 28 medians. Its direct projected `use` requires known-
present names; it does not handle absent union names like `any_of()`.

| Input | Any-of wall / CPU, s | All-of wall / CPU, s | Stata projected use, s | Stata load/inspect/keep, s |
| --- | ---: | ---: | ---: | ---: |
| tall | 0.014 / 0.033 | 0.014 / 0.033 | 0.028 | 0.016 |
| wide | 0.013 / 0.013 | 0.013 / 0.013 | 0.015 | 0.017 |
| tall-wide | 0.024 / 0.036 | 0.024 / 0.035 | 0.041 | 0.039 |
| india-2021-wm | 0.235 / 0.343 | 0.235 / 0.343 | 0.482 | 0.552 |

India's automatic `any_of()` median falls from 0.263 to 0.235 seconds, with
0.343 seconds of CPU time. [All projection observations](projection-observations.csv)
and [summaries/ranges](projection-summary.csv) retain both selection methods.


The separate control runs ten reads for each thread limit and selection method,
with matching full data signatures before timing, warmups, GC before each read,
and reversed configuration order on alternating rounds. It uses the same India
100-column selection, including its string column, and adds automatic mode to
the existing explicit-thread sweep.

| Requested threads | `any_of()` wall, s | `any_of()` CPU, s | `all_of()` wall, s | `all_of()` CPU, s |
| --- | ---: | ---: | ---: | ---: |
| 1 | 0.3050 | 0.3060 | 0.3050 | 0.3050 |
| 2 | 0.2360 | 0.3455 | 0.2360 | 0.3450 |
| 4 | 0.2370 | 0.3605 | 0.2370 | 0.3590 |
| 8 | 0.2520 | 0.4440 | 0.2520 | 0.4435 |
| 12 | 0.2600 | 0.4940 | 0.2590 | 0.4950 |
| 16 | 0.2645 | 0.5185 | 0.2650 | 0.5205 |
| 0 (automatic) | 0.2360 | 0.3450 | 0.2365 | 0.3475 |

Automatic mode matches two workers on this workload. Compared with eight
workers it uses 6.3% less wall time and 22.3% less CPU; compared with sixteen it
uses 10.8% less wall time and 33.5% less CPU. Both selection methods improve in
every matched round against sixteen. Serial mode uses still less CPU but takes
more wall time. Automatic mode balances these two costs; `threads = 1` remains
available when minimizing CPU is the priority.

The reader still scans full row blocks for a projection. Once reading those
blocks limits throughput, extra decoder workers add dispatch and synchronization
work. The policy estimates selected decode work per buffer and across the row
window. It can reduce workers for narrow projections while leaving a large
full read at the available CPU count. Explicit positive limits retain their
existing behavior. This is a heuristic tested on this host, not a guarantee
that automatic mode is optimal on every machine or dataset.

[All control observations](projection-control-observations.csv),
[summary](projection-control-summary.csv), [bindings](projection-control-provenance.json),
and [signature/session evidence](projection-worker-provenance.json).

## Retained direct-dibble fixtures

All 15 input hashes match the original fixture record, and each current snapshot
matches its retained candidate snapshot before timing. The original protocol
is preserved: three processes per input; two warmups; calibration to 150 ms;
seven measured batches per process; and three separate fresh memory processes
with the original pre-read GC. Timing rows below are normalized per-read
medians over 21 batches. RSS comes from the three separate memory processes.

| Fixture / format | Wall median, ms | CPU median, ms | Fresh peak RSS, MB |
| --- | ---: | ---: | ---: |
| double-small-arrow | 0.229 | 0.229 | 125.5 |
| double-small-dta | 0.326 | 0.326 | 125.2 |
| double-tall-arrow | 7.594 | 17.219 | 189.5 |
| double-tall-dta | 9.094 | 22.344 | 173.4 |
| double-wide-arrow | 7.750 | 21.250 | 143.9 |
| double-wide-dta | 9.812 | 14.562 | 142.4 |
| mixed-arrow | 2.203 | 6.359 | 136.6 |
| mixed-dta | 2.766 | 6.359 | 134.5 |
| ordinary-arrow-arrow | 8.406 | 13.375 | 139.7 |
| strL-arrow | 4.656 | 16.969 | 199.0 |
| strL-dta | 10.125 | 10.125 | 144.2 |
| string-high-arrow | 14.500 | 73.500 | 290.6 |
| string-high-dta | 20.625 | 96.750 | 289.3 |
| string-low-arrow | 2.844 | 14.016 | 141.5 |
| string-low-dta | 3.359 | 11.953 | 134.4 |

Against the retained September 11 candidate, the largest median increases are
3.3% for double-wide Arrow and 1.5% for ordinary Arrow; double-wide DTA is 0.3%
higher. Mixed Arrow increases 1.1% and strL DTA 0.6%; other medians are
unchanged or lower. These small historical differences do not isolate the adaptive policy:
the earlier candidate also predates the available-CPU change. Fresh peaks are
close to their retained values. The matched thread control above provides the
stronger evidence for this policy.

## Supplemental reader and metadata coverage

The synthetic full/eight-column cases use seven warm reads on the retained
Stata-first-save files. The older August 24 synthetic comparator matrix used
222,656/2,227,111 rows; its original input bytes were not available. Current
fixtures contain 231,956/2,320,123 rows. The old matrix remains dated, and its
haven/Stata timings are not attached to these different files.

The checked modern, wide, strL and legacy microcases average 100 calls after GC.
Metadata-only rows use `n_max = 0` and measure no observation decoding. These
measurements cover the remaining reader shapes, with their own protocols.

| Supplemental workload | Wall per read, ms | CPU per read, ms |
| --- | ---: | ---: |
| metadata-india | 91.290 | 91.270 |
| micro-legacy-full | 0.740 | 0.730 |
| micro-legacy-metadata-only | 0.740 | 0.730 |
| micro-legacy-window | 0.470 | 0.460 |
| micro-modern-all-types-full | 0.780 | 0.780 |
| micro-modern-all-types-metadata-only | 0.780 | 0.770 |
| micro-modern-all-types-window | 0.520 | 0.520 |
| micro-strl-full | 0.770 | 0.760 |
| micro-strl-metadata-only | 0.730 | 0.720 |
| micro-strl-window | 0.520 | 0.530 |
| micro-wide-full | 1.580 | 1.580 |
| micro-wide-metadata-only | 1.580 | 1.570 |
| micro-wide-window | 0.590 | 0.590 |
| synthetic-100mb-full | 42.000 | 136.000 |
| synthetic-100mb-projected-eight | 28.000 | 48.000 |
| synthetic-1gb-full | 150.000 | 781.000 |
| synthetic-1gb-projected-eight | 96.000 | 255.000 |

[Coverage observations](coverage-observations.csv), [summary](coverage-summary.csv),
and [input/oracle bindings](coverage-provenance.json).

## Supplemental fresh memory

Each case has three fresh processes, with no warmup or pre-read GC. These runs
use a configuration wrapper distinct from the ten-read India worker. Compare
verification settings within this wrapper; the unverified India wall time
below is not a matched comparison with the verified ten-read median above.

| Fresh workload | Wall median, s | CPU median, s | Peak RSS median, GB |
| --- | ---: | ---: | ---: |
| india-arrow-noverify | 0.621 | 4.512 | 10.268 |
| projection-india-2021-wm | 0.310 | 0.423 | 0.320 |
| projection-tall | 0.066 | 0.087 | 0.179 |
| projection-tall-wide | 0.077 | 0.088 | 0.169 |
| projection-wide | 0.065 | 0.064 | 0.147 |
| synthetic-100mb-arrow-noverify | 0.070 | 0.134 | 0.414 |
| synthetic-100mb-arrow-verify | 0.070 | 0.137 | 0.410 |
| synthetic-100mb-dta | 0.092 | 0.188 | 0.331 |
| synthetic-1gb-arrow-noverify | 0.164 | 0.637 | 1.704 |
| synthetic-1gb-arrow-verify | 0.168 | 0.673 | 1.704 |
| synthetic-1gb-dta | 0.254 | 0.898 | 0.712 |

[Fresh observations](fresh-observations.csv), [summary](fresh-summary.csv),
and [bindings](fresh-provenance.json).

## Conformance

All local checks passed on the measured package source:

- 22 immutable TypeScript fixtures, 32,085 decoded-cell comparisons; ten native
  deterministic gates plus the canonical fixture oracle.
- 291 Rust core tests, 21 isolated offline R bridge tests, and the separate
  16-case fuzz smoke lane (three tests).
- Complete R package build/check and test suite; repository-only haven,
  labelled and haven-helper interoperability suites.
- 386 TypeScript tests and 32 Python tests; formatting, Clippy and rustdoc with
  warnings denied, crate packaging, offline vendor checks, Rust source-hash
  checks, corpus aggregation tests and generated-documentation checks.

R CMD check completed with three existing warnings (macOS zstd object deployment
target, vendored GNU Makefiles, Rust abort symbol) and two existing notes
(vendored chrono citation and a generated C file without a final newline).
A preliminary toolchain invocation used unsupported Homebrew `cargo +...` syntax;
the complete bridge and core checks passed through `rustup run 1.98.0 cargo`.
Linux/Windows and dependency-version matrix checks are delegated to PR CI.

[Validation commands, outcomes and log hashes](validation.json).
[Completion evidence](completion.json) records all six successful phases and
confirms that only the package README changed after measurement.
