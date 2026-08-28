# R materialization benchmark

This benchmark compares the two output collectors built into the same package:

- `dta-tools`: numeric cells are decoded into their final R vectors; distinct
  strings are interned once and compact row indices are exposed through ALTREP.
- `rust-vectors`: the reference path builds a complete `DtaData` value before
  converting it into R vectors.

The timing runner checks exact output identity, warms both paths, alternates
execution order, runs garbage collection outside the timed region, and writes
every observation to TSV. Build the package from the current checkout and
install it into a fresh benchmark-only library before starting a benchmark
session:

```sh
dtatools_version="$(sed -n 's/^Version: //p' r-package/dtatools/DESCRIPTION)"
dtatools_tarball="dtatools_${dtatools_version}.tar.gz"
R CMD build r-package/dtatools
mkdir -p "$PWD/target"
benchmark_lib="$(mktemp -d "$PWD/target/r-benchmark-library.XXXXXX")"
R CMD INSTALL --library="$benchmark_lib" "$dtatools_tarball"
export DTATOOLS_BENCH_LIB="$benchmark_lib"
Rscript benchmarks/r-materialization/run.R input.dta timings.tsv 21
```

Both runners require `DTATOOLS_BENCH_LIB` and verify that `dtatools` was
loaded from that checkout-local library, preventing a global or stale
installation from being benchmarked accidentally. Install before the timed
process so package installation is excluded from the memory measurements.

Peak memory must be measured in fresh processes. On macOS:

```sh
/usr/bin/time -l Rscript benchmarks/r-materialization/memory-worker.R \
  input.dta dtatools dimensions full
/usr/bin/time -l Rscript benchmarks/r-materialization/memory-worker.R \
  input.dta rust-vectors dimensions full
/usr/bin/time -l Rscript benchmarks/r-materialization/memory-worker.R \
  input.dta haven dimensions full
```

Compare both `maximum resident set size` and `peak memory footprint`. The final
R object is intentionally retained until process exit so it is included in the
measurement. Replace `dimensions` with `object-size` to force complete
row-level string-pointer vectors, or replace `full` with
`projected-eight-columns` for the large-scale harness's fixed projection.

`string-workloads.R` times the complete load plus five matched consumers:
dimensions only, a distributed 1,024-row subset of every character column, a
numeric-column scan, an all-character scan, and `object.size()`. It validates
dimensions for every workload and validates non-`object.size()` checksums
against the eager Rust-vector collector. Object size is intentionally allowed
to differ between representations. The runner writes every measured
observation to TSV:

```sh
Rscript benchmarks/r-materialization/string-workloads.R input.dta string-workloads.tsv 21
```
