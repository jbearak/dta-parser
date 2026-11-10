# R and TypeScript only: the Python and Julia packages are removed

Supersedes the Python and Julia parts of ADR 0034 (datakit in Python
and Julia), ADR 0036 (Python's letters as tagged NaNs), ADR 0040
(`DtaArray`), and ADR 0041 (polars in R and Python). Their decisions
for R and TypeScript stand, R's polars functions among them.

The user wrote the Python and Julia packages as experiments, and on
2026-11-09 decided to keep only what is used: R, and TypeScript for
table-viewer. The same day's measurements had put the reason for a
core of our own where it belongs. R alone could have had tagged missing
values and labels in Parquet from a thin layer over arrow (a hand-built
Arrow array keeps `.a` to `.z`; the labels are one JSON entry in the
footer), or, in an R-only format, from qs2 with no code of ours. What
the Rust core gives that those do not is one reader and writer shared
with TypeScript, partial reads, and wide survey files read at arrow's
speed on a fraction of its CPU time. Two more languages added a
binding, a test suite, a benchmark, and a CI matrix each, for no user.

**Removed**: `python/` (the `dta_parser` package and Python's
`datakit`), `julia/` (`DtaParser.jl` and `Datakit.jl`), the native C
interface in `crates/dta-ffi` that only Julia called (`native.rs`,
`parquet_native.rs`, `include/dta.h`), their CI jobs and wheels, their
benchmarks and results, and the cross-checks whose other side they
were.

**Kept**: the R packages dtaparser, datparser, datakit, and dtatools;
the npm packages `@jbearak/dta-parser` and `@jbearak/datakit`; the
crates `dta`, `dta-parquet`, `dta-arrow` (R's polars reads and writes),
and `dta-ffi` (the wasm modules). Python stays as the language of the
benchmark drivers and of the checks in which other libraries (pandas,
pyreadstat, pyarrow, polars, DuckDB) read our files or give expected
values.

## Considered options

- **Keep them, unmaintained.** They would break silently as the core
  changes, and their docs would go on promising them.
- **Move them to their own repository.** Nobody has asked for them;
  the history holds them if someone does.

## Consequences

- The last commit with the Python and Julia packages is the parent of
  this change; plans 0018 to 0027, the ADRs above, `docs/judging`, and
  `docs/research` still describe them, as the record of what was built.
- The Julia job on Windows also ran `cargo test -p dta` there; a job
  of its own, `rust-windows`, now does.
- One cross-check lost its second side: R's and Python's polars
  frames of one file (plan 0025, stage 4). R and TypeScript still check
  each other's Parquet files, fixed-width reads, and `.dta`
  categorical markers (R's from a polars frame, in Python's place).
- `compat/readback/strls.dta` and `binary.dta` were written by the
  Python writer and stay as committed inputs; nothing here regenerates
  them.
- `crates/arrow` lost what only Python called: selection by position,
  reads from a file object, and the choice of whether an Enum's levels
  go in the field metadata. `crates/dta-ffi` lost the JSON parser that
  read what Julia sent.
