# Reader architecture review

September 15, 2026. Four explorer agents researched parser implementations in R, Python, Rust and Julia. Three architecture agents then developed alternative designs against their findings and this repository's reader contracts. This is research and design work, with no parser changes or new benchmark results.

The user requires optimization of both loading all columns and projected reads. Both are primary workloads. Survey analyses often consume only a few dozen columns, which informs downstream-use measurements even when the caller initially loads the whole dataset. I recommend a shared prepared read plan and bounded execution, with scheduling and allocation based on the requested selection. Full-load and projection gains must be reported separately.

## Primary workloads

The benchmark matrix must cover both readers and both selection modes. Loading all columns is an explicit supported use case; it does not depend on first determining the eventual analysis columns.

| Workload | Starting approach | Work to measure |
| --- | --- | --- |
| Load all columns | Use the existing reader with no `col_select`. | Reader return, CPU, peak/retained memory, subsequent analysis of a few dozen columns, and separately full-table traversal and mutation. |
| Project known columns, including a union across survey schemas | Use existing `col_select`; `all_of()` requires names and `any_of()` omits absent names. | Selection setup, selected payload reads, decoding, CPU, peak/retained memory and completed analysis of the selected columns. |
| Project columns chosen from metadata | Describe the source, choose columns and execute a projected read. Reuse matching prepared metadata where useful. | Description plus selection plus completed analysis, including repeated parsing. |

The first two rows are independent optimization targets. Metadata-based discovery is an additional projection scenario. Incremental acquisition can remain a separate experiment if useful, without replacing either primary reader workload. Full-load return times must state what work ALTREP leaves to later consumers.

Both existing readers support column projection. Arrow reads selected column buffers. The current DTA executor still reads complete observation-row blocks but decodes and allocates only the selected columns. This gives Arrow a physical advantage for column selection. It does not predict a linear speedup with fewer columns because metadata, dictionaries and touched-buffer verification still contribute. [DTA wrapper](../../r-package/dtatools/R/read-dta.R), [Arrow selection contract](../../r-package/dtatools/R/read-arrow.R).

For example, selecting 30 of 2,000 columns should avoid constructing the remaining 1,970. The existing readers can already do this when supplied the selection. An owned-column design addresses how the 30 chosen columns retain memory. A demand-loaded source additionally decides when each column is read. These are separate mechanisms and can be combined.

A new public row-filter or aggregate interface is not required for either full loads or column projections. The prior deferred DTA prototype underperformed on most sparse-use cases, every known-selection case and every full-traversal case. A new acquisition mechanism needs its own evidence across the applicable workloads. [Prior sparse-use results](read-dta-construction-and-deferred-decoding.md#deferred-numeric-timing-results).

## Evidence to use

The checkout is `573e6366`. A newer locally stored `origin/main`, `b41d8f9d`, contains compact-byte batching, adaptive worker selection and local-source startup fixes. Those changes belong in the control for any new experiment. We inspected that reference without switching branches or fetching remote changes. The [local evidence note](parser-exploration-local-evidence-2026-09-15.md) explains the revisions, implemented work and existing prototypes.

The latest locally retained India report measures candidate `8bb746b0` on the same 724,115-row, 5,972-column dataset. Its ten fresh-process reads use a warm filesystem cache and include first-call reader work. Native Stata observations are retained from the earlier four-tool comparison.

| Reader | Median read time | Median process peak RSS |
| --- | ---: | ---: |
| `read_dta()` | 0.7520 s | 5.231 GB |
| Verified `read_arrow()` | 0.5580 s | 10.275 GB |
| Stata native `use` | 0.5015 s | 5.256 GB |

Matching that Stata median would require about 33.3% less DTA time or 10.1% less Arrow time. These are arithmetic targets for the primary full-load workload, not predictions of a proposed change's gains. The Arrow file is a retained conversion with some metadata differences. Separate repeated warm-reader measurements do not establish a win over this Stata cohort. [Report and protocol](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/benchmarks/reader-startup/results-2026-09-13/README.md), [warm-reader qualifications](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/benchmarks/reader-refresh/results-2026-09-12-balanced/README.md).

The retained 100-column India projection supplies evidence for the other primary workload. It measured `read_dta()` at 0.235 s, against retained Stata projected `use` at 0.482 s and Stata load/inspect/keep at 0.552 s. These are warm projection measurements with their own protocol, separate from the full-import table above. The different ordering reinforces the need to optimize and compare both workloads individually. No new few-dozen-column or projected Arrow benchmark was run in this research. [Projection report](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/benchmarks/reader-refresh/results-2026-09-12-defaults/README.md#projection-and-thread-control).

## What the explorers found

| Ecosystem | Mechanism worth carrying forward | Limit that matters here |
| --- | --- | --- |
| [R](parser-exploration-r-2026-09-15.md) | Arrow can retain eligible native primitive buffers through ALTREP. fread separates native parsing from R string creation. | R strings and mutable columns can require conversion. vroom/readr experience shows retained files and deferred errors change the meaning of a completed read. |
| [Python](parser-exploration-python-2026-09-15.md) | PyArrow separates decoded tables from pandas conversion. Batch consumption and releasing converted inputs reduce overlapping ownership. | Compatible numeric types, nulls, chunk count and the requested destination determine whether copying is avoidable. |
| [Rust](parser-exploration-rust-2026-09-15.md) | Arrow-rs separates byte reads, decoder state and output batches. Polars chooses parallel work according to scan shape. | dtatools already has typed loops, selected IPC reads and parallel work. `Buffer::from(Vec<T>)` already transfers ownership without an extra payload copy. |
| [Julia](parser-exploration-julia-2026-09-15.md) | Tables makes producer-to-consumer ownership explicit. Arrow views and CSV task-local columns can avoid compulsory consolidation. | Mutable materialization is a separate cost. Some lazy Parquet column access repeats reads and allocations instead of caching them. |

The common lesson is to account for the destination representation and its ownership. Parquet's page decoding, statistics and row-group pruning solve problems specific to Parquet. DTA has row-major observations; IPC already stores column buffers. Neither benefits simply from copying a Parquet reader's tuning parameters. [Parquet layout](https://parquet.apache.org/docs/file-format/), [Arrow conversion constraints](https://arrow.apache.org/docs/python/pandas.html#memory-usage-and-zero-copy).

## Existing work changes the priority

Direct dibble construction, compact-byte batches, adaptive compact worker selection and the local-source startup shortcut have already been implemented in the newer reference. Numeric row tasks and borrowed microtiles also have local prototypes. The earlier owned-row deferred numeric experiment lost on every full-traversal/signature comparison against direct eager construction. These are controls or prior evidence, not new recommendations. [Evidence inventory](parser-exploration-local-evidence-2026-09-15.md#work-already-explored).

The remaining Arrow handoff is concrete. The core returns all selected decoded chunks; the R adapter then allocates all destinations, fills them and publishes columns while retaining the decoded result. This proves an interval of overlapping allocations. It does not prove how much of the observed time or RSS that interval explains. [Core result](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/dta-tools/src/arrow/read.rs#L89), [R read implementation](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/rust/src/arrow_ffi.rs#L3298).

## Architecture review

### A. Bounded eager execution

The [eager design](parser-architecture-eager-2026-09-15.md) keeps the existing reader result and compact storage. Prepare a read, allocate its final destinations on the R thread, then decode, verify and fill a limited amount of work at a time. Publish only after completion. The Arrow objective is to release temporary arrays after filling their destination ranges, instead of retaining the entire decoded table alongside all final columns.

This design must retain value-dependent output choices. Selected ordinary Int32 values can determine whether R needs doubles, and selected string nulls affect string construction. Some cases need a bounded classification pass or the existing path. A schema-only allocator would change behavior.

For DTA, the distinct candidate is a byte-limited queue across persistent column owners. It lets workers advance without the current all-worker acknowledgement barrier after each block, while retaining ascending per-column string construction. It is different from the existing numeric row-task and microtile prototypes. Wider numeric batch kernels are a separate experiment from scheduling.

### B. Owned native columns

The [owned-column design](parser-architecture-owned-2026-09-15.md) puts the seam at the in-memory column. It retains fully decoded, verified Arrow buffers as immutable owners. R captures receive independent handles. Region readers consume chunks, and the first supported mutation detaches into writable compact storage.

Start with one compatible profiled numeric chunk. Measure how many bytes qualify on actual files before extending to multiple chunks, ordinary Arrow classes or strings. This is a larger change because C and Rust currently assume a contiguous pointer into R-owned raw memory. ALTREP, summaries, comparisons, gathers, writers, serialization and mutation all need a consistent ownership interface.

The potential gain is removing the destination copy itself. The costs include first mutation, chunk traversal and native memory that R's heap accounting does not see. DTA already fills its compact destination directly, so there is no equivalent DTA copy saving to claim.

### C. Prepared sources and explicit scans

The [scan design](parser-architecture-scan-2026-09-15.md) puts the seam between a retained source and its consumers. A source can describe fields, prepare a request and execute into a completed table, owned batches or a scalar result. The plan records which operations it fully executed and which remain for the consumer.

Its smallest useful step is private plan reuse inside existing readers. Reuse metadata, selection and classification evidence only when their source and row-window scope match. The plan must support both all-column reads and projections without an extra discovery requirement on full loads. The design also explores filtering and counting, which require additional operation-order and partial-result rules if a consumer needs them.

This design addresses selective workflows. It cannot establish a faster full import by returning before that import has happened. It also must preserve union-safe selection, Stata missing-code identity and the broader validation required by metadata predicates.

### Comparison and recommendation

| Design | Seam and depth | Locality and cost | Best initial test |
| --- | --- | --- | --- |
| A. Bounded eager execution | One completion interface hides allocation, decode, verification, scheduling and publication. | Concentrates execution changes in the core readers and R bridges. Keeps existing column storage and its consumers. | Verified profiled numeric Arrow reads with bounded temporary arrays. |
| B. Owned native columns | A column interface hides buffers, chunks, typed regions and detachment. | Can concentrate ownership rules now spread across C and Rust, but only after all direct consumers use the new interface. | Eligibility and chunk inventory, then one compatible owned numeric chunk. |
| C. Prepared sources/scans | A source interface hides metadata, selection, execution and exact residual handling. | Shares planning across consumers, with additional lifetime and operation-order rules for public scans. | Reuse a private prepared plan inside existing eager readers. |

A's bounded execution and C's private prepared plan are complementary first candidates. Use the same completion module for all-column reads and projections. Resolve selection before allocation, then choose useful worker counts and bounded tasks from selected bytes, types and rows. Full loads need throughput; narrow projections also need low planning and coordination costs. Existing adaptive scheduling is part of the control.

For Arrow, measure bounded conversion on both all-column and projected reads. The large full-load allocation overlap is a direct reason to test it. Projections test whether task setup or classification prepasses outweigh the smaller conversion workload. Private metadata reuse should proceed when phase measurements establish repeated work, with no extra metadata pass added to the all-column path.

B can remove destination copying for compatible columns in either selection mode. It has the largest integration cost. Measure eligible bytes, chunk geometry and ordinary R materialization on both workloads. As designed, it completes decoding and verification of the requested selection before return: all columns for a full load, selected columns for a projection. Public incremental loading remains a separate decision.

I would order implementation experiments as follows:

1. Establish a matrix on the newer reference for both readers: all columns and projections of 10, 30 and 60 columns across narrow and wide survey schemas. Include known names, union-safe names and metadata-based discovery. Use realistic numeric/string mixes and clustered/scattered selections. Record reader return and downstream use separately.
2. Test bounded Arrow conversion and isolated typed fill kernels. Measure avoided live bytes and conversion work for full loads, plus planning/task overhead on projections. Preserve current verification, classification and output behavior in both modes.
3. Remove repeated metadata/selection work where profiling establishes it. Reuse one private plan through completion, including the all-column case. Require fewer repeated parses without expanding the consumed-metadata scope or adding a new full-load prepass.
4. Test DTA coordination and wider numeric kernels on both workloads, holding the existing adaptive worker policy constant. Compare block size and total staging budget separately. Full-load and projection timing/CPU/memory results must each remain visible.
5. Evaluate owned-buffer adoption from the remaining measured copy costs. Qualify both selection modes, sparse downstream use after a full load, traversal of all requested columns, and first mutation. Additional public scan or incremental-acquisition work needs its own benefit beyond these readers.

Do not spend the next experiment simply adding more workers, disabling verification, replacing IPC with Parquet, repeating contiguous column grouping, or restoring the rejected lazy DTA default. The research identifies more specific mechanisms and the evidence needed to reject them.

## What an experiment must establish

Start with the newer reference's reader code and the existing same-file benchmark workers. Reproduce a matched control before changing one mechanism. Retain the observed input, library and worker identities, and run timed work without other builds or benchmarks competing for the machine.

Measure the work that each design claims to remove:

- Planning, verification, decoding, destination filling and R publication time.
- Bytes read, copied and allocated, including peak live temporary native buffers.
- Read-call wall time, process CPU and peak RSS, plus memory retained after GC.
- For a full load: reader return, analysis of a few dozen columns, then separate full-table traversal and mutation cases. For a projection: reader return, completed analysis of the selected columns and mutation. These distinguish eager work from deferred R materialization.

Every performance report must include separate DTA/full, DTA/projected, Arrow/full and Arrow/projected results. Track improvement goals for both workloads; neither is merely a regression control. A targeted change may help one more than the other, but a combined average must not hide a material regression. Record tradeoffs explicitly and use the matched controls to judge run variability.

Qualify selected values, storage types, system and extended missings, strings, temporal values, metadata, output containers and malformed-input behavior outside the timed interval. Include projection order, empty selections, row windows, null-bearing Arrow arrays, chunk boundaries, strings, source replacement, interrupts, serialization and mutation isolation where the mechanism changes them. Keep Arrow verification enabled.

A smaller staging queue does not imply a fixed whole-process memory cap. Final columns, persistent dictionaries, R overhead and indivisible encoded buffers need separate accounting. Reject or narrow a candidate if it merely moves copying after the reader clock, increases common full-use time, repeats metadata work, or changes supported semantics. Set acceptable timing variation from the matched control rather than inventing a universal millisecond threshold.

## Deliverables

- Explorer reports: [R](parser-exploration-r-2026-09-15.md), [Python](parser-exploration-python-2026-09-15.md), [Rust](parser-exploration-rust-2026-09-15.md), [Julia](parser-exploration-julia-2026-09-15.md).
- Architecture proposals: [bounded eager execution](parser-architecture-eager-2026-09-15.md), [owned native columns](parser-architecture-owned-2026-09-15.md), [prepared sources and scans](parser-architecture-scan-2026-09-15.md).
- [Shared local evidence and constraints](parser-exploration-local-evidence-2026-09-15.md).

Primary sources and inspected-version limits are recorded in each explorer report. Some upstream documentation and source links are mutable and should be pinned before depending on an exact implementation. No new speedup, semantic qualification, or cold-cache result is claimed by this review.
