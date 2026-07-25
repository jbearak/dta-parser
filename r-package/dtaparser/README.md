# dtaparser

`dtaparser` is the native R interface to this repository's bounded Rust DTA
reader. Its exported `read_dta()` function deliberately mirrors the formal
arguments of `haven::read_dta()`, while observation storage is decoded by Rust
and copied directly into R vectors.

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
