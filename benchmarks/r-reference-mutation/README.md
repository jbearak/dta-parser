# R reference mutation benchmark

Run this benchmark against an installed development build:

```sh
Rscript benchmarks/r-reference-mutation/run.R
```

The workload times repeated one-row changes in a five-million-row compact Stata
byte column. It fails if the direct target materializes or if R reports one
allocation as large as the native byte payload. A second timing keeps an
unselected missing value at the end of the target to catch accidental
full-column cache scans. It then generates a five-million-row column and uses
`tracemem()` to check that neither existing column payload was copied.

The benchmark also patches a metadata proxy. Isolation requires that path to
detach and copy the full compact native byte payload. The check confirms the
copy is no larger than compact storage and never becomes a full R double
column. Direct targets do not pay that detachment cost.

`Rprofmem()` reports individual R allocations. Native compact backing appears
as its raw-vector allocation, but the profiler does not measure allocator
overhead or Rust-owned memory. This benchmark is a regression gate for the two
specific promises in #86, not a process-wide peak-memory measurement.
