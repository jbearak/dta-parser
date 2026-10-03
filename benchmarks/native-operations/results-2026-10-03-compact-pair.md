# Compact pair arithmetic, final acceptance, 2026-10-03

Compact int16/float addition and multiplication are **1.72–1.86× faster** than merged general arithmetic, reaching **1.09–1.48× typed-double CPU** in these four million-row cases. Long/float addition improves 1.01× without missing values and 1.07× with missing values. **Broad parity remains unmet:** across all 34 cases, compact operations take 0.75–2.34× typed-double CPU and 0.84–2.81× bare-double CPU; twelve cases exceed the local 1.5× diagnostic target.

Six balanced rounds compare clean baseline `8e4e1cf957558d727a3b8b092df05d2f3dca2f8d` with candidate `af9f76e3eb3b0b0328ec6609ddb017d42edb3c9d`. All 1,224 observations pass complete result/storage, missing-mask/cache, input-state/hash and native-entry checks. A later integration with main `20ec12ce` is qualified separately; the measured artifacts remain unchanged.

## Complete operation matrix

CPU milliseconds are medians per public call, including result allocation and automatic GC. Every case and control is retained. The 1.5× target is a local diagnostic, not a CI timing threshold. Actual intervals and paired-round ratios remain in the [raw observations](results-2026-10-03-compact-pair/timings/raw.csv), [summary](results-2026-10-03-compact-pair/timings/summary.csv) and [independent audit](results-2026-10-03-compact-pair/timings/independent-audit.json).

| Input | Missing | Operation | Before ms | After ms | Speedup | After / typed | After / bare | Above 1.5× typed |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| float | no | `x * 2` | 0.327 | 0.324 | 1.010× | 1.144× | 1.225× | no |
| float | yes | `x * 2` | 0.324 | 0.324 | 0.998× | 1.167× | 1.287× | no |
| int | no | `x * 2` | 0.242 | 0.242 | 0.997× | 0.750× | 0.835× | no |
| int | yes | `x * 2` | 0.239 | 0.240 | 0.998× | 0.821× | 0.942× | no |
| float | no | `x * 1.01` | 0.416 | 0.417 | 0.997× | 1.548× | 1.651× | **yes** |
| float | yes | `x * 1.01` | 0.541 | 0.542 | 0.999× | 1.840× | 2.134× | **yes** |
| int | no | `x * 1.01` | 0.279 | 0.264 | 1.060× | 0.869× | 0.955× | no |
| int | yes | `x * 1.01` | 0.288 | 0.288 | 1.001× | 1.068× | 1.089× | no |
| float | no | compact plus typed double | 0.328 | 0.314 | 1.046× | 1.012× | 1.121× | no |
| float | yes | compact plus typed double | 0.459 | 0.462 | 0.992× | 1.416× | 1.717× | no |
| int | no | compact plus typed double | 0.450 | 0.427 | 1.054× | 1.204× | 1.477× | no |
| int | yes | compact plus typed double | 0.406 | 0.405 | 1.002× | 1.313× | 1.445× | no |
| float | no | `x + 0.1` | 0.416 | 0.416 | 1.000× | 1.555× | 1.565× | **yes** |
| float | yes | `x + 0.1` | 0.540 | 0.542 | 0.997× | 2.008× | 2.063× | **yes** |
| int | no | `x + 0.1` | 0.264 | 0.263 | 1.005× | 0.872× | 0.983× | no |
| int | yes | `x + 0.1` | 0.290 | 0.288 | 1.006× | 0.990× | 1.138× | no |
| float | no | `x - 0.1` | 0.417 | 0.415 | 1.003× | 1.415× | 1.719× | no |
| float | yes | `x - 0.1` | 0.540 | 0.540 | 1.000× | 1.834× | 2.149× | **yes** |
| int | no | `x - 0.1` | 0.262 | 0.261 | 1.005× | 0.899× | 0.982× | no |
| int | yes | `x - 0.1` | 0.288 | 0.289 | 0.997× | 1.074× | 1.098× | no |
| float | no | `0.1 - x` | 0.418 | 0.416 | 1.007× | 1.545× | 1.581× | **yes** |
| float | yes | `0.1 - x` | 0.540 | 0.540 | 1.000× | 2.014× | 2.226× | **yes** |
| int | no | `0.1 - x` | 0.263 | 0.262 | 1.005× | 0.884× | 1.037× | no |
| int | yes | `0.1 - x` | 0.290 | 0.286 | 1.013× | 1.025× | 1.128× | no |
| float | no | `1.01 / x` | 0.516 | 0.519 | 0.993× | 1.717× | 2.153× | **yes** |
| float | yes | `1.01 / x` | 0.708 | 0.706 | 1.003× | 2.340× | 2.812× | **yes** |
| int | no | `1.01 / x` | 0.664 | 0.659 | 1.007× | 2.253× | 2.598× | **yes** |
| int | yes | `1.01 / x` | 0.659 | 0.659 | 1.000× | 2.300× | 2.600× | **yes** |
| int | no | int plus float | 0.615 | 0.357 | 1.720× | 1.091× | 1.382× | no |
| int | yes | int plus float | 0.867 | 0.467 | 1.857× | 1.430× | 1.800× | no |
| int | no | int times float | 0.619 | 0.358 | 1.729× | 1.148× | 1.317× | no |
| int | yes | int times float | 0.871 | 0.469 | 1.858× | 1.479× | 1.662× | no |
| long | no | long plus float | 0.418 | 0.414 | 1.011× | 1.323× | 1.546× | no |
| long | yes | long plus float | 0.572 | 0.535 | 1.070× | 1.720× | 1.969× | **yes** |

The four int/float cases improve from 0.615–0.871 ms to 0.357–0.469 ms. Their output remains compact float with exactly the existing rounding and storage behavior. The unchanged scalar and compact-plus-double paths remain controls. Three unchanged no-missing cases show apparent gains of 4.6–6.0%: integer general scaling and int/float compact plus double. These are unattributed control differences. They are not evidence of an additional optimized path.

Float scaling's absolute CPU remains 0.417/0.542 ms without/with missing values. Its final typed ratios are 1.548×/1.840× because the typed controls are timed independently. Reciprocal operations still take 1.72–2.34× typed-double CPU; missing long/float addition takes 1.72×. Float scalar addition, subtraction and reverse subtraction retain material gaps. This PR preserves useful pair improvements while leaving those measured residuals for separate work.

## Implementation and numerical contract

The general compact-pair producer uses physical input bounds to remove redundant binary64 result classification. Finite byte/int16/int32/binary32 pairs cannot overflow the observed binary64 range under addition, subtraction, multiplication or division by a nonzero finite operand. Exact input classification remains, including legacy reserved values, noncanonical imported float encodings, NaNs and observed infinities. Division preserves finite / observed infinity as signed zero; inherited missing values, infinite numerators and zero denominators produce system missing.

For addition, subtraction and multiplication with float output, a second producer operates directly in binary32 when both compact operands convert exactly: byte/int16/binary32, with at least one binary32 operand. Long, ordinary/foreign inputs, scalar recycling and temporal values retain existing paths. Operator dispatch stays outside the typed tile, and source capture/read claims are unchanged.

A finite binary32 product needs at most 48 significant bits and is exact in binary64. For addition/subtraction, normalized exponent gaps through 29 produce an exact binary64 result; for larger gaps, the smaller operand plus binary64 rounding error cannot cross a binary32 nearest midpoint, including the smaller spacing below a binade boundary. Directed rounding composes across nested grids. Thus these admitted operations retain the established binary64-then-float value result. The [multiplication proof](results-2026-10-03-compact-pair/proofs/f32-equivalence/proof.md) and [addition/subtraction proof](results-2026-10-03-compact-pair/proofs/f32-add-sub-equivalence/proof.md) give the assumptions and bounds.

Storage selection still follows the established **rounded binary64 expression**. A rounded float magnitude strictly inside/outside the exactly represented observed limit proves fit/promotion by monotonicity. Equality remains ambiguous: the existing binary64 producer reruns with provisional reductions reset. Promotion recomputes every result from the original captured inputs, never by widening already rounded float outputs. Tests distinguish an exact rational sum above the limit whose binary64 result rounds back to the limit from a binary64 result that remains above it. Missing tags collapse to system missing, and the output count uses the union of invalid lanes.

## Isolated experiments and compiler evidence

These are separate before/after experiments, not factors to multiply into an end-to-end gain:

| Change | Observations | Targeted improvement | Targeted typed-double ratio after change |
| --- | ---: | --- | --- |
| Compact-pair binary64 domain proof | 432 | 1.028–1.222× across selected mixed cases | 1.106–2.138× |
| Direct binary32 multiplication | 648 | float×float 1.948×/1.700×; int16×float 1.546×/1.517×, without/with missing | 0.870–1.490× |
| Direct binary32 addition/subtraction | 648 | 1.512–1.568× across four mixed cases | 1.012–1.481× |

Each stage retains full controls and its own source/library/runtime bindings in the [published diagnostics](results-2026-10-03-compact-pair/diagnostics). The addition/subtraction stage has an unchanged long/float control 1.053× faster; other controls remain 0.995–1.012×. The multiplication stage has a missing mixed-add control 5.5% slower by ratio of medians, while twelve other unchanged controls remain 0.993–1.008× and missing long/float is 3.7% faster.

That mixed-add anomaly remains unattributed. Its paired-round median gain is 0.974× versus 0.948× for the ratio of medians. Candidate-second rounds are slower; candidate-first rounds are near equal or faster. Full normalized producer disassembly has 61,188 matching instructions apart from relocations to the same R_NaReal and R_CheckUserInterrupt symbols. A separate receipt regenerates both disassemblies from the source-bound DLLs. This establishes normalized producer-body equivalence, not unchanged whole-call execution or a cause for the timing difference. Caller layout, allocation history, caches and dynamic counts remain outside the static comparison.

Representative emitted int16/float tiles use direct vector `fadd.4s`, `fsub.4s` and `fmul.4s`, exact integer-to-float conversion, missing-union counting and an unsigned magnitude reduction. They have no binary64 lane conversions. [Loop excerpts and their binding](results-2026-10-03-compact-pair/diagnostics/float-add-sub-validation-binding.json) establish the intended mechanism, not its performance contribution. Timings provide the separate evidence of speed.

## Qualification and limits

The multiplication standalone probe compares 36,914,944 cases per optimized/UBSan build, with four rounding modes, 19 whole-column models and fifteen independent rational witnesses. The addition/subtraction probe compares 70,004,784 cases per build, with eight operator/mode records, 38 column models and 814 independent rational witnesses. Outputs match exactly with no mismatch or sanitizer finding. Independent audits replay every saved rational witness. These are reviewed standalone models with extracted, source-bound classifiers; they do not themselves establish package dispatch, ownership or ABI correctness. Floating exception traces and cross-platform performance are outside their claim.

The clean measured candidate passes **98,134 full-suite assertions**, covering all 1,797 manifest blocks, with zero failures, errors or skips and seven existing warnings. Both builds pass the original 102 untimed operation cases with identical full hashes/storage/source states and the expected native entry counts. Six controller guards pass normally and with Python assertions disabled; seven manifest guards pass. The required conformance command passes from frozen af9, including the source archive build/check. That historical script deleted its temporary archive, so its preserved log is not presented as an independently retained archive hash. The clean installed build/full-suite binding is separate.

The separately built integration `dbcf75cbfe589b5ac2a78166d1e436faa7bbb896` merges main `20ec12cebcce0afa6981c82a59686fa055975b6f`. Its five arithmetic runtime/test files are byte-identical to the measured candidate. It passes **98,625 full-suite assertions** across all 1,804 manifest blocks, with zero failures, errors or skips and seven existing warnings; all 102 untimed operation results match the measured candidate exactly. Required conformance passes with the temporary source archive retained. The [archive receipt](results-2026-10-03-compact-pair/integration/validation/integration-conformance.json) verifies 348 packaged source files against immutable Git blobs and records twenty explicit build exclusions. The [integration binding](results-2026-10-03-compact-pair/integration/validation/integration-binding.json) ties these checks to the clean installed build. These are additional correctness checks, not new performance measurements.

The independent final performance audit reproduces all 1,224 worker/raw rows, the 68-row summary, every median/control/paired ratio, all six representation orders, native counts and complete source/library/controller/runtime inventories. It independently derives source missing positions and reciprocal zero-denominator normalization and compares both separate no-clock qualifications. It ran after the exclusive measurements, without new measurements.

Each build runs in a fresh R process per round; build order alternates and representations cover all six permutations. Timing includes dispatch, allocation and automatic GC, excluding construction, explicit GC, qualification, hashing and calibration. The exact worker launcher/runtime and complete source/library/controller identities are checked before and after. Calibration targets 150 ms; retained CPU intervals actually range 99–182 ms and wall intervals 100–182 ms. The three isolated stages have respective CPU ranges 101–186, 51–184 and 101–182 ms. Ratios have no formal confidence interval. This is one arm64 macOS host with R 4.6.1 and Apple clang 21.0.0, without hardware isolation from normal desktop activity.

The final matrix measures constructed million-row inputs, retaining all 34 original cases. Missing fixtures contain 1,003 periodic missing values in the left input and 1,010 in the second input, about 0.1% per input. Dense or clustered missing distributions are outside this throughput claim. Additional float×float and mixed subtraction/division cases appear in the isolated 18-case screens. Retained chunks, all missing tags, imported physical edge values, IEEE values, signed zeros, delayed promotion and reentrant ownership are correctness coverage, not retained-throughput claims. Typed doubles apply Stata result normalization but do not perform identical narrow-output storage/promotion work. Bare reciprocal controls retain R infinities/NaNs and have a separately checked oracle. No result establishes universal ordinary-double parity or end-to-end reader speed.

The [protocol](results-2026-10-03-compact-pair/timings/protocol.json), [source delta](results-2026-10-03-compact-pair/timings/source.patch), [validation binding](results-2026-10-03-compact-pair/validation/validation-binding.json), [source map](results-2026-10-03-compact-pair/publication-source-map.json) and [artifact manifest](results-2026-10-03-compact-pair/publication-manifest.json) bind the evidence. Private paths are substituted with original/published hashes retained. Installed binaries and complete disassemblies are not published.

## Reproduction and archived tools

Python, R and shell files inside the evidence directory are historical snapshots. They preserve the scripts used for these runs, with private paths redacted as documented by the source map. They are not executable entrypoints from the published tree. In particular, changing the archived controller to import its neighboring `run.py` would still omit that recorder's repository-relative dependencies and would change the measured controller bytes. Use the maintained [general controller](general-run.py), [worker](general-worker.R), [source builder](../r-file-readers/build-snapshot.py) and [reproduction instructions](README.md#general-arithmetic) for a new run. Invoke required package conformance with `DTA_REQUIRE_R_CONFORMANCE=1 sh scripts/conformance.sh` from the repository root.

A review found that the historical full-suite binder counted only the exact string `TRUE`, allowing malformed status strings to count as false. The actual saved records contain only `TRUE`/`FALSE` and were independently audited. The executable [post-publication verifier](verify-compact-pair-evidence.py) now rejects malformed flags and counts, checks both complete saved suites, requires receipt and observed source inventories to agree, and verifies the original publication manifest and required conformance marker. Run it with `python3 benchmarks/native-operations/verify-compact-pair-evidence.py`; its corruption tests also run with Python assertions disabled in CI. This additional check does not rerun tests, timings or the private source-archive validation. The original scripts, receipts and measurements remain unchanged.
