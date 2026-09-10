# Direct dibble final integrated acceptance

Status: final functional checks, local integrated performance assessment and selected-evidence origin/transport verification are complete. The [evidence bundle](direct-dibble-final-evidence/README.md) supports the final CI and merge disposition for [#172](https://github.com/jbearak/dta-parser/issues/172).

This record follows the [nine-stage implementation plan](../plans/dibble-result-performance.md), the [stage history](../plans/dibble-result-performance-progress.md), the separate bracket feature, and the reader research. It records fresh checks of the resulting merged source. Earlier measurements retain their original source identities.

## Merged scope

| Stage | Delivered scope | Implementation PR | Verified normal merge |
| --- | --- | --- | --- |
| 1 | Shared result finalizer; direct select, rename and relocate | [#192](https://github.com/jbearak/dta-parser/pull/192) | `c8173b2af7105596f8a59e28e61a9bdd49fa8c3f` |
| 2 | Shared row gathering, grouping metadata and reconstruction | [#193](https://github.com/jbearak/dta-parser/pull/193) | `fd069a36832ed7c1bdedeed52a4281ecabb36e25` |
| 3 | Owned ordinary-double columns | [#194](https://github.com/jbearak/dta-parser/pull/194) | `ec10a6ac34602f3bd691e8043019c1b479babda4` |
| 4 | Owned string, logical and integer/factor columns | [#195](https://github.com/jbearak/dta-parser/pull/195) | `f622f1ddba04b2bb7ac07415faccf2b417aab0e6` |
| 5 | Expression engine; direct mutate, transmute and computed grouping | [#205](https://github.com/jbearak/dta-parser/pull/205) | `b2751d2dbf195557021cc5c5aa2d87a20cae69a7` |
| 6 | Direct filter, arrange, distinct and slice helpers | [#209](https://github.com/jbearak/dta-parser/pull/209) | `4d07d656dc95cd2cf5fae12c1dc08d6fae4f8d2c` |
| 7 | Direct summaries, group callbacks and nested results | [#212](https://github.com/jbearak/dta-parser/pull/212) | `af0bed0b9c200f82d37891902266d200a1819196` |
| 8 | Join assembly, base binding and reconstruction integration | [#214](https://github.com/jbearak/dta-parser/pull/214) | `7a7aa79228dd00e263f9d425406ea1b884df05dc` |
| 9 | Independent recoding, optional dplyr, native installation and CI | [#217](https://github.com/jbearak/dta-parser/pull/217) | `e3843a13dd867b05d8a98457cf2edc12f6331eeb` |

The separate Stage 9 evidence PR [#218](https://github.com/jbearak/dta-parser/pull/218) merged as `eb9828a4c15ee9417581df55a0d5112146b515af`. The [Stage 9 evidence](stage9-evidence/README.md) retains the full local R/dependency matrix, final binary gate, hosted platform results, earlier failures and their corrections.

Bracket feature [#213](https://github.com/jbearak/dta-parser/issues/213) was completed by PR [#220](https://github.com/jbearak/dta-parser/pull/220), merged as `de83bcbbeca9771dacf6e91fe727d2a228172d64`. Ordinary two-dimensional reads support column predicates and ordered `.()` selection. Lone programmatic indices still use caller lookup; compound expressions use columns first, with `.env` as the caller escape. Assignment and stored language values retain their established behavior. The acknowledged cost of preparing a read mask for call-valued indices remains part of the final width/storage comparison below.

Reader research [#216](https://github.com/jbearak/dta-parser/issues/216) was completed by PR [#221](https://github.com/jbearak/dta-parser/pull/221), merged as `4c2d1f9c2683c15345bb06294ff5fe2d55980f51`. Its [report](read-dta-construction-and-deferred-decoding.md) and selected evidence distinguish public baseline measurements, direct-constructor experiments, native phase instrumentation and a private deferred numeric prototype. They do not introduce that prototype into the released package.

The research merge has parents `e75518730db2d37d41ab8fb5aa44ab5c5c5f025c` and reviewed head `5376340a5682abc9b740e8a2654abb4642076572`; its full tree matches the reviewed head. All 17 CI jobs passed. The final package includes independently merged PR [#219](https://github.com/jbearak/dta-parser/pull/219). Its Raven metadata/tests are included in the fresh counts below. The research measurements themselves remain attributed to `de83bcbb`, before that addition.

## Fresh final source and functional checks

All checks in this section use merged source `4c2d1f9c2683c15345bb06294ff5fe2d55980f51`, package tree `abc1117250e874353d3cc4fe90f2d8e770b25558`, and separate fresh installations for the present and native gates. The initial installer completed all seven commands. Independent verification checked all 350 recorded products, the exact 57 installed files and all 266 exported package files against Git. The native coordinator separately installed the isolated source archive with tests, producing the 127-file installation recorded below.

| Gate | Actual completed result |
| --- | --- |
| Full optional-dplyr-present suite | 1,166 blocks; 20,555 passing assertions; six established warnings; zero failed expectations, errors or skips |
| Physical native-only host source build | Four steps returned zero, including before/after dependency probes and source archive validation |
| Physical native-only host installation and full tests | All ten families and 1,166 blocks completed; 15,335 passing assertions; three established warnings; 201 exact optional-dplyr skips; zero failed expectations or errors |
| Native installed help examples | All 27 executable topics completed without warnings; all 38 Rd topics inventoried and generated source/installed example code matched |
| Native process boundaries | Eleven declared children, two actual interruption forks and 150 library guards completed successfully |
| Package and conformance driver | All 16 commands returned zero, including interoperability, documentation generation, source/archive checks, conformance, R CMD check and binary packaging |
| Installed and packaged attribution | NOTICE bytes match the exported source, fresh installation, binary installation, source archive and binary archive |

The native run used disjoint mandatory/test libraries. Its fresh observations found none of dplyr, labelled, dtplyr, tidyr or haven in visible package membership or loaded namespaces. All 201 skips have the exact expected dplyr-unavailable reason. There were no Arrow, profiling or operating-system capability skips on this host. The 91 native and 59 example guards cover the declared observation boundaries; they are not a claim about every image loaded by the operating system.

The child count includes eight synchronous children, two background children and one Rscript child. Both fork records describe actual collected children with the intended interruption targets. The example runner executes `\donttest` examples and leaves `\dontrun` examples unexecuted. The final manifest preserves all 106 public exports and records the complete native suite; final membership is checked against this source.

Relative to the accepted #213 full suites, 1,161 existing blocks have identical outcome fields. Four Raven loops contribute 85 additional passes and one new constructor block contributes seven. This accounts for the exact increase of 92 assertions in both present and native runs. All earlier comparisons retain their original identities.

The present suite's six warnings and the native suite's three warnings match their preceding qualified conditions. Independent package review confirms the same three warning and two note categories as #213: deployment-target mismatches in 28 zstd objects, GNU extensions in three vendored Makefiles, the Rust abort symbol, the chrono citation file and a generated zstd file's final newline. Tests and examples pass; a PDF manual is outside the `--no-manual` check's scope.

The retained installation log has 22 nested Apple `nm` errors from an LLVM attribute-version mismatch, three members without symbols and status 1. Successful installation does not establish a complete successful symbol scan. Separate Haven conformance retains one loopback-server capability skip. Actual conformance executes 22 TypeScript fixtures with 32,085 cell comparisons and eleven Rust cases; 44 discovered names are not 44 executions or a full Rust suite. Roxygen leaves all 38 Rd files and NAMESPACE byte-identical to the committed export.

Independent current identity checks found all 12,997 package products and all 64,864 bound package input records unchanged. The native chain separately verifies all 26 outer, 28 coordinator and 362 native input records, six before/after tree inventories and the exact 127-file installation used for source-with-tests qualification. These are selected filesystem and execution records, not a whole-host reproducibility claim.

| Artifact | SHA-256 |
| --- | --- |
| Fresh installer receipt | `496da6bd9688e232007da2fb5b8877bef82b72a46ae20ccf6d6ca2a9b93baea5` |
| Isolated native source archive | `02c18c085afa0986a25d4bfd402246a2b24ae0c39c2cd54e0b2629b0e4802f6b` |
| Package-gate source archive | `87a6add312c284c6693fb9ce29affb7c47304be96a1f1962516f68b80ad36a90` |
| Package-gate binary archive | `f934e5a66eece460e4420cc5ff58fde5135fdfab23102bcc56a7b33f64c39890` |

The binary archive was built and installed by the package gate. The fresh full physical-absence execution above used the separately recorded source archive. Historical Stage 9 full binary-native results keep their historical identity.

## Final performance assessment

The measurement window began after installation, functional/package work, downstream lifecycle work and required broad filesystem checks had stopped. Excluded setup pilots do not enter final comparisons. Coordinated agent quiet does not establish exclusive use of the host.

The reviewed workloads below measure final source `4c2d1f9c2683c15345bb06294ff5fe2d55980f51` with fresh installer receipt `496da6bd`. Broad, row, group and join gates use fixed runner/helpers `f3b8b984c6a9ea5a0f062eee70e392bb567e5042`; bracket has its separately frozen worker. The targeted pipeline uses its own bounded worker `cd153ceb` and helpers bound to final source. Different predecessors and benchmark routes remain separate comparisons.

| Reviewed workload | Predecessor source | Actual result |
| --- | --- | --- |
| Broad atomic/double operations | `ec10a6ac34602f3bd691e8043019c1b479babda4` | 252 cross-build pairs; the same twelve million-row atomic read cases jointly flag; zero double flags. Four final direct-versus-safe pipeline comparisons also flag. |
| Broad selectors and memory | Same ec10 predecessor | All existing candidate selector, copy/scan and memory budgets pass; 36 memory pairs and 36 separately checked tracked-heap pairs reconcile. |
| Row operations | `235b6354f9b1f5878417255d3a20bc6501e69035` | 528 series and 3,696 raw samples; zero joint timing flags across 396 relations. All 132 final public medians are lower than predecessor public medians. |
| Group summaries and nesting | `4d07d656dc95cd2cf5fae12c1dc08d6fae4f8d2c` | 162 series, 1,134 raw samples and 108 comparisons; zero joint flags, with slower medians and nesting allocation increases retained. |
| High-cardinality nesting | Same 4d07 predecessor | Twelve series and 84 raw samples; four timing flags against old public, zero against the fixed safe reference. The predecessor public route has the documented foreign-write defect. |
| Bracket width/storage repeats | Same ec10 predecessor as the broad gate | Three complete pairs, 108 cases per build and 4,536 raw warm timings. Original 16 cross-build and one within-candidate flags recur in neither additional pair; signed costs and allocation overhead remain. |
| Selector-pipeline repeats | Same final installation's safe route | Three processes, 24 series and 168 raw samples; all twelve comparisons reproduce the route cost. |
| Joins and binding | `af0bed0b9c200f82d37891902266d200a1819196` | 180 series, 1,260 raw samples and 120 comparisons; five flags against fixed safe, zero against old public. All three targeted pairs retain four bind_cols flags; the row-bind flag does not recur. |

The strict timing flag requires both an increase above 1 ms and a ratio above 1.1. The twelve broad read flags retain candidate excesses of 1.699–2.383 ms and ratios of 1.644–9.726. The four same-install pipeline flags cover string and declared-character inputs at 100,000 and 1,000,000 rows: direct exceeds safe delegation by 1.175–1.485 ms, or 1.846–2.049 times. Those pipelines improve over ec10; the route findings are a separate safe-delegation obligation, not new cross-build regressions. Their completed targeted repeats are reported below. Complete signed comparisons, including unflagged slower rows, are retained.

Direct rename/select/relocate has no cross-build joint flags. Its largest recorded R allocation is 91,168 bytes; post-read selectors reach 82,912 bytes, with the existing zero-copy and string-scan guards satisfied. Pipeline allocation is outside those selector-only assertions. Candidate retained vector heap is 81,368–90,728 bytes, with signed post-drop excess of -87,696 to -55,720 bytes. The separate tracked-header-plus-vector calculation yields 84,240–114,960 retained bytes and 3,288–76,120 post-drop excess bytes. All existing budgets pass. Whole-child RSS includes startup, fixtures and validation and is not interchangeable with retained heap, cumulative R allocation or native counters.

The original broad coordinator remains failed: all ten measurement phases and the atomic/double comparisons completed, but its final heap comparator rejected the configuration schema. A separately reviewed comparator with the one-literal schema correction returned zero against the same completed records. Both the original failure and the successful correction remain. The 257-product manifest is unchanged. Broad timing files retain medians, allocation totals and iteration/GC counts for seven GC-inclusive iterations, not raw timing vectors. Atomic timed results are checked; double uses separate functional validation with timed checking disabled. These data do not support raw-sample uncertainty claims.

The row suite contains 132 comparisons for each of final public versus predecessor public, final public versus same-install safe, and final safe versus predecessor safe. None crosses both thresholds. Final public improves by 0.029–15.058 ms against predecessor public. Four public medians exceed their same-install safe counterparts, but by at most 0.028 ms and a ratio of 1.019. Allocation is not uniformly lower: warmed R and bench allocation increase in 20 of 132 predecessor-public comparisons, by up to 8,402,200 bytes for factor arrange at one million rows and eight columns. All signed allocation fields remain available; allocation is not retained memory.

The row review recomputes all 1,056 first/warm allocation profiles, 50,688 source-state column records and 44 isolation directions per build. The isolation fixtures are fresh 16-row logical tables, not a complete storage-type isolation suite. Timings follow profiling and validation, retain GC iterations, alternate route order and use seven samples per series. Two row sizes and two widths do not establish statistical significance or asymptotic complexity. Value and metadata claims rely on the source-bound producer assertions; the saved-data review does not rerun them.

The groups matrix compares 54 final public shapes with both predecessor public and fixed-safe routes. Eight final medians exceed each reference, despite no joint flags: the largest increases are 46.066 ms against public and 56.311 ms against safe, both for wide summarise with 100,000 rows, 16 payload columns and 128 groups. Their ratios remain below 1.1. Warmed R allocation increases in 18 nesting cells against old public, by up to 36,297,176 bytes, and in 14 nesting cells against safe, by up to 27,839,264 bytes. These absolute costs remain reported rather than being hidden by the timing threshold.

The high-cardinality cases use two rows per group, one payload column and an integer key. All four old-public flags remain:

| Groups | Operation | Final median ms | Ratio to old public | Ratio to fixed safe |
| --- | --- | ---: | ---: | ---: |
| 1,024 | group_nest | 68.953 | 1.770 | 0.375 |
| 1,024 | nest_by | 70.655 | 1.739 | 0.373 |
| 4,096 | group_nest | 303.294 | 2.025 | 0.426 |
| 4,096 | nest_by | 318.376 | 1.947 | 0.433 |

The old public route has the previously demonstrated foreign-write defect; the fixed safe reference enforces the stronger publication contract. That distinction does not erase the four old-public latency flags, and no foreign-write workload was repeated here. Candidate warmed allocation is 2.144–21.435 times old public and 0.00749–0.00978 times fixed safe. Increasing group count and row count fourfold gives candidate allocation ratios of 3.630 for group_nest and 3.681 for nest_by. Those are within-build scaling observations, not candidate/predecessor allocation ratios or asymptotic bounds.

Independent group review reads every raw timing and scalar-state CSV, including 274,176 state rows. It links all 324 allocation profiles to the accepted assessor and independently reparses 24 selected profiles; it does not repeat the full 515 MB profile sweep. High-cardinality review recomputes all twelve warmed profiles and eight schema pairs. Scalar states and schemas do not independently prove alias isolation, full values, retained memory or RSS. Producer validation and observers precede timing, so these are not cold-process or unread-source measurements. All 528 selected review inputs were unchanged at review completion; a new full package/runtime inventory is outside that review's scope.

The bracket repeats preserve the original case grid and alter only output paths and the declared build order. All 324 signed cross-build and 324 within-build comparisons remain separate:

| Bracket pair | Build order | Cross-build higher / lower | Cross-build flags | Final literal higher / lower than precomputed | Within-final flags |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | Baseline, then final | 67 / 41 | 16 | 46 / 8 | 1 |
| 2 | Final, then baseline | 37 / 71 | 0 | 48 / 6 | 0 |
| 3 | Baseline, then final | 40 / 68 | 0 | 47 / 7 | 0 |

The sixteen original flags are 1,024-column numeric cases. Their signed final-minus-baseline deltas are +1.200–+1.844 ms in pair 1, -0.339–+0.518 ms in pair 2 and -0.264–+0.812 ms in pair 3. These observations do not establish why the first pair differed or support treating its flags as repeatable final elapsed regressions. Allocation differences recur in every pair: +37,104 warmed Rprofmem bytes for precomputed indices and +45,344 for literal indices. Both routes are affected, and the ec10-to-final comparison spans multiple implementation stages, so this does not isolate #213's effect.

The original within-final string case—30,000 rows, 128 columns, negative literal index—remains slower than precomputed in all three pairs: +3.034 ms/10.88%, +1.788 ms/6.30% and +2.251 ms/7.99%. Only the first pair crosses both thresholds; the warmed allocation difference remains +1,072 bytes. Across the full final grid, 39 of 54 literal-route medians are higher in every pair and three are lower in every pair. The 1,024-column numeric literal penalties remain about 0.26–0.62 ms, with +8,240 or +9,488 warmed Rprofmem bytes depending on the index. Logical literal cases can include timed index construction: these are whole-call route comparisons, not isolated mask timings.

First-pair scalar records show unchanged source handles/backing, double depth one, compact-integer depth zero and string depths zero/one in baseline/final. Those fields do not identify explicit ALTREP classes or measure retained memory. The additional pairs complete the repeat investigation while preserving the measured signed costs and source-level optimization candidates. No pooled estimate replaces individual pairs, and lack of recurring joint flags does not establish zero cost, unavoidable overhead or overall acceptance.

All twelve targeted selector-pipeline comparisons reproduce the same-install cost: +1.107–1.256 ms, ratios 1.752–1.930. Direct medians are 2.512–2.621 ms; safe medians are 1.339–1.471 ms. Profiled R allocation is 424,720 bytes, except 451,824 in each process's first string case, versus 97,968 for safe. Those profile totals are distinct from warmed bench allocations. All 24 profile validation-scanned-value counters are zero; the worker does not establish that stronger claim for every timed batch. At fixed sixteen columns, tenfold rows give direct timing ratios 0.972–1.016 without a profile-allocation increase.

The pipeline performs rename, select, relocate, mutate from c02 and rename back. Source inspection finds a result context and publication boundary for each direct result; the recorded safe route takes one source snapshot and closes once after operating on the ordinary frame. That supports investigating repeated planning/metadata/publication work, not assigning an isolated measured cost to each function. The cost remains reported, without an irreducibility claim or an optimization that bypasses validation, ownership, grouping or callbacks. Repeats keep direct-then-safe order and omit the broad process's preceding selector history; their medians are not pooled with the broad results. The qualified audit checks 48,308 inputs, 24 raw series and 192 initial scalar states; independent review rechecks its selected result/source links and exported arithmetic rather than repeating the raw RDS audit.

The joins/binding grid compares 60 final public shapes with both predecessor public and fixed-safe routes. Its five joint flags are all against fixed safe:

| Operation | Rows | Payload width | Final median ms | Final minus safe ms | Ratio to safe |
| --- | ---: | ---: | ---: | ---: | ---: |
| bind_rows_wide | 100,000 | 8 | 48.773 | +4.975 | 1.114 |
| bind_cols | 100,000 | 8 | 1.451 | +1.188 | 5.516 |
| bind_cols | 1,000,000 | 8 | 1.483 | +1.221 | 5.655 |
| bind_cols | 100,000 | 16 | 1.485 | +1.142 | 4.327 |
| bind_cols | 1,000,000 | 16 | 1.637 | +1.298 | 4.827 |

Each reference comparison also has eighteen positive median deltas. The largest are +14.397 ms against public base_rbind and +19.906 ms against safe rows_update, both below the ratio threshold. Warmed R allocation increases in 52 of 60 public comparisons and 58 of 60 safe comparisons; the largest increases are 16,004,096 and 16,005,080 bytes for cross_four despite faster elapsed times. bind_cols records 664,232/670,672 bytes at widths eight/sixteen, exceeding safe by 580,272/582,992 bytes while its listed native counters remain zero. The flagged wide row-bind adds 402,520 R bytes; its owned-capture observation matches the reference. These are cumulative allocation observations, not retained-memory or isolated-cause measurements.

Join review reads all 1,260 raw times and 59,880 scalar state records. It links all 360 profiles to the accepted assessor and independently reparses the twenty first/warm profiles for the five flagged shapes on final and safe routes. Nested scalar states cover first and last children; full value/group/schema assertions remain source-bound producer evidence. Reported source exposures and all signed scaling/counter fields remain visible. The completed bounded repeat investigation is reported below.

Three restricted binding pairs preserve the original route/shape order and use baseline/candidate, candidate/baseline, then baseline/candidate process order. All six corrected jobs and their readers/comparators complete: 45 series, 315 raw samples, 90 first/warm profiles, 14,238 scalar states and 30 comparisons. All twelve bind_cols comparisons against safe remain flagged, adding 1.231–1.358 ms at ratios 4.466–6.124. Warmed R allocation gaps remain 580,272 bytes at width eight and 582,992 at width sixteen. No predecessor-public comparison crosses both thresholds.

The wide row-bind repeat deltas remain positive at 1.862–2.720 ms, but ratios of 1.041–1.060 fall below the joint threshold. The original full-grid 4.975 ms/1.114 flag remains recorded. Its repeated warmed allocation gap is 429,280 bytes, distinct from the original full-grid 402,520 bytes. Restricted runs omit the preceding full-grid workload and cannot erase that history.

For the selected one-million-row, eight-column bind_cols comparison, source/profile investigation identifies fourteen intermediate 40,048-byte reservation events: 560,672 of the 580,272-byte warmed R allocation gap. This explains that allocation subtotal, not all elapsed time or an unavoidable cost. The first restricted baseline attempt wrote its ten series and then failed an unchanged full-grid terminal-count assertion. It remains failed and excluded; the six successful jobs use the separately recorded one-expression count correction and fresh outputs.

| Completed record | SHA-256 |
| --- | --- |
| Original broad receipt, failed only at final schema comparator | `b104180dfb076dfab37f88446df109ee8aa8056c933316bf2d90cbeaf98e0d17` |
| Broad product manifest, also used by the corrected heap comparison | `c6d4c7935be30301be9b0ff3b03ca0b0ef9435506137801faed79eb6ca8b3bea` |
| Row predecessor measurement receipt | `3657161717a30aa62aef78fb8b98befe9e30fa2c47bc836fae4996057faa5c4a` |
| Row final measurement receipt | `cabd17568d20839aa01a25ba8a0cdbfdd1f59821b61bd090a554077b11bc6e63` |
| Groups predecessor measurement receipt | `5fb6b235f5d540ff75b0b73427ad749dbb6c665a0ab50cb42adf8636a59d934c` |
| Groups final measurement receipt | `7167baedc7d722eb10cbcef3464b03d0a9a764feff7622e03c491c9ba0c4dffb` |
| High-cardinality predecessor measurement receipt | `8198c155897be939b64a281e9f05eee1b963ae9a84554fdd2d46286cdb0c3034` |
| High-cardinality final measurement receipt | `010216cf9748dea048c357b483dc6a5e4f67374667e207ce6a2eb614c73f6e91` |
| Qualified pipeline raw-data audit assessment | `1db1a70b47fc2ca6525b2365bfdde4f0f1ab2f71622164ead037d23d5f575eb7` |
| Joins predecessor measurement receipt | `6a67f35bd97a8e56114c569a4304ff5a17258380336ba4c6ad55243f2ab0e9f0` |
| Joins final measurement receipt | `6b7ac47d97defa483ec086c0d3005fb9526f65bed0f48cee1d54ecd42d6e9a92` |

The reviewed records are `api-review/broad-actual-results-01/REVIEW.md` (`7aaa343c`), `api-review/rows-actual-results-01/REVIEW.md` (`e56ca649`), `api-review/groups-highcard-actual-results-01/REVIEW.md` (`aef860f8`), `dta-direct-final-bracket-recurrence-assessment-01/REVIEW-01.md` (`43b59375`), `semantics-review/pipeline-repeat-review-01/REVIEW-01.md` (`d599a6f4`), `api-review/joins-actual-results-01/REVIEW.md` (`4dab0112`) and `api-review/joins-repeat-actual-results-01/REVIEW.md` (`39ccc802`), with their task-owned replay scripts and complete derived tables. The [final evidence bundle](direct-dibble-final-evidence/README.md) supplies the exact member map, archive parts, verification scripts and replay limits. The three parts reconstruct archive `c03edfc4`, containing 8,409 files and 2,007,394,542 uncompressed bytes; selection `863e78d3` binds their identities. Later-workload producers and comparators explicitly leave overall performance acceptance undecided; those fields are not execution failures.

The local integrated assessment accepts the existing allocation/scaling budgets and the completed timing investigations with the residual costs reported above. It does not claim universally lower allocation, no timing regressions, universal direct-path speedup, or irreducible overhead. The original undecided acceptance fields and failed receipts remain unchanged. Publication and issue closure still require the final evidence gates.

## Downstream compatibility and restoration

The actual downstream fertility lifecycle ran 507 test blocks for both baseline and candidate. Both runs retained the same six failing blocks, comprising ten failed expectations, and two skipped blocks. The complete observed failures were unchanged and no column-reallocation warning appeared. This is a no-new-regression comparison, not an all-tests-passed claim.

The original installed package was restored and verified after the candidate run; the checkout and data were verified unchanged. Only these aggregate outcomes and restoration facts belong in the public evidence. Other repositories' source, data, test names, logs and detailed test/report files remain local and are excluded from publication.

## Final disposition

Fresh functional/source/package checks and the local integrated performance assessment are complete within their recorded scopes. Dedicated reviewers cleared the selected functional, performance, bracket/pipeline and prose records. Exact-member transport, independent stream verification and three-part reassembly agree on the published archive identity. The original Cargo metadata with upstream author/description prose stays local; its selected derivative contains only dependency identities and graph metadata. All detailed foreign-repository records remain excluded.

The evidence PR runs all 17 CI jobs: six physical native-absence lanes, three supported-R/dplyr compatibility lanes, three platform package lanes, TypeScript/Bun, two Rust toolchains, deterministic fuzz smoke and offline Cargo dependency checks. Normal merge follows successful required CI; #172 closure follows verification that the merge retains the tested package tree. CodeRabbit is not a gate for this evidence-only change. Its PR records the CI and merge outcome; the archive retains the pre-publication snapshots as history.
