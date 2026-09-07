# Stage 4 API, tests, documentation and attribution review, round 4

Reviewed at 2026-09-07T03:06:13.943309+00:00 in `/private/tmp/dta-direct-stage4`, against `ec10a6ac34602f3bd691e8043019c1b479babda4`. HEAD is `b259ad5a521dbb867a0b8563e3a0c2262e298671`, the root-owned benchmark commit. Package changes and three new files remain uncommitted. The root-owned benchmark README clarification is included in this snapshot.

Full tracked plus untracked diff: `api-review-round4.diff`, SHA-256 `7af079ecc11be67db9b25ea66692bdc64fc437ece6c1b7fd2c098befc8b6382f`. Tracked-only diff SHA-256: `251fe4067f79f3a08cccc9bc0da9bdd4030d00b9b8ae778da213f34ea9b3e1cc`. The combined diff contains `git diff --binary BASE` followed by sorted untracked-file patches from `git diff --binary --no-index -- /dev/null PATH`. Per-file hashes and tracked status are saved in `api-review-round4-identities.json` and listed below. Source consistency was checked while creating the snapshot.

## Disposition

All three round 3 API findings are closed. No new actionable API, tests, documentation or attribution finding remains in the reviewed fixes. Native supplement execution, final installed/archive provenance, full required checks, performance qualification and external review remain acceptance gates. This source review does not claim those gates have passed.

This was read-only review during root's baseline timed window. The reviewer ran no R process, package tests, build, benchmark, behavioral probe or synthetic driver test. Only source/evidence reads and the durable review artifacts were produced.

## Reviewed fixes

1. `R/dibble.R` and `man/dibble.Rd` now agree that owned doubles, strings, logicals and integer/factor backing share values through independent metadata handles. The obsolete claim that ordinary strings are copied at each selector is gone. Borrowed capture, backing-fact reuse and conservative rechecking of unknown/exposed values are stated consistently. The ingress paragraph now covers supported atomic columns.

2. The general export test now uses `replace_values()` on supported string/logical source columns before mutating exported values. It checks the returned alias and selected sibling, freezes the changed source, and checks that source again after export mutation. The additional table-export matrix exercises data.frame/tibble explicit replacement and an actual `data.table::set()` write. Factors retain their documented public replacement restriction and ordinary replacement tests. This closes the missing explicit-write-boundary coverage without expanding the public API.

3. The native integer/factor/ordered-factor runner computes first-write, second-write and full-replacement expectations independently and validates values, source preservation, column attributes, table names/class/custom metadata and compact row names immediately after each profile. The first and second profiles change different rows. Oracle work stays outside Rprofmem. The runner explicitly rechecks backing/handle privacy after the first oracle and GC before measuring the second private write, so oracle reads cannot silently turn it into a shared-write measurement. Full replacement still checks zero overwritten-payload capture/copy and preserves the retained prior alias.

The native runner now binds its own file and directly sourced helpers.R to committed Git blobs before opening outputs, records SHA-256 identities, creates session/CSV files exclusively and validates installed package provenance before and after work. It has not executed yet because its new source remains uncommitted. Runtime execution and negative guard evidence remain required before those results can qualify the stage.

## Additional actual-diff checks

- The borrowed/stale-string fixture adds an address-identity assertion after native slot installation. Public captured values remain independently checked, and all previous stale-width/missing-repair assertions remain.
- The callback-length helper now protects its logical argument across allocation before calling the existing double callback constructor. No public function is added.
- Root's benchmark README now accurately discloses that expected DTA factor warning collection/checking occurs inside the measured writer wrapper in both revisions. Value/metadata oracles remain outside timing. This corrects the scope wording without changing runner bytes or historical measurements.
- The committed atomic helpers, operation/memory runners, qualification driver, synthetic tests and provenance checks are unchanged from the round 3 reviewed bytes. Their previous clean source-review disposition remains.
- ADR 0033, the ADR 0032 cross-reference, package README attribution and NOTICE remain consistent with flat owned storage, storage facts, writable-pointer exposure, serialization fallback, callback roots and package-owned dictionary pins. Existing complete upstream license/copyright texts remain intact. No new copied/adapted upstream portion is apparent.
- NAMESPACE and DESCRIPTION were compared byte-for-byte with the Stage 3 base and are unchanged. The progress document continues to identify Stage 4 as active and keeps later stages and issue 172 open. No optional-dplyr completion or final performance claim is made.

## Evidence inspected

`focused-7.log` contains the dibble-columns, mutate-data, owned-atoms, owned-columns and owned-reads focused suites and ends with DONE, without failure or warning sections. This is existing working-install evidence, not a reviewer rerun or an exact-source full-suite result. The earlier complete-suite log with five now-corrected borrowed-fixture failures is not relabeled as passing.

The native supplement and source/installed/binary NOTICE checks still need final execution evidence. Parent/root own the quiet-window measurements and broader qualification. Final storage review remains a separate gate.

## Reviewed file identities

- `benchmarks/r-dibble-dplyr/README.md`: `94d93066b56e6abd3108ffb30dc264e04dd20ebfd888bab86aaaf4c4050aa8f1`
- `benchmarks/r-dibble-dplyr/owned-atomic-helpers.R`: `4ea65133046e058f2bdf071417ed3c701a6ae98ec600e842dd14fde95ffa4ba1`
- `benchmarks/r-dibble-dplyr/owned-atomic-memory.R`: `38f4aa25fe12193ec6c1860dfc85accbdd857e1afb207ab2867bc8cff3a966f2`
- `benchmarks/r-dibble-dplyr/owned-atomic.R`: `1b86479434dac71c2354d120894f9deacf57bbb0887567630b4e5b2be80c3012`
- `benchmarks/r-dibble-dplyr/run-atomic-qualification.py`: `37f1aae3c103f976acfdc2d2ad2f8cf5382fef98b38a36b5aa7c4e52511185a7`
- `benchmarks/r-dibble-dplyr/test-atomic-qualification.py`: `21a88739a6c8cdf8b213da32ee3689f9e2ce057cf1db15bee7db1ef2407e866f`
- `benchmarks/r-dibble-dplyr/test-provenance.R`: `16f3f1bc2412795094e60c7c17e2e85161b4e4ade88cc431b168283e44120290`
- `benchmarks/r-reference-mutation/owned-atoms.R` [untracked]: `e4faf3a23dfbf0a180321eeeec16c5312b27e6b535e26565ac8420e1a76b870b`
- `docs/adr/0032-share-owned-double-backing-with-transactional-table-writes.md`: `4034ae55454416d3c895b2df1c2e336f686de1e8f0bf75e567e8cf3c7a9a1e94`
- `docs/adr/0033-share-owned-atomic-backing-and-storage-facts.md` [untracked]: `c940585e77f3e3b05399cbef9f0caa54f35e5f91ba6a60e5ca21ea6a87787bb6`
- `docs/plans/dibble-result-performance-progress.md`: `994b09f3771a54fd4887ef4b6cf8295c50a51598edc0482ad4ec1a875b59916f`
- `r-package/dtatools/R/dibble-result.R`: `20c86c603f7cd7300e9b7b06bb4fe1ba29a14b74e4192b67a6061b0bdc421fc7`
- `r-package/dtatools/R/dibble.R`: `1ebfc62751b92804ef3906ac323ff0616ec1b5589b6e039424d32f5799ee7e1e`
- `r-package/dtatools/R/dta-string.R`: `d51592fe87cb2c0374618d2beaec9994cc5c03c60b70b617408769cb782e9a03`
- `r-package/dtatools/R/mutate-data.R`: `337477c4dfbd67d1f1f9c758a7ac49ec2048d0f2ae727bf1f8880c1b7ed76bc0`
- `r-package/dtatools/README.md`: `289cf37339967cc4ee757c20994e3421e752ff042589410dde8363ba50e20d64`
- `r-package/dtatools/inst/NOTICE`: `3f19001559480e42ecfc7f6255afecbe9583977b6e7bd75b6ff076f22d8614e3`
- `r-package/dtatools/man/dibble.Rd`: `edcfcb131f7ae581dca2e010282bf39c404ead5060fa25278d1b89852278f894`
- `r-package/dtatools/src/init.c`: `4af5b42c7e1ae4a088436cdeef91a9b7cef68b75eeb950bf0d82fc91b145d13d`
- `r-package/dtatools/src/mutation-write.h`: `d8e5f6abbe970c4ed12fb923fa55b76e6278e9c1072089356a7698f9cd8c489d`
- `r-package/dtatools/src/owned-columns.h`: `2c4c56ce637cc6d647b5c2f710c7b79c0a94e9a89570244ed6437ffbf2624c03`
- `r-package/dtatools/src/rust/src/lib.rs`: `ac116b61e69767be69ce95c2521a0880e907db16532b345ef477db95dfd93486`
- `r-package/dtatools/tests/testthat/test-dibble-columns.R`: `07a27397ecb617cb822255ca46d48cd2971ada75f1198244de66ced8e0848c90`
- `r-package/dtatools/tests/testthat/test-owned-atoms.R` [untracked]: `ed0a81f7c2814fcd8d23fa04fe818490ce8f62e0166da2ce1c8ee4235dd572fc`

## Evidence identity

- `focused-7.log`: `250958a7e7b03d9428b323aec8c253bacba378832d6f90de0b41df01f65fcf27`
