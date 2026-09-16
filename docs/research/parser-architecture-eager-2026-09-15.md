# Bounded eager read completion

Design A, September 15, 2026. This proposal keeps `read_dta()` and `read_arrow()` as completed dataset reads. It changes temporary ownership and execution behind one private interface. It adds no runtime dependency or benchmark result.

## Recommendation and evidence

Start with Arrow decode-to-final-storage. Then test DTA scheduling independently. The first change removes an established interval of overlapping ownership; the second tests whether block coordination wastes time. Neither establishes how much of the remaining Stata gap it can close.

I inspected locally stored `b41d8f9d` using `git show`, including `file.rs`, `arrow/read.rs`, `lib.rs`, `arrow_ffi.rs`, and `init.c`. That reference includes compact-byte batching, adaptive workers and the local-source startup fix. Checkout `573e6366` is not the control. The latest retained India medians are 0.752 s DTA, 0.558 s verified Arrow, and 0.5015 s retained Stata. The [evidence note](parser-exploration-local-evidence-2026-09-15.md) explains the warm-cache cohorts and metadata qualification limits.

The [R exploration](parser-exploration-r-2026-09-15.md), [Python exploration](parser-exploration-python-2026-09-15.md), [Rust exploration](parser-exploration-rust-2026-09-15.md), and [Julia exploration](parser-exploration-julia-2026-09-15.md) support separating fetched bytes, decoded values and final ownership. Arrow's pandas converter illustrates why releasing a column does not release a shared allocation. Rust's typed decoders fill caller-provided output. data.table separates native parsing from R string creation. These mechanisms inform this proposal, without transferring their performance results. [Arrow conversion](https://arrow.apache.org/docs/python/pandas.html#memory-usage-and-zero-copy), [typed decoder](https://arrow.apache.org/rust/parquet/column/reader/decoder/trait.ColumnValueDecoder.html), [data.table adapter](https://raw.githubusercontent.com/Rdatatable/data.table/master/src/freadR.c).

## One caller interface

The module belongs at the native read-completion seam used by the two R bridges. Format decoders remain in the core crate. Public R arguments remain unchanged.

```rust
// Private design sketch, not existing declarations.
enum ReadSource<'a> {
    Dta(&'a mut DtaFile<File>),
    Arrow(&'a ArrowFileSnapshot),
}
struct EagerRequest {
    selection: NormalizedSelection, // source indices and row window
    semantics: ExistingReadSemantics, // storage, encoding, profile flags
    workers: ExistingWorkerPolicy,
    staging: StagingPolicy, // positive byte target; internal configuration
}
enum ReadFailure {
    Input(ExistingFormatError), Allocation, Interrupted, WorkerPanic,
}
fn complete_read(
    source: ReadSource<'_>, request: EagerRequest,
    r: &mut RReadContext, // main-thread token and protected-object ownership
) -> Result<CompletedFrame, ReadFailure>;
```

`RReadContext` and `CompletedFrame` are neither `Send` nor `Sync`. `CompletedFrame` owns a preserved R root until the existing C return protocol accepts it. Failure returns no table. Dropping it releases ownership on the R thread. The borrowed source stays open until all workers join; no source bytes or file handle become result backing.

A caller only normalizes its existing arguments and invokes completion:

```rust
let frame = complete_read(ReadSource::Arrow(snapshot), request, &mut r)?;
return frame.into_sexp_for_existing_c_return();
```

Internally, move-only states enforce `Prepared -> Allocated -> Filled -> Published`. A destination range has one writer, checked byte and row extents, and a storage-specific kernel. A checked chunk carries structural validation and the requested checksum-verification scope. Only the decoder constructs that evidence. Publication requires every selected range filled exactly once and all required validation complete, including zero-row and zero-column behavior.

Depth comes from hiding allocation, scheduling, verification, cancellation and finalization behind this interface. Locality puts their ownership rules in one module instead of duplicating them across two FFI entry points. It does not justify making the format decoders share parsing logic.

## Execution phases

### Prepare

Reuse the open source's metadata and resolve output order, lengths, field documents, Stata storage types and conversion kernels once. Keep schema descriptors as runtime values. Preserve projected-field validation and the broader scope required for stored signatures and profiled predicates under [ADR 0010](../adr/0010-promise-stability-for-frozen-arrow-profiles.md).

Arrow preparation cannot always use schema alone. `classify_read_column()` checks non-null `i32::MIN` before choosing ordinary integer versus double storage, and string nulls decide dictionary storage versus an eager character vector. A sliced batch's whole-batch null count is insufficient. Use a bounded classification prepass for ambiguous columns, retaining only decisions and verification facts about owned bytes. Released bytes need verification again when reread. Explicit R integer semantics must retain their existing error. Profiled numeric columns avoid this prepass. Recheck classification invariants during filling so an in-place source change cannot silently invalidate the destination choice. [Current classification](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/rust/src/arrow_ffi.rs#L2041).

### Allocate

The R thread creates and protects final numeric destinations, character-vector shells, output-container shell and shared label attributes. Null-free strings reserve final row IDs and grow the existing canonical `RStringData` dictionary during execution. These are result allocations, not queued decoded chunks.

Compact representation currently uses R `RAWSXP` backing. Transferring an arbitrary Arrow `Vec` into that backing would require another storage design. This proposal copies numeric chunks into the existing backing and moves completed native string dictionaries through the existing transfer protocol. [Current storage allocation](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/rust/src/lib.rs#L2622).

### Decode, verify and fill

For Arrow, admit tasks by estimated live bytes and conversion kind. Decode one selected field's complete touched IPC buffers, validate its layout, verify checksums before slicing, fill its assigned final range, then release its arrays. Group dictionary-dependent fields so the verified dictionary can be released after its last consumer. Preserve dictionary-delta and factor-level validation. Ordered string consumers append directly to their final dictionaries; nullable strings enter a byte-limited queue for the R thread to construct CHARSXPs.

This replaces `ArrowReadResult` containing all selected chunks followed by a second all-column filling phase. The current core already separates `PreparedRead` and `decode_planned_column()`, making the change possible without replacing IPC decoding. [Prepared state](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/dta-tools/src/arrow/read.rs#L1323), [decode and verify](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/dta-tools/src/arrow/read.rs#L1531), [current allocation/fill overlap](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/rust/src/arrow_ffi.rs#L3344).

Dispatch once per storage type, endian order and missing-value rule. Compare a contiguous copy plus missing-count reduction against a fused typed loop. Retain float NaN bits, tagged missing identity and temporal conversion. For DTA, extend bulk strided filling to `int`, `long`, `float` and eager doubles; byte batching already exists. Checksums and structural validation remain separate requirements even if an implementation eventually combines compatible passes.

DTA keeps persistent column owners and their ascending-row string dictionaries. Replace the all-worker acknowledgement barrier before each new dispatch with a byte-credit ring of shared observation blocks. Each owner advances independently through ordered blocks. The last consumer returns a block's credit; the coordinator reads only when credit exists. Faster owners can cross a block transition while a slower owner finishes preceding work. This changes coordination without task-local string dictionaries or a second string scan.

It still reads full rows and performs a strided gather. A larger live input set can hurt cache locality, so ring depth and block size require separate experiments. Keep current least-loaded column assignment: contiguous weighted groups already failed to improve the measured byte-batch path. Borrowed microtiles and positioned numeric row tasks are also existing experiments, not this proposal. [Current barrier](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/dta-tools/src/file.rs#L2245), [negative grouping result](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/benchmarks/dta-reader-performance/README.md#alternatives-measured).

### Publish

Join workers, reduce missing counts, finish string dictionaries, install metadata/classes, then expose the completed output container. Preserve Stata string missing, Stata string vector, compact representation, stored output container, name repair and supported mutation semantics as defined in [CONTEXT.md](../../CONTEXT.md). Existing deferred R string materialization remains; the proposal adds no deferred file decoding or validation.

## Memory and failure contracts

For the new executor, account for live memory as:

`final allocations + metadata/plans + max(staging target, indivisible working set) + runtime/allocator overhead`.

The staging ledger charges actual allocation capacities for observation blocks, compressed input, decoded buffers, dictionary dependencies, conversion scratch and pending string publication. Shared owners count once. Credit returns only when the last owner drops. Final string dictionaries include hash-table overhead and row IDs; their growth is unavoidable result storage and must remain visible in measurements.

A single IPC field may require a whole compressed buffer, decoded offsets and values, plus its dictionary. Dictionary delta concatenation can retain old, delta and new buffers simultaneously. These bytes determine the indivisible working set. If it exceeds the target, drain other tasks and admit that operation alone. Do not call this a hard RSS cap or reject previously valid files merely for exceeding the scheduling target. Preserve existing length checks, decompression limits and the 256 MiB partial-batch safety rule. Codec scratch and capacity growth require explicit accounting. [Current allocation checks](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/dta-tools/src/arrow/read.rs#L878).

DTA `strL` currently adds selected-row pointer vectors and GSO indexes. Initially retain that compatibility path and report its dependency memory separately. A fixed-scratch guarantee for all DTA inputs requires separate index partitioning work; the ring experiment must not conceal those allocations. Full India includes fixed strings and can exercise the ring without claiming `strL` coverage.

Only the R coordinator allocates R objects, polls R interrupts or invokes callbacks. Workers observe a cancellation flag between bounded kernels. Queue waits must let the coordinator poll; cancellation wakes blocked producers. Join workers before releasing destinations. Preserve DTA's earlier-block error precedence over later speculative reads, and established Arrow error/interrupt categories, rather than selecting whichever task wins a race.

Use the existing `R_ToplevelExec`-based allocation, attribute, string and interrupt wrappers so R nonlocal exits cannot cross live Rust ownership. Transfer flags prevent double-free when wrapping native dictionaries fails. Test failure at allocation, decode, checksum, CHARSXP construction and publication, including GC pressure and interrupted queue draining. An open descriptor preserves identity across pathname replacement, but is not an immutable snapshot against concurrent writes. Returned results own their storage. [C guards](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/init.c#L3087).

## Dependencies and qualification

Decoding, planning, codecs and checksums are in-process dependencies. Keep them concrete. Filesystem access is local-substitutable through existing `Read + Seek` readers: production `File`/`PositionedFile` and `Cursor<Vec<u8>>` fixtures are two actual adapters. Use real temporary files for short reads, replacement and truncation. The existing DTA sink seam has real `RDataFrameSink` and `VecSink` implementations. Add no generic plugin interface for the sole R host; qualify R behavior through real child processes.

Tests cross the completion interface for values, errors, missing codes and ownership. Existing lower-level decoder coverage remains useful while it covers distinct format behavior; avoid duplicating every internal scheduling step in tests.

## Ranked experiments and delivery order

1. **Arrow lifetime change.** First add phase timing and owned-capacity counters around `prepare_read`, `decode_planned_column`, `plan_read_column` and `run_column_fills`. Implement bounded numeric completion in `arrow/read.rs` and a private completion module beside `arrow_ffi.rs`. At fixed output size, increasing record-batch count must not increase simultaneously retained decoded bytes beyond the budget rule. Require lower native peak allocation and process RSS, with no elapsed regression beyond paired-run variability. Stop if an unexpected owner prevents release.
2. **Typed bulk fills.** Isolate Arrow copy/reduction variants in `fill_profiled_compact`, then extend `DtaColumnSink`/`RColumn` beyond `try_push_byte_rows`. Require reduced fill CPU and improved complete-read time on qualifying types. Reject extra memory passes that lose end-to-end. India is byte-heavy, so broader DTA kernels need mixed-storage controls before any India claim.
3. **DTA ring.** Change `ObservationBlock`, worker messages and acknowledgement/recycling logic in `file.rs`, holding adaptive worker policy constant. Measure queue wait, input occupancy and decode CPU. Compare fixed block size and separately fixed total staging bytes. Require less waiting and lower read time on skewed mixed schemas without a matched India/projection regression. Reject if a steady slow owner or cache pressure consumes the benefit.
4. **Broader Arrow coverage.** Add ambiguous-column preflight, dictionary lifetimes and nullable string publication. Require exact current storage choices and errors. Stop default rollout for affected classes if rereading or R-thread backpressure produces a repeatable regression; keep the existing completed-read path until resolved.

For every stage, bind source and installed-library identities to the same files and worker settings. Run timings sequentially. Report fresh-process warm-cache reads, repeated reads, CPU, peak/retained memory, full traversal, ordinary R consumers and first mutation. Qualify semantic read parity outside timings. Add cold/cache-constrained runs when that workload matters. No disabled verification, new format, public scan interface, immutable backing, Python/Julia runtime, or predicted speedup belongs in this experiment.
