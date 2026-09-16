# Reader parity implementation results

Owned Arrow buffers substantially improve the India full read, and wider DTA execution reduces its full-read gap. The implementation has not established general parity with Stata. DTA full reads still trail Stata, projection regressions remain, and some completed downstream workflows are slower. **All experimental controls remain disabled by default.** Full reads and projections must pass independently.

The final reader and downstream screens use source `9ac470bb07029db52e02b02780999cf8bec75291`, compared with baseline `b41d8f9d8dba260b8c93d5c7d83cb12ee8102600`. Build, installation, input and worker hashes are recorded with the [results](reader-parity-results/README.md). These are screening results, not a release qualification.

## Implementation

The experiments add wider DTA numeric kernels, bounded read queues and a prepared DTA source that retains the opened file through metadata selection. Direct full and selected reads reuse one decode plan. Arrow completion separates preparation from decode/fill, allocates protected destinations on R's thread, and completes verification before publication. Value-dependent classifications use the prepared fallback.

Owned compact numeric columns retain immutable Arrow buffers behind independent R handles. Byte, int, long and float storage are supported; doubles and strings keep their existing representations. Mutable access detaches storage. Native consumers share read-region operations, and writing/signatures preserve canonical 65,536-row batches across source chunks. Summaries carry one accumulator across chunks to preserve arithmetic order. Legacy missing-layout decisions apply to the entire column before normalization.

Owned and bounded Arrow reading currently use separate paths; owned mode takes precedence when both are requested. See the [DTA](reader-parity-dta-implementation.md), [Arrow](reader-parity-arrow-implementation.md) and [owned-column](reader-parity-owned-implementation.md) notes for interfaces, ownership and limitations.

## Measurement scope

The local manifest contains 17 inputs and 209 full/projection cases. Current-profile Arrow files were generated once by the baseline installation and checked against its DTA value/metadata signatures. The final `screen-v3-combined` run covers four selected cases, with one cohort and six fresh-process observations per method. Reader initialization is timed; process startup is excluded. The filesystem protocol is warm. R uses its adaptive thread policy; Stata 18 has eight licensed processors on the same 16-logical-CPU host.

The candidate combines prepared DTA selection, wider kernels, four 4 MiB queue blocks under a 16 MiB queue budget, and owned Arrow columns. The screen cannot isolate each component's contribution. Selected cases qualify baseline/candidate R values and metadata before timing. Stata loads the same hashed DTA and checks dimensions; cross-language semantic conformance is separate.

The screen reports `eligible=false` and `timing_parity=false`. The [benchmark protocol](../../benchmarks/reader-parity/README.md) requires two balanced cohorts, both fresh and warm modes, and at least 12 observations per method/case; its default is 20. Intervals below 10 ms are indeterminate. Tiny fresh reads cannot qualify under this timer rule; batched warm observations do not resolve their fresh measurements. Screening already rejects general parity, so the complete release timing matrix was not run.

The controller's warm mode performs an untimed read and full R garbage collection. Large cases then have **one timed read**, not repeated-read steady-state measurement. Small warm cases repeat calls to improve resolution. Separate native repeated-read/collection stress tests check ownership and reclamation; they do not replace matched warm timing or establish long-running RSS stability. The final reader screen reported here is fresh-only. No cold-filesystem-cache conclusion is claimed.

## Full reads and projections

Matched medians are in seconds; memory figures below use decimal GB.

| Case and reader | Baseline | Candidate | Stata |
| --- | ---: | ---: | ---: |
| India full, DTA | 0.7460 | 0.6160 | 0.4705 |
| India full, verified Arrow | 0.5685 | 0.2870 | 0.4705 |
| 100 MB full, DTA | 0.0475 | 0.0440 | 0.0100 |
| 100 MB full, verified Arrow | 0.0310 | 0.0310 | 0.0100 |
| India 30 scattered columns, DTA | 0.2640 | 0.2720 | 0.3160 |
| India 30 scattered columns, verified Arrow | 0.0705 | 0.0720 | 0.3160 |

India has 724,115 rows and 5,972 columns. Owned Arrow cuts its full-read time by about 50% against the matched baseline and falls below Stata in this screen. Median process peak RSS drops from 10.281 GB to 5.401 GB; Stata uses 5.257 GB. DTA improves by about 17%, but remains above Stata. Its median peak RSS is essentially unchanged, 5.238 versus 5.235 GB.

The 100 MB full-read gap remains large for both readers. India projection times regress by about 3% for DTA and 2% for Arrow, despite both remaining below Stata. Owned Arrow projection peak RSS falls from 0.266 to 0.242 GB. These regressions cannot be offset by the full-read improvement. Mixed-fixture fresh Stata medians are about 1 ms, below the resolution floor; precise ratios are not justified.

Earlier controls belong to source `534ede17`, not the final candidate. Its no-experiment screen stayed near baseline, with India full medians of 0.7465 seconds for DTA and 0.5735 for Arrow. Prepared DTA alone changed little, including metadata discovery at 0.3430 versus 0.3435 seconds. The bounded Arrow screen showed little timing change on supported measured cases and did not include India full reads. Earlier tall-wide improvements also remained slower than Stata. Those controls explain selection of the final experiments but do not substitute for final-source measurements.

## Completed downstream work

`downstream-v3` uses the same final source and combined controls, with six observations per variant. Its workflow clock includes import, setup and consumption. Sparse work sums all rows of up to 30 numeric columns; traversal computes the complete signature. First-write setup includes an isolated saved copy. The R-vector workload copies one numeric column into ordinary R storage and computes its mean.

| Arrow workflow | Baseline | Candidate |
| --- | ---: | ---: |
| India full, sparse summaries | 0.5920 | 0.3100 |
| India full, full signature | 1.2785 | 0.9760 |
| India full, saved copy and first write | 1.0510 | 0.5110 |
| India full, ordinary R vector | 0.5855 | 0.3070 |
| India 30 columns, sparse summaries | 0.1020 | 0.1080 |
| India 30 columns, ordinary R vector | 0.0760 | 0.0805 |

The India full import gain survives completed consumption. Final summary changes reduce the earlier v2 sparse-consumer penalty, but projected Arrow sparse and ordinary-vector workflows still regress by about 6%. Projected DTA sparse work regresses from 0.2900 to 0.3020 seconds. The 100 MB Arrow sparse workflow is 0.0360 versus 0.0350 seconds; its full-signature workflow is unchanged at 0.0530 seconds. Tiny operation differences remain resolution-sensitive. These are R baseline/candidate comparisons, without a Stata downstream claim.

Process peak RSS includes import, setup and consumption, not just one retained result. India full Arrow first-write peak falls from 13.421 to 5.512 GB, including the changed saved-copy representation.

## Memory limits and validation

Bounded Arrow's 64 MiB value is an accounted scheduling target, not a hard RSS or total-native-memory cap. It includes retained dictionaries, worker readers, task descriptors, touched buffers and known scratch. Oversized tasks run alone. Final outputs, metadata, allocation rounding, thread stacks and opaque zstd workspace remain outside that guarantee. Preparation can already exceed the target. Writing has separate batch/dictionary scratch, and legacy conversion can allocate across an entire column; it has no 64 MiB cap.

The final clean source archive built and passed archive-contents checks. Its full R suite passed **23,202 assertions**, with no failures or skips and six test warnings reproduced on baseline. `R CMD check --no-manual` finished with zero errors, three warnings and two notes. A baseline archive check with tests omitted reproduced the same diagnostic categories: macOS link targets, vendored files and Rust's abort symbol. These packaging diagnostics remain unresolved.

Core validation passed 314 Rust tests, Clippy with warnings denied, and a build without the private adapter feature. Bridge Clippy and Rust formatting passed. Cross-language checks passed 22 immutable TypeScript fixtures covering 32,085 decoded cells, ten deterministic native gates and the canonical fixture oracle. The benchmark driver passed three tests, and all native-test manifest file hashes match. The strict isolated native-test runner was not run.

Focused final-summary validation also passed 1,433 assertions, including 743 owned-column assertions. Earlier development R checks are recorded separately in the [validation evidence](reader-parity-results/validation.json); the final package check binds the clean archive to its source commit and package tree.

- Both final 209-case qualification passes matched baseline values, metadata, dimensions and warnings: combined DTA/owned Arrow controls, and bounded Arrow plus bulk copying. All 384 final downstream observations matched results and passed captured-copy checks where applicable.
- The full corpus matched all **1,826 inputs**: 1,823 DTA files and three retained older Arrow files. Both builds rejected the same two malformed DTA files with identical errors. Successful reads matched signatures, dimensions and warnings. Controllers rechecked input, worker and installed-file hashes after every final run.

## Pre-merge corrections

Review found that row and group calculations could retain a numeric descriptor after a foreign R callback materialized the source and released its backing. These consumers now retain independent payload roots, and numeric readers snapshot compact descriptors. Regression tests cover native and R-backed columns, copied handles, and cleanup after callback errors and interrupts.

Parallel Arrow completion now distinguishes peer cancellation from a user interrupt, preserving the conversion error that stopped another worker. Its regression uses an unrepresentable timestamp alongside owned-column preparation. Benchmark controllers also resolve command-line paths before starting workers in separate directories; all three controllers have a subprocess regression in CI.

These corrections follow the measured build. The timing tables and archived validation above remain bound to `9ac470bb`; they are not measurements of the subsequent fixes.

Keep all experiments disabled by default. Before enabling one, close the full-read Stata gaps, remove material projection and downstream regressions, resolve timing uncertainty, and complete the independent timing and memory gates. The current screens identify useful improvements; they do not meet the accepted general parity target.
