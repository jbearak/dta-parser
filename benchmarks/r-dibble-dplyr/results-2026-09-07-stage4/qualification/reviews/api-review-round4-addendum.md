# Stage 4 API review, round 4 addendum

Reviewed at 2026-09-07T03:08:46.803857+00:00. This addendum preserves the original round 4 report and identities. It adds the subsequently edited string scan counters, repeated-anyNA test, ADR scan-scope wording and native qualification README. It also records the detailed review of the delayed callback helper and two legacy regression blocks, which were already included in the original round 4 snapshot.

Base: `ec10a6ac34602f3bd691e8043019c1b479babda4`. HEAD: `b259ad5a521dbb867a0b8563e3a0c2262e298671`. Combined tracked plus untracked diff SHA-256: `b2271b2e5ad4161cdb0342af1e9deac3815a7417feb3674f833a75dcfd2a54e4`. Exact full diff is `api-review-round4-addendum.diff`; file identities are in `api-review-round4-addendum-identities.json` and below. The combined diff uses the same tracked-plus-sorted-untracked procedure as round 4.

No additional actionable API, test-design, documentation or attribution finding. Original round 3 findings remain closed. No R process, test, build, behavioral probe or benchmark was run during the quiet window. Only source reads and review-artifact writes occurred.

## Additional reviewed source

The private delayed integer callback checks its own four-element state, skips only the requested matching element reads, and retains the existing one-shot disarm-before-evaluation behavior. Three-element callback states retain their prior behavior. The new registration remains internal; NAMESPACE is unchanged.

The legacy row test asserts ordinary/dictionary/materialized/compact target representations so it cannot silently exercise the owned-target shortcut. Its replacement-length callback detaches owned integer rows, runs GC, and checks one callback and the original row positions. The compact-replacement test delays its callback until after the two initial row reads, then materializes the replacement after its descriptor has been cached. It checks both compact and materialized targets, replacement values and changed representation. These cases address the reported legacy reader lifetime transitions.

The owned string missingness-only loop now increments the same pass and inspected-value counters as width scans. The cache-hit return precedes the increments, while the loop counts only values actually visited before an NA or completion. The new bare captured-string test expects one two-value pass on first anyNA and no additional pass on the repeat. This closes the observability gap where a missingness scan could previously hide behind zero width-scan counts. ADR 0033 now states that counter scope and keeps it separate from allocation-byte counters.

The native supplement README describes the three lower-level integer storage cases, row scales, unchanged allocation budgets, exact-source and DLL guards, independent oracles and distinct public factor restriction. Its scope agrees with the current runner. It does not substitute native factor writes for public factor behavior.

## Evidence boundary

The delayed callback helper, the two legacy tests and the new missingness-counter test have not executed yet. The earlier focused-7 log predates these additions and must not be cited as their passing evidence. The native supplement also still awaits a committed source and execution. These runtime checks, final storage review, full installed/archive checks and NOTICE evidence remain required. This clean source-review disposition is not Stage 4 acceptance.

## File identities

- `benchmarks/r-dibble-dplyr/README.md`: `94d93066b56e6abd3108ffb30dc264e04dd20ebfd888bab86aaaf4c4050aa8f1`
- `benchmarks/r-dibble-dplyr/owned-atomic-helpers.R`: `4ea65133046e058f2bdf071417ed3c701a6ae98ec600e842dd14fde95ffa4ba1`
- `benchmarks/r-dibble-dplyr/owned-atomic-memory.R`: `38f4aa25fe12193ec6c1860dfc85accbdd857e1afb207ab2867bc8cff3a966f2`
- `benchmarks/r-dibble-dplyr/owned-atomic.R`: `1b86479434dac71c2354d120894f9deacf57bbb0887567630b4e5b2be80c3012`
- `benchmarks/r-dibble-dplyr/run-atomic-qualification.py`: `37f1aae3c103f976acfdc2d2ad2f8cf5382fef98b38a36b5aa7c4e52511185a7`
- `benchmarks/r-dibble-dplyr/test-atomic-qualification.py`: `21a88739a6c8cdf8b213da32ee3689f9e2ce057cf1db15bee7db1ef2407e866f`
- `benchmarks/r-dibble-dplyr/test-provenance.R`: `16f3f1bc2412795094e60c7c17e2e85161b4e4ade88cc431b168283e44120290`
- `benchmarks/r-reference-mutation/README.md`: `05247604a53e97aad4263e1b26179f62f707e7cf99b9eeccc68322a073a876bf`
- `benchmarks/r-reference-mutation/owned-atoms.R` [untracked]: `e4faf3a23dfbf0a180321eeeec16c5312b27e6b535e26565ac8420e1a76b870b`
- `docs/adr/0032-share-owned-double-backing-with-transactional-table-writes.md`: `4034ae55454416d3c895b2df1c2e336f686de1e8f0bf75e567e8cf3c7a9a1e94`
- `docs/adr/0033-share-owned-atomic-backing-and-storage-facts.md` [untracked]: `86e5d59f60c21bdde6cd06f09719ecf32cccab0a14b4aeb4a8f23bdf70a0bff3`
- `docs/plans/dibble-result-performance-progress.md`: `53e463ddeeeccfa122eb30bc7482945cfa701caa7fc7e667a229a90db7302f8d`
- `r-package/dtatools/R/dibble-result.R`: `20c86c603f7cd7300e9b7b06bb4fe1ba29a14b74e4192b67a6061b0bdc421fc7`
- `r-package/dtatools/R/dibble.R`: `1ebfc62751b92804ef3906ac323ff0616ec1b5589b6e039424d32f5799ee7e1e`
- `r-package/dtatools/R/dta-string.R`: `d51592fe87cb2c0374618d2beaec9994cc5c03c60b70b617408769cb782e9a03`
- `r-package/dtatools/R/mutate-data.R`: `337477c4dfbd67d1f1f9c758a7ac49ec2048d0f2ae727bf1f8880c1b7ed76bc0`
- `r-package/dtatools/README.md`: `289cf37339967cc4ee757c20994e3421e752ff042589410dde8363ba50e20d64`
- `r-package/dtatools/inst/NOTICE`: `3f19001559480e42ecfc7f6255afecbe9583977b6e7bd75b6ff076f22d8614e3`
- `r-package/dtatools/man/dibble.Rd`: `edcfcb131f7ae581dca2e010282bf39c404ead5060fa25278d1b89852278f894`
- `r-package/dtatools/src/init.c`: `4af5b42c7e1ae4a088436cdeef91a9b7cef68b75eeb950bf0d82fc91b145d13d`
- `r-package/dtatools/src/mutation-write.h`: `d8e5f6abbe970c4ed12fb923fa55b76e6278e9c1072089356a7698f9cd8c489d`
- `r-package/dtatools/src/owned-columns.h`: `72e0a7a3c9cf45f7f95da3a0495509a732912e13199ac3598a1d33cd7dd99ab6`
- `r-package/dtatools/src/rust/src/lib.rs`: `ac116b61e69767be69ce95c2521a0880e907db16532b345ef477db95dfd93486`
- `r-package/dtatools/tests/testthat/test-dibble-columns.R`: `07a27397ecb617cb822255ca46d48cd2971ada75f1198244de66ced8e0848c90`
- `r-package/dtatools/tests/testthat/test-owned-atoms.R` [untracked]: `9f6c19946577e662739eada0c7a88b450795d9596649d30a2e4c1aa37409a6ac`
