# Experimental retained numeric columns

Date: 2026-09-15. This records the implemented prototype and its correctness checks. Reader timing results belong in the parity experiment report; these changes do not establish a performance improvement.

## Scope and activation

`DTATOOLS_EXPERIMENT_ARROW_OWNED=1` enables retained storage for compact byte, int, long, and float columns in `read_arrow()`. Doubles remain on their existing path. Default reader behavior is unchanged. The owned experiment takes precedence over the separate bounded Arrow completion experiment. `DTATOOLS_EXPERIMENT_TRACE=1` prints activation and fallback diagnostics; it must remain unset in timed runs.

The public reader interface is unchanged. The module boundary is private: [`owned_numeric.rs`](../../r-package/dtatools/src/rust/src/owned_numeric.rs) owns immutable storage, [`init.c`](../../r-package/dtatools/src/init.c) owns R handles and roots, and the Rust reader and writer adapters expose checked regions to their consumers. This seam separates native memory ownership from R's contiguous raw-vector representation.

## Representation and lifetime contract

An immutable `Arc<Owner>` contains checked chunk boundaries, element width, logical length, and retained native byte accounting. Each native chunk retains an Arrow `Buffer`; a frozen R-backed test adapter instead points into an actual immutable R raw allocation. Those adapters have different lifetime obligations. Native Arrow buffers are owned by Rust; every handle for a frozen R allocation also protects that R allocation.

`NumericData` and the matching C descriptor append an opaque native-owner pointer. Owned descriptors have a null contiguous `values` pointer. They do not disguise foreign memory as an R raw vector. Existing contiguous storage still uses a genuine R raw backing and a null native-owner pointer. Matching C and Rust layout assertions cover the changed descriptors.

Captures receive independent ALTREP descriptors, external pointers, and materialization state. They may share immutable bytes. A private C read handle pins the original owner and any R raw roots before later operands invoke foreign callbacks. Materializing the public vector cannot clear that private handle. Typed descriptor fields are copied where an operation must survive changes to the original descriptor. Worker threads never invoke R and finish before C releases the roots.

`RetainedRead::from_owner()` retains the native `Arc`. Its region interface returns a read-only pointer and the contiguous row count available from a logical offset. `CompactRead` adapts both retained owners and existing contiguous storage. Gather cursors cache the current span; comparison workers split their intervals at the boundaries of every operand; DTA writers cache a source region and reuse the existing typed encoding kernels. No mutable view into an owned buffer is exposed.

## Preparation and publication

The first prototype counted missing values serially during R publication. The revised adapter creates `PreparedOwnedNumeric` outcomes inside the existing column-fill workers. It checks types, null absence, byte width, chunk lengths, and total output length, then computes the exact missing count before publication. Integer missing classification follows the source format version; float classification includes NaNs and Stata missing encodings. Reader classification still decides whether a selected column is eligible before this adapter runs.

Missing-value scans use typed blocks of 65,536 rows. Each block checks cancellation; the inner reduction makes no R calls or per-element cancellation calls. The coordinator polls R interrupts, including while waiting for a worker tail, and shares cancellation with workers. Only the R thread publishes external pointers and attributes. Completed outcomes own their memory through RAII, so errors or cancellation drop unpublished owners when the worker results are discarded.

Single and multiple chunks use the same checked representation. Slice offsets are carried by the retained Arrow buffers; a slice may retain a larger underlying allocation. This implementation does not infer a dataset's chunk geometry from its dimensions or file size.

## Native consumers and writable access

| Consumer | Owned behavior |
| --- | --- |
| Element and region reads, missing queries, summaries, serialization, compact subsetting | Read immutable spans; serialized output contains independent bytes. |
| Scalar and vector comparisons | Split worker intervals at operand chunk boundaries and reuse contiguous kernels. |
| Fused comparison and patch | Read operands through retained spans; the target uses writable compact storage. |
| Single-column and parallel column gathers | Copy selected rows into new output storage, retaining input owners. |
| DTA writer | Retain source owners and encode typed regions directly, including the existing legacy conversion rules. |
| Arrow writer and dataset signature | Retain native Arrow arrays and supply canonical writer windows through the core source interface. |

For modern native Arrow chunks, `RetainedRead::arrow_chunks()` clones buffer owners without copying their payload. The frozen R raw adapter copies its chunks into writer-owned Arrow arrays. That copy is explicit: returned arrays can then outlive the R read root without depending on borrowed R memory. Legacy Arrow output first makes a whole-column layout decision. If normalization is required, it allocates normalized arrays; an observed conflict in a later chunk must affect the entire column's metadata and encoding.

Legacy consumers that request writable contiguous bytes still use the compatibility adapter. It copies into a real R raw allocation and records `compatibility_bytes`. A fused patch can request that writable target during preparation even when no rows ultimately change. Therefore the contract is copy on requested writable access, not a promise that copying waits for the first changed cell. Separate read operands retain their immutable owners. The direct owned `C_dtatools_patch_vector` transaction commits a private writable copy only after successful completion; failure or interruption preserves the original owned target and its captures.

## Native accounting and collection

Owner creation charges retained Arrow allocation capacity; final owner destruction releases the charge. Shared slices within one owner are deduplicated by underlying allocation address. Different owners can conservatively charge the same shared allocation more than once. The diagnostic counters describe retained owner capacity, not process RSS, writer scratch, or every native allocation. A lower R allocation profile alone does not demonstrate lower memory use.

R's heap accounting does not see retained Arrow payloads. A stress fixture with one ten-million-row int column retained 20 MB per read. Twenty repeated reads without explicit collection left 400 MB in twenty native owners, although only the final result was still reachable. Manual collection left the expected 20 MB in one owner.

The owned read entry point now requests collection once at the start of a read when outstanding native charges exceed 64 MiB. A C `R_ToplevelExec` wrapper contains any long jump from collection or user finalizers. This does not run on the default reader path and does not collect per column. Repeating the same stress test left 40 MB in two owners before manual collection and 20 MB afterward. Live retained results survived. The diagnostic loop also showed a collection cost: collection-bearing reads took approximately 18–19 ms versus approximately 3–5 ms for ordinary warm reads on this small fixture. These observations describe that stress test, not general reader throughput or a tuning result.

## Validation and remaining limits

The combined development package installed successfully. The final owned suite passed **574 assertions with no failures, warnings, or skips**. It covers four compact types, empty columns, varied chunk sizes, date conversion, missing tags, modern and legacy data, parallel missing counts, repeated-read collection, serialization, captured-handle isolation, failed and interrupted writes, and read-only consumer accounting. A 300,005-row comparison/patch test uses mismatched 65,531/65,537-row chunks and multiple workers. Foreign operand callbacks materialize the original vector and force collection during comparisons, gathers, DTA writing, Arrow writing, and signatures. A legacy test places its only observed layout conflict in the second chunk.

The broader consumer run passed 3,652 other assertions across Arrow, DTA writing, numeric summaries, native comparisons, and owned column/atom/read suites. Its initial additional callback test compared a constructed data frame's signature with the default dibble read model. The same difference reproduced on the baseline: default container restoration gives an ordinary numeric column a Stata storage declaration. The corrected test compares matching tibble read models and separately compares the two saved-file signatures; it requires no production behavior change.

Per-test-block evidence is stored outside the repository at `/private/tmp/dta-parity-owned-consumers-final.csv` and `.json`, with the full test object in `.rds` and console output in `.log`. The broader run has the same suffixes under `/private/tmp/dta-parity-owned-consumers-broad`. Later source-bound validation must record the actual installed source hashes; these development checks do not substitute for that binding.

Remaining costs include descriptor/chunk allocations, exact missing scans, R publication, collection when native charges cross the threshold, writable detachment, legacy normalization, and frozen-R writer copies. Summaries and element-based consumers preserve ownership but are not all vectorized across full chunks. Performance and peak-RSS conclusions require isolated measurements against the same corpus and bindings.
