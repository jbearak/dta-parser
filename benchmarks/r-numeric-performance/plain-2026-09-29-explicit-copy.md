# Ungrouped plain and owned vectors under the explicit-copy contract

All 112 measured ungrouped cases beat dplyr, including the upper ends of their pointwise 95% bootstrap intervals. At the median, 111 take at most 1.05 times data.table's runtime; 108 meet that threshold through the interval's upper end. The revised contract removes the five wide plain `mutate()` misses in the previous run. Using the existing replacement-buffer plan for already-shared owned targets removes the four owned `replace_values(x = abs(-3))` misses. The new run still has four plain-vector confidence-bound exceptions, listed below. It does not establish universal data.table parity.

All 56 ungrouped plain cases improve against #266, by 1.93 to 27.31 times at the median. Owned comparisons against #266 are mixed, from 0.67 to 2.44 times; the source change for owned replacement selects an existing staging plan, and these separate-process timings do not isolate every change from run-to-run variation. Grouped performance is measured separately in [the grouped follow-up](https://github.com/jbearak/dta-parser/pull/268).

Every dtatools operation runs on a dibble. Every input column, including grouping keys and untouched siblings, is a canonical plain or owned Stata double vector as indicated. Compact vectors are excluded. Comparators use plain doubles in ordinary tibbles and data.tables.

[ADR 0044](../../docs/adr/0044-require-explicit-copies-before-foreign-reference-writes.md) preserves ordinary R copy-on-modify and isolation under dtatools mutators. Independence from later foreign reference writes requires `copy_data()`. Explicit independent copies are excluded from these timings for all engines. No result is required to share storage, and the operand/key snapshots needed during execution remain protected.

| Inputs | Cases | Beats dplyr at median | At most 5% slower than data.table at median | Both targets through upper 95% bound |
| --- | ---: | ---: | ---: | ---: |
| Plain | 56 | 56 | 55 | 52 |
| Owned | 56 | 56 | 56 | 56 |

The target is no more than 5% slower than data.table. Cases more than 5% faster also meet it; this is different from literal plus/minus 5% equivalence.

## Remaining data.table exceptions

All four cases below beat dplyr through the upper confidence bound. Only the first misses the data.table target at the median. Their pointwise intervals cross 1.05, so this run cannot establish the requested data.table bound for them. The results are retained without further optimization or selection of a favorable rerun.

| Rows | Input columns | Operation on plain dibble | / data.table | Pointwise 95% interval |
| ---: | ---: | --- | ---: | ---: |
| 100 | 100 | `:=` creating five `x + 1` columns | 1.086× | 0.975–1.168× |
| 100,000 | 2 | `gen(y = x + 1)` | 0.934× | 0.812–1.079× |
| 100,000 | 100 | `replace_values(x = abs(-3))` | 1.019× | 0.910–1.099× |
| 100,000 | 100 | `:=` creating five `x + 1` columns | 0.996× | 0.920–1.075× |

For the 100,000-row, 100-column plain one-column `mutate()` creation, the isolated allocation check fell from 80,827,480 bytes on the pre-contract #267 build to 1,622,728 bytes on this build. Both checks confirmed native publication and correct values. The final regression requires less than 16 MiB while retaining ordinary R, dtatools and explicit-copy isolation checks. [Before](plain-2026-09-29-explicit-copy/red-result.txt), [after](plain-2026-09-29-explicit-copy/green-result.txt), [reproduction](plain-2026-09-29-explicit-copy/check-wide-copy.R).

## Plain vectors in dibbles

100,000 rows, ungrouped. The full matrix also includes 100-row inputs. Times are microseconds. Ratios are candidate divided by comparator; smaller is faster. Both tables have the same operation and shape rows.

| Input columns | Operation | #266 µs | Candidate µs | Speedup | / dplyr | / data.table |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 2 | `replace_values(x = 3)` | 342.3 | 113.0 | 3.03× | 0.23× | 0.54× |
| 2 | `:=` replacing `x = 3` | 443.6 | 184.5 | 2.40× | 0.38× | 0.88× |
| 2 | `mutate(x = 3)` | 1155.5 | 151.6 | 7.62× | 0.31× | 0.72× |
| 2 | `replace_values(x = abs(-3))` | 410.1 | 153.3 | 2.68× | 0.39× | 0.70× |
| 2 | `:=` replacing `x = abs(-3)` | 455.2 | 176.3 | 2.58× | 0.45× | 0.81× |
| 2 | `mutate(x = abs(-3))` | 1089.5 | 150.8 | 7.23× | 0.38× | 0.69× |
| 2 | `replace_values(x = x + 1)` | 2786.3 | 174.7 | 15.95× | 0.40× | 0.70× |
| 2 | `:=` replacing `x = x + 1` | 2837.8 | 213.0 | 13.32× | 0.49× | 0.85× |
| 2 | `mutate(x = x + 1)` | 826.1 | 155.3 | 5.32× | 0.36× | 0.62× |
| 2 | `gen(y = x + 1)` | 577.4 | 299.4 | 1.93× | 0.57× | 0.93× |
| 2 | `:=` creating `y = x + 1` | 639.2 | 264.6 | 2.42× | 0.50× | 0.82× |
| 2 | `mutate(y = x + 1)` | 835.4 | 180.5 | 4.63× | 0.34× | 0.56× |
| 2 | `:=` creating five `x + 1` columns | 2031.8 | 376.5 | 5.40× | 0.52× | 0.95× |
| 2 | `mutate()` creating five `x + 1` columns | 1682.1 | 161.0 | 10.45× | 0.22× | 0.40× |
| 100 | `replace_values(x = 3)` | 484.8 | 176.9 | 2.74× | 0.24× | 0.67× |
| 100 | `:=` replacing `x = 3` | 599.1 | 252.6 | 2.37× | 0.34× | 0.95× |
| 100 | `mutate(x = 3)` | 4667.8 | 229.1 | 20.37× | 0.31× | 0.86× |
| 100 | `replace_values(x = abs(-3))` | 579.7 | 251.1 | 2.31× | 0.42× | 1.02× |
| 100 | `:=` replacing `x = abs(-3)` | 639.0 | 229.3 | 2.79× | 0.39× | 0.93× |
| 100 | `mutate(x = abs(-3))` | 4712.6 | 213.4 | 22.08× | 0.36× | 0.87× |
| 100 | `replace_values(x = x + 1)` | 3012.0 | 239.9 | 12.56× | 0.39× | 0.90× |
| 100 | `:=` replacing `x = x + 1` | 3076.4 | 244.7 | 12.57× | 0.40× | 0.91× |
| 100 | `mutate(x = x + 1)` | 4373.2 | 222.9 | 19.62× | 0.36× | 0.83× |
| 100 | `gen(y = x + 1)` | 760.1 | 267.0 | 2.85× | 0.40× | 0.94× |
| 100 | `:=` creating `y = x + 1` | 839.6 | 248.4 | 3.38× | 0.37× | 0.88× |
| 100 | `mutate(y = x + 1)` | 4372.6 | 189.5 | 23.07× | 0.29× | 0.67× |
| 100 | `:=` creating five `x + 1` columns | 2691.8 | 399.4 | 6.74× | 0.47× | 1.00× |
| 100 | `mutate()` creating five `x + 1` columns | 5681.1 | 208.0 | 27.31× | 0.25× | 0.52× |

## Owned vectors in dibbles

100,000 rows, ungrouped. The full matrix also includes 100-row inputs. Times are microseconds. Ratios are candidate divided by comparator; smaller is faster. Both tables have the same operation and shape rows.

| Input columns | Operation | #266 µs | Candidate µs | Speedup | / dplyr | / data.table |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 2 | `replace_values(x = 3)` | 98.0 | 108.8 | 0.90× | 0.21× | 0.47× |
| 2 | `:=` replacing `x = 3` | 159.0 | 178.8 | 0.89× | 0.34× | 0.77× |
| 2 | `mutate(x = 3)` | 109.8 | 123.2 | 0.89× | 0.23× | 0.53× |
| 2 | `replace_values(x = abs(-3))` | 287.8 | 161.3 | 1.78× | 0.38× | 0.67× |
| 2 | `:=` replacing `x = abs(-3)` | 160.5 | 181.9 | 0.88× | 0.43× | 0.75× |
| 2 | `mutate(x = abs(-3))` | 111.3 | 127.9 | 0.87× | 0.30× | 0.53× |
| 2 | `replace_values(x = x + 1)` | 142.9 | 166.6 | 0.86× | 0.37× | 0.66× |
| 2 | `:=` replacing `x = x + 1` | 183.5 | 206.9 | 0.89× | 0.46× | 0.82× |
| 2 | `mutate(x = x + 1)` | 102.1 | 117.6 | 0.87× | 0.26× | 0.46× |
| 2 | `gen(y = x + 1)` | 201.1 | 264.1 | 0.76× | 0.54× | 0.88× |
| 2 | `:=` creating `y = x + 1` | 191.7 | 239.4 | 0.80× | 0.49× | 0.80× |
| 2 | `mutate(y = x + 1)` | 103.5 | 144.8 | 0.72× | 0.30× | 0.48× |
| 2 | `:=` creating five `x + 1` columns | 306.4 | 368.8 | 0.83× | 0.49× | 0.90× |
| 2 | `mutate()` creating five `x + 1` columns | 103.6 | 143.2 | 0.72× | 0.19× | 0.35× |
| 100 | `replace_values(x = 3)` | 126.9 | 144.2 | 0.88× | 0.22× | 0.61× |
| 100 | `:=` replacing `x = 3` | 182.0 | 200.8 | 0.91× | 0.30× | 0.85× |
| 100 | `mutate(x = 3)` | 156.6 | 196.5 | 0.80× | 0.29× | 0.83× |
| 100 | `replace_values(x = abs(-3))` | 474.1 | 220.3 | 2.15× | 0.37× | 0.92× |
| 100 | `:=` replacing `x = abs(-3)` | 264.5 | 202.6 | 1.31× | 0.34× | 0.84× |
| 100 | `mutate(x = abs(-3))` | 195.9 | 178.1 | 1.10× | 0.30× | 0.74× |
| 100 | `replace_values(x = x + 1)` | 238.4 | 221.2 | 1.08× | 0.37× | 0.85× |
| 100 | `:=` replacing `x = x + 1` | 243.4 | 226.6 | 1.07× | 0.38× | 0.87× |
| 100 | `mutate(x = x + 1)` | 186.1 | 186.6 | 1.00× | 0.32× | 0.72× |
| 100 | `gen(y = x + 1)` | 334.5 | 256.3 | 1.30× | 0.38× | 0.83× |
| 100 | `:=` creating `y = x + 1` | 303.5 | 237.2 | 1.28× | 0.35× | 0.77× |
| 100 | `mutate(y = x + 1)` | 218.6 | 167.2 | 1.31× | 0.25× | 0.54× |
| 100 | `:=` creating five `x + 1` columns | 389.8 | 356.5 | 1.09× | 0.40× | 0.93× |
| 100 | `mutate()` creating five `x + 1` columns | 208.3 | 177.7 | 1.17× | 0.20× | 0.46× |

## Validation and measurement

The final plain build passed all 1,359 affected-file assertions with zero failures, errors, skips or warnings. The combined build in #268 then passed the complete suite: 26,877 assertions, zero failures, errors or skips and seven existing warnings. The separate runs are distinguished here; [this artifact](plain-2026-09-29-explicit-copy/test-results.csv) records the final plain targeted run. New regressions verify two-way ordinary R and dtatools writes, table and extracted aliases, metadata writes, explicit `copy_data()` isolation under foreign writes, reduced allocation and native publication for shared owned constant targets.

All 104 ungrouped cells covered by the retained whole-operation publication counters published natively, including all four owned constant-call cases. Literal `replace_values(x = 3)` uses a separate scalar path, so a zero in the unique-replacement counter for those eight cells is expected.

The unchanged full matrix contains four ungrouped shapes, 100 or 100,000 rows at 2 or 100 columns, and two grouped shapes. Candidate and #266 baseline each ran in a fresh process, candidate first, with 20 observations per engine and condition: 4,560 calls per build and 9,120 total. Engines are randomized within conditions. All calls passed complete values, target and untouched attributes, column order and applicable input-immutability checks outside timing. The candidate recorded 119 timed collections and the baseline 120, included in the measurements. The grouped rows retained in these artifacts are outside this PR's performance claims; `scope-summary.json` contains the ungrouped counts.

Full public calls are timed. Fixture construction, explicit GC, admission counters and correctness checks are outside the timer. data.table uses one thread. No local build or test ran concurrently with these benchmarks. Seeds are 290929 for candidate and 290930 for baseline. The unchanged analyzer uses fixed seed 20260929, 10,000 resamples and saved bootstrap indices. Candidate/comparator samples are paired; builds are resampled independently. Intervals are pointwise percentile intervals, not simultaneous guarantees or a formal equivalence test. One machine, one process per build, candidate-first order and process variation limit generalization.

Measured on macOS ARM64, R 4.6.1 revision 90187, dplyr 1.2.1, data.table 1.18.6.1, vctrs 0.7.3, rlang 1.3.0 and tibble 3.3.1. Guarded paths require the audited runtime/dependency artifacts; other builds retain ordinary fallback. Source and DLL hashes pin the measured executable revisions. Subsequent report commits do not change that executable source.

[Complete comparisons](plain-2026-09-29-explicit-copy/comparisons.csv), [scoped counts](plain-2026-09-29-explicit-copy/scope-summary.json), [fixed bootstrap indices](plain-2026-09-29-explicit-copy/bootstrap-indices.npz), [source and DLL hashes](plain-2026-09-29-explicit-copy/provenance.json), [candidate observations](plain-2026-09-29-explicit-copy/experiments-raw.csv), [baseline observations](plain-2026-09-29-explicit-copy/merged-main-raw.csv), [candidate session](plain-2026-09-29-explicit-copy/experiments-session.txt), [baseline session](plain-2026-09-29-explicit-copy/merged-main-session.txt), [publication counters](plain-2026-09-29-explicit-copy/experiments-publications.csv).

Reproduce after installing each recorded revision separately:

```sh
Rscript benchmarks/r-numeric-performance/validate-plain-grouped.R /path/to/plain-lib experiments /tmp/plain-bench/experiments 20 290929
Rscript benchmarks/r-numeric-performance/validate-plain-grouped.R /path/to/pr266-lib merged-main /tmp/plain-bench/merged-main 20 290930
python3 benchmarks/r-numeric-performance/analyze-experiments.py /tmp/plain-bench /tmp/plain-analysis
```
