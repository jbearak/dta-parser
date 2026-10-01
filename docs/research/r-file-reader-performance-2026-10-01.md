# R file readers and performance mechanisms

Research date: 2026-10-01. Baseline source inspected at
`dced75ff5350e58c9f772fd0c9f9c07dc11f7929`, with the current candidate described
below. This survey uses the projects'
own documentation and source. Their published benchmark numbers are not
measurements of this checkout. Documentation on development branches can
describe behavior newer than the installed package; benchmark records must
include installed versions and effective settings.

This baseline already includes PR #276's eager-double DTA batch path,
bounded `u32` reduction for Arrow byte missing counts, and narrower namespace
profile setup. The earlier October 1 CPU assessment predates those changes.
Its proposed eager-double batch and startup work are historical leads,
not unimplemented opportunities in this checkout.
[Merged implementation and paired results](../../benchmarks/io-optimization/results-2026-10-01.md).

The most useful lessons for dtatools are to allocate the intended output once,
move type and bounds decisions outside value loops, avoid unnecessary input
and output copies, and size parallel work to the selected workload. Returning
before values have been consumed can reduce initial latency, but it is a
different result from reducing the complete read-and-use workload. Those
distinctions matter when comparing tibbles and dibbles, whose output container
does not by itself specify their column representation.
[Repository definitions](../../CONTEXT.md),
[earlier eager/deferred experiment](read-dta-construction-and-deferred-decoding.md).

## Core R and major packages

| Reader | Data and result | Performance mechanism and benchmark consequence |
| --- | --- | --- |
| `utils::read.table()`, `read.csv()`, `read.delim()` | Delimited text to a base data frame. CSV and TSV functions change defaults around `read.table()`. | Without `colClasses`, input columns first become character vectors and then undergo type conversion. Specifying atomic types and `nrows` reduces allocation; disabling comments helps when the input contract permits it. Include a tuned, explicitly typed base reader alongside defaults. [R reference](https://stat.ethz.ch/R-manual/R-devel/library/utils/html/read.table.html) |
| `base::scan()` | Text to an atomic vector or typed list. | `what` specifies column types and `NULL` skips fields. Known item counts avoid geometric buffer growth. Useful as a low-level text control, with table construction included if the required result is a table. [R reference](https://stat.ethz.ch/R-manual/R-devel/library/base/html/scan.html) |
| `base::readBin()` and `readChar()` | Binary primitives or character sequences. | Explicit sizes and byte order can avoid textual parsing. These do not decode DTA or Arrow metadata, so a raw-byte read is an I/O control, not a competing complete table reader. [R reference](https://stat.ethz.ch/R-manual/R-devel/library/base/html/readBin.html) |
| `base::readRDS()` and `load()` | Serialized R objects. `readRDS()` returns one object; `load()` restores named objects into an environment. | Useful R persistence controls that avoid rediscovering a table schema. Record writer version and compression, including an uncompressed RDS control. Do not assume that serialized external pointers restore live native ownership. [R reference](https://stat.ethz.ch/R-manual/R-devel/library/base/html/readRDS.html) |
| `data.table::fread()` | Delimited text to a data table or data frame. | Samples distributed rows through an on-demand memory map to infer types and allocate columns. Out-of-sample type changes can require rereading affected columns. It reads typed numeric columns directly, supports column selection, and exposes `nThread`. Measure both default inference and supplied schema. [Official reference](https://rdatatable.gitlab.io/data.table/reference/fread.html) |
| `readr::read_csv()` / `read_delim()` | Delimited text to a tibble. | The current implementation uses vroom for the second-edition parser. It exposes supplied column types, selection, thread count and `lazy`. The documented default is `lazy = FALSE`. Set it explicitly in an eager comparison. [Reference](https://readr.tidyverse.org/reference/read_delim.html), [implementation](https://github.com/tidyverse/readr/blob/main/R/read_delim.R) |
| `vroom::vroom()` | Delimited text to a tibble. | Can defer parsing through ALTREP and use threads for reading and materialization. Its documented environment defaults enable character ALTREP but disable numeric ALTREP. Record effective ALTREP types, not just the argument's printed default. Include `altrep = FALSE` and a separately labelled lazy workflow if measured. [Reader](https://vroom.tidyverse.org/reference/vroom.html), [ALTREP controls](https://vroom.tidyverse.org/reference/vroom_altrep.html) |
| `haven::read_dta()` | DTA to a tibble with supported Stata labels and dates. | Supports row windows and selected columns, making it the direct same-file R comparator. Its public read interface has no thread-count argument. Preserve tagged missing values and compare the common metadata contract explicitly. [Official reference](https://haven.tidyverse.org/reference/read_dta.html) |
| `foreign::read.dta()` and `readstata13::read.dta13()` | DTA to attributed data frames. | `foreign` is frozen at Stata 5–12 files. Both interfaces default to factor conversion, which changes the comparison unless controlled. `readstata13` supports row/column selection and an optional separate missing-code attribute. Keep legacy coverage separate from the modern DTA matrix. [foreign](https://stat.ethz.ch/R-manual/R-devel/library/foreign/html/read.dta.html), [readstata13](https://cran.r-project.org/web/packages/readstata13/refman/readstata13.html) |
| `arrow::read_feather()` / `read_ipc_file()` | Feather/Arrow IPC to a tibble by default, or an Arrow Table. | Columnar buffers, column selection and memory mapping are relevant to avoiding copies. `as_data_frame = FALSE` changes the required output and must not be ranked as a completed tibble read. A generic reader also does not apply dtatools' private Stata profile. [Official reference](https://arrow.apache.org/docs/r/reference/read_feather.html), [dtatools contract](../../r-package/dtatools/R/read-arrow.R) |
| `arrow::read_parquet()` | Parquet to a tibble or Arrow Table. | A columnar compressed persistence comparator with projection and optional memory mapping. Record writer compression, schema and row-group settings; a different file layout is part of the comparison. [Official reference](https://arrow.apache.org/docs/r/reference/read_parquet.html) |
| `fst::read_fst()` | fst storage for data frames. | Uses type-specific compression, background decompression and I/O overlap. Supports selected columns and row ranges. The lesson is bounded pipeline overlap, not that additional workers are free. Published fst throughput divides an in-memory size by time, so it must not be relabelled as disk bandwidth. [Project documentation](https://www.fstpackage.org/fst/) |
| `qs2::qs_read()` and `qd_read()` | General R serialization in qs2; data-only serialization in qdata. | qs2 combines R's serializer with compression and improved I/O. Its documented defaults are one thread and disabled checksum validation. qdata replaces unsupported internal types with `NULL`; current main temporarily disables requested string ALTREP. Qualify actual installed behavior and native-owner restoration. [Project documentation](https://github.com/qsbase/qs2) |

The original `qs` project now directs users to `qs2`; retain it as a separately
versioned legacy comparator only when that matters for deployed workflows.
[Maintainer notice](https://github.com/qsbase/qs).

Other major readers serve different input contracts. `readxl::read_excel()`
returns a tibble from XLS/XLSX and exposes sheet/range/type selection.
`jsonlite` reads JSON and supports streaming newline-delimited records. Their
document/container parsing work is useful for those applications, but neither
is a direct DTA or Arrow persistence baseline. Adding them to a single speed
ranking would mostly compare encodings. [readxl](https://readxl.tidyverse.org/reference/read_excel.html),
[jsonlite](https://cran.r-project.org/web/packages/jsonlite/vignettes/json-aaquickstart.html).

The implemented comparison covers base CSV and RDS, fread, readr, eager and
lazy vroom, haven, generic Feather, fst and qs2, alongside both dtatools
readers. It uses default CSV schema inference. Typed CSV, low-level R
readers, legacy DTA readers, Parquet, Excel and JSON remain survey coverage,
not measured methods. The benchmark README records the actual fixtures,
writer settings and available methods.
[Current comparison protocol](../../benchmarks/r-file-readers/README.md).

## Comparisons that answer different questions

Use a same-file matrix for parser improvements. Compare baseline and candidate
`dtatools::read_dta()` on identical DTA bytes, with haven as an external
reference. Compare baseline and candidate `read_arrow()` on identical IPC
bytes. Keep `verify = TRUE` as the primary profiled Arrow measurement. A
`verify = FALSE` control measures the cost of a changed integrity contract;
it is not evidence of an implementation improvement. Plain IPC has no
dtatools profile to verify. [Reader contract](../../r-package/dtatools/R/read-arrow.R).

Use a separately labelled persistence matrix to compare CSV, RDS, fst, qs2,
Parquet and IPC generated from one canonical table. Include file size,
compression and conversion settings. Before timing, qualify every round trip
against that table's values, missingness, row and column order, and required
classes. Text and general Arrow formats do not inherently preserve the full
dtatools Stata metadata contract. A practical common-denominator matrix should
therefore use ordinary integer/double/string columns; a separate semantic
matrix should exercise Stata storage, missing tags and metadata. This follows
the repository's distinction between semantic parity and identical internal
representation. [Domain model](../../CONTEXT.md).

Measure `output = "tibble"` and `output = "dibble"` explicitly for both
dtatools readers. Both can carry compact Stata columns; a tibble is not
automatically an eager-double control. In this comparison, external readers
return tibbles, including any needed conversion inside the timer. Native
tibble subclasses remain intact. A call that stops at an Arrow Table or a
data table does not satisfy that endpoint. External-reader-to-dibble
conversion is outside the measured matrix.
[Output and compact-column arguments](../../r-package/dtatools/R/read-arrow.R),
[container definition](../../CONTEXT.md).

For ALTREP readers, retain two endpoints: returned table and read plus first
full consumption. Consume all rows of every numeric and string column through
the same operations. The current worker casts numeric columns with
`as.double()` before summing and counting missing values, avoiding
class-specific aggregate rounding. It also visits every string's byte length.
The cast may allocate, so consumption RSS describes this ordinary-R traversal
and cannot stand in for every compact-aware aggregate. Run explicit eager
controls where the reader exposes them. Projected reads are a separate
workload when the application needs only a few known columns. The earlier owned,
deferred-numeric prototype returned sooner on some inputs but lost every
full-traversal comparison against direct eager construction. That is enough
reason to reject return time as the sole measure of success.
[Earlier qualification and complete workflow measurements](read-dta-construction-and-deferred-decoding.md).

## Wall time, CPU and memory protocol

Record elapsed time and process user plus system CPU over exactly the same
read interval. Their ratio estimates concurrent CPU consumption during that
interval; it is not a speedup or energy metric. Keep process-startup CPU and
elapsed measurements separate. R's `proc.time()` documents the distinction
between process CPU and elapsed time. [R clock reference](https://stat.ethz.ch/R-manual/R-devel/library/base/html/proc.time.html).

Measure whole-process peak RSS in fresh child processes with equivalent
setup. A peak includes package loading, allocations and touched mapped pages;
it is not retained table size. Repeated warm reads in one process can inherit
an earlier high-water mark, so they cannot supply independent per-read peaks.
R allocation traces are useful diagnostics but exclude native `malloc` and
`new` allocations, which matter for Rust, Arrow and compression libraries.
Do not substitute `bench::mark()`'s `mem_alloc` for peak RSS.
[bench memory definition](https://bench.r-lib.org/reference/mark.html),
[repository fresh-process protocol](../../benchmarks/reader-refresh/README.md).

Run one benchmark child at a time and pause compiles, tests and competing
readers. Alternate or balance method order, retain every observation and
report median plus spread. Warm filesystem cache, fresh R process, first
reader call and repeated reader call are distinct states. Record them rather
than calling all first-process reads cold. Perform fixture generation,
semantic qualification and profiling outside the clean measurement window.
The existing refresh driver already records installation/input identities and
separates read-call clocks from process CPU and RSS; reuse those safeguards.
[Driver method](../../benchmarks/reader-refresh/README.md).

Record actual library versions, hardware, OS, R version, thread limits and
effective parallelism. Compare both one-thread and package-default settings
for the high-performance readers. A fixed thread budget is useful as another
control, but equal requested limits do not prove equal active workers.
Earlier local evidence shows why resource reporting matters: the
October 1 India DTA automatic mode had lower wall time than eight requested
threads but higher aggregate CPU. Changing all workloads to that one file's
best count would be unjustified.
[Measured scaling and boundaries](r-reader-cpu-assessment-2026-10-01.md).

Use several shapes: tiny files dominated by setup, wide shallow tables,
large narrow tables, byte-heavy numeric data, double-heavy data, low- and
high-distinct strings, and mixed data. Add full reads, clustered/scattered
projections, row windows and first full consumption. Include compressed and
uncompressed Arrow fixtures when a change touches buffer handling. The
repository already has evidence that direct construction helps wide tables
more than high-distinct strL inputs, and that narrow projections prefer fewer
workers than a full India read.
[Construction evidence](read-dta-construction-and-deferred-decoding.md),
[projection scaling](../../benchmarks/dta-reader-performance/README.md).

## Implications for this optimization

The retained candidate reduces repeated construction work and widens the
use of bounded Arrow missing-count reductions. Those mechanisms do not
establish a speedup by themselves; paired acceptance measurements must do so.

1. Reduce repeated per-column or per-cell work before increasing thread
   counts. `fread`'s typed destination allocation and the previous DTA batch
   improvement support this direction. Current DTA already allocates compact
   destinations, batches eager doubles and compact numerics, and uses a
   bounded observation ring. The present candidate reuses immutable class,
   scalar metadata and symbol values during one reader result's construction.
   DTA and Arrow share this attribute path. It also retains the native tibble
   shell after name repair, avoiding another tibble construction pass. These
   changes must preserve attribute isolation, garbage-collection roots, name
   repair and all output-container semantics. DTA gather-loop experiments
   are excluded from the retained candidate.
   [Baseline batch result](../../benchmarks/io-optimization/results-2026-10-01.md),
   [DTA bridge](../../r-package/dtatools/src/rust/src/lib.rs),
   [container completion](../../r-package/dtatools/R/output-container.R).

2. Arrow's candidate uses `u32` partial sums for Int16, Int32 and Float32
   missing counts, extending the byte reduction already in the baseline.
   It preserves each classifier, including ordinary NaN handling for Float32,
   and widens each bounded partial sum into the full-column count. The scan
   retains its cancellation polls. Profile other time among buffer reads,
   decompression, validation, checksums, destination filling and final R
   attributes before changing those paths. The core verifies
   the complete touched array before row slicing. Any later buffer-sharing
   change must preserve immutable retained payload ownership and completion
   before publishing R objects.
   [Core decoder](../../r-package/dtatools/src/dta-tools/src/arrow/read.rs),
   [compact numeric preparation](../../r-package/dtatools/src/rust/src/owned_numeric.rs),
   [R bridge](../../r-package/dtatools/src/rust/src/arrow_ffi.rs),
   [completion ownership analysis](reader-parity-arrow-implementation.md).

3. For future work, borrow fst's overlap principle with measured memory limits. The existing
   DTA ring and Arrow task scheduling already overlap work. Increasing queue
   depth can increase transient RSS; smaller jobs can increase synchronization
   and CPU. Compare configurations under the same complete-work endpoint.
   An accounted scheduler target does not cap total RSS or codec workspace.
   [Existing reader architecture](r-reader-cpu-assessment-2026-10-01.md),
   [Arrow reservation limits](reader-parity-arrow-implementation.md).

4. Keep validation and source lifetime intact. Dropping checksums, reading
   only dimensions, deferring required errors or retaining mutable file
   mappings would change the task. Fix repeated work only after establishing
   which checks have identical inputs and which guard distinct contracts.
   Separate startup improvements from read-call gains. PR #276 already avoids
   two unused full profile constructions while preserving artifact validation;
   that work is outside an already-loaded reader's timer.
   [Qualified startup change](../../benchmarks/io-optimization/results-2026-10-01.md),
   [earlier contract analysis](r-reader-cpu-assessment-2026-10-01.md).

Accept a candidate on paired baseline/candidate measurements of the unchanged
public defaults, with both output containers and first-consumption checks.
Publish the signed wall/CPU/RSS deltas for every qualified workload, including
regressions. A faster return that merely moves parsing or expands memory after
the timer does not establish the requested improvement.
