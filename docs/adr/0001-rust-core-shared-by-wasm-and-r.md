# One Rust core, shared by the npm package (wasm) and dtatools (static library)

The `.dta` format is implemented once, in the dependency-free Rust crate
`crates/dta`, and exposed through a small C ABI (`crates/dta-ffi`). The
npm package compiles it to wasm32 and instantiates it synchronously from
bytes embedded in its CommonJS bundle. dtatools links it as a static
library through C glue. We chose Rust because the readers parse
untrusted files inside editors, and one source compiles to both targets.
The cost is that installing dtatools from source needs `cargo`.

## Considered options

- **Wrap ReadStat (C, MIT).** It is a push parser that walks every row in
  file order and calls back per value. It has no random access to row
  windows and no lazy strLs, which the viewers and the multi-gigabyte
  column reads need. haven's writer, which the user wants beaten on
  memory, already goes through it.
- **A C core.** R would need no extra toolchain. But bounds checks on
  every attacker-controlled length would rest on discipline, and the
  wasm build would need a clang wasm32 toolchain and a libc.
- **A TypeScript core plus a separate R implementation.** That is two
  implementations of the format, which the user asked us to avoid.
- **wasm-bindgen.** The ABI is about a dozen functions over handles and
  byte buffers. Hand-written glue is shorter to read than generated glue
  and needs no extra build tool.

## Consequences

The core does no I/O of its own. It reads through a `Source` trait
(`read_at`) and writes through a `Sink` trait. On disk (R) these are
files; in wasm, they are calls back into JavaScript, so a file never has
to fit in wasm's 4 GiB memory. Panics are caught at every FFI entry
point and returned as error statuses.
