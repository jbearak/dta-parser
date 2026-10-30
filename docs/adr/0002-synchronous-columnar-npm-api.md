# The npm API is synchronous and reads columns

All three TypeScript consumers need synchronous reads: manuscript-markdown's
embed pipeline is synchronous, and table-viewer decodes rows synchronously.
So the npm package compiles its wasm module synchronously at load time, from
bytes embedded in the CommonJS bundle, and reads files through `fs.readSync`.
Reads are columnar (`readColumns` returns typed arrays per variable), and
`readRows` is a thin wrapper over them, so there is one read path.

## Considered options

- **Async with an AbortSignal.** Sight cancels long whole-column reads. Our
  reads are fast enough (15M rows × 3 columns from an 11.8 GB file in about
  2 s), so a consumer that wants to yield can read row ranges in a loop and
  check its own signal between them.
- **Row objects from wasm.** That would mean one boundary crossing per cell.
  Typed arrays cost one copy per column.

## Consequences

Each call into the wasm module stops after the row at which its decoded
output reaches 64 MiB (or at 2^20 rows), so module memory is bounded by
that plus one row, however wide the read or large the strLs. A wasm trap
should not happen, because damaged files give errors. If one does, the
glue replaces the module instance, and readers opened on the old instance
report themselves closed.

## Note: Node 24 (plan 0008)

From 1.0 the package requires Node 24 or later. That is a policy, not a
technical need: the build also runs on Node 18. Node 26 is the current
release, and VS Code runs extensions on Node 24 from 1.123. Nothing may
depend on a Node 26-only feature until VS Code ships Node 26.
docs/research/node-24.md records what each version offers.
