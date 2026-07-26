# R materialization benchmark

This benchmark compares the two output collectors built into the same package:

- `direct-r`: numeric cells are decoded into their final R vectors; strings are
  retained only until they can be batch-materialized into R.
- `rust-vectors`: the reference path builds a complete `DtaData` value before
  converting it into R vectors.

The timing runner checks exact output identity, warms both paths, alternates
execution order, runs garbage collection outside the timed region, and writes
every observation to TSV:

```sh
Rscript benchmarks/r-materialization/run.R input.dta timings.tsv 21
```

Peak memory must be measured in fresh processes. On macOS:

```sh
/usr/bin/time -l Rscript benchmarks/r-materialization/memory-worker.R input.dta direct-r
/usr/bin/time -l Rscript benchmarks/r-materialization/memory-worker.R input.dta rust-vectors
```

Compare both `maximum resident set size` and `peak memory footprint`. The final
R object is intentionally retained until process exit so it is included in the
measurement.
