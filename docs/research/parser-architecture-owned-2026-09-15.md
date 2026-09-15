# Architecture B: owned columns through R publication

September 15, 2026. Design proposal only. No implementation or benchmark ran. The inspected reference is locally stored `origin/main`, `b41d8f9d8dba260b8c93d5c7d83cb12ee8102600`, using `git show` without changing the checkout.

## Decision and evidence

Retain fully decoded, verified native columns as the compact representation returned by the existing readers. R receives independent handles to immutable owners. Supported mutation detaches the affected column into writable storage. This targets full-reader callers without adding a query interface or retaining undecoded DTA observation rows.

The four explorations support this particular ownership seam. Arrow R retains eligible arrays; pandas distinguishes Arrow-backed columns from conversion into NumPy storage; Arrow-rs transfers buffer ownership; Julia table consumers can accept parser-owned columns. Their restrictions matter as much as their mechanisms. Chunk consolidation, null conversion, writable pointers and string interning can consume the apparent saving. See the [R](parser-exploration-r-2026-09-15.md), [Python](parser-exploration-python-2026-09-15.md), [Rust](parser-exploration-rust-2026-09-15.md) and [Julia](parser-exploration-julia-2026-09-15.md) reports.

Locally, `ArrowReadColumn` retains `Vec<ArrayRef>`. `arrow_ffi.rs` subsequently allocates every destination and fills it while retaining those arrays. That is the copy to investigate. `Buffer::from(Vec<T>)` already transfers ownership without another copy. DTA already fills compact destinations directly, so this proposal establishes no comparable DTA copy saving. Its DTA case is shared native consumers and adaptive string storage. [Local evidence](parser-exploration-local-evidence-2026-09-15.md), [Arrow result](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/dta-tools/src/arrow/read.rs#L92), [destination construction](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/rust/src/arrow_ffi.rs#L3427).

## A deep column module

The module owns representation, decoding into R values, region iteration and ownership transitions. Its interface hides chunk offsets, missing classification, temporal conversion, string representation and retained allocations. A private sketch follows. These are proposed types, not existing declarations.

```rust
struct OwnedColumn { /* immutable; contains no SEXP */ }
struct ColumnSpec { len: usize, meaning: Meaning }
enum Meaning { StataNumeric(Storage, Release, Temporal), StataString }
enum Admission { Adopt(Arc<OwnedColumn>), Convert(VerifiedColumn) }

fn admit(input: VerifiedColumn, spec: ColumnSpec) -> Result<Admission, Error>;
fn regions(column: &OwnedColumn, rows: Range<usize>) -> Result<Regions<'_>, Error>;
fn decode_region(column: &OwnedColumn, start: usize, out: &mut [f64])
    -> Result<usize, Error>;
fn copy_for_patch(column: &OwnedColumn, out: &mut WritableCompact)
    -> Result<(), Error>;
```

`VerifiedColumn` proves the selected payload, layout and consumed profile documents have passed the existing checks. It is constructed privately by the format adapter, with the explicit unverified-reader option represented separately. Adoption must never upgrade an unverified read into verified evidence. Conversion remains the fallback when admission conditions fail.

An owner stores typed numeric chunks or string chunks, row-prefix lengths, source-release semantics and exact missing counts. Counts use the current float NaN rules. Length sums, allocation sizes and offsets are checked before publication. Numeric chunks preserve Stata storage widths and bits; their regions carry storage, release and temporal meaning. Sequential iteration crosses each chunk once. Random access locates a chunk by its row prefixes. An empty column has length zero and no dereferenceable region.

The R adapter owns a distinct handle for every independent column capture or duplicate. That handle retains an `Arc<OwnedColumn>` and has its own materialization state. Shared immutable bytes are allowed; shared mutable caches are not. Ordinary R aliases to the same dataset still follow the existing Dibble contract. Independence refers to captures that the current interface promises to isolate, not to every R binding. This distinction preserves explicit dataset mutation and ordinary replacement behavior. [Domain contract](../../CONTEXT.md).

## Lifetime, errors and native access

This requires a new C interface. Current Rust `NumericData`, `RNumericData` and C `numeric_data` assume a contiguous pointer protected by an R `RAWSXP`. `numeric_from_backing()`, serialization and mutation views use that backing directly. Replacing a field with `Arc` would break both layout and lifetime assumptions. [Rust descriptors](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/rust/src/lib.rs#L230), [C ownership and descriptors](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/init.c#L201).

Introduce opaque owned-column handles and versioned `dtatools_owned_column_*` functions for retain/release, descriptors, region cursors and decoding. The C descriptor contains an ABI version and checked integer lengths; it does not expose a Rust enum or `Arc` layout. Status distinguishes malformed input, unsupported conversion, capacity failure and cancellation; the caller frees returned error text. Keep legacy `numeric_data` for detached writable compact storage. An R external pointer finalizer releases one native handle exactly once. Its protected slot holds only genuine R roots. Foreign memory never masquerades as an R raw allocation.

A region cursor retains its owner until release. Its read-only pointer stays valid for that cursor's lifetime and cannot escape into a writable descriptor. All pointer widths, alignment and slice offsets are checked. Single-chunk read-only consumers can use a scoped contiguous view. Workers receive native owners or disjoint writable destinations and finish before publication or cleanup.

No Rust panic or R long jump crosses a live foreign stack frame. Native functions return status plus an owned error message; C raises the R condition after cleanup. R allocation, protection, attribute installation and interrupt polling remain on the R thread. Cancellation joins workers and discards unpublished owners. Native allocation accounting must expose retained bytes and inform the coordinator's GC policy. An external pointer alone does not give R the same allocation pressure as a large raw vector. Bound scratch and handoff queues in decoded bytes, with an explicit maximum single-buffer admission. Completed owned columns count as retained output.

After successful return, deleting, replacing or truncating the source cannot affect values. First access performs no file I/O, validation or DTA parsing. Memory mapping is a separate external-lifetime design and is excluded. Decompression may produce adoptable owned chunks, but compressed file bytes are never numeric backing.

## Adoption and strings

Start with one compatible, owned profiled numeric chunk. Require matching physical type, valid alignment, checked offsets, native byte order and the profile's missing representation. Preserve default checksum verification before adoption and compute missing counts before return. Retain the actual Arrow buffer owner, including any base allocation referenced by a slice. Measure excess retained bytes for narrow row windows.

Initially retain eager conversion for null-bearing ordinary Arrow columns, nonprofiled logical/integer semantics, factors and doubles. Preserve value-dependent classification on the selected arrays, including ordinary Int32 `i32::MIN` and sliced string null presence. Footer metadata alone cannot choose those R types. Existing compact `NumericKind` covers byte, int, long and float. An eight-byte owner is a later extension; raw Stata double missing bits are not automatically usable as an R `REAL` pointer. Dates keep their existing Stata-to-R offset or scale conversion at value access, with missing classification first. Ordinary Arrow dates, timestamps and durations retain their existing eager paths until separately qualified.

Multiple chunks need a second implementation stage. Store them with row prefixes and use regions throughout consumers; do not conceal concatenation inside handle construction. Readiness still includes complete decoding and verification. Chunking changes access costs, not whether the read has finished.

For strings, preserve the current dictionary and repeated-cycle strategy on repeated data. Admit validated owned UTF-8 bytes plus offsets when hashing and dictionary allocations would exceed that representation's costs. A bounded sample estimates distinct count, string lengths and retained bytes. Cap dictionary growth and allow at most one switch to offsets, charging the conversion to read time. Existing Arrow UTF-8 buffers may transfer directly after validation. DTA strings undergo the current encoding and replacement rules before owners freeze; `strL` resolution completes before return.

The empty string remains Stata string missing. Nullable ordinary Arrow strings keep the existing eager `NA_character_` path initially. Arrow dictionaries currently representing factors stay factors. Per-chunk string dictionaries may remain independent internally, but factor levels, ordering and metadata require their current reconciliation. R character creation stays on the R thread, with an independent cache for each handle. No durable Arrow profile change follows from an in-memory representation choice.

## Caller behavior and costs

The public readers keep their arguments and output containers.

```r
survey <- read_arrow("survey.arrow")
saved <- copy_data(survey)
total <- sum(survey$income, na.rm = TRUE)
replace_values(survey, income = 0, where = income < 0)
```

`sum()` visits typed regions without making a full double vector. `copy_data()` may share immutable bytes while providing independent handles and deep-copying the same attributes it copies today. Its existing rejection of attributes that cannot be isolated remains. The first patch copies the target's compact bytes into private writable storage, validates storage promotion, then uses existing patch logic. The saved dataset remains unchanged. Subsequent eligible patches can reuse the writable target.

Detachment applies even when the adopted owner currently has one reference. This keeps published owners immutable and avoids hidden Arrow-buffer sharing mistakes. Error or interrupt must leave values, missing counts, metadata and source caches unchanged under existing rollback rules. Group-wise assignment, sorting and promotion retain their established ordering and identity semantics.

Ordinary replacement uses an independent target handle when R requests duplication. Metadata proxies, call-local mutation views and captured replacement operands retain independent read handles. They must stop comparing raw backing pointers to synchronize missing counts. A writable `Dataptr` materializes private R storage, installs it only on that handle and releases its native owner when unused. Narrow numeric read-only `Dataptr` also needs a double allocation; `Dataptr_or_null` remains null until materialized. Full foreign consumption can therefore erase the load saving. String mutation retains today's full target-character materialization cost.

Compact serialization iterates regions into the existing canonical little-endian raw state; it never serializes addresses or chunk ownership. Existing version-2 state remains readable. Materialized vectors retain their current serialization route. Subsets and gathers create independent results, copying selected regions initially to avoid retaining an entire source for a tiny subset. DTA/Arrow writing and signatures must consume regions without silently forcing all columns to doubles.

## Real adapters, source changes and tests

The seam has two real format adapters: verified Arrow arrays and eagerly completed DTA columns through `DtaColumnSink`/`ParallelDtaSink`. Preserve the latest DTA byte-batch and adaptive-worker paths. Owned files and memory readers provide local-substitutable input sources where their capabilities match. Codecs, checksums and planning are in-process dependencies. R is an in-process runtime tested in actual R child processes. Python and Julia provide evidence only.

Stage changes in this order:

1. Add the owned-column module and C handle interface. Inventory every direct access before enabling adoption. Route ALTREP access, summaries, missing checks, factor conversion, comparisons, patches, gathers, writer descriptors, metadata views, duplication and serialization through a shared read interface. Keep existing contiguous adapters available.
2. Enable single-chunk Arrow admission in `arrow_ffi.rs` around classification, planning and finalization. Reuse verified owners from core `arrow/read.rs`; do not alter its verification scope. Instrument adoption, conversion and retained bytes.
3. Introduce region-aware native consumers and then multichunk admission. Update `lib.rs` write sources and Arrow export descriptors together with C callers and layout assertions. A compatibility adapter that coalesces must report its copy and remain temporary.
4. Add adaptive strings and the owned DTA sink separately. Do not attribute their costs or gains to numeric adoption.

The interface is the test surface. Run real fixture files and equivalent owned-memory inputs through each adapter, then the same R operations. Cover frozen profiles, malformed buffers, late validation errors, all missing codes, legacy releases, temporal formats, nulls, chunk edges, dictionaries, encoding, zero rows, projection and output containers. Exercise source deletion, GC stress, allocation failure, interrupts, captured columns, both duplication depths, `copy_data()`, materialization, promotion and serialization round trips. Extend existing semantic suites rather than adding tests that mirror buffer internals.

## Experiments and recommendation

Use the latest reference as a same-file control and the [local measurement protocol](parser-exploration-local-evidence-2026-09-15.md). Bind installed build, workers, inputs, verification and metadata qualification. Run timed work sequentially.

| Experiment | Falsifiable prediction and rejection criterion |
| --- | --- |
| Single owned chunk | First inventory actual record-batch geometry and eligible bytes, including India. Eligible columns allocate fewer destination bytes. Reject if ownership or alignment requires equivalent copying, or qualified read-plus-full-use time regresses beyond measured variability. |
| Multiple chunks | Retained bytes avoid coalescing across batch sizes. Reject default admission when cursor overhead, random access or consumer materialization erases the workflow gain. |
| Copy and first mutation | Captures avoid payload copies; first patch pays one compact detachment. Reject if alias isolation fails or mutation-heavy workflows consistently lose. |
| Adaptive strings | High-distinct columns spend less on hashing and allocation. Reject if switching or R materialization consumes the saving, or repeated-string controls regress. |
| Owned DTA sink | Existing eager decoding remains competitive. Reject this adapter as a default if allocation/GC behavior regresses without a completed-workflow benefit. |

Measure return, full traversal, ordinary R consumers, native summaries/writers, first mutation, CPU, peak RSS and retained memory separately. Include repeated dropped reads with GC, finalizer cleanup and allocation failures. Lower `Rprofmem` allocation is insufficient evidence of lower process memory. No speedup follows from these sketches.

I recommend bounded eager final-storage construction as the lower-risk first production experiment. This owned-column module is the stronger long-term candidate if native consumers commonly preserve compact representation. Its depth would concentrate ownership and conversion knowledge now spread across C and Rust, improving locality. That benefit only exists after consumers cross the shared interface; adding an owner beside unchanged pointer assumptions would make the code harder to maintain.
