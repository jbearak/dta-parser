# Stage 4 storage review, round 4

Reviewed at 2026-09-07T03:24:13.323772+00:00.

- Worktree: `/private/tmp/dta-direct-stage4`
- Branch: `codex/direct-dibble-owned-atoms`
- Git base: `ec10a6ac34602f3bd691e8043019c1b479babda4`
- Current HEAD: `b259ad5a521dbb867a0b8563e3a0c2262e298671`; package implementation and supplemental native runner remain working-tree changes.
- Full current diff SHA-256: `2706066274a87c134fd5cbf0f903c9c41b5731c4790d2ffaaf9f0df82d594894`
- Saved exact diff: `/private/tmp/dta-direct-stage4-validation/storage-review-round4.diff`

The diff is `git diff --binary BASE`, followed by sorted untracked-file patches from `git diff --binary --no-index -- /dev/null PATH`. Two initial captures matched around the per-file identity reads. The final evidence addendum rechecked every reviewed file hash unchanged and refreshed the full diff identity after the parent updated the progress document. The full diff includes documentation assigned to the separate API reviewer; the reviewed path list below identifies this storage/benchmark review scope.

## Disposition

No actionable correctness, storage-lifetime, alias, fact-cache or rollback finding remains in the reviewed source. The root atomic benchmark runners and supplemental native integer/factor runner are also source-review clean. This closes the round-3 legacy reader-lifetime finding and the additional callback-boundary findings discovered during round 4. Full required gates and exact-source allocation, timing and memory qualification remain pending; this is not Stage 4 acceptance or merge approval.

## Round-4 findings and fixes

1. Legacy `patch_vector` retained owned row and replacement addresses without rooting the exact allocation and used compact descriptors after callbacks could materialize their handles. The path now roots entry target state and both operand payloads, copies compact row/replacement encodings before callback exposure, and retains the exact dictionary descriptor/cache through the existing independent descriptor pin. The source regression covers ordinary, dictionary, materialized numeric and compact numeric targets, including a replacement Length callback that detaches owned integer rows and invokes GC.
2. Entry target state was captured after initial row callbacks, and compact target encoding was dereferenced after replacement Length without an intervening state check. Entry data1/data2 roots now precede all operand callbacks, and the initial state check precedes compact dereference. A second compact prevalidation check remains in place. The regression asserts a changed-state error with values intact when initial row or replacement Length callbacks materialize the target.
3. Foreign row or replacement element callbacks could run again during compact journaling or apply, after prevalidation, freeing the cached target descriptor or invalidating writable pointers. Unknown ALTREP operands are now copied once to protected ordinary vectors before native readers and transaction state are retained. Ordinary operands and admitted owned/compact/dictionary/metadata representations preserve their existing path. Admission uses actual native ALTREP identity through `reference_mutable_altrep`, not S3 class attributes. Current metadata constructors only wrap the admitted native representations or their ordinary decoded payloads. Protected staged rows, exact row payload and copied row encoding precede replacement staging. Delayed callback regressions show callbacks scheduled beyond the initial capture cannot reach journal/apply; immediate callbacks finish before readers are created. Existing injected after-write interruption and unwind rollback remain intact.
4. A foreign ALTSTRING used as the target's declared storage attribute can call R after transaction state has been saved. A final state check now follows `string_declared_width` and precedes `R_UnwindProtect`. It rejects target materialization before journaling or rollback can reuse the saved external pointer. The numeric malloc undo buffer is freed on this mismatch path; string transactions have no malloc undo. Source coverage includes a dictionary target materialized by the declared-width callback. The updated legacy PROTECT counts (6 before transaction state, 8 compact transaction, 14 vector transaction) balance on the reviewed returns.
5. The native integer/factor benchmark's former `original <- values` check shared the ordinary source vector and could mask a borrowed write. It now makes an independent serialized snapshot before native capture and derives expectations from that snapshot. It checks first shared and subsequent private writes, a distinct reverse alias mutation, unchanged sibling and full alias after full replacement, complete table attributes and raw row names, and zero old-value journal bytes for full replacement. Own-source/shared-helper identity is checked before and after execution.
6. Missingness-only native string validation is now counted per scan and per visited element. Cached no-NA returns do not increment either counter. The new private probe calls the public R No_NA entry points to exercise the registered native method directly; its regression checks one scan followed by a cache hit and separately checks `anyNA` semantics. This corrects the initial test assumption that this R build's `anyNA` dispatches through STRING_NO_NA.

The previously reviewed dictionary reference-count pin, callback-rooted generation and writer paths, consumed-row bounds, callback-dependent subset fact propagation, retained-pointer invalidation, Set_elt isolation and restored 2,048-column shape limit retain their round-3 disposition. The new descriptor pins do not mark payloads shared, and no newly discovered pin lifetime defect remains.

## Root benchmark fix review

The operation/read runner guards from round 3 remain intact: independent initial/profile/bench-retained-result oracles, final writer-file reopening, meaningful private and reverse-isolation writes, source backing checks with retained aliases, and attribute-name-order preservation. The Python driver checks its own bytes and all five sourced R dependencies, complete matrices, iteration counts and fresh/exclusive evidence paths; its rejection logic remains effective under Python optimization. The README now explicitly locates DTA warning collection/checking inside the measured writer wrapper for both revisions, while value and metadata oracles stay outside timing/profiling. No further benchmark finding.

## Evidence inspected and limits

- `focused-8.log` completed the focused suites and reported only two assertions from the original no-NA counter test assumption; no legacy callback regression failure was reported. That test now uses the native No_NA probe described above.
- `working-install-9.log` reports successful installation of the revised probe/test source.
- `bridge-tests-working-8.log` reports all 18 Rust bridge tests passing, including descriptor retention after original-owner release. Parent also reports format/check success.
- `full-working-9.log` now reports the full working suite completed with no failures; the parent records exit 0, four unchanged baseline warnings and no skips. `workspace-tests-working-9.log` records 278 Rust workspace tests passing. Parent records workspace fmt, clippy, documentation and package gates passing as well. These completed working-source gates precede the exact archived-source and native allocation/performance gates.
- Earlier evidence remains recorded in round 3: dictionary/atom tests, root development smoke, 87 synthetic driver guard cases and provenance rejection/counterchecks. Development evidence is not exact-source full-size qualification.

No builds, package tests, probes, timing workloads or source edits were performed by this reviewer, including during the root timed baseline quiet window. Work was limited to source/evidence reads and durable review artifacts.

## Reviewed file identities

- `r-package/dtatools/src/init.c`: `d2cc1924149be0c13138289bd4fcf9754402ada49ac6e7c2e06573d09d195c4a`
- `r-package/dtatools/src/mutation-write.h`: `d8e5f6abbe970c4ed12fb923fa55b76e6278e9c1072089356a7698f9cd8c489d`
- `r-package/dtatools/src/owned-columns.h`: `ece57105403f174edcb5dfef977df4b4a5bcc8a0b1105a7a54ecdffb967e6886`
- `r-package/dtatools/src/rust/src/lib.rs`: `bde26cc55f6f2e2d80e042dff915b2cd6367bfd600ddd93087b639e6bdcca0e8`
- `r-package/dtatools/tests/testthat/test-owned-atoms.R`: `90661e9a074f68b0e3731b6a57b58f8738a8244c68ee3b111dcf75ae6edf86bf`
- `r-package/dtatools/R/dibble-result.R`: `20c86c603f7cd7300e9b7b06bb4fe1ba29a14b74e4192b67a6061b0bdc421fc7`
- `r-package/dtatools/R/dibble.R`: `1ebfc62751b92804ef3906ac323ff0616ec1b5589b6e039424d32f5799ee7e1e`
- `r-package/dtatools/R/dta-string.R`: `d51592fe87cb2c0374618d2beaec9994cc5c03c60b70b617408769cb782e9a03`
- `r-package/dtatools/R/mutate-data.R`: `337477c4dfbd67d1f1f9c758a7ac49ec2048d0f2ae727bf1f8880c1b7ed76bc0`
- `docs/adr/0033-share-owned-atomic-backing-and-storage-facts.md`: `5f4d75c0ae2c41555e22247728ca8924ae642aba020b96c0901455b5e83ee2e2`
- `benchmarks/r-dibble-dplyr/owned-atomic-helpers.R`: `4ea65133046e058f2bdf071417ed3c701a6ae98ec600e842dd14fde95ffa4ba1`
- `benchmarks/r-dibble-dplyr/owned-atomic.R`: `1b86479434dac71c2354d120894f9deacf57bbb0887567630b4e5b2be80c3012`
- `benchmarks/r-dibble-dplyr/owned-atomic-memory.R`: `38f4aa25fe12193ec6c1860dfc85accbdd857e1afb207ab2867bc8cff3a966f2`
- `benchmarks/r-dibble-dplyr/run-atomic-qualification.py`: `37f1aae3c103f976acfdc2d2ad2f8cf5382fef98b38a36b5aa7c4e52511185a7`
- `benchmarks/r-dibble-dplyr/test-atomic-qualification.py`: `21a88739a6c8cdf8b213da32ee3689f9e2ce057cf1db15bee7db1ef2407e866f`
- `benchmarks/r-dibble-dplyr/test-provenance.R`: `16f3f1bc2412795094e60c7c17e2e85161b4e4ade88cc431b168283e44120290`
- `benchmarks/r-dibble-dplyr/README.md`: `94d93066b56e6abd3108ffb30dc264e04dd20ebfd888bab86aaaf4c4050aa8f1`
- `benchmarks/r-dibble-dplyr/owned-double-helpers.R`: `a6c5a83561a03401258aa5f0ebbd8dc494a1f8ac46fdc3f1d9fdd19c3dfd53c2`
- `benchmarks/r-dibble-dplyr/helpers.R`: `38be0d6709ba66af9307446c58dce5c6c953e3390da1c3d90258b8c727cf7219`
- `benchmarks/r-reference-mutation/owned-atoms.R`: `d1f278ffbffbaee0097be4f9a7cd4414f8c114a8c89cdf751f888b0daae10bef`
- `benchmarks/r-reference-mutation/README.md`: `05247604a53e97aad4263e1b26179f62f707e7cf99b9eeccc68322a073a876bf`
