# Storage review round 11: public logical subsets and nullable Arrow test

No actionable correctness, storage, alias, GC or callback finding was found in this bounded fix review. The nullable Arrow test correction strengthens the intended storage distinction; it does not remove its value or missingness oracle. No workloads, R processes, builds, tests or probes were executed by this reviewer. Performance acceptance and final Stage 4 qualification remain unresolved.

## Exact snapshot and reviewed paths

Captured `2026-09-07T05:56:59.438406+00:00` from `/private/tmp/dta-direct-stage4`, HEAD `ca6b678e5f173ebc6acf921520d7fa562de42bb9`. Package comparison base is `7d56080f3e97bc4d73a848e363d729767b9629c0`; logical Stage 4 base remains `ec10a6ac34602f3bd691e8043019c1b479babda4`.

- Exact package diff: `storage-review-round11-logical-arrow.diff`, SHA-256 `d58491b82038c1a11ef3c26a3521c4d351ae5f85f47d6e0c656b654f941cdffe`.
- Increment since the clean round 10 snapshot: `storage-review-round11-increment.diff`, SHA-256 `3a08ab057ac59d69812c2de7786813bc798772a6a20178228bb514b1271a1a0c`.
- Complete source copies and file identities: `storage-review-round11-snapshot/` and `storage-review-round11-snapshot.json`. No snapshotted file had changed at the end-of-review hash check.

Reviewed changed paths:

| Path | SHA-256 |
| --- | --- |
| `r-package/dtatools/src/owned-columns.h` | `6fc5e6c322476521e8fac9fe6bb5bfba7298283316604a5e1686d05216bf3f0d` |
| `r-package/dtatools/tests/testthat/test-owned-atoms.R` | `509b778b4127250eb69330063540c0b26657349c4f041b0e66bae22377156e4a` |
| `r-package/dtatools/tests/testthat/test-arrow.R` | `ced7425bf3ebd50d3d70f5951cb2606b58cd70e2491464ca60cada03e80e93a3` |
| `r-package/dtatools/src/rust/src/lib.rs` | `e2fa30dad4c852a018d7607dbb23a35dd78ff8348daa991ac06834ff018591dd` |
| `r-package/dtatools/inst/NOTICE` | `bea096dc51a83cdd85ccf29d6d59c80bafd5e4da4d6e19fcb4e05ae72bc19488` |
| `docs/adr/0033-share-owned-atomic-backing-and-storage-facts.md` | `a602b0d43970c8401153a86a5180e19de0d3db355f2397b3d5770bf2c386db0a` |
| `docs/plans/dibble-result-performance-progress.md` | `d2daeb89a113fb28a3a58ae4cf227f75de6785c74d3a924920038a850ace431e` |

Supporting nullable-reader source `r-package/dtatools/src/rust/src/arrow_ffi.rs` is unchanged at `d9c295d7f808eb1bfd7d6e57381b1b10a10d9bd4873369ff375f2228897f2d8b`. init.c, Makevars and the root heap supplement are unchanged from their earlier clean review scopes.

## Public logical subset disposition

The previous atomic gather loop is factored into `owned_atomic_gather(value, index, adopt)`. It still roots the source record and exact index payload, allocates a fresh same-type output, and uses the same index validation, padding, callback ordering and string write barrier. The sole ordinary-return branch releases the three existing protections and immediately returns that new allocation; it never returns or lends the source payload. There is no intervening allocation after the output is unprotected and before return.

Only the logical class's public Extract_subset callback chooses `adopt = 0`. Integer/factor and string public callbacks, the private C_owned_subset helper, and the all-qualified discrete batch continue to choose `adopt = 1`, including their earlier conservative facts propagation. The private batch still restores attributes explicitly. Public ordinary subset output relies on the same surrounding R subset attribute/name policy that applied to the prior newly adopted output. No new generic dispatch bypass, mutation step, record replacement or borrowed writable exposure is introduced.

The new regression covers named and unnamed owned logical sources, empty/repeated/NA positions, ordinary public result representation, exact equality to an independent ordinary subset including names, and owned private output. It also proves source writes cannot change a previously returned public result, result writes cannot change the source, and read-only subsetting does not detach source backing. The existing gather, foreign-index and pointer regressions remain active. Direct table gathering still produces owned buffers; later public ordinary subsets entering a table use the existing capture boundary.

The stored `logical-subset-working-19-red.log` shows the expected failure of the new ordinary-output assertion under DLL `79d08b06272c11ad9a575bb987569ce1`. `read-fixes-working-20-logical-subset.log` completes without failure. These are development evidence, not reviewer reruns.

## Nullable Arrow correction disposition

The fixture contains 100 values in each string column and 25 actual NA values in the nullable column. Reader classification checks actual chunk null counts. Null-free strings take the compact dictionary path. Null-bearing strings instead allocate STRSXP, explicitly write `R_NaString` for null entries and UTF-8 CHARSXPs for non-null entries, then adopt that completed ordinary allocation into an owned handle. This path was introduced and reviewed earlier; round 11 does not change its implementation.

The old assertion that the nullable result was not any ALTREP confused eager value decoding with ordinary public representation. The replacement now requires the non-null column to be an unmaterialized dictionary string and the nullable column not to be one. It additionally requires non-NULL owned info, flat depth 1, actual character type, identical missingness and unchanged whole-table `expect_identical(actual, data)`. That last assertion retains complete value/type/attribute parity. The revised assertions reject a nullable dictionary, a foreign wrapper, a plain unowned result, wrong type, wrong missingness or changed values. They do not silently bless a different missing-value encoding.

`full-working-20.log` has exactly one failure: the obsolete `.is_altrep(actual$m)` expectation. It also records the four reported baseline warnings. The subsequent `read-fixes-working-20-arrow-storage.log` completes the corrected Arrow test file without failure. The old full-suite failure remains preserved; a new whole-suite pass is not claimed here.

## Documentation, formatting and evidence limits

The Rust lib.rs change since round 10 is only the rustfmt line split of the same `adopt_atomic(...).map_err(...)` expression. NOTICE adds reference-study attribution for the discrete route and factor/logical ordinary temporaries. ADR accurately distinguishes public ordinary logical results from private adopted batches and retains the existing ingress, exposure and transaction rules.

The progress document explicitly records unresolved acceptance costs and the stale-object disclosure. Its working-20 logical mean 3.876 ms and ordered range 2.615 ms agree with stored development output (3.875607 and 2.614857 ms), which identifies DLL `2a5b211c95d9b6df22e8a0e4e822cc03`. These measurements are not a final paired comparison. Logical mean remains above the stated baseline, and no clean Stage 4 acceptance follows from this review.

Stored-log identities are recorded in `storage-review-round11-evidence-identities.json`. The bridge format/check/test manifest hashes agree with the stored logs and records exit 0 for all three; no commands were rerun. Final exact-source/native/full-matrix gates remain outside this bounded disposition.
