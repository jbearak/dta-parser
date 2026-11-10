# The npm package @jbearak/datakit is removed

Supersedes ADR 0035 (datakit in TypeScript), the TypeScript part of
ADR 0018 (fixed-width files through release 118), the npm parts of
ADR 0033 (Parquet with a dta profile), and the part of ADR 0042 that keeps
`@jbearak/datakit`. ADR 0037 stands for `@jbearak/dta-parser`: its
`NumberColumn` holds `.a` to `.z` as tagged NaNs.

On 2026-11-10 the user decided to delete `@jbearak/datakit`, which was
never published. It had one user, table-viewer, and that user no longer
needs it: table-viewer reads Parquet through pqparser
(github.com/jbearak/pqparser), a private npm package of its own on
arrow-rs, and fixed-width text through a SAS setup file is read by
datparser (github.com/jbearak/datparser), which carries its own copy of
the reader. Keeping the package would have meant a second wasm module,
C libzstd built for wasm32, and a Parquet writer in TypeScript, all
maintained for nobody.

**Removed**: `js/datakit/` (`ParquetReader`, `readParquet`,
`saveParquet`, `readFixedWidth`, `readDta` and `saveDta` into a
`Dataset`, the `dtaparser_categorical` writer, and their tests);
`crates/dta-ffi`'s `parquet_wasm.rs` and `fixed_width_wasm.rs`, the
`wasm-parquet` feature and its dependency on `dta-parquet`, and what
only they used (`ensure_room_parts`, `json::strings`, four `Dict`
methods); `crates/dta`'s fixed-width reader (`fixed_width.rs`,
`fixed_width_to_dta` and its types, its tests and
`compat/fixed_width/`), and the writer's hidden
`long_variable_labels` option, which only it set; the checks whose other
side was TypeScript's datakit (`compat/parquet/cross_language.*`,
`categorical_marker.sh`, `readback.mjs`); the Node Parquet benchmark
(`bench/parquet/case.mjs`, `run_node.py`, `results/parquet-node.md`
and its section of `bench/RESULTS.md`); the libraries only those used
from `bench/node`; and datakit's parts of the CI and publish workflows,
`scripts/build-wasm.sh` and `scripts/js-notices.py`.

**Kept**: `@jbearak/dta-parser` (`js/`, feature `wasm-dta`), with its
shared reader types (`TableReader`, `TableInfo`'s `"parquet"`,
`BigIntColumn`, the `missing` arrays on string columns) unchanged, so
that its API does not break; R's datakit and `crates/parquet`, which
move to a repository of their own later; and the files TypeScript's
datakit wrote.

## Consequences

- There is no TypeScript writer for Parquet, nor for the
  `dtaparser_categorical` marker, in this repository. R cannot write a
  categorical holding `.a` to `.z`, so nothing here makes those files
  now.
- R's dtaparser and datakit still read the files and markers TypeScript
  wrote: `compat/parquet/legacy/ts_*.parquet` and datakit's
  `fixtures/categorical-letters*.parquet` are committed, and their tests
  run as before. `legacy/make.mjs` stays as the record of TypeScript's
  data; it runs only in a checkout of commit 408c350 or earlier, and
  `legacy/make.sh` now makes R's half alone.
- The wasm module needs no C compiler: `scripts/build-wasm.sh` builds
  one module (and its capped test build) with Rust alone, and CI no
  longer installs clang and llvm or builds `dta-parquet` for wasm32.
- `docs/typescript.md`'s examples now run in `js/`'s own docs test,
  which ran them in datakit's before.
- The last commit with `@jbearak/datakit` is the parent of this change,
  408c350. Plans 0018 to 0023, ADRs 0035 and 0037, `docs/judging`, and
  `docs/research` still describe it, as the record of what was built.
