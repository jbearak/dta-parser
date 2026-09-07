# Stage 4 evidence review, round 6 addendum

Reviewed at 2026-09-07T04:10:29.075200+00:00.

No actionable discrepancy in the revised initial-report lead. It now limits the passing value, metadata, isolation, selector-allocation and retained-memory statement to the measured benchmark matrix. It also discloses the later owned-string Arrow callback failure and states that this candidate has not passed acceptance.

The first failure in `read-fixes-red.log`, at `test-owned-atoms.R:514`, records output `changed`, `changed`, `changed` where `alpha`, `beta`, `alpha` was expected. The associated test prepares the first column, then puts a callback in a later column's metadata. That callback patches the previously prepared owned string handle and invokes GC before writing. The measured candidate's character Arrow descriptor at commit `7d56080f3e97bc4d73a848e363d729767b9629c0` assigns `descriptor->strings = values`, so its later reads follow the changed handle. This supports the lead's explanation that the descriptor retained the handle instead of the exact allocation. The addendum does not review the subsequent package fixes or claim this new regression has passed.

All 157 indexed evidence files still match their recorded sizes and hashes. Comparison against all 160 round-6 reviewed artifact identities found only the report changed. Its edit is confined to the lead paragraph; the archived benchmark measurements, index, derivation records and README are unchanged. The report continues to preserve the 43 read-regression flags and the initial candidate's incomplete acceptance status.

## Exact identities

- Prior report SHA-256: `d71485c83fa3930597aeb12b55276b6db9c50773ac8c6f79e46c49649c5416a5`
- Revised report SHA-256: `5ce0087ef4a5f00a349f459bfb755d9d98b3b58f8d8430fee30ade2ba00f1e88`
- Lead-only review diff: `/private/tmp/dta-direct-stage4-validation/storage-review-round6-evidence-addendum.diff`
- Review diff SHA-256: `8845e4dc0b38ab5499ee249c54c9b6bb06bd2e6ca07db3126a6c200c153c8370`
- `read-fixes-red.log` SHA-256: `59d7c68576f33706bbdd71da02ca80ea2ae45220abfc11300eba69c6346242f7`
- Unchanged initial evidence index SHA-256: `d58ba06fc93efc8429ed5511e7461cae9764014c70bdb84ea4c10f325661e40c`
- Reviewed current test source SHA-256: `1e1bac0ebb4ecc858a0dc3098f0c29636e9d7843ee12c2ff919fb8b537ae2e9f`

The preceding round-6 report and identity document retain the complete evidence scope. No R processes, builds, tests or probes were run. No root-owned file was edited.
