# Stage 4 API, tests, documentation and attribution review, round 5

Reviewed at 2026-09-07T03:29:08.271376+00:00, against `ec10a6ac34602f3bd691e8043019c1b479babda4`, in `/private/tmp/dta-direct-stage4`. Recorded HEAD: `7d56080f3e97bc4d73a848e363d729767b9629c0`. The reviewed working tree includes the package/native supplement changes plus root's uncommitted benchmark README clarification.

Full tracked plus untracked diff: `api-review-round5.diff`, SHA-256 `24963c3e77d6992e6b92ad08497bf7973b99441109e53f3d76f1a78652cbebd2`. Tracked-only diff SHA-256: `24963c3e77d6992e6b92ad08497bf7973b99441109e53f3d76f1a78652cbebd2`. The combined diff contains `git diff --binary BASE` and sorted untracked-file patches from `git diff --binary --no-index -- /dev/null PATH`. Per-file hashes and tracked status are recorded in `api-review-round5-identities.json` and below. Snapshot consistency was verified against a second source read.

## Disposition

No actionable API, test-design, documentation, plan-consistency or attribution finding remains in the reviewed source. Earlier API findings remain closed. The recorded source commit is clear to proceed to exact archived-source qualification from this review's perspective. Exact-source archive/install/native/performance/evidence checks and external review remain required; this is not Stage 4 completion or merge approval.

No package edits, R tests, native/Rust builds, benchmarks or behavioral probes were run by this reviewer. Existing source and validation artifacts were inspected; `git diff --check` also passed.

## Latest actual-diff fixes

Legacy `patch_vector` captures original target state before operand callbacks and stages unknown ALTREP operands into protected ordinary vectors before retaining native readers, journals or writable target pointers. Admission to direct reads uses actual native ALTREP class identity, not public S3 class tags. Ordinary and known owned/compact/dictionary/metadata storage retain their existing direct paths. The new row snapshot is rooted before replacement preparation, and exact payload roots plus copied compact descriptors survive the full read lifetime.

Original-target checks follow operand preparation and compact prevalidation, and the final string-declaration check completes before the transaction enters journal/apply. A target materialized by row, replacement-length or declared-width callbacks produces the changed-state error with original values preserved. Unknown operands no longer invoke callbacks during later journal, apply or rollback phases. The new tests explicitly distinguish immediate callbacks, delayed callbacks that must not execute beyond capture, legacy target representations, callback counts and expected values. This matches the intended lifetime boundary without claiming unknown ALTREP is callback-free.

The missingness regression now invokes STRING_NO_NA through the internal probe, exercising the public native entry point and registered method directly. It proves one two-value missingness scan followed by a cached result; anyNA semantics are checked separately. This fixes the former assumption about anyNA's implementation on this R build. The source still counts both width and missingness-only native scans, with cache-hit returns preceding counter increments.

Rust changes since the previous source snapshot are formatting of the already reviewed descriptor reference count and lifetime test. No additional public Rust/R interface change or source adaptation appears.

## Native supplement source review

The native integer/factor/ordered-factor supplement now snapshots ordinary source values independently before capture. The changed-source oracle cannot alias the source it checks. Each shared/private/full profile has immediate value, source, column-attribute, complete table-attribute and raw-row-name guards. The reverse sibling write has its own expected value; both sibling and retained pre-full-replacement alias are checked after the full replacement. Full replacement requires zero old-value journal bytes in addition to zero overwritten-payload copying. Original numerical budgets are unchanged.

`checked_line` rejects failed system2 commands, missing/multiple/NA output lines and malformed hash text. Git hashes require one 40-digit lowercase hexadecimal value. shasum output requires one line beginning with a 64-digit lowercase hexadecimal value. Both directly executed source files are matched against committed Git blobs before output and checked again afterward. SHA-256 identities are computed before opening either output, and output connections use exclusive creation. Installed package/DLL and installation provenance guards remain before and after work.

No remaining source guard defect was found. The planned failed-git/failed-shasum/malformed-output and no-output rejection checks still need execution, followed by the 18 numerical cases. This review does not mark those pending tests as passed.

## Documentation and interface

R/dibble.R and man/dibble.Rd remain consistent about owned atomic backing, borrowed capture and validation-fact reuse. ADR 0033 now describes unknown operand snapshots, original-target checks and stable journal/write/rollback operands. Its No_NA counter scope, factor restrictions, exposed-pointer rules, serialization fallback and distinction from temporary blank names remain accurate. The native README matches the supplement's storage kinds, row scales, budgets, oracles, provenance and public factor restriction.

Progress correctly records the full development suite, the corrected No_NA test assumption, Rust working checks, exact baseline benchmark work and the remaining exact-source/final gates. Stages 5 through 9 remain required and issue 172 remains open. Parent owns refreshing tested source/commit identities during archived-source qualification.

NAMESPACE and DESCRIPTION are byte-identical to the Stage 3 base. No new exported verb or incidental dependency change is present. NOTICE and package README retain the exact R 4.6.1/SVN 90187 study-only attribution and all existing full upstream notices. The additional lifetime/callback code is package-owned; no further copied/adapted upstream portion is apparent. Source, installed and binary NOTICE distribution checks remain pending final evidence.

The root atomic runner files are unchanged from the previously reviewed committed bytes. The README clarification accurately places expected factor-warning collection/checking inside the measured writer wrapper in both revisions. Historical Stage 3 evidence remains unchanged.

## Existing evidence inspected

- `full-working-9.log` ends with DONE and no failure or skip section. It records four established warnings: factor conversion, temporal comparison dispatch, and two tibble row-name warnings. This is a passing development run, not an exact committed archive check and not warning-free.
- `bridge-tests-working-8.log` records 18 passing tests, including dictionary_pin_survives_release_of_original_owner. Its JSON execution record reports exit 0 for bridge fmt, check and tests.
- `workspace-tests-working-9.log` result lines sum to 278 passes, with zero failures/ignored/filtered tests. The JSON record reports exit 0 for workspace fmt, Clippy, tests, docs and packaging.
- `workspace-package-working-9.log` also contains 11 warnings about excluded integration-test files. Successful packaging is not described as warning-free. No new-warning attribution is inferred from that log alone.
- The separate storage round 4 review clears source lifetime, alias, rollback and benchmark findings. This review independently inspected the latest API/testing/documentation changes and the subsequent native checked_line guard.

The old failed borrowed-fixture and No_NA-assumption logs retain their historical status. Exact archived-source package checks, conformance/interoperability, native allocation gates, notices, final source-bound timings/memory and external review remain required.

## Reviewed file identities

- `benchmarks/r-dibble-dplyr/README.md`: `94d93066b56e6abd3108ffb30dc264e04dd20ebfd888bab86aaaf4c4050aa8f1`
- `benchmarks/r-dibble-dplyr/owned-atomic-helpers.R`: `4ea65133046e058f2bdf071417ed3c701a6ae98ec600e842dd14fde95ffa4ba1`
- `benchmarks/r-dibble-dplyr/owned-atomic-memory.R`: `38f4aa25fe12193ec6c1860dfc85accbdd857e1afb207ab2867bc8cff3a966f2`
- `benchmarks/r-dibble-dplyr/owned-atomic.R`: `1b86479434dac71c2354d120894f9deacf57bbb0887567630b4e5b2be80c3012`
- `benchmarks/r-dibble-dplyr/run-atomic-qualification.py`: `37f1aae3c103f976acfdc2d2ad2f8cf5382fef98b38a36b5aa7c4e52511185a7`
- `benchmarks/r-dibble-dplyr/test-atomic-qualification.py`: `21a88739a6c8cdf8b213da32ee3689f9e2ce057cf1db15bee7db1ef2407e866f`
- `benchmarks/r-dibble-dplyr/test-provenance.R`: `16f3f1bc2412795094e60c7c17e2e85161b4e4ade88cc431b168283e44120290`
- `benchmarks/r-reference-mutation/README.md`: `05247604a53e97aad4263e1b26179f62f707e7cf99b9eeccc68322a073a876bf`
- `benchmarks/r-reference-mutation/owned-atoms.R`: `5ce543534ada9a4a13523fe6c16964130f37bca54300c778b0df4d70b88d3b73`
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

- `full-working-9.log`: `327dac9ae6d27905522a08df819f7c75d884ae8d028ca2addb3a5a0750e74919`
- `bridge-tests-working-8.log`: `61bbbd2cb2d0e701d79d66ff2ec5874366ba45fdeb3fa1511f2ca1ca63f1d9b8`
- `bridge-working-8.json`: `2818714cc61ad92f260ec4c035f14940580753808fb4ae6c0cf13ff8b71fd2d1`
- `workspace-tests-working-9.log`: `879cc077b7c519b651d8e00d413de1f3af2b0f93db5d4408ce886ff7864c1414`
- `workspace-working-9.json`: `fc6a08dba2313a47bb14e8120ff9dd7b4517ef43f882b46a5b83f8355042bb70`
- `workspace-package-working-9.log`: `7ec5c0398d2c17da1f2708a53029fa78c09dc78055bb112ca397f5e486aeb793`
- `storage-review-round4.md`: `93b8f82ab446b88f515aec917eef1a3da1ad32b4f35382a746243ac36c3f8a3a`
