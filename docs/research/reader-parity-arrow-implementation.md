# Bounded Arrow completion experiment

Implemented September 15, 2026, in the isolated reader-parity worktree. This note describes the core experiment. It makes no performance claim and does not change the default core reader.

## Interface and ownership

The `r-adapter-internal` feature adds `ArrowFileSnapshot::prepare_completion(options, count_source_rows, interrupt)`. Preparation uses the same footer, profile, dictionaries, row-window planning, output-size checks, and dictionary verification as the existing reader. It retains a cloned descriptor of the already opened file, using positioned reads. It does not reopen the pathname during execution.

The returned completion provides:

- `metadata()` for inspecting output descriptors and exact selected row counts before allocation.
- `read(interrupt)` for continuing through the established retained-chunk implementation when output classification depends on values. This uses the preparation already performed.
- `into_parts()` to transfer an owned `ArrowReadResult` containing metadata and an independent decoder to the R adapter.
- `complete(byte_budget, interrupt, fill)` on that decoder to decode and fill final storage.
- `complete_with_report(...)` to return capacity/reservation telemetry after successful completion, without changing the existing `complete(...)` result type.

Dataset and selected field documents move into the metadata result. The decoder retains the version and checksum information it needs. Duplicate projected fields receive separate output descriptors, preserving the existing selected-field ownership rules. Empty dictionary arrays remain available for zero-row factors.

The fill closure receives an output column index, a checked row offset within the selected output, and one owned `ArrayRef`. It can run concurrently for disjoint column/row ranges. It must avoid R calls and release the array before returning. The adapter must allocate and protect destinations first, complete every worker before finalization, and discard unpublished destinations on failure.

Metadata with no chunks is not evidence of null absence or ordinary Int32 compatibility with R integers. An adapter must restrict the experiment to classifications established without scanning values, or use the prepared retained-chunk fallback. No output classes are inferred from empty chunks in the core.

## Scheduling target

The R experiment uses a 64 MiB accounted scheduling target. A task is one selected column from one overlapping record batch. Its reservation starts with encoded plus declared decoded buffer bytes, using the existing checked IPC allocation estimator. Uncompressed storage counts once. Compressed storage receives additional capacity headroom because `read_to_end` can retain capacity beyond its logical length. Full buffers count even when the requested row window selects only a few rows.

Reservations also cover possible bitmap/offset checksum copies and known codec scratch. For lz4_flex 0.14, the conservative allowance covers its maximum supported block buffers and linked-history window. For zstd 0.13, it covers the input `BufReader` capacity returned by `DCtx::in_size()`. This zstd reader does not expose its allocated native context/window size. Compressed capacity headroom is an estimate, not a proved upper bound on all codec allocations.

Admission includes the capacities of retained dictionary buffers, explicit 8 KiB worker readers, and the task vector as a fixed resident cost. Persistent workers reserve additional task bytes and release them after decode, verification, and fill. An indivisible task that cannot fit alongside the resident cost runs alone. If dictionaries already exceed the target, every task runs alone; preparation is not retroactively bounded. The core does not retain completed observation chunks.

The report returns target bytes, dictionary capacities, reader capacities, task-vector capacity, peak accounted bytes, oversized-task count, and the largest observed decoded chunk capacity. It flags compressed capacity estimates and unmeasured zstd workspace separately. Dictionary children count once in resident memory rather than again in each observed chunk. Metadata, final destinations, allocation rounding, thread stacks, and zstd native context/window memory remain outside the guarantee. A successful report establishes the scheduler's reservations, not a 64 MiB RSS or total-native-memory cap. Measuring preparation peaks and codec allocator peaks would require additional instrumentation or a different decoder interface.

The coordinator polls interruption while waiting for workers. Errors cancel further task admission and join all workers before returning. A reservation guard releases accounted bytes and cancels the queue during a worker panic. Separate panic guards also cancel panics outside a reservation, such as a coordinator interrupt callback. Callback errors propagate rather than publishing partially filled output. Native allocation failure that aborts the process is outside recoverable Rust panic handling.

## Validation

Every task calls the existing `decode_planned_column`. Layout checks and required checksums apply to the full touched array before slicing and invoking the fill closure. Projection indexes, row offsets, source row counts, profile selection scope, and stored signatures retain the existing preparation rules. The source must remain unmodified while reading; a retained descriptor protects against pathname replacement, not concurrent in-place edits.

The metadata-move audit confirms that `decode_planned_column` reads only the retained profile version and checksums. Array validation uses footer field types/nullability, layouts, and retained dictionaries. It does not inspect moved dataset or field documents. The prepared fallback returns those documents from the separate metadata result.

The default `read()`, `read_with_source_row_count()`, and generic seekable-source reader remain unchanged. New code is confined to the feature-gated completion path and its tests.

## Checks completed

`cargo test -p dta-tools --features r-adapter-internal arrow::read::tests --lib` passed 25 tests after the scheduler audit. Seven added completion tests cover:

- Uncompressed, LZ4, and zstd data across a batch boundary, with reordered and duplicate projection, metadata/signature parity, and retained-read fallback.
- Oversized tasks running alone, zero-row selections, and zero-column row counts.
- Corruption outside selected rows failing verification before the fill callback.
- Interruption, callback-error propagation, worker completion, and reuse through the fallback reader.
- Opened-file identity surviving pathname replacement on Unix.
- A worker callback panic while it holds the only oversized reservation, with a five-second timeout to detect a coordinator deadlock.
- Dictionary-capacity accounting, observed decoded capacities, dictionary fallback parity, and zero-row dictionary values surviving the metadata move.

The first test run rejected an invalid fixture that omitted the required sentinel-encoding declaration. Correcting that fixture produced the passing results above. R runtime qualification and matched completed-workflow measurements belong to the integration stage.
