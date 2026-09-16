# Arrow completion and native consumer experiments

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

The default `read()`, `read_with_source_row_count()`, and generic seekable-source reader remain unchanged. The completion interface is feature-gated. The writer changes below share an implementation with the existing public writer.

## Chunk sources for writing and signatures

The private `r-adapter-internal` interface adds `ArrowWriteSource`, `ArrowWriteSourceColumn`, and `ArrowWriteSourceDataset`. `ArrowWriteSource::try_new(chunks)` owns immutable array handles, validates each array's layout and values, checks type and aggregate length, and requires unchanged dictionary values across chunks. Empty columns supply at least one typed empty array. Its metadata accessors are `len()`, `is_empty()`, `data_type()`, and `null_count()`.

`ArrowWriteSource::from_array(array)` adapts ordinary arrays under the same valid-array precondition as the existing `ArrowWriteColumn`. It retains a handle and small source descriptors without copying the column or adding a full validation pass. This matters for ordinary R string and dictionary arrays already checked by their builders. The multichunk constructor's full validation is constant work per primitive numeric chunk without nulls; null bitmaps, strings, and dictionary keys require scans. The common writer does not repeat that full array validation.

`dataset_signature_from_sources`, `save_arrow_file_from_sources_with_preflight`, and `save_arrow_file_from_sources_to` use the same validation, metadata, checksum, and IPC writer implementation as the existing public functions. `ArrowWriteColumn` and `ArrowWriteDataset` remain unchanged. Their single-array adapter does not allocate source descriptors. Canonical record batches remain exactly 65,536 rows, independent of source chunk boundaries, and the data-signature payload is unchanged.

A canonical window contained within one chunk shares its value buffers. A crossing window concatenates only its selected rows. Non-byte-aligned validity or boolean buffers receive a bounded bitmap copy because the existing canonical checksum requires byte alignment. Dictionary windows concatenate keys without recoding or dropping levels. Batch hash workers retain at most one canonical column window each; dictionary-value hashing retains its existing whole-dictionary behavior. The IPC writer requires a complete record batch and can retain one such window per column, plus existing compression and encoding scratch. Variable-width windows have no fixed byte limit. There is no 64 MiB writer-memory claim.

The R bridge supplies retained native chunks for owned compact columns. Arrays backed by native Arrow buffers keep those buffers alive independently of R handles; the R-backed compatibility case copies before an array can outlive its C root. Modern compact values need no missing-code conversion. For legacy compact layouts, the bridge checks the entire logical column for observed values that collide with modern missing sentinels before normalizing any chunk. A conflict preserves every chunk's legacy layout and records release 111, matching the existing contiguous adapter. Otherwise it normalizes each chunk. This legacy conversion can allocate across the whole column before writing and is outside the canonical-window scratch bound.

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

`cargo test -p dta-tools --features r-adapter-internal arrow::write --lib` passed all 13 writer/source tests. The five added tests cover shared within-chunk buffers, bounded crossing copies, invalid sources and row counts, non-nullable profile rejection, interruption, bit-exact signatures and verified round trips across misaligned chunks, all ten supported missing-release documents, serial and parallel hashing, uncompressed/LZ4/zstd writing, checksum-free writing, unaligned null/boolean bitmaps, strings, unchanged dictionaries, and zero-row dictionary levels. Existing metadata preflight and footer-size tests also passed. `cargo check -p dta-tools` passed without the private adapter feature.

The core tests preserve raw missing layouts; the bridge's legacy normalization and callback/root behavior require the separate R integration tests. A read-only bridge audit found matching C/Rust descriptor layouts and independently rooted compact owners. Later callbacks can materialize a public vector while its private read handle continues to retain the original source.
