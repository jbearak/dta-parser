# Balanced warm reader benchmarks — September 12, 2026

This follow-up balances reader order across six cohorts. It replaces the earlier
fixed-order warm table in the R README. The reader implementation is unchanged;
corpus, fresh-process India, projection and memory measurements remain in the
[complete adaptive-default report](../results-2026-09-12-defaults/README.md).
Haven and Stata were not run. Their retained measurements are unchanged.

## Method and source

- Measurement checkout: `db09041b61f188a3a05b6c3e618df3c968b1d3a9`.
- Isolated installation built from `af0dd7ce77ba079e6416d6498cbc8e00c44ca97a`;
  its package tree matches the measurement checkout. Production R and Rust
  reader sources are identical to the preceding adaptive-default measurements.
  The intervening package change strengthens missing-value conformance coverage.
- Same Apple M4 Max, 16 CPUs, 128 GiB RAM, macOS 26.6.2, R 4.6.1 and
  dtatools 0.9.0. The retained DTA and Arrow input hashes match the earlier run.
- All three DTA/Arrow equality checks finish before any timed warm worker.
  Values, names and shared metadata match. The older Arrow files omit
  value-label names, declared string widths and some variable notes; those
  known differences are excluded from qualification.
- Each case uses all six permutations of DTA, verified Arrow and unverified
  Arrow. Each method occupies each position twice, and each pair runs in both
  orders equally often. Case order rotates across cohorts.
- Each of 54 worker processes performs one untimed warmup, then 11 timed reads
  per synthetic input or five for India, with full GC between reads. That gives
  66 observations per synthetic case/method and 30 per India method: 486 total.
- Read-call elapsed time and user-plus-system CPU cover the same interval.
  CPU is summed across threads. Reported medians pool individual read calls;
  per-cohort summaries remain available. R clock values have millisecond precision.
- No builds, tests or other benchmarks ran concurrently. Source, installed
  package, worker and input bindings matched before and after the run.
  Subsequent README edits do not alter the measured reader sources.

## Pooled results

| Input | Reader | Reads | Wall median, s | Wall range, s | CPU median, s |
| --- | --- | ---: | ---: | ---: | ---: |
| Synthetic 100 MB, 231,956 × 40 | read_dta | 66 | 0.0410 | 0.040–0.044 | 0.131 |
| Synthetic 100 MB, 231,956 × 40 | read_arrow_verify | 66 | 0.0230 | 0.022–0.031 | 0.074 |
| Synthetic 100 MB, 231,956 × 40 | read_arrow_noverify | 66 | 0.0230 | 0.021–0.027 | 0.071 |
| Synthetic 1 GB, 2,320,123 × 40 | read_dta | 66 | 0.1590 | 0.155–0.163 | 0.775 |
| Synthetic 1 GB, 2,320,123 × 40 | read_arrow_verify | 66 | 0.0730 | 0.070–0.082 | 0.429 |
| Synthetic 1 GB, 2,320,123 × 40 | read_arrow_noverify | 66 | 0.0700 | 0.068–0.081 | 0.400 |
| India, 724,115 × 5,972 | read_dta | 30 | 0.5435 | 0.515–0.596 | 4.803 |
| India, 724,115 × 5,972 | read_arrow_verify | 30 | 0.3120 | 0.291–0.385 | 3.213 |
| India, 724,115 × 5,972 | read_arrow_noverify | 30 | 0.3020 | 0.281–0.380 | 3.096 |

India DTA has a 0.5435-second wall median and verified Arrow 0.3120 seconds,
compared with 0.540 and 0.302 seconds in the earlier fixed-order cohort.
The inputs and reader code are unchanged, and the observed ranges overlap.
This is a measurement-order check; it does not establish a code performance
change. Arrow remains faster for these repeated full reads.

Without checksum verification, India Arrow has a 0.3020-second median:
3.2% less wall time than verified Arrow, with CPU falling from 3.213 to
3.096 seconds. Keep verification enabled by default to retain corruption
detection. This saving does not change the recommendation.

## India by cohort

Order uses D for DTA, V for verified Arrow and U for unverified Arrow.
Each cell is the median of five reads in one process. These expose variation
across the six orders; they are not independent estimates of a code change.

| Cohort | Reader order | D wall, s | V wall, s | U wall, s |
| --- | --- | ---: | ---: | ---: |
| 1 | D, V, U | 0.536 | 0.310 | 0.304 |
| 2 | D, U, V | 0.541 | 0.312 | 0.298 |
| 3 | V, D, U | 0.543 | 0.312 | 0.306 |
| 4 | V, U, D | 0.548 | 0.308 | 0.300 |
| 5 | U, D, V | 0.538 | 0.306 | 0.302 |
| 6 | U, V, D | 0.570 | 0.314 | 0.301 |

Warm repeated-read process peaks are not fresh-read memory estimates.
The [ten-read fresh India comparison](../results-2026-09-12-defaults/README.md#india-ten-fresh-processes-per-reader)
remains 0.8195 seconds and 5.236 GB peak RSS for DTA, and 0.5980 seconds and
10.279 GB for verified Arrow. The retained Stata `use` median is 0.5015 seconds.
Do not compare the warm table above directly with that fresh-process protocol.

## Evidence and validation

[All 486 observations with actual execution order](warm-read-observations.csv),
[pooled wall/CPU summaries](warm-read-summary.csv),
[all 54 cohort summaries](warm-cohort-summary.csv),
[input identities](read-inputs.csv), and [source/installation/CSV provenance](warm-provenance.json).
The private attempt history records 64 successful children and no failures;
only the 54 balanced warm workers contribute to this table. The other children
are three equality qualifications, three fresh spot checks and four projections.

Full conformance passed on `af0dd7ce` after expanding all numeric missing-code
coverage. R CMD check retained the same three warnings and two notes described
in the complete report. The feature-enabled compact-output Rust library test
run passed all 123 tests. Benchmark validation passed 20 refresh-driver tests,
ten experiment-runner tests and three installer-boundary tests, including
optimized-Python checks. The reader benchmark verification and feature-enabled
Rust tests now run in CI. See the [driver instructions](../README.md) to reproduce
the balanced cohort without rerunning the corpus or either comparator.
