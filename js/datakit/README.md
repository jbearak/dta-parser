# @jbearak/datakit

Data preparation in TypeScript and JavaScript that keeps Stata's labels
and missing values `.a` to `.z`:

- **Parquet files** that keep value labels, variable labels, display
  formats, `.a` to `.z`, notes, categoricals and time zones, read and
  written by R's datakit too, and plain Parquet
  to every other tool. `ParquetReader` reads columns and windows of rows
  synchronously through the same `TableReader` interface as
  `@jbearak/dta-parser`'s `DtaReader`; `openParquetAsync` reads over
  HTTP.
- **Fixed-width text through a SAS setup file**, such as CDC's National
  Survey of Family Growth files, with the setup's labels and its
  missing-value recodes (kept as `.a`, `.b`, ... on request).
- **Whole tables in memory**: `readParquet`, `readDta` and
  `readFixedWidth` give a `Dataset` of typed-array columns, labels and
  letters included, which you change and save with `saveParquet` or
  `saveDta`.

```ts
import { MISSING } from "@jbearak/datakit";
import { readDta, readFixedWidth, readParquet, saveDta, saveParquet } from "@jbearak/datakit/node";

const ds = readDta("survey.dta");              // or readParquet(path), readFixedWidth(dat, sas)
ds.variables.map((v) => v.name);
ds.valueLabels.nonresponse.get(MISSING[".d"]); // "Don't know"
saveParquet(ds, "survey.parquet");             // labels and .a to .z kept
saveDta(readParquet("survey.parquet"), "copy.dta");
```

`@jbearak/dta-parser` (2.0 or later) is a peer dependency: datakit takes
its missing values and column types from it, and reads and writes `.dta`
through it. The Parquet and fixed-width code is datakit's own
WebAssembly module, built from the same Rust core, embedded in the
package; the main entry uses no Node API, so it runs in browsers, and
`@jbearak/datakit/node` adds the functions that take paths.

Neither package is on npm yet: build both from a checkout of
[the repository](https://github.com/jbearak/dta-parser), as
[docs/typescript.md](https://github.com/jbearak/dta-parser/blob/main/docs/typescript.md#datakit-install)
says. That page documents every function.

The open-source projects studied for the Parquet code, and the codec
crates it uses, are listed with their licenses in
[docs/acknowledgements.md](https://github.com/jbearak/dta-parser/blob/main/docs/acknowledgements.md);
the crates' licence texts are in `THIRD-PARTY-NOTICES`.
