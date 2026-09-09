# Stage 8 performance and retained-memory assessment

Candidate `cf317730d3110568c72862719424e01c2876141b` passes the selected Stage 8 value, metadata, isolation and memory checks. The complete timing grid has no joint slowdown flag against predecessor public methods. Four `bind_cols()` comparisons with the fixed reference remain flagged after three paired repeats. They are an explicit limit of this implementation.

The shared-finalizer change reduces the large predecessor address-history growth in the finite 500-call histories. It does not establish a general allocation reduction for joins and bindings: 52 of 60 public comparisons have higher warmed R allocation, with increases from 240 to 16,004,096 bytes. All signed timing/allocation/native-counter differences remain in the comparison CSV.

## Source and measurement scope

Predecessor source is `af0bed0b9c200f82d37891902266d200a1819196`. Both full runs use runner `f3b8b984c6a9ea5a0f062eee70e392bb567e5042`, the same executed workload/support sources, and the original predecessor-observed schema file SHA256 `56b4690a4b89332dbb4cdf49de822a22960292f0cd653baf77124e7004a4b8dc`. Independent row/value formulas supplement those schemas. The candidate is freshly installed on stock host R 4.6.1. Timings ran sequentially during coordinated agent quiet, without claiming exclusive OS CPU.

The predecessor grid has 120 series, candidate 60, covering two widths and the declared large/small shapes. Seven GC-inclusive samples per series, first-input and warmed Rprofmem files, GC rows and native/source state records are retained. Root checked all candidate 420 samples, 120 profiles, 19,960 state rows and 1,289 GC events against producer identities and independently recomputed their reported quantities. The prior corresponding predecessor assessment remains complementary. A first-input profile is not a cold process; source validation and its possible backing exposure precede warmed measurements. R allocation and native counters overlap and must not be added. Native state observations cover all flat columns and selected first/last nested children plus prototypes; every nested value/schema is checked separately.

## Large shapes at width 8

Times are medians in milliseconds. Allocation is warmed cumulative R bytes expressed in decimal MB. These are selected rows; the complete 120 paired comparisons are retained.

| Workload | Input rows | Old public ms | Fixed reference ms | Candidate ms | Old R MB | Candidate R MB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| left_unique | 1,000,000 | 588.647 | 584.509 | 561.711 | 357.891 | 365.892 |
| inner_double | 1,000,000 | 987.981 | 991.919 | 908.813 | 635.316 | 651.317 |
| full_padded | 1,000,000 | 857.472 | 855.221 | 828.539 | 600.087 | 609.893 |
| left_rolling | 1,000,000 | 448.661 | 443.731 | 408.049 | 281.292 | 289.293 |
| semi_half | 1,000,000 | 338.527 | 365.576 | 338.529 | 207.686 | 207.686 |
| anti_half | 1,000,000 | 336.310 | 369.436 | 354.702 | 219.686 | 219.686 |
| base_rbind | 1,000,000 | 739.932 | 744.404 | 752.052 | 1210.089 | 1210.105 |
| base_cbind | 1,000,000 | 54.140 | 54.657 | 54.499 | 32.084 | 32.101 |
| bind_rows_wide | 1,000,000 | 449.992 | 451.364 | 450.262 | 360.486 | 360.486 |
| bind_cols | 1,000,000 | 1.461 | 0.267 | 1.400 | 0.663 | 0.664 |
| rows_update | 1,000,000 | 368.647 | 378.156 | 382.719 | 206.505 | 206.527 |
| reconstruct | 1,000,000 | 0.203 | 0.176 | 0.204 | 0.081 | 0.081 |
| grouped_left | 1,000,000 | 626.719 | 629.564 | 595.668 | 443.350 | 451.351 |
| cross_four | 250,000 | 97.445 | 97.263 | 47.808 | 116.086 | 132.088 |
| nest_double | 4,096 | 2350.387 | 2333.701 | 1934.422 | 663.171 | 664.155 |

All 33 positive median differences among the 120 pairs are retained, including those below the joint >10% and >1 ms investigation threshold. No positive delta in owned-capture bytes, compact-copy bytes or unchanged-value scan counts occurs against predecessor public in this grid. That does not erase the R allocation increases or assign their cause.

## Repeated bind_cols reference cost

Three fresh paired repeats preserve the four 100k/1M by width8/16 bind_cols shapes, their local fixture/oracle/profile/state preparation and seven GC-inclusive samples. They omit the preceding 36 full-grid shapes. Original within-predecessor route parity is preserved, and source order alternates between pairs. All 36 series, 252 samples, 72 profiles and 12,600 state rows pass the saved-record assessment.

All four reference comparisons cross the joint threshold in each repeat; none does against predecessor public. Candidate medians span 1.408–1.623 ms, fixed-reference medians 0.260–0.353 ms, and paired increments 1.149–1.281 ms. The full-grid candidate warmed allocations are exactly 664,232 bytes at width8 and 670,672 at width16 at both row counts, with zero owned-capture, compact-copy and validation-scan counters. The first 100k/width8 candidate shape in every fresh repeat has a 690,992-byte warmed profile versus 664,232 bench bytes; its 1,660,960-byte first-input profile remains separate. Corresponding old-public first warmed profiles are 690,256 bytes. The first-case process-history difference is retained rather than normalized away.

The consumed fixed reference snapshots both inputs, calls the same dplyr bind_cols orchestration, then closes once. It still performs name repair, recycling/type selection and final capture. Marked public inputs additionally reach dtatools prototype/bracket/proxy/restore integration. The exported vctrs frame-prototype default is x[0]; dibble bracket publication reserves a fresh list and names vector with the default 5,000 spare slots, even for an empty prototype. The selected pair01 1M/width8 warmed profiles provide allocation-stack evidence for this mechanism. Both public versions record four 40,048-byte reservation events under frame-prototype/bracket publication and ten under restore. Final reconstruction contributes two 40,184-byte events, also present in the fixed reference. The intermediate reservations total 560,672 bytes of the candidate/reference 580,272-byte warmed difference for this case. This selected stack inspection does not attribute all elapsed time to reservation or establish that public prototype and restore behavior can safely be skipped. A specialized frame-prototype method would need separate proofs for class, metadata, capacity, mixed/custom containers and callbacks. No such optimization is implemented or claimed irreducible here.

## Retention, writes and peak memory

The separate installed 500-call histories were executed on `8ffa5ac5f29b08e01d55c6b54288ee8679634f34`. The entire recursive Git delta to cf317 changes only H01 test lifetime setup; all executable production/helper/native inputs retain their blob/type/mode. These results keep their original source and installation identities. This is source-level reuse, not a claim that the two fresh installed RDB/DLL files are byte-identical.

Across eight 256-row histories, every 5→50 interval adds 15 Ncells/208 vector bytes and every 50→500 interval adds 15 Ncells/192 bytes. Every final released/three-GC checkpoint is 130 Ncells/1,984 vector bytes above its own warmed prefixture. Predecessor 50→500 increments were 10,980–59,610 Ncells and 58,672–318,032 vector bytes across those eight cases. Root checked all 88 heap and 694 state rows; the independent semantic review recomputed the heap differences. Selected owned depth stays one, and retained source/first handles stay stable. Recorder and validation residue remains; these finite observations are not zero-retention or asymptotic claims.

Twenty-four fresh cf317 children then performed 500 calls and numerical/label writes on sixteen-row fixtures. All 48 prepared/completed graphs pass an independent decoder, including intended duplicate-slot coupling and every protected retained role. Source-to-result and result-to-source cases remain distinct. Complete final payload graphs were not saved by the heap producer; its independent producer formulas and these separate write graphs are complementary evidence. The known temporary callr client DLL byte gaps remain outside any complete child-image claim.

Each of the eight large RSS cases performs 50 calls in a fresh child, keeping source, first and latest. Every 5→50 heap interval adds 15 Ncells/208 vector bytes. Root checked all 96 heap and 1,368 state rows plus exact RSS/log/command/validation records. Later validation/release residue remains in the full assessment, with its own warmed prefixture comparison. Whole-child peak RSS includes startup, fixtures, validation and observers; it is not one-operation peak allocation.

| Workload | Rows | Old public RSS bytes | Candidate RSS bytes |
| --- | ---: | ---: | ---: |
| nest_double | 1,024 | 1,047,642,112 | 908,558,336 |
| nest_double | 4,096 | 3,747,659,776 | 3,746,611,200 |
| base_cbind | 100,000 | 196,149,248 | 197,459,968 |
| bind_rows_wide | 100,000 | 259,211,264 | 359,792,640 |
| full_padded | 100,000 | 430,342,144 | 389,234,688 |
| base_cbind | 1,000,000 | 473,677,824 | 473,530,368 |
| bind_rows_wide | 1,000,000 | 1,320,845,312 | 1,321,435,136 |
| full_padded | 1,000,000 | 1,511,473,152 | 1,534,492,672 |

The original 100k wide-bind peak increase is retained. It did not recur in two further alternating-order pairs: 262,012,928→267,976,704 bytes and 259,375,104→264,126,464 bytes, increases of about 2.28% and 1.83%. All four repeat children pass their value/schema/handle checks, with 48 heap and 472 state rows assessed. No exclusive GC, allocator or object-level cause is assigned to the original peak.

## Disposition and remaining work

No further Stage 8 production optimization is required by these observed public-regression and row-scaling results. Preserve the repeated restricted-reference cost and all R allocation increases when describing the change. The corrected observer-free H01 test passes with unchanged budgets in fresh host and minimum installations; original failed host/minimum runs and the paired predecessor/candidate diagnosis remain preserved.

This assessment does not close Stage 8 package/PR/CI/review requirements or the epic. Stage 9, final merged-main absence/presence and performance validation, the twelve earlier base-R read costs, four historical many-small-group costs, #172 acceptance/closure and actual fertility renv validation/restoration remain separate obligations. No blanket performance acceptance follows from this selected Stage 8 grid.

Root artifacts are identified by CURRENT.json in this preparation directory. The complete comparison CSVs, assessments, original failures, source freezes, command/receipt records and reviewer reports should be published through the existing evidence-selection process before the implementation is declared complete.
