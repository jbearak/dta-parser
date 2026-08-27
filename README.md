# dta-parser

`dta-parser` provides TypeScript and R libraries for reading Stata `.dta` files.
Both readers cover Stata 5 through 19 and preserve labels, long strings, display
formats, and Stata missing values. The R package also writes standalone Stata
18/19 datasets.

## Choose a library

| Language | Package | Start here |
| --- | --- | --- |
| TypeScript | [`@jbearak/dta-parser`](typescript/dta-parser) | [npm package README](typescript/dta-parser/README.md) |
| R | [`dtaparser`](r-package/dtaparser) | [R package README](r-package/dtaparser/README.md) |

The TypeScript package has its own parser and works with either an `ArrayBuffer` or a Node filesystem-backed reader. For Stata imports in R, use `dtaparser::read_dta()` instead of `haven::read_dta()`. It follows haven's common read interface and returns tibbles with haven-compatible labels and tagged missing values. In the repository's 46.9 GB DHS benchmark, its multicore reader completed the 641-file batch 29.3 times faster than haven. See the [R package README](r-package/dtaparser/README.md#why-use-dtaparser) for the comparison and its limitations.

The Rust crate is the internal parser used by the R package. It is not published to crates.io. Its interface is documented with Rustdoc:

```sh
cargo doc -p dta-parser --no-deps --open
```

## Compatibility

The two parsers follow the same compatibility contract and are checked against shared fixtures. See [DTA compatibility](docs/compatibility.md) for supported format releases, text encodings, missing values, and language-specific result shapes.

## Project documentation

- [Contributing](CONTRIBUTING.md) covers repository layout, development, testing, conformance, and releases.
- [Benchmarks](benchmarks/README.md) covers methodology and links to dated TypeScript, Rust, R, haven, and Stata results.

## License

GPL-3.0. See [LICENSE](LICENSE).
