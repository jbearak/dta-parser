# Parquet with a dta profile, from our own reader and writer

datakit, and the Python, Julia and npm packages, read and write
Parquet files (plan 0018). A file we write is plain Parquet that every
tool opens. What Parquet cannot say goes into one JSON entry in the
file's key-value metadata, the dta profile (key `dta`): variable and
value labels, display formats, notes, characteristics, factor levels,
time zones. `.` is a null. `.a` to `.z` are tagged NaNs in DOUBLE
columns: the bit pattern R uses for them (haven's tagged NA), so R's
own Parquet readers give the letters back too, and a numeric column
holding them is written as DOUBLE with its storage type in the profile. The format is implemented in a new crate,
`crates/parquet`, over `crates/dta`'s `Source` and `Sink`, with small
codec crates from crates.io; `crates/dta` stays free of dependencies.

## Considered options

- **Arrow IPC (Feather).** Faster to map than to decode, but none of our
  targets can use Arrow's layout as it is (R's missing values are
  in-band), so every reader converts anyway. Fewer tools read it,
  its files are larger, and table-viewer removed an Arrow IPC source
  before release (#308).
- **`.a` to `.z` as nulls, with the letters in a string column**
  (`<name>__missing`) that our readers fold back in. This was the first
  design, approved at Gate 1: every tool, SQL engines included, sees a
  missing value. The user chose tagged NaNs instead (2026-11-04): R
  already holds `.a` to `.z` that way, our readers decode the bits in
  every language, and tagged NaNs cost nothing to write or read and
  need no extra column to name, match and validate. The cost is that
  DuckDB SQL, polars and Spark see `.a` to `.z` as NaN, not null
  (`IS NULL` is false, `count()` counts them, `mean()` is NaN). The
  writers' `missing_letters = FALSE` writes plain nulls for files meant
  for those tools.
- **Letters in the footer**, per column chunk. Invisible to other tools,
  but lost by any tool that rewrites the file, and the footer grows
  with the data.
- **An Arrow extension type (a struct of value and code).** pandas round
  trips it; polars and DuckDB see a struct, not a number.
- **R's `serialize()` in the metadata**, as arrow does for attributes.
  R only, lossy for NaN payloads, and the route of CVE-2024-52338.
- **The `parquet` crate from arrow-rs.** Mature and complete, but
  without its Arrow layer it turns dictionary codes into one value per
  row, so R would make a string per row rather than per distinct value;
  with that layer, every column passes through Arrow arrays before the
  language's own vectors. Measurements are in
  `docs/research/parquet-codecs.md`. It is also larger in the npm
  package: our whole wasm module with Parquet reading and writing and
  every codec (C libzstd included) is 2,238,567 bytes, 432,503
  compressed with brotli
  (quality 11), against parquet-wasm's 456 KB brotli-compressed for a
  read-only build without codecs (its README); without Parquet the
  module was 349,363 bytes, 92,056 with brotli.

## Consequences

- The core takes its first third-party crates: `snap`, `lz4_flex`,
  `miniz_oxide`, `brotli-decompressor` and `zstd` (C libzstd, which in
  the npm package's wasm module needs a clang that targets wasm32 to
  build). They are pinned, vendored in the R
  tarball and Python sdist, and checked by `cargo deny`.
- dtaparser's bridge registers `dtaparser_parquet_read` and
  `dtaparser_parquet_write`, and the ABI number goes from 2 to 3, so the
  three R packages are released together as 3.1.0.
- In DuckDB SQL, polars and Spark, `.a` to `.z` in our files are NaN
  values, not nulls. The docs say so, with the query that treats them
  as missing.
- Nested columns are neither read nor written.
