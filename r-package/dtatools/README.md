# dtatools

`dtatools` reads Stata `.dta` files into R tibbles and writes standalone Stata
18/19 datasets. Use it instead of `haven::read_dta()` for Stata imports. The
read interface accepts haven's common arguments and returns compatible values,
labels, dates, and tagged missing values. Numeric columns also retain their
declared Stata storage type.

## Functions

| Function | Purpose |
| --- | --- |
| `read_dta()` | Read a DTA file into a tibble with labels, display formats, notes, tagged missing values, and compact numeric columns. |
| `write_dta()` | Write a standalone Stata 18/19 dataset, preserving storage types, labels, notes, and missing codes. |
| `dta_merge()` | Merge two datasets, or DTA files, with Stata `merge` semantics: distinct missing codes, a declared relationship, and a `_merge` indicator. |
| `recode()` | Change selected values while keeping unmatched system and extended missing codes. |
| `tab()` | Label-aware frequency tables that can keep `.`, `.a` through `.z`, and `NaN` as separate categories. |
| `factor_from_labels()` | Intentional one-way conversion of a labelled numeric variable to an ordinary R factor. |
| `stata_byte()`, `stata_int()`, `stata_long()`, `stata_float()`, `stata_double()` | Declare a derived vector's Stata storage type, with validation and compact backing. |
| `stata_storage_type()` | Report a column's declared storage type without materializing its compact backing. |
| `tagged_missing()`, `missing_tag()`, `is_tagged_missing()` | Create, extract, and select extended missing values `.a` through `.z`. |
| `var_label()`, `val_labels()`, `dataset_label()`, `set_variable_labels()`, `set_value_labels()` | Get and set Stata label metadata without haven or `labelled`. |

## Why use dtatools?

Repository benchmarks compare `dtatools` with haven across a large survey corpus and one especially wide file:

| Workload | dtatools | haven | Difference |
| --- | ---: | ---: | ---: |
| 641 DHS files, 46.9 GB total | 93 seconds | 2,727 seconds | 17.6 times faster per file on average; 29.3 times faster for the complete batch |
| India 2021 DHS women, 5.2 GB and 5,972 columns | 1.9 seconds; 5.2 GB memory | 437 seconds; 35.1 GB memory | 230.5 times faster; about 30 GB less memory |

Across the full DHS, MICS, and NSFG comparison, `dtatools` was faster on 1,803 of 1,812 files and tied on five. `haven` led on four files between 31 and 66 KB, each by 1 millisecond. `dtatools` was faster on all 1,534 files larger than 1 MB.

These are warm-cache measurements from an Apple M4 Max, not performance guarantees. The multicore corpus refresh reused haven measurements made earlier on the same machine and files; the later India check likewise reran dtatools only. See the [dated corpus report](https://github.com/jbearak/dta-tools/blob/main/benchmarks/r-corpus-performance/results-2026-08-24.md) for the full results and methodology.

### Projected reads across surveys

Pipelines that process many surveys can pass the union of every raw variable
they use without first loading or special-casing each file:

```r
raw_variables <- c("caseid", "v005", "v012", "survey_specific_variable")
data <- read_dta(
  "survey.dta",
  col_select = tidyselect::any_of(raw_variables)
)
```

`any_of()` keeps requested variables that exist and silently omits those that
do not. `read_dta()` resolves the selection from DTA metadata before reading
observations, so it does not decode unselected columns.

A warm-cache benchmark selected 100 variables spread across the 5.2 GB,
5,972-column India 2021 DHS women's file. The `any_of()` union also contained
100 absent names:

| Method | Median read time |
| --- | ---: |
| `read_dta(any_of(union))` | 0.301 seconds |
| Stata direct projected `use` with known-present names | 0.482 seconds |
| Stata full `use`, inspect union, then `keep` | 0.552 seconds |

All methods returned the same 724,115-row, 100-column result. These are medians
from 11 runs on an Apple M4 Max. The direct Stata command is not union-safe;
Stata errors if its varlist contains an absent name. See the
[dated projection report](https://github.com/jbearak/dta-tools/blob/main/benchmarks/projection-introspection/results-2026-08-28.md)
for the synthetic comparisons, per-method bounds, and limitations.

### Synthetic write benchmarks

The primary synthetic benchmark gives dtatools the exact output from Stata's
first save of an in-memory fixture covering every numeric Stata storage type:

| Scale | dtatools | Stata | Comparison |
| --- | ---: | ---: | ---: |
| 100 MB | about 0.02 seconds | about 0.01 seconds | about 1.6 times Stata |
| 1 GB | about 0.15 seconds | about 0.13 seconds | about 1.2 times Stata |

The secondary benchmark gives dtatools and haven the same ordinary R data
frame, without Stata storage or labelling metadata:

| Scale | dtatools | haven | dtatools advantage |
| --- | ---: | ---: | ---: |
| 100 MB | 0.183 seconds | 0.439 seconds | 58.3% faster |
| 1 GB | 1.797 seconds | 4.052 seconds | 55.7% faster |

These are medians from seven fresh-process runs on the same Apple M4 Max, not
performance guarantees. See the [dated write report](https://github.com/jbearak/dta-tools/blob/main/benchmarks/large-scale/results-2026-08-28.md) for percentiles, memory and output sizes, source provenance, and the complete methodology.

### Synthetic merge benchmarks

The merge benchmark joins a 200,000-row, 151-column master to a 360,044-row,
110-column using dataset on a character key. Sixty non-key variables occur in
both inputs, and the result has 440,044 rows.

These are default-workflow timings, not identical output construction.

| Method | Input columns | 1:m median | m:1 median | 1:m allocated | m:1 allocated |
| --- | --- | ---: | ---: | ---: | ---: |
| `dta_merge()` | Stata classes | 0.101 s | 0.097 s | 0.61 GB | 0.62 GB |
| dplyr `full_join()` | Stata classes | 1.716 s | 1.411 s | 9.27 GB | 9.43 GB |
| base `merge()` | Stata classes | 5.125 s | 7.433 s | 23.26 GB | 31.23 GB |
| `dta_merge()` | Standard R | 0.107 s | 0.108 s | 0.66 GB | 0.79 GB |
| dplyr `full_join()` | Standard R | 0.115 s | 0.108 s | 0.74 GB | 0.76 GB |
| base `merge()` | Standard R | 1.576 s | 1.855 s | 2.06 GB | 2.06 GB |
| Stata 18 MP `merge` | Native DTA | 0.257 s | 0.329 s | Not measured | Not measured |

The Stata-class inputs come from `read_dta()`. The standard controls contain
the same values in base character, integer, and double columns. dplyr and base
R materialize intermediate values or reconstruct classed outputs, and their
wider results also increase allocation. They leave the compact source columns
untouched. `dta_merge()` and Stata coalesce the 60 shared variables and return
201 columns including `_merge`; dplyr and base R retain suffixed copies and
return 260 columns. Base R and Stata sort by the key; `dta_merge()` and dplyr
retain input order.

The R figures are `bench::mark()` medians on the same Apple M4 Max. Allocated
memory is cumulative R allocation, not peak RSS. The Stata median includes
reading the using file, while the R operation timers start with both inputs
loaded. These are not performance guarantees. See the
[dated merge report](https://github.com/jbearak/dta-tools/blob/main/benchmarks/r-merge-performance/results-2026-08-28.md)
for versions, iteration counts, correctness checks, and reproduction commands.

Keep using haven when you need to write older DTA releases or work with SAS and
SPSS formats.

## Installation

Published GitHub Releases contain compiled packages for Windows x86_64, Linux x86_64, and macOS ARM64. Open the [latest release](https://github.com/jbearak/dta-tools/releases/latest), choose the asset matching the R version, operating system, and architecture, and copy its URL:

```r
pak::pkg_install("url::<asset-url>")
```

Base R can install the same URL after the package's imported dependencies are installed:

```r
install.packages("<asset-url>", repos = NULL)
```

Source installation requires Cargo and Rust 1.98.0 or newer:

```sh
git clone --depth 1 https://github.com/jbearak/dta-tools.git
R CMD INSTALL dta-tools/r-package/dtatools
```

## Read a file

```r
library(dtatools)

cars <- read_dta(
  "auto.dta",
  col_select = c(model = make, price, foreign),
  skip = 10,
  n_max = 20
)

cars
```

An extensionless local path resolves to its `.dta` file:

```r
cars <- read_dta("auto") # reads auto.dta
```

`file` accepts local paths, raw DTA bytes, binary connections, and URLs. Local gzip, bzip2, xz, and zip files are decompressed automatically; remote gzip is also supported. Applications should validate or allowlist untrusted URLs before passing them to `read_dta()`.

## Write a file

```r
write_dta(cars, "cars.dta")
```

The writer targets Stata 18 or 19 and emits release 118 for ordinary datasets
or release 119 above 32,767 variables. It preserves declared numeric storage,
formats, temporal values, labels, tagged missing codes, long strings, and
dataset notes. It writes through a sibling temporary file so validation,
serialization, and interruption failures leave an existing destination intact.

Factors become value-labelled Stata `long` variables, character missing values
become empty strings, and unrepresentable numeric values become Stata system
missing. Each conversion category produces one warning per call. An
extensionless output path receives `.dta` with a warning.

## Merge datasets

```r
merged <- dta_merge(cars, "makes.dta", by = "make", relationship = "m:1")
```

Use `dta_merge()` instead of base `merge()` or a dplyr join when Stata key
identity matters. Both of those match keys with R missing semantics: system
missing `.` and extended missings `.a` through `.z` fall into one missing
bucket, so by default every missing key matches every other missing key. Rows
that Stata would keep apart match each other, sometimes into an accidental
many-to-many expansion, and the opt-outs (`incomparables`, `na_matches`) can
only stop missing keys from matching at all. This affects only the key columns
being matched; non-key columns pass through any of these joins with their
missing codes intact. Base `merge()` can additionally drop the right key's
labels and other metadata, since it keeps only the left key column.

`dta_merge()` matches each of the 27 missing codes only to itself, requires
the relationship declaration (`"1:1"`, `"m:1"`, or `"1:m"`), coalesces key
storage types and labels, follows Stata's master-wins rule for overlapping
variables (with a warning naming them, where Stata is silent), and generates
the value-labelled `_merge` indicator. `keep` and
`assert` mirror Stata's options, and either input may be a DTA file path so
only the merged result occupies memory. See
[the joins note](../../docs/r-joins-with-stata-columns.md) for the evidence
behind these differences.

## Data returned to R

Dataset and variable labels, notes, display formats, and value-label tables are retained as attributes. Stata daily dates become `Date`; `%tc` and `%tC` values become UTC `POSIXct`.

System missing `.` becomes `NA_real_`. Extended `.a` through `.z` values use the tagged-NA payloads understood by haven:

```r
missing_tag(cars$foreign)
is_tagged_missing(cars$foreign, "a")
cars$foreign[1] <- tagged_missing("f")
```

Stata byte, int, long, and float columns appear as R doubles so every missing tag can be represented. `dtatools` keeps those columns at their Stata widths until R needs a full double vector. The storage declaration remains on the column after materialization.

## Working with Stata data

Inspect storage without materializing a compact column, or declare storage for
a derived vector:

```r
stata_storage_type(cars$foreign)

status <- stata_byte(c(1, 2, NA_real_, tagged_missing("a")))
empty_status <- stata_byte(.size = 1000)
```

The five constructors are `stata_byte()`, `stata_int()`, `stata_long()`,
`stata_float()`, and `stata_double()`. They reject values that the requested
type cannot store and name a wider constructor in the error. Float construction
rounds values to binary32.

Subset assignment, `replace()`, `dplyr::if_else()`, and `dplyr::mutate()`
retain declared storage. Arithmetic widens only when its result values require
it. Base `ifelse()` strips the declaration because it takes attributes from the
condition; pass its result to a constructor to declare storage again. Encoding
materializes doubles temporarily, so the memory reduction is steady-state
rather than a reduction in peak memory during construction.

`recode()` changes selected values without losing unmatched system or extended missing codes. It also preserves classes and Stata metadata for numeric, `haven_labelled`, `Date`, and `POSIXct` vectors.

`tab()` creates one-way and multidimensional frequency tables using Stata value labels. With `missing = TRUE`, it keeps `.`, `.a` through `.z`, and R `NaN` as separate categories when they occur:

```r
tab(cars$foreign, missing = TRUE)
```

`factor_from_labels()` makes an ordinary R factor for modeling, plotting, or
data manipulation. It keeps distinct numeric codes distinct even when their
label text is the same. The default excludes missing values and retains unused
nonmissing value-label entries as levels:

```r
origin <- factor_from_labels(cars$foreign)
origin_with_missing <- factor_from_labels(cars$foreign, missing = TRUE)
```

This conversion is intentionally one-way. Both it and `tab()` read compact
numeric columns without first allocating their decoded double representation.

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
?write_dta # standalone Stata 18/19 output, conversions, and metadata
?dta_merge # Stata-identity merges with relationship checks and _merge
?stata_byte # construct and inspect declared Stata numeric storage
?recode    # recoding without losing unmatched missing tags
?tagged_missing    # create, inspect, and select extended missing values
?factor_from_labels # one-way conversion to an ordinary factor
?tab                # label-aware frequency tables
?var_label          # dataset, variable, and value-label metadata
```

## Performance controls

`threads = 0` chooses an automatic worker count for sufficiently large reads; `threads = 1` forces serial decoding. `use_numeric_altrep = FALSE` disables the compact numeric representation and creates R double vectors during the read.

Additional measurements and their provenance live in the repository's [dated benchmark reports](https://github.com/jbearak/dta-tools/tree/main/benchmarks).

## Compatibility

The reader covers Stata 5 through 19. The writer targets Stata 18/19 and does
not emit older formats. See the shared [compatibility contract](https://github.com/jbearak/dta-tools/blob/main/docs/compatibility.md) for exact format releases, encodings, missing-value behavior, and intentional differences from haven.

## Contributing

- [Contributing](https://github.com/jbearak/dta-tools/blob/main/CONTRIBUTING.md)

## License

GPL-3.0. See the repository's [LICENSE](https://github.com/jbearak/dta-tools/blob/main/LICENSE).
