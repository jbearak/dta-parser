# dtatools

`dtatools` reads Stata data quickly and brings Stata column types and
data-management tools to R. Create and recode variables, manage labels and
missing values, merge and append datasets, and save Stata or Arrow files.
Use the Arrow-based `.arrow` format for performance-sensitive workloads or
data frames that mix Stata and ordinary R column types.

The October 1, 2026 benchmark covered 1,879 readable survey files totaling
57.1 GB. Summed `read_dta()` call times were 31.792 seconds for tibbles and
37.323 seconds for dibbles, using a warm filesystem cache. A separate paired
comparison on the 5.2 GB India survey file recorded a 0.2265-second median
`read_arrow()` call for tibble output. See the
[benchmark results and methods](#why-use-dtatools) for CPU time, peak RSS and
timing boundaries.

Stata columns can live in ordinary data frames, tibbles, data.tables, or
dtatools' own table class, the dibble. They carry Stata storage types, labels,
display formats, and missing codes. A dibble extends a tibble and applies Stata
typing to supported numeric and character columns as you add them. Choose
their Stata storage explicitly, or use the defaults. Logicals and factors
can remain ordinary R columns.

Dibbles support base R and dplyr syntax, plus mutation by reference through
`:=` and helpers such as `gen()` and `repl()`.

## Installation

Requires R 4.6 or later.

Install from the [dtatools R package repository](https://jbearak.github.io/dta-parser/):

```r
install.packages("dtatools", repos = c(
  dtatools = "https://jbearak.github.io/dta-parser",
  CRAN = "https://cloud.r-project.org"
))
```

For manual installation, see [GitHub Releases](https://github.com/jbearak/dta-parser/releases/latest).
See [installation details](https://github.com/jbearak/dta-parser/blob/main/docs/r-package-repository.md)
for platform support and building from source.

Dplyr is optional. Install dplyr 1.2.1 or newer to use its verbs with dibbles.

Data.table is also optional. Dibbles support mutation by reference natively.
To use dtatools' storage types with data.table, install version 1.18.2.1 or newer.

## Dibbles, tibbles, and data tables

Readers return dibbles by default. A dibble is a tibble that preserves Stata
storage types and metadata as you work with the data. Use `dibble()` to create
one, `as_dibble()` to convert a data frame, and `is_dibble()` to check its type.
Use dplyr verbs and ordinary R table operations with dibbles.

Choose Stata storage when creating columns, or let the dibble assign it:

```r
library(dtatools)

survey <- dibble(
  age = dta_byte(c(20, 30)),
  weight = dta_double(c(0.8, 1.2)),
  eligible = c(TRUE, FALSE),
  group = factor(c("A", "B"))
)
```

The numeric columns carry their declared Stata types. `eligible` stays an R
logical and `group` stays an R factor. Automatic typing gives supported new numeric
columns the same Stata missing-value comparisons as imported columns. See
[column types and missing values](../../docs/r-dataset-behavior.md#column-types-and-missing-values)
for examples.

Choose a different container for one read or for the session:

```r
survey <- read_dta("survey.dta", output = "tibble")
options(dtatools.output = "data.table")
survey <- read_dta("survey.dta")
```

`save_arrow()` records the container, and `read_arrow()` restores it unless
you supply an `output` argument.

Helpers such as `gen()`, `repl()`, and `rename_vars()` update the supplied dibble
in place; a tibble, data frame, or data table is rejected until you assign
`data <- as_dibble(data)`. Use `copy_data()` when you need an independent copy.
Functions that add columns should return the updated dataset for their caller
to assign.

```r
order_vars(survey, region)
rename_vars(survey, age_years = v1)
reorder_dta_rows(survey, order(survey$id))
first_ten <- slice_dta_rows(survey, 1:10)
```

The [dataset behavior guide](../../docs/r-dataset-behavior.md) covers copying,
grouping and other advanced details. The
[container guide](../../docs/r-containers.md) compares supported operations,
and the [egen guide](../../docs/r-egen.md) explains grouped calculations.
See the separate [generation and mutation performance guide](https://github.com/jbearak/dta-parser/blob/main/docs/r-generation-mutation-performance.md)
for benchmarks of `gen()`, `replace_values()`, `:=`, and dibble `mutate()`.

## Why use dtatools?

The October 1 reader changes reduce repeated table and metadata construction.
In the paired synthetic comparison, tibble read wall time fell 29% to 73%
for DTA and 48% to 76% for Arrow, with lower read CPU time. Wide dibble reads
improved about 8% to 9%; most other dibble differences were inconclusive.
Wide tibble peak RSS fell about 14%. One single-thread read-plus-consumption
case used 2.5 MB more peak RSS, a 0.5% increase. Complete workflows often show
smaller gains than the read call alone.

The [reader comparison](../../benchmarks/r-file-readers/results-2026-10-01.md)
contains 1,728 observations, paired uncertainty intervals and resource costs.
It also measures base R, data.table, readr, vroom, haven, Arrow, fst and qs2.
The [reader survey](../../docs/research/r-file-reader-performance-2026-10-01.md)
explains their formats and metadata tradeoffs. These comparisons were completed
before the subsequent full-cache rerun below; Haven was not rerun for that work.

### Fast imports from existing Stata files

The October 1, 2026 benchmark covers every regular `.dta` file in the DHS,
MICS, NSFG, ENADID and WFS survey datasets under `/opt/aww_cache`: 1,881 files,
with both tibble and dibble outputs. All 1,879 readable files passed. The two
known malformed MICS files were attempted for both outputs and retained as exact, hash-checked
exclusions. Two directory symlinks alias files already counted and were not
followed.

The tables select the five survey datasets from the completed measurements
and sum one successful `read_dta()` call per file and output. GB means
1,000,000,000 bytes. CPU time sums work across cores.

| Corpus | Readable files | DTA GB | Tibble read wall | Dibble read wall |
| --- | ---: | ---: | ---: | ---: |
| DHS | 643 | 46.963 | 21.863 s | 25.644 s |
| MICS | 949 | 3.690 | 4.463 s | 5.288 s |
| NSFG | 229 | 5.777 | 4.812 s | 5.648 s |
| ENADID | 17 | 0.554 | 0.454 s | 0.500 s |
| WFS | 41 | 0.130 | 0.200 s | 0.243 s |
| Total | 1,879 | 57.114 | 31.792 s | 37.323 s |

| Output | Read CPU total | Process CPU total | Maximum individual peak RSS |
| --- | ---: | ---: | ---: |
| tibble | 83.446 s | 583.614 s | 5.257 GB |
| dibble | 89.014 s | 589.140 s | 5.254 GB |

Each attempt used a fresh R process, automatic threads and default numeric
ALTREP on a shared Apple M4 Max. Hashing each source immediately before its
two reads warmed the filesystem cache. There was no forced pre-read garbage
collection or compiled timing wrapper. These are summed read-call times,
not the elapsed time to execute the benchmark. Process CPU and peak RSS also
include startup, package loading, result checks and shutdown; peak RSS is the
largest individual process peak, not a sum over files.

Before timing, these survey files had 7,524 untimed reads comparing complete
value-and-metadata signatures, dimensions and warning/error behavior between
the baseline and optimized builds, separately for each container. The baseline
was used for correctness qualification only. These batch totals do not estimate a
before/after speedup.
The [full-cache report](../../benchmarks/reader-corpus/results-2026-10-01-full-cache/README.md)
records source `61954ee8`, all coverage and resource totals, background-load
samples, and input/build checks before and after timing.

#### Comparison with Haven and native Stata

The historical comparison below covers the same 1,812 files for all four
readers. The dtatools measurements are from September 16, 2026; Haven and
Stata measurements are retained from August 24 on the same files and computer.
These are warm-cache batch totals from one fresh-process read per file.

| Corpus | Files | DTA GB | `read_dta()` | `read_arrow()` | `haven::read_dta()` | Stata native `use` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| DHS | 641 | 46.903 | 38.684 s | 26.878 s | 2,727.051 s | 68.806 s |
| MICS | 949 | 3.690 | 6.575 s | 5.656 s | 216.732 s | 1.155 s |
| NSFG | 222 | 5.772 | 8.724 s | 6.602 s | 234.588 s | 0.885 s |

The dtatools rows use default dibble output and automatic thread selection
on an Apple M4 Max. Arrow files were preconverted; read times include checksum
verification and exclude conversion. The
[September 16 corpus report](../../benchmarks/reader-corpus/results-2026-09-16-base-r/README.md)
records CPU time, peak RSS, coverage and the original comparator sources.
Comparisons span measurement dates. The October 1 survey totals above use a
larger inventory and different instrumentation, so they remain a separate
series. No Haven, Stata or Arrow timing was rerun for that full-cache benchmark.

Projected reads load specified columns and can help when the needed variables
are known in advance. See [details and examples](../../docs/r-reader-projections.md).

### Performance on a demanding dataset

The October 1, 2026 refresh measures the 5.2 GB India 2021 DHS women's file,
with 724,115 rows and 5,972 columns. Each dtatools row uses ten new full reads,
in fresh R processes with a warm filesystem cache. Haven and Stata native
`use` values are retained unchanged from September 16 on the same file and
computer; neither comparator was rerun.

| Reader and output | Median read wall | Range | Median read CPU | Median process CPU | Median peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| `read_dta()`, tibble | 0.6280 s | 0.618–0.646 s | 4.8310 s | 5.1377 s | 5.250 GB |
| `read_dta()`, dibble | 0.6415 s | 0.631–0.682 s | 4.8575 s | 5.1698 s | 5.250 GB |
| `read_arrow()`, tibble | 0.2275 s | 0.224–0.230 s | 2.4180 s | 2.7540 s | 5.436 GB |
| `read_arrow()`, dibble | 0.2400 s | 0.238–0.244 s | 2.4160 s | 2.7497 s | 5.436 GB |
| `haven::read_dta()` | 472.9965 s | 422.801–572.189 s | n/a | 473.0478 s | 35.113 GB |
| Stata native `use` | 0.4725 s | 0.471–0.542 s | n/a | 0.5070 s | 5.257 GB |

CPU time sums work across cores. Read wall and read CPU cover the same first
reader call; process CPU and peak RSS include startup, loading, checks and
shutdown. The readers use automatic threads and numeric ALTREP. Arrow reads
verify checksums; conversion and qualification are outside timing. The four
DTA/Arrow and tibble/dibble combinations passed complete value-and-metadata
qualification before the timed reads.

This refresh follows the original India timing protocol, including jsonlite
job setup and no forced garbage collection or compiled timing wrapper. The
host is an Apple M4 Max with R 4.6.1. Current measurements use macOS 26.7;
the retained comparators used 26.6.2. The different measurement dates prevent
treating this as a newly paired comparison with Haven or Stata. The
[India refresh report](../../benchmarks/reader-parity/results-2026-10-01-india-refresh/README.md)
records every observation, source and input binding, historical comparator
source, and sampled host activity.

The separate paired optimization experiment found tibble read wall reductions
of 6.13% for DTA and 15.22% for Arrow on this file. Its CPU intervals include
zero, and most RSS differences are small and inconclusive. DTA dibble wall
time fell 0.92%; the automatic-thread Arrow dibble interval includes zero.
That experiment used eight reads and a different setup. The
[large-file results](../../benchmarks/r-file-readers/results-2026-10-01.md#large-input-controls)
retain its baseline, single-thread controls and uncertainty intervals.

The earlier [October 1 release comparison](../../benchmarks/io-merge-review/results-2026-10-01/README.md)
uses v0.10.0 as its baseline and a different measurement protocol. The
[reader CPU assessment](../../docs/research/r-reader-cpu-assessment-2026-10-01.md)
discusses thread scaling.

### Full-cache Stata conformance

The October 1 conformance suite covers all 1,881 regular `.dta` files in the
DHS, MICS, NSFG, ENADID and WFS survey datasets beneath `/opt/aww_cache`. All
1,879 readable inputs passed both direct DTA and Arrow-mediated round trips,
for 3,758 successful live-Stata comparisons.
The two known malformed MICS inputs were the only exclusions, each matched
by identity, byte count and SHA-256. No Haven reader or comparator was rerun.

For each input, the suite calls `read_dta()`, `save_dta()`, `save_arrow()` and
`read_arrow()`. Stata compares the original with the direct DTA output and
with a DTA written from the Arrow result. It checks every stored value,
dimensions, variable order and names, storage types, formats, dataset and
variable labels, value-label assignments and definitions, and dataset notes.

This oracle uses default dibble output. It does not check arbitrary dataset
or variable characteristics, including variable notes, or add projected reads
and synthetic release-119 cases. The
[full oracle report](../../benchmarks/r-corpus-roundtrip/results-2026-10-01.md)
records the corpus coverage, comparator controls, exact source build and
before/after input and executable audits. The full-cache reader qualification
separately compares baseline and optimized signatures within each container.

### Using `.arrow` dataset files

Call `save_dta()` to write a standalone Stata 18/19 dataset or `save_arrow()`
to write a standalone Arrow dataset. An Arrow dataset can mix Stata-specific
columns with supported ordinary R `logical`, `integer`, `double`, `character`,
`raw`, `factor`, `Date`, `POSIXct`, and `difftime` columns. See `?save_arrow`
for the preserved class details and metadata.

The files use Apache Arrow's column-oriented IPC format. dtatools adds
metadata for Stata and R semantics and a fingerprint for each data buffer.
`read_arrow()` checks those fingerprints by default to detect accidental
file corruption. Keep verification enabled for normal use.

The dtatools Arrow profile is experimental, version `"0"`, and does not yet
promise cross-version stability. Keep original source files when using it.

The [Arrow format report](../../benchmarks/arrow-interchange/results-2026-08-29.md)
records conversion costs, file sizes and interoperability details. Older warm
reader comparisons are retained in the
[balanced reader report](../../benchmarks/reader-refresh/results-2026-09-12-balanced/README.md).

### Synthetic merge benchmarks

`dta_merge()` implements Stata key identity, relationship checks, shared-variable
coalescing and the `_merge` indicator. In the August 28, 2026 synthetic benchmark,
a 200,000-row, 151-column master joins a 360,044-row, 110-column using dataset
on a character key. Both dtatools and Stata return 440,044 rows and 201 columns.

| Relationship | `dta_merge()` on Stata columns | Stata 18 MP `merge` |
| --- | ---: | ---: |
| `1:m` | 0.101 s | 0.257 s |
| `m:1` | 0.097 s | 0.329 s |

These compare default workflows with different timing boundaries: R starts
with both inputs loaded, while Stata's timer includes reading the using file.
Stata also sorts by the key; `dta_merge()` retains input order. The figures
therefore describe these workflows and do not isolate merge-engine speed.
They are warm-cache medians on the same Apple M4 Max, from nine R iterations
and seven Stata iterations. The
[merge report](../../benchmarks/r-merge-performance/results-2026-08-28.md)
contains the source version, correctness checks, allocation measurements,
dplyr and base R comparisons, and reproduction commands.

The [October 1 release comparison](https://github.com/jbearak/dta-parser/blob/main/benchmarks/io-merge-review/results-2026-10-01/README.md)
uses the same fixture schema but a different process and warmup protocol.
Typed-column merges were unchanged from v0.10.0, at about 0.355 seconds for
`1:m` and 0.382 seconds for `m:1`. Ordinary-R-column `m:1` rose from 0.109 to
0.132 seconds, a repeatable regression; ordinary `1:m` was unchanged. These
are release-to-release measurements, not a new comparison with Stata.

### Synthetic write benchmarks

In the August 29, 2026 comparison on a 1 GB synthetic Stata-class fixture,
`save_dta()` took 0.152 seconds, Stata `save` took 0.130 seconds, and
`haven::write_dta()` took 9.048 seconds.
These are medians from seven fresh-process runs on the same Apple M4 Max.
dtatools retained declared numeric storage; haven widened the 30 numeric
columns to double. The
[write report](../../benchmarks/large-scale/results-2026-08-28.md) and
[Arrow report](../../benchmarks/arrow-interchange/results-2026-08-29.md)
include the ordinary-R-column controls, Arrow comparisons, output sizes and
memory measurements.

In the [October 1 release comparison](https://github.com/jbearak/dta-parser/blob/main/benchmarks/io-merge-review/results-2026-10-01/README.md),
the 1 GB typed fixture showed no clear improvement over v0.10.0 for either
writer, at about 0.165 seconds for `save_dta()` and 0.246 for `save_arrow()`.
The ordinary-R-column controls showed a small `save_dta()` slowdown. The
historical Stata and haven comparisons above were not rerun.

Keep using haven when you need to write older DTA releases or work with SAS and
SPSS formats.

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
save_dta(cars, "cars.dta")
```

The writer targets Stata 18 or 19. With the default Stata 19 target, it also
supports wide datasets with more than 32,767 variables. It preserves declared numeric storage,
formats, temporal values, labels, tagged missing codes, long strings, numbered
notes, and arbitrary characteristics at dataset and variable scope. It writes
through a sibling temporary file so validation,
serialization, and interruption failures leave an existing destination intact.

Factors become value-labelled Stata `long` variables, character missing values
become empty strings, and unrepresentable numeric values become Stata system
missing. Each conversion category produces one warning per call. An
extensionless output path receives `.dta` with a warning.

## Merge datasets

```r
merged <- dta_merge(cars, "makes.dta", by = "make", relationship = "m:1")
```

`dta_merge()` applies Stata missing-code identity to both bare and typed numeric
keys. For bare double keys, dplyr equality joins with `na_matches = "na"` match
system missing `.` and extended missings `.a` through `.z` together. Homogeneous
dtatools numeric keys distinguish those codes through their typed equality
proxies. The bare-double behavior can create a many-to-many expansion; it
does not mean non-key missing payloads are discarded. Base `merge()` can also
drop the right key's labels and other metadata when it retains only the left
key column.

`dta_merge()` matches each of the 27 missing codes only to itself, requires
the relationship declaration (`"1:1"`, `"m:1"`, or `"1:m"`), coalesces key
storage types and labels, follows Stata's master-wins rule for overlapping
variables (with a warning naming them, where Stata is silent), and generates
the value-labelled `_merge` indicator. `keep` and
`assert` mirror Stata's options, and either input may be a `.dta` or `.arrow` file
path so only the merged result occupies memory; the
[input-source report](https://github.com/jbearak/dta-parser/blob/main/benchmarks/dta-merge/results-2026-08-29.md)
shows a from-file merge costs its read plus the merge itself. See
[the joins note](../../docs/r-joins-with-stata-columns.md) for the evidence
behind these differences.

One Stata behavior is intentionally excluded. Stata stores named value-label
definitions at dataset scope. If master and using contain different mappings
with the same definition name, Stata keeps master's definition and can display
the wrong labels on a using-only variable. `dta_merge()` keeps each variable's
resolved mapping instead. For example, if master uses `labels4` for interview
privacy and using assigns its own `labels4` month mapping to `bh4m`, Stata can
show privacy labels for the merged `bh4m`; `dta_merge()` keeps the month labels.
The latter is normally what the user intended. Stata's result can silently
misdirect later recodes that use label text. Correct accidental name collisions
in Stata source before comparing exact merge output. The
[label metadata guide](../../docs/r-label-metadata.md#compatibility-with-stata-merge)
explains the representation and writer behavior.

## Append datasets

```r
stacked <- dta_append(list(round1, "round2.dta", "round3.arrow"))
```

`dta_append()` stacks sources the way Stata's `append using ..., force` does.
The result holds the union of the sources' variables in first-appearance
order, a source that lacks a variable contributes that variable's missing
value for its own rows, string storage widens to the widest contributor, and
numeric storage promotes along Stata's lossless lattice. Variable labels,
formats, and variable-level notes come from the first source that contributes
the variable, and value-label tables are owned by table name, as in Stata.

Sources are taken as one list rather than a master and a using pair, so the
schema union is resolved in a single pass instead of reallocating the result
once per source. File sources are read in two passes — schema first, then
observations — so peak memory is roughly the result plus the largest single
source. A string/numeric conflict follows Stata's `force`: the first
contributor's type wins, the conflicting sources' rows hold missing, and a
message names them. `force = FALSE` makes that an error. Stata does not define
what `append` does with dataset-level notes and keeps the master's, so
`dataset_notes` defaults to `"first"`; `"all"` concatenates and `"none"` drops
them.

## Verify source data

```r
datasig("survey.dta")

loaded <- read_dta("survey.dta", datasig = TRUE)
attr(loaded, "datasig")
```

`datasig()` computes an order-sensitive content signature of a data frame or
a `.dta` or `.arrow` file, shaped `rows:columns:digest`. It covers variable names
and order, storage types, labels, display formats, notes, and every value in
row order, so it detects changes Stata's `datasignature` misses: values
swapped within a variable, reordered observations, and values exchanged
between same-type variables. A `.dta` file, a corresponding `.arrow` file at
any compression, and their loaded read models all sign identically, so a
signature recorded in a tracked table verifies a raw source file regardless
of container.

`datasig()` always recomputes from current content. Both readers accept
`datasig = TRUE` to also record the file's signature as a load-time
attribute: `read_arrow()` derives it from the stored footer checksums in
milliseconds, even under column projection, while `read_dta()` hashes the
decoded columns and requires a complete read. The signature shares the
experimental Arrow profile's stability caveat: recorded signatures may need
re-baselining until the profile freezes.

## Data returned to R

Dataset and variable labels, numbered notes, arbitrary characteristics,
display formats, and resolved value-label mappings are included as attributes. Use
`dta_notes()` and `dta_characteristics()` to inspect them, and pass a
column name as `variable` for variable scope. `dta_note()` and
`dta_characteristic()` read one entry; `set_dta_note()`, `add_dta_note()`,
`set_dta_characteristic()`, `drop_dta_notes()`, `drop_dta_characteristics()`,
and `renumber_dta_notes()` edit tables by reference and return them invisibly.
Vector forms return a copy that must be assigned. `set_var_format()` and
`set_var_formats()` edit display formats; `set_dta_metadata()` restores complete
metadata bundles, including a value-label mapping and its name. See the
[notes and characteristics guide](https://github.com/jbearak/dta-parser/blob/main/docs/stata-notes-and-characteristics.md)
for validation rules and Stata's numbering behavior. Stata daily dates become
`Date`; `%tc` and `%tC` values become UTC `POSIXct`.

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
dta_storage_type(cars$foreign)

status <- dta_byte(c(1, 2, NA_real_, tagged_missing("a")))
empty_status <- dta_byte(.size = 1000)
```

The five constructors are `dta_byte()`, `dta_int()`, `dta_long()`,
`dta_float()`, and `dta_double()`. They reject values that the requested
type cannot store and name a wider constructor in the error. Float construction
rounds values to binary32.

Subset assignment, `replace()`, `dplyr::if_else()`, and `dplyr::mutate()`
retain declared storage. Arithmetic widens only when its result values require
it. As in Stata, a missing operand makes the result system missing `.`
whatever its tag (`.a + 1`, `-.a`, `.a + .b`, and `sqrt(.a)` are all `.`);
only the rounding functions `round()`, `signif()`, `floor()`, `ceiling()`, and `trunc()`
return a tagged missing unchanged. Comparisons are unaffected. Base `ifelse()` strips the declaration because it takes attributes from the
condition; pass its result to a constructor to declare storage again. Encoding
materializes doubles temporarily, so the memory reduction is steady-state
rather than a reduction in peak memory during construction.

`recode()` changes selected values without losing unmatched system or extended missing codes. It also preserves classes and Stata metadata for numeric, `haven_labelled`, `Date`, and `POSIXct` vectors.

Character and factor recoding uses package-owned kernels. Character output does
not restore source labels or Stata string-width declarations; character-backed
Haven vectors now follow that rule without requiring Haven to be loaded or
recursing through the two recode interfaces. Character factor replacements retain
factor attributes and level order. Numeric recoding keeps its separate Stata
missing-value policy. See
`?recode` for default, missing and metadata-wrapper behavior.
Selected foreign S3 recode methods retain an optional public dplyr adapter;
the standard character, factor and numeric paths use the owned kernels.

With dplyr, `rows_patch()` follows the column's missing-value policy. A typed
Stata numeric destination keeps its system missing value, while an ordinary
tibble `NA` can be patched:

```r
if (requireNamespace("dplyr", quietly = TRUE)) {
    typed <- dibble(id = 1:3, x = c(10, NA, 30))
    ordinary <- tibble::tibble(id = 1:3, x = c(10, NA, 30))
    patch <- tibble::tibble(id = 2L, x = 99)
    as.double(dplyr::rows_patch(typed, patch, by = "id")$x) # 10 NA 30
    dplyr::rows_patch(ordinary, patch, by = "id")$x         # 10 99 30
}
```

Use explicit column names with base `cbind()`, such as `cbind(data, extra = x)`,
when the output name matters. An unnamed argument following a dibble can retain
a value-derived name from the existing base-binding adapter.

`tab()` creates Stata-style frequency and summary tables. It supports weights, group and row selection, subpopulations, association tests, cell percentages and contributions, sorting, keys, and plots. `tab1()` and `tab2()` create multiple tables; `tabi()` accepts a matrix of counts. With `missing = TRUE`, it keeps `.`, `.a` through `.z`, and R `NaN` as separate categories when they occur, and the empty string as the string missing:

```r
tab(cars, foreign, missing = TRUE)
tab(cars, rep78, foreign, row = TRUE, all = TRUE)
tab(cars, foreign, summarize = mpg)
tab(cars, rep78, weights = weight, weight = "aweight")
as.table(tab(cars, rep78))  # the plain frequency table
```

The [parity matrix](https://github.com/jbearak/dta-parser/blob/main/docs/r-tab-stata-parity.md) lists every `tabulate` form and option and how far each is matched.

The popular R package dplyr exports `dplyr::summarise()` and its alias
`dplyr::summarize()`. dtatools uses `summ()` for Stata's `summarize` command
to avoid those name conflicts.
Use `detail = TRUE` for percentiles, moments, and the four smallest and largest
values, or `meanonly = TRUE` for a silent result without variance calculations.

```r
summ(cars, price, mpg)
summ(cars, mpg, detail = TRUE, by = foreign)
result <- summ(cars, mpg, weights = weight, weight = "aweight")
result$r$mean                  # Stata's r(mean) for the last variable
as.data.frame(result)          # statistics for every variable and group
summ(cars, "i.rep78")          # proportions for each observed level
```

The interface supports analytic, frequency, and importance weights, `where`
and `rows` sample selection, factor interactions, and time-series operators
with `time` and optional `panel` column names. See `?summ` for the full
argument and return-value reference.
The [Stata comparison](https://github.com/jbearak/dta-parser/blob/main/docs/r-summarize-stata-parity.md)
lists equivalent calls and describes the native conformance fixtures.

`labelbook()` describes named value-label tables rather than observations.
An R data frame reports tables assigned to its current columns. A direct DTA
path reads the complete on-disk registry without decoding observations, so it
also reports unassigned tables. Use `.tables` for programmatic exact-name
selection. `order = "alpha"` maps to Stata's `alpha` option, and `list_limit`
maps to `list(#)` but chooses a deterministic prefix instead of a random sample.

`codebook()` describes variables and their observed data. Numeric variables
with at most nine unique nonmissing values are tabulated by default; variables
with more values receive summary statistics. Its result retains underlying
numeric codes, system and extended missing counts, notes, diagnostics, and
Stata-style missingness implications without requiring callers to parse the
printed report.

```r
labelbook(cars)
labelbook("survey.dta", .tables = c("yesno", "region"))

codebook(cars, foreign, mpg)
codebook(cars, mpg, where = foreign == 1, mv = TRUE)
```

`val_labels()` returns one variable's resolved mapping as a named Stata
numeric, so a tagged-missing code prints as `.a` and compares as Stata
compares it, while `labelbook()` groups mappings by their named table
assignments. `tab()` counts observed
values. Base `summary()` remains useful for ordinary R summaries, while
`codebook()` applies Stata's categorical threshold, missing-code rules,
metadata terminology, and problem checks. Multilingual value-label registries
are not yet represented and are never merged implicitly.

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
set_var_label(cars, foreign, "Vehicle origin")

val_labels(cars$foreign)
set_val_labels(cars, foreign, c(Domestic = 0, Imported = 1))

dataset_label(cars) <- "Automobile data"
```

These setters retain compact numeric storage, Stata formats, temporal classes,
and unrelated attributes. See the
[R label metadata guide](../../docs/r-label-metadata.md) for bulk updates,
Stata 19 validation and portability limits, attach-order behavior, and the
version-specific comparison with `labelled` 2.16.0.

Resolve a variable reference against the current column names with
`resolve_var_name()`. Exact names take priority over abbreviations, and an
abbreviation must match only one column:

```r
survey <- data.frame(identifier = 1:2, income = c(10, 20))

resolve_var_name(survey, "ident")
#> [1] "identifier"
resolve_var_name(survey, "missing")
#> [1] NA
```

Set `exact = TRUE` to disable abbreviation. Set `on_failure = "error"` when a
missing or ambiguous reference should stop execution.

`confirm_var()` checks the same kind of reference and returns `TRUE` when it
resolves. By default it throws an error when the reference is missing or
ambiguous, like Stata's uncaptured `confirm variable` command. Use
`on_failure = "false"` for a non-throwing check:

```r
confirm_var(survey, "inc")
#> [1] TRUE
confirm_var(survey, "missing", on_failure = "false")
#> [1] FALSE
```

### Generate and replace

`gen()` appends a variable and `repl()`
replaces selected values, both by reference. The target and its values are
one tagged pair, or the positional pair that reads like the Stata line.

```r
survey <- dibble(
  identifier = 1:3,
  id = c(2, 1, 2), region = c("west", "east", "west"), year = 2024L,
  income = c(10, 20, 30), eligible = c(TRUE, FALSE, TRUE)
)
gen(survey, adjusted = income + 5)
# Alternatively: gen(survey, adjusted, income + 5)
repl(survey, adjusted = 0, where = !eligible)
as.numeric(survey$adjusted)
#> [1] 15  0 35
```

Replacement preserves the input R double by default, widening storage for
range, integrality, or precision. Stata can round instead. For example:

```r
data <- dtatools::dibble(x = dtatools::dta_float(1))
dtatools::repl(data, x = 16777217)
dtatools::dta_storage_type(data$x)  # "double"
as.double(data$x)                  # 16777217
```

In Stata 18, `generate float x = 1` followed by `replace x = 16777217`
keeps `float` and stores 16777216.

| Input and replacement | Stata 18 | dtatools `promote = TRUE` | dtatools `promote = FALSE` |
| --- | --- | --- | --- |
| `float`, replace with 16777217 | `float`, 16777216 | `double`, 16777217 | `float`, 16777216 |
| `byte`, replace with 0.1 | `float`, rounded to float | `double`, exact input R double | Error |

`promote = FALSE` holds declared storage fixed. It allows float rounding but
rejects fractional or out-of-range values in integer storage. It is not a
general Stata-compatibility mode. Preserving an R double does not mean exact
decimal arithmetic; 0.1 is already a binary approximation.
See `?replace_values`, the
[intentional differences guide](https://github.com/jbearak/dta-parser/blob/main/docs/r-stata-divergences.md#numeric-replacement),
and [ADR 0024](https://github.com/jbearak/dta-parser/blob/main/docs/adr/0024-promote-in-replace-values-as-stata-does.md).
For identifiers, choose sufficient storage in Stata before assignment and
investigate disagreements before adding casts that reproduce rounding in R.

Stata's `by varlist:` prefix is the `by` argument. Groups are formed first,
then `where` and the values are evaluated on each group's rows, with `.n`
and `.N` as the within-group row number and count, so `bysort id: replace
last = _n == _N` becomes one line. `bysort` sorts the dataset by reference
on the listed columns, in Stata's total order for declared Stata columns
(finite values, then `.`, then `.a` through `.z`), and then groups by them;
`by` never sorts. A dibble grouped with `dplyr::group_by()` supplies its
groups the same way. Stata's parenthesized sort-only keys have no direct
equivalent: write `bysort id (date):` as `dplyr::arrange()` or
`reorder_dta_rows()` followed by `by = id`.

```r
gen(survey, last = .n == .N, bysort = id)
gen(survey, share = income / sum(income), by = c(region, year))
```

A dibble also accepts data.table's bracket form. `i` selects rows, `j`
holds one or more `:=` assignments, and `by` or `bysort` group. Unlike
`gen()` and `repl()`, `:=` creates a missing column and overwrites an
existing one; several assignments apply left to right, and rows are
selected once for the whole call.

```r
survey[income < 0, income := NA]
survey[, `:=`(adjusted = income + 5, flag = income > 0)]
survey[, last := .n == .N, bysort = id]
```

Only a dibble supports the bracket form. On a data table it runs
data.table's own `:=`, which ignores declared Stata storage.

Without `:=`, brackets return an independent selection. Compound row
expressions read columns first, with `.env` available for caller objects.
Read `.()` takes unnamed column names or strings in the requested order.

```r
survey[income > 20, .(id, income)]
cutoff <- 20
survey[income > .env$cutoff, .("income", id)]
rows <- c(3L, 1L)
cols <- c("income", "id")
survey[rows, cols]
```

A lone row-index name such as `rows` is read from the caller. Compound
predicates run once over the whole table, including grouped dibbles. Logical
`NA` produces a padded missing row; explicit `NULL` selects no rows. `.()`
selects zero columns and does not compute or rename columns. These reads work
without dplyr or data.table. Assignment keeps its existing shadow check and
dynamic target form `.(name) := value`.

### Programming with variable names

`gen()`, `repl()`, `replace_values()`, and `set_var_label()` capture their
variable-name argument the way Stata's `generate` and `replace` do, so the name
is normally written unquoted. When the name is only known at run time, unquote
it with rlang's `!!` operator or write `.(name)`. These functions capture with
`rlang::enquo()`, which already applies quasiquotation, so no `rlang::inject()`
wrapper is needed. Inside the `values` and `where` expressions, `.(name)` and
the `.data` pronoun both read a column whose name is a string. In the name
position, which names a target rather than reading a column, `!!name` and
`.(name)` work but `.data[[name]]` does not. `.(name)` is the one spelling that
works everywhere, and it may sit inside a larger expression.

```r
target_name <- "income"
source_name <- "identifier"

repl(survey, !!target_name, .data[[source_name]])
repl(survey, !!target_name, 0, where = is_missing(.data[[source_name]]))
gen(survey, !!paste0(target_name, "_flag"), .data[[source_name]] > 0)
set_var_label(survey, !!target_name, "Total income")

# `.(name)` is evaluated where it sits, in the caller's environment
repl(survey, .(target_name), .(source_name) + 1)

# `!!rlang::sym(name)` is the equivalent older spelling and still works
repl(survey, !!rlang::sym(target_name), 1)
```

Inside `values` and `where`, columns win over objects in the calling
environment. A bare symbol that is both a column and an object bound anywhere
from the calling frame up to the global environment is an error, because
either reading is defensible and the wrong one fails silently. Write
`.data$name` for the column or `.env$name` for the object:

```r
rows <- survey$income < 9000
repl(survey, income, 0, where = rows)        # error if `rows` is a column
repl(survey, income, 0, where = .env$rows)   # the local, unambiguously
```

Bindings in attached packages and base are not consulted, so a column named
`pi` or `T` is not flagged, and a function binding does not count, so a
recode script named after the column it builds is not flagged either. A
one-sided formula asks for the data mask outright, so `where = ~ rows`
reads the column without complaint.
`options(dtatools.shadow_check = FALSE)` turns the check off.

`set_var_labels()` and `set_val_labels()` update columns by name in `...`.
A column named at run time takes a `.(name) := value` tag there, or supply a
named list through `.labels`:

```r
set_var_labels(survey, .(target_name) := "Total income", identifier = "ID")
set_val_labels(survey, .(source_name) := c(low = 1, high = 2))
```

Use the installed help for exact behavior and examples:

```r
?read_dta  # inputs, selection, encoding, threads, compact vectors, labels, and missing values
?dibble    # the default container, its Stata-storage and closure invariants
?save_dta # standalone Stata 18/19 output, conversions, and metadata
?save_arrow # write a standalone .arrow dataset with supported Stata and R classes
?read_arrow # read a .arrow dataset and check it for file corruption
?dta_merge # Stata-identity merges with relationship checks and _merge
?dta_append # Stata-semantics stacking of data frames and files
?datasig   # order-sensitive data signatures for files and data frames
?dta_byte # construct and inspect declared Stata numeric storage
?recode    # recoding without losing unmatched missing tags
?tagged_missing    # create, inspect, and select extended missing values
?factor_from_labels # one-way conversion to an ordinary factor
?tab                # label-aware frequency tables
?var_label          # dataset, variable, and value-label metadata
?resolve_var_name    # resolve variable names and abbreviations
?confirm_var         # check variable names and abbreviations
?"dta-storage-defaults" # the Stata storage a dibble gives its columns
?order_vars          # move variables to the front by reference
?rename_vars         # rename variables by reference
?slice_dta_rows      # select rows through Stata storage
?reorder_dta_rows    # permute a table's rows in place
?dta_notes           # read and edit notes and characteristics
```

## Functions

| Function | Purpose |
| --- | --- |
| `dibble()`, `as_dibble()`, `is_dibble()` | Build, convert, or identify a tibble that preserves Stata storage and metadata. |
| `read_dta()` | Read a DTA file into a dibble, tibble, or data table with labels, display formats, notes, tagged missing values, and compact numeric columns. |
| `save_dta()` | Write a standalone Stata 18/19 dataset, preserving storage types, labels, notes, and missing codes. |
| `save_arrow()` | Write a standalone `.arrow` dataset, preserving supported Stata and ordinary R column classes and metadata. |
| `read_arrow()` | Read a `.arrow` dataset and check it for accidental file corruption by default. |
| `dta_merge()` | Merge two datasets, or `.dta`/`.arrow` files, with Stata `merge` semantics: distinct missing codes, a declared relationship, and a `_merge` indicator. |
| `dta_append()` | Stack data frames, `.dta`, and `.arrow` sources with Stata `append` semantics: the union of variables, missing values for absent ones, widening string storage, and lossless numeric promotion. |
| `dta_identical()` | Compare equal-length vectors in order using Stata value identity while ignoring storage, class, names, and metadata. |
| `dta_match()`, `dta_in()` | Match bare or Stata-backed values while keeping `.`, `.a` through `.z`, and finite values distinct. |
| `dta_union()`, `dta_intersect()`, `dta_setdiff()`, `dta_setequal()` | Apply Stata identity to stable set operations with symmetric bare-vector support and package-owned metadata handling. |
| `datasig()` | Order-sensitive content signature of a data frame or a `.dta` or `.arrow` file, for verifying that source data has not changed. |
| `recode()` | Change selected values while keeping unmatched system and extended missing codes. |
| `gen()` | Append a variable by reference from a data-mask expression or formula, optionally for selected rows. |
| `egen()` | Generate a column by reference from a selected calculation sample, with optional grouping. |
| `dta_mean()`, `dta_min()`, `dta_max()`, `dta_total()` | Calculate Stata summaries as ordinary functions usable in `gen()`, `egen()`, or `:=`. |
| `dta_row_max()`, `dta_row_total()`, `dta_group_id()`, `dta_group_tag()` | Calculate across columns, assign sorted group codes, or mark each group's first row. |
| `replace_values()`, `repl()` | Replace selected values by reference, preserving or widening Stata storage as needed. |
| `set_dta_values()` | Loop-friendly assigner: write into one column by name or position at given rows, by reference, without tidy evaluation, keeping the declared storage. |
| `keep_vars()`, `drop_vars()` | Keep or drop variables by reference, including variables created by `gen()`. |
| `order_vars()`, `rename_vars()` | Move variables to the front, or rename them, by reference, as Stata's `order` and `rename` do. |
| `slice_dta_rows()`, `reorder_dta_rows()` | Select rows into a new table, or permute a table's rows in place, gathering compact Stata columns in native code. |
| `resolve_var_name()`, `confirm_var()` | Resolve or check an exact variable name or unique abbreviation, with configurable failure behavior. |
| `copy_data()` | Make an independent copy of a dataset and its metadata. |
| `tab()` | Stata frequency and summary tables, weights, association tests, indicators, and stored results. `tab1()`, `tab2()`, and `tabi()` provide multiple and immediate forms. |
| `summ()` | Stata summary statistics, weights, detailed distributions, grouping, and factor/time-series varlists. |
| `labelbook()` | Structured reports on named value-label tables, assignments, mappings, and problems. |
| `codebook()` | Structured variable metadata, observed-data summaries, missingness relationships, and problems. |
| `factor_from_labels()` | Intentional one-way conversion of a labelled numeric variable to an ordinary R factor. |
| `dta_byte()`, `dta_int()`, `dta_long()`, `dta_float()`, `dta_double()` | Declare a vector's Stata storage type with validation; byte, int, long, and float use compact backing. |
| `dta_string()` | Construct an owned Stata string vector with validated fixed-width or `strL` storage and preserved variable metadata. |
| `dta_storage_type()` | Report a column's declared numeric or string storage type without materializing its compact backing. |
| `.a` through `.z`, `tagged_missing()`, `missing_tag()`, `is_tagged_missing()` | Create, extract, and select extended missing values. |
| `is_missing()`, `is_mi()` | Identify Stata missing values and empty strings. Both names perform the same check. |
| `dta_notes()`, `dta_note()`, `set_dta_note()`, `add_dta_note()`, `drop_dta_notes()`, `renumber_dta_notes()` | Read and edit numbered Stata notes at dataset or variable scope. |
| `dta_characteristics()`, `dta_characteristic()`, `set_dta_characteristic()`, `drop_dta_characteristics()` | Read and edit arbitrary Stata characteristics at dataset or variable scope. |
| `var_label()`, `val_labels()`, `dataset_label()`, `set_var_label()`, `set_var_labels()`, `set_val_labels()` | Get and set Stata label metadata without haven or `labelled`. |

Package-owned classes now use `dta_`, including `dta_numeric` and `dta_string`.
See the [naming migration](../../docs/dta-naming.md) for class checks and saved objects.

## Performance controls

Both readers default to `threads = getOption("dtatools.threads", 0L)`. Zero
chooses automatically from the CPUs available to the process. For compact DTA
reads, the policy also accounts for selected types and widths, rows per input
block and the row window. Narrow projections can use fewer workers; small
reads remain serial.

Set `threads = 1` for serial reading, pass another positive number to limit one
call, or set `options(dtatools.threads = 4L)` for the session. A per-call
argument overrides the option. `use_numeric_altrep = FALSE` disables compact
numeric storage and creates R double vectors during the read.

Additional measurements and their provenance live in the repository's [benchmark reports](https://github.com/jbearak/dta-parser/tree/main/benchmarks).

## Compatibility

The reader covers Stata 5 through 19. The writer targets Stata 18/19 and does
not emit older formats. See the shared [compatibility contract](https://github.com/jbearak/dta-parser/blob/main/docs/compatibility.md) for supported file formats, encodings, missing-value behavior, and intentional differences from haven.

`dtatools` takes Stata's behavior as its compatibility target.
[Where dtatools diverges from Stata](https://github.com/jbearak/dta-parser/blob/main/docs/r-stata-divergences.md)
explains differences such as `mutate(data, y = x)` copying labels as well as
values where `gen(data, y = x)` copies values only, numeric type promotion, and
merge result order.

## Contributing

- [Contributing](https://github.com/jbearak/dta-parser/blob/main/CONTRIBUTING.md)

## License

GPL-3.0. See the repository's [LICENSE](https://github.com/jbearak/dta-parser/blob/main/LICENSE).

## Acknowledgements

Dtatools builds on work by the R Core Team and the dplyr and vctrs authors.
See the [source and license notice](inst/NOTICE) and
[implementation credits](../../docs/r-implementation-credits.md) for attribution
and details of the adapted code.
