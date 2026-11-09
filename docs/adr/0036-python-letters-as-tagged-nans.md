# Python's datakit keeps .a to .z in the frame, as tagged NaNs

Superseded for Python by ADR 0040: Python's datakit returns pandas, with
`.a` to `.z` in `DtaArray` columns, which compare as missing. Its
paragraph on TypeScript is superseded by ADR 0037: TypeScript's
`NumberColumn` now holds tagged NaNs too.

Supersedes the paragraph of ADR 0034 on where Python's datakit keeps
`.a` to `.z`, and the option it rejected, "letters as tagged NaNs in
Float64 columns".

ADR 0034 kept the letters outside the polars frame: in `meta.missing`,
a Series per column aligned with the rows as read, or in a companion
column `x_letter`. Neither is part of the column. `meta.missing` goes
stale after any row operation, and a companion column must be carried,
renamed, joined and kept null where a value is set, by hand, in every
expression. The user rejected both: the letters should be in the column
itself, as R's tagged NAs and Julia's `DtaColumn` hold them.

polars 2.1 offers three places for them, which we tried:

- **A code under a null.** Arrow keeps a value under each null slot,
  but polars' sort, gather and join write zeros there, so the code is
  lost.
- **An extension type.** polars still marks extension types unstable,
  and `==`, arithmetic, casts and `fill_null` raise errors on them;
  `mean()` returns None.
- **A tagged NaN in Float64.** The letter survives filter, sort, join,
  concat, arithmetic, and Parquet. polars counts NaN as a value, so
  `is_null()`, `count()` and `mean()` need `fill_nan(None)` first.

**Python's datakit holds `.a` to `.z` as tagged NaNs in `Float64`
columns.** A letter is R's `NA_real_` with the letter's ASCII code in
bits 32 to 39, the layout haven, R's dtaparser and the Parquet files'
DOUBLE columns already use, so a column goes to R and back bit for bit.
A reader of the tag ignores the sign and the quiet bit, which
arithmetic may change. `.` stays a null.

- Every read gives a column holding letters in the rows read as
  `Float64`. An `Int8`, `Int16`, `Int32` or `Float32` column is cast,
  and `meta` keeps its type privately, so `save_dta` and `save_parquet`
  write it in that storage type again when its values still fit it.
  `letters=False` reads the letters as nulls and keeps the type.
- A `Date`, `Datetime` or `Enum` cannot hold NaN. Holding letters, a
  date reads as Stata's days since 1960 (`%td`), a timestamp as its
  milliseconds since 1960 (`%tc`), and a categorical as its level
  numbers, labelled: what Julia's Datakit gives for the first two, and
  R's and Julia's for the third.
- `factors=True` makes a labelled column holding letters an Enum all the
  same, the letters nulls, with a warning, as R's datakit does.
- `tagged_na(letter)`, `na_tag(x)` and `is_tagged_na(x, letter=None)`,
  named as in haven and dtaparser, make and read the letters.
- `meta.missing`, `meta.letter_columns`, `Meta.letters`,
  `letters_to_columns`, `letter_suffix` and the read digests are gone;
  `letters` is `True` or `False`.

TypeScript is unchanged: its `Dataset` columns already hold each row's
code beside its value.

## Considered options

- **Keep companion columns and `meta.missing`** (ADR 0034). The user
  rejected them.
- **An extension type.** Every comparison and computation would need
  the storage unwrapped first, and the API may change in any polars
  release.
- **Keep `meta.missing` for dates, timestamps and categoricals only.**
  Two mechanisms, one of them positional; reading those columns as
  numbers is what R and Julia already do where their types cannot hold
  a letter.
- **`factors=True` leaves columns holding letters as numbers.** Keeps
  the letters, but Python would then give other columns than R for the
  same file and the same argument.

## Consequences

- polars counts the letters as values: `is_null()`, `null_count()`,
  `count()`, `mean()` and `drop_nulls()` need `fill_nan(None)` first.
  The guide says so where it introduces the letters, and in its
  troubleshooting section.
- A column's dtype depends on the rows read: a window without letters
  reads a byte column as `Int8`, one with them as `Float64`.
- Python can no longer write an Enum holding letters, or a Date or
  Datetime holding letters as such. The native writer still can (it
  writes TypeScript's), so its error messages for those cases, which
  name the old API, are unreachable from Python. The native functions,
  their ABI number and the unused digest function are unchanged.
- The cross-language checks expect Python's date, timestamp and
  categorical holding letters as Stata's numbers, as Julia writes them.
- Nothing was published with the old API; datakit stays 0.3.0.
