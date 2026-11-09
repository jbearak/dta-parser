# Plan: Parquet categoricals that keep `.a` to `.z`

Status: approved at Gate 1 (revision 5; Claude Sonnet and GPT Terra;
record in `docs/judging/categorical-letters/`).

## Problem

A categorical can hold `.a` to `.z` in a `.dta` file: there it is labelled
codes, and any Stata variable may hold the extended missing values, with
labels on them. Python's datakit reads one (`factors=True`: an `Enum`, the
letters in `meta.missing`) and `save_dta` writes it back. TypeScript's
`saveDta` refuses one, and so does every Parquet writer: Python's
`save_parquet` ("an Enum or Categorical and has .a to .z ... save it as
.dta"), TypeScript's `writeParquet`/`saveParquet` (plan 0021). The reason
is the file: a categorical is written as dictionary-encoded text, which
has a null and nothing else, while `.a` to `.z` live in DOUBLE columns as
tagged NaNs (docs/parquet.md, "Missing values").

The user asked on 2026-11-08 that our Parquet categoricals keep `.a` to
`.z`, and that a language whose categorical type cannot hold them (R's
factor) read such a column as labelled doubles.

## Proposal

### The file

The format already widens a column when it holds `.a` to `.z`: a byte,
int, long or float column becomes DOUBLE with `"storage"` in the profile,
a date or timestamp becomes DOUBLE with `"logical": "date"` or
`"timestamp"`. A categorical follows the same rule:

- **A categorical holding any of `.a` to `.z`** is written as **DOUBLE**:
  each value is its level's number counted from 1 (the first level is 1),
  `.` is a null, and `.a` to `.z` are tagged NaNs. Its profile entry has
  `"logical": "categorical"` beside the `"categorical"` entry it has now
  (`levels`, every level in order, and `ordered`), and `"value_labels"`
  naming a set that labels 1 to k with the levels (below). `ARROW:schema`
  gives it as Float64.
- **A categorical without letters** is written as now: dictionary-encoded
  BYTE_ARRAY STRING, every level in order in every row group, no set.
  Nothing changes for it, so pandas, polars, pyarrow and arrow keep
  reading it as a category or factor.
- `missing_letters = false` / `missingLetters: false` writes the letters
  as nulls, as for every other column, so the column stays text.

Which form a column takes is decided by its values, as for every widened
column; a reader decides by the file's schema and profile at open (DOUBLE
with a valid `logical` categorical, below), never by the rows read, so
every window and every read of one column has one type, and the type a
reader reports before any read (`variables`, the info call) is the one
its reads give.

**The set.** A set *fits* a categorical of k levels when its entries
other than `.a` to `.z` are exactly 1 to k, labelled with the levels in
order; entries for `.a` to `.z` may be there too, and are kept (so a
label on `.r`, "Refused", travels with the column). The writer picks the
set to record, in this order:

1. the set the caller names for the column (Python's
   `meta.columns[x].value_labels`, TypeScript's variable `valueLabels`),
   if the sets being written have it and it fits;
2. else the first of the column's name, `name_2`, `name_3`, ... that is
   either a set being written that fits (recorded as it is) or no set at
   all and not the name of another column in the file (a set is added,
   from the levels).

No two columns can make the same name this way, also when each makes
its own without seeing the other's (a reader of some columns): a made
name is the column's own name or `column_k`, and since `k` is digits,
`a_j` equals `b_k` only when `a` is `b`; and a column's own name is
never made by another column, which skips names of columns. So
categorical `x` with `x_2` taken skips `x_2` if a column is named
`x_2`, and that column makes `x_2` for itself. Two columns that reuse
one fitting set have the same levels, so the set is right for both.

The writer has every set it writes, so the check is complete, and no set
another column uses is changed. A reader uses the recorded set. Writing
back what was read names the same set (step 1), so the name is the same
after any number of write and read rounds.

**Reading such a column.** A value must be a whole number from 1 to the
number of levels, a null, or a tagged NaN `.a` to `.z`. Anything else
(another tool rewrote the column, or wrote it by hand) is read as `.`,
and the reader warns once per column, naming it and the first such row
of the rows read: in R, Python and Julia one warning per read call; in
TypeScript one per reader and column (`process.emitWarning`, code
`DATAKIT_CATEGORICAL`, else `console.warn`), however many windows are
read. The type stays a categorical. No whole-column scan is needed, and
a window without a bad value warns about nothing.

**A damaged or contradictory profile entry** is decided at open, each
case with one warning naming the column and the entry, and the rest of
the profile used (the forgiving rule):

| entry | read as |
|---|---|
| `logical` categorical with no valid `categorical` (missing, or its `levels` not a list of distinct texts) | the doubles, letters kept, with their `value_labels` set if any; `logical` dropped |
| `logical` categorical on a column that is not DOUBLE | as the column's own type; `logical` dropped (as `logical` date is today) |
| `categorical` on a DOUBLE column without `logical` categorical | the doubles; `categorical` ignored (as today) |
| `logical` categorical and `storage` both | the doubles with that storage; `logical` dropped |
| a valid DOUBLE categorical with no `value_labels`, or one naming a set the profile lacks or that does not fit | the categorical, with a set made from the levels and named by step 2 against every set name and column name the file has (no warning when `value_labels` is absent; one when it names a set that is missing or does not fit) |

A `categorical` entry that cannot be read (not an object, no levels, a
level twice) is dropped by the profile parser with its warning, as now;
when its column's `logical` is categorical, the parser drops that too,
without a second warning (the first says the column is read as
numbers). So an absent `categorical` gives the first row's warning and
a malformed one the parser's: one each. Dropping `logical` categorical
for `storage` or a non-DOUBLE column drops the levels with it (they
would only warn again), except on a text column, which stays a text
categorical.

The writer never writes these. A made set is not in the file, so reading
the same file always gives the same name.

**Every set name, in every read mode.** Step 2 on read needs all the
file's set names, also when only some columns are read
(`Profile::parse_some`) or the sets are read lazily
(`Profile::parse_lazy_labels`, which Python and TypeScript use). The
parser already passes over unselected columns and unread sets; it now
records the names (the keys of `value_labels`, not their contents) as it
passes, and `Reader::value_label_set_names` returns them all in every
mode. The core does the reading side once:
`Reader::categorical_labels(column) -> (name, ValueLabelSet, Option<warning>)`,
which reads the recorded set (lazily if need be), checks the fit, and
otherwise makes one by step 2. The bindings call it.

**Profile version.** It stays 1. A reader older than this plan meets an
unknown `logical` and a `categorical` on a non-text column; it drops both
with a warning each (the profile's forgiving rule) and reads numbers with
their letters and the recorded set: labelled numbers. Bumping the version
would make that reader warn about every file, most of which use nothing
new.

**What other tools see**: numbers 1 to k with NaN (pyarrow, polars,
DuckDB SQL) or the letters (arrow and nanoparquet in R, through tagged
NAs) for such a column, as for every other column holding letters.
`docs/parquet.md`'s "What other tools see" gains the row.

### The core (`crates/parquet`)

- `profile::Logical` gains `Categorical` (`"categorical"`).
  `Logical::from_name`'s message lists the three values.
- **Writing.** `FillCodes` fills level codes from 0, negative for a
  missing value; today any negative is a null. Now `-1` is `.` and `-2`
  to `-27` are `.a` to `.z` (the missing code, negated); any other
  negative is still `.`, on purpose: today every negative is a null, and
  bindings that fill other negatives keep working. `holds_letters` scans a categorical's codes; a
  categorical that holds a letter is tagged, so `schema_for` and
  `arrow_schema_for` already make it DOUBLE/Float64, and the encoder
  writes it through the number path (`code + 1`, tagged NaNs), checking
  each code against the levels as the text path does. A letter is not
  an error for a categorical any more (`holds_letters` lists the types
  that widen). The `letters` hint of `write_with_letters` keeps its
  contract for categoricals too: `Some(true)` where the binding found a
  letter; `Some(false)` writes any letter as a null; `None` makes the
  writer scan. Each binding that passes hints (TypeScript, Python)
  computes them for categoricals from the codes it hands over.
- **`profile_for`** takes `logical` and `categorical` from the values,
  never from an entry the caller supplied: a supplied entry may keep
  only `logical` date or timestamp, and only on a Double column (R's
  `Date` and `POSIXct`, as now). A supplied `logical` categorical, and a
  supplied `categorical` on a column whose values are not a categorical,
  are dropped (today a stale `categorical` stays). For a tagged
  categorical it sets `logical` categorical, `storage` none, and
  `value_labels` to the set the rule above picks, adding that set when
  step 2 makes one.
- **Reading.** `check_widened` keeps `logical` categorical on a DOUBLE
  column that has a valid `categorical` entry, and applies the table
  above otherwise. The loop that warns about `categorical` on a non-text
  column (`read.rs`, after the profile is parsed) skips such a column, so
  a clean file gives no warning and a damaged one gives exactly the one
  its table row says. `ColumnInfo` keeps `kind` Double, `profile_logical`
  Categorical and `levels` None, so `Output::Levels` and Arrow `Keys`
  (which decode text against a dictionary) are untouched: every binding
  reads the column as it reads a DOUBLE column with letters (its values
  as doubles, `.a` to `.z` as missing codes or, in the Arrow path,
  Python's `(row, code)` list) and turns the doubles into level indices
  with one core function, `dta_parquet::level_index(x: f64, levels:
  usize) -> Option<u32>`: `Some(i)` for a whole number `1 <= x <= levels`
  (index `x - 1`), `None` for anything else (the caller has already taken
  out nulls and letters), so the rule is one. The levels come from the
  profile entry, as each binding already takes them for text
  categoricals; the set from `Reader::categorical_labels`.
- `r/dtaparser/src/rust/parquet` (the committed copy R builds from) is
  refreshed, as CI checks.

### What each language gives

| | categorical without letters | categorical with letters (DOUBLE) |
|---|---|---|
| R `read_parquet` | factor, as now | a `dtaparser_labelled` double: the codes 1 to k, tagged NAs for `.a` to `.z`, labels from the recorded set (1 to k the levels, and any labels on letters), `label_set` its name. `factors = TRUE` does not make it a factor: R's factor cannot hold the letters, so this column stays a labelled double whatever `factors` says (the C read returns which columns are such, and the `factors` loop in `r/datakit/R/parquet.R` passes over them) |
| Python `read_parquet` | `Enum`, as now | `Enum` of the levels; `.` and the letters null, the letters in `meta.missing` (or a companion column `x_letter` with `letters="columns"`, which pairs this column like any other); `meta.columns[x].value_labels` names the recorded set, which `meta.value_labels` holds, as `read_dta(factors=True)` gives a categorical with letters, so `letters_to_columns`, `save_dta` and `save_parquet` accept its letters. The same with `factors` true or false |
| Julia `read_parquet` | `CategoricalArray` (with CategoricalArrays.jl), as now | a `DtaColumn{Float64}` of the codes 1 to k with the letters (as a DOUBLE column with letters reads), its `colmetadata` `value_labels` the recorded set's name, the set in the table's `value_labels` metadata |
| TypeScript `ParquetReader` | `DictionaryColumn`, as now | `DictionaryColumn`: `codes` the level index, `values` every level, `missing` 0 for a value, 1 for `.`, 2 to 27 for `.a` to `.z` (the codes `NumberColumn.missing` uses); `readRows` gives the level's text or the `Missing` (`cellOf` in `js/datakit/src/parquet.ts` gives `MISSING["."]` for every missing dictionary value today; it uses `missingValue` of the code instead); `variables[i].valueLabels` names the recorded set, which `valueLabels(name)` gives |

`variables[i]` (TypeScript), the info call (every language) and R's
`read_parquet_info` say `categorical` for both forms; the physical type
says DOUBLE for the second.

Writing:

| | what writes a categorical with letters |
|---|---|
| Python `save_parquet` | an `Enum` whose letters `meta.missing` or a companion column holds (letters on an `Enum` are accepted, as now, when `meta.columns` gives it a value label set, as `read_dta(factors=True)` and `read_parquet` above make it); the refusal goes, and the tests that expect it (`python/datakit/tests/test_letters.py`) change to expect the DOUBLE form. An `Enum` without a set, and a polars `Categorical`, cannot be given letters, with the errors they give now; so for Python, step 2 runs only when the column's set does not fit |
| TypeScript `writeParquet`, `saveParquet` | a `DictionaryColumn` whose `missing` holds 2 to 27, or codes with `levels` among which are `Missing` values `.a` to `.z`; plan 0021's refusal (`js/datakit/src/parquet.ts`) goes, and the copy of a `DictionaryColumn` into the writer's input keeps `missing` codes 2 to 27 as letters instead of folding every nonzero code into `.` |
| R `save_parquet` | none: a factor cannot hold letters. A `dtaparser_labelled` column (such as one read from the second form) is written as labelled numbers, as now |
| Julia `save_parquet` | none: a `CategoricalArray` cannot hold letters. A `DtaColumn` with value labels is written as labelled numbers, as now |

So a categorical with letters goes between Python and TypeScript as a
categorical, and reaches R and Julia as labelled numbers, which keep the
letters, the level texts and the labels on letters. R or Julia writing
it back gives labelled numbers, not a categorical: the same as R does
today with a `.dta` factor whose letters fail plan 0020's marker check.
The docs say so.

### `.dta` (TypeScript `saveDta`)

The other half of the confusion: TypeScript's `saveDta` refuses a
categorical with letters, while Python's `save_dta` keeps them. `saveDta`
now writes one as it writes every categorical (plan 0021): codes 1 to k,
or a restored factor's own `categorical.codes`; stored as long; a set
with every level, unused ones included, named by plan 0021's rule; and
`.a` to `.z` where they were. Both inputs carry letters: a
`DictionaryColumn` whose `missing` holds 2 to 27 (today
`js/datakit/src/save-dta.ts` writes every nonzero `missing` as `.`), and
codes with `Missing` levels. The marker is decided by the values
written: a categorical with any letter gets **no** `dtaparser_factor`
marker (plan 0020's read check would reject it, and Python's `save_dta`
writes none), one without letters gets it as now; every marker in the
input is dropped first, as now. `saveDta` has no option that turns
letters into nulls. It reads back as labelled numbers with the letters.

Labels on letters are kept: the set `saveDta` builds (codes to levels)
takes the entries for `.a` to `.z` of the set the variable names
(`valueLabels`, which a categorical read from Parquet has: "Refused" on
`.r`, say), and the name it starts from is `categorical.labelSet`, else
that `valueLabels`, else the column's name. An existing set by that
name is reused when it says the same as the built set (numbers and
letters), as plan 0021's rule has it, so the set read is written back
under its own name.

`DictionaryColumn.missing`'s TSDoc (`js/src/index.ts`) says it may hold
2 to 27.

## Documentation

- `docs/parquet.md`: "The file" table and "Missing values" gain the
  categorical row and rule; "The profile" lists `logical` categorical
  and the recorded set; "What other tools see" and the errors and
  warnings table (the damaged entries, a bad value) gain their rows;
  Python's refusal row goes.
- Each language's guide: the type table row for a categorical with
  letters; R's that `factors = TRUE` leaves it a labelled double; where
  R and Julia write it back as labelled numbers.
- `docs/typescript.md`: `DictionaryColumn.missing` holds 2 to 27; the
  `saveDta` rules; plan 0021's error text goes.
- `docs/migration.md`: TypeScript: `DictionaryColumn.missing` may now
  hold 2 to 27 (code that tests `missing[i] === 1` for a missing value
  should test `missing[i] !== 0`).
- TSDoc, roxygen and docstrings for the changed functions.

## Tests

- Core: a categorical with letters is DOUBLE with `logical` categorical,
  its levels and the recorded set in the profile, no `storage`; without
  letters it is text as before, with no set; `missing_letters` off, and
  a `Some(false)` hint, give text with nulls; a code past the levels is
  an error; `level_index` on 1, k, a fraction, 0, k + 1, a plain NaN;
  each damaged-entry row of the table above gives its warning (exactly
  one) and its type, an absent and a malformed `categorical` beside
  `logical` categorical one warning each; a clean file gives no warning.
- `profile_for`: a supplied entry with `logical` categorical on a plain
  Double column, and a supplied `categorical` on an Int32 column, are
  dropped from the file; a supplied `logical` date on a Double column is
  kept.
- The set: the caller's fitting set is recorded; a caller's set that
  does not fit (codes 1, 2, 5) is kept for whatever uses it and the
  column gets `name` or the next free name; a set named after the column
  that another column uses and that does not fit is left as it is and
  the column records `name_2`; one that fits is reused; labels on
  letters in the recorded set survive the round.
- Made names do not collide: a file whose categoricals `x` and `x_2`
  (different levels) record no set while a set `x` that does not fit is
  taken: `x` makes `x_3`, `x_2` makes `x_2`, read whole and each column
  alone; Python writes it back and reads the same names.
- Every set name: a file (core test writer) whose DOUBLE categorical has
  no `value_labels`, while an unselected column uses a set named after
  it: reading only the categorical, with `parse_some` and with lazy
  sets, gives `name_2` in R, Python, Julia and TypeScript's
  `variables[i].valueLabels`.
- Stable names: Python reads a file with a collision (above), writes it,
  reads it, writes it again: the set names are the same each round, and
  the file's sets are the same after the second write as after the
  first.
- Older readers: the file is read by `@jbearak/dta-parser` 1.1.0 (the
  published version, whose profile parser is the one before this plan),
  a devDependency of `js/datakit` under an alias
  (`"dta-parser-1": "npm:@jbearak/dta-parser@1.1.0"`, in the lockfile,
  installed by `npm ci`, so the test needs no network): it gives the two
  warnings and the codes with their letters and the recorded set.
- Bad values: a file whose DOUBLE categorical holds 1.5 in a later row
  group: a window before it reads a clean categorical with no warning, a
  window over it reads `.` there with one warning, a second read of it
  warns again in R, Python and Julia and not again in TypeScript, and
  the type is the same throughout.
- R: `read_parquet` with `factors = FALSE` and `factors = TRUE` gives the
  same labelled double with its letters, and no lost-letters warning.
- Each language: reads a file of both forms (written by the core's test
  writer and by Python and TypeScript) to the types above, cell by cell,
  with no warning; Python and TypeScript write and read back a
  categorical with letters unchanged (levels, ordering, unused levels,
  the letters by row, the set); R and Julia write back what they read as
  labelled numbers.
- The cross-language check (`compat/parquet/cross_language.sh`): Python's
  and TypeScript's files gain a categorical with letters (`grade`, levels
  `["low", "mid", "high"]`, rows `low`, `.a`, `high`, `.`, `.z`, `mid`);
  each language checks it in the other files as the table above says.
- Other tools: `compat/parquet/readback.py` and `readback.R` read the
  DOUBLE column as numbers with NaN (pyarrow, polars, DuckDB) or tagged NAs
  (arrow, nanoparquet); hyparquet (`readback.mjs`) as numbers.
- TypeScript `writeParquet`: a `DictionaryColumn` with `missing` 2 to 27
  and codes with `Missing` levels both write the DOUBLE form and read
  back with the letters by row, through `readColumns` (codes 2 to 27)
  and `readRows` (`MISSING[".a"]`, `MISSING[".z"]`).
- TypeScript `saveDta`: a categorical read from a Parquet file whose set
  labels `.r` "Refused" writes a set with 1 to k and `.r` under the same
  name, and reads back so.
- TypeScript `saveDta`: a categorical with letters, given as a
  `DictionaryColumn` and as codes with `Missing` levels, writes labelled
  codes with the letters and no marker, and reads back so; one without
  letters keeps its marker; a stale marker in the input is dropped
  either way; the same column (levels, `.a`, `.`) saved by TypeScript's
  `saveDta` and Python's `save_dta` gives files with the same storage,
  values, missing codes and sets.

## Not in this plan

- R and Julia types that are categoricals with letters (neither language
  has one); a marker so that R or Julia write a categorical back.

## Delivery

One PR: this plan and its judging record, the core, the four languages,
the docs and the tests. Nothing is published.
