# Stage 4 review fix qualification, 2026-09-07

The fixed candidate passes the ownership, correctness, allocation and retained-heap gates. The fresh paired matrix retains the same twelve base-R element-read costs and three delegated-filter timing flags. Overall epic performance acceptance remains open; Stage 6 must resolve the filter paths.

Candidate `c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe`, package tree `f88005766aee9b9dd5827b33a3930feff6672008`, installed DLL MD5 `c655c59a09cbf1cd72a6f72e7e94758e`. Baseline `ec10a6ac34602f3bd691e8043019c1b479babda4`. Both sides use runner `c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe`. The two documented Python drivers have unchanged executable ASTs. All R workloads retain their original bytes.

Thirteen coordinated phases completed without concurrent agent builds, tests or probes. Both sides ran all 206 atomic operations, 126 after-read selector checks and 18 write checks; the double matrix ran 46 operations, 30 after-read checks, six writes and four capture profiles per side. Seven iterations were used for timings. Separate memory runs comprised 30 atomic and six double processes per side, plus 36 retained-heap processes per side. Every raw memory log and derived comparison is hash-checked.

## Retained-column operations

Each table has one million rows and 16 columns. Every rename below allocates 84,056 R bytes. Supported direct selectors and pipelines stay below one million allocated R bytes, with no repeated scans of unchanged strings.

| Column kind | Baseline rename, ms | Candidate rename, ms |
| --- | ---: | ---: |
| string | 137.036 | 0.604 |
| declared_character | 136.928 | 0.597 |
| logical | 1.808 | 0.480 |
| factor | 2.968 | 0.488 |
| ordered | 1.926 | 0.486 |

The direct five-operation column pipelines allocate 422,240 R bytes and take 2.691–3.377 ms. Equally safe delegated pipelines allocate 98,248 bytes and take 1.382–1.532 ms. Delegation remains faster in this case.

The independent constructor probe covers one, 100,000 and one million elements. Native counters record exactly one initial payload capture and zero additional capture on the first private write, with stable backing and unchanged borrowed input. The identical corrected probe fails on e343. Actual registered width-entry probes also release conversion temporaries for both the 1,000-element and single Latin-1-character cases. These are copy-counter and temporary-lifetime checks, not constructor timing or total R-allocation measurements.

## Remaining timing findings

These are the same 15 cases as the earlier e343 confirmation. Each exceeds both 10 percent and one millisecond against the fresh baseline. No new flagged case appears. The double matrix has no flags.

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

All twelve element-read/coercion flags have unchanged cumulative R allocation. The three filters retain their Stage 6 owner and prior row-planning diagnosis. This source fix does not establish universal read parity or make those costs irreducible.

## Memory and integrated checks

Across all 36 candidate heap cases, retained R header/vector heap is 86,032 to 227,104 bytes; residual heap after dropping results is 57,936 to 209,776 bytes. Both stay below one million bytes. All five checkpoints were recomputed from the 72 paired raw logs; the inferred header size is 56 bytes on this host. This excludes native allocation and process RSS.

Whole-process candidate peak RSS ranges from 190,513,152 to 1,133,461,504 bytes for atomic cases and 230,981,632 to 1,256,767,488 bytes for doubles. Those values include startup, fixture construction and validation; they are separate from operation allocation and retained heap.

The fresh artifact passes the original 159 native assertions plus 15 readiness checks, 18 supplemental native atom cases and the rename allocation gate. The complete installed R suite records 16,445 passing assertions, zero failed/error/skipped results and four established warnings. The standard package check retains three warnings and two notes. Loopback-dependent coverage was completed with authorized access, including Haven without skips. Fresh core checks pass 278 tests, bridge checks pass 18; the 11 existing Cargo package warnings remain disclosed. Source/binary archives, NOTICE, roxygen and interoperability checks pass. Root independently checked all 1,950 source blobs/modes and all 27 crate members.

All 219 historical pure-R behavior comparisons and exact RDS results match. The fresh isolated-library fertility check matches its complete baseline log: 499 tests, four known failed/errored blocks and two skips, without a Column reallocation warning. All 454 project files, Git state and existing output size/mtime remain unchanged. This is strict parity for c8; the earlier e343 footer-mismatch attempts remain historical failures. It does not replace the final actual fertility renv install/test/restore.

Failed development and checker attempts remain preserved. Root corrected an integer-versus-double expected-count assertion in the constructor probe and a post-run parser that expected DLL_md5 where three historical fixtures print DLL. The latter audit rereads unchanged successful R outputs; it does not rewrite them or rerun their workloads. The original package fixture corrections and sandbox loopback skips are also recorded separately.

Stages 5 through 9, the final absence/presence/minimum/current/load-order matrix, final performance acceptance and the actual fertility renv restoration obligation remain open. Issue #172 stays open.
