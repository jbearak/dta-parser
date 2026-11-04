# Parquet compatibility: fixtures and readback

Two checks for `crates/parquet` (plan 0018):

- **Fixtures** (`fixtures/`): small Parquet files written by other tools
  from data the scripts here make. `expected/` holds what pyarrow reads
  from each, as JSON. `crates/parquet/tests/compat.rs` reads every
  fixture with dta-parquet, whole and in row windows, on one thread and
  on four, and compares.
- **Readback**: files dta-parquet writes (from data made in
  `crates/parquet/tests/support/mod.rs`) are read by pyarrow, pandas,
  polars, DuckDB, arrow (R) and nanoparquet, and their values and types
  checked against what the writer was given and against plan 0018's
  table "What other tools see in our files".

No file here comes from Stata or from any dataset; every value is made by
the scripts.

## Fixtures

| file | writer | what it covers |
|---|---|---|
| `pyarrow_default.parquet` | pyarrow, defaults | snappy, dictionary and PLAIN, data page v1 |
| `pyarrow_v2_pages.parquet` | pyarrow, `data_page_version="2.0"` | data page v2 |
| `pyarrow_gzip.parquet` | pyarrow, `compression="gzip"` | gzip |
| `pyarrow_small_pages.parquet` | pyarrow, zstd, 200-row row groups, 1 KiB pages, `write_page_index=True` | row groups, many pages, an offset index |
| `pyarrow_plain.parquet` | pyarrow, `use_dictionary=False`, no compression | PLAIN only, uncompressed |
| `pyarrow_nested.parquet` | pyarrow, defaults | a list, a struct and a map among flat columns, which are not read |
| `polars_default.parquet` | polars, defaults | zstd, polars' encodings |
| `polars_zstd.parquet` | polars, zstd, statistics, 250-row row groups | row groups, polars' offset index |
| `duckdb_default.parquet` | DuckDB `COPY ... (FORMAT parquet)` | PLAIN_DICTIONARY, DuckDB's timestamps |
| `arrow_r_default.parquet` | arrow (R) `write_parquet`, defaults | factors, zoned `POSIXct`, list of raw |
| `nanoparquet_default.parquet` | nanoparquet `write_parquet`, defaults | nanoparquet's encodings |

The Python fixtures hold 8-, 16-, 32- and 64-bit integers, floats and
doubles (with NaN and -0.0), booleans, text (repeated and distinct),
bytes, dates, timestamps in milliseconds, microseconds and nanoseconds
(UTC, a zone, and local) and a dictionary column, each with nulls. The R
fixtures hold R's types: integer, double, logical, character, `Date`,
`POSIXct` with a zone, factor and (arrow only) a list of raw vectors.

To regenerate, from the repository root:

    python3 compat/parquet/make_fixtures.py    # pyarrow, polars, DuckDB
    Rscript compat/parquet/make_fixtures.R     # arrow, nanoparquet
    python3 compat/parquet/expected.py         # pyarrow reads them all

The fixtures were written with pyarrow 26.0.1, polars 2.1.0, DuckDB
2.0.0, arrow (R) 26.0.0 and nanoparquet 0.5.2.

## Readback

    cargo run -p dta-parquet --example samples -- DIR
    python3 compat/parquet/readback.py DIR     # pyarrow, pandas, polars, DuckDB
    Rscript compat/parquet/readback.R DIR      # arrow, nanoparquet

`samples` writes every type with nulls, `.a` to `.z`, categoricals
(ordered and not, with an unused level) and time zones; the same in each
codec; 5,000 rows in five row groups of small pages; an empty table;
`.a` to `.z` in a byte, an int, a long, a float and a double column,
beside `.` and a NaN value, written once as tagged NaNs and once with
`missing_letters` off; the same for a date and three timestamps (a zone,
an instant without one, a local time in nanoseconds), which are written
as days and seconds since 1970 in DOUBLE columns, with `logical` in the
profile; and 5,000 columns with 50 label sets of 1,000
labels. Each script checks every
value, that the `dta` key is in the file's metadata, and these cells of
plan 0018's table:

| ours | pyarrow / pandas | polars | DuckDB | arrow (R) | nanoparquet |
|---|---|---|---|---|---|
| `.a` to `.z` | pyarrow: NaN, not null, in a `double` column, with the storage or logical type in the profile; pandas: missing (`isna()`) | NaN, not null (`null_count()` leaves them out) | NaN, not NULL: `count()` counts them, and `x IS NULL OR isnan(x)` finds every missing value | tagged NA, letter kept (`haven::na_tag()`) | tagged NA, letter kept |
| categorical | `dictionary<..., ordered>` with every level in order; pandas `category`, ordered kept | `Categorical` | VARCHAR | factor (ordered kept), every level | factor, every level, never ordered |
| zoned timestamp | tz-aware, our zone | our zone | TIMESTAMP WITH TIME ZONE | `POSIXct` in our zone | `POSIXct` in UTC |
| INT(8), INT(16) | int8, int16 (pandas: float64 with nulls) | Int8, Int16 | TINYINT, SMALLINT | integer | integer |

Results with pyarrow 26.0.1, pandas 3.1.1, polars 2.1.0, DuckDB 2.0.0,
arrow (R) 26.0.0 and nanoparquet 0.5.2: every check passes, with these
differences from plan 0018's table, none of which is a bug in
those tools:

- nanoparquet 0.5.2 reads our categoricals as factors with our levels
  (from `ARROW:schema`), not as character as the table says; it does not
  keep whether they are ordered.
- nanoparquet 0.5.2 does not read LZ4_RAW ("Compression is not supported
  yet"), so the readback skips that file for it.
- A table with no rows has no row groups, so no dictionary pages: other
  tools see its categoricals with no levels. Ours read them from the
  profile.

## Credits

The fixtures were written with, and the expected values read by, these
open-source projects:

- [Apache Arrow](https://arrow.apache.org/) (pyarrow and the arrow R
  package), Apache-2.0
- [polars](https://pola.rs/), MIT
- [DuckDB](https://duckdb.org/), MIT
- [nanoparquet](https://github.com/r-lib/nanoparquet), MIT
- [pandas](https://pandas.pydata.org/), BSD-3-Clause, for the readback
- [haven](https://haven.tidyverse.org/), MIT, for the readback's tagged NAs
