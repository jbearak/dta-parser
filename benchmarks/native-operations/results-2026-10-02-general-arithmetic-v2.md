# General compact arithmetic, final acceptance, 2026-10-02

General typed spans and scalar range proofs make all 30 changed million-row cases **1.24–27.17× faster** than merged main. The existing `x * 2` controls remain within 0.996–1.000×. Integer general scaling reaches 0.86× typed-double CPU without missing values and 1.06× with missing values. **Broad parity remains unmet:** across all 34 cases, compact operations take 0.75–2.77× typed-double CPU and 0.85–3.07× bare-double CPU. Fifteen cases exceed the local 1.5× typed-double diagnostic target.

Six balanced rounds compare clean merged baseline `460db463669336ea7a79aa52f797b7bd5baf5bdb` with integrated candidate `cf72cd8efb318d9d9851f5a51f8e947fd3b158db`. All 1,224 observations pass full result, storage, missing-mask/cache, source-state and native-entry checks. This report supersedes the [intermediate screen](results-2026-10-02-general-arithmetic-v1.md) for the final implementation; its staged experiments remain separately preserved below.

## Original diagnostic cases

These eight cases retain the original input formulas and operation definitions. Ratios use median CPU per public call from six observations. The 1.5× target is a local diagnostic, not a CI timing threshold. Six cases pass; both float scaling cases remain above it.

| Input | Missing values | Operation | Before / typed | After / typed | After / bare | Speedup |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| int | no | `x * 1.01` | 5.179× | 0.861× | 0.976× | 5.856× |
| int | yes | `x * 1.01` | 6.551× | 1.064× | 1.086× | 6.058× |
| float | no | `x * 1.01` | 2.777× | 1.542× | 1.584× | 1.861× |
| float | yes | `x * 1.01` | 3.742× | 2.008× | 2.047× | 1.858× |
| int | no | compact plus typed double | 3.913× | 1.269× | 1.581× | 3.006× |
| int | yes | compact plus typed double | 4.305× | 1.305× | 1.497× | 3.354× |
| float | no | compact plus typed double | 4.566× | 0.904× | 1.146× | 4.524× |
| float | yes | compact plus typed double | 4.710× | 1.462× | 1.845× | 3.119× |

## Complete operation matrix

Every constructed case appears below. CPU milliseconds include public dispatch, result allocation and automatic GC. Ratios compare matching case medians; a final column marks all 15 cases exceeding 1.5× typed-double CPU. Absolute control times, actual repetition counts and paired-round ratios remain in the [summary](results-2026-10-02-general-arithmetic-v2/timings/summary.csv) and [raw observations](results-2026-10-02-general-arithmetic-v2/timings/raw.csv).

| Input | Missing | Operation | Before ms | After ms | Speedup | After / typed | After / bare | Above 1.5× typed |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| float | no | `x * 2` | 0.326 | 0.327 | 0.997× | 1.104× | 1.229× | no |
| float | yes | `x * 2` | 0.324 | 0.324 | 1.000× | 1.101× | 1.332× | no |
| int | no | `x * 2` | 0.242 | 0.242 | 0.996× | 0.745× | 0.854× | no |
| int | yes | `x * 2` | 0.241 | 0.241 | 1.000× | 0.888× | 0.901× | no |
| float | no | `x * 1.01` | 0.778 | 0.418 | 1.861× | 1.542× | 1.584× | **yes** |
| float | yes | `x * 1.01` | 1.007 | 0.542 | 1.858× | 2.008× | 2.047× | **yes** |
| int | no | `x * 1.01` | 1.557 | 0.266 | 5.856× | 0.861× | 0.976× | no |
| int | yes | `x * 1.01` | 1.750 | 0.289 | 6.058× | 1.064× | 1.086× | no |
| float | no | compact plus typed double | 1.414 | 0.313 | 4.524× | 0.904× | 1.146× | no |
| float | yes | compact plus typed double | 1.469 | 0.471 | 3.119× | 1.462× | 1.845× | no |
| int | no | compact plus typed double | 1.370 | 0.456 | 3.006× | 1.269× | 1.581× | no |
| int | yes | compact plus typed double | 1.365 | 0.407 | 3.354× | 1.305× | 1.497× | no |
| float | no | `x + 0.1` | 0.956 | 0.417 | 2.293× | 1.535× | 1.640× | **yes** |
| float | yes | `x + 0.1` | 3.031 | 0.540 | 5.615× | 1.923× | 2.207× | **yes** |
| int | no | `x + 0.1` | 4.770 | 0.265 | 17.974× | 0.875× | 0.989× | no |
| int | yes | `x + 0.1` | 7.512 | 0.288 | 26.112× | 1.062× | 1.092× | no |
| float | no | `x - 0.1` | 0.993 | 0.416 | 2.391× | 1.403× | 1.624× | no |
| float | yes | `x - 0.1` | 3.095 | 0.545 | 5.677× | 1.831× | 2.245× | **yes** |
| int | no | `x - 0.1` | 5.285 | 0.264 | 20.049× | 0.872× | 1.065× | no |
| int | yes | `x - 0.1` | 7.875 | 0.290 | 27.171× | 1.075× | 1.095× | no |
| float | no | `0.1 - x` | 0.985 | 0.417 | 2.363× | 1.470× | 1.650× | no |
| float | yes | `0.1 - x` | 2.970 | 0.540 | 5.501× | 1.997× | 2.040× | **yes** |
| int | no | `0.1 - x` | 4.734 | 0.264 | 17.929× | 0.881× | 0.986× | no |
| int | yes | `0.1 - x` | 7.538 | 0.288 | 26.182× | 1.018× | 1.134× | no |
| float | no | `1.01 / x` | 0.647 | 0.506 | 1.279× | 1.650× | 2.083× | **yes** |
| float | yes | `1.01 / x` | 0.878 | 0.708 | 1.240× | 2.230× | 2.784× | **yes** |
| int | no | `1.01 / x` | 1.490 | 0.664 | 2.245× | 2.071× | 2.597× | **yes** |
| int | yes | `1.01 / x` | 1.866 | 0.662 | 2.821× | 2.285× | 2.596× | **yes** |
| int | no | int plus float | 1.837 | 0.615 | 2.989× | 1.852× | 2.363× | **yes** |
| int | yes | int plus float | 1.843 | 0.862 | 2.138× | 2.737× | 3.059× | **yes** |
| int | no | int times float | 1.829 | 0.619 | 2.957× | 1.977× | 2.296× | **yes** |
| int | yes | int times float | 1.848 | 0.871 | 2.122× | 2.766× | 3.068× | **yes** |
| long | no | long plus float | 1.219 | 0.421 | 2.895× | 1.355× | 1.543× | no |
| long | yes | long plus float | 1.212 | 0.572 | 2.118× | 1.737× | 2.046× | **yes** |

The first seven operations each cover int and float, with and without missing values. Each mixed-width operation covers both missing states. Inputs use binary-exact fractions and include zero lanes for reciprocal operations. Int/float results remain float when their binary64 results fit; long/float results use double under the existing storage policy. Typed controls apply Stata invalid-result normalization. Bare reciprocal controls preserve R’s infinity/NaN behavior, so they are throughput controls with a separately checked oracle.

The remaining costs extend beyond the eight original cases. Reciprocal operations take 1.65–2.28× typed-double CPU. Int/float addition and multiplication take 1.85–2.77×, and long/float addition with missing values takes 1.74×. The changed float scalar addition, subtraction and multiplication cases with missing values take 1.83–2.01×. These results justify separate follow-up work; they do not establish ordinary-double parity for every operation.

## What changed

The general producer reads each physical input directly within intersected spans. It dispatches source kind, scalar shape, operator and output kind outside the row loop, avoiding decoded double-value and missing-code scratch arrays. It supports all four arithmetic operators, scalar operands on either side, mixed compact widths and ordinary double/integer/logical operands. Existing integer and binary-scaling specializations run first.

Integer output retains range and integrality preflight. Float promotion discards provisional rounding and recomputes the complete result from captured inputs as double. Out-of-range provisional values use an unobservable finite placeholder before narrowing. Arithmetic collapses missing tags to system missing, while input classification preserves modern/legacy layouts, noncanonical imports, NaNs and the existing infinity policy.

Three refinements reduce work inside the native loops. Missing float lanes gain quiet-NaN bits in 32-bit storage before widening, keeping their classification mask narrow. For compact integers and finite scalars, checking both full signed physical endpoints can prove every result finite and storable before iteration; the producer then reuses the captured missing count and removes output-validity, magnitude and count reductions. For compact floats and finite scalars, exact monotone searches over ordered binary32 encodings find the input interval whose binary64 operation fits float output. The producer checks that interval in source width and substitutes a proved finite anchor before narrowing. It still counts observed infinities and promotes on observed finite values outside the interval. These proofs cover broad operator/storage/scalar domains; unsafe cases retain the general path.

The proofs use the same protected captured descriptor and backing as production. Temporary read claims also protect ordinary owned operands across reentrant writes between preflight and output allocation. Cleanup checks identity, supports nesting and unwind, and preserves genuine sharing facts created during callbacks. Plain R operands retain their usual borrowing rules; previously retained foreign writable pointers are outside this contract.

## Compiler diagnosis and isolated experiments

Each row below is a separate before/after experiment with 432 observations. Its gain cannot be multiplied into an end-to-end speedup. All retain the original eight cases and four unchanged `x * 2` controls.

| Change | Targeted gain | Remaining target gap in that experiment |
| --- | ---: | --- |
| 32-bit masked-OR missing normalization | 1.128× float scaling with missing; 1.198× float plus double with missing | scaling 2.210× typed; pair 1.343× typed |
| Integer scalar full-domain proof | 2.319× scaling without missing; 2.113× with missing | 0.869× and 0.979× typed |
| Float scalar exact fit interval | 1.131× scaling without missing; 1.190× with missing | 1.392× and 1.933× typed |

A preceding conditional float-NaN select was rejected before timing: the compiler moved the selection after widening and retained the original 64-bit mask sequence. Explicit masked OR preserved the intended 32-bit operations. The interval producer’s compiled loop uses source-width fit/classification before widening and removes binary64 output-validity/magnitude reductions. [Static loop excerpts](results-2026-10-02-general-arithmetic-v2/diagnostics/float-interval-loop-excerpt.json) and [compiler receipts](results-2026-10-02-general-arithmetic-v2/diagnostics/float-interval-compiler-diagnostic.json) establish the generated mechanism, not its runtime cost. The retained timing experiments supply the performance evidence.

The staged integer-missing pair improved by about 9% outside the changed float paths; that control difference is unattributed. Float scaling’s final absolute CPU, 0.418/0.542 ms without/with missing, closely matches the interval experiment’s 0.418/0.543 ms. Its final typed ratios are higher because the independently timed typed controls were faster. This is why the final report retains every control and does not substitute a favorable staged ratio.

A high-number threshold alone cannot replace raw-import classification. Modern input can preserve noncanonical finite values and observed infinities; arithmetic invalidates infinities while public raw missing inspection treats modern infinity as observed. A cached missing count therefore does not prove a canonical or finite input domain. The scalar proofs preserve those inputs instead of silently narrowing the importer contract. A protected canonical-domain or no-observed-infinity fact is a possible later optimization, requiring producer/reader/mutation lifecycle evidence and measurement.

## Protocol, validation and limits

Each build runs in a fresh R process per round. Build order alternates and representation order follows all six permutations. Timing includes public dispatch, output allocation and automatic GC; construction, explicit GC, warm-up, calibration and full hashing are excluded. Calibration targets 150 ms, while actual retained CPU and wall intervals are **100–188 ms**. Ratios are medians, without a formal confidence interval. Other local builds, tests and benchmarks were stopped during timing. This is one arm64 macOS host with R 4.6.1 and Apple clang 21.0.0, without hardware isolation from ordinary desktop activity.

The matrix measures warm constructed columns. It does not measure file reading, retained-chunk throughput or an end-to-end import workflow. Typed doubles apply matching invalid-result rules but do not incur identical narrow-output storage/promotion work. Untimed tests cover retained chunks, all 27 missing tags, legacy and modern raw encodings, IEEE values, signed zero, exact boundary neighbors, later-chunk promotion, early-result precision, nonzero safe anchors and reentrant ownership.

The clean final candidate passes **84,707 full-suite assertions**, with zero failures, errors or skips and seven existing warnings. All 1,778 manifest blocks are observed and all 465 package source hashes match the build receipt. Both final builds pass 102 separate untimed benchmark qualifications. Forty-two manifest tests pass; controller tests pass normally and with Python assertions disabled. Conformance passes 32,085 TypeScript cell comparisons, ten native gates plus the canonical oracle, source archive checks and packaged R tests. `R CMD check` retains three known warnings and two notes concerning the macOS SDK/vendor build files, package-source metadata and existing Rust/non-API R calls; it is not warning-free.

An [independent artifact audit](results-2026-10-02-general-arithmetic-v2/timings/independent-audit.json) reproduced all 1,224 worker/raw rows, 68 summary rows, every CPU median, paired/control ratio and speedup. It verified all six representation orders, result/storage/source identity, native entries in both builds and before/after source/library/controller/runtime bindings. No new measurements were run for that audit.

The final, integer-bounds and float-interval controllers hash the exact worker Rscript and R runtime before and after execution and compare the runtime with both build receipts. The earlier masked-OR controller recorded build runtime hashes and R version but lacked that exact launcher check during timing. Its [post-run supplement](results-2026-10-02-general-arithmetic-v2/diagnostics/post-run-runtime-supplement.json) matched the actual launcher/runtime afterward; it cannot prove historical stability during that earlier run. Original receipts are preserved.

[Final protocol](results-2026-10-02-general-arithmetic-v2/timings/protocol.json), [build provenance](results-2026-10-02-general-arithmetic-v2/timings/provenance-before.json), [source delta](results-2026-10-02-general-arithmetic-v2/timings/source.patch), [full-suite observations](results-2026-10-02-general-arithmetic-v2/validation/full-tests.csv), [validation binding](results-2026-10-02-general-arithmetic-v2/validation/validation-binding.json), [conformance log](results-2026-10-02-general-arithmetic-v2/validation/conformance.log), [publication source map](results-2026-10-02-general-arithmetic-v2/publication-source-map.json) and [artifact manifest](results-2026-10-02-general-arithmetic-v2/publication-manifest.json) bind the published evidence. Private paths are substituted with both original and published hashes recorded. Installed libraries are not published. The measured package source is unchanged; later publication commits contain only evidence and documentation.
