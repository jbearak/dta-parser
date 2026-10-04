# Compact column facts

The [report](report.md) records the measured gains and constructor cost of caching bounds and zero counts for native compact columns. The public operation panels retain 216 general observations and 36 dense reciprocal observations. A separate panel retains 72 observations of construction followed by zero, one or five operations. All three use the same qualified candidate DLL.

The [source bindings](source-bindings.json) identify the installed DLL, qualified runtime checkpoint, changed package files and exact workers/controllers. The [candidate build receipt](evidence/candidate-build-receipt.json) retains all 479 source hashes. [Publication provenance](publication-source-map.json) records original and published hashes for copied artifacts; [the manifest](publication-manifest.json) covers this directory. JSON command paths use placeholders. Recorded artifact hashes for omitted logs, binaries and derived headers refer to private originals. The construction summary includes its full before snapshot, so its separate `before.json` duplicate is omitted.

The existing [general controller](../remaining-compact-kernels/run.py) and [dense controller](../remaining-compact-kernels/dense-run.py), with their workers, produced these operation panels without changes. They qualify values, missing masks, metadata, source state and native entry counts outside timing. Both bind the installed DLL, R databases and package metadata before and after their sequential workers. Historical evidence in earlier benchmark directories is unchanged.

Run an operation panel with separately installed baseline and candidate libraries, with no concurrent benchmark or build:

```sh
python3 benchmarks/remaining-compact-kernels/run.py \
  --baseline-library /path/to/baseline-library \
  --candidate-library /path/to/candidate-library --output /path/to/fresh-general-output
python3 benchmarks/remaining-compact-kernels/dense-run.py \
  --baseline-library /path/to/baseline-library \
  --candidate-library /path/to/candidate-library --output /path/to/fresh-dense-output
```

The construction worker includes allocation and automatic garbage collection in its clocks. Its input fixtures match those public workers. Every one or five-operation workflow divides the same newly constructed source repeatedly; results are not chained. Phase positions rotate, and build order alternates across six fresh-process pairs. The exact executed construction controller is retained in `evidence/construction/controller.py`. The portable controller changes only its default path to the sibling public workers; its timing and qualification logic is unchanged.

```sh
python3 benchmarks/compact-column-facts-performance/construction-run.py \
  --baseline-library /path/to/baseline-library \
  --candidate-library /path/to/candidate-library \
  --baseline-receipt /path/to/original-baseline-build-receipt.json \
  --candidate-receipt /path/to/original-candidate-build-receipt.json \
  --output /path/to/fresh-construction-output
```

Construction qualification requires the original local build receipts and their matching build-source copies. Published receipt placeholders must be restored before replay. `--qualify-only` runs the same semantic workflow without clocks. None of these controllers installs dependencies or compiles R.

The focused runner checks seven public regression files against an installed candidate:

```sh
Rscript --vanilla benchmarks/compact-column-facts-performance/focused-tests.R \
  /path/to/candidate-library r-package/dtatools/tests/testthat /path/to/test-results.csv
```

The structural probes use actual production headers with mocked R boundaries. Their receipts and case CSVs are in `evidence/probes/`; maintained drivers remain in [compact-pair-domain](../compact-pair-domain/work-count.py), [dense-float-reciprocal](../dense-float-reciprocal/work-count.py), [integer-reciprocal](../integer-reciprocal/work-count.py), and [compact-float-facts](../compact-float-facts/metadata-span.py). These local probes establish semantic and work counts, not R ownership or runtime speed. They add no hosted C++ job or timing gate.

Validate this publication against the recorded source checkpoint without running R:

```sh
python3 benchmarks/compact-column-facts-performance/validate.py
```
