# dtatools builds R objects from Rust, not through a C ABI

The plan was to give R the same C ABI as wasm, with C glue on top. Instead,
a small Rust crate in the R package (`src/rust/lib.rs`) calls R's C API
directly, through about fifteen declared functions. It fills R vectors
from the core's chunked reads and sets their attributes there. One C file
registers the routines and raises R errors after Rust has returned.

This keeps one copy of the column data in memory: R's vectors, filled
chunk by chunk, and not also a C-ABI buffer. Setting attributes in Rust
also stops R from duplicating a 15M-row vector to modify it. Reading 3
columns × 15.1M rows from an 11.8 GB release-115 file takes 0.9 s and
463 MB peak RSS. haven takes 15.7 s and 492 MB.
