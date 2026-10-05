# Narrow integer reciprocal and constructor results

Large BYTE/INT scalar reciprocal calls now compute the exact result for each physical code once per call, then read compact codes directly through a local lookup table. The original binary64 division and single destination cast are retained. On the original million-row sparse INT fixture, six paired local rounds measured a 1.302x gain and a compact/typed DOUBLE ratio of 1.004. The compact/bare R ratio remains 1.230; this does not establish universal parity.

The same change removes repeated R scalar access from the two constructor validation passes. Ordinary double input uses a refreshed direct pointer in bounded chunks; other inputs use bounded `REAL_GET_REGION` calls, with scalar fallback when a foreign ALTREP returns zero. Both validation passes, final encoded facts and error handling remain intact. Pointer borrows stay bounded, and the second pass refreshes and revalidates inputs after allocation.

| Million-row reciprocal fixture | Baseline/candidate CPU | Candidate/typed DOUBLE | Candidate/bare R |
| --- | ---: | ---: | ---: |
| INT, sparse missing | 1.302 | 1.004 | 1.230 |
| INT, observed | 0.996 | 0.988 | 1.072 |

Ratios are medians of within-round ratios, not ratios of independent time medians. The [general panel](general/balanced-summary.json) retains all six fixtures and 216 observations, including unchanged FLOAT and mixed-operation controls. The observed INT fixture offered no measured gain. These are public operations on preconstructed inputs, so constructor preparation is outside their clocks.

Construction was measured separately with the original dense FLOAT and sparse INT fixtures. Each workflow constructs a compact source, then performs zero, one or five reciprocal evaluations on that same source. Per-call table setup, output allocation, automatic GC and identical workflow bookkeeping are inside the clocks.

| Workflow fixture | Constructor candidate/baseline CPU | Constructor CPU saved | One-operation workflow gain | Five-operation workflow gain |
| --- | ---: | ---: | ---: | ---: |
| FLOAT, random half missing | 0.935 | 0.827 ms | 1.074 | 1.031 |
| INT, sparse missing | 0.863 | 1.339 ms | 1.168 | 1.187 |

The [construction summary](construction/summary.json), 72 raw observations, source bindings and worker logs preserve all six alternating build pairs. The roughly 7% and 14% constructor savings apply to these fixtures and this host. Reader throughput and foreign-import construction were not measured.

## Setup-inclusive threshold screen

The [supplement](supplement/summary.json) uses two fresh paired rounds, ten BYTE/INT controls and three representations: 120 observations. Every public call includes table creation and allocation. It is a screening result, with too few rounds to support universal or finely tuned threshold claims.

| Width/output/cardinality | Rows | Baseline/candidate CPU |
| --- | ---: | ---: |
| BYTE/FLOAT/low | 262,143 | 0.970 |
| BYTE/FLOAT/low | 262,144 | 1.263 |
| BYTE/FLOAT/full observed | 1,000,000 | 1.698 |
| BYTE/DOUBLE/full observed | 1,000,000 | 1.513 |
| INT/FLOAT/low | 262,143 | 0.973 |
| INT/FLOAT/low | 262,144 | 1.011 |
| INT/FLOAT/low | 1,000,000 | 1.364 |
| INT/FLOAT/full observed | 1,000,000 | 1.248 |
| INT/DOUBLE/full observed | 262,144 | 1.120 |
| INT/DOUBLE/full observed | 1,000,000 | 1.134 |

The below-threshold controls retain the existing producer. INT at the initial 262,144 admission threshold was nearly neutral; the DOUBLE screens had substantial between-pair variation. The full observed grids cover constructor-accepted values, not the signed physical minima. The native proof below covers all physical codes. Forced DOUBLE uses a typed DOUBLE numerator on compact and typed inputs; the bare R control uses the ordinary scalar. Those are deliberate API controls.

Typed controls preserve package storage, metadata and invalid-result rules. Bare R division retains infinity at zero denominators, whereas native results normalize it to missing. Compact FLOAT narrows once. Each representation has its own independent exact oracle. Baseline/candidate compact pairs preserve identical fixtures, result bytes, missing masks/count-cache mutation, input facts and ownership state; these are the direct implementation comparison.

## Correctness and build lineage

The [committed actual-header oracle](proof/candidate-receipt.json) passed 1,472 cases under four witnessed rounding modes, with zero semantic or proved-work failures. BYTE and INT tests cover every physical code, modern and legacy missing policies, FLOAT/DOUBLE output, signed zero, subnormals, magnitude limits, known/unknown zero counts, bounded spans and both sides of lookup admission. The kernel reduces producer row divisions to zero on lookup cases; exact binary64 division occurs during per-call table setup. General storage preflight is retained and may stop after its first fractional chunk.

The [historical negative control](proof/historical-negative-control-receipt.json) uses immutable source `00b7d873401cebf272a3445d0c08e14e89bbda5a`: zero semantic failures and 709 expected work failures. This is a structural negative control, distinct from the measured baseline DLL. The [O3 control](proof/frozen-kernel-o3-receipt.json) has the same frozen reciprocal header and identical case records, but preserves its earlier dirty-worktree/controller binding; it is not a second qualification of the final constructor source. Probe R allocation, readers and interrupts are mocked. Public tests provide the ownership and callback evidence.

The installed candidate passed [69,092 focused assertions](validation/focused-tests-receipt.json) across 136 blocks and ten files, with zero failures, errors, warnings or skips. Public regressions cover lookup storage/cache behavior and allocation callbacks, plus direct, full, partial, zero and invalid constructor regions, second-pass input changes, strict errors, signed zero and tags. The temporary ALTREP fixture compiles once in an isolated child process; its DLL remains loaded until that process exits. No production diagnostic counters or ALTREP test registration were added.

Runtime source checkpoint is `3ef04edca377e122befd77c8481831a60bda6b64`, candidate DLL `8834c59562bda7efe3ddb549f21318623d2ecf2fa76b637fa0c2617dd03c5fa5`; final test metadata is `56f4631701477c29d444dd293ca2bda752f625e8`. The measured baseline is the prior qualified facts build, DLL `e6e4c4edf80144803dcb556612ca86ca54b0c6568fc560c0c5ecc258fcd8bc13`. [Original](validation/original-build-receipt.json), [guard-corrected](validation/guard-corrected-build-receipt.json) and [final test-overlay](validation/final-tests-build-receipt.json) receipts preserve the lineage. Installation compiled one C object and no Rust crates, reusing the unchanged qualified Rust archive and R dependencies.

The original build controller exited 1 after a successful `R CMD INSTALL`: its post-build guard mistook help-index installation for another package. The original receipt had already recorded the install's exit 0; the derived receipt separately preserves the outer controller's exit 1. The corrected receipt classifies package-start lines; no build or R process was rerun for that correction. Later test-only fixes corrected oracle materialization/order assumptions and pointer-query bounds. The final test overlay changed no DLL, R databases or runtime source. Earlier diagnostic failures remain in local evidence; they are not reported as passing runs.

## Reproduction and validation

The existing [C probe controller](../work-count.py) includes the real headers and supports immutable source commits. Use `--root`, `--commit`, `--output` and `--require-proved`; the immutable historical negative control additionally uses `--source-commit 00b7d873401cebf272a3445d0c08e14e89bbda5a` and is expected to exit 1 for work failures. The [existing general controller](../../remaining-compact-kernels/run.py) and worker are referenced by exact source hashes rather than copied again. Executed supplement and construction controller/worker bytes are included. These timing controllers require separately qualified installed libraries and an exclusive CPU slot; the supplied receipts retain the actual commands and paths.

```sh
python3 benchmarks/integer-reciprocal/results-2026-10-04-lookup/validate.py
python3 -O benchmarks/integer-reciprocal/results-2026-10-04-lookup/validate.py
```

Validation checks the complete published file inventory, current runtime/probe/test source hashes, original/derived build lineage, executed controller bindings, raw observation counts and reconstructed numerical summaries. It launches no R process, compiler, package installation or timing. The portable native probe remains optional local analysis. No hosted C++ scan, package build, benchmark or broad CI matrix was added.
