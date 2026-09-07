# Stage 4 storage review, round 3

Reviewed at 2026-09-07T02:52:35.420955+00:00.

- Worktree: `/private/tmp/dta-direct-stage4`
- Branch: `codex/direct-dibble-owned-atoms`
- Git base: `ec10a6ac34602f3bd691e8043019c1b479babda4`
- Current HEAD: `ec10a6ac34602f3bd691e8043019c1b479babda4`; reviewed working tree includes uncommitted and untracked Stage 4 work.
- Full current diff SHA-256: `52443f4485b2eb170d81fb1ac7b58d72f06e82b73006790741dd3d1058f27d16`
- Saved exact diff: `/private/tmp/dta-direct-stage4-validation/storage-review-round3.diff`

The diff is `git diff --binary BASE`, followed by sorted untracked-file patches produced by `git diff --binary --no-index -- /dev/null PATH`. The per-file identities below cover the reviewed paths. Documentation outside the listed review scope may be included in the full diff identity; API/docs/attribution review is a separate assigned role.

## Disposition

Package source review still has one actionable lifetime finding. Root benchmark source review is clean. Full required gates and exact-source performance runs remain pending; this report is not stage acceptance or merge approval.

## Open finding

`src/init.c:patch_vector` still uses `reference_patch_rows_create` and cached numeric replacement readers without exact payload roots or copied compact row/replacement encodings for the complete legacy transaction lifetime. This path remains active for dictionary/materialized targets and ordinary direct-vector targets.

A foreign replacement callback can directly patch an owned integer row handle previously marked shared, detach its old payload, and run `gc()`. The cached `row_plan.integer_values` can then point at collected storage while validation, journaling, writing or rollback consumes later rows. Conversely, a foreign row callback can detach or materialize a cached numeric replacement during compact/materialized replacement validation. The new generation and staged numeric/atomic paths already retain their exact row allocation; the legacy path needs equivalent protection. Reported to the implementation parent during round 3. Regression coverage should retain the legacy path and callback/GC transition, rather than silently routing it into the newly staged owned-target path.

## Closed findings and reviewed fixes

1. Foreign index callbacks no longer propagate source string-width facts to owned subset results. Their facts remain unknown and require a scan. Ordinary and owned callback-free indices retain upper-bound propagation.
2. Generation and staged numeric/atomic row plans retain exact owned payloads and copied compact row descriptors. Consumed row positions are checked against the original row count, and by-row replacement offsets are checked against value count. These changes close the reported generation dangling-owned-row and out-of-bounds cases.
3. DTA numeric writer readers retain payload roots and copied compact descriptors. Arrow integer/logical/factor reads use read-only pointers and retain corresponding owned payloads.
4. Dictionary readers now retain an immutable Rust descriptor reference through an independent external-pointer root that also retains the exact cache. Materializing the original handle releases one reference without freeing a descriptor still pinned by subset, generation, atomic/legacy string reader, or writer code. The AtomicUsize field is appended after the C-readable prefix, preserving its layout. Retain overflow fails without changing the count, and final release frees indices and dictionary exactly once. No additional pin-protection defect found in this reviewed implementation.
5. The accidentally reduced physical-shape limit has returned to `MUTATION_SHAPE_NAME_SLOTS / 2`, preserving the 2,048-column domain.
6. Root's read runner validates initial results, allocation-profile results and bench's retained preflight results outside measured operations. It reopens final profiled and timed DTA/Arrow output files against the independent value/metadata oracle.
7. The private sparse measurement now changes row 3 after preparing privacy at row 1. The reverse source-isolation write changes row 4, including a real TRUE-to-FALSE transition for logicals.
8. Atomic source-preservation guards include column and table attribute-name order, independent values/types/attribute contents and raw row-name bookkeeping. Source backing is measured before and after read/export/profile/timing phases while returned aliases remain alive.

## Benchmark review

Reviewed the actual R helpers, operation runner, memory runner, Python qualification driver and synthetic CLI guard tests, benchmark README and extended provenance tests. No further actionable benchmark finding. The driver checks all five sourced R dependencies and its own committed bytes before and after work, uses explicit conditional exceptions under Python optimization, checks complete case matrices and timing iteration counts, reserves a new operation directory and creates logs exclusively. Existing evidence hashes and all memory log paths are checked before memory work. Memory output distinguishes retained vector heap from whole-process peak RSS and includes release/flat-depth guards. Factor fixtures intentionally exercise ordinary integer table backing because public dibble ingress promotes bare integers; public factor replace_values restrictions remain unchanged.

## Evidence inspected, not rerun

- `atoms-6.log`: atom-focused suite reports DONE.
- `working-install-6.log`: installation reports DONE with the already documented macOS object deployment-target linker warnings.
- `development-atomic-driver-guards.log`: 87 default/-O/PYTHONOPTIMIZE guard cases reported passing.
- `development-atomic-provenance.log`: 36 exact-diagnostic rejection/no-output cases, 9 usage counterchecks, matching CSV and dependency identities passed.
- Root's durable status records the working-install 8/40-row development smoke. These are not exact-source full-size performance measurements.

No builds, package tests, timing workloads or source edits were performed by this reviewer. Only source/evidence reads and this durable review artifact were produced.

## Reviewed file identities

- `r-package/dtatools/src/init.c`: `12a9e0801d38f497c3e52cb0734d807ff5725dd9c4a168976eaac4fecd80b1cd`
- `r-package/dtatools/src/mutation-write.h`: `d8e5f6abbe970c4ed12fb923fa55b76e6278e9c1072089356a7698f9cd8c489d`
- `r-package/dtatools/src/owned-columns.h`: `532db53277f893e124557812ce92e137778e8f7e71da126081f703fb6f7f4536`
- `r-package/dtatools/src/rust/src/lib.rs`: `ac116b61e69767be69ce95c2521a0880e907db16532b345ef477db95dfd93486`
- `r-package/dtatools/tests/testthat/test-owned-atoms.R`: `37b4bc31a654409e976f1a10cffcb37594bdc04d49a24a9e414b0992abdf2bae`
- `r-package/dtatools/R/dibble-result.R`: `20c86c603f7cd7300e9b7b06bb4fe1ba29a14b74e4192b67a6061b0bdc421fc7`
- `r-package/dtatools/R/dibble.R`: `8854a2b1c2df06f216c88d812dafc3d368abd2b63f7f54160cb48ecc491dd26b`
- `r-package/dtatools/R/dta-string.R`: `d51592fe87cb2c0374618d2beaec9994cc5c03c60b70b617408769cb782e9a03`
- `r-package/dtatools/R/mutate-data.R`: `337477c4dfbd67d1f1f9c758a7ac49ec2048d0f2ae727bf1f8880c1b7ed76bc0`
- `docs/adr/0033-share-owned-atomic-backing-and-storage-facts.md`: `c940585e77f3e3b05399cbef9f0caa54f35e5f91ba6a60e5ca21ea6a87787bb6`
- `benchmarks/r-dibble-dplyr/owned-atomic-helpers.R`: `4ea65133046e058f2bdf071417ed3c701a6ae98ec600e842dd14fde95ffa4ba1`
- `benchmarks/r-dibble-dplyr/owned-atomic.R`: `1b86479434dac71c2354d120894f9deacf57bbb0887567630b4e5b2be80c3012`
- `benchmarks/r-dibble-dplyr/owned-atomic-memory.R`: `38f4aa25fe12193ec6c1860dfc85accbdd857e1afb207ab2867bc8cff3a966f2`
- `benchmarks/r-dibble-dplyr/run-atomic-qualification.py`: `37f1aae3c103f976acfdc2d2ad2f8cf5382fef98b38a36b5aa7c4e52511185a7`
- `benchmarks/r-dibble-dplyr/test-atomic-qualification.py`: `21a88739a6c8cdf8b213da32ee3689f9e2ce057cf1db15bee7db1ef2407e866f`
- `benchmarks/r-dibble-dplyr/test-provenance.R`: `16f3f1bc2412795094e60c7c17e2e85161b4e4ade88cc431b168283e44120290`
- `benchmarks/r-dibble-dplyr/README.md`: `153909beb7baba33d5ec179fcfb362f8355fac3a45b81bd54acdf85d5c96152c`
- `benchmarks/r-dibble-dplyr/owned-double-helpers.R`: `a6c5a83561a03401258aa5f0ebbd8dc494a1f8ac46fdc3f1d9fdd19c3dfd53c2`
