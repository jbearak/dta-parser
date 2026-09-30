# Grouped plain and owned vectors under the explicit-copy contract

All 20 measured grouped cases beat dplyr and take at most 1.05 times data.table's runtime, including each pointwise 95% bootstrap interval's upper end. Median speedups against the updated plain-vector branch range from 24.23 to 111.55 times. All 20 candidate cases have positive native publication counters.

Canonical plain and owned double grouping keys enter the existing grouped paths. Group planning and arithmetic retain ordered private snapshots. Unchanged plain sibling columns may share with the input under the revised contract. The bracket and mutate paths retain their `source + 1` limit and positive integral keys up to INT_MAX; gen retains literal offsets and its existing signed integral-key domain. Missing or fractional keys, custom metadata, unfamiliar ALTREP storage and changed public dependencies use ordinary execution. These measurements cover one- and five-column creation at 10,000 rows and 100 groups. They do not cover grouped replacement or arbitrary expressions.

Every dtatools operation runs on a dibble. Every input column, including grouping keys and untouched siblings, is a canonical plain or owned Stata double vector as indicated. Compact vectors are excluded. Comparators use plain doubles in ordinary tibbles and data.tables.

[ADR 0044](../../docs/adr/0044-require-explicit-copies-before-foreign-reference-writes.md) preserves ordinary R copy-on-modify and isolation under dtatools mutators. Independence from later foreign reference writes requires `copy_data()`. Explicit independent copies are excluded from these timings for all engines. No result is required to share storage, and the operand/key snapshots needed during execution remain protected.

| Inputs | Cases | Beats dplyr at median | At most 5% slower than data.table at median | Both targets through upper 95% bound |
| --- | ---: | ---: | ---: | ---: |
| Plain | 10 | 10 | 10 | 10 |
| Owned | 10 | 10 | 10 | 10 |

The target is no more than 5% slower than data.table. Cases more than 5% faster also meet it; this is different from literal plus/minus 5% equivalence.

## Plain vectors in dibbles

10,000 rows and 100 groups. Times are microseconds. Ratios are candidate divided by comparator; smaller is faster. Both tables have the same operation and shape rows.

| Input columns | Operation | #267 µs | Candidate µs | Speedup | / dplyr | / data.table |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 2 | `gen(y = x + 1, by = g)` | 12629.4 | 321.3 | 39.31× | 0.35× | 0.49× |
| 2 | `:=` creating `y = x + 1`, by `g` | 12651.5 | 332.1 | 38.09× | 0.36× | 0.51× |
| 2 | `mutate(y = x + 1, .by = g)` | 8024.7 | 320.4 | 25.04× | 0.35× | 0.49× |
| 2 | `:=` creating five `x + 1` columns, by `g` | 57332.3 | 628.9 | 91.17× | 0.36× | 0.77× |
| 2 | `mutate()` creating five `x + 1` columns, `.by = g` | 30540.2 | 330.2 | 92.50× | 0.19× | 0.40× |
| 100 | `gen(y = x + 1, by = g)` | 12527.0 | 408.5 | 30.67× | 0.34× | 0.59× |
| 100 | `:=` creating `y = x + 1`, by `g` | 12849.6 | 383.5 | 33.51× | 0.32× | 0.55× |
| 100 | `mutate(y = x + 1, .by = g)` | 11170.9 | 361.6 | 30.90× | 0.30× | 0.52× |
| 100 | `:=` creating five `x + 1` columns, by `g` | 58374.5 | 725.8 | 80.43× | 0.37× | 0.86× |
| 100 | `mutate()` creating five `x + 1` columns, `.by = g` | 42491.8 | 380.9 | 111.55× | 0.20× | 0.45× |

## Owned vectors in dibbles

10,000 rows and 100 groups. Times are microseconds. Ratios are candidate divided by comparator; smaller is faster. Both tables have the same operation and shape rows.

| Input columns | Operation | #267 µs | Candidate µs | Speedup | / dplyr | / data.table |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 2 | `gen(y = x + 1, by = g)` | 12067.8 | 332.0 | 36.35× | 0.31× | 0.49× |
| 2 | `:=` creating `y = x + 1`, by `g` | 12381.7 | 346.9 | 35.69× | 0.33× | 0.51× |
| 2 | `mutate(y = x + 1, .by = g)` | 7839.4 | 323.6 | 24.23× | 0.31× | 0.47× |
| 2 | `:=` creating five `x + 1` columns, by `g` | 56254.2 | 622.1 | 90.43× | 0.35× | 0.74× |
| 2 | `mutate()` creating five `x + 1` columns, `.by = g` | 31223.4 | 343.4 | 90.91× | 0.19× | 0.41× |
| 100 | `gen(y = x + 1, by = g)` | 12274.3 | 400.5 | 30.64× | 0.33× | 0.58× |
| 100 | `:=` creating `y = x + 1`, by `g` | 12561.7 | 394.5 | 31.84× | 0.33× | 0.57× |
| 100 | `mutate(y = x + 1, .by = g)` | 10688.7 | 388.7 | 27.50× | 0.32× | 0.56× |
| 100 | `:=` creating five `x + 1` columns, by `g` | 57091.9 | 702.8 | 81.23× | 0.34× | 0.89× |
| 100 | `mutate()` creating five `x + 1` columns, `.by = g` | 42300.2 | 444.1 | 95.26× | 0.22× | 0.56× |

## Validation and measurement

The final combined build passed the complete installed suite: 26,877 assertions, zero failures, errors or skips, and seven existing warnings. [Full test observations](grouped-2026-09-29-explicit-copy/test-results.csv). The tests retain public callback behavior, key-write validation, fallback continuation, first-appearance groups, complete metadata and Stata range checks. Updated wide-result cases verify ordinary R and dtatools isolation plus two-way foreign-write independence for `copy_data()`.

Candidate and updated #267 baseline each ran in a fresh process, candidate first, with 20 observations for each of 36 engine/condition combinations: 720 calls per build and 1,440 total. All calls passed complete value, column order, target and untouched attribute checks outside timing. The candidate recorded zero timed collections; the baseline recorded 120, included in its timings. The legacy `main_*` fields mean the updated #267 baseline in this report.

Full public calls are timed. Fixture construction, explicit GC, admission counters and correctness checks are outside the timer. data.table uses one thread. No local build or test ran concurrently with these benchmarks. Seeds are 290929 for candidate and 290930 for baseline. The unchanged analyzer uses fixed seed 20260929, 10,000 resamples and saved bootstrap indices. Candidate/comparator samples are paired; builds are resampled independently. Intervals are pointwise percentile intervals, not simultaneous guarantees or a formal equivalence test. One machine, one process per build, candidate-first order and process variation limit generalization.

Measured on macOS ARM64, R 4.6.1 revision 90187, dplyr 1.2.1, data.table 1.18.6.1, vctrs 0.7.3, rlang 1.3.0 and tibble 3.3.1. Guarded paths require the audited runtime/dependency artifacts; other builds retain ordinary fallback. Source and DLL hashes pin the measured executable revisions. Subsequent report commits do not change that executable source.

[Complete comparisons](grouped-2026-09-29-explicit-copy/comparisons.csv), [scoped counts](grouped-2026-09-29-explicit-copy/scope-summary.json), [fixed bootstrap indices](grouped-2026-09-29-explicit-copy/bootstrap-indices.npz), [source and DLL hashes](grouped-2026-09-29-explicit-copy/provenance.json), [candidate observations](grouped-2026-09-29-explicit-copy/experiments-raw.csv), [baseline observations](grouped-2026-09-29-explicit-copy/merged-main-raw.csv), [candidate session](grouped-2026-09-29-explicit-copy/experiments-session.txt), [baseline session](grouped-2026-09-29-explicit-copy/merged-main-session.txt), [publication counters](grouped-2026-09-29-explicit-copy/experiments-publications.csv).

Reproduce after installing each recorded revision separately:

```sh
DTATOOLS_BENCH_GROUPED_ONLY=1 Rscript benchmarks/r-numeric-performance/validate-plain-grouped.R /path/to/grouped-lib experiments /tmp/grouped-bench/experiments 20 290929
DTATOOLS_BENCH_GROUPED_ONLY=1 Rscript benchmarks/r-numeric-performance/validate-plain-grouped.R /path/to/plain-lib merged-main /tmp/grouped-bench/merged-main 20 290930
python3 benchmarks/r-numeric-performance/analyze-experiments.py /tmp/grouped-bench /tmp/grouped-analysis
```
