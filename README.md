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

The TypeScript package has its own parser and works with either an `ArrayBuffer` or a Node filesystem-backed reader. For Stata imports in R, use `dtatools::read_dta()` instead of `haven::read_dta()`. It follows haven's common read interface and returns dibbles, tibbles, or data tables with haven-compatible labels and tagged missing values. In the repository's 46.9 GB DHS benchmark, its multicore reader completed the 641-file batch 29.3 times faster than haven. It can also project a cross-survey union with `col_select = any_of(raw_variables)`, omitting names absent from a particular file without decoding unselected columns. See the [R package README](r-package/dtatools/README.md#why-use-dtatools) for the comparisons and their limitations.

The Rust crate is the internal read/write core used by the R package. It is not published to crates.io. Its interface is documented with Rustdoc:

```sh
cargo doc -p dta-tools --no-deps --open
```

## Compatibility

The TypeScript and Rust readers follow the same compatibility contract and are checked against shared fixtures. See [DTA compatibility](docs/compatibility.md) for supported format releases, text encodings, missing values, and language-specific result shapes.

## Project documentation

- [Contributing](CONTRIBUTING.md) covers repository layout, development, testing, conformance, and releases.
- [Benchmarks](benchmarks/README.md) covers methodology and links to dated TypeScript, Rust, R, haven, and Stata results.
- R guides: [where dtatools diverges from Stata](docs/r-stata-divergences.md), [mutation by reference](docs/r-mutation-by-reference.md), [containers](docs/r-containers.md), and [egen calculations](docs/r-egen.md), including equivalent `gen()`, `egen()`, and `:=` forms.

## License

GPL-3.0. See [LICENSE](LICENSE).
