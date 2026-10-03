# General compact arithmetic, intermediate screen, 2026-10-02

General typed spans improve arbitrary scalar and mixed-width arithmetic, but **parity remains unmet**. Across all 34 million-row cases, compact operations take 0.78–2.83× typed-double CPU and 0.85–3.61× bare-double CPU. Five of the eight original diagnostic cases still exceed the local 1.5× typed-double target. This is an intermediate candidate retained for further diagnosis, not a completed parity result.

Six balanced rounds compare clean merged baseline `fd72c344` with runtime candidate `48c2243f`. All 1,224 observations pass full result, storage, missing-mask/cache, source-state and native-entry checks. The original `x * 2` control has a baseline/candidate CPU ratio of 0.987–1.003×. The new operations improve by 1.14–12.98×, with substantial costs still visible in float output and inputs containing missing values.

## Original failing cases

These eight cases retain the original diagnostic input formulas and operation definitions. Numbers are compact CPU divided by the corresponding typed-double control, using the median per-call CPU from six observations. The target is a local diagnostic, not a CI timing threshold.

| Input | Missing values | Operation | Baseline / typed | Candidate / typed | At most 1.5× |
| --- | --- | --- | ---: | ---: | --- |
| int | no | `x * 1.01` | 5.802× | 2.019× | no |
| int | yes | `x * 1.01` | 6.395× | 2.130× | no |
| float | no | `x * 1.01` | 2.653× | 1.675× | no |
| float | yes | `x * 1.01` | 3.596× | 2.560× | no |
| int | no | compact plus typed double | 3.857× | 1.284× | yes |
| int | yes | compact plus typed double | 4.099× | 1.295× | yes |
| float | no | compact plus typed double | 4.365× | 0.911× | yes |
| float | yes | compact plus typed double | 4.787× | 1.759× | no |

## Complete operation matrix

CPU milliseconds per public call, including result allocation and automatic GC. Each range covers the corresponding width/missing cases. Speedups and ratios compare matching case medians; they are not ratios between range endpoints. The complete 34-case breakdown and paired-round ratios are in the [summary](results-2026-10-02-general-arithmetic-v1/timings/summary.csv).

| Operation | Before ms | After ms | Typed double ms | Bare double ms | Speedup | After / typed | After / bare |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `x * 2` | 0.242–0.326 | 0.241–0.328 | 0.286–0.316 | 0.252–0.289 | 0.987–1.003× | 0.781–1.149× | 0.852–1.237× |
| `x * 1.01` | 0.779–1.771 | 0.473–0.726 | 0.283–0.304 | 0.242–0.276 | 1.339–2.882× | 1.675–2.560× | 1.934–2.749× |
| compact plus typed double | 1.381–1.497 | 0.314–0.547 | 0.311–0.353 | 0.256–0.292 | 2.710–4.770× | 0.911–1.759× | 1.169–2.135× |
| `x + 0.1` | 0.898–7.768 | 0.474–0.725 | 0.271–0.298 | 0.243–0.269 | 1.896–12.721× | 1.664–2.677× | 1.789–2.869× |
| `x - 0.1` | 1.022–7.881 | 0.470–0.724 | 0.273–0.303 | 0.243–0.258 | 2.174–12.977× | 1.724–2.458× | 1.853–2.976× |
| `0.1 - x` | 1.026–7.868 | 0.472–0.724 | 0.269–0.303 | 0.245–0.266 | 2.176–12.957× | 1.627–2.695× | 1.922–2.724× |
| `1.01 / x` | 0.635–1.884 | 0.503–0.780 | 0.303–0.305 | 0.244–0.254 | 1.141–2.886× | 1.661–2.570× | 2.060–3.179× |
| int plus float | 1.841–1.843 | 0.615–0.932 | 0.314–0.330 | 0.284–0.285 | 1.976–2.999× | 1.959–2.825× | 2.164–3.273× |
| int times float | 1.831–1.854 | 0.619–0.941 | 0.344–0.347 | 0.259–0.261 | 1.971–2.959× | 1.785–2.733× | 2.394–3.609× |
| long plus float | 1.216–1.223 | 0.421–0.659 | 0.328–0.346 | 0.259–0.276 | 1.844–2.905× | 1.217–2.011× | 1.525–2.543× |

The first seven operations each cover int and float with and without missing values. Each mixed-width operation covers both missing cases. Int/float results stay float when their values fit; long/float results use double under the existing type lattice. The reciprocal cases include zero lanes. Typed outputs normalize nonfinite results to system missing, while bare R arithmetic preserves its own infinity and NaN behavior.

## What changed and what remains

The general producer reads each physical input directly within intersected spans. It dispatches source kind, scalar shape, operator and output kind outside the inner loop. It no longer expands these admitted cases into temporary double-value and missing-code arrays. It supports all four arithmetic operators, arbitrary scalar operands on either side, mixed compact widths, and ordinary double/integer/logical operands. Existing integer and binary-scaling specializations still run first.

Integer output uses a range and integrality proof. That scan stops when floating output becomes necessary. Float production combines computation, missing counting and range proof. Promotion discards provisional float rounding and recomputes the complete result from captured inputs as double. Out-of-range provisional values use an unobservable zero placeholder before promotion, avoiding an out-of-range C conversion. Missing arithmetic collapses tags to system missing, while exact input classification preserves the existing modern/legacy and noncanonical-import semantics.

Temporary read claims also protect ordinary owned operands when a reentrant write occurs between range proof and output production. Cleanup checks allocation identity, supports nesting and unwind, and preserves genuine sharing facts created during a callback. Plain R operands retain R's normal sharing rules. These claims do not protect previously retained foreign writable pointers.

The results establish useful gains and leave a clear next experiment. Float-producing scalar operations still cost roughly 0.47–0.78 ms per million rows, and int/float pairs containing missing values reach 0.93–0.94 ms. Float input with no missing values plus typed double reaches 0.91× typed-double CPU, while the corresponding input with missing values costs 1.76×. This contrast does not isolate the classifier's share of total time. The next diagnosis must inspect actual compiled loops, vectorization, input classification and output fit/count reductions. The standalone classifier probe is insufficient to attribute the remaining cost.

## Protocol and validation

Each build runs in a fresh R process per round. Build order alternates, and representation order rotates and reverses through six balanced rounds. Inputs use deterministic binary-exact values so all representations begin with identical numeric bytes. Timing includes public dispatch, output allocation and automatic GC. Construction, explicit GC, calibration, full qualification and hashing are excluded. Untimed warm-up settles lazy dependencies before native-entry counts are required.

Calibration targets 150 ms per retained interval. Actual CPU intervals range from **44 to 187 ms**, with two below 100 ms. Ratios use medians; no formal confidence interval is claimed. Other local builds, tests and benchmarks were stopped during this run. This is one arm64 macOS host using R 4.6.1 and Apple clang 21.0.0, without hardware isolation from ordinary desktop activity. The matrix measures warm constructed columns, not readers, retained-chunk throughput or end-to-end import workflows.

The clean candidate passes **64,804 full-suite assertions**, with zero failures, errors or skips and seven existing warnings. Coverage includes all 27 missing codes, adjacent noncanonical encodings, legacy layouts, IEEE values, signed zero, storage promotion, later-chunk overflow, preserved early precision, retained spans and reentrant ownership. Both benchmark builds separately pass all 102 untimed qualification cases. Forty-two manifest tests pass. The new controller tests pass normally and with Python assertions disabled; they reject incomplete matrices, invalid timing, missing native dispatch, changed results/source states/receipts and unbalanced positions. An [independent audit](results-2026-10-02-general-arithmetic-v1/validation/independent-audit.json) reproduced every CPU median, ratio and speedup from all twelve worker files.

[Raw observations](results-2026-10-02-general-arithmetic-v1/timings/raw.csv), [protocol](results-2026-10-02-general-arithmetic-v1/timings/protocol.json), [build provenance](results-2026-10-02-general-arithmetic-v1/timings/provenance-before.json), [full-suite observations](results-2026-10-02-general-arithmetic-v1/validation/acceptance-full-tests.csv), [validation source binding](results-2026-10-02-general-arithmetic-v1/validation/source-binding.json), [source patch](results-2026-10-02-general-arithmetic-v1/timings/source.patch), [publication source map](results-2026-10-02-general-arithmetic-v1/publication-source-map.json) and [artifact manifest](results-2026-10-02-general-arithmetic-v1/publication-manifest.json) retain this intermediate result. Build logs substitute private paths; source and published hashes are both recorded. Installed libraries are not published. The package runtime and tests are unchanged from the measured candidate; subsequent branch commits add only benchmark tooling, CI coverage and documentation.
