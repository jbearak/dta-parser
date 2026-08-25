# dtaparser

`dtaparser` is the R interface to this repository's bounded Rust DTA
reader. Its exported `read_dta()` function follows `haven::read_dta()` and adds
optional `threads` and `use_numeric_altrep` controls, while observation storage is
decoded by Rust and materialized through an R-specific collector. Byte, int,
long, and float values retain their compact source widths through ALTREP by
default; source doubles are written eagerly. Each character column interns its
distinct normalized UTF-8 values once and keeps compact row-to-dictionary
indices behind an ordinary R character vector through ALTREP. Element access
resolves the dictionary immediately; allocation of the complete row-level
string-pointer vector is deferred, without retaining the source file.

Large reads from every supported Stata release use a shared block decoder
across multiple cores by default. `threads = 0` selects an automatic count,
`threads = 1` forces the serial executor, and a positive larger value requests
an explicit count capped by available parallelism and selected columns. Small
inputs and projections containing `strL` remain serial. Both executors use the
same validated observation plan and scalar value-decoding semantics.

## Installation

Published GitHub Releases include compiled R packages for Windows x86_64,
Linux x86_64, and macOS ARM64. The R version, platform, and architecture are
part of each asset name. A matching asset URL can be installed with its required
dependencies by `pak` without compiling `dtaparser` locally:

```r
pak::pkg_install("url::https://github.com/jbearak/dta-parser/releases/download/vX.Y.Z/<matching-asset>")
```

Base R can also install one matching URL with
`install.packages(url, repos = NULL)` after the package's Imports are installed;
the archive extension lets R detect the binary format. GitHub does not select
an asset for the current platform, so callers must use the URL whose R version,
operating system, and architecture match their R installation.

```r
library(dtaparser)

cars <- read_dta(
  "auto.dta",
  col_select = c(model = make, price, foreign),
  skip = 10,
  n_max = 20
)
```

`file` accepts the same practical input sources as `haven::read_dta()`:
local paths, raw DTA bytes, binary connections, and URLs. Gzip files are
decompressed locally or over a URL; local bzip2, xz, and zip files are also
decompressed automatically. Source resolution is delegated to
`readr::datasource()`, the same interface used by haven 2.5.5. Character
vectors containing literal text are rejected because haven does not handle
the resulting `source_string` for DTA input.

URLs are fetched at call time. Applications that pass untrusted values to
`file` should validate or allowlist acceptable sources before calling
`read_dta()`; the reader does not impose a network allowlist.

Source resolution remains an R-layer concern. An ordinary uncompressed local
file is passed straight to the path-based Rust reader without copying its
contents. Raw bytes and readr-resolved connections, compressed inputs, and
URLs use temporary files that are removed when the read succeeds, errors, or
is interrupted. This keeps network and decompression dependencies out of the
reusable Rust parser.

The reader supports Stata releases 105, 108, 110--111, 113--115, and 117--119. It retains dataset
and variable labels, dataset notes, display formats, value-label tables,
`strL` values, and system missing values plus `.a`--`.z` tags where the release
supports them. `%td` and legacy or
custom daily-date formats beginning `%d` are converted to `Date`; `%tc` and
`%tC` are converted to UTC `POSIXct`. Other Stata calendar formats remain
numeric and retain their `format.stata` attribute.

`encoding = NULL` uses Windows-1252 for pre-Unicode releases 105, 108,
110--111, 113--115, and 117, and UTF-8 for releases 118--119. Pre-Unicode DTA
files do not record a code page, so Windows-1252 is a pragmatic guess that
commonly recovers the intended text rather than a fact encoded in the file.
Use `encoding = "UTF-8"` for strict Stata 18 behavior. A known source encoding
can instead be selected with a case-insensitive UTF-8/UTF8,
Windows-1252/CP1252, or ISO-8859-1/latin1 alias. The override is deterministic
across platforms and applies to dataset and variable metadata, fixed strings,
`strL` payloads, and value-label names and text. ISO-8859-1 remains distinct
from Windows-1252 at bytes 0x80--0x9f. Other encoding names produce an error
instead of inheriting platform-dependent `iconv` alias or lossy-conversion
behavior. Haven 2.5.5 does not apply its override to modern `strL` payloads;
`dtaparser` deliberately applies the requested encoding consistently there.
With an explicit UTF-8 override, malformed input sequences are replaced
deterministically with U+FFFD. Haven 2.5.5 may instead omit or empty an affected
label.

## Stata missing values and labels

In releases that support extended missings (113 and newer), Stata reserves 27
numeric codes for missing values: system missing `.`, followed by `.a` through
`.z`. They occupy the top of each supported numeric storage range. For example,
byte storage uses 101 through 127, int uses 32,741 through 32,767, and long uses
2,147,483,621 through 2,147,483,647. Float and double storage use corresponding
reserved high-value bit patterns. In Stata, every missing code compares greater
than every observed number, with `. < .a < ... < .z`. Earlier supported
releases 105 through 111 encode only system missing.

`dtaparser` preserves which code was stored, including all 27 where the source
release supports them, but returns normal R-compatible numeric vectors. System
missing `.` becomes `NA_real_`; `.a` through `.z` become the tagged-NA payloads
used by haven. Base R therefore recognizes every Stata missing code without a
package-specific method.

### Using missing values in R

```r
x <- c(
  1,
  NA_real_,                   # Stata .
  haven::tagged_na("a"),      # Stata .a
  haven::tagged_na("z")       # Stata .z
)

is.na(x)
#> [1] FALSE  TRUE  TRUE  TRUE

haven::na_tag(x)
#> [1] NA  NA  "a" "z"

haven::is_tagged_na(x)
#> [1] FALSE FALSE  TRUE  TRUE

haven::is_tagged_na(x, "a")
#> [1] FALSE FALSE  TRUE FALSE

haven::na_tag(x) %in% c("a", "f")
#> [1] FALSE FALSE  TRUE FALSE
```

`haven::is_tagged_na()` accepts only one specific tag at a time, so use
`haven::na_tag(x) %in% tags` to match several tags. These functions are
exported by haven; the explicit `haven::` prefix means haven does not need to
be attached with `library(haven)`.

To identify system missing specifically, while excluding tagged missings and
ordinary `NaN`, use:

```r
system_missing <- is.na(x) & !is.nan(x) &
  !haven::is_tagged_na(x)
```

Use ordinary `NA_real_` to create Stata system missing and
`haven::tagged_na()` for an extended missing value. Assignment to a compact
numeric ALTREP column materializes that column as an ordinary R double vector,
as any writable mutation must.

```r
x[1] <- NA_real_                 # Stata .
x[2] <- haven::tagged_na("a")    # Stata .a
x[3] <- haven::tagged_na("f")    # Stata .f
```

### Recoding without losing missing tags

With base R, direct assignment and `replace()` preserve every unselected tag.
Make an observed-value predicate non-missing before using it as an assignment
index:

```r
x <- c(1, NA_real_, haven::tagged_na(c("a", "f", "z")))
selected <- !is.na(x) & x == 1
x[selected] <- 10
x <- replace(x, selected, 10)

x[haven::is_tagged_na(x, "a")] <- -1
```

Avoid `ifelse(x == 1, 10, x)`: `x == 1` is `NA` at every missing position, so
`ifelse()` writes ordinary `NA` there and loses extended tags. Adding
`!is.na(x) &` makes the test complete and preserves the payloads, but
`ifelse()` still drops attributes. Direct assignment is therefore the safer
base-R pattern for an existing column. `transform()` and `within()` inherit the
behavior of the expression used on their right-hand side.

Tidyverse operations similarly preserve tagged missings when the recoding
expression carries unmatched values forward from the original column. For
example, this replaces only `.a` and leaves `.`, `.b` through `.z`, and
observed values unchanged:

```r
data <- dplyr::mutate(
  data,
  status = dplyr::case_when(
    haven::is_tagged_na(status, "a") ~ -1,
    .default = status
  )
)
```

`dplyr::if_else()` preserves tags when its condition contains no `NA` and its
unselected branch returns the original values. If its condition can be `NA`,
also pass `missing = x`; otherwise those positions become ordinary `NA`. In
contrast, legacy `dplyr::recode()` rebuilds unmatched missing values in bare
numeric columns as ordinary `NA` and therefore loses their tags, even when
recoding only an observed number. It does not support classed
`haven_labelled`, `Date`, or `POSIXct` columns. Prefer `case_when()` or a
correctly specified `if_else()` for tagged columns. Operations intended to
replace missing values, such as
`dplyr::coalesce()`, `tidyr::replace_na()`, or a branch selected by `is.na()`,
match all 27 codes by design; use `haven::is_tagged_na(x, tag)` when only one
extended code should change.

These transformations may materialize a compact ALTREP column. Operations
that construct a new vector can also drop Stata metadata attributes such as
`label`, `format.stata`, or `labels`, just as they can for a vector read by
haven. Missing tags are numeric payloads rather than metadata attributes, so
the two concerns are separate.

Do not use `haven::tagged_na(".")` for system missing; canonical system missing
is `NA_real_`. R comparisons deliberately follow R missing-value semantics, so
`x > 100` returns `NA` at every missing position rather than reproducing
Stata's high-value comparison ordering. Use `haven::na_tag()` and an explicit
factor/order when the order among missing tags matters.

Missing tags are encoded in the numeric values themselves, not in the value
label attribute. Stata metadata are exposed separately:

```r
attr(cars, "label")              # dataset label
attr(cars, "notes")              # dataset notes
attr(cars$foreign, "label")      # variable label
attr(cars$foreign, "format.stata")
attr(cars$foreign, "labels")     # named numeric vector: text -> code
```

A non-temporal numeric column with a Stata value-label table has classes
`haven_labelled`, `vctrs_vctr`, and `double`. Its `labels` attribute is a named
numeric vector whose names are display text and whose values are the associated
codes. If Stata labels a missing code, that attribute value uses the same
tagged-NA representation and can also be inspected with `haven::na_tag()`.

Narrow numeric ALTREP columns keep the original Stata sentinels in compact
backing storage until values are requested. Conversion to R system/tagged NAs
happens during element or region access, summary kernels, or materialization.
Source doubles, and all numeric columns read with
`use_numeric_altrep = FALSE`, are converted during decoding instead. Both paths
have identical R missing-value semantics.

## Performance compared with haven and Stata

The dta-parser cells below were rerun from PR #48 at implementation commit
`1006ae4`. Haven 2.5.5 and Stata/MP 18 were not rerun: their cells retain the
archived matched measurements on the identical files. Restricting the refresh
to four deterministic synthetic workloads and one recent file from each survey
family keeps the comparison economical while covering both controlled and
real-world inputs.

Measurements used an Apple M4 Max with 128 GB RAM, macOS 26.5.2, R 4.6.1, and
Rust 1.98.0. Synthetic inputs are mixed-type, 40-column Stata 15 files. Their
elapsed times are seven-run warm-cache medians and their peak RSS values are
three-run fresh-process medians. The India DHS and NSFG rows each use one
fresh-process read, matching the archived corpus methodology. All refreshed
reads returned the archived row and column dimensions.

Peak RSS means peak resident set size: the greatest amount of physical memory
attributed to the reader process during the run. It includes the R or Stata
runtime and the loaded result, but not memory used by other processes or the
operating system's file cache outside that process. Values below use decimal GB
(`GB = 10^9 bytes`).

| Dataset/workload | Input | dta-parser time | haven time | Stata time | dta-parser / haven time | dta-parser / Stata time | dta-parser peak RSS | haven peak RSS | Stata peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Synthetic 100 MB, full 40 columns (release 119) | 0.100 GB | 0.025 s | 1.053 s | 0.011 s | 0.024x | 2.273x | 0.223 GB | 0.253 GB | 0.143 GB |
| Synthetic 100 MB, projected 8 columns (release 119) | 0.100 GB | 0.014 s | 0.271 s | 0.014 s | 0.052x | 1.000x | 0.182 GB | 0.168 GB | 0.058 GB |
| Synthetic 1 GB, full 40 columns (release 119) | 1.000 GB | 0.143 s | 10.958 s | 0.101 s | 0.013x | 1.416x | 0.663 GB | 0.888 GB | 1.133 GB |
| Synthetic 1 GB, projected 8 columns (release 119) | 1.000 GB | 0.073 s | 3.120 s | 0.140 s | 0.023x | 0.521x | 0.269 GB | 0.292 GB | 0.365 GB |
| India DHS 2021 women (release 113; 724,115 × 5,972) | 5.196 GB | 1.896 s | 437.088 s | 0.718 s | 0.004x | 2.641x | 5.218 GB | 35.103 GB | 5.256 GB |
| NSFG 2017–2019 women (release 118; 6,141 × 2,610) | 0.020 GB | 0.068 s | 1.002 s | 0.003 s | 0.068x | 22.667x | 0.142 GB | 0.308 GB | 0.051 GB |

Both ratio columns are dta-parser time divided by comparator time. Values below
1x favor dta-parser. Across these rows, dta-parser was 14.7–230.5 times as fast
as haven. It matched Stata on the projected 100 MB file and was faster on the
projected 1 GB file; Stata remained faster on the other four workloads.

Numeric ALTREP materially changes both load time and memory. Relative to the
previous dta-parser cells at `2d09478`, the four synthetic medians fell by
43.8–65.8%, India DHS fell from 35.030 to 1.896 seconds (94.6%), and NSFG fell
from 0.188 to 0.068 seconds (63.8%). Peak RSS fell by 9.3–21.0% on the
synthetic workloads, by 85.2% on India DHS, and by 49.8% on NSFG. On the
5.196 GB India file, dta-parser used 5.218 GB peak RSS versus haven's
35.103 GB and Stata's 5.256 GB.

These are load-and-return measurements. The result remains reachable through
process exit, but the dimensions check does not request contiguous vectors, so
dictionary-backed strings and narrow numeric ALTREP columns can remain compact.
A later operation that requires a writable or contiguous double vector pays
the deferred conversion cost then. That is expected deferral rather than
duplicate loading; use `use_numeric_altrep = FALSE` when eager widening better
matches the downstream workload.

R elapsed time covers only the reader call. Stata elapsed time covers its
`use` command. Application startup is excluded from elapsed time and included
in fresh-process peak RSS. Stata's official
[`use` manual](https://www.stata.com/manuals/duse.pdf) describes a real
in-memory load, so it remains a useful eager native-format reference even
though dta-parser must additionally construct R-compatible objects.

The archived [synthetic report](../../benchmarks/large-scale/results-2026-08-24.md)
and [corpus report](../../benchmarks/r-corpus-performance/results-2026-08-24.md)
provide comparator provenance and the full older corpus run. Benchmark
artifacts are report-only evidence, not CI performance thresholds.

## Scope and limitations

- Remote bzip2, xz, and zip files have the same limitations as
  `readr::datasource()`; download them locally first when readr cannot expose
  them as a decompressed source.
- `col_select` uses tidyselect and is resolved from typed metadata before
  observation data are decoded, so predicates such as `where(is.character)`
  work without reading values. If a source column is selected more than once,
  the first selection and alias win. Selection and reading open the file
  separately.
- `.name_repair` is delegated to `tibble::as_tibble()` after selection aliases
  are applied.
- Reads are synchronous. Long reads cooperatively check for R user interrupts.
- `threads = 0` automatically parallelizes sufficiently large reads from any
  supported release without selected `strL` columns. Use `threads = 1` for
  deterministic single-thread benchmarking. Option `dtaparser.threads`
  controls the default.
- `use_numeric_altrep = TRUE` retains byte, int, long, and float source widths until
  R needs a contiguous double data pointer. Set it to `FALSE`, or set option
  `dtaparser.numeric_altrep = FALSE`, to create eager double vectors during
  decoding for workloads that immediately materialize every numeric column.
- Character columns use dictionary-backed ALTREP vectors. Loading does not
  depend on the source path after `read_dta()` returns. Distinct R strings are
  created once during the load; operations that request a contiguous pointer
  to every row defer only that pointer-vector allocation until it is needed.
- R data frames are limited to `2^31 - 1` rows. `skip` must be an exactly
  representable non-negative whole number no larger than `2^53`. For `n_max`,
  `NA`, either infinity, and any negative finite value use haven's intentional
  “all remaining rows” convention; non-negative values have the same whole
  number and `2^53` limits.

### Row-window compatibility

`skip` and `n_max` are normalized once in R, before either materialization path
enters native code. Safe scalar integers and integer-valued doubles therefore
select the same rows as `haven::read_dta()`, including zero and values beyond
the file's row count when they are representable by haven's native boundary.
At the extreme `skip = 2^53` boundary, dtaparser deterministically returns an
empty result while haven's native integer coercion is platform-dependent. The
package also follows haven's intentional upstream `n_max` normalization by
mapping `NA`, `Inf`, `-Inf`, and negative finite values to one unlimited-row
sentinel.

Some haven 2.5.5 edge behavior comes from native integer coercion rather than
its `n_max` normalization contract. This package does not inherit those
coercions: it validates or normalizes these inputs deterministically before
opening the file:

| Input | dtaparser behavior | haven 2.5.5 behavior |
| --- | --- | --- |
| fractional non-negative `n_max` | error | truncates |
| `NaN` `n_max` | error | reads all rows |
| negative, missing, or infinite `skip` | error | native-coercion-dependent window |
| fractional `skip` | error | error from the native boundary |
| non-scalar or non-numeric values | error | error |
| very large whole `skip` through `2^53` | deterministic row window | platform-dependent native coercion |
| values greater than `2^53` | error | integer overflow/coercion behavior |

These deterministic choices avoid silent truncation and platform-dependent
overflow while retaining haven parity for meaningful row-window requests.

The package includes a locked Cargo dependency graph and vendored crates so
source builds do not contact a package registry. A Rust 1.98.0-or-newer toolchain
and Cargo are required for the R bridge on every platform. The Rust target
architecture must match R. On Windows, Rtools additionally requires a
MinGW-compatible Rust host: `x86_64-pc-windows-gnu` for x86_64 R or
`aarch64-pc-windows-gnullvm` for aarch64 R. `configure.win` rejects a mismatched
host before compilation and the Windows Makevars passes the target explicitly.

## Conformance and release checks

The repository conformance gate compares every bundled fixture against the
checked TypeScript/Rust oracle and, when R plus its test dependencies are
available, installs the package from the current source and compares it with
haven. Missing R dependencies produce an explicit `SKIP`; CI sets
`DTA_REQUIRE_R_CONFORMANCE=1` and checks Linux, macOS, and Windows. Only
nonmissing floating values permit `1e-7` relative tolerance; missing tags,
labels, formats, value-label tables, strings, names, dimensions, projections,
and row windows are otherwise exact. Package tests also require the dta-parser
collector to be identical to the retained `DtaData`/Rust-vector collector on
every bundled fixture.

```sh
DTA_REQUIRE_R_CONFORMANCE=1 scripts/conformance.sh
dtaparser_version="$(sed -n 's/^Version: //p' r-package/dtaparser/DESCRIPTION)"
dtaparser_tarball="dtaparser_${dtaparser_version}.tar.gz"
R CMD build r-package/dtaparser
R CMD check --no-manual "$dtaparser_tarball"
mkdir -p "$PWD/target"
benchmark_lib="$(mktemp -d "$PWD/target/r-benchmark-library.XXXXXX")"
R CMD INSTALL --library="$benchmark_lib" "$dtaparser_tarball"
export DTAPARSER_BENCH_LIB="$benchmark_lib"
Rscript benchmarks/r-materialization/run.R input.dta timings.tsv 21
```

The materialization benchmark runners require `DTAPARSER_BENCH_LIB` and verify
that the package is loaded from that freshly populated, checkout-local library
rather than an unrelated global installation.

The canonical Rust parser lives directly in `src/dta-parser`; there is no
first-party mirror or copy step. The separate `src/rust` crate provides the R
bridge and builds with `--locked --offline`. Its `vendor.tar.gz` contains only
third-party Cargo dependencies, and `scripts/check-r-cargo-vendor.sh` verifies
the archive against `vendor.sha256` and the bridge lock. Configure always
refreshes the extracted dependencies before building. Python 3.11 or newer is
only required for repository maintenance and CI, not R package installation.
Windows CI installs and selects Rust 1.98.0 with the
`x86_64-pc-windows-gnu` host matching R, confirms the exact version and host,
then builds and checks the package through Rtools.
