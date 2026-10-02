# R reader performance limits

Research date: 2026-10-01. Repository source inspected at
`93cc80890032da4c6ef93e8beb4f5b6eb0175a29`. This note supplements the
[reader survey](r-file-reader-performance-2026-10-01.md) and
[CPU assessment](r-reader-cpu-assessment-2026-10-01.md). It adds source evidence
about R's representation costs. It does not report a new benchmark run.
External documentation describes the versions available when inspected;
development-branch details must be checked against installed benchmark versions.

## What the evidence establishes

The existing tenfold CPU gap does not establish a fundamental R limit.
The retained comparison already contains R readers that use less CPU than
dtatools on the same canonical values. For its numeric fixture, generic Arrow
used 7.5 ms of read CPU and qs2 used 9.5 ms, versus 26.5 ms for the DTA tibble
and 32.0 ms for the profiled Arrow tibble. Their complete-workflow CPU medians
were 47.0, 39.5, 77.5 and 80.0 ms respectively. These are descriptive
cross-format results on a shared desktop, with different representations,
compression and metadata contracts. They refute a universal tenfold penalty
for entering R; they do not establish how much of the particular Stata gap
can be removed. [Recorded comparison](../../benchmarks/r-file-readers/results-2026-10-01.md#numeric-fixture).

Stata `save` writes an existing in-memory dataset. The matching operation
for a read comparison is `use`, which loads one. Keep a measured `save`
result as a separate persistence control rather than labeling it a native
read. The earlier local CPU assessment compared `use` and read functions.
[Stata save reference](https://www.stata.com/manuals/dsave.pdf),
[Stata use reference](https://www.stata.com/manuals/duse.pdf),
[local matched read clocks](r-reader-cpu-assessment-2026-10-01.md#current-cpu-and-thread-scaling).

## Costs imposed by the requested R result

Ordinary R integer vectors contain 32-bit integers and double vectors contain
C doubles. Character vectors contain pointers to separate string objects.
R interns most strings through a global cache keyed by contents and encoding.
Consequently, building ordinary R strings involves interning and pointer
publication, even when file bytes already contain UTF-8 text. Repeated strings
can share their interned storage; high-distinct strings require more separate
objects. The representation rules establish required work, but not a fixed
CPU multiplier. [R Internals, vector data and string cache](https://cran.r-project.org/doc/manuals/r-release/R-ints.html#The-CHARSXP-cache).

R's C API belongs on the main thread. Many operations allocate, mutate R
state or signal errors. Native workers can decode independent buffers and
fill preallocated destinations under a valid ownership protocol, but moving
string creation and R attribute assignment onto arbitrary workers violates
that boundary. This limits parallelism in those phases; it does not require
binary parsing or decompression to run in the R interpreter.
[Writing R Extensions, R API](https://stat.ethz.ch/R-manual/R-devel/doc/manual/R-exts.html#The-R-API),
[OpenMP guidance](https://stat.ethz.ch/R-manual/R-devel/doc/manual/R-exts.html#OpenMP-support).

dtatools already avoids mandatory expansion of every compact numeric value.
Its compact representation stores Stata byte, int, long and float widths while
presenting doubles to R. Arrow compact columns retain immutable native
buffers. Dictionary strings defer creation of individual R strings until
access and cache each dictionary value. The first consumer still determines
how much expansion is needed. A full ordinary-double traversal and a
compact-aware aggregate therefore measure different work.
[Storage contract](../adr/0005-construct-compact-stata-numerics.md),
[retained numeric implementation](../../r-package/dtatools/src/rust/src/owned_numeric.rs),
[dictionary access and materialization](../../r-package/dtatools/src/dictstring.c),
[ownership contract](../adr/0033-share-owned-atomic-backing-and-storage-facts.md).

## What the fast readers actually do

| Reader | Mechanism supported by its source | Consequence for interpreting a faster result |
| --- | --- | --- |
| `data.table::fread()` | It samples distributed file locations through an on-demand memory map, allocates typed destination columns once and parses types directly. Out-of-sample type changes can force selected columns to be read again. [Reference](https://rdatatable.gitlab.io/data.table/reference/fread.html) | Supplied types and predictable schemas reduce planning and conversion work. Native typed loops can make text import fast despite CSV parsing. |
| `fst::read_fst()` | It combines type-specific filters, LZ4/ZSTD compression and background decompression with disk I/O. It supports row and column selection. [Project documentation](https://www.fstpackage.org/fst/) | Fewer disk bytes and overlap can lower wall time, while extra worker CPU remains a separate cost. Its published throughput uses in-memory table size, not physical bytes read. |
| `qs2::qs_read()` | The format uses R's serialization C API with different compression and I/O. The documented default is one compression/decompression thread; checksum validation defaults off. [Maintainer documentation](https://github.com/qsbase/qs2) | Existing R object types avoid schema inference. Compare file size, codec and integrity settings before attributing a CPU advantage to serialization alone. |
| `base::readRDS()` | It restores a serialized R object. Writer compression and serialization version determine part of the workload. [R reference](https://stat.ethz.ch/R-manual/R-devel/library/base/html/readRDS.html) | Uncompressed RDS is a useful native object-restoration control. It does not reproduce DTA parsing and Stata profile validation. |
| `arrow::read_feather()` | It defaults to memory mapping and returns a tibble unless asked for an Arrow Table. [R reference](https://arrow.apache.org/docs/r/reference/read_feather.html) | The return class alone does not establish that every column became an ordinary R allocation. |
| `arrow::read_parquet()` | It reads a columnar format with column selection and possible memory mapping. [R reference](https://arrow.apache.org/docs/r/reference/read_parquet.html) | Encoding, compression and row-group choices belong in the comparison. Parquet is an additional persistence format, not the same file as IPC. |
| `vroom::vroom()` | ALTREP can defer conversion; its documented environment defaults enable character ALTREP and disable numeric ALTREP. An explicit `altrep = TRUE` enables additional types. [ALTREP reference](https://vroom.tidyverse.org/reference/vroom_altrep.html), [project benchmark explanation](https://vroom.tidyverse.org/articles/benchmarks.html) | Measure first full consumption as well as return time and record the effective ALTREP settings. |

Arrow's conversion source tries an ALTREP result before allocating an ordinary
R vector. The fallback allocates a destination once and schedules chunk fills;
its string converter runs serially and calls `Rf_mkCharLenCE` for each value.
[Arrow converter source](https://raw.githubusercontent.com/apache/arrow/main/r/src/array_to_vector.cpp).

Arrow's primitive ALTREP can expose the underlying data pointer for a
single-chunk, null-free int32 or double column. Other cases can require
materialization. String ALTREP materialization allocates the R pointer vector
and converts values. The `arrow.use_altrep` option controls admission and
defaults to enabled in this source. Thus a generic Arrow tibble can achieve
low read CPU through both avoided copies and deferred conversion. It need
not pay all ordinary-R representation costs before returning.
[Arrow ALTREP source](https://raw.githubusercontent.com/apache/arrow/main/r/src/altrep.cpp).

## Boundaries for applying these lessons here

The current implementation already includes direct destination allocation,
typed DTA batch loops, compact Arrow retention and shared per-read attribute
values. Reimplementing those mechanisms would not be a new optimization.
Profile remaining repeated work before changing them. The DTA reader must
gather values from observations into separate columns; Arrow starts with
columnar arrays. That format difference is visible in the implementations,
whereas Stata's proprietary in-memory layout was not inspected.
[DTA batch implementation](../../r-package/dtatools/src/rust/src/lib.rs),
[Arrow column planning](../../r-package/dtatools/src/rust/src/arrow_ffi.rs),
[Arrow layout specification](https://arrow.apache.org/docs/format/Columnar.html).

The Arrow source supplies one concrete hypothesis for further measurement:
check whether dtatools creates avoidable ordinary numeric copies where the
representation is already compatible. Current `plan_read_column()` allocates
R vectors for profiled double paths, while compact paths retain native owners.
A changed representation must preserve mutation isolation, source lifetime,
missing values and the full-consumption endpoint. The source comparison alone
does not show that such a change will improve this package's workloads.
[Column plans](../../r-package/dtatools/src/rust/src/arrow_ffi.rs),
[owned backing requirements](../adr/0033-share-owned-atomic-backing-and-storage-facts.md).

Default profiled Arrow reads verify buffer checksums and restore Stata
semantics. Generic IPC readers have no obligation to implement that private
contract. Retain checksum verification in the primary before/after comparison;
use `verify = FALSE` only as a labeled diagnostic. Likewise, fewer workers can
lower CPU while increasing elapsed time. The earlier thread sweep demonstrates
that tradeoff, so a faster wall-time result alone does not answer the user's
compute question. [Arrow profile contract](../adr/0010-promise-stability-for-frozen-arrow-profiles.md),
[measured CPU scaling](r-reader-cpu-assessment-2026-10-01.md#current-cpu-and-thread-scaling).

The [follow-up measurements](../../benchmarks/r-file-readers/results-2026-10-02.md)
apply these lessons to two repeated costs: address-string creation during
dibble setup and native chunk lookup during scalar access to compact Arrow
values. The changes preserve the existing storage and metadata contracts.
That report includes native Stata `use` and `save`, separate read and
consumption endpoints, thread-count comparisons, and the rejected experiments.

The [compact-kernel measurements](../../benchmarks/reader-cpu-scaling/results-2026-10-02-compact-kernels.md)
subsequently test direct compact operations against ordinary doubles. Typed
missing-mask loops bypass per-value ALTREP access, and ordered sums move
invariant checks outside their inner loops. Across 42 preloaded-column cases,
compact missing predicates are faster, integer sums are within about 2%, and
float sums and the unchanged min/max paths are faster. Reductions use
`na.rm = TRUE`; public float-result rounding is preserved and qualified
separately from native numerical equality. These results support practical
parity for controlled bulk operations on the measured inputs, not a universal
claim about every R consumer or about file-loading time.
