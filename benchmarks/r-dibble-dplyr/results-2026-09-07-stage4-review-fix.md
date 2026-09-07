# Stage 4 review fix qualification, 2026-09-07

The fixed candidate passes the ownership, correctness, allocation and retained-heap gates. Its [indexed archive](results-2026-09-07-stage4-review-fix/README.md) preserves exact inputs, outputs and failed attempts. The fresh paired matrix retains the same twelve base-R element-read costs and three delegated-filter timing flags. Overall epic performance acceptance remains open; Stage 6 must resolve the filter paths.

Candidate `c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe`, package tree `f88005766aee9b9dd5827b33a3930feff6672008`, installed DLL MD5 `c655c59a09cbf1cd72a6f72e7e94758e`. Baseline `ec10a6ac34602f3bd691e8043019c1b479babda4`. Both sides use runner `c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe`. The two documented Python drivers have unchanged executable ASTs. All paired benchmark R workloads retain their original bytes; the separate native runner changed only its preflight.

Thirteen coordinated phases completed without concurrent agent builds, tests or probes. Both sides ran all 206 atomic operations, 126 after-read selector checks and 18 write checks; the double matrix ran 46 operations, 30 after-read checks, six writes and four capture profiles per side. Seven iterations were used for timings. Separate memory runs comprised 30 atomic and six double processes per side, plus 36 retained-heap processes per side. Every raw memory log and derived comparison is hash-checked. The [coordinator manifest](results-2026-09-07-stage4-review-fix/benchmark/qualification.json) binds commands and executed input bytes before and after each phase.

## Review fixes and reproductions

PR #195's substantive review found an incomplete output-directory guard and an
unnecessary full-payload copy on a fresh string constructor's first private
write. A separate comment identified temporary encoding buffers retained during
width scans. The [actual review](results-2026-09-07-stage4-review-fix/diagnosis/external-review/reviews.json)
and all reproductions are retained.

The public constructor builds callback-free, unnamed metadata on one unpublished
native handle after declaration normalization. It captures ordinary borrowed
values before changing metadata and preserves real sharing for existing owned
inputs. Names dispatch, prototypes, foreign readers and internal declarations
keep the established fallback. Independent review caught an early draft that
forced metadata promises before capture; the final path preserves their order.

| Native constructor measurement | `e343b3b` | `c8ca0a4` |
| --- | ---: | ---: |
| Initial capture at 100,000 elements | 800,000 bytes | 800,000 bytes |
| First private write at 100,000 elements | 800,000 bytes | 0 bytes |
| Initial capture at 1,000,000 elements | 8,000,000 bytes | 8,000,000 bytes |
| First private write at 1,000,000 elements | 8,000,000 bytes | 0 bytes |

The [independent constructor probe](results-2026-09-07-stage4-review-fix/diagnosis/root-probes-final/manifest.json)
also covers one element. It verifies stable candidate backing and complete
source/result values. These native payload counters do not measure total R
allocation or constructor time. Separate retained aliases still detach.

The width helper releases each temporary translation after computing its byte
count. Actual registered entry-point probes show no retained temporary marker
for one Latin-1 character or a 1,000-element Latin-1 vector. Width, missingness
and scan-count controls agree. ASCII, UTF-8 and byte-marked strings retain their
behavior. These probes measure lifetime, not allocation bytes, RSS or time.

The native runner rejects every nonempty destination before producing identity
or result files, including hidden files and empty child directories. Eight real
runner cases pass under default Python, `-O` and `PYTHONOPTIMIZE=1`. A synthetic
Git sentinel stops the admitted empty control before identity or measured work.
The complete 18-case native allocation runner also passes the new preflight.

Useful ownership, callback, temporary-memory and current runner documentation was
added. CodeRabbit could not provide the function inventory behind its advisory
20.15% docstring metric. The [retained response](results-2026-09-07-stage4-review-fix/diagnosis/external-review/docstring-scope-response-01.json)
is not a source-function list, and no threshold or review filter changed.

## Retained-column operations

Each table has one million rows and 16 columns. Each candidate rename below allocates 84,056 R bytes. Supported direct selectors and pipelines stay below one million allocated R bytes, with no repeated scans of unchanged strings.

| Column kind | Baseline rename, ms | Candidate rename, ms |
| --- | ---: | ---: |
| string | 137.036 | 0.604 |
| declared_character | 136.928 | 0.597 |
| logical | 1.808 | 0.480 |
| factor | 2.968 | 0.488 |
| ordered | 1.926 | 0.486 |

The direct five-operation column pipelines allocate 422,240 R bytes and take 2.691–3.377 ms. Equally safe delegated pipelines allocate 98,248 bytes and take 1.382–1.532 ms. Delegation remains faster in this case.

## Remaining timing findings

These are the same 15 cases as the earlier e343 confirmation. Each exceeds both 10 percent and one millisecond against the fresh baseline. No new flagged case appears. The double matrix has no flags. The [full comparison](results-2026-09-07-stage4-review-fix/benchmark/atomic-comparison/operation-comparison.csv) and [all flagged rows](results-2026-09-07-stage4-review-fix/benchmark/atomic-comparison/investigate.json) preserve unrounded values. These reads use one-million-row, eight-column inputs: element operations read one column, while filters return rows across all eight.

| Column kind | Read operation | Baseline, ms | Candidate, ms |
| --- | --- | ---: | ---: |
| declared_character | any_na | 0.287 | 2.627 |
| declared_character | nonmissing_count | 1.072 | 3.399 |
| logical | nonmissing_count | 1.017 | 3.204 |
| logical | coercion_character | 3.009 | 5.380 |
| logical | filter_half | 5.207 | 9.279 |
| logical | coercion_integer | 0.267 | 2.440 |
| logical | mean | 1.831 | 3.843 |
| factor | any_na | 0.251 | 2.436 |
| factor | nonmissing_count | 1.016 | 3.189 |
| factor | coercion_character | 2.244 | 4.394 |
| factor | filter_half | 4.918 | 8.190 |
| ordered | any_na | 0.252 | 2.434 |
| ordered | nonmissing_count | 1.015 | 3.210 |
| ordered | coercion_character | 2.446 | 4.425 |
| ordered | filter_half | 4.952 | 8.151 |

All twelve element-read/coercion flags have unchanged cumulative R allocation. Their measured extra cost is 1.979–2.370 ms per million elements. The three filters retain their Stage 6 owner and prior row-planning diagnosis. This source fix does not establish universal read parity or make those costs irreducible.

## Memory and integrated checks

Across all 36 candidate heap cases, retained R header/vector heap is 86,032 to 227,104 bytes; residual heap after dropping results is 57,936 to 209,776 bytes. Both stay below one million bytes. The [heap comparison](results-2026-09-07-stage4-review-fix/benchmark/heap-comparison/heap-comparison.csv) recomputes all five checkpoints from the 72 paired raw logs; the inferred header size is 56 bytes on this host. This excludes native allocation and process RSS.

Whole-process candidate peak RSS ranges from 190,513,152 to 1,133,461,504 bytes for atomic cases and 230,981,632 to 1,256,767,488 bytes for doubles. Those values include startup, fixture construction and validation; they are separate from operation allocation and retained heap.

The fresh artifact passes the original 159 native assertions plus 15 readiness checks, 18 supplemental native atom cases and the rename allocation gate. The complete installed R suite records 16,445 passing assertions, zero failed/error/skipped results and four established warnings. The standard package check retains three warnings and two notes. Loopback-dependent coverage was completed with authorized access, including Haven without skips. Fresh core checks pass 278 tests, bridge checks pass 18; the 11 existing Cargo package warnings remain disclosed. Source/binary archives, NOTICE, roxygen and interoperability checks pass. Root independently checked all 1,950 source blobs/modes and all 27 crate members. The [exact gate manifest](results-2026-09-07-stage4-review-fix/qualification/checks/exact-gates-manifest.json) and [independent audit](results-2026-09-07-stage4-review-fix/qualification/source/root-c8ca0a4-gate-audit.json) bind those results.

All 219 historical pure-R behavior comparisons and exact RDS results match. The fresh isolated-library fertility check matches its complete baseline log: 499 tests, four known failed/errored blocks and two skips, without a Column reallocation warning. All 454 project files, Git state and existing output size/mtime remain unchanged. This is strict parity for c8; the earlier e343 footer-mismatch attempts remain historical failures. It does not replace the final actual fertility renv install/test/restore.

Failed development and checker attempts remain preserved. Root corrected an integer-versus-double expected-count assertion in the constructor probe and a post-run parser that expected DLL_md5 where three historical fixtures print DLL. The latter audit rereads unchanged successful R outputs; it does not rewrite them or rerun their workloads. The original package fixture corrections and sandbox loopback skips are also recorded separately. The two root manifests also contain empty-hash self entries observed while their output was still open. A [separate completed-file audit](results-2026-09-07-stage4-review-fix/qualification/manifest-audit/c8ca0a4-manifest-self-entry-audit.json) verifies all 32 other file hashes and externally binds the completed manifests, without rewriting either. The summarizer had an initial pre-execution syntax error with no outputs; no malformed snapshot or error log was retained, and none is reconstructed.

Independent evidence review and latest-head substantive CodeRabbit, CI and normal merge remain separate gates. Stages 5 through 9, the final absence/presence/minimum/current/load-order matrix, final performance acceptance and the actual fertility renv restoration obligation remain open. Issue #172 stays open.
