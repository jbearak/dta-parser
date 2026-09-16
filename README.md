# dta-tools

`dta-tools` provides TypeScript and R libraries for working with Stata `.dta`
files. Both readers cover Stata 5 through 19 and preserve labels, long strings,
display formats, and Stata missing values. The R package also writes Stata
18/19 `.dta` files. Its Arrow-based `.arrow` format preserves supported R column
classes alongside Stata storage types and metadata in the same data frame.
The R package also supplies Stata-aware metadata, storage, recoding, tabulation,
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
labels and tagged missing values. In the September 16, 2026 corpus run, its
multicore reader completed the 641-file, 46.9 GB DHS corpus in 38.7 seconds,
about 70 times as fast as the recorded haven comparison. In the ten-read
India comparison, median read time for the 5.2 GB file was well under a second,
versus several minutes with haven.
See the R package README for
[benchmarks and methods](r-package/dtatools/README.md#why-use-dtatools).

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
