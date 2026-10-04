# Remaining compact kernel results

The accepted changes remove more per-row classification and mask work from compact arithmetic. Sparse INT/FLOAT addition improved by 1.27x, multiplication by 1.32x, and dense FLOAT reverse division by 1.51x in balanced local measurements. They retain established rounding and binary64 division, whole-column promotion, canonical missing results, source isolation and captured-read ownership.

Parity remains unproven. Sparse integer reverse division still takes 1.37x the typed DOUBLE control and 1.53x bare R doubles. Dense FLOAT reverse division takes 1.21x and 1.31x respectively. The remaining gap is explicit in the tables, rather than inferred away from successful tests or CI.

## Final public-operation panel

| Million-row case | Baseline compact ms | Final compact ms | Baseline/final | Final/typed DOUBLE | Final/bare DOUBLE |
| --- | ---: | ---: | ---: | ---: | ---: |
| FLOAT reverse division, observed | 0.290 | 0.292 | 0.990 | 0.953 | 1.018 |
| FLOAT reverse division, sparse missing | 0.325 | 0.324 | 1.004 | 1.035 | 1.140 |
| INT reverse division, observed | 0.437 | 0.375 | 1.148 | 1.056 | 1.250 |
| INT reverse division, sparse missing | 0.486 | 0.451 | 1.078 | 1.366 | 1.525 |
| INT/FLOAT addition, sparse missing | 0.494 | 0.393 | 1.274 | 1.075 | 1.291 |
| INT/FLOAT multiplication, sparse missing | 0.494 | 0.376 | 1.316 | 1.133 | 1.331 |
| FLOAT reverse division, random half missing | 0.734 | 0.482 | 1.507 | 1.208 | 1.306 |

Times are medians of CPU per call. Ratios are medians of within-round ratios, so they need not equal ratios of time medians. The first six cases produced 216 observations in six alternating baseline/candidate rounds, and the dense case produced 36 more. Representation positions were balanced. Both panels used the same final DLL, `cc084e97ba396766be2cdfd480f952dfd420ee92ae9f2adf9d1f7db86833072b`. Raw records, source bindings and command receipts are in [the final evidence](evidence/final/README.md).

The controls have different result contracts. Typed DOUBLE keeps the package's storage, metadata and missing-value rules. Bare R division preserves infinity for zero denominators, while package division normalizes it to missing. Compact FLOAT output also narrows observed values once. Each representation was checked against its own independent oracle. These measurements do not establish a fundamental R limit, universal parity, arbitrary-import performance or reader throughput.

## Why the kernels changed

The mixed kernel previously used the general imported-FLOAT classifier even when a captured descriptor already proved strict modern Stata bytes. General classification checks exact missing-tag encodings, IEEE NaNs and infinities. Strict modern FLOAT values instead admit a single sentinel comparison for missing values. The new private policies select existing canonical loaders from that captured proof, with an additional observed-only policy when the protected missing count is zero. Unknown, legacy and temporal layouts retain their existing classification paths. Arithmetic, rounding-sensitive boundary handling and promotion recomputation are unchanged.

Dense reciprocal blocks previously prepared denominator and missing-mask arrays after ordinary-block proofs failed. Four ordinary-block failures now select a fused writer for strict modern bytes. It classifies the source, divides in binary64, narrows once and counts invalid lanes in one pass. Below-threshold observed denominators make that pass provisional; the exact producer overwrites the entire attempted range, and promotion recomputes from the original captured input. This preserves the safe fallback while avoiding repeated preparation for dense missing data.

Integer reciprocal no longer substitutes an inherited missing code before division. Every nonzero physical signed integer, including a reserved positive missing code, has magnitude at least one. The existing scalar proof therefore bounds its quotient, and the missing store discards that provisional result. Only zero needs a benign denominator. Choosing that denominator in the source width also avoids a wider selection. Exact binary64 division and the final narrowing remain intact.

The extra clean-block scan tried in candidate2 did not offer enough observed benefit to retain. Its single-round comparison cannot separate kernel effects from simultaneous changes and host drift. The [rejected screen](evidence/rejected-clean-pair/README.md) records that decision and the actual experimental header hash. Final mixed arithmetic uses the simpler candidate1 canonical policies.

## Validation and CI

The final installed binary passed 65,745 assertions across 71 focused public test blocks, with zero failures, errors, warnings or skips. The new tests cover byte and INT mixed operands, strict and invalidated domains, all missing tags, signed zero and subnormal values, ambiguous limits, promotion from original inputs, cache clearing, aliases and allocation callbacks. Dense reciprocal tests also cover a late unsafe denominator after provisional output.

Small structural drivers passed 624 mixed-pair cases and 1,136 dense reciprocal cases against committed source `1b58701c612c55c7c6f72a3fdb128bfdf473e60b`, with zero semantic or work failures. They exercise the actual headers with independent value oracles and work counters, covering four floating-point rounding modes and strict, unknown and legacy layouts where applicable. The [receipts and case records](validation/probe-publication-source-map.json) retain both original and public hashes. Their R allocation, reader and interrupt boundaries are mocked, so public tests remain the ownership and lifecycle evidence. The drivers are maintained optional local C++ inputs. No hosted C++ scan, package install or benchmark was added to CI.
