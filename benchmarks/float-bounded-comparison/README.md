# Bounded compact-float comparison

This benchmark compares plain and retained compact-float pairs with contiguous
typed-double controls. It checks whether a short exceptional prefix keeps a
long ordinary tail on the exact-classification path. The
[October 3 report](results-2026-10-03.md) includes the 768-observation measured
result, slower cases and exact source bindings.

The controller requires Unix R executable layout. Package support on other
platforms is unchanged. It pins clean baseline `bb135c1f` and candidate
`847919ce` build receipts; a receipt's actual build variant remains distinct
from its role in this comparison. Use the source-bound builder in
`benchmarks/r-file-readers/build-snapshot.py` to build those commits in separate
directories. It produces each build's `library`, `source` and
`build-receipt.json`.

Run each panel's no-clock qualification before measurement. All output
directories must be new. For example, from the repository root:

```sh
python3 benchmarks/float-bounded-comparison/test-run.py
python3 -O benchmarks/float-bounded-comparison/test-run.py
python3 benchmarks/float-bounded-comparison/run.py \
  --baseline /path/to/baseline-build --candidate /path/to/candidate-build \
  --repository "$PWD" --output /path/to/density-qualification \
  --panel density --qualify-only
python3 benchmarks/float-bounded-comparison/run.py \
  --baseline /path/to/baseline-build --candidate /path/to/candidate-build \
  --repository "$PWD" --output /path/to/density-measurement \
  --panel density --qualification /path/to/density-qualification
```

Repeat with `--panel pattern` and `--panel ordinary`, each with separate output
and qualification paths. Use six rounds or a positive multiple of six. Stop
other builds, tests and benchmarks during measurement.

Every worker validates full values and results, independent missing ranks,
metadata, native eligibility and source states. Plain and retained layouts
must have identical values; retained operands have 123 and 62 native chunks.
The controller rejects incomplete or unbalanced matrices and changed source,
library, execution-runtime, controller or qualification bindings. Successful
runs end with `completion.json`, full worker CSVs, aggregate raw observations,
summary ratios, before/after provenance and the exact package-source patch.

Timed repeated public calls include result allocation and automatic collection.
Explicit collection, calibration, construction and verification are excluded.
The no-clock mode records one operation after separate public-result and
native-eligibility checks. It does not mean the public operation is called only
once in the worker.
