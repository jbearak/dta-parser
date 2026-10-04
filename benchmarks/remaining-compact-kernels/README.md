# Remaining compact arithmetic kernels

This panel revisits six cases from the earlier 34-case public-operation benchmark. It uses the original million-row fixtures, result oracle, timed operations, native-entry checks and mutation checks. The subset contains integer and FLOAT reverse division, plus sparse integer/FLOAT addition and multiplication. The worker is an exact copy of the recorded subset worker. `evidence/candidate1/repro-source.json` records its relationship to the original panel.

The [final report](report.md) records the accepted candidate3 combination. Sparse mixed addition and multiplication improved by 1.27x and 1.32x. Dense FLOAT reverse division improved by 1.51x. Gaps remain against both DOUBLE controls; this change does not establish parity. The [final evidence](evidence/final/README.md) binds both timing panels and the focused regression tests to one installed DLL.

The [candidate1 record](evidence/candidate1/README.md) preserves the preliminary 216 observations separately.

The [rejected clean-pair screen](evidence/rejected-clean-pair/README.md) records a later single-round experiment. The added clean-block scan offered no clear incremental benefit, so it was removed from the final combination. The reciprocal changes were retained and measured separately in the final panels. This screen is not a balanced performance result or a final candidate binding.

The two controls answer different questions. `typed_double` performs the public dtatools operation and produces DOUBLE storage with its missing-value and metadata rules. `ordinary` performs a base R double operation. For example, base R reverse division retains infinity for zero denominators; dtatools canonicalizes an invalid result to missing and may narrow the column. The report must show both controls. A compact/typed ratio near one does not establish parity with bare R doubles.

The worker checks result bytes, storage, missing masks, missing-cache clearing, source bytes, source materialization state, and native-entry counts outside timing. Each timed observation lasts approximately 150 milliseconds after calibration. Fresh R workers run sequentially. Odd rounds run baseline then candidate, and even rounds reverse that order. Representation order also rotates. Statistics use CPU per call and medians of within-round ratios. There is no statistical parity assertion or timing gate in CI.

Run the panel with already installed, separately qualified libraries while no other benchmark, build or test is running:

```sh
python3 benchmarks/remaining-compact-kernels/run.py \
  --baseline-library /path/to/baseline-library \
  --candidate-library /path/to/candidate-library \
  --output /path/to/fresh-output
```

The general controller performs no installation or compilation. It records worker/controller hashes and installed DLL, R database and package metadata hashes before and after the run. The caller must retain the matching build receipt or source binding for each installed library. Timing a DLL does not prove which source produced it.

The dense panel uses the original million-row `random_half` fixture, all 27 missing tags and a separate three-representation worker. Its calibration targets approximately 300 milliseconds of CPU per observation. Run it against the same libraries:

```sh
python3 benchmarks/remaining-compact-kernels/dense-run.py \
  --baseline-library /path/to/baseline-library \
  --candidate-library /path/to/candidate-library \
  --include-bare --output /path/to/fresh-dense-output
```

The exact executed dense controller is retained with the evidence. It checked worker and DLL immutability, but did not bind the installed R databases or package metadata. Its result oracles and metadata and missing-cache checks remain valid within that recorded scope. The current portable controller defaults to three representations, accepts `.so`, `.dll` and `.dylib` libraries, and binds DLLs, `DESCRIPTION`, `NAMESPACE` and both R database files before and after each worker. These changes are recorded separately and do not revise the historical receipts. Bare division retains the fixture's 48 zero-denominator infinities; package outputs normalize them to missing.

Check the portable dense controller's library discovery and drift guards without running R:

```sh
python3 benchmarks/remaining-compact-kernels/test-dense-run.py
```

Replay the focused public regressions against an installed candidate without rebuilding:

```sh
Rscript --vanilla benchmarks/remaining-compact-kernels/focused-tests.R \
  /path/to/candidate-library r-package/dtatools/tests/testthat /path/to/tests.csv
```

To validate and summarize existing observations without running R:

```sh
python3 benchmarks/remaining-compact-kernels/run.py \
  --summarize-only --output /path/to/existing-output
```

Structural probes use the actual headers with mocked R boundaries. They supplement the public package tests and do not measure runtime or package ownership. The [mixed-pair probe](../compact-pair-domain/work-count.py) checks strict and unknown domains, all missing tags, four floating-point rounding modes and promotion limits. The [dense reciprocal probe](../dense-float-reciprocal/work-count.py) checks the reciprocal writer and exact replay. Both are optional local C++ analysis inputs. They add no hosted C++ CI job.
