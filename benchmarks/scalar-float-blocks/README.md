# Scalar float block comparison

This screen measures public `x + 0.1`, `x - 0.1`, `x * 1.01` and `x / 1.01`
on one million plain compact-float values. Typed doubles provide controls for
every pattern; bare R doubles are included only without missing values.
Seven missing layouts cover none, a sparse 997-row grid, an independently
sampled half, the first half, the first 256, the last 256 and every row.
All 27 canonical missing ranks cycle where missing values occur.

Compact expected results use independent binary64 arithmetic followed by
binary32 rounding. Typed and bare results keep binary64 precision. Comparing
their throughput does not assert that the differently stored outputs have
identical bits. Source values are identical across representations, and
same-storage results must agree across builds and rounds. Arithmetic missing
results normalize to system missing; input tags remain intact.

The controller pins exact source commits and preserves each build receipt's
actual variant independently of its baseline/candidate role. It requires Unix
R executable layout. From the repository root:

```sh
python3 benchmarks/scalar-float-blocks/test-kernel.py
python3 -O benchmarks/scalar-float-blocks/test-kernel.py
python3 benchmarks/scalar-float-blocks/test-run.py
python3 -O benchmarks/scalar-float-blocks/test-run.py
python3 benchmarks/scalar-float-blocks/run.py \
  --baseline BASELINE_BUILD --candidate CANDIDATE_BUILD \
  --repository "$PWD" --output NEW_QUALIFICATION --qualify-only
python3 benchmarks/scalar-float-blocks/run.py \
  --baseline BASELINE_BUILD --candidate CANDIDATE_BUILD \
  --repository "$PWD" --output NEW_RESULTS --qualification NEW_QUALIFICATION
```

Qualification has 120 observations with no clocks or calibration. Each worker
executes a primer and then one recorded native-entry-checked call per case.
The measured matrix has 720 observations over six rounds. Build and operation
orders alternate, and representation positions balance exactly. Seven-pattern
order rotates and reverses; six rounds neither exhaust all permutations nor
balance every pattern position. Both builds use the same case order per round.

Timed repeated calls include result allocation and automatic garbage collection.
Calibration takes at least 50 ms CPU, then selects repetitions targeting 300 ms.
Input construction, explicit collection, calibration, hashes and qualification
are excluded. Every retained typed call must enter the native scalar route in
both builds. Full input, rank, result and missing-mask hashes, result storage,
missing caches, metadata stability and source ownership are checked separately.

Before/after provenance binds the actual absolute Rscript launcher and R runtime,
complete clean source and installed-library inventories, controller dependencies
and prior qualification. Every worker CSV is preserved and validated before
aggregation. Results describe one host and these plain inputs. Retained spans,
reverse division, imported noncanonical values and precision boundaries have
separate correctness coverage and are not timed here. The existing 34-case
general-arithmetic benchmark remains available as a broader acceptance check.
