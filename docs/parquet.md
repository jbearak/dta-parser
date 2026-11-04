# Parquet files that keep what a `.dta` file says

datakit (R) reads and writes Parquet files that keep a `.dta` file's
value labels, variable labels, display formats, notes and extended
missing values `.a` to `.z`, and also factor levels and time zones. A
file it writes is ordinary Parquet that pyarrow, pandas, polars,
DuckDB, arrow and nanoparquet read; what Parquet has no place for goes
into one JSON entry of the file's metadata, the *dta profile*, which
those tools ignore. Only flat tables are read and written: nested
columns (lists, maps, structs) are not, so for nested data use arrow,
pyarrow or polars. The Python, Julia and TypeScript packages get the
same reader and writer later (plan 0018); this page gains their
sections then.

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

Nothing beyond the package: R, [Parquet: install](r.md#parquet-install).
Python, Julia, TypeScript: not yet.

### Read a whole file, and what each type becomes

R: [Read a Parquet file](r.md#read-a-parquet-file) and
[What each Parquet type becomes](r.md#what-each-parquet-type-becomes-in-r).

### Read some columns

R: [Read some columns](r.md#read-some-columns-of-a-parquet-file).

### Read a range of rows

R: [Read a range of rows](r.md#read-a-range-of-rows-of-a-parquet-file).
Only the row groups that hold the rows are read, and within them only
the pages that do: through the file's offset index, or, when it has
none, by walking the page headers.

### Get the schema and metadata without the data

R: [Schema and metadata](r.md#a-parquet-files-schema-and-metadata).

### Value labels and variable labels

R: [Labels](r.md#labels-in-parquet-files).

### Dates and timestamps, with time zones

R: [Dates and time zones](r.md#dates-and-time-zones-in-parquet-files).

### Write a table; compression and row groups

R: [Write a Parquet file](r.md#write-a-parquet-file). The defaults are
[below](#defaults-and-the-measurements-behind-them).

### Write labels and a data label, and check them

R: [Write labels](r.md#write-labels-to-a-parquet-file).

### Keep `.a` to `.z` through a write and a read

R: [Keep .a to .z](r.md#keep-a-to-z-in-a-parquet-file).

### Read a file another tool wrote

R: [Files from other tools](r.md#parquet-files-from-other-tools).

## The file

A file is plain Parquet: every column OPTIONAL, data pages v1, with
statistics, an offset index, the legacy converted types beside the
logical types, and an `ARROW:schema` entry so that pyarrow, polars and
arrow restore factors and time zones. What each value becomes:

| what is written | Parquet physical type | logical type |
|---|---|---|
| Stata byte | INT32 | INT(8, signed) |
| Stata int | INT32 | INT(16, signed) |
| Stata long; R integer | INT32 | none |
| R `integer64` | INT64 | none |
| Stata float | FLOAT | none |
| Stata double; R double | DOUBLE | none |
| R logical | BOOLEAN | none |
| text: strN, strL, R character | BYTE_ARRAY | STRING |
| binary: a binary strL, an R list of raw vectors | BYTE_ARRAY | none |
| R `Date` | INT32 | DATE |
| R `POSIXct` | INT64 | TIMESTAMP(MICROS, adjusted to UTC); the zone in the profile and `ARROW:schema` |
| R factor | BYTE_ARRAY, dictionary-encoded, every level in order in every row group | STRING; levels and ordering in the profile |

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
  that it reads back unchanged.
- A reader takes a DOUBLE value as `.a` to `.z` only when its bits are
  exactly that pattern with a letter `a` to `z`; any other NaN is NaN,
  a value.
- `save_parquet(missing_letters = FALSE)` writes `.a` to `.z` as nulls,
  for files meant for tools that count NaN as a value. The letters are
  then lost.

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
  written so because of `.a` to `.z`, `storage` or `logical`.
- `value_labels` maps a set's name to an array of `[code, text]` pairs.
  A code is a JSON number, finite and within ±2^53 if it is an integer,
  or a missing code as text: `"."` or `".a"` to `".z"`. An array keeps
  numeric codes as numbers, which object keys would not.
- `characteristics` maps `_dta` or a column name to its named texts;
  `notes` and `sort` (column names) are arrays of text; `label` is the
  data label.
- **Reading is forgiving.** `version` is 1; a higher one is read for
  what is known, with one warning. The profile must be a JSON object of
  at most 64 MiB with no duplicate keys at any level. An entry that
  breaks a rule (a label set that is not a list of pairs, a code given
  twice, a `levels` list with a level twice, a `value_labels` name with
  no set, a `storage` or `logical` on a column that is not DOUBLE) is
  dropped with one warning naming it, and the rest is used. A profile
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

- **Compression: zstd at level 3.** In
  [the codec measurements](research/parquet-codecs.md), zstd 3 through
  C libzstd made DHS data a quarter of snappy's size (a ratio of 0.022
  against 0.086), writing at 2.6 GB/s and reading at 3.7 GB/s against
  snappy's 4.3 and 4.4. Columns are compressed in parallel, so the
  slower codec costs little time; the write measurements below compare
  the two. `snappy`, `gzip`, `lz4_raw` and `none` are there on request.
- **Row groups: up to 262,144 rows (polars' default) and about 1 GiB of
  values.** The plan had 64 MiB, which made a DHS file of 5,000 columns
  four row groups where pyarrow and polars write one; pyarrow then took
  2.4 times as long to read our file as its own, and polars 1.6 times.
  At 1 GiB survey files are one row group, as those tools write them,
  and a long file is cut at 262,144 rows.
- **Pages** of about 1 MiB of values, data page v1, which every reader
  reads. Dictionary encoding for a column chunk while its dictionary
  stays under 1 MiB and smaller than 60% of the values it replaces;
  past either, the rest of the chunk is PLAIN. No DELTA or
  BYTE_STREAM_SPLIT encodings, which some readers cannot read.
- **Threads: up to two, for reads and writes of 16 MB or more.** By
  plan 0007's rule, each thread added must speed the task up by at
  least half of one thread's work, and CPU time must stay within 1.15
  times one thread's. A third thread missed on NSFG 1995 reads
  (it added 0.48 of a thread's speed) and on writes of NSFG 1995 and a
  DHS women's file (0.43 and 0.37). `DTA_THREADS` and each language's
  threads option change the count. The measurements at 1 to 12
  threads are in [bench/RESULTS.md](../bench/RESULTS.md#parquet).

The speed of reads and writes against arrow, nanoparquet and DuckDB,
and of other tools reading our files, is in
[bench/RESULTS.md](../bench/RESULTS.md#parquet).

## Errors and warnings

| message | cause | what to do |
|---|---|---|
| `column "x" is not in the file; its columns are ...` | a name in `col_select` the file does not have | check the name against `read_parquet_info(file)$columns$name` |
| `the file has nested columns, which are not read: "l", ...; select the columns wanted, or pass nested = "skip"` | a list, map or struct column, and no `col_select` that leaves it out | select the flat columns, or `nested = "skip"`; for the nested data, use arrow |
| `column "x" is nested (a list, map or group), which is not read` | `col_select` names a nested column | leave it out |
| `column "x" is DECIMAL, which this version does not read yet` (also INT96, TIME, unsigned integers, FIXED_LEN_BYTE_ARRAY, FLOAT16) | a type this version does not read | leave the column out with `col_select` |
| `values encoded DELTA_BINARY_PACKED, which this version does not read yet` (also the other DELTA encodings and BYTE_STREAM_SPLIT); `BROTLI compression is not read yet`; `LZO compression is not supported` | an encoding or codec this version does not read | leave the column out, or rewrite the file with another tool's defaults |
| `column "x": the value 9007199254740993 in row 1 cannot be held exactly as a double; read with int64 = "integer64" or int64 = "character" to keep every digit` | an INT64 value beyond 2^53 | as it says |
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
