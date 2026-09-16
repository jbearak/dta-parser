# dta-tools

`dta-tools` provides TypeScript and R libraries for working with Stata `.dta`
files. Both readers cover Stata 5 through 19 and preserve labels, long strings,
display formats, and Stata missing values. The R package also writes standalone
Stata 18/19 `.dta` datasets or standalone `.arrow` datasets; callers choose one
format for each save. The `.arrow` format preserves supported ordinary R column
classes alongside Stata storage types and metadata, so one data frame can mix R
and Stata columns without flattening them to one set of column types. The R
package also supplies Stata-aware metadata, storage, recoding, tabulation,
merge, and data-signature operations.

## Choose a library

| Language | Package | Start here |
| --- | --- | --- |
| TypeScript | [`@jbearak/dta-parser`](typescript/dta-parser), DTA and Arrow IPC readers | [npm package README](typescript/dta-parser/README.md) |
| R | [`dtatools`](r-package/dtatools) | [R package README](r-package/dtatools/README.md) |

The TypeScript package has its own parser and works with either an `ArrayBuffer`
or a Node filesystem-backed reader.

For Stata imports in R, `dtatools::read_dta()` follows haven's common read
interface and returns dibbles, tibbles, or data tables with haven-compatible
labels and tagged missing values. Its multicore reader completed the
repository's 641-file, 46.9 GB DHS benchmark 69.1 times faster than haven.

For repeated analysis, save an Arrow copy once per source-file version and
read only the variables each analysis needs. Both readers accept
`col_select = any_of(raw_variables)`, omitting names absent from a particular
survey. Dibbles retain Stata column types and metadata through supported
operations, including Stata-aware merges. See the R package README for the
[reusable-file workflow](r-package/dtatools/README.md#reuse-survey-files-across-analyses)
and [benchmarks](r-package/dtatools/README.md#why-use-dtatools), including the
opt-in development reader results and their limitations.

The Rust crate is the internal read/write core used by the R package. It is not published to crates.io. Its interface is documented with Rustdoc:

```sh
cargo doc -p dta-tools --no-deps --open
```

## Compatibility

Install the R package from the [dtatools package repository](https://jbearak.github.io/dta-parser/):

```r
install.packages("dtatools", repos = c(
  dtatools = "https://jbearak.github.io/dta-parser",
  CRAN = "https://cloud.r-project.org"
))
```

See [installation and publishing details](docs/r-package-repository.md) for
binary support, source requirements, and automatic release updates.

Package-owned underscore identifiers use `dta_` and `_dta`. See the
[naming migration](docs/dta-naming.md) for renamed classes, constants, and metadata fields.

The TypeScript and Rust readers follow the same compatibility contract and are checked against shared fixtures. See [DTA compatibility](docs/compatibility.md) for supported format releases, text encodings, missing values, and language-specific result shapes.

## Project documentation

- [Contributing](CONTRIBUTING.md) covers repository layout, development, testing, conformance, and releases.
- [Benchmarks](benchmarks/README.md) covers methodology and links to dated TypeScript, Rust, R, haven, and Stata results.
- R guides: [intentional differences from Stata](docs/r-stata-divergences.md), including [numeric replacement and identifier precision](docs/r-stata-divergences.md#numeric-replacement), [mutation by reference](docs/r-mutation-by-reference.md), [containers](docs/r-containers.md), and [egen calculations](docs/r-egen.md), including equivalent `gen()`, `egen()`, and `:=` forms.

## License

GPL-3.0. See [LICENSE](LICENSE).
