# dtatools builds R objects from Rust, through C shims that contain R's errors

The plan first gave R the same C ABI as wasm, with C glue on top. Instead,
a small Rust crate in the R package (`src/rust/lib.rs`) fills R vectors
from the core's chunked reads and sets their attributes. One C file
(`src/init.c`) registers the routines. This keeps one copy of the column
data in memory, R's own vectors filled chunk by chunk, and setting
attributes in Rust stops R from duplicating a 15M-row vector to change
them. Reading 3 columns × 15.1M rows from an 11.8 GB release-115 file
takes 0.8 s at 464 MB peak RSS (page cache warm). haven takes 15.7 s and
492 MB.

R raises errors by jumping up the stack, and that must never pass through
Rust frames. So Rust calls only R functions that cannot raise
(`REAL`). Allocation, building strings and setting attributes go through
shims in `init.c`. Each shim runs its R calls under `R_UnwindProtect`,
catches the jump, and returns a status. Rust then returns normally,
dropping what it holds, and the entry point resumes R's error with
`R_ContinueUnwind`. Each object Rust makes is stored at once into an
object R can already reach, so Rust never needs `PROTECT`. Strings are
built a chunk at a time in one protected call. Between chunks the reader
asks R, through `R_ToplevelExec`, whether the user pressed Ctrl-C.

## Considered options

- **A C ABI shared with wasm.** It needs a buffer outside R for each
  column, which doubled peak memory in the slice.
- **extendr.** It solves the same problems but brings a large dependency
  and macros. The bridge here is about 300 lines.

Since ADR 0015, the bridge and the packed string columns live in
dtaparser, which dtatools imports.
