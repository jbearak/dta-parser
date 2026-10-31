# Node 24: what it allows the npm package

The npm package requires Node 24 or later from 1.0 (plan 0008). This
note records what Node 24 (V8 13.6) and Node 26 (V8 14.6) offer that
could make reads faster or use less memory, and what we did with each,
so the decisions can be revisited.

Measured on an M4 Max, October 2026. Each feature was probed directly:
a minimal script per feature, run under each Node version, that either
compiles and runs a small module using it or checks the API exists.

| feature | Node 24 | Node 26 | decision |
|---|---|---|---|
| wasm memory64 (more than 4 GiB of module memory) | yes | yes | Not adopted. Rust's `wasm64-unknown-unknown` is a tier 3 target: nightly Rust and `-Zbuild-std` only. Every memory access would also pay a bounds check. Plan 0008's memory work removes the cases measured to reach the 4 GiB ceiling. Revisit when the target is stable. |
| `wasm:js-string` builtins | yes | yes | Not usable. They build JavaScript strings from wasm GC arrays, which Rust does not produce. |
| `using` and `Symbol.dispose` | yes | yes | Adopted: `DtaReader[Symbol.dispose]` calls `close()`. |
| `WebAssembly.Memory.prototype.toResizableBuffer` | no | yes | Not relied on: Node 26 only. |
| `Uint8Array.fromBase64` | no | yes | Not relied on: Node 26 only. |
| wasm SIMD128 (`-C target-feature=+simd128`) | yes | yes | Not adopted. In Node since 16; reads measured 1–3% faster, within run-to-run noise. |

Neither version makes string creation itself cheaper. The large string
read gains in plan 0008 come from making fewer strings: one decode per
call and `substring` per cell, or a dictionary of distinct values.

## Which Node consumers run

Measured by the Sight thread:

- VS Code 1.123 (Electron 42, Node 24.15) is the first release whose
  extension host runs Node 24. 1.111 to 1.122 run Node 22; 1.144 runs
  Node 24.22.1.
- The 1.0 package also runs on Node 18.20.8. It fails on Node 16.20.2,
  whose wasm compiler rejects the reference-types feature newer Rust
  emits. Requiring 24 is therefore a policy, not a technical need.
- VS Code does not ship Node 26, so nothing in the package may depend on
  a Node 26-only feature.
