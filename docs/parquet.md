# Parquet files that keep what a `.dta` file says

datakit (R) and `@jbearak/datakit` (TypeScript) read and write Parquet
files that keep a `.dta`
file's value labels, variable labels, display formats, notes and extended
missing values `.a` to `.z`, and also factor levels and time zones. A
file it writes is ordinary Parquet that pyarrow, pandas, polars,
DuckDB, arrow and nanoparquet read; what Parquet has no place for goes
into one JSON entry of the file's metadata, the *dta profile*, which
those tools ignore. Only flat tables are read and written: nested
columns (lists, maps, structs) are not, so for nested data use arrow,
pyarrow or polars.

Contents:
[Tasks](#tasks) ·
[The file](#the-file) ·
[The profile](#the-profile) ·
[What other tools see in our files](#what-other-tools-see-in-our-files) ·
[Defaults and the measurements behind them](#defaults-and-the-measurements-behind-them) ·
[Errors and warnings](#errors-and-warnings)

## Tasks

Each task links to its section on the language page.

### Install

Parquet needs no Arrow or other Parquet library: the packages read and
write it through their own Rust core. In both languages it is in
datakit, which needs the format package (dtaparser,
`@jbearak/dta-parser`). R installs from the project's package
repository, with binaries for macOS, Windows and Ubuntu. The npm
packages install from a checkout of this repository, which needs Rust
and a C compiler (for the zstd library).

- R: [Parquet: install](r.md#parquet-install).
- TypeScript: [datakit: install](typescript.md#datakit-install);
  `@jbearak/datakit` beside `@jbearak/dta-parser`.

### Read a whole file, and what each type becomes

Each language's type table gives what every Parquet type becomes. Every
conversion is exact or an error naming the option that keeps the value,
with one exception: DECIMAL. R reads it by default as the nearest
double, which may not equal the decimal value exactly; a value with
more than 15 significant digits, which a double cannot give back, is an
error, and `decimal = "character"` keeps every digit as text.
TypeScript reads precision up to 15 as the nearest double and higher
precision as text.

R: [Read a Parquet file](r.md#read-a-parquet-file) and
[What each Parquet type becomes](r.md#what-each-parquet-type-becomes-in-r).
TypeScript: [Read a Parquet file](typescript.md#read-a-parquet-file) and
[What each Parquet type becomes](typescript.md#what-each-parquet-type-becomes-in-typescript).

### Read some columns

R: [Read some columns](r.md#read-some-columns-of-a-parquet-file).
TypeScript: [Read some columns](typescript.md#read-some-columns-of-a-parquet-file).

### Read a range of rows

R: [Read a range of rows](r.md#read-a-range-of-rows-of-a-parquet-file).
TypeScript: [Read a range of rows](typescript.md#read-a-range-of-rows-of-a-parquet-file),
and [in a browser or over HTTP](typescript.md#parquet-in-a-browser-or-over-http).
Only the row groups that hold the rows are read, and within them only
the pages that do: through the file's offset index, or, when it has
none, by walking the page headers.

### Get the schema and metadata without the data

R: [Schema and metadata](r.md#a-parquet-files-schema-and-metadata).
TypeScript: [Schema and metadata](typescript.md#a-parquet-files-schema-and-metadata).

### Value labels and variable labels

R: [Labels](r.md#labels-in-parquet-files).
TypeScript: [Labels](typescript.md#labels-in-parquet-files).

### Dates and timestamps, with time zones

R: [Dates and time zones](r.md#dates-and-time-zones-in-parquet-files).
TypeScript: [Dates and time zones](typescript.md#dates-and-time-zones-in-parquet-files).

### Write a table; compression and row groups

R: [Write a Parquet file](r.md#write-a-parquet-file).
TypeScript: [Write a Parquet file](typescript.md#write-a-parquet-file).
The defaults are [below](#defaults-and-the-measurements-behind-them).

### Write labels and a data label, and check them

R: [Write labels](r.md#write-labels-to-a-parquet-file).
TypeScript: [Write labels](typescript.md#write-labels-to-a-parquet-file).

### Keep `.a` to `.z` through a write and a read

R: [Keep .a to .z](r.md#keep-a-to-z-in-a-parquet-file).
TypeScript: [Keep .a to .z](typescript.md#keep-a-to-z-in-a-parquet-file).

### Read a file another tool wrote

R: [Files from other tools](r.md#parquet-files-from-other-tools).
TypeScript: [Files from other tools](typescript.md#parquet-files-from-other-tools).
Every encoding and codec other tools write by default is read. Of the
encodings, only BIT_PACKED for values is not, which the format has
deprecated and current writers do not use; what else is not read
(nested columns, FLOAT16, INTERVAL, LZO, the Hadoop framing of LZ4 and
encrypted files) is listed in each language's section. These types are read too:
unsigned integers, DECIMAL, TIME, INT96, fixed-length binary, UUID,
ENUM and JSON. A category or factor that
pandas, polars or arrow wrote (a dictionary of strings in
`ARROW:schema`) reads as a categorical whose levels are the values of
the rows read, in order of first appearance, so two windows of one
column can have different levels; a file we write carries every level
in the profile instead. An instant's zone (a timestamp adjusted to UTC)
comes from the profile, else from `ARROW:schema`, else is UTC. A clock
time (not adjusted to UTC) has no zone: TypeScript reads it without
one, and R, whose `POSIXct` needs one, reads its clock reading as UTC.

## The file

A file is plain Parquet: every column OPTIONAL, data pages v1, with
statistics, an offset index, the legacy converted types beside the
logical types, and an `ARROW:schema` entry so that pyarrow, polars and
arrow restore factors and time zones. What each value becomes:

| what is written | Parquet physical type | logical type |
|---|---|---|
| Stata byte; polars `Int8` | INT32 | INT(8, signed) |
| Stata int; polars `Int16` | INT32 | INT(16, signed) |
| Stata long; R integer; polars `Int32` | INT32 | none |
| R `integer64`; polars `Int64` | INT64 | none |
| polars `UInt8` to `UInt64` | INT32 or INT64 | INT(8 to 64, unsigned), with unsigned statistics |
| Stata float; polars `Float32` | FLOAT | none |
| Stata double; R double; polars `Float64`, and an all-null `Null` column | DOUBLE | none |
| R logical; polars `Boolean` | BOOLEAN | none |
| text: strN, strL, R character, polars `String` | BYTE_ARRAY | STRING |
| binary: a binary strL, an R list of raw vectors, polars `Binary` | BYTE_ARRAY | none |
| R `Date`; polars `Date` | INT32 | DATE |
| R `POSIXct`; a polars `Datetime` with a zone | INT64 | TIMESTAMP(MICROS for R, the column's unit for polars, adjusted to UTC); the zone in the profile and `ARROW:schema` |
| a polars `Datetime` without a zone | INT64 | TIMESTAMP(its unit, not adjusted to UTC) |
| polars `Time` | INT64 | TIME(NANOS) |
| R factor; polars `Enum`, `Categorical` | BYTE_ARRAY, dictionary-encoded, every level in order in every row group | STRING; levels and ordering in the profile |
| a categorical holding `.a` to `.z`: a TypeScript categorical given `MISSING` values or tagged NaNs among its codes | DOUBLE: level numbers from 1, the letters as tagged NaNs | none; `"logical": "categorical"`, levels, ordering and a value label set in the profile |

Missing values:

- `.` and every other missing value is a null.
- `.a` to `.z` are **tagged NaNs**: R's `NA_real_` (`0x7FF00000000007A2`)
  with the letter's ASCII code in bits 32 to 39, the pattern haven's
  tagged NA and dtaparser use. A NaN is the only value a double can
  hold beside numbers, so a numeric column holding any `.a` to `.z` is
  written as DOUBLE, with its storage type in the profile
  (`"storage": "byte"`, `"int"`, `"long"` or `"float"`).
- A date or timestamp column holding them is DOUBLE too: days since
  1970-01-01 or seconds since 1970-01-01 00:00, with
  `"logical": "date"` or `"timestamp"` (and the zone, `tz`) in the
  profile. So is an R `Date` with a fraction of a day, or a `POSIXct`
  whose seconds no whole number of microseconds gives back exactly, so
  that it reads back unchanged. R reads such a column back as `Date`
  or `POSIXct` with tagged NAs.
- A categorical holding them is DOUBLE too (plan 0022): each value is
  its level's number counted from 1, `.` is a null, `.a` to `.z` are
  tagged NaNs, and the profile has `"logical": "categorical"` beside
  its `categorical` levels, and `value_labels` naming a set that labels
  1 to the number of levels with the levels (and may label letters,
  "Refused" on `.r`, say). The set is the one the writer was given for
  the column if it fits, else the first of the column's name,
  `name_2`, `name_3`, ... that fits or is free, so no other column's set
  changes and the name stays the same through any number of writes and
  reads. A categorical without letters stays text. R and
  TypeScript, whose factor and `DictionaryColumn` cannot hold letters,
  read it as labelled numbers: the level numbers with the letters and
  the set (`factors = TRUE` leaves it so). TypeScript reads the
  categorical when the rows read hold no letters, and its `readRows`
  gives its levels as text. R writes it back as labelled numbers, not a
  categorical. A value that is
  not a level number (another tool rewrote the column) reads as `.`,
  with one warning naming the column and the first such row.
- A reader takes a DOUBLE value as `.a` to `.z` only when its bits are
  exactly that pattern with a letter `a` to `z`; any other NaN is NaN,
  a value.
- `save_parquet(missing_letters = FALSE)` (R) and
  `missingLetters: false` (TypeScript) write `.a` to `.z` as nulls, for files meant for tools that count NaN as a value. The letters
  are then lost.

## The profile

The profile is JSON, under the key `dta` in the file's key-value
metadata:

```json
{
  "version": 1,
  "label": "Smoking survey, 2024",
  "notes": ["Wave 2 only."],
  "characteristics": {"_dta": {"note0": "1"}, "age": {"source": "q12"}},
  "sort": ["id"],
  "timestamp": "1 Mar 2024 09:30",
  "columns": {
    "age":    {"label": "Age in years", "format": "%9.0g",
               "value_labels": "agelbl", "storage": "byte"},
    "region": {"categorical": {"levels": ["North", "South", "West"], "ordered": false}},
    "seen":   {"format": "%tdCCYY-NN-DD"},
    "when":   {"tz": "America/New_York"},
    "asked":  {"logical": "date"}
  },
  "value_labels": {
    "agelbl": [[97, "Refused"], [".d", "Don't know"]]
  }
}
```

- `columns` is keyed by column name. A reader ignores entries for names
  the file does not have, so a file another tool rewrote after dropping
  or renaming columns still reads.
- A column entry may hold `label` (the variable label), `format` (the
  display format), `value_labels` (the name of a set), `categorical`
  (`levels`, every level in order, unused ones too, and `ordered`),
  `tz` (a timestamp's zone; `""` for an instant without one), `unit`
  (`"s"` where Parquet has no such unit), and on a DOUBLE column
  written so because of `.a` to `.z`, `storage` or `logical` (`"date"`,
  `"timestamp"` or `"categorical"`; a categorical has `categorical` and
  `value_labels` too).
- `value_labels` maps a set's name to an array of `[code, text]` pairs.
  A code is a JSON number, finite and within ±2^53 if it is an integer,
  or a missing code as text: `"."` or `".a"` to `".z"`. An array keeps
  numeric codes as numbers, which object keys would not.
- `characteristics` maps `_dta` or a column name to its named texts;
  `notes` and `sort` (column names) are arrays of text; `label` is the
  data label; `timestamp` is the `.dta` file's time stamp, as text, where
  a language keeps one (R's `meta$timestamp` and TypeScript's
  `Dataset` do).
- **Reading is forgiving.** `version` is 1; a higher one is read for
  what is known, with one warning. The profile must be a JSON object of
  at most 64 MiB with no duplicate keys at any level. An entry that
  breaks a rule (a label set that is not a list of pairs, a code given
  twice, a `levels` list with a level twice, a `value_labels` name with
  no set, a `storage` or `logical` on a column that is not DOUBLE) is
  dropped with one warning naming it, and the rest is used. A
  `"logical": "categorical"` without valid `categorical` levels, or
  beside a `storage`, is dropped with its levels, and the column reads
  as numbers; a categorical whose `value_labels` names no set or one
  that does not fit gets a set made from its levels, named as the
  writer would. A profile
  that is not JSON, too large, or not an object gives one warning, and
  the file reads as plain Parquet. Damaged metadata is never an error:
  the values are intact.
- **Writing is strict**: a code that is not finite or beyond ±2^53, a
  code or level given twice, two entries for one name, are errors.

## What other tools see in our files

Checked by `compat/parquet/readback.py` and `readback.R` (pyarrow
26.0.1, pandas 3.1.1, polars 2.1.0, DuckDB 2.0.0, arrow 26.0.0,
nanoparquet 0.5.2):

| ours | pyarrow / pandas | polars | DuckDB | arrow (R) | nanoparquet |
|---|---|---|---|---|---|
| value labels, variable labels, formats, notes | lost (the profile is ignored) | lost | lost | lost | lost |
| `.a` to `.z` | pyarrow: NaN, not null; pandas: missing | NaN, not null | SQL: NaN, not NULL; DuckDB in R: tagged NA, letter kept | tagged NA, letter kept | tagged NA, letter kept |
| a categorical | dictionary, ordered kept; pandas `category` | `Categorical` | VARCHAR | factor, ordered kept | factor, not ordered |
| a categorical holding `.a` to `.z` | double: the level numbers 1 to k, the letters NaN | Float64, the letters NaN | DOUBLE, the letters NaN | double, tagged NA, letter kept | double, tagged NA, letter kept |
| a zoned timestamp | tz-aware, our zone | our zone | TIMESTAMP WITH TIME ZONE | `POSIXct` in our zone | `POSIXct` in UTC |
| INT(8), INT(16) | int8, int16 (pandas: float64 with nulls) | Int8, Int16 | TINYINT, SMALLINT | integer | integer |

In DuckDB SQL and polars, `.a` to `.z` are NaN values: `IS NULL` is
false for them, `count(x)` counts them and `mean(x)` is NaN. To treat
them as missing:

```sql
SELECT count(*) FILTER (WHERE x IS NULL OR isnan(x)) AS missing FROM 'survey.parquet'
```

and in polars, `pl.col("x").is_null() | pl.col("x").is_nan()`. Or
write the file with `missing_letters = FALSE`.

## Defaults and the measurements behind them

- **Compression: snappy.** The plan chose zstd at level 3, which
  [the codec measurements](research/parquet-codecs.md) found made raw
  DHS data a quarter of snappy's size, and said the default would
  become snappy if zstd missed a target. It missed the target that
  other tools read our files about as fast as their own: DuckDB took
  1.40 times as long to read our zstd copy of long.dta as its own
  snappy output, and pyarrow and DuckDB were up to 1.2 times slower on
  our zstd survey files. Our reader paid too: random doubles barely
  compress, and decoding them through zstd took three times the CPU
  time. The size saving was small, because most survey columns are
  dictionary-encoded before compression: zstd files of the NSFG and DHS
  files were 16 to 17% smaller than snappy ones, and writing them took
  3 to 11% longer. `zstd` (with
  `compression_level`), `gzip`, `lz4_raw` and `none` are there on
  request, in both languages, the npm package included: its wasm
  module carries C libzstd too.
- **Row groups: up to 262,144 rows (polars' default) and about 1 GiB of
  values.** The plan had 64 MiB, which made a DHS file of 5,000 columns
  four row groups where pyarrow and polars write one; pyarrow then took
  2.4 times as long to read our file as its own, and polars 1.6 times.
  At 1 GiB survey files are one row group, as those tools write them,
  and a long file is cut at 262,144 rows.
- **Pages** of about 1 MiB of values, data page v1, which every reader
  reads. Dictionary encoding for a column chunk while its dictionary
  stays under 1 MiB and smaller than 60% of the values it replaces;
  past either, the rest of the chunk is PLAIN. A chunk of numbers is
  PLAIN from the start once 90% of its first 32,768 values are
  different: such a dictionary seldom meets the 60% rule, and building
  it was half the time to write wide.dta's random doubles. No DELTA or
  BYTE_STREAM_SPLIT encodings, which some readers cannot read.
- **Threads: more for larger work.** Reads and writes of under 16 MB
  use one thread. Larger reads use one thread per 176 MiB of decoded
  values, at least two and at most eight; larger writes one per 256
  MiB of values, at least two and at most six. These numbers come from
  plan 0007's rule, applied at each size: each thread added must make
  the task faster by at least half of what one thread does alone, and
  CPU time must stay within 1.15 times one thread's. Survey files of up
  to about 250 MiB decoded fail it at three threads (NSFG 1995 gained
  0.39 of a thread from the third), because much of their work is
  per-column work on the calling thread. Large files have more to
  share: long.dta (777 MiB) passed for reads up to four threads and
  wide.dta (4.6 GB) up to eight, and wide.dta's writes up to six.
  The Arrow path that
  R's datakit uses with polars (plans 0019 and 0025) has its own rule, set against
  polars, which uses every core: reads of 256 KiB or more use one
  thread per 32 MiB, at least four and at most twelve, and writes one
  per 8 MiB, at least four and at most sixteen. There the measure is
  polars' wall time, with CPU time within the larger of 1.15 times
  polars' and the speed gained. A read on the Arrow path also hands
  nothing to the calling thread in row order, so more threads stay
  busy. A write encodes the next
  row groups while it writes out the current one, so a long table of
  few columns keeps its threads busy. On the Arrow path the workers encode as
  far ahead of the column chunk being written out as 256 MiB of encoded
  chunks allows, rather than two chunks per thread, so a wide survey
  file's many small chunks keep every thread busy. `DTA_THREADS` and each
  language's threads option set the count instead. The measurements at
  1 to 16 threads are in
  [bench/RESULTS.md](../bench/RESULTS.md#parquet).
- **Memory for a read in R.** Before a large read, dtaparser has R
  make room for the whole result at once. R otherwise grows its memory
  a step at a time, collecting garbage at each step, which took a
  quarter to a third of a first read's time in a new session.

The speed of reads and writes against arrow, nanoparquet and DuckDB,
and of other tools reading our files, is in
[bench/RESULTS.md](../bench/RESULTS.md#parquet).

## Errors and warnings

| message | cause | what to do |
|---|---|---|
| `column "x" is not in the file; its columns are ...` | a name in `col_select` the file does not have | check the name against `read_parquet_info(file)$columns$name` |
| `the file has nested columns, which are not read: "l", ...; select the columns wanted, or pass nested = "skip"` | a list, map or struct column, and no `col_select` that leaves it out | select the flat columns, or `nested = "skip"`; for the nested data, use arrow |
| `column "x" is nested (a list, map or group), which is not read` | `col_select` names a nested column | leave it out |
| `column "x" is FLOAT16, which is not read` (also `an INTERVAL, which this version does not read`) | a type this version does not read | leave the column out with `col_select` |
| `values encoded BIT_PACKED, which this version does not read yet`; `LZO compression is not supported`; `the Hadoop framing of LZ4 is not supported (LZ4_RAW is)` | an encoding or codec this version does not read | leave the column out, or rewrite the file with another tool's defaults |
| `column "x": the value 9007199254740993 in row 1 cannot be held exactly as a double; read with int64 = "integer64" or int64 = "character" to keep every digit` | an INT64, or unsigned 32- or 64-bit, value a double does not hold exactly | as it says |
| `column "x": the value 9252967440985262337 in row 302 cannot be held exactly as a 64-bit integer; read with int64 = "character" to keep every digit` | an unsigned 64-bit value of 2^63 or more, read with `int64 = "integer64"` | `int64 = "character"` |
| `column "x": the value 12345678901234567.89 in row 1 has more than 15 significant digits, which a double cannot hold exactly; read with decimal = "character" to keep every digit` | a DECIMAL value a double cannot give back | `decimal = "character"` |
| `column "x": row 2 is 1000000007 nanoseconds, which is not a whole number of microseconds; read with timestamps = "truncate" ...` | a nanosecond timestamp; a `POSIXct` holds microseconds | `timestamps = "truncate"` |
| `column "x": the value -2147483648 in row n cannot be held as an R integer, whose NA it is` | a 32-bit integer equal to R's `NA_integer_` | none in R; read the column with another tool |
| `not a Parquet file: it does not start and end with PAR1`; `the footer's length ... is more than the file holds` | not a Parquet file, or a truncated one | check the file |
| `the file is an encrypted Parquet file, which is not supported` | Parquet encryption | decrypt it with the tool that wrote it |
| `column "x", row group 2: ...` (at byte n) | a damaged page | the file is damaged at that column and row group |
| `unknown compression "lzo"; use one of "snappy", "zstd", "gzip", "lz4_raw" or "none"` | `save_parquet(compression = )` | one of those |
| `zstd levels run from 1 to 22, not 99`; `snappy has no compression levels` | `compression_level` | a level the codec has, or `NULL` |
| `save_parquet: cannot write x, a column of class complex` (or a list, `POSIXlt`, `difftime`, a nested data frame) | a column type Parquet files here do not hold | convert it first |
| `column "l": element 1 is not a raw vector or NULL; a list column must hold only raw vectors` | a list that is not binary data | convert it, or drop it |
| `column "b": row 1 holds 1000, which a byte column cannot hold` | a value outside its `storage` attribute's type | change or drop the `storage` attribute |
| `save_parquet: columns sharing label set "yn" have different labels` | two columns name one set with different labels | give one a different `label_set` |
| warning: `dropped "columns.x.storage" from the dta profile: ...` (and other `dropped ...` warnings) | a damaged or hand-edited profile | none needed; the values are read, the entry is not |
| warning: `the dta profile is not JSON (...); the file is read as plain Parquet` | the `dta` entry is damaged | as for any file from another tool |
| warning: `the dta profile is version 2, newer than this reader's 1; ...` | a newer writer | update datakit |
| warning: `column "x": row 3 holds a value that is not one of its 3 level numbers; it is read as .` (R: `as NA`; TypeScript counts rows from 0, code `DATAKIT_CATEGORICAL`) | another tool wrote a value into a categorical holding `.a` to `.z` | none needed; the value reads as `.` |
| warning: `column "x" is a categorical whose value label set "s" does not label 1 to 3 with its levels; a set made from the levels is used` | a hand-edited profile | none needed |
The TypeScript package gives the same messages, with its own option
names, and a `code` on each error ([Errors](typescript.md#errors)):

| message (TypeScript) | cause | what to do |
|---|---|---|
| `no variable "x"; the file's are ...` (`DTA_OUT_OF_RANGE`) | a name or index in `columns` the file does not have | check `r.variables` |
| `the file has nested columns, which are not read: "l"; select the columns wanted, or open with nested: "skip"` | `readRows` without `columns` on a file with a list, map or struct | select columns, or `{ nested: "skip" }` |
| `column "n": the value 9007199254740993 in row 1 ... read with int64: "bigint" to keep every digit` | `int64: "number"`, or statistics that understated a column's range | `{ int64: "bigint" }` |
| `maxStringBytes is for .dta files; Parquet strings are read whole` | `maxStringBytes` on a Parquet reader | leave it out |
| `x: a .dta file cannot hold 64-bit integers; use writeParquet` | `writeDta` given bigints | `writeParquet`, or numbers |
| warnings in `info.warnings` | a damaged or newer dta profile | as above |
