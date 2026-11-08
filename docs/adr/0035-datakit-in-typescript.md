# datakit in TypeScript, with its own WebAssembly module

Supersedes the TypeScript paragraph of ADR 0034.

ADR 0034 kept Parquet in `@jbearak/dta-parser` because table-viewer
needs one synchronous `TableReader` over both formats and because no
translator targets TypeScript. The user asked for a datakit in
TypeScript (plan 0021), so npm now matches R, Python and Julia: the
format package reads and writes `.dta`, and `@jbearak/datakit` reads and
writes Parquet, reads fixed-width text through a SAS setup file, and
reads and saves `.dta` into a `Dataset`, keeping labels and `.a` to `.z`.

**Each package has its own module.** In the other languages datakit
calls the format package's native code behind an ABI number, because a
second Rust build would mean a second compile or binary for users. An
npm module is prebuilt and embedded, so a second one costs only CI time,
and the split takes Parquet and libzstd out of the module that
`.dta`-only users load. The `.dta` writer, which `fixed_width_to_dta`
needs, is in both.

**`MISSING`'s objects are one per realm.** They key `ValueLabels` maps,
and every bundle with its own copy of the code used to make its own (the
root and `./format` entries already differed). From 2.0 they are made
once, in a `globalThis` registry under a `Symbol.for` key, so every
copy shares them. datakit's root imports only dta-parser's wasm-free
`./format` entry, and its `./node` entry loads the `.dta` module only
when a `.dta` function is called.

**One shared `TableReader`.** The interface and the column types stay in
dta-parser; datakit's `ParquetReader` implements it. A viewer opens
`.dta` with dta-parser and Parquet with datakit and treats both alike.

**`Dataset` rather than a frame library.** JavaScript has no frame most
data code uses; nodejs-polars is Node-only native code. A `Dataset` is
plain typed arrays with `.a` to `.z` in each column's `missing` codes.
`saveParquet` writes it as it is; `saveDta` converts what `.dta` holds
differently (dates, timestamps, categoricals, 64-bit and unsigned
integers) and is the only way a `Dataset` becomes `.dta`. One documented
recipe takes it into Arquero and back.

dta-parser becomes 2.0.0, since 1.1.0 published the Parquet exports.

## Considered options

- **Keep Parquet in dta-parser** (ADR 0034). The user asked for the
  split.
- **One module, datakit calling dta-parser's through an internal entry
  and an ABI number**, as in the other languages. It keeps 1.1's module
  size for `.dta`-only users and couples the two packages' releases for
  no saving users see.
- **datakit re-exports dta-parser's Parquet code.** Parquet would still
  load with every `.dta` read, and the move would be in name only.
- **nodejs-polars or Arquero frames from the read functions.** Ties the
  package to one library; nodejs-polars excludes browsers.
