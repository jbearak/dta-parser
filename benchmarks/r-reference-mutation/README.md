# R reference mutation benchmark

Run this benchmark against an installed development build:

```sh
Rscript benchmarks/r-reference-mutation/run.R
```

The workload changes one row in a five-million-row compact Stata byte column.
It fails if the column materializes or if R reports one allocation as large as
the corresponding full double vector. It then generates a five-million-row
column and uses `tracemem()` to check that neither existing column payload was
copied.

`Rprofmem()` reports individual R allocations. Native compact backing appears
as its raw-vector allocation, but the profiler does not measure allocator
overhead or Rust-owned memory. This benchmark is a regression gate for the two
specific promises in #86, not a process-wide peak-memory measurement.
