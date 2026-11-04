# Parquet and Arrow readers and writers for R and Julia

Question: what do the existing Parquet (and Arrow IPC) readers and writers
for R and Julia offer, how do they treat what `dtaparser::read_dta()`
returns, and what should datakit's Parquet reader and writer, and the
Python, Julia and TypeScript libraries that match it, copy or avoid?

Read and measured 2026-11-04 on macOS arm64. R 4.6 (Homebrew, source
packages only), Julia 1.13.3. Versions looked at: arrow 26.0.0,
nanoparquet 0.5.2, duckdb 2.0.0, haven 2.5.5, data.table 1.18.6.1,
fst 0.9.8, qs2 0.4.0, r-polars (docs site, `main`); the Julia versions
are in the Julia section. R package source comes from the CRAN
tarballs; paths are relative to each package's root. "Observed" means
we ran it here, on data we made (`dtaparser::with_labels()`,
`haven::labelled()`, factors, dates). No Stata, Stata files or Stata
documentation were used.

## What has to survive

`read_dta()` (`r/dtaparser/R/read_dta.R`, `labelled.R`) returns a
tibble of: labelled numbers (class `c("dtaparser_labelled",
"vctrs_vctr")` over a double or integer, attributes `labels`, `label`
and sometimes `format`); `.a` to `.z` in doubles as haven's tagged NAs
(R's NA bits, low word 1954, with the letter in the payload:
`r/dtaparser/src/init.c:233`); factors, Date, POSIXct in UTC; plain
columns with optional `label` and `format`; and tibble attributes
`label` and `notes`. A Parquet file can hold these in its key-value
metadata, in `ARROW:schema`'s field metadata and extension types, or,
for the letters, in the bits of a non-null DOUBLE; a null has no payload.

## The short version

| | arrow (R) | nanoparquet | duckdb | Parquet2.jl | Arrow.jl |
|---|---|---|---|---|---|
| Parquet read / write | yes / yes | yes / yes | yes / yes (SQL) | yes / yes | no (IPC only) |
| column selection | tidyselect | names or indices | SQL | lazy columns | lazy columns |
| rows | datasets API or row groups | none | `WHERE`, `LIMIT` | row groups | record batches |
| threads | yes | no | yes | column-parallel | threaded writes |
| value labels | kept, R-only metadata | dropped | dropped | `LabeledArray` an error | not from DataFrames |
| variable / dataset labels | kept, R-only `r` key | dropped | dropped | column-chunk metadata | only if passed |
| `.a` to `.z` | lost (null) | lost (null) | lost | lost | lost |
| factor / categorical | kept | kept, unordered | character | write error | kept, unordered |
| time zone | kept | always UTC | dropped | dropped | kept |
| license | Apache-2.0 | MIT | MIT | MIT | Apache-2.0 |

Round trip of one tibble with both labelled classes, factors, Dates,
POSIXct in UTC and America/New_York, column `label` and `format`, and
dataset `label` and `notes` (observed):

| written by → read by | labels and class | tagged NA letters | var / dataset labels, `format`, `notes` | ordered factor | tz |
|---|---|---|---|---|---|
| arrow → arrow | kept | lost (plain NA, also inside `labels`) | kept | kept | kept |
| arrow → nanoparquet | plain double | lost | dropped | plain factor | UTC |
| arrow → duckdb | plain double | lost | dropped | character | UTC |
| nanoparquet → nanoparquet | plain double | lost | dropped | plain factor | UTC |
| nanoparquet → arrow | plain double | lost | dropped | kept | UTC |
| duckdb → arrow | plain double | lost | dropped | character | none (local) |

No writer keeps `.a` to `.z`: R's `ISNA()` is true for a tagged NA, so
arrow and nanoparquet write a null
([apache/arrow#49149](https://github.com/apache/arrow/issues/49149),
open). The readers do keep NaN bits, though. We wrote a file whose
DOUBLE holds the bytes of `tagged_na("r")` (`a2 07 00 00 72 00 f0 7f`)
as a non-null value: arrow, nanoparquet and DuckDB in R gave back a
value whose `haven::na_tag()` is `"r"`, and Parquet2.jl and DuckDB.jl
gave a NaN with the same bits. The cost: DuckDB calls it NaN, not NULL
(`x IS NULL` false, `isnan(x)` true), as will any engine that tells NaN
from null.

## R: arrow 26.0.0

Apache-2.0. Bindings to the Arrow C++ library; Parquet support is
Arrow C++'s parquet-cpp.

### Read

- `read_parquet(file, col_select = NULL, as_data_frame = TRUE,
  props = ParquetArrowReaderProperties$create(), mmap = TRUE, ...)`.
  `ParquetArrowReaderProperties$create(use_threads = option_use_threads())`.
- `col_select` is tidyselect: bare names, strings, `starts_with()` and
  so on. A character vector held in a variable works but tidyselect
  warns that `all_of()` is wanted
  ([apache/arrow#38890](https://github.com/apache/arrow/issues/38890)).
  dtaparser already special-cases this (`read_dta.R`).
- **No row arguments.** For rows there are two routes:
  `ParquetFileReader$create(file)` with `$ReadRowGroup(i, column_indices)`
  and `$ReadRowGroups(...)` (0-based), or
  `open_dataset(path) |> filter(...) |> head(n) |> collect()`, which
  pushes the filter down to row-group statistics.
- Returns a tibble (since arrow 13 even when a plain `data.frame` was
  written, by design:
  [apache/arrow#44524](https://github.com/apache/arrow/issues/44524)),
  or an Arrow `Table` with `as_data_frame = FALSE`.
- Types back to R
  ([data types article](https://arrow.apache.org/docs/r/articles/data_types.html)):
  strings to character through ALTREP (each string made on first use);
  dictionary to factor, ordered kept; date32 to Date; timestamp to
  POSIXct in the schema's zone, or with no `tzone` when the file has
  none (observed); int64 to integer when all values fit, else
  `bit64::integer64` (`arrow.int64_downcast = FALSE` forces it); uint64
  and decimal to double; lists to `arrow_list`; structs to data frames.
- Schema without data: `ParquetFileReader$create(f)$GetSchema()`,
  `$num_rows`, `$num_row_groups`, `$num_columns`. The R API does not
  show column-chunk statistics or encodings; Python's does.

### Write

- `write_parquet(x, sink, chunk_size = NULL, version = "2.4",
  compression = default_parquet_compression(), compression_level = NULL,
  use_dictionary = NULL, write_statistics = NULL, data_page_size = NULL,
  use_deprecated_int96_timestamps = FALSE, coerce_timestamps = NULL,
  allow_truncated_timestamps = FALSE)` (`R/parquet.R:154`).
- Defaults: snappy, set in R to match pyarrow (`R/parquet.R:208`);
  dictionary encoding with fallback to PLAIN; statistics on; 1 MiB
  pages; page v1 (observed); format 2.4. The codec, level, dictionary
  and statistics arguments take one value or a vector named by column.
  `chunk_size = NULL` means the whole table under 250 million cells
  (`R/parquet.R:629`), but Arrow C++ caps row groups at 1,048,576 rows
  (observed).
- Types: double to DOUBLE, integer to INT32, character to STRING, factor
  to dictionary STRING (marked in `ARROW:schema`), Date to DATE, POSIXct
  to TIMESTAMP(MICROS, UTC) with the zone in `ARROW:schema`, `NA` to
  null, NaN kept as NaN with its payload (observed).
- Labelled columns: a vctrs vector arrow does not know becomes extension
  type `arrow.r.vctrs`, holding the zero-length prototype as
  `serialize(ptype, NULL, ascii = TRUE)` (`R/extension.R:505`,
  `R/type.R:91`). `haven_labelled` and `dtaparser_labelled` come back
  whole, except that ASCII serialization turns a tagged NA inside
  `labels` into plain `NA` (observed).

### Metadata

- Attributes of the data frame and its columns, less those arrow maps
  itself (class, levels, tzone: `remove_attributes()`,
  `R/metadata.R`), go under key `r` as `serialize(..., ascii = TRUE)`
  text, gzipped when large
  ([metadata article](https://arrow.apache.org/docs/r/articles/metadata.html)).
  Dataset `label` and `notes`, column `label` and `format` came back
  (observed). Only R reads `r` or the `arrow.r.vctrs` prototype; the
  article says pandas ignores it, and DuckDB, nanoparquet and Julia
  readers gave plain doubles.
- Reading it once ran `unserialize()` on file contents:
  [CVE-2024-52338](https://nvd.nist.gov/vuln/detail/CVE-2024-52338),
  code execution from a crafted file, arrow 4.0.0 to 16.1.0, fixed in
  17.0.0. Now only basic types are kept, with a warning
  (`safe_r_metadata`, `R/metadata.R:86`), unless
  `options(arrow.unsafe_metadata = TRUE)`.
- Double attributes such as POSIXct lose precision in the ASCII form
  ([apache/arrow#51695](https://github.com/apache/arrow/issues/51695));
  wide files with per-column attributes read slowly
  ([apache/arrow#34319](https://github.com/apache/arrow/issues/34319)).

### Performance

- Multithreaded decoding (`options(arrow.use_threads)`,
  `set_cpu_count()`, `set_io_thread_count()`); memory-mapped input by
  default (`mmap = TRUE`); strings converted lazily through ALTREP;
  `open_dataset()` scans files bigger than memory, and partitioned
  directories.
- Measured here (5 million rows: an id, two doubles, an integer, a Date,
  a 3-value string, a unique 10-byte string): arrow wrote in 1.9 s
  (108 MB), nanoparquet in 0.8 s (113 MB). arrow's read returned in
  0.07 s (0.21 s on one thread), but the first `nchar()` over the unique
  strings then took 1.25 s; nanoparquet read in 1.0 s, `nchar()` 0.06 s.
  arrow by codec: 149 MB uncompressed, 108 MB snappy, 80 MB zstd, 72 MB
  gzip; writes 1.7 to 1.8 s (gzip 34 s); reads 1.3 s with any codec.
- Published: nanoparquet's
  [benchmark article](https://nanoparquet.r-lib.org/articles/benchmarks.html)
  (nanoparquet 0.5.1, arrow 23.0.1.2, duckdb 1.5.2, Apple Silicon,
  arrow's ALTREP off). On 67 million rows (8.1 GB): read arrow 4.8 s /
  17.6 GB peak, duckdb 5.3 s / 18.8 GB, nanoparquet 5.9 s / 14.1 GB;
  write duckdb 14.8 s / 12 GB, nanoparquet 15.6 s / 4 GB, arrow 19 s /
  2.7 GB. On 337,000 rows nanoparquet read fastest (21 ms vs 26 and 40).

### Errors

- Unknown column: tidyselect's "Can't select columns that don't exist"
  (class `vctrs_error_subscript_oob`). Truncated or non-Parquet file:
  "Parquet magic bytes not found in footer. Either the file is corrupted
  or this is not a parquet file." Every codec is built in (`arrow_info()`).
  Page checksums cannot be turned on from R
  ([apache/arrow#53138](https://github.com/apache/arrow/issues/53138)).

### Feather / Arrow IPC

`read_feather(file, col_select = NULL, as_data_frame = TRUE, mmap =
TRUE)`; `write_feather(x, sink, version = 2, chunk_size = 65536L,
compression = c("default", "lz4", "lz4_frame", "uncompressed", "zstd"),
compression_level = NULL)`, `"default"` being lz4. Same metadata rules.

### Documentation

Good: a vignette per task (files, data types, metadata, datasets);
every default documented; per-column vectors explained. Weak: no way
shown to read the first n rows of one file without datasets; the
metadata article says haven labels survive but not that tagged NAs do
not; the time-zone example prints UTC while the text says the zone is
kept. Install is heavy without binaries (libarrow), and broken builds
have shipped without Parquet
([apache/arrow#40667](https://github.com/apache/arrow/issues/40667)).

## R: nanoparquet 0.5.2

MIT. Gábor Csárdi (Posit), from Hannes Mühleisen's miniparquet; no
dependencies; vendors snappy, zstd, miniz, thrift and flatbuffers
(`inst/COPYRIGHTS`).

### Read

- `read_parquet(file, col_select = NULL, options = parquet_options())`.
  `col_select` is a character vector of names or numeric indices, no
  tidyselect; repeats are an error; result in `col_select` order.
- **No rows.** [#48](https://github.com/r-lib/nanoparquet/issues/48)
  ("Read a subset of rows") is open; whole columns are read into memory.
- Returns class `c("tbl", "data.frame")`, not a tibble
  ([#144](https://github.com/r-lib/nanoparquet/issues/144)).
- Strings are made while reading (no ALTREP). Dictionary columns are
  factors only if `ARROW:schema` says so, and come back unordered
  (observed). TIMESTAMP is POSIXct in UTC whatever the schema says
  ([#140](https://github.com/r-lib/nanoparquet/issues/140)); INT64 is
  double unless `read_int64_type = "integer64"`; DECIMAL is double; LIST
  a list (since 0.5.0); unannotated BYTE_ARRAY `blob::blob`.
- `parquet_options(class = "tbl", compression_level = NA_integer_,
  read_int64_type = "double", keep_row_groups = FALSE,
  num_rows_per_row_group = 122880L, use_arrow_metadata = TRUE,
  write_arrow_metadata = TRUE, write_data_page_version = 1L,
  write_minmax_values = TRUE)`, each default read from an
  `options(nanoparquet.*)` option first.
- Without data: `read_parquet_info(file)` (rows, columns, row groups,
  size, `created_by`); `read_parquet_schema(file, options)` (Parquet
  type, logical type, and the R type it will read as);
  `read_parquet_metadata(file, options)` (tables of file metadata,
  schema, row groups and column chunks with codec, encodings and
  min/max); `edit_parquet_metadata()` edits key-value pairs in place.

### Write

- `write_parquet(x, file, schema = NULL, compression = c("snappy",
  "gzip", "zstd", "uncompressed"), encoding = NULL, metadata = NULL,
  row_groups = NULL, options = parquet_options())`; `append_parquet()`
  with the same arguments adds rows without rewriting the file.
  `file = ":raw:"` returns a raw vector; `":stdout:"` writes to standard
  output.
- Defaults: snappy; gzip level 6 and, documented, zstd level 3 (but see
  below); 122,880 rows per row group, to match DuckDB; data page v1;
  min/max statistics on; `ARROW:schema` written.
- Encodings (`?"parquet-encodings"`): factors RLE_DICTIONARY; logicals
  RLE when the first 10,000 values average runs of 15 or more; other
  columns RLE_DICTIONARY when two thirds of the values repeat, else
  PLAIN. `encoding` overrides by column, but only PLAIN, RLE_DICTIONARY
  and RLE can be written.
- Types (`?"nanoparquet-types"`): integer to INT(32), double to DOUBLE,
  character to STRING (`enc2utf8()`), factor to STRING marked in
  `ARROW:schema`, Date to DATE, POSIXct to TIMESTAMP(MICROS, UTC) with
  the zone dropped, hms, difftime, integer64, blob and simple lists.
  `schema = parquet_schema(...)` overrides per column (INT8, FLOAT,
  DECIMAL, ENUM, UUID ...); `infer_parquet_schema(df)` previews the
  mapping. Other vector types are an error.
- Labelled columns: a `haven_labelled` or `dtaparser_labelled` is a
  double underneath, so it is written as DOUBLE and its labels and label
  are dropped without a warning (observed).
- `metadata` adds key-value strings, but `read_parquet()` does not give
  them back as attributes. The maintainer declined that in
  [#84](https://github.com/r-lib/nanoparquet/issues/84): only R would see
  them, and serializing arbitrary R objects into files is unsafe. The
  feature requests [#145](https://github.com/r-lib/nanoparquet/issues/145)
  and [#165](https://github.com/r-lib/nanoparquet/issues/165) are open.

In 0.5.2, `compression = "zstd"` without a level writes at zstd level
-1, not the documented 3, so the file is barely smaller than an
uncompressed one (observed: 22.50 MB vs 22.50 MB uncompressed, 9.51 MB
with `compression_level = 3`). The default-setting code compares the
codec's number with `"zstd"` (`R/write-parquet.R:148`). Already fixed
upstream by [r-lib/nanoparquet#177](https://github.com/r-lib/nanoparquet/pull/177)
(merged 2026-10-05), not yet on CRAN.

### Performance

Single-threaded, reads the selected columns into memory, no memory
mapping. Lowest peak memory of the R Parquet readers in its own
benchmark, and fastest on small files (numbers under arrow above).

### Errors

"Column nope does not exist in Parquet file"; "Unvalid (too large)
column selected" (sic) for a bad index; "Compression is not supported
yet" for brotli or lz4, naming neither codec nor column; "No trailing
magic bytes, invalid Parquet file at '<path>' @ lib/ParquetReader.cpp:85"
for a truncated file.

### Documentation

Good: a README with install, read, schema-first, write and limitations
up front; pages mapping every type both ways and every encoding. Weak:
the README still says nested types are unsupported (LIST came in
0.5.0); nothing says labels and attributes are dropped, or how to read
part of a big file.

## R: duckdb 2.0.0

MIT. Took several minutes to compile from source here (no binaries for
Homebrew R).

- Read: `dbGetQuery(con, "SELECT a, b FROM 'f.parquet' WHERE a = 1
  LIMIT 10")`; projection and filter pushdown, 16 threads here by
  default. `read_parquet()` options
  ([DuckDB 2.0 docs](https://duckdb.org/docs/2.0/data/parquet/overview.html))
  include `file_row_number`, `hive_partitioning`, `union_by_name`,
  `schema` and, new in 2.0, `bound_schema` and `utf8_validation`.
  Dictionary columns come back as character, timestamps as POSIXct in
  UTC (observed).
- Metadata: `parquet_metadata()` (per column chunk: encodings, codec,
  min/max), `parquet_schema()`, `parquet_kv_metadata()` (raw vectors in
  R, observed).
- Write: `COPY t TO 'f.parquet' (FORMAT parquet, COMPRESSION zstd,
  ROW_GROUP_SIZE 100000, PARQUET_VERSION V2, KV_METADATA {k: 'v'})`;
  default snappy. Observed: page v1, PLAIN for doubles and dates,
  RLE_DICTIONARY for a factor, which is a plain string in the file; no
  `ARROW:schema`; POSIXct as TIMESTAMP without a zone; labels and
  attributes dropped.
- Errors: "Binder Error: Referenced column "nope" not found in FROM
  clause! Candidate bindings: ...", naming the closest columns: the most
  helpful message here.

## R: polars

MIT; installed from R-multiverse rather than CRAN; not installed here
([site](https://pola-rs.github.io/r-polars/)). `pl$scan_parquet(source,
..., n_rows = NULL, row_index_name = NULL, parallel = c("auto",
"columns", "row_groups", "prefiltered", "none"), use_statistics = TRUE,
low_memory = FALSE, missing_columns = c("raise", "insert"), ...)` gives
a lazy frame; `$collect()` then `as.data.frame()` brings it into R. Worth
noting: `n_rows` on the reader. The docs say nothing on R attributes.

## R: neighbouring APIs (ergonomics only)

| function | columns | rows | other |
|---|---|---|---|
| `haven::read_dta(file, encoding = NULL, col_select = NULL, skip = 0, n_max = Inf, .name_repair = "unique")` | tidyselect | `skip`, `n_max` | MIT |
| `haven::write_dta(data, path, version = 14, label = attr(data, "label"), strl_threshold = 2045, adjust_tz = TRUE)` | | | dataset label as an argument defaulting to the attribute |
| `fst::read_fst(path, columns = NULL, from = 1, to = NULL, as.data.table = FALSE)` | names | `from`, `to` | `fst(path)` gives a lazy table, `metadata_fst(path)` the schema; `write_fst(x, path, compress = 50, uniform_encoding = TRUE)`; AGPL-3 |
| `qs2::qd_read(file, use_alt_rep, validate_checksum, nthreads)` / `qd_save(object, file, compress_level, shuffle, warn_unsupported_types, nthreads)` | whole object | whole object | defaults come from `qopt()`; checksums; GPL-3 |
| `data.table::fread(..., nrows = Inf, skip = "__auto__", select = NULL, drop = NULL, colClasses = NULL, integer64 = "integer64", nThread = getDTthreads(), tz = "UTC")` | `select`, `drop` | `skip`, `nrows` | `fwrite(..., compress = c("auto", "none", "gzip"), compressLevel = 6L, nThread = ...)`; MPL-2.0 |

The pattern users know from haven, readr and fst is one function with
`col_select` (or `columns`) and `skip`/`n_max` (or `from`/`to`), and a
separate cheap function for the schema. arrow and nanoparquet both lack
rows on the main function.

## Julia

Tested on Julia 1.13.3 in a scratch depot: Parquet2.jl 0.2.37, Parquet.jl
0.8.6, Arrow.jl 2.8.1, DuckDB.jl 2.0.0, ReadStatTables.jl 0.4.0
(DataFrames 1.8.2, CategoricalArrays 1.1.1, TimeZones 1.22.4).

Our binding (`julia/DtaParser/src/column.jl`) keeps `.a` to `.z` as a
`DtaColumn{T} <: AbstractVector{Union{Missing,T}}`: values plus a
`UInt8` code per row (0 a value, 1 `.`, 2 to 27 `.a` to `.z`), `missing`
on indexing, `stata_code()` for the letter. Labels, formats and notes
are DataAPI metadata of `:note` style (`table.jl`), so `DataFrame(t)`
keeps them. Every library below turns the letters into plain `missing`.

### Parquet2.jl 0.2.37 (MIT)

Pure Julia, [GitLab](https://gitlab.com/ExpandingMan/Parquet2.jl),
[docs](https://expandingman.gitlab.io/Parquet2.jl/); one maintainer,
last release September 2026, 21 of 63 issues open.

- **Read.** `Parquet2.Dataset(path_or_io_or_bytes; support_legacy = true,
  use_mmap = true, mmap_shared = true, load_initial = nothing,
  parallel_column_loading = nothing, ...)` (alias `readfile`) reads only
  the footer; per-column options (`lazy_dictionary = true`,
  `use_statistics = false`, `allow_string_copying = false`, ...) take a
  value, a NamedTuple or a Dict. It is a lazy Tables.jl source:
  `DataFrame(ds; copycols = false)`, `Parquet2.load(ds, "col")`,
  `ds |> Parquet2.select(:a, :b)`. Rows only as whole row groups
  (`ds[i]`).
- **Types read.** Int64 exact; strings as `StringRefVector` into the
  memory map; dictionary columns as `PooledVector` (R arrow's
  dictionary-encoded numbers too); NaN payloads kept (our tagged-NA file
  gave bits `0x7ff00072000007a2`); DATE as `Date`; every TIMESTAMP as a
  UTC `DateTime`, zone ignored, sub-millisecond units cut through Float64
  (`schema.jl:185`); DECIMAL as `DecFP.Dec64`. A nested column anywhere
  makes `Dataset` fail even when not selected
  ([#55](https://gitlab.com/ExpandingMan/Parquet2.jl/-/issues/55)).
- **Write.** `Parquet2.writefile(path_or_io, tbl; metadata = Dict(),
  propagate_table_metadata = true, npages = 1, compression_codec =
  :snappy, column_metadata = Dict(), compute_statistics = false,
  json_columns = false, bson_columns = false, propagate_col_metadata =
  true)`; `FileWriter` streams. One row group per `Tables.partitions`
  partition, one page per column; no compression level; dictionary only
  for `DataAPI.refpool` vectors; page v1 only. Pages over 2 GiB fail
  ([#41](https://gitlab.com/ExpandingMan/Parquet2.jl/-/issues/41),
  [#56](https://gitlab.com/ExpandingMan/Parquet2.jl/-/issues/56)).
- **Types written** (`schema.jl:233-300`): Date as INT32 DATE without the
  legacy converted type (DuckDB 2.0 then reads plain Int32 days);
  DateTime as TIMESTAMP(MILLIS, not UTC-adjusted), via Float64
  (`write.jl:409`), so 2,977 of 200,000 random 1900 to 1995 times came back
  1 ms early; `Union{Missing,T}` as OPTIONAL. CategoricalArray,
  ZonedDateTime and ReadStatTables' `LabeledArray` are errors.
- **Metadata.** File key-value pairs from `metadata=` and
  `DataAPI.metadata(tbl)` (values `string()`-ed); column metadata in each
  column chunk's `key_value_metadata`. `metadata!`/`colmetadata!` round-
  trip into `DataFrame(ds)`, but R arrow saw only the file key.
  `ARROW:schema` is neither written nor read.
- **Errors.** `KeyError: key "nope" not found`; truncated:
  `invalid parquet: final bytes are ..., expect "PAR1"`.
- **Performance.** Memory map, lazy columns, threads across columns; no
  published figures. Here (5M rows, 5 columns, 4 threads): write 0.37 s
  (1.3 GB allocated), read to a DataFrame 0.09 s.
- **Docs.** Clear on install, all or some columns, metadata; rows only by
  row group; nothing on dates, time zones, labels or missing values.

### Parquet.jl 0.8.6 (MIT)

[JuliaIO/Parquet.jl](https://github.com/JuliaIO/Parquet.jl), last release
August 2025; the README points to Parquet2.jl and DuckDB.jl.
`read_parquet(path; rows, filter, batchsize, use_threads,
column_generator)`, `Parquet.File(path)` for the schema,
`write_parquet(path_or_io, tbl; compression_codec = "SNAPPY")` (PLAIN,
numbers, Bool and String only; no metadata,
[#170](https://github.com/JuliaIO/Parquet.jl/issues/170)). Every R arrow
26 and DuckDB file failed (`KeyError: key 7 not found`, an outdated
Thrift definition: [#189](https://github.com/JuliaIO/Parquet.jl/issues/189)),
and on 1.13 non-null columns came back as garbage. Not a usable
reference.

### Arrow.jl 2.8.1 (Apache-2.0)

[apache/arrow-julia](https://github.com/apache/arrow-julia); IPC only,
Parquet declined in [#410](https://github.com/apache/arrow-julia/issues/410).
`Arrow.Table(file; convert = true)` memory-maps and gives zero-copy lazy
columns; `Arrow.Stream` iterates batches; `Arrow.getmetadata()` and
DataAPI `metadata`/`colmetadata` for reading. `Arrow.write(io, tbl;
compress = nothing (or :lz4, :zstd), alignment = 8, dictencode = false,
denseunions = true, largelists = false, metadata = Arrow.getmetadata(tbl),
colmetadata = nothing, ntasks, ...)` writes partitions on threads. Date,
DateTime, ZonedDateTime and CategoricalArray get `JuliaLang.*` extension
types; `ordered = true` is lost. A DataFrame's `metadata!`/`colmetadata!`
are not written unless passed explicitly
([#337](https://github.com/apache/arrow-julia/issues/337)). An R haven
column arrives as `arrow.r.vctrs` with a warning and plain Float64s. A
truncated file silently gave 0 rows, and a Parquet file a 0×0 table. A
3.0 rewrite is an open PR
([#609](https://github.com/apache/arrow-julia/pull/609)).

### DuckDB.jl 2.0.0 (MIT)

`DataFrame(DBInterface.execute(db, "SELECT ... FROM 'f.parquet' WHERE
... LIMIT ..."))` opened every file (nested, decimals, DELTA,
BYTE_STREAM_SPLIT); TIMESTAMPTZ came back as a UTC `DateTime`; NaN
payloads kept. No DataAPI or `ARROW:schema` support;
`register_data_frame` fails on a CategoricalArray. Clear errors.

### ReadStatTables.jl 0.4.0 (MIT)

[junyuan-chen/ReadStatTables.jl](https://github.com/junyuan-chen/ReadStatTables.jl):
`readstat(path; usecols = nothing, row_limit = nothing, row_offset = 0,
ntasks = nothing, apply_value_labels = true, ...)`. A labelled column is
a `LabeledArray` with `labels::Dict{K,String}`; for `.dta`,
`K = Union{Char,Int32}`, so a label on a tagged missing value is keyed
by its letter (`'r' => "Refused"`). Variable labels and formats are
DataAPI column metadata; only `label`, `vallabel`, `file_label` and
`notes` are `:note` style. `.a` and `.r` in the data become plain
`missing` (a TODO in `parser.jl:199-220`). `Arrow.write` turns a
labelled column into a dictionary of value-plus-label-map structs and
drops the metadata; Parquet2 refuses it.

### What this means for Julia

Parquet2 is the only usable pure-Julia Parquet library, and it lacks
DELTA and BYTE_STREAM_SPLIT, nested types, time zones and `ARROW:schema`.
A Rust core behind our binding would beat all of these. No Julia
library reads `ARROW:schema`, so labels belong in file-level key-value
metadata too. Write the legacy converted types (DATE, TIMESTAMP_*)
beside the logical types.

## Codecs and encodings

Key: R = reads, W = writes by default, w = writes on request, no = not
supported. Sources: Apache Parquet's
[implementation status](https://parquet.apache.org/docs/file-format/implementationstatus/)
page for arrow C++ (behind R arrow) and DuckDB, nanoparquet's
`?"parquet-encodings"` and `?write_parquet`, and the Julia section; we
checked the defaults by reading back the files each writer made.

| | arrow (R) | nanoparquet | duckdb | Parquet2.jl |
|---|---|---|---|---|
| snappy | R W | R W | R W | R W |
| gzip | R w | R w | R w | R w |
| zstd | R w | R w | R w | R w |
| lz4_raw | R w (`"lz4"`) | no | R w | R |
| lz4 (Hadoop, deprecated) | R | no | no | no |
| brotli | R w | no | R w | R w |
| PLAIN | R W | R W | R W | R W |
| RLE_DICTIONARY / PLAIN_DICTIONARY | R W | R W | R W | R W (pooled vectors only) |
| RLE (booleans, levels) | R W | R W | R W | R W |
| DELTA_BINARY_PACKED | R w | R | R w | no |
| DELTA_LENGTH_BYTE_ARRAY | R w | R | R w | no |
| DELTA_BYTE_ARRAY | R w | R | R w | no |
| BYTE_STREAM_SPLIT | R w | R | R w | no |
| data page v2 | R w | R w | R w | R (code path, untested) |
| default data page | v1 | v1 | v1 | v1 |
| default row group | 1,048,576 rows | 122,880 rows | 122,880 rows | one per table partition |

For arrow, "w" on the DELTA, BYTE_STREAM_SPLIT and page v2 rows means
Arrow C++ can write them; R's `write_parquet()` can only switch
dictionary encoding on or off (nothing else in `R/parquet.R` or
`src/parquet.cpp`). The same page lists the Rust `parquet` crate
(arrow-rs), which a Rust core could build on, as reading and writing every
row, Hadoop LZ4 included.

## Lessons for our design

### API ideas worth adopting

- **One read function shaped like `read_dta()`.** `col_select`
  (tidyselect, with dtaparser's `all_of()` handling), `skip`, `n_max`,
  `factors`, `dates`. No R Parquet reader has rows on its main function,
  and haven, readr, fst and data.table users expect them. Footer row
  counts let `skip` pass whole row groups without decoding them.
- **A cheap schema call that says what each column will become**, as
  `nanoparquet::read_parquet_schema()` does, plus file info and the
  labels, without reading data.
- **Per-column settings by named vector**, as arrow's `compression =
  c(x = "zstd")` and nanoparquet's `encoding` (with `""` for the rest).
  Few arguments, defaults documented in one place; not global
  `options()`, which make a script's output depend on the session.
- **Defaults.** zstd or snappy (snappy is everyone's default; zstd
  level 3 made a file 26% smaller than snappy here at the same read
  time, and every working reader above reads it); dictionary encoding
  when values repeat; page v1; statistics on; row groups near 122,880
  rows or a byte budget, so DuckDB, arrow and polars read in parallel.
  Write `ARROW:schema` so arrow and pyarrow restore factors, Dates and
  zones, and the legacy converted types for older readers.
- **Labels every language can read.** One namespaced key-value entry of
  JSON with value labels (code, text, letter for `.a` to `.z`, as
  ReadStatTables keys them), variable labels, formats, dataset label and
  notes, copied per column into `ARROW:schema` field metadata. Never R
  `serialize()`: R-only, the route of CVE-2024-52338, and lossy for NaN
  payloads and doubles. If we read arrow's `r` key as a fallback, accept
  only basic types and never `unserialize()` untrusted input.
- **Errors that name the column and codec**, like DuckDB's "Candidate
  bindings"; not nanoparquet's "Compression is not supported yet".
- **Writing to memory and appending** (nanoparquet's `":raw:"`,
  `append_parquet()`): cheap from a Rust core, useful for npm.

### Extended missing values: the real choice

No existing writer keeps `.a` to `.z`, yet every working reader keeps them
if the file stores them as non-null NaNs with the tag in the payload. That
leaves two designs:

1. **Payload in the value.** The DOUBLE column holds haven's bit pattern;
   R readers (arrow, nanoparquet, DuckDB) give back tagged NAs without
   knowing about us, and Parquet2.jl and DuckDB.jl keep the bits. But SQL engines, polars and Arrow compute treat the
   value as NaN, not null: `IS NULL`, `count(x)` and `null_count` miss
   it, and `mean()` returns NaN.
2. **Null in the value, letter beside it.** The value is null (so every
   tool sees a missing value) and the letter goes in a sibling column
   (for instance `x` plus a dictionary-encoded `x.missing`), or in the
   JSON metadata as row positions for sparse cases. Our reader puts the
   letters back; other readers lose only the reason.

Option 2 is the safer default for a file meant for other tools; option 1
could be an opt-in for R-to-R exchange. Integer codes with `.a` to `.z`
have no NaN to carry a payload, so they need option 2 anyway.

### Pain points users hit

- Labels and attributes dropped without a word: nanoparquet
  ([#84](https://github.com/r-lib/nanoparquet/issues/84),
  [#145](https://github.com/r-lib/nanoparquet/issues/145),
  [#165](https://github.com/r-lib/nanoparquet/issues/165)), DuckDB,
  Parquet2's unsupported types, Arrow.jl's DataFrame metadata
  ([#337](https://github.com/apache/arrow-julia/issues/337)). Write them,
  and when something cannot be kept, warn once naming the columns, as
  `read_dta()` does for factors.
- Tagged NAs turned into plain NA
  ([apache/arrow#49149](https://github.com/apache/arrow/issues/49149)).
- Time zones ignored (nanoparquet
  [#140](https://github.com/r-lib/nanoparquet/issues/140), Parquet2,
  DuckDB's writer) and ordered factors unordered (nanoparquet, Arrow.jl).
- The returned class surprises: arrow gives a tibble for a data frame
  ([apache/arrow#44524](https://github.com/apache/arrow/issues/44524)),
  nanoparquet `"tbl"` without `tbl_df`
  ([#144](https://github.com/r-lib/nanoparquet/issues/144)).
- tidyselect warns on a character vector in `col_select`
  ([apache/arrow#38890](https://github.com/apache/arrow/issues/38890)).
- Wide files with per-column R metadata read slowly
  ([apache/arrow#34319](https://github.com/apache/arrow/issues/34319)):
  keep metadata compact and parse it once.
- Silent failures: Arrow.jl returns 0 rows for a truncated file; arrow R
  cannot check page checksums
  ([apache/arrow#53138](https://github.com/apache/arrow/issues/53138)).
  Fail loudly on a bad footer, page or checksum.
- `arrow::read_parquet()` and `nanoparquet::read_parquet()` share a name,
  so attaching both masks one (it caught us here). Pick names that do
  not collide, or document `datakit::`.
- Heavy installs: libarrow; DuckDB compiling for minutes from source.
  One small Rust library is an advantage worth keeping.
- Deferred strings move cost, they do not remove it (arrow: 0.07 s read,
  then 1.25 s on first use). Benchmarks should time a first use.

### For Julia

Make the Julia reader return DataAPI metadata of `:note` style, as
DtaParser does, keep `.a` to `.z` in `DtaColumn` codes, and key labels on
missing values by letter as ReadStatTables does. Return `Date`,
`DateTime` and, where the file has a zone, `ZonedDateTime`, which no
Julia Parquet reader does today.

## Licenses

All are compatible with GPL-3.0 for study and credit.

| project | version | license | note |
|---|---|---|---|
| arrow (R) | 26.0.0 | Apache-2.0 | compatible with GPL-3.0 (not with GPL-2.0-only) |
| nanoparquet | 0.5.2 | MIT | vendored snappy, zstd, miniz, thrift, flatbuffers under their own permissive licenses (`inst/COPYRIGHTS`) |
| duckdb (R and Julia) | 2.0.0 | MIT | |
| polars (R) | docs | MIT | |
| haven | 2.5.5 | MIT | bundles ReadStat (MIT) |
| data.table | 1.18.6.1 | MPL-2.0 | GPL-compatible through MPL's secondary-license clause; copied files stay MPL |
| fst | 0.9.8 | AGPL-3 | **Flag.** It may be combined with GPL-3.0 code (GPL-3.0 section 13), but copied code keeps AGPL's network clause; study only, copy nothing |
| qs2 | 0.4.0 | GPL-3 | |
| Parquet2.jl | 0.2.37 | MIT | |
| Parquet.jl | 0.8.6 | MIT | |
| Arrow.jl | 2.8.1 | Apache-2.0 | |
| ReadStatTables.jl | 0.4.0 | MIT | |
| Apache Parquet format docs | |  Apache-2.0 | |
