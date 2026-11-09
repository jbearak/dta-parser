# Gate 1, round 1: plan 0021 revision 1

Judges: Claude Sonnet 5.5 (`claude-sonnet-5-5`) and GPT-6.1 Terra
(`gpt-6.1-terra`, reasoning effort high), each in a fresh session given
`brief.md`. Both returned **CHANGES**.

| question | Sonnet | Terra |
|---|---|---|
| 1. package split, two modules | sound; Rust split under-specified | reasonable; needs a concrete Rust refactor and a corrected account of peers |
| 2. `Dataset`, no frame library | right call; `readDataset` and the types do not work as written | defensible; writer compatibility and metadata need defining |
| 3. correctness risks | identity design right; fixed-width memory missing | categoricals, metadata, timestamp conversion |
| 4. tests prove it | yes, with B2's fix | mostly; add the contracts and duplicate instances |
| 5. wrong about the code | `wasm.rs`, `shared.ts`, `parquet.ts` imports | `wasm.rs` shared code, `TableReader` |

## Findings and what revision 2 did

S = Sonnet, T = Terra.

| id | finding | answer in revision 2 |
|---|---|---|
| S-B1, T3 | `parquet_wasm.rs` uses `wasm.rs`'s `State`, `call`, `copy`, `ensure_room`, `result`, `HostFile`, `HostSink`, error codes, and the allocator and error exports; a Parquet-only build would not compile | `wasm.rs` splits into `wasm_common.rs` (always on wasm32: allocator, error and result exports, host I/O, `call`, `State`'s shared fields, `test-hooks`), `wasm_dta.rs` (`wasm-dta`, its handle table) and `parquet_wasm.rs` (`wasm-parquet`, its own); each module's export list is tested against its wrappers; the native build and Julia unchanged |
| S-B2 | `shared.ts` imports `MISSING_NAMES`, `parquet.ts` imports `MISSING`; bundling them gives datakit its own `MISSING` | `MISSING`'s 27 objects are made once per process in a `globalThis` registry under `Symbol.for`, so every copy of `values.ts` (dta-parser's root and `./format` bundles, which today have separate copies, and datakit's) shares them; test with copies loaded separately |
| T4 | a peer dependency does not guarantee one instance | the registry makes identity independent of instances for 2.0 and later; a 1.x copy does not share, stated |
| S4 | importing datakit instantiates dta-parser's module | `dtaKey` and `dtaKeys` move to the `./format` entry (pure JavaScript); datakit's root imports only `@jbearak/dta-parser/format`; its `./node` loads `@jbearak/dta-parser/node` on the first call that needs it; the import-time measurement checks that a Parquet-only import compiles no `.dta` module |
| S-B3, T2 | `TableReader` has no `notes()`, `characteristics()` or list of label sets; `.dta` timestamp | `TableReader` and `AsyncTableReader` gain `notes()`, `characteristics()` and `valueLabelNames()` in 2.0 (both readers have the first two); every set is kept, used or not; `timestamp` from `info.timestamp` for `.dta`; metadata tested |
| S1, T1 | `DatasetVariable extends WriteVariable` does not type-check; a `Dataset` is not a valid input to `writeDta` | datakit has its own `DatasetVariable` and `Dataset` (the Parquet-capable write types) and `ReadDataset` for what reads return; `saveDta` is the only `.dta` boundary; the claim removed; which `WriteVariable.values` members leave dta-parser stated |
| S2 | fixed-width memory and wasm32's 4 GiB | `readFixedWidth` reads the data file straight into module memory and streams the `.dta` to a temporary file; peak stated; files past the module's room are `DTA_TOO_LARGE`; measured on the largest NSFG file |
| S3, T5 | `saveDta` rules ambiguous: unsigned types, null timestamps, units, bigint, stale markers | integers take the smallest type holding their values, as Python's `save_dta`; each timestamp unit's exact conversion in bigint arithmetic, with range and fraction errors; null is `.`; every `dtaparser_factor` characteristic in the input is dropped and markers written afresh; a test compares with Python's `save_dta` |
| T6 | every fixed-width warning kind, not only skipped statements | stated; tests for four kinds |
| T7 | size attribution not provable | sizes reported for both modules, both packages and the two together, with no attribution as a pass rule |
| S-N1 | datakit 2.0.0 as a first version; Gate 2 left open | the version rule stated; Gate 2 decided: not repeated |
| S (cut) | the Arquero and nodejs-polars recipes add a test dependency for little | one short Arquero recipe, tested; nodejs-polars named in prose only |
