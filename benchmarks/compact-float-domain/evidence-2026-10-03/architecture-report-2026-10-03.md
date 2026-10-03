# Compact execution: architectural findings and final acceptance

The final combined panel contains 1,224 validated observations across 34 public operations. Historical stage results below are separately measured comparisons, not factors to multiply.

The measurements do not show a fundamental order-of-magnitude limit imposed by R. Several controlled operations reach typed-double speed. The expensive paths repeatedly interpret storage and missing values, cross per-element interfaces, rescan buffers, or do unnecessary bookkeeping. Fixing those paths requires preserving the package's arithmetic, ownership and callback rules.

The earlier reader study tested RDS, CSV readers, haven, generic Arrow, fst and qs2 alongside the package readers. Generic Arrow and qs2 were faster in several ordinary-value comparisons. Their advantages exposed work we could examine: retaining compatible buffers, restoring R-native representations and avoiding later compact-to-double decoding. The synthetic data also compressed unusually well for qs2. Those formats did not preserve the same Stata representation and metadata, and fast read return sometimes deferred work until consumption. [Reader methods, results and limitations](https://github.com/jbearak/dta-parser/blob/main/benchmarks/r-file-readers/results-2026-10-02.md).

## Stata's missing representation is useful when its domain is known

Stata orders ordinary numbers below its 27 numeric missing values. A strict modern compact FLOAT made by our constructor contains finite ordinary values in the permitted range or one of those exact positive encodings. Its missing predicate can therefore be a single `value >= 0x1p127f` comparison. [Stata missing values](https://www.stata.com/manuals/dmissingvalues.pdf), [Stata storage types](https://www.stata.com/manuals/ddatatypes.pdf).

Our imported-byte domain is wider. It admits legacy layouts, observed infinities and high finite bit patterns between canonical missing encodings. Applying the threshold to every imported FLOAT would change results. A zero missing count alone does not prove the strict finite domain. Missing classification also differs from operator invalidity: observed infinity is a valid input to some operations, and a finite value divided by infinity produces signed zero.

The accepted correction keeps a private domain flag on the protected storage descriptor. Strict constructors establish it; unknown imports and deserialization do not. Retained aliases preserve it with the same immutable owner. Writable acquisition clears it before exposing storage. Captured read claims keep the proven bytes and count stable across allocations, interrupts and reentrant mutation. The first consumer is LONG/FLOAT addition. The corrected isolated screen improved dense missing-bearing cases 1.338–1.641× directly and 1.335–1.560× in paired rounds. Those cases reached 1.070–1.258× typed-double CPU. Ordinary plain columns reached 0.979–0.981× typed-double CPU. The 840 observations and 140 prior qualifications passed independent semantic, ordering, statistical and source/runtime audits. The final combined source also passed 111,083 assertions in the retained package conformance archive, 38,954 focused assertions and 71 Rust tests. The archive retained seven existing test warnings; its package check retained three existing warning categories and two notes.

## Architectural costs and the changes they justified

| Finding | Consequence | Implemented response |
| --- | --- | --- |
| Scalar ALTREP access is a native callback, but each element can still repeat dispatch, bounds checks, chunk lookup and decoding. | A C entry point alone can remain much slower than a tight loop. | Controlled operations capture typed spans and dispatch storage/operator policy outside the element loop. |
| Sort comparisons repeatedly decoded and classified the same keys. | Repeated interpretation grew with comparator calls. | Prepare numeric order keys once and retain them through sorting, spending eight bytes per row per key. |
| Object identity was checked through temporary address strings during table construction. | Setup repeatedly allocated and compared strings as column count grew. | Compare object identity directly in the native construction path. |
| A failed proof selected fallback for the rest of an arbitrarily large span. | A short missing prefix made a million-row ordinary tail use the expensive decoder. | Bound fallback windows and retry proofs after at most 16,384 rows. |
| A column-level missing count selected scratch preparation for every block. | Dense data improved while sparse and clustered data regressed sharply. | Try ordinary blocks first, prepare only failed blocks, and limit adaptive decisions to the current bounded span. |
| Range and validity checks were repeated for results that could be proved safe in advance. | Exact division paid avoidable checks on every result. | Integer and FLOAT reciprocal kernels derive safe bounds once, retaining the original binary64 division and final narrowing. |
| An exact all-missing count was available but the producer still read every input. | It decoded and computed results already known before the loop. | Fill the fresh canonical-missing output directly under the captured count proof. |
| Interrupt polling followed physical chunk boundaries. | Synthetic seven-/eleven-row chunks caused 220,780 checks per million-row pair. | Poll against completed rows while preserving whole span requests and a maximum 16,384-row processing gap. |
| Each retained region request repeated a binary search over chunks. | The same short-chunk pair caused 441,560 region calls and about 8.17 million partition comparisons. | The accepted direct locator uses immutable regular row geometry; irregular chunks keep the search. |
| Mutable aliases could invalidate cached facts during R callbacks. | Rooting an address alone did not keep its bytes or missing count unchanged. | Read claims force reentrant writes to detach; facts belong to captured protected storage. |
| An immutable read triggered a backing copy before materialization. | It copied the compact input and then allocated the required double output. | Decode under a stable read claim, avoiding the redundant compact copy. |
| Native allocation pressure depended only on live bytes. | Small reads repeatedly collected unrelated retained data. | Require allocation progress before another pressure-triggered collection. |
| Nullable string decoding crossed the caught R-call boundary per cell. | Error-boundary overhead scaled with non-null cells. | Use one caught native loop per column while preserving R string allocation. |
| Reader thread settings showed lower CPU and higher latency with one worker. | A lower CPU count could make the user wait longer. | Retain the measured CPU/latency tradeoff; no universal worker cap was adopted. |

The direct locator subsequently improved the seven-/eleven-row stress cases 4.750–4.861× against the accepted polling implementation, reaching 2.331–2.377 milliseconds per million rows. The 696-observation screen retains all 26 cases. Larger retained chunks showed small mixed costs, with direct speedups of 0.960–1.016×; the largest paired typed-normalized cost was 1.046×. The short-chunk cases still cost 7.179–7.337× the plain typed-double control. This is a substantial lookup improvement, not elimination of per-chunk overhead or a general throughput claim.

Physical chunk regularity does not imply contiguous memory. The direct locator still takes the pointer from the selected actual chunk. It changes lookup work, not ownership or buffer placement. Polling and locator results from deliberately short chunks are structural stress measurements, not file-reader throughput claims.

Prepared grouping provides a measured example of hoisting repeated interpretation. It improved the constructed cases 11.94–23.69× and reached 0.967–1.007× typed-double CPU. Its full key cache is an explicit memory tradeoff. [Grouping report](https://github.com/jbearak/dta-parser/blob/main/benchmarks/prepared-grouping/results-2026-10-02.md).

Direct binary32 arithmetic required a separate numerical proof. For admitted exactly converting byte, int16 and FLOAT operands, the specialized addition, subtraction and multiplication preserve the specified binary64-then-binary32 result. Ambiguous equality at a storage boundary reruns the binary64 producer, and promotion recomputes from the original inputs. Using the narrower representation is therefore conditional on preserving the public result, not simply on choosing a faster instruction. [Compact-pair arithmetic](https://github.com/jbearak/dta-parser/pull/297).

## What the compiler and unsuccessful experiments taught us

A simpler source loop can be slower. Earlier float prototypes lost SIMD in exceptional-value loops and regressed dense inputs despite improving ordinary inputs. We checked the emitted code and restored vectorization by exposing immutable bounds to the compiler. Structural counters establish which source work disappears; they do not count emitted machine instructions.

The first production threshold experiment bypassed ordinary-block proofs for trusted columns. All 840 strict-domain and unknown-import observations passed semantic and provenance checks. Plain random-half-missing cases improved 1.444–1.456×, reaching 1.180–1.183× typed-double CPU. But ordinary cases fell to 0.940–0.952× speed, and short missing-prefix/suffix cases to 0.840–0.890×. We rejected that routing policy. A cheaper missing classifier does not justify running missing-mask work on ordinary blocks that can skip it. The accepted correction retains those proofs and applies the classifier only inside the existing bounded exact fallback. An actual-header work test was red on the rejected route and green after correction, with zero semantic failures. Ordinary inputs execute zero canonical exception rows; a 256-row missing prefix is limited to 16,384 exception rows.

The correction still has measured costs. Retained suffix LONG/FLOAT addition had a paired typed-normalized cost of 1.067×, with five of six rounds slower. Short-chunk ordinary FLOAT/LONG addition cost 1.052× after normalization, with all six rounds slower. The unknown-import random-half reverse case cost 1.035×, with four rounds slower. Typed controls moved by 0.898–1.167× across the screen, so direct and paired results remain separate from normalized costs. The unchanged all-missing fill showed a direct timing gain that cannot be attributed to the new domain fact.

The adaptive reciprocal experiment initially prepared every block whenever any input was missing. Its sparse and prefix speedups fell to 0.549× and 0.490×. That version was rejected. The accepted adaptive version improved the measured sparse, random-half-missing and all-missing cases by 1.080×, 1.126× and 4.611×. Its prefix case was 0.976×, and the half-missing case still cost 1.922× typed-double CPU. The retained report includes both experiments and that regression. [PR303](https://github.com/jbearak/dta-parser/pull/303).

The first polling prototype split spans to fit the remaining interrupt budget. It increased medium-geometry lookups from 368 to 490. The accepted version preserves the original 124, 368 and 441,560 calls for the three measured geometries. Tiny-chunk CPU improved 1.056–1.139× but still cost 33.46–34.70× the typed control. Polling explains only a minority of that fragmentation cost. [PR302](https://github.com/jbearak/dta-parser/pull/302).

The published reader comparison also separates CPU from latency. On its compact Arrow fixture, automatic decoding used 46.0 ms CPU and returned in 7.5 ms; the one-thread request used 23.5 ms CPU and returned in 23.5 ms. These sequential measurements show the tradeoff but do not isolate scheduler overhead or establish a universally better default. [Reader thread comparison](https://github.com/jbearak/dta-parser/blob/main/benchmarks/r-file-readers/results-2026-10-02.md#cpu-versus-latency-at-different-thread-settings).

## Final combined public-operation acceptance

[Canonical-domain implementation and stage evidence](results-2026-10-03.md), [final panel evidence](final-acceptance-2026-10-03/README.md), [complete per-round comparisons](final-acceptance-2026-10-03/validation/final-panel-description.json).

The unchanged original 34-case worker was run against baseline `7003eba901671797ee91fffc97f08e28a1f7f515` and final combined candidate `3eadb244253fb817d5773b01b11cb36c284f3a1d`. Six paired rounds covered all six representation orders, for 1,224 timed observations after 204 untimed qualifications. An independent audit verified the complete matrix, full result and missing-mask hashes, result storage, missing-count caches, native routes, source states, every summary statistic, and the exact source, installed library, runtime and controller identities. The source archive and package validation are separately bound to that same candidate.

Across this panel, compact CPU cost was **0.769–1.545× typed-double cost**: 23 of 34 cases were within 10% or faster, and 31 were within 50% or faster. Against bare doubles, the range was **0.778–1.915×**, with 14 cases within 10% and 28 within 50%. These counts describe this constructed panel, not statistical acceptance thresholds or a universal parity claim.

The follow-ups improved ordinary/sparse FLOAT reciprocal division by 1.828×/2.302× directly (1.825×/2.294× paired), integer reciprocal division by 1.583×/1.415× (1.583×/1.410× paired), and LONG/FLOAT addition by 1.182×/1.452× (1.223×/1.520× paired). All six cases improved relative to both matched controls in every round.

The complete table retains the costs. Ordinary integer-plus-double was 0.947× direct and 0.958× paired speed, a roughly 5.6% increase in median compact CPU. Its matched controls also moved: the paired typed-normalized cost was 0.934×, with two of six rounds slower, so this screen does not isolate the source change as the cause. Conversely, ordinary FLOAT-plus-double had nearly unchanged compact time (0.995× direct) but a 1.118× typed-normalized cost, with five rounds slower. Sparse integer general scaling similarly had 0.993× direct speed and a 1.111× normalized cost, with five rounds slower. All per-round costs and both control comparisons remain in the evidence.

The three cases above 1.5× typed cost were sparse integer/FLOAT addition (1.518×), sparse integer/FLOAT multiplication (1.514×), and sparse integer reciprocal division (1.545×). Dense missing distributions and short retained chunks are covered by the separate stage screens above; they are not present in this original panel. In particular, its result does not erase the retained short-chunk gap.

The table reports median CPU milliseconds per operation over one million rows. Gain is baseline compact CPU divided by candidate compact CPU; values above one mean faster. The last two columns divide candidate compact CPU by candidate control CPU; values below one mean faster.

| Storage | Sparse missing | Operation | Compact CPU ms | Gain vs7003 | Paired gain | / typed doubles | / bare doubles |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| float | no | add_scalar | 0.236 | 1.013 | 1.010 | 0.877 | 0.938 |
| float | no | pair_compact_double | 0.311 | 0.995 | 0.995 | 1.012 | 1.227 |
| float | no | reverse_divide | 0.275 | 1.828 | 1.825 | 0.961 | 1.096 |
| float | no | reverse_subtract | 0.238 | 0.997 | 0.993 | 0.812 | 0.994 |
| float | no | scale_binary | 0.324 | 0.997 | 1.002 | 1.086 | 1.283 |
| float | no | scale_general | 0.237 | 0.991 | 0.996 | 0.806 | 0.985 |
| float | no | subtract_scalar | 0.237 | 0.996 | 0.994 | 0.800 | 0.981 |
| float | yes | add_scalar | 0.269 | 1.016 | 1.014 | 1.015 | 1.016 |
| float | yes | pair_compact_double | 0.460 | 1.006 | 1.007 | 1.490 | 1.728 |
| float | yes | reverse_divide | 0.308 | 2.302 | 2.294 | 1.069 | 1.282 |
| float | yes | reverse_subtract | 0.276 | 1.009 | 1.015 | 1.039 | 1.045 |
| float | yes | scale_binary | 0.325 | 0.992 | 0.997 | 1.158 | 1.340 |
| float | yes | scale_general | 0.272 | 0.993 | 0.990 | 1.017 | 1.133 |
| float | yes | subtract_scalar | 0.271 | 0.996 | 0.996 | 0.964 | 1.128 |
| int | no | add_scalar | 0.263 | 1.002 | 1.000 | 0.875 | 0.973 |
| int | no | mixed_add | 0.360 | 0.992 | 0.990 | 1.159 | 1.406 |
| int | no | mixed_multiply | 0.360 | 0.993 | 0.991 | 1.158 | 1.392 |
| int | no | pair_compact_double | 0.457 | 0.947 | 0.958 | 1.279 | 1.589 |
| int | no | reverse_divide | 0.415 | 1.583 | 1.583 | 1.302 | 1.625 |
| int | no | reverse_subtract | 0.262 | 0.995 | 0.997 | 0.892 | 0.985 |
| int | no | scale_binary | 0.242 | 1.004 | 0.996 | 0.769 | 0.778 |
| int | no | scale_general | 0.264 | 1.003 | 1.002 | 0.830 | 1.006 |
| int | no | subtract_scalar | 0.262 | 1.002 | 1.007 | 0.883 | 0.974 |
| int | yes | add_scalar | 0.287 | 1.004 | 1.002 | 1.077 | 1.197 |
| int | yes | mixed_add | 0.469 | 0.993 | 0.994 | 1.518 | 1.758 |
| int | yes | mixed_multiply | 0.466 | 1.000 | 1.000 | 1.514 | 1.745 |
| int | yes | pair_compact_double | 0.405 | 1.001 | 1.001 | 1.319 | 1.497 |
| int | yes | reverse_divide | 0.463 | 1.415 | 1.410 | 1.545 | 1.915 |
| int | yes | reverse_subtract | 0.286 | 1.000 | 1.000 | 0.971 | 1.189 |
| int | yes | scale_binary | 0.241 | 0.997 | 0.997 | 0.893 | 0.906 |
| int | yes | scale_general | 0.288 | 0.993 | 0.993 | 1.076 | 1.081 |
| int | yes | subtract_scalar | 0.288 | 0.993 | 0.993 | 1.074 | 1.181 |
| long | no | long_float_add | 0.322 | 1.182 | 1.223 | 1.036 | 1.201 |
| long | yes | long_float_add | 0.366 | 1.452 | 1.520 | 1.190 | 1.359 |

Baseline 7003 is an earlier qualified integration that already contains native-kernel improvements. The new panel measures the accumulated follow-ups against that baseline and, separately, the final gap to typed and bare doubles. It is not a before/after comparison for every change in this project.

The panel measures preloaded public operations, including output allocation and automatic GC. The typed-double control uses ordinary double storage with the package's typed-operation and result-storage rules. The bare-double control uses base R arithmetic without those rules. Both comparisons are reported because compact-versus-typed isolates storage more closely, while compact-versus-bare answers the practical speed question. The panel does not measure file reading. Native Stata save, R read return and full table consumption perform different work. The reader study and subsequent reader changes retain their own end-to-end scopes and limitations.

## Remaining limits

Compact storage reduces input bandwidth but may still require widening for binary64 arithmetic, missing masks, narrowing, promotion and the package's result-storage policy. Those costs depend on the operation and data. Foreign scalar consumers can still invoke element callbacks; controlled native kernels cannot silently change another provider's behavior.

Further fusion would need to preserve evaluation order, intermediate rounding, errors, promotion and callbacks. It remains a design question, not an unmeasured performance claim. The work above addresses demonstrated costs and records remaining gaps rather than treating all compact operations as solved.
