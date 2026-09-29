# Validated saved performance experiments — 2026-09-29

The saved whole-operation experiments have been integrated into PR #266 and validated together. In the measured ungrouped owned-double matrix, all 56 operation/shape combinations beat plain dplyr, and 52 beat plain data.table by more than 5%. The four exceptions are `replace_values(x = abs(-3))`, which takes 1.37–1.79 times the data.table runtime. All 56 dplyr comparisons and all 52 data.table wins also meet their respective thresholds at the upper end of the pointwise 95% bootstrap interval.

The broader claim does **not** hold for plain vectors or grouped operations with plain/owned double keys. Only 6 of 56 ungrouped plain cases beat dplyr, and none matches data.table. All 20 grouped cases remain slower than both comparators. The combined changes also regress some operations against merged main; these results are retained below. No further performance search was performed after the saved experiments were selected. Integration changes repair correctness, lifetime, callback, metadata and test-portability defects.

This report supersedes the earlier [small-subset report](results-2026-09-29.md), which omitted these whole-operation paths. It does not claim that every public operation or input reaches a native path.

## Scope and aggregate results

Every dtatools operation runs on a **dibble**. Every input column, including the group key and untouched siblings, uses the stated storage mode: ordinary R double buffers with Stata attributes (`plain`), or package-owned double buffers (`owned`). Compact numeric payloads are excluded from the timing matrix. References use plain double columns in ordinary tibbles/data.tables. `mutate()` includes its copy/isolation semantics; reference mutation is timed through the respective public interfaces.

| Input and operation scope | Cases | Beats dplyr | At most 5% slower than data.table | Literal ±5% of data.table | Faster than main |
| --- | ---: | ---: | ---: | ---: | ---: |
| Plain, ungrouped | 56 | 6 | 0 | 0 | 21 |
| Owned, ungrouped | 56 | 56 | 52 | 0 | 48 |
| Plain, grouped | 10 | 0 | 0 | 0 | 10 |
| Owned, grouped | 10 | 0 | 0 | 0 | 10 |

“Literal ±5%” means a runtime ratio from 0.95 to 1.05. All 52 successful owned/data.table comparisons are faster than that band, so none falls inside it. These are counts of sampled medians; pointwise intervals are in the [complete comparison table](experiments-2026-09-29/comparisons.csv), not simultaneous guarantees across the matrix.

The 43 slower medians against main comprise 35 ungrouped plain cases and all eight owned `replace_values()` scalar/call cases. The worst median slowdowns are 22.7% for plain and 33.5% for owned. The pointwise interval supports a slowdown in 40 of those 43 cases. The remaining 89 medians improve, with speedups up to 6.05× for plain and 97.17× for owned. Grouped cases improve 3.08–5.59× against main but still miss the requested comparison targets. The saved grouped kernels require compact group keys; they do not apply to this matrix's double keys. No new key-specialization experiment was added.

## Plain vectors in dibbles

100,000 rows, two input columns, ungrouped. Times are microseconds. Comparator ratios are candidate runtime divided by comparator runtime; lower is better. Main speedup is main divided by candidate; values below 1 indicate a regression.

| Operation on a dibble | Main µs | Candidate µs | Main speedup | / dplyr | / data.table |
| --- | ---: | ---: | ---: | ---: | ---: |
| `replace_values(x = 3)` | 304.2 | 337.0 | 0.90× | 0.73× | 1.70× |
| `:=` replacing `x = 3` | 356.6 | 424.4 | 0.84× | 0.92× | 2.14× |
| `mutate(x = 3)` | 3196.4 | 1119.6 | 2.85× | 2.44× | 5.64× |
| `replace_values(x = abs(-3))` | 326.3 | 392.8 | 0.83× | 1.06× | 1.95× |
| `:=` replacing `x = abs(-3)` | 376.3 | 435.3 | 0.86× | 1.18× | 2.17× |
| `mutate(x = abs(-3))` | 2047.7 | 1052.3 | 1.95× | 2.85× | 5.23× |
| `replace_values(x = x + 1)` | 4326.3 | 2727.1 | 1.59× | 7.02× | 12.41× |
| `:=` replacing `x = x + 1` | 4374.5 | 2783.3 | 1.57× | 7.17× | 12.66× |
| `mutate(x = x + 1)` | 2278.9 | 795.1 | 2.87× | 2.05× | 3.62× |
| `gen(y = x + 1)` | 2501.3 | 562.9 | 4.44× | 1.44× | 2.35× |
| `:=` creating `y = x + 1` | 2514.8 | 616.8 | 4.08× | 1.58× | 2.58× |
| `mutate(y = x + 1)` | 2294.1 | 804.7 | 2.85× | 2.06× | 3.36× |
| `:=` creating five columns, each `x + 1` | 11982.6 | 1980.0 | 6.05× | 3.19× | 5.73× |
| `mutate()` creating five columns, each `x + 1` | 9881.8 | 1645.8 | 6.00× | 2.65× | 4.77× |

## Owned vectors in dibbles

The same operations, dimensions and comparison definitions as the plain table.

| Operation on a dibble | Main µs | Candidate µs | Main speedup | / dplyr | / data.table |
| --- | ---: | ---: | ---: | ---: | ---: |
| `replace_values(x = 3)` | 82.9 | 93.2 | 0.89× | 0.20× | 0.47× |
| `:=` replacing `x = 3` | 164.0 | 151.4 | 1.08× | 0.33× | 0.76× |
| `mutate(x = 3)` | 3147.4 | 108.7 | 28.96× | 0.23× | 0.55× |
| `replace_values(x = abs(-3))` | 212.8 | 278.7 | 0.76× | 0.74× | 1.37× |
| `:=` replacing `x = abs(-3)` | 265.9 | 151.8 | 1.75× | 0.40× | 0.75× |
| `mutate(x = abs(-3))` | 2015.0 | 110.2 | 18.28× | 0.29× | 0.54× |
| `replace_values(x = x + 1)` | 2130.4 | 137.7 | 15.48× | 0.36× | 0.63× |
| `:=` replacing `x = x + 1` | 2182.6 | 172.1 | 12.68× | 0.45× | 0.79× |
| `mutate(x = x + 1)` | 2230.7 | 97.7 | 22.82× | 0.25× | 0.45× |
| `gen(y = x + 1)` | 2462.1 | 201.0 | 12.25× | 0.50× | 0.82× |
| `:=` creating `y = x + 1` | 2484.1 | 188.4 | 13.19× | 0.47× | 0.77× |
| `mutate(y = x + 1)` | 2236.1 | 101.3 | 22.08× | 0.25× | 0.41× |
| `:=` creating five columns, each `x + 1` | 11843.8 | 297.9 | 39.76× | 0.48× | 0.87× |
| `mutate()` creating five columns, each `x + 1` | 9828.7 | 101.1 | 97.17× | 0.16× | 0.30× |

## Validation

The combined installed package passed 1,533 test blocks across 111 files: **26,854 assertions, zero failures/errors/skips**, and seven existing warnings. After the final lifetime and callback-order repairs, the affected six files passed 407 assertions, and the final bracket regression file passed all five child-process tests. The [latest per-file observations](experiments-2026-09-29/validation/latest-observations.csv) combine those runs; they are not represented as one full run of the final source.

The saved control fixtures were rerun on the combined build: unfamiliar names and column positions, zero/small/large row counts, arbitrary offsets, grouped selection, parser rejection, each committed output prefix, source writes during generation, public function tracing, real GC/finalizer callbacks, and mutable output metadata. Added regressions cover preserving an evaluated RHS on fallback, late grouped shaping errors, independent sibling metadata and reference-marker callback counts. The final archive passed a fresh installed native-admission run: 17 assertions, zero failures/errors/skips/warnings.

The CodeRabbit optional `data.table` guards are included. With dplyr absent and data.table present, the selected native-lane tests pass 585 assertions with six expected skips and no failures or warnings. With dplyr present and data.table absent, all four blocks in the three reviewed test files skip cleanly. These are focused dependency checks, not full-suite runs without optional dependencies.

`R CMD build`, archive-content validation, and `R CMD check --no-manual --no-tests` pass with the same three warnings and two notes as merged main: local macOS deployment targets in vendored objects, vendored GNU makefiles, a Rust abort symbol, vendored CITATION placement and a generated C file without a final newline. Tests run separately against installed code. [Check log](experiments-2026-09-29/validation/R-CMD-check.log).

The frozen execution profile was independently reproduced: 328 public roots, 47 dependency artifacts and seven R/base artifacts. Public body/formals replacement, tracing, custom methods, ordinary callbacks, errors, values, metadata and input isolation remain supported through qualification or fallback. As agreed earlier, direct bytecode writes and modification of private helper/native registrations are outside the compatibility boundary.

## Measurement and provenance

- Six shapes: ungrouped 100 or 100,000 rows, each at 2 or 100 columns; grouped 10,000 rows and 100 groups, at 2 or 100 columns. Ungrouped scenarios are scalar replacement, a scalar call, arithmetic replacement, one creation and five creations. Grouped scenarios are one and five creations. The five-output expressions are identical `x + 1` expressions; this does not establish the same gains for five unrelated expressions.
- Two fresh R processes, candidate then main, with seeds 290929 and 290930. Engines are randomly interleaved within each condition. Twenty observations per engine/condition give 4,560 timed calls per build, **9,120 total**. Every call passed complete value, column-order, untouched-attribute, target-storage and dplyr input-isolation checks.
- Fixtures, storage checks, explicit GC and result verification are outside the timer. The full public call is inside it. Timed GC remains included: 116 candidate observations and 418 main observations. data.table uses one thread; allocation profiling is off.
- Ratios use sample medians. Fixed seed 20260929 produces 10,000 bootstrap resamples. The same observation indices pair candidate and comparator within a sample; main/candidate indices are independent because builds ran separately. [Saved indices](experiments-2026-09-29/bootstrap-indices.npz) make the analysis reproducible. Intervals are pointwise percentile intervals, not a formal equivalence test. One machine and one process per build leave build order and machine variation uncontrolled.
- R 4.6.1 revision 90187, macOS ARM64; dplyr 1.2.1, data.table 1.18.6.1, vctrs 0.7.3, rlang 1.3.0, tibble 3.3.1 and NumPy 2.5.2. Other dependency/runtime profiles retain ordinary fallback and are not covered by these performance claims.
- Main executable source is `63233be065831cabf5fa859e7573cf0739341a54`, equivalent to merged `0fe58d945323aa805b33a6fbb0417deddaf65aad` except for the test manifest. Candidate executable changes are committed in `a110da24`; `6c9ac647` normalizes profile CSV line endings. The [measured source hashes](experiments-2026-09-29/measured-source-sha256.json) pin the benchmark build before final comment cleanup and CSV normalization. Those changes and subsequent test/report edits do not change executable behavior.

Native DLL SHA-256:

```text
main      de8e2462dab0062c0b689714f3a3f4752cedf21611f3335c4da9b15c771db1c7
candidate 59453d5c94cec8709fb543dd6f2840fd8d3b9edc988fb99277518cda41799409
```

[Candidate observations](experiments-2026-09-29/experiments-raw.csv), [main observations](experiments-2026-09-29/merged-main-raw.csv), [candidate provenance](experiments-2026-09-29/experiments-provenance.json), [main provenance](experiments-2026-09-29/merged-main-provenance.json) and [aggregate counts](experiments-2026-09-29/summary.json) accompany the report. Admission counters are saved separately from timed calls.

## Reproduce

Install the two revisions into separate libraries, then run from the repository root:

```sh
Rscript benchmarks/r-numeric-performance/validate-experiments.R /path/to/candidate-lib experiments /tmp/performance/experiments 20 290929
Rscript benchmarks/r-numeric-performance/validate-experiments.R /path/to/main-lib merged-main /tmp/performance/merged-main 20 290930
python3 benchmarks/r-numeric-performance/analyze-experiments.py /tmp/performance /tmp/analysis
```
