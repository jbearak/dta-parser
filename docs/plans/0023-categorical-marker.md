# Plan: a `.dta` marker for categoricals, which may hold `.a` to `.z`

Status: approved at Gate 1 (revision 5; Claude Sonnet and GPT Terra;
record in `docs/judging/categorical-marker/`).

## Problem

Plan 0020 marks an R factor written to `.dta` with a characteristic,
`dtaparser_factor` = `ordered <set>` or `unordered <set>`, so that
`read_dta()` gives the factor back. A factor cannot hold `.a` to `.z`,
so plan 0020's readers take a letter in a marked column as proof that
the file was edited, and read it as labelled numbers with a "stale"
warning.

Python and TypeScript have categoricals, not factors, and since plan
0022 a categorical may hold `.a` to `.z` (a polars `Enum` with its
letters in `meta.missing`; a TypeScript `DictionaryColumn` whose
`missing` holds 2 to 27). Their `.dta` writers do not say what they
wrote:

- Python's datakit `save_dta` writes an `Enum` as codes 1 to k with a
  value label set and no marker, and its `read_dta` ignores markers, so
  an `Enum` comes back from `.dta` as labelled integers.
- TypeScript's `saveDta` writes `dtaparser_factor` on a categorical
  without letters and nothing on one with letters (plan 0022), so the
  latter comes back as labelled numbers.

The user asked on 2026-11-08 that Python's and TypeScript's `save_dta`
mark what they write as a categorical, not as a factor: Parquet records
a categorical with letters (`"logical": "categorical"`), and `.dta`
should too.

## Proposal

### The marker

A new characteristic on the variable, `dtaparser_categorical`, with the
value plan 0020's marker has: `ordered <set>` or `unordered <set>`, the
set being the value label set written for the variable. It says: this
variable was a categorical, its levels are the set's texts for its
numeric codes in code order (unused ones included), and `.a` to `.z`
in it are the categorical's own missing values, as are any labels the
set gives them.

`dtaparser_factor` keeps its meaning (an R factor, which holds no
letters) and its checks, unchanged.

### Who writes it

| writer | writes |
|---|---|
| Python datakit `save_dta` | `dtaparser_categorical` on each `Enum` and `Categorical` column, letters or not |
| TypeScript datakit `saveDta` | `dtaparser_categorical` on each categorical, letters or not; it no longer writes `dtaparser_factor` |
| R dtaparser `save_dta` | `dtaparser_factor` on each factor, as now |
| Python dta_parser `write_dta` (pandas) | `dtaparser_factor` on each `category`, as now (a pandas `category` cannot hold letters) |
| Julia | nothing, as now (plan 0020) |

**Every writer drops both markers from its input** before writing its
own, for every column (a column that was an `Enum` and is now integers
must not keep one): R's `save_dta.R` (which filters only
`dtaparser_factor` today), pandas' `_write.py`, TypeScript's
`save-dta.ts` (`data.characteristics` filter), and the loop in
`python/src/arrow/dta.rs` that copies `meta.characteristics`, which
filters nothing today.

**Python's categorical set.** `category_sets` names the set as now
(after the column, replacing `meta`'s set of that name, or `name_2`,
... when another column's labels use that name), and the marker names
the set written. The set is the levels at codes 1 to k, as now, plus
the labels on `.a` to `.z` of the set `meta.columns[x].value_labels`
names, read before `meta`'s set of the column's name is replaced, so
"Refused" on `.r` survives when the set read was named otherwise. So
through Python a categorical keeps its texts, order, unused levels,
letters and letter labels, but its codes become 1 to k (a file's codes
10, 20, 30 are renumbered; TypeScript's `saveDta` keeps a restored
categorical's own codes, plan 0021), and a polars `Categorical` comes
back as an `Enum`. With `missing_letters=False` the letters are written
as `.`, the set carries no letter labels, and the marker is written.

**TypeScript's `saveDta`** writes `dtaparser_categorical` where it now
writes `dtaparser_factor` (and on a categorical with letters, which now
gets none), with the set its plan 0021 and plan 0022 rules give. A
restored categorical's `categorical.codes` must increase with the
levels (readers order the levels by code, so codes `[20, 10]` for
`["low", "high"]` would come back as `["high", "low"]`): a code given
twice, or out of order, is an error naming the variable (today the
second level of a repeated code silently takes the first's code). A
categorical restored from a file always has increasing codes.

**The order word** is `ordered` when the categorical is ordered, else
`unordered`. Python: `meta.columns[x].ordered` is true (`write.rs`
already reads it for Parquet; `dta.rs` now reads it too); a
`Categorical`, or `None`, is `unordered`. TypeScript, as now:
`v.categorical?.ordered ?? v.ordered ?? false`.

### The read checks

A `dtaparser_categorical` variable is restored when all hold:

- the marker is `ordered <set>` or `unordered <set>`, and the variable's
  value label set is `<set>`, which the file has;
- it is stored as a number (byte, int, long, float or double): a
  marked string was edited, even when no row of it is read;
- the reader does not read it as a date or time: its display format is
  not one the reader converts (`%td`, `%d`, `%tc` and the others
  `date_kind` takes in Python); in Python's datakit, whose native reader
  converts first, the frame's column is still numeric. With date
  conversion off (R `dates = FALSE`, pandas `dates=False`) a date
  format does not fail this check, nor in TypeScript's `readDta`, which
  never converts dates (it keeps the numbers and their format). A writer never
  gives a categorical a format, so a marked date was edited;
- the set's numeric codes are whole numbers within long's range, no two
  sharing a text;
- the set labels no `.` (plain missing), told from `.a` to `.z` by its
  missing code (R and pandas use the tag test they already have, as
  `dtaparser::na_tag` and pandas' `MissingValue` do);
- every non-missing value read has a label.

Unlike `dtaparser_factor`, `.a` to `.z` in the values, and labels on
any of them in the set (used or not, whatever their text, which may
repeat a level's), are allowed.

A variable that fails a check is read **as if it had no marker**
(labelled numbers, or a date with a date format, and with
`factors=TRUE` a factor or `Enum` as any labelled column would be),
with one warning per read call naming the columns, in its own words:
"written as categoricals, but the file has changed since: their value
label set changed, a value has no label, two codes share a text, a
code is not a whole number, `.` is labelled, or a date format was
given". R gives it the condition class `dtaparser_stale_categorical`;
TypeScript lists it in its `DATAKIT_FACTOR` warning beside stale
factors (whose per-column reasons already name the check); Python
gives a `UserWarning`. Stale factors keep their own warning.

**Both markers on one variable** (an edited file, or two tools in
turn): each reader collects both characteristic names per variable
before checking (R's `factor_marks`, pandas' `marks`, TypeScript's and
Python's lookups); neither marker is trusted; the variable is read as if unmarked, and is
named in the categorical warning ("it has both markers").

### What each reader gives

| reader | `dtaparser_categorical`, no letters in the rows read | with letters in the rows read |
|---|---|---|
| Python datakit `read_dta` | `Enum` of the levels; `meta.columns[x].ordered` from the marker and `value_labels` naming the set, which `meta.value_labels` keeps | the same; the letters where `letters` puts them (`meta.missing`, `x_letter` companions, or dropped with `letters=None`, as for every column) |
| TypeScript datakit `readDta`, `readDataset` | categorical: `DictionaryColumn` with `categorical` `{ levels, ordered, labelSet, codes }`, as a restored factor is (plan 0021) | the same, `missing` 2 to 27 for the letters |
| R dtaparser `read_dta` | factor (ordered from the marker), as for `dtaparser_factor` | labelled numbers with the letters and their labels, no warning, whatever `factors` says |
| Python dta_parser `read_dta` (pandas) | `category`, as for `dtaparser_factor` | the numbers with the letters (`DtaArray`) and the set in `df.attrs`, no warning |
| Julia DtaParser | the marker as a characteristic, as now | the same |

Details:

- **Python datakit.** The restore runs in `_frame.finish`, before
  `to_factors` and before the letters are placed, on the frame read
  (so on the rows of `skip` and `n_max`), whatever `factors` says. A
  restored column's marker leaves `meta.characteristics`; a column
  that failed is left to `to_factors` as an unmarked one. `_digests`
  are taken after, as now. The native reader converts `%t` columns to
  dates first; a marked one fails the format check above.
  `dtaparser_factor` stays unrestored in Python's datakit, as now
  (restoring it would change what existing R files read as).
- **TypeScript.** `check` gains the categorical rules: letters and
  letter labels allowed, a label on `.` not. A restored categorical's
  levels and codes come from the set's numeric codes only; `missing`
  copies each row's code (1 to 27, not 1 for all); when the set labels
  a letter, `valueLabels` keeps naming it and it stays in the dataset's
  `valueLabels` (else both are dropped, as for a factor); the marker
  leaves `characteristics`.
- **R.** `read_dta` takes both markers; a valid categorical with
  letters is labelled numbers, which the `factors = TRUE` pass leaves
  alone (as plan 0022 does for Parquet), so no letter is lost: the
  restore records the columns it left as labelled numbers because of
  their letters, and the pass skips exactly those. A stale
  one is unmarked, `factors = TRUE` included.
- **pandas.** The marker check comes before date conversion, as for
  `dtaparser_factor` now; a column with letters is a `DtaArray` and
  keeps its set's name and labels in `df.attrs["dta"]` as unmarked
  columns do.

R and pandas give a factor or numbers by the rows read, as plan 0020's
check already does: a column can be a factor in one window and numbers
in another. That is accepted; Python's and TypeScript's types do not
depend on the rows.

## Documentation

- `docs/plans/0020-factor-characteristic.md`: a line pointing to this
  plan.
- `docs/python.md`, `docs/typescript.md`, `docs/r.md`: the marker each
  writer writes, what each reader makes of both markers, Python's
  renumbering.
- Roxygen, docstrings and TSDoc of the changed functions.

## Tests

- Python datakit: an `Enum` with letters, unused levels, `ordered` and
  a label on `.r` (its set named `gl`, not the column's name) goes
  through `save_dta` and `read_dta` with the same levels, order,
  letters by row and letter label, with `letters="meta"`, `"columns"`
  and `None` (letters gone); a file with codes 10, 20, 30 comes back
  with codes 1 to 3 and the same texts; a `Categorical` comes back an
  `Enum`; `missing_letters=False` writes `.` and the marker; the file
  has `dtaparser_categorical` and no `dtaparser_factor`; a marker left
  in `meta.characteristics` on a column now integers is dropped; with
  `factors=True` a valid marked column is the same `Enum` and a stale
  one goes through `to_factors`; a window without letters is an `Enum`.
- TypeScript: `saveDta` writes `dtaparser_categorical` for a
  categorical with and without letters; `readDta` restores both with
  their letters and letter labels; a file whose set has codes 10, 20,
  30 keeps them in `categorical.codes`; a `dtaparser_factor` file still
  restores, and letters in it still fail.
- Each failing check in each reader (Python datakit, TypeScript, R,
  pandas): the set renamed, an unlabelled value, two codes sharing a
  text, a code 1.5 and a code past long's range, a label on `.`, a
  `%td` and a `%d` format (with date conversion on; not in TypeScript,
  where a marked `%td` column restores, as tested), a string column,
  both markers; each read as unmarked with the categorical warning. A label on a letter no row
  holds passes.
- Python: an ordered `Enum` comes back ordered, an unordered one
  unordered. TypeScript: `categorical.codes` with a code twice, or
  `[20, 10]`, is an error; a categorical with no ordering given is
  written `unordered`.
- R: a column without letters reads as a factor, one with letters as
  labelled numbers with no warning, with `factors = TRUE` too; a window
  of rows without the letters is a factor.
- pandas: the same, as `category` and `DtaArray`, windows included; a
  marked string column (pandas skips string columns' markers today)
  warns and reads as text, also when the window holds only empty rows.
- Across languages (`compat/parquet/save_dta_compare.sh` and a new
  `compat/parquet/categorical_marker.sh`): Python's and TypeScript's
  files for the same columns (`region`; plan 0022's `grade` with
  letters and a label on `.a`) have the same marker kind and order
  word (set names may differ by plan 0021's rule); Python reads
  TypeScript's file and TypeScript reads Python's with the same levels,
  order, letters by row and letter labels; R reads both as the table
  says.

## Not in this plan

- R or Julia writing `dtaparser_categorical` (they have no categorical
  that holds letters).
- Changing `dtaparser_factor`'s checks, or restoring it in Python's
  datakit.

## Delivery

One PR: this plan and its judging record, the writers, the readers, the
docs and the tests. Nothing is published.
