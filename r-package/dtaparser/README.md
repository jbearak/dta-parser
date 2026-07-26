# dtaparser

`dtaparser` is the native R interface to this repository's bounded Rust DTA
reader. Its exported `read_dta()` function deliberately mirrors the formal
arguments of `haven::read_dta()`, while observation storage is decoded by Rust
and materialized through an R-specific collector. Numeric values are written
into their final R vectors during decoding; strings are batch-materialized to
avoid interleaving R allocation with the parser's hot loop.

```r
library(dtaparser)

cars <- read_dta(
  "auto.dta",
  col_select = c(model = make, price, foreign),
  skip = 10,
  n_max = 20
)
```

The reader supports Stata releases 113--115 and 117--119. It retains dataset
and variable labels, display formats, value-label tables, `strL` values, and
system or `.a`--`.z` missing values. `%td` is converted to `Date`; `%tc` and
`%tC` are converted to UTC `POSIXct`. Other Stata calendar formats remain
numeric and retain their `format.stata` attribute.

## Scope and limitations

- `file` must be a local, uncompressed file path. Connections and URLs are not
  supported.
- `encoding` must be `NULL`. Legacy files use Windows-1252 and XML-era files
  use UTF-8 according to the DTA storage format.
- `col_select` uses tidyselect and is resolved from typed metadata before
  observation data are decoded, so predicates such as `where(is.character)`
  work without reading values. If a source column is selected more than once,
  the first selection and alias win. Selection and reading open the file
  separately.
- `.name_repair` is delegated to `tibble::as_tibble()` after selection aliases
  are applied.
- Reads are synchronous. Long reads cooperatively check for R user interrupts.
- R data frames are limited to `2^31 - 1` rows; `skip` and finite `n_max` must
  be exactly representable non-negative whole numbers no larger than `2^53`.

The package includes a locked Cargo dependency graph and vendored crates so
source builds do not contact a package registry. A Rust 1.74-or-newer toolchain
and Cargo are required. Windows builds require 64-bit R and the
`x86_64-pc-windows-gnu` Rust toolchain; `configure.win` rejects a mismatched
host before compilation and the Windows Makevars passes the target explicitly.

## Conformance and release checks

The repository conformance gate compares every bundled fixture against the
checked TypeScript/Rust oracle and, when R plus its test dependencies are
available, installs the package from the current source and compares it with
haven. Missing R dependencies produce an explicit `SKIP`; CI sets
`DTA_REQUIRE_R_CONFORMANCE=1` and checks Linux, macOS, and Windows. Only
nonmissing floating values permit `1e-7` relative tolerance; missing tags,
labels, formats, value-label tables, strings, names, dimensions, projections,
and row windows are otherwise exact. Package tests also require the direct-R
collector to be identical to the retained `DtaData`/Rust-vector collector on
every bundled fixture.

```sh
DTA_REQUIRE_R_CONFORMANCE=1 bun run conformance
R CMD build r-package/dtaparser
R CMD check --no-manual dtaparser_0.1.0.tar.gz
Rscript benchmarks/r-materialization/run.R input.dta timings.tsv 21
```

The native source of truth is `rust/dta-parser`. After a root-first change,
mirror it here and run `scripts/check-rust-sync.sh`; the check also verifies the
Cargo locks and deterministic offline `vendor.tar.gz` identity. Windows CI
installs and selects `stable-x86_64-pc-windows-gnu`, confirms the rustc host,
then actually builds and checks the package through Rtools.
