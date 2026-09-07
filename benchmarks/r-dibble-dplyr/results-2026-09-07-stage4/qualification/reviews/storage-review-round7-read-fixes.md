# Stage 4 storage review, round 7 read fixes

Reviewed at 2026-09-07T04:29:13.932128+00:00.

- Worktree: `/private/tmp/dta-direct-stage4`
- Current HEAD: `ca6b678e5f173ebc6acf921520d7fa562de42bb9`
- Reviewed package diff base: `7d56080f3e97bc4d73a848e363d729767b9629c0`
- Logical Stage 4 base: `ec10a6ac34602f3bd691e8043019c1b479babda4`
- Measured initial candidate package tree: `82b95507e3ea9fe8b8658d7c2098b1f95f5c3756`
- Current package working diff SHA-256: `5fc80d52fcc4d85ac654ecbbacf637fda834e182be714513799df80ea93a094a`
- Saved exact package diff: `/private/tmp/dta-direct-stage4-validation/storage-review-round7-read-fixes.diff`
- Complete reviewed file identities: `/private/tmp/dta-direct-stage4-validation/storage-review-round7-read-fixes-identities.json`
- Identity document SHA-256: `a6caed012f16fd2c0eed221d0b86f9508a4edf2f75c82daf73f52df302dc32d2`

The saved diff is `git diff --binary 7d56080f3e97bc4d73a848e363d729767b9629c0 -- r-package/dtatools`. Two captures matched around the file-identity reads. This bounded review covers the eight changed package paths below and reads the corresponding ADR description for context. The root-owned initial benchmark report and evidence archive were reviewed separately in round 6 and its addendum.

## Disposition

No actionable correctness, storage-ownership, alias, callback, GC or mutation finding in the reviewed read-fix source. The reported owned-string Arrow callback defect is closed in source by retaining and reading the exact allocation. The borrowed-string constructor correction also establishes capture before metadata changes. This is a source-correctness disposition only. It does not accept residual performance, substitute for exact archived-source gates, approve a merge, or complete Stage 4.

## Storage and callback review

`owned_atomic_subset` now retains the source backing record and, for owned indices, the exact ordinary index allocation before using cached pointers. Ordinary index storage is rooted directly. The integer/logical fast path rejects nonpositive, missing and out-of-range indices before indexing, while the general loop retains the existing finite-range/truncation behavior for real indices. Character results still use `SET_STRING_ELT`, preserving R's write barrier. Foreign ALTREP indices retain their element callbacks and read order; their results do not inherit source facts that a callback could change. Source storage exposed to a retained pointer remains excluded from fact propagation. Protection counts balance, and every retained source/index address remains reachable through the loop and output adoption.

DTA string planning unwraps owned strings to a protected ordinary payload for its scan. It returns the tracked handle when strings already require no UTF-8 normalization, and keeps the existing copied normalization path for foreign ALTSTRING input or translated strings. Its temporary elements and normalized output retain the required protection. This change does not publish the ordinary backing as an untracked R result.

DTA and Arrow descriptors now read the exact string payload retained in their call-local roots, rather than following an owned handle after a later metadata callback changes its backing. The DTA root slot covers both its ordinary payload and the existing dictionary-pin branch. Arrow's existing root slot retains the same allocation that the descriptor reads. Dictionary inputs still use their independent immutable descriptor/cache pins; no new sharing-flag change or unrooted dictionary lifetime is introduced. Other native numeric readers and the existing compact encoding snapshots retain their prior behavior.

## Native adoption

The C/Rust adoption bridge now accepts completed ordinary real, integer, logical and character buffers through the common owned constructor. Each admitted allocation is native and unpublished. Arrow's `run_column_fills` consumes its fill jobs and completes all worker activity before `finalize_read_column` adopts the result. Null-bearing character columns complete their R-thread character fill before adoption. Factor levels and class move from the ordinary vector to the owned handle; later metadata is attached to that handle. The result guard retains the original allocation and the column guard retains the new handle until the result frame owns it. The bridge still contains R allocation failures through `R_ToplevelExec`, and Rust preservation/release remains balanced. Raw and compact dictionary paths retain their existing representations.

## String construction and metadata

Explicit string construction now captures ordinary or foreign character values before stripping an incoming class or other metadata. This capture is deliberately broader than generic table ingress because construction replaces the incoming class. Already owned, unexposed strings fork their tracked backing, exposed strings copy, and compact dictionaries retain their separate existing contract. Thus an ordinary data.table column or foreign metadata wrapper cannot become an untracked borrowed payload merely because its removable class was stripped before generic qualification.

The private attribute helper creates a separate owned handle and uses `Rf_setAttrib`; it does not change attributes on the incoming handle. Attribute-only changes preserve payload facts because they do not change values. Name arguments that are foreign or attributed decline the fast path. Names replacement on an object, or with a nonordinary/attributed replacement, also declines so the existing R setter performs dispatch and conversion. The R fallback and numeric metadata-restoration path preserve their previous behavior. New coverage checks custom names dispatch, both mutation directions after metadata forking, attributes with non-ASCII names, and constructor isolation from data.table writes at 64, 1,000 and 1,000,000 rows.

## Regression evidence and limits

`read-fixes-red.log` records the initial Arrow callback failure, with three `changed` strings written instead of `alpha`, `beta`, `alpha`; it also records the missing owned DTA-plan/Arrow-reader behavior targeted by the new tests. `string-unknown-constructor-working-13.log` records the failed unknown-class constructor value check that motivated capture before metadata replacement.

The new source tests exercise the later-metadata callback on owned string writer input, initially private public string writes during callbacks, DTA-plan backing retention, fresh logical/factor Arrow adoption, 63/64/1,000-row fact retention, names dispatch and large borrowed/unknown-class constructor isolation. The source preserves the existing callback, retained-pointer, dictionary, rollback and alias suites. `read-fixes-working-14.log` reports the owned-atoms suite completed without failures, and `working-install-14-capture.log` reports successful installation. These working-install logs are evidence inspected, not tests run by this reviewer and not exact-source full qualification.

No R processes, tests, builds, probes or timing workloads were run by this reviewer. No package, benchmark or root-owned source was edited. Review work was limited to actual source diffs, related call paths, existing evidence and these durable artifacts.

## Reviewed paths and SHA-256

- `r-package/dtatools/R/dta-numeric.R`: `58283825d778a1ef22f639c0a4295c1871da892bc969d5d24e44f8dd288dbff9`
- `r-package/dtatools/R/dta-string.R`: `35a5016265af8e202a30041b3f8d51e3976828e43a65188661f084d526b6ac49`
- `r-package/dtatools/inst/NOTICE`: `3c698aaef0c05e1e049142654af2fc29bf85da1fb0c42d2c3dadd5205e0e11f6`
- `r-package/dtatools/src/init.c`: `299beb275b34f2585733588cac217962af29efc5d44588d63950f47d09dfaa16`
- `r-package/dtatools/src/owned-columns.h`: `a337cea8c6d32da1322155c234ba40f3e9a7d7961bbad7e34afbcb87dd7178de`
- `r-package/dtatools/src/rust/src/arrow_ffi.rs`: `d9c295d7f808eb1bfd7d6e57381b1b10a10d9bd4873369ff375f2228897f2d8b`
- `r-package/dtatools/src/rust/src/lib.rs`: `593aa143a72c5e5492bb1289e39f6541805e846916b045bf81f4e2769bfe18e4`
- `r-package/dtatools/tests/testthat/test-owned-atoms.R`: `ced1d0b2404bb251cb2673f6aaec5bdea002ae1bc14f203c1eb24ae66bbbeb2f`
- `docs/adr/0033-share-owned-atomic-backing-and-storage-facts.md`: `e1e40ac6b903bd69bfafab2c8f32493f14a8a8a42a480c8353a5972ae48559b0`

## Evidence identities

- `read-fixes-red.log`: `59d7c68576f33706bbdd71da02ca80ea2ae45220abfc11300eba69c6346242f7`
- `string-unknown-constructor-working-13.log`: `d91852429c35859475fda22fc66534edf236f0beb7d68289bced03a1bcebda6c`
- `read-fixes-working-14.log`: `a6c258551fb004cea01052dc040ae638c02c110d20b7693086db316cc8fe0f44`
- `working-install-14-capture.log`: `69ba1176b25d74dc068d8f230e1f168162db2d40001e5bce77cb55194dc317a6`
