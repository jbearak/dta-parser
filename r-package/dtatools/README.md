# dtatools

`dtatools` reads Stata `.dta` files into R dibbles, tibbles, or data tables
and writes standalone Stata 18/19 datasets. Use it instead of
`haven::read_dta()` for Stata imports. The read interface accepts haven's
common arguments and returns compatible values, labels, dates, and tagged
missing values. Numeric columns also retain their declared Stata storage type.

## Functions

| Function | Purpose |
| --- | --- |
| `dibble()`, `as_dibble()`, `is_dibble()` | Build, convert, or test a dibble: a tibble that is a Stata dataset, carrying reference state and Stata storage on every numeric and string column. |
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
| `replace_values()`, `repl()` | Replace selected values by reference without widening declared Stata storage. |
| `keep_vars()`, `drop_vars()` | Keep or drop variables by reference, including variables created by `gen()`. |
| `order_vars()`, `rename_vars()` | Move variables to the front, or rename them, by reference, as Stata's `order` and `rename` do. |
| `slice_dta_rows()`, `reorder_dta_rows()` | Select rows into a new table, or permute a table's rows in place, gathering compact Stata columns in native code. |
| `resolve_var_name()`, `confirm_var()` | Resolve or check an exact variable name or unique abbreviation, with configurable failure behavior. |
| `copy_data()` | Make an isolated copy, including compact column backing and mutable dataset metadata. |
| `tab()` | Label-aware frequency tables that can keep `.`, `.a` through `.z`, and `NaN` as separate categories. |
| `labelbook()` | Structured reports on named value-label tables, assignments, mappings, and problems. |
| `codebook()` | Structured variable metadata, observed-data summaries, missingness relationships, and problems. |
| `factor_from_labels()` | Intentional one-way conversion of a labelled numeric variable to an ordinary R factor. |
| `dta_byte()`, `dta_int()`, `dta_long()`, `dta_float()`, `dta_double()` | Declare a vector's Stata storage type with validation; byte, int, long, and float use compact backing. |
| `dta_string()` | Construct an owned Stata string vector with validated fixed-width or `strL` storage and preserved variable metadata. |
| `dta_storage_type()` | Report a column's declared numeric or string storage type without materializing its compact backing. |
| `.a` through `.z`, `tagged_missing()`, `missing_tag()`, `is_tagged_missing()` | Create, extract, and select extended missing values. |
| `is_missing()`, `is_mi()` | Classify Stata system and extended numeric missing values and empty strings; `is_mi()` is an alias for `is_missing()` that matches Stata's `mi()` shorthand. Use either in `where` expressions for `gen()` and `replace_values()`. |
| `dta_notes()`, `dta_note()`, `set_dta_note()`, `add_dta_note()`, `drop_dta_notes()`, `renumber_dta_notes()` | Read and edit numbered Stata notes at dataset or variable scope. |
| `dta_characteristics()`, `dta_characteristic()`, `set_dta_characteristic()`, `drop_dta_characteristics()` | Read and edit arbitrary Stata characteristics at dataset or variable scope. |
| `var_label()`, `val_labels()`, `dataset_label()`, `set_var_label()`, `set_var_labels()`, `set_val_labels()` | Get and set Stata label metadata without haven or `labelled`. |

Package-owned classes now use `dta_`, including `dta_numeric` and `dta_string`.
See the [naming migration](../../docs/dta-naming.md) for class checks and saved objects.

## Dibbles, tibbles, and data tables

Readers return dibbles by default: a dibble is a Stata dataset held in a
tibble. It carries dtatools reference state from creation, so `gen()` and the
other by-reference operations find it ready, and two invariants follow. Every
numeric and string column carries Stata storage: `dibble()`, `as_dibble()`,
and every operation that adds or changes a column give a bare column the
storage that `?"dta-storage-defaults"` maps its R type to. Logical columns
stay logical and factors stay factors. And every dataset operation on a dibble
returns a dibble: the dplyr verbs, joins and `bind_rows()` with a dibble first, base
`subset()`, `transform()`, `within()`, `head()`, `rbind()`, `cbind()`, and `[`
subsetting. Each result is a fresh object following copy-on-modify, so a
by-reference `:=` or `replace_values()` on the input or the result leaves the
other as it was; untouched columns are shared copy-on-write, so compact
columns stay compact. `tibble::as_tibble()` returns a tibble snapshot.

Ordinary `$<-`, `[[<-`, `[<-`, names, row-name, and nested attribute
replacement use R copy-and-rebind semantics. Existing aliases stay unchanged.
Converting a table with `as_dibble()` does not make function-local replacement
reach its caller. Return and assign the result, or use explicit helpers such as
`set_var_format(data, x, "%9.0g")`, `set_var_label()`, `set_dta_metadata()`,
`gen()`, and `repl()` when caller mutation is intended.

Prepare and assign before passing a table to a function that adds or drops
columns: `survey <- reserve_columns(survey, n = 10L)`. Explicit helpers preserve
the supplied table and fail before growth if its allocation is insufficient.
`column_capacity(survey)` reports total usable slots; `can_add_columns(survey, 10L)`
checks room for ten additions. Ordinary copies and base serialization can lose
capacity; `copy_data()` returns a prepared independent table. Data.table
support requires version 1.18.2.1 or newer; update an older installation before
using that container.

`dibble()` builds one like `tibble::tibble()`, `as_dibble()` converts a data
frame, tibble, or data table (a data table is copied, since a dibble cannot
share its self-reference), and `is_dibble()` tests for one. `as_dibble()` of a
grouped tibble keeps its grouping. Set one session-wide default container or
override it for one read:

```r
options(dtatools.output = "data.table")
survey <- read_dta("survey.dta")
survey_tbl <- read_dta("survey.dta", output = "tibble")
```

The data.table package remains optional. Requesting data-table output without
it installed is an error. Direct reader construction retains compact numeric
and dictionary-string columns; it does not build a tibble and convert it.

`save_arrow()` records whether its input is an ordinary dibble, tibble, or data
table. `read_arrow()` restores that container by default. An explicit `output`
argument overrides the stored choice. Older Arrow files and files saved from a
plain data frame use `dtatools.output`, then fall back to a dibble; a recorded
container this release does not know reads as a tibble.

Exported whole-table operations support ordinary data tables. `gen()` installs
a physical column, and `repl()` invalidates keys or secondary indexes that use
the changed column while preserving unrelated lookup state. Keys, indexes,
allocation capacity, and `.internal.selfref` are runtime state and are not
stored in Arrow files. Mutating and table-producing operations reject custom
data-table subclasses whose invariants dtatools cannot know.

`gen()`, `replace_values()`, `keep_vars()`, and `drop_vars()` mutate the supplied data frame or tibble. Dataset
aliases observe the change. Separate tables sharing a column remain isolated. Call `copy_data()`
first when the original dataset, its compact storage, and its metadata must
remain independent. See `?replace_values` for selection, evaluation, formula,
grouping, and Stata compatibility details, and
[mutation by reference](../../docs/r-mutation-by-reference.md) for what writing
by reference means and how it changes a workflow.
[Containers](../../docs/r-containers.md) tabulates what `gen()`, `repl()`,
`:=`, `mutate()`, and the replacement operators do on a dibble, tibble, data
frame, and data table, and the column types each produces.

The [egen guide](https://github.com/jbearak/dta-parser/blob/main/docs/r-egen.md)
compares `gen()`, `egen()`, and `:=` for all eight calculations. All three
can use the same value functions; `egen()` differs by calculating over the
selected sample when a row filter is supplied.

`order_vars()` and `rename_vars()` mutate by reference too, as Stata's `order`
and `rename` do: `order_vars()` moves the selected columns to the front and
leaves the rest in their existing relative order, and `rename_vars()` takes
`new_name = old_name` pairs, or a complete `.names` vector. Both leave the
column vectors, their storage declarations, and their metadata untouched, and
both reach columns created by `gen()`.

`slice_dta_rows()` returns the selected rows in the input's container, and
`reorder_dta_rows()` applies a permutation to a table in place, so every
reference to it sees the new order. Both gather compact Stata numeric columns
through the native kernel rather than dispatching `[` once per column, which
matters for wide data, and leave compact columns unmaterialized. For a data
table they drop the `sorted` marker and secondary indexes, which a row
selection or permutation invalidates.

```r
order_vars(survey, region)
rename_vars(survey, age_years = v1)
reorder_dta_rows(survey, order(survey$id))
first_ten <- slice_dta_rows(survey, 1:10)
```

For a dibble with at least ten rows, `slice_dta_rows(survey, 1:10)` and
`survey[1:10, ]` both return the first ten rows with all columns, preserving
Stata metadata and leaving `survey` unchanged. Brackets use ordinary tibble
subsetting; `slice_dta_rows()` batches compact Stata numeric columns in native
code to reduce per-column overhead. Use brackets for everyday subsetting;
consider `slice_dta_rows()` when slicing wide Stata datasets.

## Why use dtatools?

Repository benchmarks compare `dtatools` with haven across a large survey corpus and one especially wide file:

| Workload | dtatools | haven | Difference |
| --- | ---: | ---: | ---: |
| 641 DHS files, 46.9 GB total | 93 seconds | 2,727 seconds | 17.6 times faster per file on average; 29.3 times faster for the complete batch |
| India 2021 DHS women, 5.2 GB and 5,972 columns | 1.9 seconds; 5.2 GB memory | 437 seconds; 35.1 GB memory | 230.5 times faster; about 30 GB less memory |

Across the full DHS, MICS, and NSFG comparison, `dtatools` was faster on 1,803 of 1,812 files and tied on five. `haven` led on four files between 31 and 66 KB, each by 1 millisecond. `dtatools` was faster on all 1,534 files larger than 1 MB.

These are warm-cache measurements from an Apple M4 Max, not performance guarantees. The multicore corpus refresh reused haven measurements made earlier on the same machine and files; the later India check likewise reran dtatools only. See the [dated corpus report](https://github.com/jbearak/dta-parser/blob/main/benchmarks/r-corpus-performance/results-2026-08-24.md) for the full results and methodology.

### Using `.arrow` dataset files

Call `save_dta()` to write one `.dta` file or `save_arrow()` to write one
`.arrow` file. Each call writes only the selected format. A `.arrow` dataset
can mix Stata-specific columns with supported ordinary R `logical`, `integer`,
`double`, `character`, `raw`, `factor`, `Date`, `POSIXct`, and `difftime`
columns. dtatools preserves the class-specific details and profile metadata
documented by `save_arrow()`.

Apache Arrow stores tabular data by column in a standard binary layout. A
`.arrow` dataset uses Arrow's IPC (interprocess communication) file format to
exchange that data between programs. dtatools adds metadata for Stata and R
semantics plus a small fingerprint for each data buffer. `read_arrow()` checks
those fingerprints by default to detect accidental file corruption. The
dtatools profile is experimental (version `"0"`) and carries no cross-version
stability promise yet.

Warm-cache read medians on the same files:

| Input | `read_dta()` on `.dta` | `read_arrow()` on `.arrow` |
| --- | ---: | ---: |
| Synthetic 100 MB, 40 columns | 0.048 seconds | 0.028 seconds |
| Synthetic 1 GB, 40 columns | 0.184 seconds | 0.097 seconds |
| India 2021 DHS women, 5.2 GB, 5,972 columns | 1.608 seconds | 0.416 seconds |

Both readers decode with automatic multicore workers and defer numeric and
character materialization through ALTREP. `read_arrow()` is faster because the
`.arrow` file already stores each column contiguously in its Stata storage width,
so reading is mostly parallel column copies rather than row-major decoding.
Checksum verification is on by default and accounts for only a few percent;
converting the India file with `save_arrow()` took 1.4 seconds once. See the
[dated Arrow report](https://github.com/jbearak/dta-parser/blob/main/benchmarks/arrow-interchange/results-2026-08-29.md)
for conversion times, file sizes, and methodology.

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
[dated projection report](https://github.com/jbearak/dta-parser/blob/main/benchmarks/projection-introspection/results-2026-08-28.md)
for the synthetic comparisons, per-method bounds, and limitations.

### Synthetic write benchmarks

The primary synthetic benchmark gives dtatools and haven the exact output from
Stata's first save of an in-memory fixture covering every numeric Stata storage
type:

| Writer | 100 MB | 1 GB |
| --- | ---: | ---: |
| Stata `save` | 0.013 seconds | 0.130 seconds |
| `save_dta()` | 0.023 seconds | 0.152 seconds |
| `save_arrow()` | 0.037 seconds | 0.254 seconds |
| `save_arrow(checksums = FALSE)` | 0.031 seconds | 0.235 seconds |
| `haven::write_dta()` | 1.238 seconds | 9.048 seconds |

Haven took 53.8 times as long as dtatools at 100 MB and 59.5 times as long at
1 GB on these Stata-class inputs. dtatools took 1.77 times Stata's median at
100 MB and 1.17 times at 1 GB.
dtatools preserved the declared numeric storage types. Haven preserved values
and the metadata represented by its read model but widened all 30 numeric
columns to `double`. `save_arrow()` received the identical input but writes
Arrow IPC rather than DTA; it exports compact columns and dictionary strings
without copying or materializing them. Checksums cost only the step between
the two `save_arrow()` rows — the hashing runs on worker threads that overlap
the write — so the small remaining gap to `save_dta()` is mostly the larger
Arrow output.

The secondary benchmark gives dtatools and haven the same ordinary R data
frame, without Stata storage or labelling metadata:

| Writer | 100 MB | 1 GB |
| --- | ---: | ---: |
| `save_dta()` | 0.193 seconds | 1.927 seconds |
| `save_arrow()` | 0.105 seconds | 0.897 seconds |
| `haven::write_dta()` | 0.495 seconds | 4.195 seconds |

`save_dta()` was 61.0% faster than haven at 100 MB and 54.1% faster at 1 GB.
On ordinary R columns `save_arrow()` is the fastest writer of the three:
without Stata storage declarations there are no compact columns for the DTA
fast path to exploit, and the Arrow writer skips DTA-specific work such as
fixed-width string planning.

These are medians from seven fresh-process runs on the same Apple M4 Max, not
performance guarantees. The Stata median in the primary table is reused from
the [dated write report](https://github.com/jbearak/dta-parser/blob/main/benchmarks/large-scale/results-2026-08-28.md),
which also covers percentiles, memory and output sizes, and provenance for the
DTA writers; the refreshed R-writer medians and the `save_arrow()` rows come
from the
[dated Arrow report](https://github.com/jbearak/dta-parser/blob/main/benchmarks/arrow-interchange/results-2026-08-29.md).

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
[dated merge report](https://github.com/jbearak/dta-parser/blob/main/benchmarks/r-merge-performance/results-2026-08-28.md)
for versions, iteration counts, correctness checks, and reproduction commands.

Keep using haven when you need to write older DTA releases or work with SAS and
SPSS formats.

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
R CMD INSTALL dta-parser/r-package/dtatools
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
save_dta(cars, "cars.dta")
```

The writer targets Stata 18 or 19 and emits release 118 for ordinary datasets
or release 119 above 32,767 variables. It preserves declared numeric storage,
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
`assert` mirror Stata's options, and either input may be a `.dta` or `.arrow` file
path so only the merged result occupies memory; the
[dated input-source report](https://github.com/jbearak/dta-parser/blob/main/benchmarks/dta-merge/results-2026-08-29.md)
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
display formats, and resolved value-label mappings are retained as attributes. Use
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

`tab()` creates one-way and multidimensional frequency tables using Stata value labels. With `missing = TRUE`, it keeps `.`, `.a` through `.z`, and R `NaN` as separate categories when they occur:

```r
tab(cars$foreign, missing = TRUE)
```

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

`val_labels()` returns one variable's resolved mapping, while `labelbook()`
groups mappings by their named table assignments. `tab()` counts observed
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

`gen()` appends a variable and `repl()` (an alias of `replace_values()`)
replaces selected values, both by reference. The target and its values are
one tagged pair, or the positional pair that reads like the Stata line.
Assign `reserve_columns()` before adding columns to a data frame:

```r
survey <- reserve_columns(data.frame(
  identifier = 1:3,
  id = c(2, 1, 2), region = c("west", "east", "west"), year = 2024L,
  income = c(10, 20, 30), eligible = c(TRUE, FALSE, TRUE)
), n = 3L)
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
`by` never sorts. A tibble grouped with `dplyr::group_by()` supplies its
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
survey <- as_dibble(survey)
survey[income < 0, income := NA]
survey[, `:=`(adjusted = income + 5, flag = income > 0)]
survey[, last := .n == .N, bysort = id]
```

Only a dibble supports the bracket form. On a data table it runs
data.table's own `:=`, which ignores declared Stata storage.

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

## Performance controls

`threads = 0` chooses an automatic worker count for sufficiently large reads; `threads = 1` forces serial decoding. `use_numeric_altrep = FALSE` disables the compact numeric representation and creates R double vectors during the read.

Additional measurements and their provenance live in the repository's [dated benchmark reports](https://github.com/jbearak/dta-parser/tree/main/benchmarks).

## Compatibility

The reader covers Stata 5 through 19. The writer targets Stata 18/19 and does
not emit older formats. See the shared [compatibility contract](https://github.com/jbearak/dta-parser/blob/main/docs/compatibility.md) for exact format releases, encodings, missing-value behavior, and intentional differences from haven.

`dtatools` takes Stata's behavior as its compatibility target.
[Where dtatools diverges from Stata](https://github.com/jbearak/dta-parser/blob/main/docs/r-stata-divergences.md) lists
the places it deliberately does something else — the `generate` default's
reach, the promotion ladder, merge result order, colliding value-label table
names, `labelbook`'s deterministic listing, and the rest — and why.

## Contributing

- [Contributing](https://github.com/jbearak/dta-parser/blob/main/CONTRIBUTING.md)

## License

GPL-3.0. See the repository's [LICENSE](https://github.com/jbearak/dta-parser/blob/main/LICENSE).
