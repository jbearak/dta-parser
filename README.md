# dta-parser

This repository contains three libraries for reading Stata `.dta` files,
built around two independent parser implementations:

| Library | Location | Parser implementation | Primary interface |
| --- | --- | --- | --- |
| TypeScript/npm package | [`typescript/dta-parser`](typescript/dta-parser) | TypeScript | `@jbearak/dta-parser` and `@jbearak/dta-parser/node` |
| Rust crate | [`rust/dta-parser`](rust/dta-parser) | Rust | `dta_parser::{read_dta, DtaFile}` |
| R package | [`r-package/dtaparser`](r-package/dtaparser) | Rust | `dtaparser::read_dta()` |

The TypeScript and Rust parsers are separate implementations checked against
the same fixtures and compatibility contract. The R package is a language
binding around the Rust parser, not a third parser.

## Libraries

### TypeScript

[`@jbearak/dta-parser`](typescript/dta-parser) provides portable buffer-based
parsing and a Node filesystem-backed `DtaFile` API. It was first written inside
[Sight](https://github.com/jbearak/sight), then extracted for use by Sight and
[manuscript-markdown](https://github.com/jbearak/manuscript-markdown).

See the [TypeScript package README](typescript/dta-parser/README.md) for npm
installation, entrypoints, examples, supported formats, and the API reference.

### Rust

[`dta-parser`](rust/dta-parser) reads byte slices or bounded `Read + Seek`
sources into storage-preserving, column-oriented vectors. It supports row and
column projection, exact missing tags, value labels, long strings, cooperative
cancellation, and strict format validation.

See the [Rust crate README](rust/dta-parser/README.md) for examples and its I/O
and memory contracts.

### R

[`dtaparser`](r-package/dtaparser) exports a haven-shaped `read_dta()` function
backed by the bounded Rust reader. It supports tidyselect projection, row
windows, labelled data, tagged missing values, long strings, and R date/time
classes.

See the [R package README](r-package/dtaparser/README.md) for installation,
documented interface limitations, conformance with `haven::read_dta()`, and
benchmark results.

## Compatibility

All three libraries read Stata releases 111, 113--115, and 117--119:

| Release | Stata generation |
| ---: | --- |
| 111 | Stata/SE 7 |
| 113 | Stata 8 |
| 114 | Stata 10 |
| 115 | Stata 12 |
| 117 | Stata 13 |
| 118 | Stata 14--19 |
| 119 | Stata 15--19 files with more than 32,767 variables |

Release 111 uses the fixed legacy header shared with release 113: 33-byte
variable names, 12-byte display formats, 33-byte value-label names, 81-byte
variable labels, one-byte storage codes, and 32-bit expansion-field lengths.
Unlike later releases, it has one system-missing value per numeric storage
type and does not encode `.a`--`.z` tags; integer system missing is the storage
maximum. Releases 114--115 widen display-format fields to 49 bytes.

Other formats are rejected. Each library preserves Stata's system missing and
`.a`--`.z` missing values where the on-disk release supports them rather than
collapsing distinct tags into a single sentinel.
See the language-specific README for differences in result shape, I/O, date
conversion, and public API.

## Repository layout

| Path | Purpose |
| --- | --- |
| [`typescript/dta-parser`](typescript/dta-parser) | TypeScript source, tests, built distribution, and npm metadata |
| [`rust/dta-parser`](rust/dta-parser) | Rust parser crate and Rust tests |
| [`r-package/dtaparser`](r-package/dtaparser) | R package and its vendored copy of the Rust parser |
| [`tests/fixtures/dta`](tests/fixtures/dta) | Shared immutable `.dta` fixtures |
| [`conformance`](conformance) | Cross-implementation compatibility inventory |
| [`scripts`](scripts) | Conformance and Rust/R source-synchronization checks |
| [`benchmarks`](benchmarks) | Report-only TypeScript, Rust, and R benchmarks |

The Rust crate is the source of truth for the Rust parser and its R binding.
The R package mirrors its runtime tree under
`r-package/dtaparser/src/vendor/dta-parser`; do not edit only the mirror.
Matching `dta-parser.tree.sha256` files pin the normalized parser manifest,
recursive `src` contents, and an optional `build.rs` script.
`scripts/check-rust-sync.sh` verifies both trees and
pins, Cargo locks, and the normalized offline dependency archive. After
mirroring a parser change, run `scripts/check-rust-sync.sh --update-pins`; it
refuses to update the pins unless the canonical and R runtime trees agree.
The repository synchronization checker requires Python 3.11 or newer; R
package installation does not require Python.

## Conformance and benchmarks

`conformance/cases.json` identifies 22 immutable fixture files and eight
generated or derived cases. The shared contract covers format and byte order,
metadata, rows and columns, storage types, labels, formats, value-label tables,
`strL` cells, exact missing tags, projections, row windows, and representative
rejection errors.

From the repository root:

```sh
scripts/conformance.sh
scripts/check-rust-sync.sh
```

The conformance command reports R/haven as `SKIP` when R or its test
dependencies are unavailable. Set `DTA_REQUIRE_R_CONFORMANCE=1` to require
that comparison. Benchmark commands and reporting requirements are in
[`benchmarks/README.md`](benchmarks/README.md); benchmarks are evidence for
investigation and do not impose timing thresholds.

## Development

Run TypeScript package checks from its package directory:

```sh
cd typescript/dta-parser
bun install --frozen-lockfile
bun run typecheck
bun run test
bun run build
```

Run Rust and repository-wide checks from the repository root:

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --all-targets --locked
cargo doc --workspace --locked --no-deps
scripts/conformance.sh
scripts/check-rust-sync.sh
```

Build and check the R source package from the repository root with its declared
R dependencies installed:

```sh
dtaparser_version="$(sed -n 's/^Version: //p' r-package/dtaparser/DESCRIPTION)"
dtaparser_tarball="dtaparser_${dtaparser_version}.tar.gz"
R CMD build r-package/dtaparser
R CMD check --no-manual "$dtaparser_tarball"
```

## License

GPL-3.0. See [LICENSE](LICENSE).
