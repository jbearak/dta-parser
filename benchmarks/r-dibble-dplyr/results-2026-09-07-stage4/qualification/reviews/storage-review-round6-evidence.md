# Stage 4 storage review, round 6 evidence archive

Reviewed at 2026-09-07T04:00:01.747068+00:00.

- Worktree: `/private/tmp/dta-direct-stage4`
- Current HEAD: `80e636e5636d4b3d742303aaba7278d9dd6e17df`
- Logical Stage 4 base and measured baseline: `ec10a6ac34602f3bd691e8043019c1b479babda4`
- Measured initial candidate: `7d56080f3e97bc4d73a848e363d729767b9629c0`
- Candidate package tree: `82b95507e3ea9fe8b8658d7c2098b1f95f5c3756`
- Atomic runner revision: `b259ad5a521dbb867a0b8563e3a0c2262e298671`
- Prior-double runner revision: `ec10a6ac34602f3bd691e8043019c1b479babda4`
- Scoped evidence/report/README diff SHA-256: `978484bf05c7fb4293efb926a668f8ae745980f87a3ec9a5d3d7d9a0326044bf`
- Saved scoped diff: `/private/tmp/dta-direct-stage4-validation/storage-review-round6-evidence.diff`
- Complete reviewed artifact identities: `/private/tmp/dta-direct-stage4-validation/storage-review-round6-evidence-identities.json`
- Identity document SHA-256: `cfb414f153b7996b38160ae1a091c06a507c45796ac4158b0adc0ee5835cc5b4`

The scoped diff includes changes to the report, README and complete initial-evidence directory against current HEAD, including untracked files. The identity document records every reviewed artifact's exact relative path, size and SHA-256. The evidence index independently identifies all 157 copied artifacts, and this review verified each indexed copy against its original path. It did not rewrite any root-owned file.

## Disposition

No actionable discrepancy found in the report, archived evidence, comparison derivation or README clarification. The report accurately rejects performance acceptance for the initial candidate. Its 43 atomic read flags remain investigation findings, and the report does not claim they are all repeatable or that Stage 4 is accepted. Production read-path diagnosis and later source revisions are outside this evidence-only review.

## Evidence integrity and source identities

All 157 indexed artifacts, totaling 618,316 bytes, match their recorded size and SHA-256 and are byte-identical to their original files. The only directory file absent from the copied-artifact list is the evidence index itself, as expected. Every manifest output, CSV row count and completed memory-log digest checked matches the copied artifact. Atomic baseline/candidate manifests identify the same six runner files, comprising five R dependencies plus the Python driver. Each digest matches the committed git blob at the recorded runner revision. Prior-double manifests likewise match their four committed R files and each other.

Both comparison derivation records match the archived input-manifest digests, derivation-script digests and output digests. Source review confirms that the derivation scripts pair complete unique operation keys, require baseline/candidate direction and matching runner bytes, preserve the seven-iteration requirement, and flag only rows exceeding both 1 ms absolute and 10% relative regression. Static checks of the stored comparison tables against their raw CSVs found no mismatched paired metrics, deltas, ratios or flags. This review did not execute either comparison script or collect new benchmark observations.

The source identities in sessions, manifests and report consistently distinguish measured package revisions from atomic and prior-double runner revisions. The candidate package tree resolves to the recorded git tree. R session records confirm R 4.6.1, macOS 26.6.2, dplyr 1.2.1 and vctrs 0.7.3. Installation/source/DLL validation is supported by the recorded runner checks and qualification records; no installation was rebuilt or loaded by this reviewer.

## Failed baseline memory attempt and retry

The original baseline memory log includes the R retained/release metrics, then the exact `sysctl kern.clockrate: Operation not permitted` error from `/usr/bin/time`, with no RSS result. It remains separately archived. The copy proof's original-manifest digest and every copied successful operation artifact match the preserved original directory. Successful operation files in the qualified retry match those same bytes. The retry manifest preserves all original fields apart from its updated manifest timestamp and the appended memory evidence/scope. All 30 retry memory cases record exit zero and matching log hashes. The report's statement that operation timings were preserved without rerun or relabeling is consistent with these files.

## Reported results and measurement scope

The atomic archive contains 206 operation/read rows, 126 selectors after reads and 18 public write profiles. The comparison has exactly 43 flagged rows, all in the read family. The prior-double comparison has 46 paired operation/read rows and zero flags. Its archive also preserves 30 after-read selector rows, six write profiles, four expression-capture profiles and six memory cases.

The five one-million-row rename examples match their table values and rounding. All 40 direct selector/pipeline rows are present, with maximum cumulative R allocation 449,360 bytes and 422,240 bytes for each one-million-row five-verb pipeline. First shared string/logical writes show exactly 8 MB/4 MB target copies; private writes show zero target-copy bytes and 416 R bytes. Full replacements show zero target-copy and old-journal bytes. The report keeps smaller staged/capture work in the linked write CSV and does not sum overlapping counters.

The three named regression examples match the stored read rows. Candidate retained vector heap ranges from 81,368 to 92,576 bytes across 30 memory processes. Final residuals range from -56,488 to -46,640 bytes. Whole-process RSS ranges from 190,578,688 to 1,133,445,120 bytes, consistent with the report's rounded 0.191 to 1.133 GB. The report explicitly separates RSS, retained heap and cumulative allocation, and states that process RSS includes startup, fixtures, retained oracles and validation. Expression-capture examples match 16,000,312 versus 24,000,360 R bytes for nested string RHS and 1,000,048 bytes for the arithmetic predicate.

The README clarification matches the actual measured writer wrapper: expected DTA factor-warning collection/checking runs inside the measured call in both revisions; independent value/metadata oracles run outside. It accurately identifies bench's retained preflight result separately from writers' final timed files.

## Historical regression scope

The root regression manifest, driver source and driver log agree on 45 generation/names, 72 delayed-mask, 72 delayed-private-mask and 30 symbol/private-callback comparisons, totaling 219. The four scripts and baseline RDS files match the referenced historical input hashes and original files. All four candidate RDS outputs are byte-identical to their respective baselines. Child logs and the outer driver record the requested exact candidate library/source checks. The report and manifest explicitly exclude the historical 18-case custom native names observer with unavailable C source. They make no claim to have rerun that binary or to substitute these 219 comparisons for the separate native mutation gate.

No R processes, tests, builds, probes or benchmarks were run. Review work was limited to source/evidence reads, hashing and lightweight consistency checks of stored artifacts, followed by these durable review files.

## Selected exact file identities

- `benchmarks/r-dibble-dplyr/results-2026-09-07-stage4.md`: `d71485c83fa3930597aeb12b55276b6db9c50773ac8c6f79e46c49649c5416a5`
- `benchmarks/r-dibble-dplyr/README.md`: `94d93066b56e6abd3108ffb30dc264e04dd20ebfd888bab86aaaf4c4050aa8f1`
- `benchmarks/r-dibble-dplyr/results-2026-09-07-stage4/initial-evidence-index.json`: `d58ba06fc93efc8429ed5511e7461cae9764014c70bdb84ea4c10f325661e40c`
- `benchmarks/r-dibble-dplyr/results-2026-09-07-stage4/archive-initial-evidence.py`: `d4928584efa25af8217b805507cedca99c6c63a5a5950df1dc2a0014a638921a`
- `benchmarks/r-dibble-dplyr/results-2026-09-07-stage4/compare-atomic.py`: `4a9051ce97c5a84ff580f0ddda4cce2692c847695d0500ad8c239618e312b9bf`
- `benchmarks/r-dibble-dplyr/results-2026-09-07-stage4/compare-double.py`: `6da73e867e3d33cbb8469bc253058a4044ae8011220d6f539f43107f2d9867ad`
- `benchmarks/r-dibble-dplyr/results-2026-09-07-stage4/comparison-atomic-7d56080/derivation.json`: `390fda18b6a99e47bf26f4dc44ab969bc5188f735f0cd3c65922a27145c16ee1`
- `benchmarks/r-dibble-dplyr/results-2026-09-07-stage4/comparison-double-7d56080/derivation.json`: `73dd94af755100f6983c81a774e7895536fa4d5a206d39fac2ba80b569911ccf`
- `benchmarks/r-dibble-dplyr/results-2026-09-07-stage4/baseline-b259ad5-memory-retry-copy.json`: `074f97fc9f3e750f03af62e17833fbbbc46740477e141f91b56ff10cc5762ec5`
- `benchmarks/r-dibble-dplyr/results-2026-09-07-stage4/root-acceptance-7d56080/root-manifest.json`: `5b6387454272272892022cea201aebc05a75006b13d536b377a44dd0ebcc0a2d`
