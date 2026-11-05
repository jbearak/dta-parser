# Plan: datakit in Python and Julia; Parquet leaves the format packages

Status: approved at Gate 1 by Claude Sonnet and GPT Terra (revision 7,
after seven rounds; see `docs/judging/datakit-design/`).

## Goal

Plan 0018 put Parquet reading and writing into four packages: R's
datakit, and the format packages of the other three languages
(dta_parser for Python, DtaParser.jl, `@jbearak/dta-parser` for npm).
In R, ADR 0032 had already split the format package (dtaparser: `.dta`
I/O and its R representation) from the data-prep package for do-files
translated to R (datakit). The user asked for the same split in the
other languages:

1. `read_parquet`, `write_parquet` and the info call move out of
   dta_parser and DtaParser.jl into a datakit package in each language,
   with `read_fixed_width`, as they did in R.
2. **Python's datakit is polars-first.** A downstream translator writes
   polars code, not pandas. `df, meta = read_parquet(path)` returns a
   `polars.DataFrame` and a separate label object, and
   `save_parquet(df, path, meta=meta)` writes `meta` into the dta
   profile, the same one R writes, so files go between languages.
   `meta` holds variable labels, value labels, display formats and the
   `.a` to `.z` codes, keyed by column.
3. **Julia's datakit returns a DataFrame**, with labels in
   `colmetadata`, rather than a `DtaTable`, if `.a` to `.z` can be held
   there.
4. **No Stata-style helpers** (an equivalent of R's `:=`) in Python or
   Julia. polars' `when/then/otherwise` with `.over()`, and
   DataFrames.jl's `transform!`, are how those languages do it.
5. **TypeScript:** decide whether a datakit npm package makes sense, or
   whether Parquet stays in `@jbearak/dta-parser`.
6. **No release.** Nothing goes to PyPI, npm or the Julia registry, and
   no release tag is made.

Plan 0018's speed targets and its Gate 2 documentation judging carry
over, with polars and pyarrow's `Table` as the comparison in Python.

## Why a separate label object in Python

Checked on polars 2.1.0 (2026-11-05):

- A polars `DataFrame` has no frame or column metadata.
- polars extension types keep a dtype's parameters (labels could ride
  on one) through filter, sort, join, concat, `when/then` and a Parquet
  round trip. But `==`, arithmetic, `mean`, `fill_null` and casts reject
  them unless every use unwraps with `.ext.storage()`, and polars marks
  them unstable. A translator would have to unwrap at every use.
- pandas `attrs` were lost after a groupby aggregation, so pandas is no
  better a home.

So the frame holds plain polars columns, and what polars cannot hold
travels beside it.

## Packages after the move

| language | format package (`.dta`) | datakit |
|---|---|---|
| R | dtaparser: `read_dta`, `save_dta`, labels, tagged NA | `read_parquet`, `read_parquet_info`, `save_parquet`, `read_fixed_width`, `:=` (unchanged) |
| Python | dta_parser: `read_dta`, `write_dta`, `read_meta` (`.dta` only), `StataArray`, all pandas | `read_parquet`, `read_parquet_info`, `save_parquet`, `read_dta`, `save_dta`, `read_fixed_width`, `Meta`, `Column`, `ParquetInfo`, `LETTERS`, `letters_to_columns`, `FixedWidthWarning`, all polars |
| Julia | DtaParser: `read_dta`, `write_dta`, `read_meta` (`.dta` only), `DtaColumn` | `read_parquet`, `read_parquet_info`, `save_parquet`, `read_fixed_width` |
| TypeScript | `@jbearak/dta-parser`: `.dta` and Parquet (below) | none |

Python's datakit also reads and writes `.dta` (below), because its
frames are polars and dta_parser's are pandas; in R and Julia the
format package already returns the frame datakit uses
(`DataFrame(read_dta(f))` in Julia).

### Native code stays in the format package

As in R (ADR 0032), one Rust build per language. Python's datakit is
pure Python and calls `dta_parser._native`; Julia's calls the library
DtaParser loads. dta_parser's wheel and DtaParser's library therefore
still carry the Parquet code and codecs, although neither exports
Parquet, as dtaparser's does in R.

- **The contract.** The functions datakit calls are named, documented
  as for datakit only, and versioned by an ABI number:
  `dta_parser._native.ABI_VERSION` (new; Python has none today) and
  Julia's existing `ABI_VERSION` in DtaParser's `lib.jl`. Julia's
  datakit reaches DtaParser's internals through one module,
  `DtaParser.Internals`, which lists what it re-exports for Datakit
  (the native call wrappers, the column builders, the JSON reader, the
  error type). Each datakit checks the ABI number when it loads and
  stops with a message naming both versions and the reinstall to do.
- **Versions.** dta_parser 0.2.0 and DtaParser 0.2.0 lose exports, so
  both become 0.3.0. dta-datakit and Datakit start at 0.3.0, and
  require their format package `>=0.3, <0.4` (Python) and `0.3`
  (Julia compat). The ABI check, not an exact pin, is what guards the
  native contract, as in R. Tags are made when the user publishes;
  none now (goal 6).
- **Dependencies.** dta-datakit requires `polars>=2.0,<3` and `dta-parser`.
  dta-parser requires numpy and pandas, so installing dta-datakit
  installs pandas too; that is stated in its README. Importing datakit
  does not import pandas: `dta_parser/__init__.py` loads its pandas
  names lazily (module `__getattr__`), so `import dta_parser._native`
  runs no pandas code. The PR measures `import datakit` time.
  Julia's Datakit depends on DtaParser, DataFrames (compat from the
  oldest version its keep/lose tests pass on, found in PR 3; DtaParser
  allows 1.4), DataAPI, Tables and
  Dates, with TimeZones and CategoricalArrays as package extensions.

### Where they live, names, install

- `python/datakit/` (its own `pyproject.toml`, the package in
  `python/datakit/datakit/`, tests in `python/datakit/tests/`) and
  `julia/Datakit/`, beside `r/datakit/`.
- The Python distribution is `dta-datakit`, since `datakit` on PyPI
  belongs to another project (0.0.9, which has no files to install,
  checked 2026-11-05); the import name is `datakit`, as R's package
  name, so a translated script reads alike in both languages
  (`import datakit as dk`). The README says that the two cannot be
  installed in one environment. The Julia package is `Datakit` (no
  General registry entry by that name or `DataKit`, checked
  2026-11-05).
- **Install while unpublished**, documented in each README and in the
  language page's install section, and tested from a clean environment
  in the PR: Python, `pip install ./python ./python/datakit` from a
  checkout (Rust and a C compiler needed, as for dta_parser today);
  Julia, `Pkg.develop(path="julia/DtaParser")` then
  `Pkg.develop(path="julia/Datakit")`, which builds the library through
  DtaParser's `deps/build.jl`. Datakit's `Project.toml` also names
  DtaParser's path under `[sources]`, which Julia 1.11 and later use.
- **CI.** `ci.yml` gains a job per package (tests, docs tests) and the
  Python sdist offline build; while GitHub's runners are unavailable
  these run locally, Linux in Docker, with results in each PR's
  comment.

### The same verbs in every datakit

R's names: `read_parquet`, `read_parquet_info` and `save_parquet` in
Python and Julia too (they called the info call `read_meta`; in Python
`meta` now names the label object, so the old name would mislead).
dta_parser's and DtaParser's `read_meta` stay, for `.dta` only. Julia
keeps its convention of the destination first,
`save_parquet(path, df)`, as `write_dta(path, table)` and `CSV.write`
do; Python and R put the frame first.

## Python: datakit (polars)

```python
import datakit as dk

df, meta = dk.read_parquet(source, columns=None, skip=0, n_max=None,
                           factors=False, letters="meta",
                           letter_suffix="_letter", timestamps="error",
                           nested="error")
info = dk.read_parquet_info(source)
dk.save_parquet(df, path=None, meta=None, *, compression="snappy",
                compression_level=None, row_group_size=None,
                missing_letters=True, timestamps="error")

df, meta = dk.read_dta(path, columns=None, skip=0, n_max=None,
                       factors=False, letters="meta",
                       letter_suffix="_letter", encoding=None,
                       timestamps="error")
dk.save_dta(df, path, meta=None, *, missing_letters=True,
            timestamps="error")
df, meta = dk.read_fixed_width(path, setup, recodes="setup",
                               columns=None, skip=0, n_max=None,
                               commented_formats=True, letters="meta",
                               letter_suffix="_letter")
df = dk.letters_to_columns(df, meta, columns=None, suffix="_letter")
```

`source` is a path, `bytes` or a binary file object with `seek`, as now.
`save_parquet` returns the file as `bytes` when `path` is None. Every
read returns a tuple, so the docs' first example unpacks it, and say
that `dk.read_parquet(p).filter(...)` fails.

**When to use polars instead.** The Python page's first paragraph on
Parquet says: for a file without a dta profile, or for lazy queries,
predicate pushdown, many files, cloud paths or nested columns, use
`pl.scan_parquet` and `DataFrame.write_parquet`. datakit is for files
that carry labels and `.a` to `.z`, which polars drops, and for the
files a translated do-file reads and saves.

### What a read returns

`df` is a `polars.DataFrame`. Every missing value, `.` and `.a` to
`.z` alike, is a polars null, so `is_null()`, `drop_nulls()`, `mean()`
and `count()` treat them as Stata treats missing values.

| Parquet | polars |
|---|---|
| INT(8), INT(16), INT32, INT64 | Int8, Int16, Int32, Int64, with nulls |
| unsigned 8 to 64 | UInt8 to UInt64 |
| a DOUBLE written so for `.a` to `.z` (profile `storage`) | its storage type again: Int8 for byte, Int16 int, Int32 long, Float32 float |
| a DOUBLE with profile `logical` `date` | Date; a value with a fraction of a day is an error naming the column and row, unless `timestamps="truncate"`, which drops the fraction. A value outside Date's range, an infinity or a NaN that is not a letter is an error in both modes |
| a DOUBLE with profile `logical` `timestamp` | Datetime("us", tz). A value is read as the nearest whole number of microseconds when that count `n`, converted back to seconds as `n / 10^6` in doubles, gives the same double (the rule by which the writers chose DOUBLE, `docs/parquet.md`), so 0.1 s written from 100,000 µs reads exactly; any other value is an error naming the column, the row and `timestamps="truncate"`, which truncates to the microsecond. A value outside Datetime("us")'s range, an infinity or a NaN that is not a letter is an error in both modes |
| FLOAT, DOUBLE | Float32, Float64; NaN stays a value, not a null |
| DECIMAL, precision up to 38 | Decimal(precision, scale), exact; `save_parquet` does not write Decimal (below), so cast before saving |
| DECIMAL, precision above 38 (polars' limit) | String, every digit kept |
| DATE | Date |
| TIMESTAMP | Datetime(unit, tz): the file's unit, except the profile's `"unit": "s"`, which polars lacks, reads as "ms"; the zone from the profile, else `ARROW:schema`, else "UTC" when adjusted to UTC; no zone when not adjusted |
| INT96 | Datetime("ns") |
| TIME | Time (nanoseconds; exact for every unit) |
| STRING, ENUM, JSON | String |
| BYTE_ARRAY, FIXED_LEN_BYTE_ARRAY without annotation, UUID | Binary |
| categorical (profile) | Enum(levels), every level in order, unused ones too |
| dictionary of strings in `ARROW:schema`, no profile entry | Categorical (levels as the rows read give them, as in plan 0018) |
| BOOLEAN | Boolean |
| FLOAT16, INTERVAL | errors naming the column, as in plan 0018: the core does not decode them (polars could hold FLOAT16, so reading it is a core change for later) |
| nested (LIST, MAP, groups) | an error naming them, or left out with `nested="skip"`, as in plan 0018 |

So every value is exact or an error, as plan 0018 requires. R's
`int64` and `decimal` options and Julia's `decimal` have no Python
counterpart: polars holds those types.

### `Meta`

```python
@dataclass(eq=False)
class Meta:
    label: str | None = None
    notes: list[str] = field(default_factory=list)
    characteristics: dict[str, dict[str, str]] = field(default_factory=dict)
    sort: list[str] = field(default_factory=list)
    timestamp: str | None = None
    columns: dict[str, Column] = field(default_factory=dict)
    value_labels: dict[str, dict[int | float | str, str]] = field(default_factory=dict)
    missing: dict[str, pl.Series] = field(default_factory=dict)
    letter_columns: dict[str, str] = field(default_factory=dict)
    rows: int = 0      # the frame's height as read

@dataclass
class Column:
    label: str | None = None           # variable label
    format: str | None = None          # display format
    value_labels: str | None = None    # name of its set in Meta.value_labels
    ordered: bool | None = None        # an Enum column's profile "ordered"
```

- **Plain mutable values.** Every container is the caller's to change;
  defaults are fresh per instance. `meta == other` compares every field,
  Series with `Series.equals`. `meta.copy()` is a deep copy (Series
  cloned).
- **Value labels** are kept by set, as in a `.dta` file and the
  profile, since several columns may share one. A code is an `int` or
  `float`, or a missing code as text (`"."`, `".a"` to `".z"`). Sets no
  column names are kept and written. `meta.labels("x")` returns column
  `x`'s set itself (changes to it change `meta`), `{}` if `x` has none,
  and raises `KeyError` naming the column when `meta.columns` has no
  `x`.
- **Storage.** The polars dtype says it (Int8 byte, Int16 int, Int32
  long, Float32 float). A column that held `.a` to `.z` gets its storage
  type back from the profile.
- **Categoricals and dates** need no entry: Enum, Date and Datetime
  carry them. `Column.ordered` keeps the profile's `ordered`. polars'
  Enum always compares by level order, so an unordered factor from R
  reads as an Enum that still sorts and compares by level; the docs
  say so, and `ordered` is written back unchanged.
- **The digests** behind the `meta.missing` check (below) live in a
  private field, `Meta._digests`, keyed by column. `==` ignores them;
  `copy`, `rename` and `select` carry them with their columns; a digest
  whose column has no `meta.missing` entry is ignored.
- **`meta.rename(mapping)`** and **`meta.select(names)`** return a new,
  deep-copied `Meta` for `df.rename(mapping)` and `df.select(names)`.
  They rename or keep the names in `columns`, `missing` (each Series
  given its new name with `.alias`), `letter_columns`,
  `characteristics` and `sort`. A name that `meta.columns` lacks is a
  `KeyError`; a rename onto an existing name is a `ValueError`.
  `select` keeps `sort` up to its first unselected column, since the
  rest no longer says how rows are ordered. Value label sets are all
  kept. With `labels`, `letters`, `copy` and equality, these are all
  of `Meta`'s methods; it does not follow polars operations.
- **`sort` is checked when saving**, since row operations can make it
  false: if `df` is not in `meta.sort`'s order as Stata orders rows
  (values ascending, then `.`, then `.a` to `.z`, the letters taken from
  the companion or `meta.missing`), `save_parquet` and `save_dta` leave
  it out with one warning naming it. polars' `df.sort("x")` puts nulls
  first, so it fails the check; the docs' sort recipe (below) passes.

### `.a` to `.z`

In `df`, every row holding `.a` to `.z` is null. The `letters`
argument of every read says where the letters go, and `save_parquet`
and `save_dta` take them from either place:

1. **In `meta.missing`** (the default, `letters="meta"`). For each
   column holding a letter in the rows read, `meta.missing[name]` is a
   polars Series of the frame's length, of dtype `dk.LETTERS`
   (`pl.Enum([".a", ..., ".z"])`), with the letter where a row has one
   and null elsewhere. It is positional: it describes `df` as read.
   `meta.letters(name)` returns that Series, or an all-null one of
   `meta.rows` rows for a column without letters, so code need not know
   whether a file or a window held letters. It raises a `KeyError` for a
   name `meta.columns` lacks, and a `ValueError` naming the companion for
   a column whose letters are in one (below), so it never answers "no
   letters" where there are some.
2. **In the frame**, as companion columns. A companion of column `x`
   is `x_letter` (the suffix is `letter_suffix`), of dtype `LETTERS`, placed after `x`, holding `x`'s
   letters and null elsewhere; `meta.letter_columns["x"] = "x_letter"`
   records the pair, and `x` has no `meta.missing` entry. It follows its
   rows through row-preserving operations (filter, sort, join, concat,
   `when/then`) because it is a column; an aggregation or an expression
   that builds a new `x` is the caller's to mirror on `x_letter`.
   - `letters="columns"` gives every **eligible** column a companion,
     all null where it has no letters, so the same generated code runs
     on any file or window. Eligible is decided by the column's type in
     the file, before `factors`: a byte, int, long, float or double, a
     date or a timestamp, which is any column a letter can be written to
     (not 64-bit or unsigned integers, booleans or text). A labelled
     column that `factors=True` makes an Enum stays eligible, since
     `save_dta` keeps its letters. It costs a byte and a bit per row per
     column, which the docs state; on a wide survey file that is a second
     set of columns.
   - `letters=["x", "y"]` gives companions to those columns only, all
     null where they have none; a name that is not eligible is an error.
     Every other column's letters stay in `meta.missing`, as in the
     default, so a translator that names only the columns it changes
     loses none.
   - A companion name that is already a column of the file is an error
     naming it and `letter_suffix`.
   - `dk.letters_to_columns(df, meta, columns=None, suffix="_letter")`
     does the same after a read in the default mode, before rows change:
     `columns=None` means every eligible column, a list those columns.
     It returns the new frame and **changes `meta` in place**, moving the
     columns' letters from `meta.missing` to `meta.letter_columns`; the
     docstring says so. Before moving a column's letters it makes the
     check `save_parquet` makes on `meta.missing` (the frame's height,
     the column's digest), and stops with the same error if the rows
     have changed, so stale letters never become a companion; the
     equal-value blind spot applies here too, and a test reorders rows
     and expects the error. A companion name already in `df` is an error
     naming it and `suffix`; a column already paired is left as it is.
   - `letters=None` keeps no letters: they are nulls like `.`, and
     nothing is built for them.

A translator should generate `letters="columns"`, or name with
`letters=[...]` every column its code gives letters to. The docs say so
in the section's first paragraph, with polars' traps for code that
compares letters:

- `pl.col("x_letter") != ".d"` is null, not true, on every row without
  a letter, so a `filter` drops all valued rows; a do-file's
  `if x != .d` is `pl.col("x_letter").ne_missing(".d")`.
- polars sorts nulls first and does not keep the order of ties unless
  asked; Stata sorts missing values last. A do-file's `sort x` is
  `df.sort(["x", "x_letter"], nulls_last=[True, False],
  maintain_order=True)`: values, then `.`, then `.a` to `.z`, ties in
  their order (checked on polars 2.1.0). Stata's sort is not stable,
  so `maintain_order` gives one of the orders it could give.

Recipes in the docs, each a test:

- **Set a letter** (`replace x = .d if age < 15`):
  ```python
  cond = pl.col("age") < 15
  df = df.with_columns(
      pl.when(cond).then(None).otherwise(pl.col("x")).alias("x"),
      pl.when(cond).then(pl.lit(".d", dk.LETTERS)).otherwise(pl.col("x_letter")).alias("x_letter"),
  )
  ```
- **Replace a letter with a value**: set `x` and set `x_letter` to
  null in the same `with_columns`. A row where both hold something is
  an error when saving (below), never resolved silently.
- **New column** (`gen y = .a`): `pl.lit(None, pl.Float64)` for `y`
  and `pl.lit(".a", dk.LETTERS)` for `y_letter`, then
  `meta.letter_columns["y"] = "y_letter"`.
- **Joins.** Companion columns travel with their rows. polars renames
  a right-hand column whose name is taken (`x_right`, `x_letter_right`);
  the pairs and labels of the right frame are then the caller's to add
  (`meta.columns["x_right"] = right_meta.columns["x"]`, and the same
  for `letter_columns`), shown in the docs.
- **Aggregation** (`group_by().agg()`): a mean or a count of `x` is a
  new value, and its letters do not carry over; `x_letter` is kept
  only if aggregated itself (e.g. `pl.col("x_letter").first()`).
  `meta` for the new frame is the caller's (`meta.select(...)` for the
  group keys).

### `save_parquet`

- Takes a `polars.DataFrame`, and `meta` or None. A `LazyFrame` is a
  `TypeError` saying to `.collect()` it.
- **Types written**, by polars dtype: Int8, Int16, Int32, Int64; UInt8,
  UInt16, UInt32, UInt64 as Parquet's unsigned types (INT(8, false) to
  INT(64, false); new in the core's writer, with unsigned statistics),
  so they read back as themselves; Float32, Float64; Boolean; String;
  Binary; Date; Datetime of any unit, with or without a zone; Time (as
  TIME(NANOS), new in the core's writer); Enum and Categorical (text
  categoricals, every level in every row group, as plan 0018); Null (an
  all-null column, as `pl.lit(None)` makes, written as an all-null
  DOUBLE, as `gen x = .` makes a float in Stata). Errors, each naming
  the column and what to cast to: Decimal (writing DECIMAL needs an
  encoder no `.dta` or R type needs; cast to Float64 or String),
  Duration, List, Array, Struct, Object, and any other dtype (Float16,
  Int128, UInt128 among them).
- **From `meta`:** the data label, notes, characteristics, sort (if
  true, above), time stamp, each column's label, format, value label
  set and `ordered`, and every set. Entries for names not in `df` are
  dropped without a warning (the frame was selected after reading). An
  Enum or Categorical column is written as a categorical, its levels
  being its text, so its `value_labels` name is not written; after
  `factors=True` and a save, that column reads back with
  `Column.value_labels` None and its set still in `meta.value_labels`.
  Writing is strict, as in plan 0018: a code that is not finite or
  beyond ±2^53, a column naming a set `meta.value_labels` lacks.
- **Letters.** Companion columns first: for each pair in
  `meta.letter_columns` whose `x` is in `df`, the companion must be in
  `df` too (a `select` that kept `x` and dropped `x_letter` is an error
  naming both, unless the caller removed the pair with
  `del meta.letter_columns["x"]` or passed `missing_letters=False`),
  of dtype `LETTERS` (or String holding only `.a` to `.z` and null),
  and null wherever `x` is not null; the companion is not written as a
  column. Then `meta.missing`: a column with both is an error. Each
  Series must have `df.height` rows, and `x` must be unchanged since it
  was read: the reader computes a 64-bit digest of `x` as it returns it
  (after `factors`), kept in `Meta._digests`, and `save_parquet`
  computes it again and compares. Digests are computed only for the
  columns that have a `meta.missing` entry, in a native pass over the
  finished column after decoding (and after `factors`, over the Enum),
  so a read without letters computes none and the decoder does no extra
  work; a test checks that a window without letters has no digests. The
  digest hashes each row's null flag and its value in a form that is the
  same across lossless casts and different for different values: an
  integer, or a float that is a whole number within ±2^127, as its exact
  integer value; any other float as the bits of its value as a double
  (a Float32 widened first, so Float32 to Float64 passes; NaN as one
  pattern); a date as its day count; a datetime as its exact count of
  nanoseconds in a 128-bit integer, so no date overflows; text and Enum values as their UTF-8 bytes. So Int32 to
  Int64, Int32 to Float64 and Float32 to Float64 pass, and Int64 2^53 + 1
  cast to Float64 (which becomes 2^53) and a Float64 to Float32 cast that
  rounds a value fail, while one whose values Float32 holds exactly
  passes; tests cover each. A filter, a
  join, a sort that moves a value,
  `fill_null`, or any change to `x`'s values fails the check, with an
  error that names the column and says to carry the letters with
  `letters_to_columns` before changing rows, or to drop them with
  `meta.missing.pop("x")`. This is validation, not proof: a reordering
  that leaves every value of `x` in place cannot be seen, which happens
  whenever the rows exchanged hold equal values, as in a column that is
  all missing or all one value; the docs say so.
- A column whose letters pass is written as plan 0018 writes one: DOUBLE
  with tagged NaNs, its storage or logical type in the profile. Int64,
  UInt64, UInt32 and Boolean columns with letters are errors, as plan
  0018 decided (a double cannot hold them). A date or timestamp column
  with letters is DOUBLE with `"logical"` in the profile, as plan 0018
  writes R's; a timestamp there is seconds in a double. A Datetime("ns")
  value with a part below a microsecond is an error naming the column
  and row, unless `timestamps="truncate"`, which drops that part. A
  value far enough from 1970 (past about the year 2255) that a double of
  seconds no longer holds its whole microseconds is an error in both
  modes, since truncating to the microsecond does not make it fit. UInt8 and UInt16 columns with letters are errors too (a
  file never gives them letters; only a cast could). An Enum or
  Categorical column with letters is an error,
  since a categorical cannot hold a tagged NaN; the error names the column and says to save it as `.dta`
  (below), drop its letters, or read without `factors`.
  `missing_letters=False` writes letters as nulls.
- **Stray companions.** A column of dtype `LETTERS` that no pair names
  (saved with `meta=None`, or after the pair was removed) is written as
  an ordinary categorical, with one warning naming it, since its letters
  are then not attached to any column.
- **Stale pairs.** A pair whose `x` is not in `df` but whose companion
  is, is an error naming both (drop the companion, or remove the pair),
  rather than writing `x_letter` as an ordinary column.
- **Categorical levels.** An Enum writes every level of its dtype. A
  Categorical writes the categories its values use, in the order polars
  lists them (polars 2 may share one category set among many columns,
  and that set is not the column's).

### `factors=True`

As R's `read_parquet(factors = TRUE)` (`labelled_factor` in
`r/datakit/R/parquet.R`): a column with a value label set becomes
`pl.Enum` whose levels are the column's distinct values and the set's
codes, in order of value, each labelled code as its text and every
other value as its number in text (as an integer for byte, int and long
columns); repeated texts are one level; missing codes' labels are not
levels, and missing values are null. Unlike R, `.a` to `.z` are not
lost: they stay in `meta.missing` or the companion column, so there is
no warning. `Column.value_labels` keeps the set's name, so
`meta.labels("x")` still works. A cross-language test reads one file
with `factors` in R and Python and compares levels and values.

**What `factors=True` loses**, said beside the argument in the docs and
docstring: the codes are gone from the frame (only the text is kept),
and codes sharing a text (two codes both labelled "Yes") become one
level that cannot be told apart again. Saving such a frame does not
restore them: `save_parquet` writes the Enum as a categorical of its
levels (and refuses it if the column has letters, above), and
`save_dta` writes it as R's `save_dta` writes a factor, as Stata's
`encode` would: codes 1 to k, stored as long, labelled with the levels
in order, with the column's letters kept, since a long holds `.a` to
`.z`. To keep the file's codes, read with `factors=False`, the default.
The round-trip tests treat `factors=True` frames as this exception,
with a duplicate-label case.

### `read_parquet_info`

Reads the footer only and returns a `ParquetInfo` dataclass (equality
as `Meta`'s): `rows`, `row_groups` (a polars DataFrame of rows and
bytes per group), `compression`, `created_by`, `key_value` (every
key-value entry of the footer, as text, `dta` and `ARROW:schema`
included), `meta` (the `Meta` a read would give, with `missing` empty
and `rows` the file's), and `columns`: a polars DataFrame with one row
per Parquet column of `name`, `role` (`data` or `nested`), `dtype` (the
polars dtype `read_parquet` will give, as text), `physical_type`,
`logical_type`, `label`, `value_labels` (set name) and `storage`.

### `.dta` in polars: `read_dta`, `save_dta`, `read_fixed_width`

A translated do-file starts with `use` and often ends with `save`, so
Python's datakit reads and writes `.dta` into the same `(df, meta)`:

- `read_dta` decodes through a new Arrow output of dta_parser's `.dta`
  reader (PR 2a, below), not through pandas, with the same `Meta` (the
  file's time stamp in `timestamp`, release and encoding not kept, as
  plan 0018 left them out of the profile). It reads releases 104 to 119
  as dta_parser does; `encoding` is dta_parser's, for text in files
  before release 118. Columns: byte, int, long, float, double as Int8,
  Int16, Int32, Float32, Float64 with nulls; strN and text strLs as
  String, binary strLs as Binary. A strL column that mixes text and
  binary values (which dta_parser keeps as `str` and `bytes` side by
  side) is Binary, its text values as their UTF-8 bytes, as plan 0018
  reads such a column from Parquet; the cell-by-cell test expects those
  bytes. Dates, by display format: `%td` is
  Date, and a value with a fraction of a day is an error naming the
  column and row unless `timestamps="truncate"` (one outside Date's
  range is an error in both modes); `%tc` is
  Datetime("ms") (a `.dta` datetime holds milliseconds, where
  `read_parquet` gives R's timestamps as Datetime("us"), so a join or
  comparison across the two needs a cast; the docs say so beside the
  type rows), and a value with a fraction of a millisecond is an
  error naming the column and row unless `timestamps="truncate"`, which
  drops the fraction. A value outside polars' Datetime range is an error
  naming the column and row in both modes, since truncating does not
  bring it into range; tests cover both modes at each edge. `%tC` (which counts leap seconds) and the other `%t`
  formats (`%tw`, `%tm`, `%tq`, `%th`, `%ty`) stay numbers, with the
  format in `meta`. `.a` to `.z` in a date column are nulls with their
  letters, since dates are eligible.
- `save_dta` calls dta_parser's native release-118 writer directly,
  with an Arrow input (PR 2a), not `write_dta` and not pandas, with the
  checks `write_dta` makes and the letter rules of `save_parquet`.
  Dates are written as `write_dta` writes them. An
  Enum or Categorical is written as `encode` would make it (above).
  Datetime becomes `%tc`, which holds milliseconds; a value that is not
  a whole number of milliseconds is an error naming the column and row,
  unless `timestamps="truncate"`. Types `.dta` cannot hold (Int64
  beyond a double, Binary outside strL, Time) are errors naming the
  column, as `write_dta`'s are.
- `read_fixed_width` moves from dta_parser with its arguments, returns
  `(df, meta)`, and reads the core's conversion through `read_dta`'s
  Arrow output. Codes given a letter by `recodes="tagged"` are letters as
  above. Warnings are `datakit.FixedWidthWarning`.

Each is tested cell by cell against `dta_parser.read_dta` on every
fixture: the same missing code where either has one; otherwise equal
numbers (integers exactly, floats by bits), equal text, a Date equal to
dta_parser's `datetime64` at midnight, a Datetime("ms") equal to its
`datetime64`; dta_parser's numbers for a date column it left as numbers
(a fraction, `%tC`, letters) are compared with ours as days or
milliseconds, and the fractional fixtures with `timestamps="truncate"`
as the truncated value (with the default, as the error); `save_dta` by
reading its files back
with `dta_parser.read_dta`. Their speed is measured and published
against dta_parser's pandas reader and writer, not gated: plan 0018's
gate is for Parquet.

### How the frame is built: Arrow memory polars adopts

polars imports Arrow memory through the PyCapsule interface
(`__arrow_c_stream__`) with `pl.DataFrame(obj)`, without pyarrow
(checked on polars 2.1.0). dta_parser's native module gains functions
that decode into Arrow buffers and hand them over, and that read
polars' export (`df.__arrow_c_stream__()`) for writing. These are new
outputs and inputs of the core beside the ones R, Julia and npm use,
which keep their behaviour; the core's shared decoding code changes
for speed (step 4 below), under the no-regression gate in "Speed and
memory".

- **Numbers.** The core decodes values into a buffer the binding
  allocates and nulls straight into an Arrow validity bitmap. The rare
  `.a` to `.z` go into a sparse list of (row, letter) per column, from
  which the binding builds `meta.missing` or the companion. The digest
  is computed afterwards, by a native pass over each finished column
  that has a `meta.missing` entry (after `factors`), as "Letters" under
  `save_parquet` says; the decoder does no hashing.
- **Text.** polars' string type is Arrow's string view (16 bytes a row,
  strings of up to 12 bytes inline). A dictionary-encoded chunk becomes
  views into its dictionary bytes, so a column of few distinct values
  costs 16 bytes a row and no copy of the text; PLAIN text becomes one
  buffer with views into it. Views are built on the worker threads, in
  any order, since Arrow output needs no in-order hand-off.
- **Categoricals.** A dictionary array of the profile's levels. A plain
  dictionary array imports as `Categorical`; polars makes it an `Enum`
  only when the field carries its own metadata key (`_PL_ENUM_VALUES2`,
  not a documented interface), or by a cast after import. PR 2a
  measures both and records which it uses; if the key, the polars pin
  stays `<3` and a test fails loudly when polars stops honouring it.
- **Writing.** polars exports strings as string views, and an Enum or
  Categorical as a dictionary of string views whose indices are uint8,
  uint16 or uint32 by the number of categories; the reader dispatches on
  the exported index type and tests all three widths. A frame may come
  in several chunks,
  and arrays may be slices. The writer reads all of these without
  copying the text.
- The Arrow C structures are hand-written for the types above (the
  spike's are about 500 lines); arrow-rs is not added (ADR 0033's
  reasons).

**A spike measured this before the plan was approved**
(`docs/research/parquet-polars-spike.md`; code on the unmerged branch
`spike/polars-arrow`, commit `3ec678a`), on the widest DHS file (5,160
columns), NSFG 2002 FemResp and the synthetic `long` and `groups`, each
as written by us, pyarrow and polars. The machine was loaded (load
average 8.6 to 10.1), so ratios within about 10% are ties:

- **The handoff works.** Frames equal `pl.read_parquet`'s on every file.
  Numbers and string views reach polars without a copy (checked by
  address and by RSS); polars converts dictionary arrays, as its own
  reader does (about 38 ms and 78 MiB for 20M rows). Buffers outlive
  the producer. polars keeps the chunks it is given; one per row group
  is what its own reader returns. Importing costs 0.1 to 2.7 ms.
- **Against pyarrow's `read_table`** every case passes, by wall time
  0.02 to 0.29 of theirs, with today's thread rule.
- **Against `pl.read_parquet`** (ours ÷ polars, geometric means of
  wall, peak RSS, CPU):

  | | whole file | five columns | 1,000 rows | read + pass |
  |---|---|---|---|---|
  | today's rules | 2.05, 0.97, 1.19 | 1.45, 0.78, 0.57 | 0.82, 0.77, 0.37 | 1.62, 1.02, 1.13 |
  | tuned | 1.06, 1.08, 1.60 | 0.94, 0.88, 0.72 | 0.80, 0.79, 0.47 | 1.06, 1.11, 1.40 |

  "Tuned" is polars' sixteen threads, text built on worker threads, value
  labels read lazily and the core's look-ahead window four times wider.
  It was not shown to miss targets 1 and 2 (whole-file wall 1.06
  against the 1.05 limit, pooled over both families at a load of 9; the
  plan's means are per family on a quiet machine), and it missed target
  3: CPU was 1.4 to 1.9 times polars' where wall time was about equal. The cause is
  the core's decode per value: on one thread our decode of the DHS file
  takes 57 ms, polars' whole read 42.

So the Arrow path is its own PR, 2a, before any of the package is
built. It does, in this order, measuring after each:

0. The spike's matrix again on a quiet machine (load under 2), with
   per-family geometric means, as the baseline.
1. The new outputs above: bitmaps and sparse letters for numbers, and
   dictionary indices decoded straight into views on the worker
   threads, without the intermediate pass over `u32` codes that kept
   the spike's `groups` at about 1.9 times polars.
2. Value labels parsed when asked for; opening a wide file made cheaper
   (about 10 ms of opening, 6.4, and setup, 4.2, on the DHS file in the
   spike).
3. The thread count for Arrow output, chosen for targets 1 and 3
   together: more threads lower wall time and raise CPU, and target 3
   allows CPU up to theirs × max(1.15, speedup), so the count is the one
   that passes both, measured against polars' count, and recorded.
4. The core's decode per value on one thread (PLAIN and dictionary
   numbers, definition levels), profiled against polars'.
5. The write path: polars' export into the writer, benchmarked against
   `DataFrame.write_parquet` and pyarrow's `write_table`, and the Enum
   route above.
6. The `.dta` paths: an Arrow output for dta_parser's `.dta` reader
   (numbers, strN and strL, value labels, sparse letters) and an Arrow
   input for its writer, which `read_dta`, `save_dta` and
   `read_fixed_width` use; tested against the pandas path, measured and
   published, not gated.

2a's gate is plan 0018's targets for reads and writes, measured with
`bench/parquet/` driving the native functions through a thin Python
builder that makes the whole `Meta` eagerly (every `Column`, the value
labels, `meta.missing`, the digests), so that 2b's public functions
cannot add a cost 2a did not measure. On the 5,160-column DHS file,
5,160 `Column` dataclasses alone take about 1.7 ms, against a target-1
allowance of about 1 ms over polars' 22 ms read. If `Meta` is what
misses, the fallback is named now: `meta.columns` becomes a documented
mapping that builds each `Column` from the parsed profile on first
access (a `dict` subclass, so code that reads it as a dict still
works), and the user is asked with both sets of numbers. If a target
still misses after these steps, 2a stays open and the user is asked,
with the numbers, as plan 0018 says, and 2b does not start until it
passes or the user decides.

### pandas

The pandas Parquet API goes with the move. dta_parser stays the pandas
package for `.dta`; datakit is polars. A pandas user converts with
`df.to_pandas()` (pyarrow then needed), and the letters stay in `meta`;
`docs/migration.md` and the Python page's migration table say so. The
pandas reader's measurements stay in `bench/RESULTS.md` as history.

## Julia: Datakit

```julia
using Datakit

df = read_parquet(source; cols=nothing, skip=0, n_max=nothing,
                  timestamps=:error, decimal=:float, nested=:error)
info = read_parquet_info(source)
save_parquet(path_or_io, table; label=nothing, notes=nothing,
             compression=:snappy, compression_level=nothing,
             row_group_size=nothing, missing_letters=true,
             value_labels=nothing, column_labels=nothing,
             column_formats=nothing, column_value_labels=nothing)
df = read_fixed_width(path, setup; ...)   # DtaParser's arguments; a DataFrame
                                          # with read_parquet's metadata keys
```

`using Datakit` loads DataFrames, so `read_parquet` always returns a
`DataFrame`.

- **`.a` to `.z` in a DataFrame.** A DataFrame column is any
  `AbstractVector`. A column holding `.a` to `.z` in the rows read is a
  DtaParser `DtaColumn{T}`: an `AbstractVector{Union{Missing,T}}` whose
  elements read as `missing` for every missing code, so `ismissing`,
  `skipmissing`, `mean` and `dropmissing` treat `.a` to `.z` as missing.
  Other columns are `Vector{T}` or `Vector{Union{Missing,T}}`. So the
  result is a DataFrame whose letter columns are `DtaColumn`s.
- **What keeps the codes**, from DtaParser's own tests
  (`test/dataframes.jl`) and to be extended in the PR: indexing,
  `filter`, `sort`, `subset`, and `select`, `transform` or `transform!`
  that pass the column through, by name or through `identity`, with or
  without `groupby`, and through `copy` without `groupby`. What loses
  them (letters become `missing`, which saves as `.`): `vcat` of
  DataFrames, `combine` of groups, `copy` within `groupby` (DataFrames
  then assembles a plain vector from the groups' pieces), and any
  function that builds a new vector (broadcasting, arithmetic, `ByRow`).
  Metadata follows DataFrames' own rule: kept for a column passed
  through, renamed or not, when the function is `identity` or `copy`,
  and dropped for any other function under a new name. Joins (`innerjoin`, `leftjoin`, `outerjoin`) are tested in
  the PR and the docs give the result; they are not promised.
- **Setting a letter** (`replace x = .d if age < 15`). `set_stata_code!`
  needs a `DtaColumn`, so a plain column is converted first, in place in
  the frame, which keeps its metadata:
  ```julia
  df.x isa DtaColumn || (df[!, :x] = DtaColumn(df.x))
  for i in findall(coalesce.(df.age .< 15, false))
      set_stata_code!(df.x, i, 5)   # codes: 1 is ., 2 to 27 are .a to .z; 5 is .d
  end
  ```
  `df[!, :x] = ...` keeps the column's `:note` metadata (checked on
  DataFrames 1.8.2). So do `transform!(df, :x => f => :x)`, `select`,
  `combine` and `vcat` under the same name; only a new output name
  (`:x => f => :y`) starts without it, unless `f` is `identity` or
  `copy`. The codes are another matter: a function that builds a new
  vector from `x` turns its letters into `missing`, whatever its name.
  The docs show this beside the recipe. Datakit re-exports `DtaColumn`, `stata_code`,
  `set_stata_code!` and `stata_key`.
- **Labels in metadata**, style `:note`: `colmetadata(df, :x, "label")`,
  `"format"`, `"value_labels"` (the set's name) and `"storage"`;
  `metadata(df, "label")`, `"notes"`, `"characteristics"`,
  `"sorted_by"`, `"timestamp"` and `"value_labels"` (a `Dict` from set
  name to a `Dict` from code, a number or `stata_key(".a")`, to text).
  These are `DtaTable`'s keys, so `DataFrame(read_dta(f))` and
  `read_parquet(g)` look alike.
- **Types** are DtaParser's Parquet types, unchanged (plan 0018's
  table), as plain vectors. One difference from Python: a date or
  timestamp column holding `.a` to `.z` reads as a `DtaColumn` of its
  Stata numbers, days since 1960 with a `%td` format or milliseconds
  since 1960 with `%tc`, as DtaParser reads it now
  (`logical_date`, `logical_timestamp` in `src/parquet.jl`), since a
  `Vector{Date}` cannot carry the codes; Python returns Date with the
  letters beside it. `docs/parquet.md`'s type table says so.
- `read_parquet_info` returns what DtaParser's `read_meta` returned for
  Parquet, plus `key_value`, with `columns` as a `DataFrame`.
- `save_parquet` takes any Tables.jl table, reading labels from DataAPI
  metadata (a DataFrame's or a `DtaTable`'s); the keyword arguments
  override the metadata, as DtaParser's `write_parquet` did.
- **Loading.** DtaParser's DataFrames extension drops its Parquet
  workload. Datakit has its own precompile workload (read and save a
  small file into a DataFrame), and the PR records the time to first
  read in a new session against DtaParser 0.2's.

## TypeScript: Parquet stays in `@jbearak/dta-parser`

No npm datakit, for two reasons.

1. **table-viewer needs one synchronous `TableReader` over `.dta` and
   Parquet**, with `readRowsAt`, the page cache and footer statistics
   (`docs/research/parquet-typescript.md`, "What table-viewer needs").
   That interface, the column classes (`NumberColumn`, `StringColumn`,
   `DictionaryColumn`, `BigIntColumn`) and the wasm module are the
   format library's. A separate package would either reach into
   `@jbearak/dta-parser`'s wasm exports, which are not its API, or ship
   a second copy of the core (2.2 MB uncompressed today).
2. **datakit exists for translated do-files.** In R, Python and Julia it
   is where a translated script's data preparation lives. No translator
   targets TypeScript; the npm package's users are viewers and tools
   reading files, for whom Parquet is one more file format.

The cost: a package named for `.dta` also reads Parquet. Its README's
opening and `package.json`'s description mention only `.dta` today; PR
4 changes both to name Parquet. Nothing else in the npm package
changes.

## Documentation

- `docs/python.md` keeps `.dta` with dta_parser and pandas; its
  "Parquet files" and "Fixed-width files" sections become datakit's,
  polars throughout, with the eleven Gate 2 tasks as headings as now,
  plus "`.dta` files into polars" and "Labels and `.a` to `.z` through
  polars operations" (the recipes and traps above). The migration table
  covers polars (`pl.read_parquet`, `scan_parquet`, `write_parquet`),
  pyarrow and pandas, and opens with when to use polars directly.
- `docs/julia.md` the same for Datakit, DataFrames throughout, with
  what keeps and loses codes.
- `docs/parquet.md` names datakit (R, Python, Julia) and the npm
  package; the type table gains the polars column; the error catalogue
  replaces the pandas rows with polars ones.
- `docs/migration.md` gains "dta_parser 0.2 to 0.3" and "DtaParser 0.2
  to 0.3": each moved function, its new home and how its result
  changed.
- READMEs: `python/datakit/README.md` and `julia/Datakit/README.md`
  (the Julia one's first example shows a function over a letter column
  turning its letters into `.`, since nothing warns when it happens)
  (install from a checkout, the name clash on PyPI); the format
  packages' READMEs say where Parquet went. CONTEXT.md's datakit entry
  covers the three languages, and it gains **Meta** and **companion
  column**.
- Docstrings for every exported name, linking to the guide sections.
  The docs tests (`test_docs.py`, `docs.jl`) run every example.

## Tests

- Each moved test moves with its function, rewritten for polars or
  DataFrames; nothing is dropped without a reason in the PR.
- **Round trip, Python.** For every fixture: a file `save_parquet`
  wrote from `(df, meta)` reads back as an equal frame
  (`polars.testing.assert_frame_equal`, dtypes checked) and an equal
  `Meta`, with `letters="meta"`, `"columns"`, a list and None. The types that cannot round trip
  (Decimal; `"unit": "s"`, which comes back as "ms"; a Categorical,
  which comes back as an Enum of the levels read) each have a test of
  what happens. `dta_parser.read_dta(f)` and `dk.read_dta(f)` agree per
  cell, value or missing code, on every fixture.
- **Round trip, Julia.** `isequal` on values, codes (`stata_code` per
  row) and metadata for every fixture.
- **Across languages** (`compat/parquet/`): Python writes a file with
  letters in both modes; R's datakit reads it and the letters, labels,
  formats and `factors` levels are checked per cell; then R writes and
  Python reads. Fixtures from R for the exactness edges: a `Date` with a
  fraction, a `POSIXct` that is not whole microseconds, a long column
  with letters. The Python PR does R and Python; the Julia PR adds
  Julia to the same script. Run locally; the PR comment has the output.
- **Through polars operations**: each recipe above; same-length
  reorderings that the digest catches (a sort, a reverse) and the one
  it cannot (a sort of an all-missing column), documented as such;
  each `save_parquet` check (wrong length, a changed column, a letter on
  a non-null row, a column paired twice, a companion that is not
  `LETTERS`, a companion dropped while its column is kept, an Enum with
  letters); the same generated expression on windows with and without
  letters under `letters="columns"`; the `sort` check against the sort
  recipe and against polars' default.
- **`factors=True`**: levels as R's, a set with two codes sharing a
  text, and what `save_parquet` and `save_dta` write from it; a
  labelled column with letters read with `factors=True` in both letter
  modes and saved with `save_dta`, letters checked.
- **Partial companions**: `letters=["x"]` on a file with letters in `x`
  and `y`, `y`'s kept in `meta.missing`; `meta.letters("x")` raising
  for a paired column; a file column already named `x_letter`; a stale
  pair; the digest's exactness boundary (Int64 2^53 + 1 to Float64).
- **Meta**: equality with Series, `copy`, `rename` (Series aliased,
  collisions), `select` (sort cut), `labels` (live, `{}`, `KeyError`),
  `sort` dropped when false; `read_parquet_info(f).meta` equals a default whole-file read's
  `meta` but for `missing`.
- **Windows**: `skip`/`n_max` windows with and without letters (so
  `meta.letters` of a column without them is all null); a column with
  letters read with and without `columns=`.
- **Errors and warnings stated above**: the stray-companion warning;
  `save_parquet` of a Datetime("ns") letter column (the error, and
  `timestamps="truncate"`); `read_dta`'s `%tc` fraction error and its
  out-of-range error.
- **Timestamps held as doubles**: an R-written fractional second that
  round trips through whole microseconds (read exactly) and one that
  does not (an error, and truncated with `timestamps="truncate"`); at
  each range edge (DOUBLE timestamps and dates beyond Datetime and Date,
  `%td` beyond Date, a Datetime("us") letter column beyond what a double
  of seconds holds), an error in both modes.
- **Other tools**: `compat/parquet/readback.py` reads Python datakit's
  files with pyarrow, polars and DuckDB, as for the other writers.
- **Julia `read_fixed_width`**: DtaParser's fixed-width tests, moved,
  on the DataFrame it returns, metadata keys checked.
- **Julia operations**: `filter`, `sort`, `subset`, `groupby`, `vcat`,
  `combine`, `innerjoin`, `leftjoin` on a DataFrame with a `DtaColumn`,
  codes and metadata checked, the results in the docs.
- **Install**: a clean venv installs both Python packages from the
  checkout and imports datakit without pandas loaded; a mismatched ABI
  stops with the message; the sdist builds offline. Julia: a fresh
  depot develops both packages and loads Datakit.

## Speed and memory

Plan 0018's method and targets 1 to 4 (`bench/parquet/`).

- **Python reads (gated)** against `pl.read_parquet` (whole file and
  `columns=`), `pl.scan_parquet(...).slice(skip, n).collect()` (the
  row window) and `pyarrow.parquet.read_table` (whole, `columns=`, and
  for the window the row groups that hold it, then sliced); also the
  read and a pass over every value. Ours includes building `meta`, in
  the default `letters="meta"`; `letters="columns"` is measured and
  published.
- **Python writes (gated)** from a frame already in memory, read by
  `pl.read_parquet` before timing starts: `DataFrame.write_parquet`, and
  `pyarrow.parquet.write_table` of `df.to_arrow()` (made before timing,
  zero-copy), each with its defaults and all with zstd level 3. Peak
  RSS is of the whole process, so every writer pays the same input.
- **Published, not gated:** DuckDB fetched to Arrow; `.to_pandas()`;
  `read_dta` and `save_dta` against dta_parser's.
- **Julia (gated):** as plan 0018 (Parquet2.jl, DuckDB.jl), into a
  `DataFrame` on both sides.
- **No regressions elsewhere.** 2a changes the core's shared decoding
  and writing code, so it reruns plan 0018's R, Julia and npm
  benchmarks and test suites; a case slower than before by more than
  the five runs' spread, or a failing test, blocks 2a like a missed
  target.
- **Threads.** polars uses a thread per core. Ours follow plan 0007's
  rule as measured for Parquet (`docs/parquet.md`). If a target misses
  and our reader at polars' thread count meets it, the PR reports both
  and the user is asked whether to change the Python default (target 3,
  CPU in proportion, still applies at that count). The rule is not
  changed silently.
- A missed target blocks the PR, as in plan 0018: the PR stays open and
  the user is asked, with the numbers.

## Gate 2 after the move

Once both datakit PRs are merged, plan 0018's Gate 2 runs as
`docs/judging/parquet-rubric.md` fixes it: our bundles are now datakit's
docs (Python, Julia, R) and the npm package's, against the same pinned
libraries. The rubric names the API reference for "Python and Julia:
the docstrings"; those are datakit's now, which the round's README
records. The packages are unpublished, so if an install section scores
below another library's, the rubric's rule applies and the user is
asked. Rounds until the pass rule holds, in
`docs/judging/parquet-round-N/`. Then `docs/acknowledgements.md` (plan
0018, "Acknowledgements"), linked from each package's README.

## Delivery

Each PR goes through sol-loop and is merged with full-send. CI runs
locally while GitHub's runners are unavailable, Linux checks in Docker,
with the results in a PR comment.

1. **This plan and ADR 0034**, with the Gate 1 record in
   `docs/judging/datakit-design/` and the spike's note.
2a. **The Arrow path** (above): the core's Arrow outputs and inputs,
   the native functions and ABI number in dta_parser, the core writer's
   unsigned and TIME types, the benchmarks against the Python gate, and
   the no-regression runs for R, Julia and npm. Stop and ask on a miss.
2b. **Python datakit**, once 2a is merged: dta_parser's lazy pandas
   import, the package, the move (dta_parser 0.3.0), docs, tests, the
   R–Python part of the cross-language test, and the gated benchmarks
   again through the public functions.
3. **Julia Datakit.** `DtaParser.Internals`, the package, the move
   (DtaParser 0.3.0), docs, tests, the Julia part of the cross-language
   test, benchmarks.
4. **Gate 2**, the npm README and description, and
   `docs/acknowledgements.md`.

PR 3 can run in parallel with 2a and 2b, but rebases on 2a once 2a
merges (its ABI number and the shared decoding changes), and runs its
benchmarks and the Julia no-regression check after that rebase. After 4, a new thread adds Parquet
reading and writing to table-viewer, with its own plan, reviewed by
Terra and Sonnet, implemented with full-send. How table-viewer gets the
npm 1.x package it needs (not on npm) is part of that plan; publishing
is the user's decision.

## Not in this plan

- `:=` or other Stata-style helpers in Python or Julia (goal 4).
- Arrow extension types for labels in polars (see "Why a separate label
  object").
- Writing DECIMAL.
- Keeping letters through DataFrames' `vcat` and `combine` in Julia.
- A release of anything (goal 6).

## Risks

- **Beating polars at its own reader.** The spike matched polars' wall
  time only at its thread count, and used 1.4 to 1.9 times its CPU; the
  remaining work is in the core's decoder (above). This is the largest
  risk in the plan, and it may end with the user deciding.
- **Positional letters.** The digest catches row operations on the
  column, not reorderings that leave its values in place. The default
  stays `letters="meta"` because a frame with extra columns surprises
  a user who did not ask for them; translators use `"columns"`.
- **The PyCapsule interface** is how polars 2 imports and exports
  Arrow. A polars release that changes what it accepts breaks the read,
  which the tests catch; the requirement is pinned to polars 2.x.
