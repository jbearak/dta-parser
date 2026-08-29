---
status: accepted
---

# Parallelize native-backed DTA observations

`save_dta()` bulk-encodes fixed-width observations when every column exposes immutable native storage and parallelizes sufficiently large multi-column blocks. The common writer retains row ordering and checks each completed block, while inputs that require an R callback or `strL` planning use the scalar serial path. This supersedes ADR-0007's serial-writer decision because per-cell dispatch made otherwise direct writes roughly nine times slower than Stata.

The writer uses a bounded 64 MiB observation block and assigns disjoint columns and output byte ranges to each worker. It flushes and closes the sibling file before atomic replacement but does not force it to durable storage; the public contract does not promise crash durability, and Stata's timed `save` has no equivalent durability barrier.
