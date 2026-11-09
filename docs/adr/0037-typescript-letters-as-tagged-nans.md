# TypeScript's NumberColumn holds .a to .z in its values, as tagged NaNs

Supersedes, for TypeScript, `NumberColumn.missing` (plan 0001's codes
beside the values) and the TypeScript paragraph of ADR 0036.

ADR 0036 moved Python's datakit from letters beside the frame to
letters in the column. The user asked that every language work that way.
R already does: haven's and dtaparser's tagged NAs are the values.
TypeScript did not: a `NumberColumn` was `values` (a Float64Array, NaN
where missing) and `missing`, a Uint8Array of codes (0 a number, 1 `.`,
2 to 27 `.a` to `.z`) that every caller had to carry beside the values.

**A `NumberColumn` is `{ kind: "number", values }`.** `.` is R's
`NA_real_` (a NaN whose low word is 1954) and `.a` to `.z` are that NaN
with the letter's ASCII code in bits 32 to 39, the bits R, Python's
datakit and the Parquet files use. Any other NaN is a number, as a NaN
with code 0 was. `missingCode(x)` gives the old code; `NA`,
`taggedNa(letter)`, `naTag(x)` and `isTaggedNa(x, letter?)` make and
read them, from the wasm-free `/format` entry, re-exported by datakit.
Reading a code ignores the sign and the quiet bit: V8 keeps a
Float64Array's bits, but a NaN stored in a plain array, or one that
arithmetic produced, is quieted, its payload kept.

- `WriteVariable.missing` and, for a Float64Array, `DatasetVariable.missing`
  are gone; `DatasetVariable.missing` stays for a BigInt64Array's nulls.
  A plain array still takes `null` and `MISSING` values, and now tagged
  numbers too.
- Rows (`readRows`) still give `MISSING` objects, and value label maps
  are still keyed by them: a Map would treat every NaN as one key.
- The wasm modules and their ABI are unchanged: the reader turns the
  module's codes into numbers, and the writers turn numbers back into
  codes, at the boundary.
- A `DictionaryColumn`'s codes cannot hold a NaN, so a categorical
  holding `.a` to `.z` in the rows read comes back from `readColumns` as
  a `NumberColumn` of its level numbers from 1, labelled by its set, as
  R, Julia and Python read it; `readDataset` gives it type `double`, and
  a `.dta` `dtaparser_categorical` column holding letters stays labelled
  numbers, its marker kept. `readRows` still gives the levels as text.
  `DictionaryColumn.missing`, `StringColumn.missing` and
  `BigIntColumn.missing` are null flags, not Stata's letters, and stay.

Julia keeps `DtaColumn`, which is already one column whose letters
follow its rows, and reads every code as `missing`, which tagged NaNs in
a `Vector{Float64}` would not.

## Considered options

- **Tagged NaNs in `values`, keeping `missing` as well.** Not breaking,
  but two sources of truth that disagree as soon as code edits one.
- **Codes for `.a` to `.z` in a `DictionaryColumn`'s `codes`**
  (sentinels near 2^32). A second encoding to learn, for one column kind.
- **Leave TypeScript as it was.** The user asked otherwise.

## Consequences

- Breaking for dta-parser 2.0 and datakit 2.0, which are not published;
  table-viewer, Sight and manuscript-markdown, which read `missing`, need
  `missingCode(values[i])` when they move to 2.0.
- `Float64Array.prototype.sort()` makes every NaN the same, and
  `JSON.stringify` writes `null`; the guide says to sort by `dtaKeys`
  and to convert before serializing.
- `assert.deepEqual` counts every NaN as equal, so the tests compare each
  column's `missingCode`s too.
