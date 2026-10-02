# Prepared numeric grouping

This benchmark measures public `dta_group_id(..., missing = TRUE)` calls on
constructed compact columns, typed doubles and ordinary doubles. Every case
contains system missing, `.a` and `.z`. It covers byte, int, long and float
storage at 100,000 rows with one or four keys, plus one-million-row int
and float cases with one key. Random and sorted layouts use the same sample.
Compact inputs use contiguous constructor storage; retained chunks have separate unit coverage.

The [October 2 results](results-2026-10-02.md) include all observations, build
receipts, correctness evidence, an independent audit and explicit memory costs.

The baseline repeats numeric decoding and validation while sorting. The
candidate prepares one ordered 64-bit key per row and numeric column before
sorting. Its new temporary key payload is exactly `8 * rows * columns` bytes;
the decode tile is bounded separately. Strings and foreign ALTREP inputs keep
the previous scalar path, and are outside this benchmark.

## Reproduce

Commit the candidate, then create two fresh private source-bound builds:

```sh
python3 benchmarks/r-file-readers/build-snapshot.py \
  --variant baseline --base-commit fd72c344 \
  --work /private/tmp/grouping-baseline
python3 benchmarks/r-file-readers/build-snapshot.py \
  --variant candidate --base-commit CANDIDATE_COMMIT \
  --source r-package/dtatools --work /private/tmp/grouping-candidate
```

Check the full case matrix without measuring intervals:

```sh
Rscript --vanilla benchmarks/prepared-grouping/worker.R \
  /private/tmp/grouping-candidate/library 1 /private/tmp/grouping-qualification.csv qualify
python3 benchmarks/prepared-grouping/test-run.py
```

Stop other builds and tests on the host, then run:

```sh
python3 benchmarks/prepared-grouping/run.py \
  --baseline /private/tmp/grouping-baseline \
  --candidate /private/tmp/grouping-candidate \
  --output /private/tmp/grouping-results --rounds 6
```

Recompute compact/control CPU ratios, paired-round ratios and memory medians:

```sh
python3 benchmarks/prepared-grouping/analyze.py \
  --results /private/tmp/grouping-results \
  --output /private/tmp/grouping-ratios.csv
```

`publish.py` verifies a completed run against the original clean-build receipts
and a separate correctness-validation binding, substitutes private paths, and
records both original and published hashes for every artifact. The published
source map preserves that distinction; sanitizing a receipt does not make its
published hash equal its original hash. Both analysis and publication refuse
Python's `-O` mode so their assertions cannot be silently disabled.

The controller checks clean-build receipts, package source and installed-file
inventories, DLL equality, and controller hashes before and after measurement.
Each round uses a fresh R process per build, alternating build order and
balancing the three representation orders over six rounds. There are 60
observations per build per round. Calibration is untimed and selects fixed
repetitions targeting a 150 ms retained interval. The interval includes public
dispatch, allocations and automatic collection. Explicit collection, input
construction, qualification, hashing and the memory diagnostic are excluded.
Inspect actual retained durations; the target is not a guaranteed minimum.

The independent oracle sorts integer ranks and compares adjacent rank tuples.
Qualification checks complete output bytes, stable first rows, public metadata,
source bytes and compact state. Candidate counters must show exactly one
prepared value per row and key, with no scalar reads. Counters are disabled
during timing. Result, metadata and source hashes must agree across builds and
rounds before the controller writes a completion receipt.

The worker also records an untimed single-call increase in R's vector-heap
high-water mark after explicit collection. This includes keys, sorting scratch
and results; it excludes node and external allocator memory. It is neither
process peak RSS nor total allocated bytes. `key_cache_bytes` records the
candidate's theoretical key payload in every row for comparison; baseline
`prepared_bytes` is unavailable because it has no diagnostic counter.

These are warm constructed operations on one host with default output storage
and labels disabled. They do not measure readers, mixed string keys, foreign
providers, or every downstream grouping operation. Timing thresholds are not
part of the test suite.
