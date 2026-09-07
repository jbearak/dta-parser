# Stage 4 native supplement API review, round 6

Reviewed at 2026-09-07T03:47:15.962679+00:00. Recorded HEAD is `7d56080f3e97bc4d73a848e363d729767b9629c0`. Production package source remains byte-identical to `7d56080f3e97bc4d73a848e363d729767b9629c0`. This is a bounded review of the native runner fixture/readiness fix; root's separate benchmark README clarification is included only in the full snapshot.

Fix diff against production: `api-review-round6-native.diff`, SHA-256 `e131883e669f94849502f1a88a6dc83250d172b07b95f0b5d465a0123001bb8b`. Full tracked plus sorted-untracked epic diff against `ec10a6ac34602f3bd691e8043019c1b479babda4`: `api-review-round6-native.full.diff`, SHA-256 `305f6b55f5f45e94364a51f6bb469c7c784b8b942608b0447b2e858d92745acf`. Complete file identities are in `api-review-round6-native-identities.json` and below. Snapshot consistency and the absence of a package diff against production were checked.

## Disposition

No actionable finding. The runner-only correction is clear to commit and execute after root releases the quiet window. The 18 corrected native cases remain unexecuted at this review. This is source clearance, not acceptance of their numerical results or Stage 4 completion.

No R process, tests, build, behavioral probe or timing workload was run. Work was limited to source/evidence reads and durable review artifacts.

## Actual fix

The runner now constructs factor/ordered-factor values with the canonical factor constructor. Given explicit first/second/unused levels, this preserves the intended integer codes 1/2/NA, level order and orderedness. It avoids manually replacing all attributes on the large pre-existing integer vector, which the retained diagnostic log shows can produce an unrecognized R ALTREP wrapper.

Before capture, readiness now explicitly requires integer storage and an ordinary vector. After capture and metadata copy, both ownership-info objects must exist, both depths must be one, and only then are backing identities compared. The former NULL/NULL identity equality can no longer masquerade as owned backing. This corrects the benchmark fixture instead of broadening production admission to unknown borrowed ALTREP.

The diff changes no profiled native call, numerical threshold, row scale or post-profile value/metadata/alias oracle. Per-case logging occurs before fixture creation and outside Rprofmem. The new info lists retain diagnostic strings and flags, not column handles. Existing shared/private readiness assertions, independent source snapshot, full table attributes/raw row names, reverse sibling expectation, retained full alias, full-replacement zero old-journal check and before/after committed-source guards remain intact.

## Existing evidence inspected

The large-fixture diagnostic reports ordinary integer input but ALTREP factor/ordered inputs from the old attribute-replacement construction; capture returns NULL ownership info for the latter. The canonical-constructor diagnostic reports ordinary factor/ordered storage and valid depth-one owned info. These support the fixture diagnosis; they are not the corrected full 18-case execution.

The exact-gates manifest for production records completed package/conformance/documentation/archive/NOTICE work and retains native/performance/final-review tasks as pending. It preserves the three R check warnings and two notes, the separate four baseline suite warnings, and existing Cargo packaging warnings. The eight native identity-command rejection cases record exit 1, exact guard diagnostics and no output files. They were run on the committed pre-fixture-fix runner; the identity logic is unchanged by this fix. This reviewer inspected their retained summaries without rerunning them or relabeling their source.

Storage round 5 independently clears the same fixture fix. Corrected native numerical execution and final paired candidate performance/evidence review remain required.

## File identities

- `benchmarks/r-dibble-dplyr/README.md`: `94d93066b56e6abd3108ffb30dc264e04dd20ebfd888bab86aaaf4c4050aa8f1`
- `benchmarks/r-dibble-dplyr/owned-atomic-helpers.R`: `4ea65133046e058f2bdf071417ed3c701a6ae98ec600e842dd14fde95ffa4ba1`
- `benchmarks/r-dibble-dplyr/owned-atomic-memory.R`: `38f4aa25fe12193ec6c1860dfc85accbdd857e1afb207ab2867bc8cff3a966f2`
- `benchmarks/r-dibble-dplyr/owned-atomic.R`: `1b86479434dac71c2354d120894f9deacf57bbb0887567630b4e5b2be80c3012`
- `benchmarks/r-dibble-dplyr/run-atomic-qualification.py`: `37f1aae3c103f976acfdc2d2ad2f8cf5382fef98b38a36b5aa7c4e52511185a7`
- `benchmarks/r-dibble-dplyr/test-atomic-qualification.py`: `21a88739a6c8cdf8b213da32ee3689f9e2ce057cf1db15bee7db1ef2407e866f`
- `benchmarks/r-dibble-dplyr/test-provenance.R`: `16f3f1bc2412795094e60c7c17e2e85161b4e4ade88cc431b168283e44120290`
- `benchmarks/r-reference-mutation/README.md`: `05247604a53e97aad4263e1b26179f62f707e7cf99b9eeccc68322a073a876bf`
- `benchmarks/r-reference-mutation/owned-atoms.R`: `0542e6943cf1b708bb17d86305483eac011ccedb30e4394d04aeace42ff6759a`
- `docs/adr/0032-share-owned-double-backing-with-transactional-table-writes.md`: `4034ae55454416d3c895b2df1c2e336f686de1e8f0bf75e567e8cf3c7a9a1e94`
- `docs/adr/0033-share-owned-atomic-backing-and-storage-facts.md`: `5f4d75c0ae2c41555e22247728ca8924ae642aba020b96c0901455b5e83ee2e2`
- `docs/plans/dibble-result-performance-progress.md`: `b6a9802edbec1ec8be3b7490df48ede84f5d264b4008eee56928c65a6a253870`
- `r-package/dtatools/R/dibble-result.R`: `20c86c603f7cd7300e9b7b06bb4fe1ba29a14b74e4192b67a6061b0bdc421fc7`
- `r-package/dtatools/R/dibble.R`: `1ebfc62751b92804ef3906ac323ff0616ec1b5589b6e039424d32f5799ee7e1e`
- `r-package/dtatools/R/dta-string.R`: `d51592fe87cb2c0374618d2beaec9994cc5c03c60b70b617408769cb782e9a03`
- `r-package/dtatools/R/mutate-data.R`: `337477c4dfbd67d1f1f9c758a7ac49ec2048d0f2ae727bf1f8880c1b7ed76bc0`
- `r-package/dtatools/README.md`: `289cf37339967cc4ee757c20994e3421e752ff042589410dde8363ba50e20d64`
- `r-package/dtatools/inst/NOTICE`: `3f19001559480e42ecfc7f6255afecbe9583977b6e7bd75b6ff076f22d8614e3`
- `r-package/dtatools/man/dibble.Rd`: `edcfcb131f7ae581dca2e010282bf39c404ead5060fa25278d1b89852278f894`
- `r-package/dtatools/src/init.c`: `d2cc1924149be0c13138289bd4fcf9754402ada49ac6e7c2e06573d09d195c4a`
- `r-package/dtatools/src/mutation-write.h`: `d8e5f6abbe970c4ed12fb923fa55b76e6278e9c1072089356a7698f9cd8c489d`
- `r-package/dtatools/src/owned-columns.h`: `ece57105403f174edcb5dfef977df4b4a5bcc8a0b1105a7a54ecdffb967e6886`
- `r-package/dtatools/src/rust/src/lib.rs`: `bde26cc55f6f2e2d80e042dff915b2cd6367bfd600ddd93087b639e6bdcca0e8`
- `r-package/dtatools/tests/testthat/test-dibble-columns.R`: `07a27397ecb617cb822255ca46d48cd2971ada75f1198244de66ced8e0848c90`
- `r-package/dtatools/tests/testthat/test-owned-atoms.R`: `90661e9a074f68b0e3731b6a57b58f8738a8244c68ee3b111dcf75ae6edf86bf`

## Inspected evidence identities

- `native-factor-large-fixture-probe.log`: `8744c5c231665dddf5f88903ef5b2c57959018dd5874b0fe90f65bcdcb3e8892`
- `native-factor-constructor-probe.log`: `864344db32881dad77152a72d3c276faacc86102259ea4e3cf107a67594f50c8`
- `storage-review-round5-native.md`: `641be62568a67f315d617dbd6324cf620afaf6f700637fb748586c2df978f04f`
- `checks-7d56080/exact-gates-manifest.json`: `6fca4d2d4467510efdaa12b33866ef81cfbe8f1e0cd20338b7512aabe22a0549`
- `checks-7d56080/native-identity-guards/results.json`: `926d343c9ee5b594ffe420c8f18af8bc1becebb6d7640053b60d2511a1c24199`
