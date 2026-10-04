# Preliminary candidate1 observations

These are six paired rounds of six cases and three representations, totaling 216 timed observations. They describe candidate1, before subsequent kernel changes. They do not establish final parity or final candidate performance.

| Case | Baseline compact ms | Candidate1 compact ms | Baseline/candidate1 | Candidate1/typed DOUBLE | Candidate1/bare DOUBLE |
| --- | ---: | ---: | ---: | ---: | ---: |
| FLOAT reverse division, observed | 0.320 | 0.308 | 1.020 | 0.846 | 1.074 |
| FLOAT reverse division, sparse missing | 0.339 | 0.352 | 1.006 | 1.037 | 1.218 |
| INT reverse division, observed | 0.477 | 0.413 | 1.146 | 1.057 | 1.164 |
| INT reverse division, sparse missing | 0.535 | 0.511 | 1.018 | 1.405 | 1.730 |
| INT/FLOAT addition, sparse missing | 0.540 | 0.403 | 1.321 | 1.096 | 1.373 |
| INT/FLOAT multiplication, sparse missing | 0.521 | 0.407 | 1.344 | 0.999 | 1.329 |

Times are medians of CPU per call. Ratios are medians of paired within-round ratios, so they need not equal the ratio of the two time medians. The individual typed-control ratios remain in `balanced-summary.json`; its `typed_drift` field is baseline/candidate1 for the typed control. Raw observations are in the twelve round CSVs. The package worker independently checked each representation's expected storage and value rules. Results can differ across representations when one narrows output or canonicalizes infinity to missing.

`build-bindings.json` extracts the three measured header hashes and DLL identities from the recorded builds. The candidate build reused the existing Rust archive. `candidate-test-only-update.json` records a later test expectation and manifest correction against the same DLL, with no runtime change. The final focused test receipt records 65,745 assertions in 71 blocks, with no failures, errors, warnings or skips. These tests qualify candidate1's runtime, not a subsequently modified candidate.

Private paths in commands and receipts are replaced by `<baseline-library>`, `<candidate1-library>` and `<evidence>`. `publication-source-map.json` records original and published hashes for each retained artifact. DLLs, installed libraries, full source trees, old evidence archives and full-suite reruns are not included. The portable controller at `../../run.py` uses explicit local library paths; it was written after this run and did not generate these historical observations.
