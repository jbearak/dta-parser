# Generation and mutation after correctness review

The correctness-review fixes retained the measured plain and owned double
optimizations. Across 132 dtatools cases, the median of the reviewed-build to
pre-review-build runtime ratios is 1.011. This is a description of this matrix,
not a workload-weighted estimate. The two process pairs give 1.023 and 0.999,
so small changes should not be read as precise causal estimates. The clearest
repeatable cost is `gen()`: its median increase is 7.3%, with 7.4% and 7.1%
in the two process pairs.

| Operation | Cases | Median reviewed runtime divided by pre-review runtime |
| --- | ---: | ---: |
| `gen()` | 12 | 1.073 |
| `replace_values()` | 24 | 1.010 |
| Dibble `:=` | 48 | 1.032 |
| `dplyr::mutate()` on dibbles | 48 | 0.995 |

All 132 reviewed-build cases beat ordinary dplyr, including the upper ends
of their pointwise 95% bootstrap intervals. For 131 cases, the reviewed
runtime is no more than 1.05 times data.table's runtime through the interval's
upper end. The exception is five-column bracket creation on a plain
100-row, 100-column dibble: the ratio is 1.056, with interval 1.043 to 1.082.
This run does not establish universal data.table parity.

Untimed admission checks confirmed that all 124 cases expected to use the
retained whole-operation publication counters did so in each of the four
processes. The other eight cases use the separate literal-scalar replacement
path and correctly record zero in that
counter. The wide plain result-allocation check remains at 1,622,728 bytes
with one native publication, unchanged from the explicit-copy benchmark.

## Scope and sources

The unchanged [benchmark](../validate-plain-grouped.R) covers 100 and 100,000
rows with two and 100 columns for ungrouped operations, plus 10,000 rows and
100 groups at both widths. It includes scalar replacement, `abs(-3)`, `x + 1`,
one-column creation and five-column creation. Dtatools uses dibbles with
canonical plain or owned Stata doubles. Dplyr and data.table use ordinary
plain double columns. The runner explicitly sets
`dtatools.generate_type = "double"` and uses the default allocation setting.
Compact payloads, custom dispatch, projections, arbitrary expressions and
non-default allocation settings are outside this timing matrix.

The pre-review library is the exact library used in the
[grouped explicit-copy report](../grouped-2026-09-29-explicit-copy.md), verified
by its DLL SHA-256. Its recorded build identifier is retained in
[provenance](provenance.json), though that original local build identifier is
not available in this checkout. All 115 R and C implementation hashes in the
[original source manifest](../grouped-2026-09-29-explicit-copy/provenance.json)
match public merge `4a3687cb`. Within those implementation files, immediate
pre-review revision `87cf7680` differs in one C comment only. This hash audit
does not cover Rust or build configuration. The reviewed library is `cbabff67`,
after review PRs 270 through 274. These measurements precede the later
configurable-capacity fix; they
do not claim timings for that fix or for non-default `dtatools.alloccol`.

Four fresh R processes ran in before, after, after, before order, using seeds
261001 through 261004. Each process collected ten observations per condition
and randomized engine order within each condition. The files named
`merged-main` contain the pre-review build; `experiments` contains the reviewed
build. Samples 1 through 10 belong to the first process for each build and
11 through 20 to its second process. Combining the files preserves the
within-process engine pairing.

All 9,120 timed calls passed value, canonical column-attribute, column-order and
applicable input-isolation checks outside timing. Fixture construction,
explicit GC, counters and verification were outside the timer. No builds or
test suites ran concurrently. No timed collection occurred. Independent
`copy_data()` calls were excluded for all engines, as in the
[explicit-copy contract](../../../docs/adr/0044-require-explicit-copies-before-foreign-reference-writes.md).

The environment was macOS ARM64, R 4.6.1 revision 90187, dplyr 1.2.1,
data.table 1.18.6.1, vctrs 0.7.3, rlang 1.3.0, tibble 3.3.1 and bench 1.1.4.
Data.table used one thread. The unchanged analyzer uses seed 20260929 and
10,000 bootstrap resamples. Its intervals are pointwise, not simultaneous
guarantees across 132 cases. Pooling 20 observations from two processes does
not model process-level uncertainty. One machine and two processes per build
limit generalization. Historical speedups against earlier optimization
baselines were not remeasured here.

## Evidence and reproduction

- [All comparisons](comparisons.csv) and [summary](summary.json).
- [Reviewed observations](experiments/raw.csv) and [pre-review observations](merged-main/raw.csv).
- [Reviewed session](experiments/session.txt) and [pre-review session](merged-main/session.txt).
- [Admission checks](admissions.csv), [allocation check](allocation-result.txt)
  and [build identities](provenance.json).
- [Saved bootstrap indices](bootstrap-indices.npz).

Recompute the comparison from the recorded observations:

```sh
python3 benchmarks/r-numeric-performance/analyze-experiments.py \
  benchmarks/r-numeric-performance/review-2026-10-01 /tmp/review-analysis
```

For a new measurement, install the two revisions separately and run
`validate-plain-grouped.R` four times in the order above, with ten samples
per process and the recorded seeds. Preserve engine pairing and offset the
second process's sample IDs by ten before using the analyzer. Use the
[allocation reproducer](../plain-2026-09-29-explicit-copy/check-wide-copy.R)
separately from timing.
