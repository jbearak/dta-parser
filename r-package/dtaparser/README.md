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

The dta-parser cells for synthetic release-119 inputs and every recognized
corpus release were refreshed with the automatic multicore executor at commit
`2d09478`. Haven and Stata were not rerun: their cells retain the archived
matched comparison on the identical files.

On an Apple M4 Max with 128 GB RAM, the new dictionary-backed implementation
was benchmarked against haven 2.5.5 and Stata/MP 18. The synthetic files are
deterministic mixed-type Stata 15 datasets with 40 columns; their time cells are
seven-run warm-cache medians. The DHS, MICS, and NSFG suite visited all 1,823
regular DTA files under the local corpus cache in fresh processes. Its time
cells are sums and its memory cells are the largest per-file peak RSS on the
common set that all three readers loaded with identical dimensions. Corpus
rows are disaggregated by the release stored in each DTA signature. Comparator
values are unchanged in both the release-specific and `all releases` rows.

| Dataset/workload | Common files | Input | dta-parser time | haven time | Stata time | dta-parser / haven time | dta-parser / Stata time | dta-parser peak RSS | haven peak RSS | Stata peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Synthetic 100 MB, full 40 columns (release 119) | 1 | 0.100 GB | 0.073 s | 1.053 s | 0.011 s | 0.069x | 6.636x | 0.276 GB | 0.253 GB | 0.143 GB |
| Synthetic 100 MB, projected 8 columns (release 119) | 1 | 0.100 GB | 0.035 s | 0.271 s | 0.014 s | 0.129x | 2.500x | 0.201 GB | 0.168 GB | 0.058 GB |
| Synthetic 1 GB, full 40 columns (release 119) | 1 | 1.000 GB | 0.258 s | 10.958 s | 0.101 s | 0.024x | 2.554x | 0.839 GB | 0.888 GB | 1.133 GB |
| Synthetic 1 GB, projected 8 columns (release 119) | 1 | 1.000 GB | 0.130 s | 3.120 s | 0.140 s | 0.042x | 0.929x | 0.302 GB | 0.292 GB | 0.365 GB |
| DHS — release 111 | 129 | 8.320 GB | 18.254 s | 435.302 s | 63.506 s | 0.042x | 0.287x | 4.526 GB | 4.526 GB | 0.725 GB |
| DHS — release 113 | 484 | 37.343 GB | 71.413 s | 2,226.568 s | 5.124 s | 0.032x | 13.937x | 35.127 GB | 35.103 GB | 5.256 GB |
| DHS — release 114 | 24 | 1.162 GB | 3.210 s | 61.036 s | 0.163 s | 0.053x | 19.693x | 0.898 GB | 0.914 GB | 0.149 GB |
| DHS — release 117 | 1 | 0.028 GB | 0.090 s | 1.505 s | 0.004 s | 0.060x | 22.500x | 0.325 GB | 0.344 GB | 0.056 GB |
| DHS — release 118 | 3 | 0.050 GB | 0.185 s | 2.640 s | 0.009 s | 0.070x | 20.556x | 0.411 GB | 0.430 GB | 0.077 GB |
| DHS — all releases | 641 | 46.903 GB | 93.152 s | 2,727.051 s | 68.806 s | 0.034x | 1.354x | 35.127 GB | 35.103 GB | 5.256 GB |
| MICS — release 117 | 494 | 1.634 GB | 14.708 s | 98.402 s | 0.567 s | 0.149x | 25.940x | 0.304 GB | 0.367 GB | 0.073 GB |
| MICS — release 118 | 455 | 2.056 GB | 14.633 s | 118.330 s | 0.588 s | 0.124x | 24.886x | 0.651 GB | 0.669 GB | 0.100 GB |
| MICS — all releases | 949 | 3.690 GB | 29.341 s | 216.732 s | 1.155 s | 0.135x | 25.403x | 0.651 GB | 0.669 GB | 0.100 GB |
| NSFG — release 105 | 4 | 0.005 GB | 0.083 s | 0.196 s | 0.028 s | 0.423x | 2.964x | 0.125 GB | 0.121 GB | 0.054 GB |
| NSFG — release 108 | 4 | 0.001 GB | 0.066 s | 0.097 s | 0.006 s | 0.680x | 11.000x | 0.106 GB | 0.104 GB | 0.030 GB |
| NSFG — release 110 | 7 | 0.015 GB | 0.164 s | 0.497 s | 0.106 s | 0.330x | 1.547x | 0.128 GB | 0.123 GB | 0.041 GB |
| NSFG — release 113 | 28 | 0.673 GB | 1.232 s | 7.389 s | 0.079 s | 0.167x | 15.595x | 0.525 GB | 0.543 GB | 0.435 GB |
| NSFG — release 114 | 44 | 1.171 GB | 4.819 s | 47.892 s | 0.156 s | 0.101x | 30.891x | 0.751 GB | 0.765 GB | 0.208 GB |
| NSFG — release 115 | 9 | 0.100 GB | 0.514 s | 3.512 s | 0.015 s | 0.146x | 34.267x | 0.392 GB | 0.414 GB | 0.068 GB |
| NSFG — release 117 | 69 | 2.180 GB | 7.565 s | 107.544 s | 0.288 s | 0.070x | 26.267x | 1.318 GB | 1.330 GB | 0.201 GB |
| NSFG — release 118 | 57 | 1.626 GB | 4.687 s | 67.461 s | 0.207 s | 0.069x | 22.643x | 2.460 GB | 2.470 GB | 0.375 GB |
| NSFG — all releases | 222 | 5.772 GB | 19.130 s | 234.588 s | 0.885 s | 0.082x | 21.616x | 2.460 GB | 2.470 GB | 0.435 GB |

Both ratio columns are dta-parser time divided by comparator time, the
reciprocals of the previously reported ratios. Values below 1x mean dta-parser
was faster; values above 1x mean the comparator was faster.

Stata's result is not a metadata-only or lazy `use`. The official
[`use` manual](https://www.stata.com/manuals/duse.pdf) says that `use` loads a
Stata-format dataset into memory, and the
[User's Guide](https://www.stata.com/manuals/u.pdf) says Stata works with a copy
of the data loaded into memory and stores data in memory. The measured RSS also
supports a real load: the 1 GB full synthetic file produced a 1.133 GB Stata
process, and the largest DHS read produced 5.256 GB. Stata's exact loader is
closed source, but its advantage plausibly comes from reading its native format
into compact native storage widths, plus mature implementation work and the
warm operating-system page cache. Dta-parser must additionally construct R
objects; in particular, its numeric result vectors use R's eight-byte doubles.
Matching Stata while returning ordinary R-compatible objects is therefore a
different engineering target, but the Stata time is still a valid eager-load
reference rather than an unattainable lazy-open measurement.

For the synthetic release-119 loads, dta-parser was 7.74--42.47 times as fast
as haven. The stored-release strata make the corpus spread explicit:
dta-parser was 2.36--31.18 times as fast as haven, while the all-release corpus
subtotals were 7.39--29.28 times as fast. Dta-parser was 3.48 times as fast as
Stata on the DHS release-111 stratum and took 0.929 times Stata's time on the
projected 1 GB synthetic workload; Stata was 1.55--34.27 times as fast on the
remaining corpus strata. At corpus level Stata was 1.35, 25.40, and 21.62 times
as fast as dta-parser on DHS, MICS, and NSFG. Dta-parser peak RSS was 2.7% lower
on MICS, 0.4% lower on NSFG, and 0.1% higher on the largest DHS file; Stata used
82.3--85.0% less peak RSS on those corpus maxima. On the 1 GB full synthetic
load, however, dta-parser used 26.0% less peak RSS than Stata. These are
workload- and machine-specific observations, not guarantees.

Compared with the archived dta-parser corpus run, the all-release refresh
reduced aggregate time from 297.669 to 93.152 seconds on DHS (68.7%), from
30.687 to 29.341 seconds on MICS (4.4%), and from 29.865 to 19.130 seconds on
NSFG (35.9%).

The corpus comparison is deliberately paired. Two MICS files were rejected by
all three readers. Nine additional files (two DHS and seven NSFG) were read with
matching dimensions by dta-parser and Stata but did not yield a comparable
haven result, so they are excluded from every aggregate rather than giving one
reader a different input set. Private paths and values are not published.

R elapsed time covers the reader call, while Stata elapsed time covers its
`use` command; application startup is excluded from both. Peak RSS comes from a
fresh process and includes the complete runtime. The archived synthetic
comparison alternated reader order after warmup; the current refresh reran only
dta-parser on the same generated files. Exact dta-parser collector identity
and sampled haven parity were checked for the archived comparison. The corpus
suite originally rotated reader order between files and retained only
successful, dimension-identical triples; the current refresh reran dta-parser
only for all recognized releases and verified status and dimensions against
that archive.

Compared with the old eager collector rebuilt under Rust 1.98.0, the new 1 GB
full-load median fell from 2.354 s to 0.911 s (61.3%) and dimensions-only peak
RSS fell from 2.184 GB to 0.834 GB (61.8%). Forcing every character vector with
`object.size()` still completes in 1.722 s versus 2.256 s for the eager
collector and uses 0.975 GB peak RSS versus haven's 1.313 GB. Thus the deferred
dictionary representation keeps its partial-access benefit without imposing
the earlier raw-deferral prototype's forcing cliff.

See the [synthetic benchmark report](../../benchmarks/large-scale/results-2026-08-24.md)
and [DHS/MICS/NSFG report](../../benchmarks/r-corpus-performance/results-2026-08-24.md)
for exact methodology, provenance, validation, and reproduction commands. The
benchmark harnesses and raw private outputs are report-only evidence, not CI
performance thresholds.

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
