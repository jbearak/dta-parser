# Compact column facts: measured results

Cached column facts remove per-row range and missing-count reductions from admitted native kernels. On the retained million-row fixtures, mixed INT/FLOAT addition and multiplication improved by 1.46x and 1.54x over the qualified PR307 binary and ran faster than both DOUBLE controls. Dense FLOAT reciprocal improved by 1.22x, reaching 1.02x typed DOUBLE CPU and 1.06x bare R DOUBLE CPU. These measurements do not establish universal parity.

All panels used candidate DLL `e6e4c4edf80144803dcb556612ca86ca54b0c6568fc560c0c5ecc258fcd8bc13` and baseline DLL `cc084e97ba396766be2cdfd480f952dfd420ee92ae9f2adf9d1f7db86833072b`. The candidate build checkpoint is `fe74d4b5de0c9e4b7aaf9edcf8bf444e1c3c7db1`. The later merge of PR308 changed no qualified package files. Source, installed-package and command bindings accompany the raw records in this directory.

| Operation / fixture | Baseline ms | Candidate ms | Speedup | Compact / typed | Compact / bare |
|---|---:|---:|---:|---:|---:|
| INT/FLOAT sparse addition | 0.375 | 0.256 | 1.461 | 0.756 | 0.846 |
| INT/FLOAT sparse multiplication | 0.391 | 0.257 | 1.543 | 0.728 | 0.890 |
| INT clean reciprocal | 0.375 | 0.342 | 1.112 | 0.958 | 1.054 |
| INT sparse reciprocal | 0.451 | 0.456 | 1.015 | 1.319 | 1.568 |
| FLOAT clean reciprocal | 0.315 | 0.333 | 0.958 | 0.956 | 1.109 |
| FLOAT sparse reciprocal | 0.350 | 0.344 | 0.993 | 1.075 | 1.310 |
| FLOAT dense reciprocal | 0.474 | 0.378 | 1.220 | 1.021 | 1.059 |

Speedup is baseline compact CPU divided by candidate compact CPU. Compact/control ratios below one mean the compact operation used less CPU. Times are medians of CPU per call; ratios are medians of within-round ratios and need not equal ratios of the displayed time medians. Six alternating build pairs and rotating representation order produced 216 general and 36 dense observations. The typed-control baseline/candidate CPU ratios ranged from 0.974 to 1.083 in the general panel and were 1.007 in the dense panel; these are measurements with host variation, not statistical parity assertions.

Typed DOUBLE runs the package operation with its missing, metadata and storage rules. Bare R runs its double operation. In reverse division, bare R retains infinity for observed zero denominators; the package returns missing and maintains its missing cache. The dense fixture has 500,000 tagged-missing rows and 48 observed zeros. Package results therefore have 500,048 missing rows, while the bare control has 500,000 missing rows plus 48 infinities. Each representation passes its own value oracle.

Sparse integer reciprocal remains slower than both DOUBLE controls: 1.319x typed and 1.568x bare CPU. Its 1.015x measured speedup does not show a substantial additional gain. Clean FLOAT reciprocal measured 0.958x baseline speedup, and sparse FLOAT measured 0.993x; this change does not claim an improvement for those cases.

The architecture change records facts about final encoded bytes during native construction: an observed maximum magnitude, a nonzero observed minimum magnitude, and an exact zero count. Narrowing a tiny double into binary32 zero is accounted for. FLOAT tags remain distinguishable by a magnitude threshold. Pair kernels use conservative bounds once to prove FLOAT storage fit and omit the row-by-row maximum reduction. Reciprocal kernels can use complete-column bounds and disjoint missing/zero counts to dispatch a single writer with the required missing/zero mask, avoiding repeated preparation and count reductions.

Facts belong to captured immutable bytes. Retained clones preserve them; writable access and mutations invalidate them. Subspans retain conservative bounds but discard the exact zero-count flag. Endpoint ambiguity, unsafe lower bounds and unknown domains keep the existing exact fallback and promotion from original inputs. Generic, imported, gathered and restored columns remain UNKNOWN. This change does not populate reader facts or claim faster ingestion.

The separate construction panel measures the cost of recording these facts and using them once or five times on the same source. It includes constructor/result allocation, identical R list bookkeeping and automatic garbage collection. It has 72 qualified observations; it does not compare construction with bare R.

| Fixture | Constructor ratio | Constructor delta ms | Construct + 1 speedup | Construct + 5 speedup |
|---|---:|---:|---:|---:|
| Dense FLOAT | 0.9951 | -0.0625 | 1.0135 | 1.0374 |
| Sparse INT | 1.0258 | 0.2445 | 0.9869 | 1.0055 |

Constructor ratio is candidate/baseline CPU; delta is the median paired candidate-minus-baseline CPU difference. Workflow speedup includes construction and all one or five reverse divisions. Dense FLOAT construction showed no increase in these observations, but that does not prove facts are free. Sparse INT construction cost approximately 2.6% more, and its one-operation workflow was approximately 1.3% slower. Five-operation gains were modest: approximately 3.7% for dense FLOAT and 0.5% for sparse INT. The facts are not a general amortization or ingestion claim.

The focused installed-package replay passed 67,212 assertions in 77 blocks, with zero failures, errors, warnings or skips. Public tests cover encoded zeros/subnormals, tags, exact cache clearing, retained aliases, serialization and writable invalidation, endpoint storage selection, unsafe fallback and source changes during allocation. Actual-header probes passed 3,216 pair cases, 2,672 dense cases and 640 integer cases under four verified rounding modes. The span probe checks full and partial plain/retained extents. Their mocked R boundaries do not replace public ownership tests.

The descriptor ABI grew from 80 to 96 bytes on 64-bit targets. Qualification rebuilt all 41 C compilation units and the own Rust archive; the build took approximately 69 seconds. A cloned Rust target cache was provided, but Cargo still recompiled 60 external crates plus the two own crates. This is not a compiled Rust dependency cache hit. Installed R dependencies were reused without rebuilding. None of these local qualifications adds a GitHub R build, C++ scan or performance gate.
