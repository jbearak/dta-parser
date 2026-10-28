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

The wasm module holds at most 2^20 rows of the columns being read at a
time, so its memory stays bounded however large the file is. A wasm trap
(which should not happen: damaged files give errors) would leave the module
unusable for the life of the process.
