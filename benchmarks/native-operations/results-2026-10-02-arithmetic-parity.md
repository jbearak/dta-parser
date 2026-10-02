# Compact arithmetic follow-up, 2026-10-02

Compact arithmetic now takes **0.58–1.13× typed-double CPU** across the 24 measured width/format/operation cases, compared with the previous report's 4.2–7.6× gap. Six balanced rounds compare merged commit `0a9c7090c100d68d4fa3005d707049e1b3d9c9a9` with candidate `5f3ea2e20136cf68790d920e9d7d8073a62c50d2`. The fresh comparison improves compact CPU by 3.91–11.13×. All 864 observations pass result, storage, native-route, source-state, and provenance checks.

Sixteen cases are faster than or equal to their typed-double controls; 22 use no more than 1.10× their typed-double control's CPU. The largest remaining typed-control overhead is 13%, for Arrow float multiplication. Against bare ordinary doubles, the range is 0.67–1.30×. These measurements support near parity for the operations below, with a remaining float cost. They do not establish universal arithmetic parity.

## Measured operations

CPU milliseconds per public call, including result allocation and automatic garbage collection. Each range spans eight width/format cases, with a median of six observations per case. Speedups and ratios compare the corresponding case medians, rather than the endpoints of these ranges.

| Operation | Before (ms) | After (ms) | Typed double (ms) | Bare double (ms) | Speedup | After / typed CPU | After / bare CPU |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `x * 2` | 1.299–1.912 | 0.263–0.343 | 0.278–0.308 | 0.253–0.279 | 3.91–7.27× | 0.89–1.13× | 0.99–1.30× |
| `x / 2` | 1.228–2.085 | 0.181–0.327 | 0.305–0.327 | 0.264–0.277 | 4.01–11.13× | 0.58–1.03× | 0.67–1.19× |
| `x + x` | 1.576–2.168 | 0.250–0.342 | 0.277–0.315 | 0.259–0.289 | 4.76–8.53× | 0.90–1.10× | 0.96–1.26× |

The displayed 1.10× maximum for addition is 1.101× before rounding.

`dta_double` applies the package's missing-value and result-validation rules. Compact output also selects storage according to the existing promotion policy and can remain narrower than double. Bare-double arithmetic returns an ordinary R vector. The two controls expose those different contracts.

The original failing diagnostic, Arrow int `x * 2`, took 2.190 ms compact versus 0.315 ms typed double, a 6.95× gap. It already entered native code on every call and kept its input compact. Repeating the same diagnostic against the clean acceptance candidate gives 0.292 ms versus 0.320 ms, or 0.91×. This separate three-pair diagnostic is retained alongside the six-round acceptance comparison.

## Why the gap existed

The remaining cost was inside native loops and result ownership. It was not a requirement to call R for each scalar.

The old producer repeatedly converted values to doubles, checked broad arithmetic and storage conditions, allocated a provisional destination, and could scan again after promotion. Integer arithmetic now stays in the integer domain for range selection and integer output. Proven bounds remove unnecessary validity checks. Long inputs stop the range scan as soon as double promotion is settled. Binary scaling combines float fit detection with output production, and a promoted result is recomputed from the original values. Captured missing counts are reused when the operation cannot introduce additional missing values. Float loops choose the encoding policy before scanning; reserved codes still receive exact classification.

A second cost came from registering a native finalizer on compact results whose bytes were already R-owned. R's weak-reference processing retained the finalizable record and its protected backing during collection. Controlled allocation diagnostics isolated this cost. The inspected R 4.6.1 source also confirms that atomic raw vectors use uninitialized allocation, so removing hypothetical raw-buffer zeroing would not solve it. Arithmetic results now keep the small plain descriptor on R's heap alongside the raw backing. Native-owned and retained payloads keep their existing destructors. Serialization continues to emit ordinary raw backing.

Temporary ownership claims keep captured plain bytes stable if an allocation callback patches a public input between range proof and output production. Cleanup restores prior ownership on normal and error exits while preserving newly created aliases. A deterministic checkpoint verifies that window. The default-Rscript scan did not reproduce immediate finalization at native allocation, so it is recorded as a protected invariant rather than a demonstrated default-runtime failure.

The retained compiler evidence uses the same `-O2` setting as the package. The final float classifier refinement reduces the modern fit loop from 77 to 66 instructions per 16 rows and preserves SIMD execution. No fast-math or reassociated reductions were introduced.

## Kernel scope

| Input and operation | Specialized work |
| --- | --- |
| Same-width compact byte, int, or long pairs with `+`, `-`, `*` | Integer range analysis and typed output, with wide intermediates where required. |
| Compact integer multiplied by an observed integral scalar in the signed 32-bit range, on either side | Integer kernel with proven intermediate bounds and the existing promotion policy. |
| Compact integer divided by a signed power of two, divisor magnitude 2 through 2^30 | Divisibility selects integer or fractional storage; contraction proves the range. |
| Compact float multiplied or divided by a signed power of two, scalar magnitude 2^-30 through 2^30 | Binary scaling with combined fit/output work; promotion recomputes the full result into doubles. Multiplication supports either scalar side. |
| Compact `x + x` with equal captured byte spans and encoding | Reads one source as multiplication by two. The proof uses captured storage, not public object identity. |

Other admitted arithmetic retains the general native implementation, and unsupported objects retain the established fallback. Only `x * 2`, `x / 2`, and `x + x` have throughput measurements here. Different-column pairs, arbitrary floating scalars, other operators, and small inputs are not covered by the parity claim. Correctness tests exercise wider combinations, but are not performance evidence for them.

## Protocol and validation

Each of six rounds starts a fresh R process for each build. Build order alternates; compact, typed-double, and bare-double order rotates and reverses across the rounds. Inputs are actual DTA and Arrow million-row byte, int, long, and float columns with periodic system missing values. Reads, input construction, explicit GC, qualification, calibration, and hashing are outside timing. Public dispatch, result allocation, and automatic GC are inside.

Untimed calibration targets 150 ms per retained interval. Actual CPU intervals span 0.065–0.193 seconds; none is below 20 ms and nine are below 100 ms. The table reports ratios of medians without a formal uncertainty interval. Builds and tests did not overlap timing. This is one warm-data arm64 macOS host using R 4.6.1 and Apple clang 21.0.0; unrelated desktop activity was not hardware-isolated. It does not measure ingestion or read-plus-consume latency.

The controller verifies all 72 unique cases in every worker, complete result bytes and output storage, unchanged source values and compact state, and actual native entry counts for every candidate arithmetic call. Before/after receipts bind Git sources, compiler inputs, installed code, DLLs, fixtures, and controllers. The original reproduction also passes against that exact clean candidate DLL.

The clean candidate passes **51,477 full-suite assertions**, with zero failures, errors, or skips and seven existing warnings. The required conformance orchestrator passes, including source-archive validation and `R CMD check`; its three warnings and two notes are retained in the log. Focused coverage includes all modern reserved float codes and adjacent encodings, legacy values, IEEE exceptions, signed zero, promotion, chunk boundaries, serialization, aliasing, forced GC, and reentrant callbacks. A separate source-bound classifier check passes 2,655,394 comparisons. Six benchmark-controller regression tests pass and are included in CI. Timing thresholds are not CI tests.

[Raw observations](results-2026-10-02-arithmetic-parity/timings/raw.csv), [case medians](results-2026-10-02-arithmetic-parity/timings/summary.csv), [protocol](results-2026-10-02-arithmetic-parity/timings/protocol.json), [build provenance](results-2026-10-02-arithmetic-parity/timings/provenance-before.json), [full-suite results](results-2026-10-02-arithmetic-parity/validation/acceptance-full-tests.csv), [conformance log](results-2026-10-02-arithmetic-parity/validation/acceptance-conformance.log), and [validation source bindings](results-2026-10-02-arithmetic-parity/validation/validation-source-bindings.json) provide the acceptance evidence. The [source patch](results-2026-10-02-arithmetic-parity/candidate-git.patch), [publication source map](results-2026-10-02-arithmetic-parity/publication-source-map.json), and [manifest](results-2026-10-02-arithmetic-parity/publication-manifest.json) identify original and published bytes, including private-path substitutions. Diagnostic evidence is labeled separately from acceptance timing. Installed libraries and input binaries are not published.

[Reproduction instructions](README.md) describe clean builds and the arithmetic-only comparison. The [earlier native-operation report](results-2026-10-02.md) remains unchanged.
