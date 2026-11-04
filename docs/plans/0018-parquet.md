# Plan: Parquet files that keep what a `.dta` file says, in four languages

Status: approved at Gate 1 by Claude Sonnet and GPT Terra (revision 7,
after seven rounds; see `docs/judging/parquet-design/`).

## Goal

The user asked for a reader and writer in datakit built on Parquet or
Arrow, with matching libraries for TypeScript, Julia and Python, and
then read-write support in table-viewer. Four requirements:

1. **Ergonomics.** Its API and documentation should be better than the
   other Parquet and Arrow readers and writers for R, Python, Julia and
   TypeScript, and stay under revision until Claude Sonnet and GPT
   Terra both say so.
2. **Speed.** It should be at least as fast as comparable readers and
   writers. Wall time and peak RSS are the targets. A lower wall time
   must not cost a disproportionate amount of extra CPU time.
3. **Study and credit.** Study the other libraries whose licenses are
   compatible with GPL-3.0, and credit them.
4. **Delivery.** A sequence of PRs, each taken to merge.

The research behind this plan is in `docs/research/parquet-r-julia.md`,
`parquet-python.md`, `parquet-typescript.md` and `parquet-codecs.md`.
They cover arrow, nanoparquet, duckdb, Parquet2.jl, Parquet.jl,
Arrow.jl, pyarrow, pandas, polars, fastparquet, hyparquet,
hyparquet-writer, parquet-wasm and apache-arrow, each at a recorded
version, with measurements.

## What is missing elsewhere

None of those libraries does what a do-file translated to R needs from
the file it saves:

- **`.a` to `.z` are lost by every writer.** arrow (R) and nanoparquet
  turn haven's tagged NAs into plain nulls (apache/arrow#49149).
  ReadStatTables, Parquet2 and Arrow.jl turn them into `missing`, and
  pandas cannot write them.
- **Labels survive only within one language, if at all.** arrow puts
  value labels and other R attributes into the file through R's
  `serialize()`. No other language can read that, and it was the route
  of CVE-2024-52338. pandas 2.1 and later write `df.attrs` as JSON and
  read it back, but only into pandas: JSON turns numeric label codes
  into strings, cannot hold `StataArray` missing codes, loses
  per-column attributes, and took 24 s instead of 0.66 s to write a
  frame with 5,000 entries; polars and DuckDB ignore it. nanoparquet,
  DuckDB, polars and every Julia library drop labels without a warning.
- **No main read function takes a row range.** arrow needs its dataset
  API, nanoparquet's request for it (r-lib/nanoparquet#48) is still
  open, pyarrow and pandas have neither skip nor limit, and polars has
  only a limit.
- **Readers lose data quietly.** Converting Arrow to pandas doubles the
  memory used (pyarrow peaked at 1,330 MB to read a 384 MB table, and
  fastparquet at 524 MB). hyparquet turns timestamps into millisecond
  `Date`s. parquet-wasm's synchronous reader ignores `columns`.
  nanoparquet drops time zones, and nanoparquet and Arrow.jl drop
  whether a factor is ordered.

Our `.dta` readers already return labels, missing codes and dates in
each language's own types. This plan gives Parquet files the same
treatment, so that a Parquet file can stand in for a `.dta` file: faster
and smaller, readable by every Parquet tool, and still read back by us
with everything the `.dta` file said. It is also a general Parquet
reader and writer for **flat tables**, with the losses it makes stated
per type and per language.

**Scope: flat tables.** The goal is survey and analysis tables, which
are flat, and table-viewer shows flat tables. Nested columns (lists,
maps, structs) are not read or written. A file that has them can still
be read for its flat columns (see "What we read"). The docs say this in
the first paragraph of `docs/parquet.md`, so a user who needs nested
data knows to use arrow, pyarrow or polars.

## Parquet, not Arrow IPC

We write and read Parquet. Arrow IPC (Feather) is not part of this
plan.

- Parquet is the format other tools exchange: DuckDB, polars, Spark,
  pandas, arrow and nanoparquet all read and write it. Arrow IPC is read
  by fewer of them.
- Parquet files are compressed and split into row groups. The footer
  gives each row group's row count and byte ranges, so `skip` and
  `n_max` can pass over whole row groups without reading them, and
  threads can decode column chunks in parallel. A viewer can read a
  window of rows by reading only the pages that hold it.
- Arrow IPC is faster to decode when it is memory-mapped and read
  without conversion. But none of our targets (R vectors, numpy and
  pandas, Julia vectors, JavaScript typed arrays) can use Arrow's
  layout as it is: R's missing values, for example, are in-band. Every
  reader has to convert anyway. Decoding Parquet straight into the
  target's memory gives up little and keeps the size advantage.
- table-viewer added read-only Arrow IPC tables (#306) and removed them
  before release (#308). Its notes record two problems: dictionaries
  had to be decoded before their size was known, and whole buffers
  were decompressed at once. Parquet's footer gives every chunk's
  compressed and uncompressed size before anything is decoded.

## The file: plain Parquet, plus a profile

A file we write is ordinary Parquet that every reader opens. What
Parquet cannot say goes into one key-value entry in the file metadata,
the **dta profile**, under the key `dta`, as JSON. Readers that do not
know the key still get every value, with nulls for plain missing
values and tagged NaNs for `.a` to `.z` (below); "What other tools
see" lists what they lose.

### Column types we write

| what we write | Parquet physical type | logical type (and converted type) |
|---|---|---|
| Stata byte; 8-bit integer | INT32 | INT(8, signed) |
| Stata int; 16-bit integer | INT32 | INT(16, signed) |
| Stata long; R integer; 32-bit integer | INT32 | none |
| 64-bit integer (Python, Julia, TypeScript `BigIntColumn`) | INT64 | none |
| Stata float; 32-bit float | FLOAT | none |
| Stata double; R double; 64-bit float | DOUBLE | none |
| logical, bool | BOOLEAN | none |
| text (strN, strL, R character, pandas `str`/`object` of text) | BYTE_ARRAY | STRING (UTF8) |
| binary strL, R list of raw, Python `bytes`, Julia `Vector{UInt8}` | BYTE_ARRAY | none |
| a strL column mixing text and binary values (Python, Julia, TypeScript) | BYTE_ARRAY | none; every value reads back as binary |
| R `Date`, a Python `datetime64` column written as a date (below), Julia `Date` | INT32 | DATE |
| a zoned time: R `POSIXct`, pandas `datetime64[unit, tz]`, Julia `ZonedDateTime` | INT64 | TIMESTAMP(unit, adjusted to UTC) |
| a clock time without zone: pandas `datetime64[unit]`, Julia `DateTime`, Stata `%tc` read as a time | INT64 | TIMESTAMP(unit, not adjusted to UTC) |
| categorical: R factor, pandas `category`, Julia `CategoricalArray`, TypeScript `DictionaryColumn` | BYTE_ARRAY, always dictionary-encoded, with the levels as the dictionary | STRING; levels and ordering in the profile |

- **Categoricals.** The dictionary page of every row group holds all
  the levels, unused ones included, in level order, so the codes are the
  level numbers and every row group has the same dictionary. That is
  what lets pyarrow and polars (through `ARROW:schema`) restore the
  levels in our order. Categoricals never fall back to PLAIN.
- **Python dates.** A `datetime64` column whose `attrs["dta"]` format is
  a `%td` format (as `read_dta` gives a Stata date) is written as DATE;
  every other `datetime64` is TIMESTAMP in its own unit, as pandas
  writes it. The type never depends on the values. A `%td` column with
  a time zone or a value that is not midnight is an error naming the
  column and the first such row, saying to drop the format from
  `attrs["dta"]` to write it as a timestamp; a test covers it.
- **Units.** R `POSIXct` (seconds in a double) and Julia `DateTime`
  (milliseconds) write MICROS and MILLIS. pandas writes the frame's own
  unit: MILLIS for `[ms]` and `[s]`, MICROS for `[us]`, NANOS for
  `[ns]`. The profile records `"unit": "s"` where Parquet has no such
  unit, so `[s]` reads back as `[s]`.
- **R's `POSIXct`** is always an instant. One without a `tzone`
  attribute is written as adjusted to UTC, and the profile records that
  it had no zone, so it reads back without one.
- The converted types are written too, because older readers, and
  DuckDB 2.0 for dates, rely on them. Every column is OPTIONAL
  (nullable), as arrow and pandas write them.
- A Stata date (`%td`) or datetime (`%tc`) that the language has already
  converted (R's `Date`, Python's `datetime64`) is written as DATE or
  TIMESTAMP. One still held as a number with its display format is
  written as that number, with the format in the profile. Either way it
  reads back as the type it was written from.
- **`ARROW:schema`** is written too, so that pyarrow, polars and arrow
  (R) read our categoricals as dictionaries (factors in arrow,
  `Categorical` in polars, `category` in pandas, ordered where ours
  was) and our zones on timestamps. It holds no labels: those stay in
  the profile.

### Missing values

- `.` and every other plain missing value is a Parquet null.
- `.a` to `.z` are written as **tagged NaNs**: the bit pattern R uses
  for them in doubles (haven's tagged NA, and what dtaparser returns).
  It is R's `NA_real_` (`0x7FF00000000007A2`) with the letter's ASCII
  code in bits 32 to 39. R already widens an integer column that holds
  `.a` to `.z` to double, and a FLOAT cannot carry the pattern, so any
  numeric column holding them is written as DOUBLE, and the profile
  records its storage type (`"storage": "byte"`, `"int"`, `"long"` or
  `"float"`) for the readers that keep it (Python, Julia, TypeScript).
  Columns without `.a` to `.z` keep their own type.
- A date or timestamp column holding `.a` to `.z` is written as DOUBLE
  too, the way R's `Date` and `POSIXct` hold it: a date as days since
  1970-01-01, a timestamp as seconds since 1970-01-01 00:00 (fractions
  as near as a double holds them), with the profile entry
  `"logical": "date"` or `"timestamp"` and the timestamp's `tz` as it
  would have been. Our readers turn these back into dates and
  timestamps; other tools see doubles. 64-bit integers (which a double
  cannot hold exactly) and booleans cannot hold `.a` to `.z`: a letter
  in either is an error unless `missing_letters` is false. `read_dta()`
  never returns such a column, so every frame it returns can be
  written.
- A reader decodes a DOUBLE value as `.a` to `.z` only when its bits are
  exactly that pattern with a letter `a` to `z`; any other NaN is NaN.
  Our readers read the bits from the file, so this works the same in
  every language, whatever that language does with NaN payloads.
- **What it costs.** Nothing extra to write or read. But tools that
  treat NaN as a value see `.a` to `.z` as NaN: in DuckDB SQL, polars
  and Spark, `IS NULL` is false for them, `count(x)` counts them and
  `mean(x)` is NaN. arrow (R), nanoparquet and DuckDB in R return them
  as tagged NAs, and pandas reads them as missing. The user chose this
  over a design that wrote them as nulls with the letters in a separate
  string column (correct in every tool, but more to write, read and
  validate); see ADR 0033. The docs give the query that treats them as
  missing in those tools (`x IS NULL OR isnan(x)` in DuckDB,
  `is_null() | is_nan()` in polars).
- The writers take `missing_letters` (default true). Set to false, they
  write `.a` to `.z` as plain nulls, for files meant for SQL engines or
  polars; the letters are then lost.
- NaN is a value, not a missing value, in every language whose doubles
  tell NaN from a missing value (R's `NaN`, Julia's `NaN`). In pandas a
  float64 `NaN` is the missing value and is written as null.

### The profile

```json
{
  "version": 1,
  "label": "Smoking survey, 2024",
  "notes": ["Wave 2 only."],
  "characteristics": {"_dta": {"note0": "1"}, "age": {"source": "q12"}},
  "sort": ["id"],
  "timestamp": "2024-03-01T09:30:00",
  "columns": {
    "age":    {"label": "Age in years", "format": "%9.0g",
               "value_labels": "agelbl", "storage": "byte"},
    "region": {"categorical": {"levels": ["North", "South", "West"], "ordered": false}},
    "seen":   {"format": "%tdCCYY-NN-DD"},
    "when":   {"tz": "America/New_York"},
    "stamp":  {"unit": "s"}
  },
  "value_labels": {
    "agelbl": [[97, "Refused"], [".d", "Don't know"]]
  }
}
```

- Keys are column names. A reader ignores entries for names the file
  does not have, so a file that another tool rewrote after dropping or
  renaming columns still reads.
- Value labels are arrays of `[code, text]`. A code is a JSON number or
  a missing code written as text (`"."`, `".a"` ... `".z"`). Arrays keep
  numeric codes as numbers, which a JSON object's keys would not. A
  numeric code must be finite and, if it is an integer, within ±2^53,
  so that JavaScript reads it exactly; a writer given any other code
  stops with an error naming it. Stata's codes are 32-bit integers, so
  every `.dta` label fits.
- `categorical.levels` keeps the order and the levels no row uses,
  which a dictionary page does not.
- Storage types are not repeated where Parquet's type says it: INT(8)
  is byte, INT(16) is int, INT32 is long, FLOAT is float, DOUBLE is
  double. `storage` appears only on a DOUBLE column written wider
  because it holds `.a` to `.z`. So does `logical` (`"date"` or
  `"timestamp"`), on a date or timestamp column written as DOUBLE for
  the same reason. A reader drops either key, with one warning, from a
  column that is not DOUBLE, or when its value is not one it knows. A
  string column
  becomes strN or strL when it is written to `.dta`, from its widest
  value, as it does today.
- `timestamp` keeps the `.dta` file's time stamp where a language
  carries one (Python and Julia do); a `.dta` file's release, byte order
  and text encoding describe that file, not the data, and are not kept.
- **Validation.** `version` is 1. A reader that finds a higher version
  reads what it knows and warns once. The profile must be a JSON object
  of at most 64 MiB, with no duplicate keys at any level, and each
  entry of the shape above. An entry that breaks a rule (a label set
  that is not a list of pairs, a duplicate code in a set, a `levels`
  list with duplicates, a `value_labels` name with no set) is dropped
  with one warning naming it; the rest of the profile is used. A
  profile that is not JSON at all, too large, or not an object gives
  one warning, and the file is read as plain Parquet. Damaged metadata
  is never an error, since the values are intact. Tests cover each
  rule.

### What other tools see in our files

| ours | pyarrow / pandas | polars | DuckDB | arrow (R) | nanoparquet |
|---|---|---|---|---|---|
| value labels, variable labels, formats, notes | lost (profile ignored) | lost | lost | lost | lost |
| `.a` to `.z` | missing (pandas reads NaN as missing); pyarrow sees NaN | NaN, not null | SQL: NaN, not NULL; DuckDB in R: tagged NA (letter kept) | tagged NA (letter kept) | tagged NA (letter kept) |
| categorical | `category` (ordered kept) | `Categorical` | VARCHAR | factor | character |
| zoned timestamp | tz-aware, our zone | our zone | TIMESTAMPTZ | `POSIXct` in our zone | `POSIXct` in UTC |
| INT(8), INT(16) | int8, int16 (float64 if the column has nulls, since we write no `pandas` key) | Int8, Int16 | TINYINT, SMALLINT | integer | integer |

The compat suite checks every cell of this table, and the docs carry it.

### What we write

- **Encodings.** Categoricals as above. Dictionary encoding
  (RLE_DICTIONARY) for any other column chunk while its dictionary
  stays under 1 MiB and smaller than 60% of the values it replaces,
  checked on the first page; past either limit the rest of the chunk is
  PLAIN. Definition levels are RLE. No DELTA or
  BYTE_STREAM_SPLIT encodings: fastparquet cannot read them, and
  Parquet2 does not.
- **Pages.** Data page v1, which every reader reads, at about 1 MiB
  uncompressed. An offset index (page locations) lets a reader go
  straight to the pages that hold a window of rows, for each column,
  without reading the pages before them. table-viewer reads many small
  windows. pyarrow does not write the index by default; our reader walks
  page headers when it is absent (below), and PR 2 measures both ways
  on a window read.
- **Compression.** `zstd` level 3 by default, `snappy`, `gzip`,
  `lz4_raw` or `none` on request, with `compression_level` where the
  codec has levels. In `parquet-codecs.md`, zstd 3 through C libzstd
  made DHS data a quarter the size of snappy's output, writing at 2.6
  GB/s and reading at 3.7 GB/s, against snappy's 4.3 and 4.4. polars and
  DuckDB also default to zstd. On one thread, compressing and writing a
  gigabyte to a 1 GB/s disk takes 0.41 s with zstd and 0.32 s with
  snappy, so zstd's smaller files cost write time unless the columns are
  compressed in parallel, as ours are. PR 3 measures writes end to end
  with both codecs; if zstd by default misses a write target there, the
  default becomes snappy, and `docs/parquet.md` records why.
- **The npm package** has no C libzstd. It writes zstd with the
  pure-Rust `ruzstd`, which has one level and compresses less (0.060 of
  the input against 0.022), and reads zstd at a quarter of libzstd's
  speed. So it writes **snappy by default**, and zstd only when asked,
  with that cost in its docs; it reads zstd files from the other
  languages at about 1 GB/s.
- **Row groups.** As many rows as fit in about 64 MiB of uncompressed
  values, at most 262,144 rows (polars' default) and at least 1 row, so a
  row group stays bounded in bytes even when each row is wide. Callers
  can set `row_group_size` in rows. Benchmarks check that DuckDB and
  polars read our files no slower than their own default output.
- **Statistics.** Minimum, maximum and null count for each column chunk,
  with `column_orders` set, so DuckDB and polars can use them. Floating
  point follows the format's rules: NaN is left out, a chunk of only NaN
  and nulls has no minimum or maximum, and a zero extreme is written as
  `-0.0` for the minimum and `+0.0` for the maximum. Text statistics are
  written only when both values are at most 64 bytes, so long strLs do
  not bloat the footer.
- `created_by` names the library and version.

### What we read

Every flat file other tools write:

- **Codecs:** none, snappy, gzip, zstd, lz4_raw and brotli. LZO, the
  older Hadoop LZ4 framing and encrypted files are errors that name the
  feature.
- **Encodings:** PLAIN, PLAIN_DICTIONARY and RLE_DICTIONARY, RLE and
  BIT_PACKED levels, RLE booleans, DELTA_BINARY_PACKED,
  DELTA_LENGTH_BYTE_ARRAY, DELTA_BYTE_ARRAY and BYTE_STREAM_SPLIT. Data
  pages v1 and v2.
- **Types:** everything in the table above, plus INT64 TIMESTAMP in
  milliseconds, microseconds and nanoseconds, adjusted to UTC or not;
  INT96 timestamps; TIME; DECIMAL; unsigned integers;
  FIXED_LEN_BYTE_ARRAY; ENUM and JSON as text. FLOAT16 is an error that
  names it. What each becomes is in
  each language's table below.
- **Nested columns** (LIST, MAP, a group) are not read. Reading a file
  that has any, without a column selection that leaves them out, is an
  error that names them and shows both ways on: select the columns
  wanted, or pass `nested = "skip"` (`nested="skip"`, `nested=:skip`,
  `{ nested: "skip" }`), which leaves them out with no warning since
  the caller asked. The info call lists them with role `nested`.
- **Row windows without an offset index.** When a file has no offset
  index, the reader walks the chunk's page headers, which give each
  page's row count and size, and decompresses only the pages that hold
  the window.
- **Damage:** a bad magic number, a footer longer than the file, a
  page whose size does not match its header, or a page that fails to
  decompress is an error naming the column, the row group and the byte
  offset.

## Exactness: what each language gets, and what it loses

Every conversion is exact or stated. Where a value cannot be held
exactly, the default is an error that names the column and the first
row and says which option keeps it; no value changes silently.

| Parquet | R | Python (pandas) | Julia | TypeScript |
|---|---|---|---|---|
| INT32 (any INT(8/16/32)) | integer | int8/16/32; with nulls, float32 (8- and 16-bit) or float64, as `read_dta` | Int8/16/32, `DtaColumn` | `NumberColumn` (`Float64Array`, as for `.dta`) |
| INT64 | `int64 = "double"` (default): double; a value that is not exactly a double is an error. `"integer64"` (bit64) or `"character"` keep every digit | int64; with nulls `Int64` | Int64 | `int64: "auto"` (default): `NumberColumn` if footer statistics, present for every row group, show every value within ±2^53; otherwise `BigIntColumn`, with the reason on the variable. Decided once per column at open, so every window has one type. A row group of only nulls counts as in range. Each decoded value is still checked against ±2^53: if statistics were wrong, the read is an error naming the column, the row and `int64: "bigint"`. `"bigint"` or `"number"` force one; `"number"` errors on a value it cannot hold |
| unsigned 8/16 | integer | uint8/16; with nulls float32, as signed 8- and 16-bit | UInt8/16 | `NumberColumn` |
| unsigned 32/64 | double, with the INT64 rules | uint32/64; with nulls float64 (32-bit) or `UInt64` (64-bit) | UInt32/64 | as INT64 |
| FLOAT, DOUBLE | double | float32, float64 | Float32, Float64 | `NumberColumn` |
| DECIMAL, precision ≤ 15 | double (the nearest double to each decimal) | float64 (same) | Float64 (same) | `NumberColumn` (same) |
| DECIMAL, precision > 15 | `decimal = "double"` (default): double, and a value with more than 15 significant digits is an error; `decimal = "character"` keeps every digit | `decimal.Decimal` objects (only above 15 digits; there is no option, since they lose nothing) | `decimal = :float` (default) as R's `"double"`; `decimal = :string` keeps every digit | string |
| DATE | `Date` | `datetime64[s]` | `Date` | days since 1970 with unit `day`; `toDate()` gives a `Date` |
| TIMESTAMP | `POSIXct` (microsecond precision; NANOS that are not whole microseconds are an error naming `timestamps = "truncate"`); zone from the profile or `ARROW:schema`, else UTC | `datetime64[unit]` in the file's unit, tz-aware when adjusted to UTC | `DateTime` (milliseconds); values that are not whole milliseconds are an error naming `timestamps = :truncate`; `ZonedDateTime` when the file has a zone and TimeZones.jl is loaded, else `DateTime` in UTC with one warning | the count in the file's unit (Float64 or BigInt by the INT64 rule), with unit and zone on the variable; `toDate()` for the safe range |
| INT96 | `POSIXct` | `datetime64[ns]` | `DateTime`, as above | as TIMESTAMP NANOS |
| TIME | `difftime` in seconds | `timedelta64` in the file's unit | `Dates.Time` | count with unit |
| dictionary of any other value type in `ARROW:schema` (a `category` of integers or dates) | read as its value type, by the rows above | same | same | same |
| STRING, ENUM, JSON (no dictionary type) | character | pandas' default text dtype (`str` from pandas 3) | `String` | `StringColumn` |
| BYTE_ARRAY, FIXED_LEN_BYTE_ARRAY without annotation | list of raw | object of `bytes` | `Vector{UInt8}` | `Uint8Array` values |
| categorical (profile) | factor (ordered kept) | `category` (ordered kept) | `CategoricalArray` when CategoricalArrays.jl is loaded, else `String` with one warning | `DictionaryColumn` |
| dictionary of strings in `ARROW:schema`, no profile entry (pandas `category`, polars `Categorical`, arrow factors) | factor; levels are the distinct non-null values in the rows read, in order of first appearance, whether a page is dictionary-encoded or PLAIN; unordered, since that order is not the writer's | `category`, unordered, the same levels | as the profile row, unordered | `DictionaryColumn` |
| BOOLEAN | logical | bool; with nulls `boolean` | Bool | `NumberColumn` of 0 and 1 |

Levels from `ARROW:schema` depend on the rows read, so two windows of
one column can have different levels; reading the whole column gives
every level. The docs say so, and say that a file we write carries its
levels in the profile and has none of this.

## Architecture

- **`crates/parquet`** (package `dta-parquet`): the format, with no I/O
  of its own, reading through the `Source` trait and writing through
  the `Sink` trait as `crates/dta` does (ADR 0001). It holds the Thrift
  compact protocol for the footer and page headers, the encoders and
  decoders, the profile and its JSON, the `ARROW:schema` flatbuffer,
  and the plan that maps a selection of columns and rows to byte
  ranges. It depends on `dta` for `Source`, `Sink`, missing codes and
  errors. `crates/dta` stays free of dependencies.
- **Codec crates.** `snap` (BSD-3-Clause), `lz4_flex` (MIT),
  `miniz_oxide` (MIT, Zlib or Apache-2.0) and `brotli-decompressor`
  (BSD-3-Clause or MIT), all pure Rust; `zstd` (MIT or BSD, C libzstd)
  on native targets and `ruzstd` (MIT, pure Rust) on wasm. All build
  for their targets (checked).
- **Decoding goes straight into the caller's memory.** The binding
  allocates each output vector (an R vector, a numpy array, a Julia
  vector, a range of wasm memory). The core decodes pages into it,
  writing the language's missing value in place where it can (R's
  `NA_integer_` and `NA_real_`, with `.a` to `.z` as tagged NaNs in
  doubles), and a byte of missing code per row where the language
  keeps them aside. Nothing is decoded into an intermediate Arrow
  array, so peak memory is the output plus the pages in flight. That is
  what fastparquet does for pandas, and why it used 60% less memory than
  pyarrow.
- **Text.** A dictionary-encoded chunk is kept as its dictionary plus a
  code per row. R makes one R string per distinct value per chunk, not
  one per row, and merges the dictionaries of a column's chunks. This
  is dtaparser's dictionary column (ADR 0011), and other bindings do
  the same. PLAIN text goes into one byte buffer with offsets, which
  becomes a packed column in R (ADR 0010), `str` in pandas 3 (object
  before), `String` in Julia and the existing `StringColumn` in
  TypeScript. Benchmarks time a pass over every value after the read,
  so deferred string work is counted.
- **Threads.** Column chunks are decoded in parallel, and the columns of
  a row group are encoded in parallel; row groups are written in order
  through the sink, and only one row group's encoded pages are held at
  a time. Calls into R or Python stay on the main thread. The thread
  pool, its controls (`threads`, `DTA_THREADS`,
  `options(dtaparser.threads)`) and its rule for when to use threads
  come from plan 0007. Plan 0007's default of at most three threads was
  measured on `.dta` reads; PR 3 measures Parquet reads and writes at
  1 to 12 threads and sets the Parquet default by the same rule (CPU
  time at most 1.15× one thread's, each added thread at least half
  efficient), recorded in `bench/RESULTS.md`.
- **Bindings.** R reaches the core through dtaparser's Rust bridge,
  which registers two new C callables, `dtaparser_parquet_read` and
  `dtaparser_parquet_write`; datakit fetches them as it fetches
  `dtaparser_fixed_width` (ADR 0032). The ABI number goes from 2 to 3,
  so dtaparser, datakit and dtatools are released together as 3.1.0.
  Python adds pyo3 functions to `dta_parser._native`, Julia adds
  `crates/dta-ffi` native calls, and npm adds wasm exports to the same
  module.
- **Building and installing.** Nothing changes in how each package is
  installed (see "Install" below). The R source tarball and the Python
  sdist ship the crates vendored (`cargo vendor`), so a build from them
  needs no network; a test in CI builds each one with the network off.
  An R install from GitHub builds from the committed copy of the core,
  as now, and fetches the crates from crates.io. A NOTICE file in each
  package lists them with their licenses. `cargo deny` checks licenses
  in CI.

### Considered: the `parquet` crate from arrow-rs (Apache-2.0)

It reads every encoding and codec, and it is well tested. Measured in
`parquet-codecs.md`: without its Arrow layer it compiles 44 crates in
13 s and vendors 54 MB of source; with the Arrow layer, 64 crates in
25 s. Our codec crates vendor 16 MB. Build time is not the reason
against it. We do not use it because:

- **Dictionary codes.** Its column readers without the Arrow layer turn
  dictionary codes into values row by row, so R would make one string
  per row rather than one per distinct value per chunk. That is the
  largest cost in reading text into R (`docs/research/r-string-cost.md`),
  and the main way we expect to beat arrow there. Keeping the codes
  means its Arrow layer: decode into Arrow arrays in batches, then copy
  each batch into the R, numpy or Julia vector, which is the double
  handling the memory target is meant to avoid.
- **Size.** parquet-wasm's README puts a read-only build at about 456 KB
  (brotli-compressed) and the full build at 1.2 MB. Our whole wasm module
  is 204 KB today, uncompressed, before any Parquet code. PR 7 records
  the module's size with Parquet, brotli-compressed, and this reason
  goes into ADR 0033 only if that is smaller than parquet-wasm's
  read-only build (456 KB brotli-compressed); otherwise the other two
  stand alone.
- **Control.** Reading a row window page by page, through our `Source`
  over a file descriptor or a JavaScript callback, with the byte budget
  table-viewer needs, would sit outside its API.

The risk of writing our own is bugs in rarely used corners: a field of
the wrong width (hyparquet-writer#60), an encoding read wrong. The
compat suite answers it: our files are read by eight other readers, and
we read files from eight other writers, with values checked.

## The API in each language

Each language reads Parquet as it reads `.dta`: the same argument
names where the meaning is the same, the same return type and the same
metadata. A script that reads
a `.dta` file with `read_dta` can switch to Parquet by changing one
name, and a `.dta` file saved as Parquet reads back as the same object.

### R (datakit)

```r
read_parquet(file, col_select = NULL, skip = 0, n_max = Inf,
             factors = FALSE, int64 = "double", decimal = "double",
             timestamps = "error", nested = "error",
             warn_extended_missing = TRUE)
read_parquet_info(file)
save_parquet(data, file, compression = "zstd", compression_level = NULL,
             row_group_size = NULL, missing_letters = TRUE)
```

- `file` is a path, or a raw vector holding a whole file.
- `read_parquet()` returns a tibble, as `read_dta()` does, with the
  same column types: integers, doubles, character, `Date`, `POSIXct`,
  factors, and `dtaparser_labelled` for columns with value labels.
  Every missing value is `NA`, and in doubles `.a` to `.z` keep their
  letter as `read_dta()` keeps them. An integer column holding any of
  them in the rows read is a double. The variable label is attribute
  `label`, the display format `format`, the data label and notes are
  attributes of the tibble, and `factors = TRUE` does what it does for
  `read_dta()`.
- `col_select` takes names or a tidyselect expression, in the order
  given. `skip` and `n_max` work as in `read_dta()`. An unknown name is
  an error that lists the names in the file.
- **The round trip is exact.** For every frame `x` that
  `dtaparser::read_dta()` returns, `identical(read_parquet(p), x)` after
  `save_parquet(x, p)`. A test checks it over every fixture and over the
  NSFG and DHS files. dtatools' dibbles are not a target: dtatools exists
  for one test suite (ADR 0016), and its users keep `.dta` files.
- `read_parquet_info()` reads the footer only and returns a list:
  `rows`, `row_groups` (rows and bytes of each), `created_by`,
  `compression`, the data label and notes, and a `columns` data frame.
  That frame has one row per Parquet column: name, role (`data` or
  `nested`), the R type `read_parquet()` will return, Parquet's
  physical and logical type, the variable label, the value label set's
  name, and the storage and logical types the profile records. This
  copies `nanoparquet::read_parquet_schema()`, the only R function that
  says what a column will become before reading it.
- `save_parquet()` writes what `save_dta()` writes and with the same
  checks, plus what `.dta` cannot hold: factors with their levels,
  logicals, time zones, long text and binary. It returns `data`
  invisibly. A column type it cannot write (a list other than of raw
  vectors, a complex number, a nested data frame) is an error naming
  the column. An unknown `compression` is an error listing the codecs.
- **Names.** `read_parquet` is also the name of arrow's and
  nanoparquet's readers. The R docs say so in their first paragraph:
  a translated script attaches dtaparser and datakit, and where arrow
  or nanoparquet is attached too, call `datakit::read_parquet()`. An
  argument from arrow's function (`as_data_frame`) then fails as an
  unused argument. `save_` matches `save_dta()` and Stata's `save`, and
  does not collide with `write_parquet`.

### Python (`dta_parser`)

```python
read_parquet(source, columns=None, skip=0, n_max=None, nested="error")
read_meta(source)                      # .dta or Parquet, told apart by magic bytes
write_parquet(df, path=None, *, label=None, variable_labels=None,
              compression="zstd", compression_level=None,
              row_group_size=None, missing_letters=True)
```

`source` is a path (`str` or `os.PathLike`), `bytes`, or a binary file
object with `seek`. `write_parquet` returns the file as `bytes` when
`path` is None. The DataFrame is the one `read_dta` returns:
`StataArray` columns where a column holds `.a` to `.z`, and
`df.attrs["dta"]` for labels, formats, notes and value labels.
`write_parquet` takes what `write_dta` takes, and also `category`,
tz-aware datetimes, `Int64` and `bytes`. `columns` takes names or
positions (of data columns), and an unknown one is a `KeyError` that
lists the names. The round trip is checked over every fixture with
`assert_frame_equal` and the `attrs`, except the keys that describe a
`.dta` file (`release`, `byte_order`, `encoding`, and each string
column's strN width, which is chosen again when it is written to
`.dta`), and except a strL column mixing text and binary values, whose
text values come back as `bytes` (the type table above says why).

**The index.** `write_parquet`, like `write_dta`, writes columns only,
not the index. When the index is anything but a default `RangeIndex`
(named, or of another kind), it warns once, naming the index and saying
to call `df.reset_index()` first to keep it. `read_parquet` returns a
default `RangeIndex`. An index that pandas stored as a column (such as
`__index_level_0__`) reads as an ordinary data column, and the docs show
`set_index()` to restore it. Both rules are in the Python page and in
`docs/parquet.md`.

`read_meta` returns the dictionary `read_dta` puts in `attrs["dta"]`,
with `"nobs"` as for `.dta`, and for Parquet also `"format":
"parquet"`, `"row_groups"` (rows and bytes of each), `"compression"`,
`"created_by"`, and per column, beside its label, format and value
labels: `"role"` (`"data"` or `"nested"`),
`"physical_type"`, `"logical_type"` and `"dtype"`, the pandas dtype
`read_parquet` will give it.

### Julia (`DtaParser`)

```julia
read_parquet(source; cols=nothing, skip=0, n_max=nothing, timestamps=:error,
             decimal=:float, nested=:error)
read_meta(source)
write_parquet(path_or_io, table; label=nothing, notes=nothing,
              compression=:zstd, compression_level=nothing,
              row_group_size=nothing, missing_letters=true,
              value_labels=nothing, column_labels=nothing,
              column_formats=nothing, column_value_labels=nothing)
```

`source` is a path, an `IO`, or a `Vector{UInt8}`. The return type is
the `DtaTable` that `read_dta` returns, with `DtaColumn`s that keep `.a`
to `.z` and DataAPI metadata. Zones and categoricals need TimeZones.jl
and CategoricalArrays.jl, loaded as package extensions; without them
the values come back as `DateTime` in UTC and as `String`, with one
warning naming the columns. The round trip is checked over every
fixture with `isequal` on values, codes and metadata, with the same
exceptions as Python's.

`read_meta` returns what it returns for `.dta` (`nrows` and the column
metadata), plus `format = :parquet`, `row_groups`, `compression`,
`created_by`, and per column `role`, `physical_type`, `logical_type` and
`eltype`, the element type `read_parquet` will give. pandas and pyarrow
write microsecond timestamps by default, which `DateTime` cannot hold,
so the first Julia example for a file from another tool passes
`timestamps = :truncate`, and the error message gives the exact call
to make.

### TypeScript (`@jbearak/dta-parser`)

```ts
openParquet(bytes: Uint8Array, options?): TableReader
openParquetFile(file: string | number, options?): TableReader
openParquetAsync(readAt: (offset: number, length: number) => Promise<Uint8Array>,
                 size: number, options?): Promise<AsyncTableReader>
writeParquet(data: WriteDataset, options?): Uint8Array
writeParquetTo(data: WriteDataset, sink: (bytes: Uint8Array) => void, options?): void
writeParquetFile(path: string, data: WriteDataset, options?): void
toDate(value: number | bigint, variable: Variable): Date | null
```

- `DtaReader` and the new Parquet reader both implement `TableReader`
  (`info`, `variables`, `readColumns(columns, { start, count })`,
  `readRows`, `readRowsAt(rows)`, `valueLabels`, `close()`, `using`).
  A viewer can then use one data source for both formats. The calls are
  synchronous, as for `.dta` (ADR 0002). Columns are the existing
  `NumberColumn` (`Float64Array` with a missing mask), `StringColumn`
  and `DictionaryColumn`, plus `BigIntColumn` for INT64 that does not
  fit a double. Keeping `Float64Array` for every number, as `.dta`
  does, costs twice the memory of an `Int32Array` for 32-bit columns,
  but it avoids a breaking change to 1.x. hyparquet returns a plain
  `Array` for any nullable column, so ours is still smaller.
- `info` is the `.dta` reader's (`nobs`, `variables` with their
  labels, formats and value labels), plus `format: "parquet"`,
  `rowGroups` (rows, compressed and uncompressed bytes of each),
  `compression`, `createdBy`, and per variable `role`, `physicalType`,
  `logicalType`, `columnKind` (which column type it reads as),
  statistics per row group, and for INT64 the reason for its kind.
- `openParquetFile` reads the footer only. Each call reads the byte
  ranges of the pages it needs, and a cache of decoded pages per reader
  (8 MiB by default, `pageCacheBytes`) serves neighbouring windows.
  `info` gives the row count, the row-group boundaries, and each
  chunk's compressed and uncompressed size and statistics, all before
  any data is read.
- `openParquetAsync` is for browsers and remote files (HTTP range
  requests). It returns an `AsyncTableReader`: the same members as
  `TableReader`, with `readColumns`, `readRows` and `readRowsAt`
  returning promises. It fetches the footer, and for each call asks the
  core which byte ranges it needs, fetches them, and decodes them
  synchronously. It is the same decoder, so the results are the same.
- `toDate` turns a date or timestamp value into a `Date` when it is
  within the range a `Date` holds exactly to the millisecond, and
  returns null otherwise; the raw value is always there.
- The writer takes the `WriteDataset` that `writeDta` takes, with
  `compression`, `rowGroupSize` and `missingLetters` options.

## Documentation

The docs are written in the PR for each language, and judged at Gate 2.

- **`docs/parquet.md`**, the shared page. One heading per Gate 2 task,
  each linking to that task's section in every language page. It also
  holds the profile's specification, "What other tools see in our
  files", the codec and row-group defaults with the measurements behind
  them, and the error catalogue (each error and warning, what causes
  it, what to do).
- **Each language page** (`docs/r.md`, `docs/python.md`,
  `docs/julia.md`, `docs/typescript.md`) gets a Parquet section, listed
  in its table of contents, with one heading per Gate 2 task, each with
  a short runnable example and its output. The examples run in CI
  through each language's existing docs test (`test-docs.R`,
  `test_docs.py`, `docs.jl`, `docs.test.mjs`). The section also has the
  language's column of the exactness table, and a migration table from
  each other library in that language (arrow and nanoparquet; pyarrow,
  pandas and polars; Parquet2.jl; hyparquet and parquet-wasm). Each
  table maps the other library's call and arguments to ours and says
  what changes.
- **Reference.** R man pages through roxygen, Python and Julia
  docstrings, and TSDoc, each linking to the guide section.
- The README's front page lists Parquet with a link to
  `docs/parquet.md`.

## Install

Parquet adds no install step. Each package installs as it does today:
R from the Pages repository (binaries for macOS, Windows and Ubuntu;
from source with Rust elsewhere); Python, Julia and the 1.x npm package
from a checkout, with Rust. A source build now also compiles C libzstd,
with the C compiler those builds already need. Publishing to PyPI, the
Julia General registry or npm is the user's decision (AGENTS.md), and
not part of this plan. Task 1 stays in the pass rule and, like every
task, is scored on the install documentation's findability,
correctness, completeness and clarity. Before Gate 2 the user is asked
whether to publish. If a package stays unpublished and its install
from a checkout scores below another library's, Gate 2 has failed for
that language, and the user is asked how to proceed.

## Speed and memory

`bench/run.py` gains Parquet cases. Every case is run five times in a
fresh process, on a quiet machine (one-minute load average under 2,
recorded), and the median is used: wall time, CPU time (user plus
system) and peak RSS. Each library uses its default thread count, which
is recorded.

- **Inputs:** the 36 NSFG files and the 10 DHS files, each converted
  to Parquet three ways: by pyarrow with its defaults (snappy), by
  polars with its defaults (zstd), and by our writer. Also the synthetic
  files in `bench/make_large.R`. Converting reads `.dta` with our
  reader, so the three hold the same data.
- **Reads:** the whole file; five columns; a 1,000-row window from the
  middle; and the whole file followed by one pass over every value, so
  that deferred work (such as arrow's strings, which take 1.25 s on
  first use after a 0.07 s read) is counted.
- **Writes:** a frame already in memory to a file, with each library's
  defaults, and with zstd level 3 for all.
- **Other tools reading our files:** pyarrow, polars and DuckDB reading
  our output against reading their own default output of the same data.
- **Compared:**
  - R: arrow, nanoparquet, duckdb.
  - Python, into pandas: pyarrow (`read_table().to_pandas()`),
    `pandas.read_parquet`, fastparquet, and polars with `.to_pandas()`.
    Into their own types: pyarrow's `Table`, polars' `DataFrame`,
    DuckDB's relation fetched to Arrow.
  - Julia: Parquet2.jl and DuckDB.jl.
  - TypeScript: hyparquet, hyparquet-writer and parquet-wasm.
- **Targets**, per language, against each library that returns the
  same table type (R data frames; pandas; Julia tables; JavaScript
  columns), for every read and write case, on each of the three inputs:
  1. **Wall time and peak RSS:** our geometric mean over the NSFG files,
     and over the DHS files, is at most theirs × 1.05 (the 5% is
     measurement noise, measured as the spread of the five runs).
  2. **No large single misses:** on no single file is ours more than
     1.25× theirs in wall time or peak RSS, unless the difference is
     under 20 ms or under 16 MiB.
  3. **CPU in proportion:** with speedup `s` = their wall time ÷ ours,
     our CPU time is at most theirs × max(1.15, `s`). A read that is no
     faster may use at most 15% more CPU; one that is three times faster
     may use up to three times the CPU.
  4. **Other tools on our files:** pyarrow, polars and DuckDB read our
     files within 1.10× of the time they take on their own default
     output.
- **What "comparable" means.** The user asked for speed at least that of
  comparable readers and writers. A comparable reader produces the same
  kind of result. Ours produce each language's usual data frame: R data
  frames, pandas, Julia tables, JavaScript columns. pyarrow's `Table`
  and polars' `DataFrame` are other kinds of result: Arrow memory that
  is never converted. We offer no such output, so those cases are not
  comparable. They are published per case alongside the gated ones,
  and the Python docs say plainly that a user who wants a polars or
  Arrow table should read with polars or pyarrow.
- A missed target blocks that language's PR. If profiling cannot close
  it, the PR stays open and the user is asked, with the numbers.

## Ergonomics and documentation: how it is judged

**Gate 1, the design (this plan).** Claude Sonnet and GPT Terra review
this plan with the research notes and the existing docs. Each says, per
language and per other library, whether the API and documentation
planned here would serve a user better, and what would make it better.
The plan is revised until both say yes for every language and library.
Each round's reviews and our answers go in
`docs/judging/parquet-design/`.

**Gate 2, the documentation (last PR).** The blind pairwise judging of
`docs/judging/rubric.md`, under its own rubric,
`docs/judging/parquet-rubric.md`, committed in its own commit before
any Parquet docs are written. Its tasks:

1. Install.
2. Read a whole file; what type each Parquet type becomes.
3. Read some columns.
4. Read a range of rows.
5. Get the schema and metadata without the data.
6. Value labels and variable labels: read them, use them.
7. Dates and timestamps, with time zones.
8. Write a table; compression and row groups.
9. Write labels, value labels and a data label, and check them by
   reading back.
10. Keep `.a` to `.z` through a write and a read.
11. Read a file another tool wrote, and know what is not supported.

The scores (findability, correctness, completeness, clarity, 0 to 3)
are as in `rubric.md`. The rubric fixes, before judging, which tasks
each other library supports. **Pass rule**, for both judges, every
language and every other library:

1. on each task that library supports, our task score is at least
   theirs;
2. our total over all eleven tasks is higher than theirs; and
3. each of our task scores is at least 2.

So a library that documents a task well and we document it worse fails
us, whatever our totals. Rounds continue until the rule passes; every
round is published in `docs/judging/parquet-round-N/` with its prompts,
coin flips, raw responses and scores. After a failed round we change
our docs or our API, never the rubric or the other libraries' bundles.

Blinding replaces package names with "Library A" and "Library B", as in
`rubric.md`. It cannot hide that our docs talk about Stata's labels and
missing values; the judges are told to score the tasks, not to guess
the library.

Compared:

- R: arrow, nanoparquet.
- Python: pyarrow, pandas, polars.
- Julia: Parquet2.jl.
- TypeScript: hyparquet (with hyparquet-writer), parquet-wasm.

The fresh-agent check of `rubric.md` runs too: one agent per language
does all eleven tasks from our docs alone.

## Acknowledgements

`docs/acknowledgements.md` lists the projects studied, with their
licenses and what each taught us: the Apache Parquet format
specification; arrow and pyarrow; nanoparquet; polars; pandas;
fastparquet; DuckDB; Parquet2.jl; Arrow.jl; ReadStatTables.jl;
hyparquet and hyparquet-writer; parquet-wasm. It also lists the codec
crates, which we use rather than study. No code is copied from the
studied projects. If any is, it is credited where it is used and in
this file, with its license. Each package's README links the file.

## Delivery

One PR at a time unless noted. Each goes through sol-loop and is taken
to merge with full-send, and includes its docs, tests and benchmark
cases.

1. **Plan and design.** This plan, approved at Gate 1, with ADR 0033,
   the research notes and the Gate 1 record.
2. **Core, first slice** (`crates/parquet`). Reading and writing
   everything we write, and the default output of pyarrow, arrow (R),
   polars, DuckDB and nanoparquet: PLAIN and dictionary encodings, RLE
   levels, pages v1 and v2, snappy, gzip and zstd, the profile, tagged
   NaNs for `.a` to `.z`, statistics, the offset index and `ARROW:schema`. Fixtures
   written by those tools from data we create, with values checked
   against pyarrow's reading of the same file. Our files read back by
   pyarrow, polars, DuckDB, arrow (R) and nanoparquet, with values
   checked.
3. **R.** dtaparser's bridge (ABI 3) and datakit's three functions,
   their docs (types from PR 4, such as DECIMAL, INT96, TIME and
   unsigned integers, are an error naming the type as not yet read;
   a dictionary column from `ARROW:schema` reads as its value type),
   the round-trip test over every fixture, NSFG and DHS, the thread
   measurement, and the R benchmarks against the targets.
   This proves the design end to end before the rest is built.
4. **Core, breadth.** The other encodings (DELTA_*, BYTE_STREAM_SPLIT),
   lz4_raw and brotli, INT96, TIME, DECIMAL, unsigned integers, reading
   dictionary types from `ARROW:schema`, and the damaged-file tests;
   R's type table is completed here, with fixtures from
   fastparquet, Parquet2.jl and hyparquet-writer too.
5. **Python**, 6. **Julia**, 7. **TypeScript**, in parallel once 4 is
   merged, each with its docs, round-trip tests and benchmarks.
8. **Judging and results.** `parquet-rubric.md` (its own commit first),
   Gate 2, `bench/RESULTS.md`'s Parquet section, `docs/parquet.md`'s
   final measurements and `docs/acknowledgements.md`.

After 8, a new thread adds Parquet reading and writing to table-viewer.
Its plan is reviewed by Terra and Sonnet and implemented with
full-send. Publishing the npm release it needs is the user's decision.

## Not in this plan

- **Arrow IPC (Feather).** See above.
- **The `pandas` metadata key.** It would make pandas read our nullable
  integers as `Int32` rather than float64. Our own reader does not need
  it, and pyarrow already restores categoricals and zones from
  `ARROW:schema`.
- **Nested columns** (see "Scope"), **datasets of many files, Hive
  partitions, predicate pushdown, encryption, bloom filters.** The docs
  say so in the "files from other tools" task.
- **Later, if asked for:** reading the Hadoop LZ4 framing, FLOAT16 and
  page CRC checks.
- **Writing DELTA or BYTE_STREAM_SPLIT encodings.** Readers that cannot
  read them would fail on our files.
- **Reading arrow's `r` metadata key.** It is R serialization, so
  unserializing untrusted input is unsafe; we do not read it.

## Risks

- **Beating polars and pyarrow on wall time.** Both are multithreaded
  and mature. Our advantages are no Arrow-to-pandas copy and one string
  per distinct value. PR 3 measures R first, so a design that cannot
  meet the targets shows before the other languages are built.
- **Wide files.** A 3,000-column file has 3,000 column chunks per row
  group. The footer parse must stay fast and the profile must be parsed
  once. pyarrow limits Thrift strings to 100 MB and containers to a
  million entries; the writer stays under both, and a test writes a
  5,000-column file with large label sets and reads it with pyarrow.
- **Dependencies.** This is the first time the core uses crates from
  crates.io. They are pinned in `Cargo.lock`, vendored in every
  package that is built offline, and checked by `cargo deny` in CI.
