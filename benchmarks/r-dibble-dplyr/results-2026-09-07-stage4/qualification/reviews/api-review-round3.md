# Stage 4 API, tests, documentation and attribution review, round 3

Reviewed working tree at 2026-09-07T02:57:07.350959+00:00, against `ec10a6ac34602f3bd691e8043019c1b479babda4`. Current HEAD remains the same base; this review includes uncommitted and untracked Stage 4 files. No package edits, builds, tests or timed workloads were performed by this reviewer.

The full review snapshot is `api-review-round3.diff`, SHA-256 `8e733b0998e0f388a9a43a2382dfee66cfa22ff1d0db73d9ad15e37e19c2c341`. It contains `git diff --binary BASE` followed by sorted untracked-file patches from `git diff --binary --no-index -- /dev/null PATH`. The tracked-only diff SHA-256 is `3322adb04a5c281e2fd9d40ae8f0d18e628028d0932a25d072758050d905e3ff`. `api-review-round3-identities.json` records per-file identities and tracked status. The complete per-file inventory appears below.

## Disposition

Three actionable API/documentation/qualification findings remain. The root-owned atomic operation, memory and Python qualification runners have no further actionable findings in this review. The separate native integer/factor runner still needs its requested oracle changes and its already planned source/output hardening. This is development review, not final Stage 4 acceptance or merge approval.

## Open findings

1. **Public documentation contradicts the new string ownership model.** `r-package/dtatools/R/dibble.R:50` still says ordinary strings are copied and checked against current values at each selector. That is the former Stage 3 behavior and conflicts with the immediately preceding atomic copy-on-write paragraph. State which owned types now share payload, how backing facts certify unchanged string declarations, and how borrowed/exposed input is handled. The ingress paragraph at line 91 should cover supported ordinary atoms too. Regenerate the corresponding manual page after the wording is corrected.

2. **The new general export matrix does not exercise the explicit write boundary.** In `test-owned-atoms.R`, the general export loop uses ordinary nested replacement for the source and export. Ordinary R replacement already copies and rebinds, so this cannot detect broken isolation in `replace_values()` for logical exports or for string data.frame/tibble/data.table exports. The separate as.character string loop covers only that one export. Use explicit writes on supported strings/logicals, keep factor replacement restrictions unchanged, mutate an actual exported data.table with `data.table::set()`, and check the current source as well as the selected sibling after exported-value mutation. Keep every returned alias alive through the next selector and both write directions.

3. **Native allocation profiles need an oracle after each operation.** `benchmarks/r-reference-mutation/owned-atoms.R` checks backing and counters immediately after the first shared write, but defers value/source checks until after the next private write. A wrong write in the first operation can therefore be overwritten by the second operation before the oracle runs. Check values, source/sibling preservation, column metadata, full table metadata and raw row names immediately after each of first_shared, subsequent_private and full_replacement, outside `Rprofmem`. Include table names/class and a custom table attribute, which are absent from the current guards. The current scalar full replacement correctly checks zero old-value copying, but also needs those fresh metadata and row-name guards.

All three findings were sent to the implementation parent during this review.

## Closed earlier findings and compatibility review

- Atomic staging now roots the exact row payload before a foreign replacement-length callback, and copies compact row descriptors. The focused regression detaches owned integer row backing, runs GC, and checks original row positions in string, double, compact generation and atom patching.
- Borrowed foreign fixtures explicitly require unowned ordinary storage before constructor, mutate, callback, bind_cols and cbind capture.
- Serialization versions 2 and 3 assert ordinary restored payload without a live owned record. The test correctly preserves `as_dibble(existing_dibble)` identity and uses ordinary result construction to prove recapture.
- Factor and ordered-factor tests retain public `replace_values()` rejection, verify ordinary replacement isolation, level/orderedness preservation and lower-level integer backing isolation. Expanding factor public mutation was not requested.
- The historical borrowed/stale-string fixture correction is justified. Public ingress now captures strings. The test installs a truly borrowed slot through the internal seam to continue exercising legacy/stale-input reconstruction, asserts unowned representation, preserves the original stale-width/missing/source-isolation checks, and separately verifies captured values survive a foreign write. It does not weaken recovery behavior.
- Writable pointer and string Set_elt tests check detachment, facts, exposure and future-fork isolation. Subset facts distinguish exact width from an upper bound; foreign index callbacks require rescanning. These changes preserve the intended R types and class names.
- No exported same-named verbs or incidental dependency declaration changes are present. NAMESPACE and DESCRIPTION are unchanged from the base. Later direct-expression/verb work and optional dplyr remain subsequent stages.

The source now also includes legacy `patch_vector` payload roots and copied compact replacement encodings. That is the fix for the separate storage review's latest finding. Its dedicated regression and final storage-review signoff remain required; this API review does not substitute for them.

## Benchmark review

Reviewed the actual atomic helpers, operation runner, memory runner, Python driver, synthetic guard tests, README and provenance-test changes. Deterministic ordinary vectors provide independent values/types/column metadata. Source preservation also checks attribute-name order and raw row names. Read/export results, allocation-profile results and bench's retained preflight results receive independent oracles. DTA/Arrow final writer files are reopened after profiling and timing. Source backing is observed before and after each read phase while aliases survive through the next selector.

The shared/private write cases change different rows. The reverse source write changes a fourth row, including a real logical transition. Selectors gate allocations and string scan counters independently. Memory cases distinguish retained vector heap from whole-process peak RSS and check flat handle depth and release after the last result. The Python driver checks all five sourced R dependencies plus its own committed bytes, uses explicit conditional exceptions under optimized Python, reserves new output directories and logs, verifies complete matrices and existing evidence hashes, and checks source bytes again afterward. Historical Stage 3 runner bytes and evidence remain unchanged.

The new native integer/factor runner covers the correct three kinds, two row scales and three write stages. Its sparse/full-copy budgets are consistent with the contract. At this snapshot its source/output hardening is explicitly still in progress: a git revision and file digests are recorded but no committed-byte guard binds the runner, output creation uses ordinary write calls after existence checks, and those checks are not yet integrated into the optimized rejection qualification. Treat any current output as development evidence until the planned hardening and review pass.

## Documentation, plan and attribution

ADR 0033 accurately distinguishes ordinary owned atomic backing from compact dictionaries and transient blank names. It preserves exact-versus-upper-bound facts, exposed-pointer rules, factor replacement restrictions, serialization fallback, row bounds and callback roots. ADR 0032 points to the extension while preserving the Stage 3 record. The progress document correctly keeps Stage 4 active, names the exact merged base and development-only evidence, and leaves Stages 5 through 9 and issue 172 open.

NOTICE identifies the exact R 4.6.1/SVN 90187 files studied for Stage 4 and explicitly says no implementation or tests were incorporated. The actual implementation generalizes package-owned Stage 3 code, with package-owned Rust descriptor lifetime code. No new upstream adaptation is apparent. Existing full dplyr, dtplyr and R copyright/license texts remain intact, and README acknowledges the new study at the bottom. Source archive, installed package and binary NOTICE checks remain required final evidence.

## Evidence inspected, not rerun

`atoms-6.log` ends with DONE and no failure/warning section. `full-working-6.log` contains exactly the five stale borrowed-string fixture failures that predate the fixture correction, plus the four already documented baseline warnings. This is not a passing complete-suite result for the corrected source. The source/installed archive checks, native/Rust checks, conformance/interoperability, roxygen, exact-source measurements and final CI/external review are still pending gates. No new-warning-free or Stage 4 performance acceptance claim is made here.

## Reviewed file identities

- `benchmarks/r-dibble-dplyr/README.md`: `153909beb7baba33d5ec179fcfb362f8355fac3a45b81bd54acdf85d5c96152c`
- `benchmarks/r-dibble-dplyr/owned-atomic-helpers.R` [untracked]: `4ea65133046e058f2bdf071417ed3c701a6ae98ec600e842dd14fde95ffa4ba1`
- `benchmarks/r-dibble-dplyr/owned-atomic-memory.R` [untracked]: `38f4aa25fe12193ec6c1860dfc85accbdd857e1afb207ab2867bc8cff3a966f2`
- `benchmarks/r-dibble-dplyr/owned-atomic.R` [untracked]: `1b86479434dac71c2354d120894f9deacf57bbb0887567630b4e5b2be80c3012`
- `benchmarks/r-dibble-dplyr/run-atomic-qualification.py` [untracked]: `37f1aae3c103f976acfdc2d2ad2f8cf5382fef98b38a36b5aa7c4e52511185a7`
- `benchmarks/r-dibble-dplyr/test-atomic-qualification.py` [untracked]: `21a88739a6c8cdf8b213da32ee3689f9e2ce057cf1db15bee7db1ef2407e866f`
- `benchmarks/r-dibble-dplyr/test-provenance.R`: `16f3f1bc2412795094e60c7c17e2e85161b4e4ade88cc431b168283e44120290`
- `benchmarks/r-reference-mutation/owned-atoms.R` [untracked]: `e5c6910d5250f5119c008ee478f7b62d9e902a521a90d71eea9f3fe0a0d81b0b`
- `docs/adr/0032-share-owned-double-backing-with-transactional-table-writes.md`: `4034ae55454416d3c895b2df1c2e336f686de1e8f0bf75e567e8cf3c7a9a1e94`
- `docs/adr/0033-share-owned-atomic-backing-and-storage-facts.md` [untracked]: `c940585e77f3e3b05399cbef9f0caa54f35e5f91ba6a60e5ca21ea6a87787bb6`
- `docs/plans/dibble-result-performance-progress.md`: `994b09f3771a54fd4887ef4b6cf8295c50a51598edc0482ad4ec1a875b59916f`
- `r-package/dtatools/R/dibble-result.R`: `20c86c603f7cd7300e9b7b06bb4fe1ba29a14b74e4192b67a6061b0bdc421fc7`
- `r-package/dtatools/R/dibble.R`: `8854a2b1c2df06f216c88d812dafc3d368abd2b63f7f54160cb48ecc491dd26b`
- `r-package/dtatools/R/dta-string.R`: `d51592fe87cb2c0374618d2beaec9994cc5c03c60b70b617408769cb782e9a03`
- `r-package/dtatools/R/mutate-data.R`: `337477c4dfbd67d1f1f9c758a7ac49ec2048d0f2ae727bf1f8880c1b7ed76bc0`
- `r-package/dtatools/README.md`: `289cf37339967cc4ee757c20994e3421e752ff042589410dde8363ba50e20d64`
- `r-package/dtatools/inst/NOTICE`: `3f19001559480e42ecfc7f6255afecbe9583977b6e7bd75b6ff076f22d8614e3`
- `r-package/dtatools/src/init.c`: `12a9e0801d38f497c3e52cb0734d807ff5725dd9c4a168976eaac4fecd80b1cd`
- `r-package/dtatools/src/mutation-write.h`: `d8e5f6abbe970c4ed12fb923fa55b76e6278e9c1072089356a7698f9cd8c489d`
- `r-package/dtatools/src/owned-columns.h`: `532db53277f893e124557812ce92e137778e8f7e71da126081f703fb6f7f4536`
- `r-package/dtatools/src/rust/src/lib.rs`: `ac116b61e69767be69ce95c2521a0880e907db16532b345ef477db95dfd93486`
- `r-package/dtatools/tests/testthat/test-dibble-columns.R`: `478051d7ebf835e57462c0cb0015279238bae963cad96c2ef002a3c4e15c737d`
- `r-package/dtatools/tests/testthat/test-owned-atoms.R` [untracked]: `37b4bc31a654409e976f1a10cffcb37594bdc04d49a24a9e414b0992abdf2bae`

## Inspected evidence identities

- `atoms-6.log`: `440e55fcf9f4a21417f88421ff10e9dea9d8bd9f8efec0c47aed305747d7a98d`
- `full-working-6.log`: `7685354ab0ebb9b152deb47d763c235f93bbab66c82fb8e78305439967eb97cb`
- `storage-review-round3.md`: `282984f96f061c30f02c2d14889ca7aae1d5a4ec3c2db14bc51045df88dddf64`
