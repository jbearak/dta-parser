# R materialization benchmark

This benchmark compares the two output collectors built into the same package:

- `direct-r`: numeric cells are decoded into their final R vectors; strings are
  retained only until they can be batch-materialized into R.
- `rust-vectors`: the reference path builds a complete `DtaData` value before
  converting it into R vectors.

The timing runner checks exact output identity, warms both paths, alternates
execution order, runs garbage collection outside the timed region, and writes
every observation to TSV. Build the package from the current checkout and
install it into a fresh benchmark-only library before starting a benchmark
session:

```sh
R CMD build r-package/dtaparser
mkdir -p "$PWD/target"
benchmark_lib="$(mktemp -d "$PWD/target/r-benchmark-library.XXXXXX")"
R CMD INSTALL --library="$benchmark_lib" dtaparser_0.1.0.tar.gz
export DTAPARSER_BENCH_LIB="$benchmark_lib"
Rscript benchmarks/r-materialization/run.R input.dta timings.tsv 21
```

Both runners require `DTAPARSER_BENCH_LIB` and verify that `dtaparser` was
loaded from that checkout-local library, preventing a global or stale
installation from being benchmarked accidentally. Install before the timed
process so package installation is excluded from the memory measurements.

Peak memory must be measured in fresh processes. On macOS:

```sh
/usr/bin/time -l Rscript benchmarks/r-materialization/memory-worker.R input.dta direct-r
/usr/bin/time -l Rscript benchmarks/r-materialization/memory-worker.R input.dta rust-vectors
```

Compare both `maximum resident set size` and `peak memory footprint`. The final
R object is intentionally retained until process exit so it is included in the
measurement.
