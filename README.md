# dta-parser

Read and write Stata `.dta` files from R, Python, Julia and
TypeScript, with one implementation of the format underneath all four.

- **Reads every release from 104 to 119**, from either byte order, and
  **writes release 118**, which Stata 14 and later, haven, pandas and
  ReadStat read.
- **Keeps Stata's missing values `.a` to `.z`** per value, through
  filtering, sorting and merging, and writes them back. Of the other
  readers, haven keeps them too (as tagged NAs); readstata13, pandas and
  pyreadstat return one `NA`/`NaN` unless asked (`missing.type = TRUE`,
  `convert_missing=True`, `user_missing=True`), and then in a separate or
  slower form; ReadStatTables.jl and statfmt keep only one missing value. One missing
  value loses the reason an answer is missing (`.d` "don't know", `.r`
  "refused"). See [missing values](docs/guide/missing-values.md).
- **Keeps the metadata**: variable labels, value labels (including labels
  on `.a` to `.z`), display formats, storage types, the data label and
  notes, characteristics, the sort order and the timestamp.
- **Reads only what you ask for**: a few columns, a window of rows, or
  the metadata alone, from files of any size, including over 4 GiB.
- **Fast.** The format is parsed by a Rust core (`crates/dta`) that
  each language calls directly; [bench/RESULTS.md](bench/RESULTS.md)
  compares it with haven, readstata13, pandas, pyreadstat,
  ReadStatTables.jl and @irbisadm/statfmt.

*Benchmark chart: to come with the rewritten
[bench/RESULTS.md](bench/RESULTS.md).*

## Packages

| language | package | docs | returns |
|---|---|---|---|
| R | `dtatools` | [docs/r.md](docs/r.md) | a tibble whose numeric columns keep `.a` to `.z` |
| Python | `dta_parser` | [docs/python.md](docs/python.md) | a pandas DataFrame |
| Julia | `DtaParser` | [docs/julia.md](docs/julia.md) | a Tables.jl table; `DataFrame(t)` |
| TypeScript, JavaScript | `@jbearak/dta-parser` | [docs/typescript.md](docs/typescript.md) | typed arrays per column, or rows |

None of them is on a package registry yet; each page says how to
install from this repository. Building needs Rust
([rustup.rs](https://rustup.rs)).

The [guide](docs/guide/README.md) explains the parts of a `.dta` file
that matter when you use it (releases, storage types, missing values,
value labels, encodings, strLs, dates) and how each language represents
them.

## A first example in each language

Each example writes a small file with a labelled column and a "don't
know" answer, then reads it back.

**R**

```r
library(dtatools)

df <- dibble(id = 1:3, smoker = dta_num(c(1, 0, .d), labels = c(No = 0, Yes = 1, "Don't know" = .d)))
save_dta(df, "smokers.dta")

back <- read_dta("smokers.dta")
back$smoker                          # 1 0 .d
val_label(back$smoker, back$smoker)  # "Yes" "No" "Don't know"
```

**Python**

```python
import pandas as pd
import dta_parser as dp
from dta_parser import missing

df = pd.DataFrame({"id": [1, 2, 3], "smoker": pd.Series([1, 0, missing.d], dtype="stata[byte]")})
df.attrs["dta"] = {"columns": {"smoker": {"value_labels": "yesno"}},
                   "value_labels": {"yesno": {0: "No", 1: "Yes", missing.d: "Don't know"}}}
dp.write_dta(df, "smokers.dta")

back = dp.read_dta("smokers.dta")
print(back["smoker"].tolist())                          # [1.0, 0.0, .d]
print(back.attrs["dta"]["value_labels"]["yesno"])       # {0: 'No', 1: 'Yes', .d: "Don't know"}
```

**Julia**

```julia
using DtaParser, DataFrames   # DataFrames brings `metadata`

write_dta("smokers.dta", (id = [1, 2, 3], smoker = DtaColumn(Int8[1, 0, 0], UInt8[0, 0, 5]));
          value_labels = Dict("yesno" => Dict(0 => "No", 1 => "Yes", ".d" => "Don't know")),
          column_value_labels = Dict(:smoker => "yesno"))

back = read_dta("smokers.dta")
stata_code(back.smoker, 3)                                  # 0x05, that is .d
metadata(back, "value_labels")["yesno"][stata_key(".d")]    # "Don't know"
```

**TypeScript**

```ts
import { MISSING, type Missing } from "@jbearak/dta-parser";
import { openDtaFile, writeDtaFile } from "@jbearak/dta-parser/node";

writeDtaFile("smokers.dta", {
  valueLabels: { yesno: new Map<number | Missing, string>([[0, "No"], [1, "Yes"], [MISSING[".d"], "Don't know"]]) },
  variables: [
    { name: "id", type: "long", values: [1, 2, 3] },
    { name: "smoker", type: "byte", valueLabels: "yesno", values: [1, 0, MISSING[".d"]] },
  ],
});

const r = openDtaFile("smokers.dta");
console.log(r.readRows(0, 3, ["smoker"]));             // [ [ 1 ], [ 0 ], [ { missing: '.d' } ] ]
console.log(r.valueLabels("yesno")?.get(MISSING[".d"])); // Don't know
r.close();
```

## What each language supports

The core rows are the same in every language. Where a language differs,
the table says how.

| feature | R | Python | Julia | TypeScript |
|---|---|---|---|---|
| read releases 104 to 119, both byte orders | ✓ | ✓ | ✓ | ✓ |
| select columns; a row range | ✓ | ✓ | ✓ | ✓ |
| storage types, variable labels, display formats, data label, notes | ✓ | ✓ | ✓ | ✓ |
| timestamp, characteristics, sort order | ✓ | ✓ | ✓ | ✓ |
| value labels, including labels on `.a` to `.z` | ✓ | ✓ | ✓ | ✓ |
| `.` and `.a` to `.z` kept per value and written back | ✓ `dta_num` | ✓ `StataArray` | ✓ `DtaColumn` (not through DataFrames' `combine`/`vcat`) | ✓ codes |
| binary strLs | an error | read and write (`bytes`) | read and write (`Vector{UInt8}`) | read and write (`Uint8Array`) |
| text encoding option for files before release 118 | ✓ | ✓ | ✓ | ✓ |
| `%td`, `%tc` as dates | numbers with their format | `datetime64` (opt out) | `Date`, `DateTime` (opt out) | numbers; `formatValue` |
| write release 118 | ✓ | ✓ | ✓ | ✓ |
| a key that sorts and compares as Stata does | built into `dta_num` | `stata_key`, `stata_keys` | `stata_key` | `stataKey`, `stataKeys` |
| Stata comparisons, arithmetic and logic on columns; `tab`, group ids, sets | ✓ | | | |

**Round trips.** In every language, reading a file and writing what was
read gives the same values, missing codes, numeric storage types,
labels, value labels, display formats and notes, within the table above.
String columns come back as narrow as their values allow (and in R and
TypeScript a short strL as a fixed-width string). Text from a file older
than release 118 comes back as UTF-8.

## Repository

| path | what |
|---|---|
| `crates/dta` | the format, in Rust: reader and release 118 writer |
| `crates/dta-ffi` | the WebAssembly interface (for TypeScript) and C interface (for Julia) |
| `r/dtatools` | the R package |
| `python` | the Python package |
| `julia/DtaParser` | the Julia package |
| `js` | the npm package |
| `compat` | test files from haven, pandas and ReadStat, and what those readers make of them |
| `bench` | benchmarks against the other readers |
| `docs` | this documentation, [decisions](docs/adr/) and [plans](docs/plans/) |

To build, test or change anything, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Acknowledgements

dta-parser learns from, tests against and measures itself against these
open-source projects:

- **What we know of the format** comes mainly from the code and
  documentation of [ReadStat](https://github.com/WizardMac/ReadStat)
  (Evan Miller and contributors, MIT) and of pandas' Stata reader and
  writer, [`pandas/io/stata.py`](https://github.com/pandas-dev/pandas/blob/main/pandas/io/stata.py)
  (the pandas development team, BSD-3-Clause). The Rust core in
  `crates/dta` is our own implementation and contains no code from
  either.
- **Tagged missing values in R**: dtatools stores `.a` to `.z` inside
  `NA` with the same bits as `tagged_na()` in
  [haven](https://github.com/tidyverse/haven) (Hadley Wickham, Evan
  Miller, Danny Smith), so the values pass between the two packages
  unchanged ([missing values](docs/guide/missing-values.md)).
- **Reference readers**: the tests check what we read against haven,
  [readstata13](https://github.com/sjewo/readstata13) (Jan Marvin
  Garbuszus, Sebastian Jeworutzki), pandas and
  [pyreadstat](https://github.com/Roche/pyreadstat) (Otto Fajardo), and
  the Julia tests against
  [ReadStatTables.jl](https://github.com/junyuan-chen/ReadStatTables.jl)
  (Junyuan Chen). See [compat/README.md](compat/README.md) and
  [ADR 0005](docs/adr/0005-oracles.md).
- **Test fixtures**: ReadStat's writer makes the files for releases
  104, 105, 108, 110 and 111 (`compat/make_legacy_fixtures.sh`),
  haven and pandas write the rest, and the big-endian files for
  releases 104 to 113 come from pandas' test suite ([compat/fixtures/README.md](compat/fixtures/README.md)).
- **Benchmarks and documentation**: the
  [benchmark plan](docs/plans/0005-four-languages.md) measures our speed
  against haven, readstata13, pandas, pyreadstat, ReadStatTables.jl,
  [StatFiles.jl](https://github.com/queryverse/StatFiles.jl) (David
  Anthoff) and [@irbisadm/statfmt](https://github.com/irbisadm/statfmt)
  (Igor Sheko), and [docs/judging](docs/judging/rubric.md) compared our
  documentation with that of each of them except StatFiles.jl.

[docs/upstream](docs/upstream/README.md) holds drafts of reports for
bugs our tests found in some of these projects.

## License

GPL-3.0 (see [LICENSE](LICENSE)). Some test fixtures come from pandas'
test suite, under its BSD-3-Clause license
([compat/fixtures/LICENSE-pandas](compat/fixtures/LICENSE-pandas)).
