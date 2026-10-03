# Native comparison follow-up

This diagnostic compares retained float kernels and ordinary decoded-double
pair kernels against the same public operators. It uses one million rows, six
balanced rounds, thread settings 1 and automatic, and missing-free or sparse
missing inputs. Bare-double controls retain R's NA-propagation contract; only
missing-free bare comparisons have the same contract as Stata comparisons.

Float inputs use retained spans of 8,191 and 16,385 values. Typed-double and
bare-double controls use ordinary decoded buffers. Scalar less-than is also a
control for the unchanged typed-double scalar kernel. The worker checks full
results, input bytes, attributes and representation state outside timing.

Build both revisions with `benchmarks/r-file-readers/build-snapshot.py` into
separate private directories. The `baseline` and `candidate` arguments identify
experiment roles; each original receipt retains its actual build variant.
The controller validates clean source inventories, installed libraries and the
actual Rscript runtime and version before and after all workers. The benchmark
builder uses the Unix R executable layout; this controller explicitly rejects
Windows. This restriction concerns the benchmark, not package support. Run without concurrent
local tests, builds or other benchmarks:

```sh
python3 benchmarks/native-comparison/run.py --baseline /private/reference-build \
  --candidate /private/candidate-build --output /private/comparison-results
```

For untimed qualification, invoke `worker.R` with an installed library, round
number, output CSV and the final argument `qualify`. The controller rejects
incomplete case matrices, unbalanced representation permutations, inconsistent
full hashes or source state, and invalid timing intervals. Timing is evidence
for review, never a CI performance threshold.
