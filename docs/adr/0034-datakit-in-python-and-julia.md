# datakit in Python and Julia; Parquet stays in the npm package

ADR 0032 split R's format package (dtaparser) from its data-prep package
for translated do-files (datakit). Plan 0019 makes the same split in
Python and Julia: Parquet reading and writing and `read_fixed_width`
leave dta_parser and DtaParser.jl for a datakit package in each
(`python/datakit`, distribution `dta-datakit`, import `datakit`;
`julia/Datakit`). The format packages keep `.dta` and its
representation, and the native code: datakit calls the format package's
native module, as R's datakit does through `R_GetCCallable`, behind an
ABI number each checks at load. Each datakit has `read_parquet`,
`read_parquet_info`, `save_parquet` and `read_fixed_width`, and none has
`:=` or another Stata-style helper; polars' `when/then/otherwise` and
DataFrames.jl's `transform!` are how those languages assign.

**Python's datakit returns polars, with labels beside the frame.**
`df, meta = read_parquet(path)` gives a `polars.DataFrame`, in which
`.` and `.a` to `.z` are all null, and a `Meta` dataclass holding the
data label, notes, each column's variable label, display format and
value label set, and the sets. polars has no frame or column metadata,
and its extension types would carry labels through operations but
reject `==`, arithmetic and casts unless unwrapped at each use, and are
unstable. `save_parquet(df, path, meta=meta)` writes `meta` into the
dta profile (ADR 0033), so files go between R, Python and Julia
unchanged. The letters are kept one of two ways: in `meta.missing`, a
Series of `dk.LETTERS` (a polars Enum) per column, aligned with the
rows as read (the default), or in a companion column `x_letter` in the
frame (`letters="columns"` for every column that can hold a letter, a
list of names, or `letters_to_columns` later), which follows its rows
through row-preserving operations (filter, sort, join, concat) and is
what a translator generates. `save_parquet` refuses positional letters for a
column whose values changed since the read, by a digest kept in
`meta`; it cannot see rows exchanged that hold equal values, so the
docs lead with companion columns for code that changes rows.
Because its frames are polars and dta_parser's are pandas, Python's
datakit also has `read_dta` and `save_dta`.

**Julia's datakit returns a DataFrame.** Labels are `colmetadata` and
`metadata` with style `:note`, under the keys `DtaTable` uses.
`.a` to `.z` stay in the frame: a column holding them is DtaParser's
`DtaColumn`, an `AbstractVector{Union{Missing,T}}` that reads every
missing code as `missing` and keeps the codes through indexing,
`filter`, `sort`, `subset`, and `groupby` with `select` or `transform`
of the column as is; `vcat`, `combine` and functions over the
column build plain vectors, in which the letters become `missing`.

**TypeScript has no datakit.** table-viewer needs one synchronous
`TableReader` over `.dta` and Parquet, built on the npm package's
column classes and wasm module; a second package would reach into the
first's wasm exports or ship a second copy of the core. No translator
targets TypeScript. So Parquet stays in `@jbearak/dta-parser`.

## Considered options

- **Python: pandas with `attrs`**, as dta_parser 0.2 did. The
  translator writes polars, and `attrs` were lost after a groupby
  aggregation.
- **Python: polars extension types** holding labels and letters in the
  dtype. They survive filter, sort, join, concat and a Parquet round
  trip, but `==`, arithmetic, `mean`, `fill_null` and casts reject them
  without `.ext.storage()`, and polars marks them unstable.
- **Python: letters as tagged NaNs in Float64 columns.** They would
  follow every row operation, but polars counts NaN as a value, so
  `is_null()`, `mean()` and `count()` would be wrong for `.a` to `.z`.
- **Python: only companion columns, no `meta.missing`.** Correct
  through every operation, but every frame read would carry columns
  the user did not ask for; it is one argument away instead.
- **Python: only `meta.missing`.** Positional letters go stale after
  any row operation, and no check can prove they still line up.
- **Python and Julia: their own native builds.** Two Rust builds per
  language for one core; R rejected it in ADR 0016.
- **Python: keep pandas Parquet beside polars.** Two APIs, two sets of
  docs and benchmarks, for a translator that uses one.
- **TypeScript: an npm datakit.** See above.

## Consequences

- dta_parser and DtaParser lose `read_parquet`, `write_parquet`,
  `read_fixed_width`, and `read_meta` for Parquet, and become 0.3.0;
  dta-datakit and Datakit start at 0.3.0 and require 0.3 of them.
- Installing dta-datakit installs pandas through dta-parser, though
  importing it does not load pandas.
- dta_parser's native module and DtaParser's library still hold the
  Parquet code and codecs, which only datakit calls.
- dta_parser's native module gains functions that decode into Arrow
  memory and read it, for polars' PyCapsule interface.
- A pandas user of dta_parser 0.2's Parquet functions converts with
  `df.to_pandas()`, losing `.a` to `.z` in the frame (they stay in
  `meta`); `docs/migration.md` says so.
- Nothing is published; the names on PyPI and in the Julia registry
  are the user's choice when they publish.
