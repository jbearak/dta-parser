# R generation and mutation performance

This page reports public-call timings for creating and replacing variables
on dibbles. It covers `gen()`, `replace_values()`, bracket assignment with
`:=`, and `dplyr::mutate()`. The October 1, 2026 review comparison found that
the correctness fixes preserved the major optimizations, with a repeatable
cost of about 7% for `gen()` and smaller changes elsewhere.

## What was measured

The matrix contains 132 dtatools cases, with 20 observations per build and
case. It includes plain and package-owned Stata doubles, small and large
tables, narrow and wide tables, and grouped and ungrouped creation. The
comparators are ordinary dplyr tibbles and data.tables with plain doubles.
All reported operations run through their public functions.

| Operation | Median runtime change after correctness review |
| --- | ---: |
| `gen()` | 7.3% slower |
| `replace_values()` | 1.0% slower |
| Dibble `:=` | 3.2% slower |
| `dplyr::mutate()` on dibbles | Essentially unchanged |

The median across case-level runtime ratios increased 1.1%. Small differences
varied between the two process pairs, so that figure is not a precise
estimate for an arbitrary workload. The `gen()` increase reproduced in both
pairs. These results compare the optimized build before review with the
reviewed build; they do not measure the full improvement from an older release.

## Comparisons with dplyr and data.table

All 132 measured cases beat ordinary dplyr. In 131 cases, the reviewed runtime
was no more than 5% slower than data.table, including each pointwise 95%
bootstrap interval's upper end. The exception was creating five columns with
`:=` on a plain 100-row, 100-column dibble: 1.056 times data.table's runtime,
with an interval of 1.043 to 1.082. These measurements do not establish
universal data.table parity.

For a plain 100,000-row, 100-column dibble, the reviewed build measured:

| Operation | Dtatools | Relative to dplyr | Relative to data.table |
| --- | ---: | ---: | ---: |
| `gen(y = x + 1)` | 244 microseconds | 0.45 times | 0.95 times |
| `:=` creating `y = x + 1` | 226 microseconds | 0.41 times | 0.88 times |
| `mutate(y = x + 1)` | 168 microseconds | 0.31 times | 0.65 times |
| `:=` creating five `x + 1` columns | 365 microseconds | 0.46 times | 1.01 times |
| `mutate()` creating five `x + 1` columns | 171 microseconds | 0.22 times | 0.47 times |

Smaller ratios mean faster execution. Fixture construction and verification
are excluded; the complete public operation is timed. All observations,
including slower ones, are retained.

## Why the gains survive

The review added checks for dispatch, evaluation order and expression capture.
It did not remove the native arithmetic loops or restore whole-table copying.
Untimed admission checks confirmed that all 124 cases covered by the
whole-operation native publication counters still used those paths.
Eight literal-scalar replacement cases use a separate
path and are not counted as whole-operation publications.

The wide plain `mutate()` allocation check remained at 1.62 MB. An earlier
implementation allocated about 80.8 MB for that same check. Ordinary results
may share unchanged columns while preserving ordinary R and dtatools mutation
isolation. Use `copy_data()` when independence from later foreign by-reference
writes is required. Explicit independent copies are excluded from the timings
for every engine. See the [copying contract](r-mutation-by-reference.md#foreign-reference-writes-require-an-explicit-copy).

## Limits and further detail

These are measurements on one Apple ARM64 machine, with R 4.6.1, dplyr 1.2.1,
data.table 1.18.6.1, vctrs 0.7.3 and rlang 1.3.0. Optimized paths require the
audited runtime and dependency behavior; other configurations use ordinary
execution. The matrix uses default allocation settings and explicitly sets
`dtatools.generate_type = "double"`, with canonical plain or owned double
columns. It does not establish timings for compact columns, arbitrary
expressions, custom classes, S4 methods or non-default allocation settings.

The timings pin reviewed commit `cbabff67`, before the later configurable
allocation-capacity fix. Correctness and native-admission tests for later
changes are not substitutes for a new timing run. The bootstrap intervals
are pointwise and do not capture all process-to-process or machine-to-machine
variation.

The configurable-capacity fix lets supported grouped `mutate()` creation
retain native execution with valid bare integer or double
`dtatools.alloccol` settings. Invalid, attributed, S4 and ALTREP settings
still use ordinary R validation. Regression tests cover exact capacity and
option changes around reservation, but the timings above use the default.

The [October 1 report and reproducible observations](../benchmarks/r-numeric-performance/review-2026-10-01/README.md)
contain the full matrix, build identities, native counters, methods and
uncertainty limits. The earlier
[ungrouped](../benchmarks/r-numeric-performance/plain-2026-09-29-explicit-copy.md)
and [grouped](../benchmarks/r-numeric-performance/grouped-2026-09-29-explicit-copy.md)
reports document the optimization work against its earlier baselines.
