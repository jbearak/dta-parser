# Parquet with a dta profile, from our own reader and writer

datakit, and the Python, Julia and npm packages, read and write
Parquet files (plan 0018). A file we write is plain Parquet that every
tool opens. What Parquet cannot say goes into one JSON entry in the
file's key-value metadata, the dta profile (key `dta`): variable and
value labels, display formats, notes, characteristics, factor levels,
time zones. Each `.a` to `.z` is a null in its column, so every tool
sees a missing value, and its letter goes in a string column named
`<name>__missing`, which our readers fold back in and other tools show
as an ordinary column. The format is implemented in a new crate,
`crates/parquet`, over `crates/dta`'s `Source` and `Sink`, with small
codec crates from crates.io; `crates/dta` stays free of dependencies.

## Considered options

- **Arrow IPC (Feather).** Faster to map than to decode, but none of our
  targets can use Arrow's layout as it is (R's missing values are
  in-band), so every reader converts anyway. Fewer tools read it,
  its files are larger, and table-viewer removed an Arrow IPC source
  before release (#308).
- **`.a` to `.z` as tagged NaNs in the values**, as haven stores them in
  R. R's Parquet readers give the letters back without knowing about
  us, but SQL engines, polars and Arrow compute see a number (NaN):
  `IS NULL` and `count()` miss it and `mean()` is NaN. Integer columns
  have no NaN to tag.
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
  `docs/research/parquet-codecs.md`.

## Consequences

- The core takes its first third-party crates: `snap`, `lz4_flex`,
  `miniz_oxide`, `brotli-decompressor` and, on native targets, `zstd`
  (C libzstd); `ruzstd` on wasm. They are pinned, vendored in the R
  tarball and Python sdist, and checked by `cargo deny`.
- dtaparser's bridge registers `dtaparser_parquet_read` and
  `dtaparser_parquet_write`, and the ABI number goes from 2 to 3, so the
  three R packages are released together as 3.1.0.
- A tool that renames columns but keeps our profile can pair a letter
  column with the wrong data. Our readers check each pairing (type,
  values, letters only on null rows) and drop the letters with a warning
  when it fails; only our writers guarantee the profile matches.
- Nested columns are neither read nor written.
