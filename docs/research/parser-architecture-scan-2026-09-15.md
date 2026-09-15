# Prepared sources and explicit scans

Architecture exploration, September 15, 2026. This is a design proposal, with no implementation or new timings. It uses locally stored `b41d8f9d` through `git show`, the [shared evidence](parser-exploration-local-evidence-2026-09-15.md), the [R](parser-exploration-r-2026-09-15.md), [Python](parser-exploration-python-2026-09-15.md), [Rust](parser-exploration-rust-2026-09-15.md), and [Julia](parser-exploration-julia-2026-09-15.md) explorations, and [CONTEXT.md](../../CONTEXT.md).

## Recommendation

The user requires optimization of both all-column loads and projections. This design contributes private metadata/plan reuse to both existing readers where repeated work is measurable. Compare projected reads with existing `col_select` and test metadata-based discovery as an additional scenario. Keep the all-column path direct, with no mandatory discovery call or added prepass. The [review](parser-architecture-review-2026-09-15.md#primary-workloads) treats both workloads as primary targets alongside bounded execution.

The public scan and incremental-acquisition ideas below remain separate design options. Measure reader return and completed consumer work for each primary workload, including sparse downstream use after loading all columns. The latest retained full-import India medians, 0.752 seconds for DTA and 0.558 seconds for verified Arrow against retained Stata at 0.5015 seconds, remain primary full-load evidence, with projection evidence assessed separately.

The proposed module hides file ownership, interpretation, selection planning, and execution behind one interface. Its depth would come from sharing that behavior across eager imports, metadata inspection, and selective consumers. A wrapper that merely forwards every existing reader option would add little depth.

The seam belongs between a prepared source and its consumers. DTA and standalone `.arrow` datasets are actual adapters there. They must retain their different physical execution and validation rules.

## Existing footholds and transferable lessons

`DtaFile<R: Read + Seek>` already retains metadata, scratch storage, and a value-label cache. Its R wrapper separately obtains a schema summary for selection and then calls the path-based native reader. Worker selection and sink eligibility also reconstruct an `ObservationPlan`. Measure those repetitions before changing them. `ArrowFileSnapshot` retains one `File`, but `summarize()` and `prepare_read()` independently read the footer. The latter already reuses a full profile parse when computing a stored signature. [DTA source](https://github.com/jbearak/dta-parser/blob/b41d8f9d/r-package/dtatools/src/dta-tools/src/file.rs#L1840), [Arrow source](https://github.com/jbearak/dta-parser/blob/b41d8f9d/r-package/dtatools/src/dta-tools/src/arrow/read.rs#L1318).

Arrow's scanners and Polars show why projection and filters should arrive together before output allocation. DuckDB pushes filters into Parquet scans and can skip row groups using their statistics. Ordinary DTA has no corresponding page index or row-group statistics. Its current observation executor reads complete row widths, so projection principally saves decoding and output allocation. Verified IPC slicing still reads and hashes each full touched buffer. Neither format inherits Parquet pruning merely by acquiring a scan interface. [Arrow scanner](https://arrow.apache.org/docs/python/generated/pyarrow.dataset.Scanner.html), [Polars scan](https://docs.pola.rs/api/python/stable/reference/api/polars.scan_parquet.html), [DuckDB Parquet](https://duckdb.org/docs/current/data/parquet/overview).

Tables.jl's documented scan contract supplies a useful rule: an operation is consumed only when its complete semantics have been executed; weaker pruning leaves a residual operation. Its SQL missing logic is unsuitable for Stata missing-code identity. Parquet2's repeated-column-read warning also matters. Reusing a plan does not cache decoded values. The rejected local deferred-numeric prototype already exposed repeated decoding through copied handles. This proposal does not restore that default. [Julia evidence and version caveat](parser-exploration-julia-2026-09-15.md#tablesjl-makes-the-boundary-small-and-explicit).

## Small explicit interface

Illustrative private types and methods, not proposed exported spellings:

```text
PreparedSource = open(SourceLease, Interpretation)
describe(View) -> Description
prepare(Request) -> Plan
close() -> ()

View = Names | SelectionTypes(SourceWindow) | FullMetadata
Description = { fields: [FieldId, source_name, logical_type, metadata],
                source_rows: Known | Unknown, validation_scope }
Request = { source_window, predicate, match_window,
            projection: [FieldId, output_name], terminal }
terminal = Rows | CountRows
Plan = { output_schema, consumed_operations, residual_operations,
         validation_scope, required_prepass, execute(Destination) }
Destination = OwnedTable | OwnedBatches(byte_budget) | Scalar
Cursor.next() -> OwnedBatch | End | Error
```

`FieldId` is a stable source position tied to this source identity. `Interpretation` captures encoding, profile behavior and verification policy once. The R adapter captures output-container options and name-repair policy separately. A plan cannot transfer to another source or silently change interpretation.

Execution order is source row window, predicate, matching-row window, projection, then terminal operation. Windows use checked nonnegative offsets and optional lengths; the private form normalizes public R arguments once. The distinction prevents `skip = 100` from unexpectedly meaning 100 matching observations in an existing eager read. Rows keep source order; projection follows requested order. Zero-column rows still carry their correct row count.

Names and tidyselect expressions resolve before native planning, using the current selection proxies and duplicate-position policy. Strict selectors such as `all_of()` reject absent names during selection; `any_of()` omits them, preserving union-safe projection across differently shaped files. An empty selection keeps the requested row count. Explicit rename information accompanies resolved positions. Name repair runs once on the projected names under the existing R policy; it never changes native field identity. A scan predicate uses source field identities, not repaired output names. A user-supplied repair function remains an R callback, with its current invocation and error behavior preserved in eager wrappers.

The first native predicate vocabulary should be deliberately small: scalar numeric comparisons against declared Stata numeric columns, explicit missing-code equality, `is_missing`, and Boolean composition. Comparisons use Stata total order; `.` and each of `.a` through `.z` are distinct. `is_missing` admits all those codes. These predicates return true or false; `AND`, `OR`, and `NOT` use ordinary two-valued Boolean logic. Noncanonical NaNs follow existing validation rather than becoming an invented null category. Factors, ordinary Arrow nulls, temporal comparisons, string comparisons, arithmetic, and arbitrary R calls remain unsupported until individually qualified. Plain Arrow fields never acquire Stata semantics.

`CountRows` returns the count after both windows and filtering, with checked overflow and an exact R representation or an explicit error beyond supported precision. It needs no grouping or floating-point reduction rules. General summaries stay with existing result modules, either after collection or through a consumer that explicitly defines a batch reduction. Do not implement joins, sorting, windows, spill, or another expression language without actual consumers.

## Residuals and schema evidence

For native requests, preparation rejects unsupported predicates. A later R scan adapter may keep an arbitrary R filter as a residual, but must retain the whole callback expression. It cannot push a conjunct ahead of an effectful callback, limit its input early, or evaluate it independently per batch. Existing expression masks retain group context, callback order, warning behavior, and expiration rules; `row-filter.h` deliberately reads later predicate payloads even for already rejected rows. Reuse that execution rather than approximating it. [Expression module](https://github.com/jbearak/dta-parser/blob/b41d8f9d/r-package/dtatools/R/dibble-expressions.R), [row reduction](https://github.com/jbearak/dta-parser/blob/b41d8f9d/r-package/dtatools/src/row-filter.h).

An owned-table destination may materialize the residual's complete input and invoke the existing R operation once. Unknown callback dependencies require all columns. Projection, matching-row limits, and counting stay after that residual. Batch and scalar destinations reject unresolved residuals before execution. A plan description exposes this distinction; successful return never leaves unapplied work disguised as a completed result.

Description has separate logical-schema and output-classification evidence. Arrow's ordinary Int32 output depends on whether selected values contain non-null `i32::MIN`; a declaration of R integer semantics makes that value an error. Selected string nulls choose dictionary-backed versus ordinary character construction. Schema parsing alone cannot determine these facts. Selection type predicates may already scan ambiguous Int32 values. That evidence is row-window-specific and does not prove checksum verification. [Classification](https://github.com/jbearak/dta-parser/blob/b41d8f9d/r-package/dtatools/src/rust/src/arrow_ffi.rs#L2041).

Freeze batch R types before emitting the first batch. Initially restrict that destination to supported declared types; add ambiguous ordinary Int32 only with an explicit classification prepass over the candidate source window. Classifying only survivors could differ from read-then-filter classes. An eager destination can retain its current classification timing. String backing may vary internally while the exposed character type remains fixed.

## Validation and ownership contracts

Opening establishes file identity and structural metadata required to describe it. Preparation validates referenced schema documents before execution. Predicate-free Arrow projection retains selected-field validation; a type-predicate summary validates all profile fields. Full reads and profiled stored-signature requests preserve their wider existing scope. Referenced row-filter fields count as consumed fields even when absent from output. Profile version rejection and frozen-profile compatibility remain unchanged. Full metadata inspection does not imply that every data buffer has been checked. [Arrow wrapper contract](https://github.com/jbearak/dta-parser/blob/b41d8f9d/r-package/dtatools/R/read-arrow.R#L25).

Before exposing values, decode performs buffer-bound checks, verification, and layout/value validation. Count-only plans must state when they use headers without verifying unreferenced values. Skipped payloads remain outside that scan's validation claim. Eager reads preserve their existing malformed-input rejection scope and data-signature rules. In particular, a stored Arrow signature describes the declared complete file; it does not certify unread payloads.

`SourceLease` owns the opened descriptor and temporary-source cleanup. A plan retains the lease. Only one cursor executes per source initially; concurrent execution errors instead of racing mutable seek state. Explicit close errors while a cursor is active, otherwise invalidates all plans and releases the lease. Repeated close is harmless. Abandoning a cursor releases it; yielded batches own decoded values and metadata and survive cursor advance, close, source deletion, and R GC. Collected tables retain the current supported mutation contract.

An open descriptor survives pathname replacement where the operating system permits it. It does not protect against in-place writes or truncation. The source contract requires stable contents while open; detected changes cause failure and invalidate plans. File-stat checks cannot guarantee detection of every concurrent edit. Immutable input bytes are a separate, explicitly costed source option. Do not advertise a file handle or mapping as immutable storage.

Owned-table and scalar execution publish only on success. A batch stream can fail after earlier batches were delivered; only `End` means completion. Interrupts cancel work, join workers, and release temporary buffers. R allocation, callbacks, protection, attribute changes and publication stay on the R thread. Reserve staging bytes before allocation, including retained dictionary dependencies. An indivisible buffer exceeding the requested batch budget causes `BudgetExceeded`; consumer-retained batches and final output are outside that budget. Other interface errors distinguish closed sources, busy cursors, invalid field identities/windows, unsupported operations, malformed input, I/O, and interruption. Eager wrappers preserve existing error presentation.

## Implementation and eager reuse

Keep planning, codecs, checksums, and predicate computation in-process. Place reusable format plans inside core `file.rs` and `arrow/read.rs`, with private adapters to their existing executors. Reuse storage-aware comparison logic in `lib.rs` rather than copying missing-code rules into a new evaluator. Runtime field descriptors avoid a compiled type per wide schema. R adapters in `lib.rs`, `arrow_ffi.rs`, and `init.c` own object construction. `read-dta.R`, `read-arrow.R`, and source cleanup transfer one lease through selection and completion. No Python, Julia, DuckDB, or other external runtime dependency is needed.

Private eager callers prepare a request with no row predicate or matching-row window, execute directly into their established final sink, then close. They need not allocate public batches or expose scan behavior. Share validated descriptors and classification evidence only when their scope matches. Preserve result isolation and metadata through `dibble-result.R`; a source pointer or lineage address is not an ownership certificate.

For example, an explicit scan can describe an income field, prepare `income >= 1000 AND NOT is_missing(income)`, project household identifiers, and collect owned rows or return `CountRows`. The missing test matters because Stata missings rank above finite numbers. Reexecuting this plan rereads values; callers retain its collected result for repeated analysis. Metadata reuse and value caching are separate decisions.

## Staged experiments and stop criteria

1. Instrument existing eager calls at the reference revision. Count opens, footer/schema parses, classifications, allocations and time by phase on tiny, wide-zero-row, projected and full files. Reject plan reuse as a performance priority if the duplicated work is negligible; retain it only if locality independently warrants the change.
2. Share one private plan through selection and eager execution. Require fewer repeated parses and equal values, metadata, errors, output containers and source cleanup. Reject any elapsed-time claim outside matched variation, or any regression caused by eagerly parsing documents previously left unconsumed.
3. Qualify one real consumer using projected batches and numeric filtering/counting. Compare clustered and scattered survivors, predicate width and repeated queries. Include open, planning, verification, decode, consumer work and final materialization. Reject a public scan product if complete workflows offer no useful time or memory benefit after these costs.
4. Test through the interface with real DTA/Arrow fixtures and memory readers where seek behavior permits. Use actual files for replacement, truncation, descriptor and temporary-source tests; real R child processes for GC, aliases, mutation, callbacks and interrupts. Corruption after the first batch must produce failure rather than successful exhaustion.

Run matched completed eager workflows separately against Stata `use`. A selective aggregate comparison needs equivalent Stata filtering, summary, validation qualification and result consumption. No scan startup result belongs in the full-load table. This design can concentrate selection and ownership knowledge, but its additional lifetime and residual rules cost interface depth. Private plan reuse is the smaller decision and should stand on its own evidence.
