# R reference mutation benchmark

Run this benchmark against an installed development build:

```sh
Rscript benchmarks/r-reference-mutation/run.R
```

The workload times repeated one-row changes in a five-million-row compact Stata
byte column. It fails if the direct target materializes or if R reports one
allocation as large as the native byte payload. It compares the same patch on a
50,000-row column and enforces an absolute latency ceiling, so a hidden
full-column scan cannot pass because every large-column timing regressed
together. A second timing keeps an
unselected missing value at the end of the target to catch accidental
full-column cache scans. The run fails when that path is materially slower than
the direct sparse update. A third timing alternates clearing and restoring the
last missing value, which catches scans while the missing-value cache changes.
An all-row scalar replacement must stay within a bounded multiple of an
independent raw-vector fill. This catches repeated scalar decoding and
validation without comparing two paths that share the same implementation.
The benchmark also profiles a sparse full-length logical selector and a compact
explicit-position sequence. Both row planners must stay below one compact byte
payload of profiled allocation, guarding against full-length R temporaries.
Full-length integer and compact-byte replacements then verify that the patcher
consumes source vectors directly instead of constructing a double or a second
encoded column. Their targets keep native rollback bytes outside the R heap so
an interrupt can restore the original payload without materializing it.
The full-length integer case also runs through a compact position sequence.
The native patcher must gather each source value by its selected row without
turning that sequence into a full R double index.
The run then generates a five-million-row compact byte column from one scalar.
It fails if the largest R allocation reaches the size of a full double column,
and uses `tracemem()` to check that neither existing column payload was copied.
Full-length integer and compact-byte generation cases apply the same allocation
limit and catch coercion or validation temporaries that scalar generation cannot
expose. The integer case also uses a compact position sequence and limits total
profiled allocation to less than one double column. Finally, scalar character
generation may allocate its result vector once, but cannot allocate a second
full-length character-vector header.

The benchmark also patches a metadata proxy. Isolation requires that path to
detach and copy the full compact native byte payload. The check confirms the
copy is no larger than compact storage and never becomes a full R double
column. A second patch must stay below one compact payload, proving the detached
proxy reuses its private native storage. Direct targets do not pay the initial
detachment cost.

`Rprofmem()` reports individual R allocations. Native compact backing appears
as its raw-vector allocation, but the profiler does not measure allocator
overhead or Rust-owned memory. This benchmark is a regression gate for the two
specific promises in #86, not a process-wide peak-memory measurement.
