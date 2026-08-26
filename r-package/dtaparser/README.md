# dtaparser

`dtaparser` reads Stata `.dta` files into R tibbles. Use it instead of `haven::read_dta()` for Stata imports. It accepts haven's common read arguments and returns the same R representations for labels, dates, and tagged missing values.

## Why use dtaparser?

Repository benchmarks compare `dtaparser` with haven across a large survey corpus and one especially wide file:

| Workload | dtaparser | haven | Difference |
| --- | ---: | ---: | ---: |
| 641 DHS files, 46.9 GB total | 93 seconds | 2,727 seconds | 17.6 times faster per file on average; 29.3 times faster for the complete batch |
| India 2021 DHS women, 5.2 GB and 5,972 columns | 1.9 seconds; 5.2 GB memory | 437 seconds; 35.1 GB memory | 230.5 times faster; about 30 GB less memory |

Across the full DHS, MICS, and NSFG comparison, `dtaparser` was faster on 1,803 of 1,812 files and tied on five. `haven` led on four files between 31 and 66 KB, each by 1 millisecond. `dtaparser` was faster on all 1,534 files larger than 1 MB.

These are warm-cache measurements from an Apple M4 Max, not performance guarantees. The multicore corpus refresh reused haven measurements made earlier on the same machine and files; the later India check likewise reran dtaparser only. See the [dated corpus report](https://github.com/jbearak/dta-parser/blob/main/benchmarks/r-corpus-performance/results-2026-08-24.md) for the full results and methodology.

`dtaparser` reads Stata files only. Keep using haven when you need to write `.dta` files or work with SAS and SPSS formats.

## Installation

Published GitHub Releases contain compiled packages for Windows x86_64, Linux x86_64, and macOS ARM64. Open the [latest release](https://github.com/jbearak/dta-parser/releases/latest), choose the asset matching the R version, operating system, and architecture, and copy its URL:

```r
pak::pkg_install("url::<asset-url>")
```

Base R can install the same URL after the package's imported dependencies are installed:

```r
install.packages("<asset-url>", repos = NULL)
```

Source installation requires Cargo and Rust 1.98.0 or newer:

```sh
git clone --depth 1 https://github.com/jbearak/dta-parser.git
R CMD INSTALL dta-parser/r-package/dtaparser
```

## Read a file

```r
library(dtaparser)

cars <- read_dta(
  "auto.dta",
  col_select = c(model = make, price, foreign),
  skip = 10,
  n_max = 20
)

cars
```

`file` accepts local paths, raw DTA bytes, binary connections, and URLs. Local gzip, bzip2, xz, and zip files are decompressed automatically; remote gzip is also supported. Applications should validate or allowlist untrusted URLs before passing them to `read_dta()`.

## Data returned to R

Dataset and variable labels, notes, display formats, and value-label tables are retained as attributes. Stata daily dates become `Date`; `%tc` and `%tC` values become UTC `POSIXct`.

System missing `.` becomes `NA_real_`. Extended `.a` through `.z` values use the tagged-NA payloads understood by haven:

```r
haven::na_tag(cars$foreign)
haven::is_tagged_na(cars$foreign, "a")
```

Stata byte, int, and long columns appear as R doubles so every missing tag can be represented. `dtaparser` keeps those columns at their smaller Stata widths until R needs a full double vector. R calls this mechanism ALTREP.

## Working with Stata data

`recode()` changes selected values without losing unmatched system or extended missing codes. It also preserves classes and Stata metadata for numeric, `haven_labelled`, `Date`, and `POSIXct` vectors.

`tab()` creates one-way and multidimensional frequency tables using Stata value labels. With `missing = TRUE`, it keeps `.`, `.a` through `.z`, and R `NaN` as separate categories when they occur:

```r
tab(cars$foreign, missing = TRUE)
```

The package also owns the common label getters and setters; `labelled` is not
required:

```r
var_label(cars$foreign)
var_label(cars$foreign) <- "Vehicle origin"

val_labels(cars$foreign)
val_labels(cars$foreign) <- c(Domestic = 0, Imported = 1)

dataset_label(cars) <- "Automobile data"
```

These setters retain compact numeric storage, Stata formats, temporal classes,
and unrelated attributes. See the
[R label metadata guide](../../docs/r-label-metadata.md) for bulk updates,
Stata 19 validation and portability limits, attach-order behavior, and the
version-specific comparison with `labelled` 2.16.0.

Use the installed help for exact behavior and examples:

```r
?read_dta  # inputs, selection, encoding, threads, compact vectors, labels, and missing values
?recode    # recoding without losing unmatched missing tags
?tab       # label-aware frequency tables
?var_label # dataset, variable, and value-label metadata
```

## Performance controls

`threads = 0` chooses an automatic worker count for sufficiently large reads; `threads = 1` forces serial decoding. `use_numeric_altrep = FALSE` disables the compact numeric representation and creates R double vectors during the read.

Additional measurements and their provenance live in the repository's [dated benchmark reports](https://github.com/jbearak/dta-parser/tree/main/benchmarks).

## Compatibility

The reader covers Stata 5 through 19. See the shared [compatibility contract](https://github.com/jbearak/dta-parser/blob/main/docs/compatibility.md) for exact format releases, encodings, missing-value behavior, and intentional differences from haven.

## Contributing

- [Contributing](https://github.com/jbearak/dta-parser/blob/main/CONTRIBUTING.md)

## License

GPL-3.0. See the repository's [LICENSE](https://github.com/jbearak/dta-parser/blob/main/LICENSE).
