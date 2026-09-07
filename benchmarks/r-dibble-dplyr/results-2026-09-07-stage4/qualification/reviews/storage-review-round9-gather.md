# Stage 4 storage review, round 9 discrete gather

Reviewed at 2026-09-07T05:09:10.756732+00:00 against the immutable snapshot captured at 2026-09-07T05:05:31.141886+00:00.

- HEAD at capture: `ca6b678e5f173ebc6acf921520d7fa562de42bb9`
- Package base: `7d56080f3e97bc4d73a848e363d729767b9629c0`
- Full current package diff SHA-256: `8ba44a8db283629798a3d15645b32c6e32d406054ee2ecd08f56878afcf7dadd`
- Saved package diff: `/private/tmp/dta-direct-stage4-validation/storage-review-round9-gather.diff`
- Gather increment since round 8: `/private/tmp/dta-direct-stage4-validation/storage-review-round9-gather-increment.diff`
- Increment SHA-256: `1b31320911dbc31bffde71b67c6d8a76cad25c86ce06f989cc05dc8064263a76`
- Exact source snapshot: `/private/tmp/dta-direct-stage4-validation/storage-review-round9-snapshot`
- Snapshot identities: `/private/tmp/dta-direct-stage4-validation/storage-review-round9-snapshot.json`
- Snapshot identity-document SHA-256: `bbff8d761ac29989ce0b681149b543f7643faec93875fe285e9b441056382b3c`

Two package-diff captures matched around the snapshot copies, and all copied file hashes were rechecked. The parent received the snapshot boundary before review. The later accessor prototype is excluded. Earlier package changes retain their round-7/8 source-review scope; this round reviews the discrete-gather increment and its call sites, tests and explanatory text.

## Disposition

No actionable correctness, ownership, alias, GC, callback-order or mutation finding in this gather snapshot. This is a bounded source-review result. Development timings are not accepted performance evidence, and full focused/exact-source qualification and Stage 4 acceptance remain separate.

## Qualification and behavior

The new C helper qualifies the entire remaining column batch before gathering any column. It accepts only package-owned integer/logical vectors and factors with exactly ordinary factor or ordered/factor classes and ordinary unattributed levels. It declines S4, unsupported classes, unknown attribute names, column names, dimensions and foreign/attributed locations. Preflight inspects native storage identity and metadata without invoking foreign element readers. Thus an unsupported column prevents partial use of the new route and preserves the existing fallback's cross-column callback order.

The helper is called only under the existing `fallback = "vctrs"` policy. Public row-slice callers first normalize locations with vctrs or their container's row-planning operation; grouping callers construct checked positive positions. The native helper consumes those positions rather than replacing public subscript normalization. Base-frame gathering still invokes its original base path, preserving the factor attribute behavior that differs from vctrs.

The gather itself uses the previously reviewed rooted atomic subset implementation. Each output gets a fresh ordinary integer/logical payload adopted into its own handle. Missing positions pad with the correct missing code; empty and repeated positions preserve the established selection semantics. Source records and index storage remain rooted during each gather, and the result list and each newly gathered vector are protected while attributes are copied and results installed. Attribute copying preserves their original order and contents on a separate handle. No incoming column payload is written or exposed as an untracked R value. The source and output remain independent under explicit native writes.

The returned list preserves column names, and the R caller assigns the batch to the original numeric positions, so table column ordering and duplicate-name handling remain with the existing surrounding code. Grouping, row-name reconstruction and output-container dispatch are unchanged.

## Regression review

The positive test establishes ordinary input and non-NULL owned-capture preconditions before comparison. It uses the real `vctrs::vec_slice` result as the value/attribute oracle and explicitly checks column attributes. Empty, repeated and missing row selections all run through the direct helper and shared R gatherer. A separate comparison uses the actual base-frame row result, including factor metadata behavior. The list oracle restores the expected column names because `.plain_data_columns` intentionally strips list attributes.

The alias checks mutate the source logical column after gathering and the result factor after gathering, then compare the opposite side with independent expected values. Source backing identity checks for untouched columns avoid relying on sharing flags that the vctrs oracle itself may affect. The negative cases verify whole-batch decline for a foreign column and for metadata or location cases, with callback counters confirming that qualification does not execute foreign elements.

`read-fixes-working-16-gather-oracle.log` reports the owned-atoms suite completed without failures. The earlier diagnostic/test attempts remain in the validation directory. No test or development timing was rerun by this reviewer. The ADR and progress text accurately limit the route to prevalidated vctrs gathering, preserve base and foreign fallbacks, and keep final qualification pending.

No R processes, builds, tests, probes or benchmarks were run. No source or root-owned file was edited. Review work was limited to source/evidence reads, snapshot hashes and these durable review artifacts.

## Reviewed paths and SHA-256

- `r-package/dtatools/R/dibble-rows.R`: `1ce41f4cbe505584dea298b807d600c08b9a735d6b13a41dd9520f7c29d570b3`
- `r-package/dtatools/src/init.c`: `ab3204cc0fe18017d420b14dc101b2911ec4b14f1eea32acfedc1a5aa5b9ca62`
- `r-package/dtatools/src/owned-columns.h`: `f32c5e55233bfaeba0f7dae0873378dbb312fa1649d2c0f8543d0cb4b976885c`
- `r-package/dtatools/tests/testthat/test-owned-atoms.R`: `d9944dd816edcdd0e653f5ad38dec9c68f8d67b781ad1b6dbfe331526047eb92`
- `docs/adr/0033-share-owned-atomic-backing-and-storage-facts.md`: `3b5c0e472a8ecdf0b945c704ad012d1bf40992ddb0348452a898223569f7b154`
- `docs/plans/dibble-result-performance-progress.md`: `9eed5d0cf25b7769bdd6c3316c230b17807ddd5ed6e0bffe99a21c5f12a89ba5`

- `read-fixes-working-16-gather-oracle.log`: `10969a105b9a5151be0f05b7cbbcbcf545b30b75ee1e47cff031d8332c77fd85`
