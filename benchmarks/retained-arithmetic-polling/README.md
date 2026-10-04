# Retained arithmetic interrupt checks

The [source-bound report](results-2026-10-03.md) records the whole-span polling experiment, complete controls, residual fragmentation cost and later integration checks.

From the repository root, run the current-source structural guard with an absent output directory:

```sh
python3 -O benchmarks/retained-arithmetic-polling/work-count.py --require-proved --output /tmp/retained-poll-check
```

The guard extracts the actual arithmetic headers from the immutable current commit. It checks complete values and missing counts, then independently derives the original span-request trace and polling positions from completed span endpoints, including the final tail. It covers 18 cases and rejects extra lookups, excessive or misplaced checks, missing cases and malformed records. R interrupts and span delivery are mocked; public ownership/reentry and real Rust lookup behavior are separate qualifications. No elapsed-time threshold is used.

The measured controller and original probe snapshots under the results directory are historical evidence. Their private paths are redacted; use their recorded source commits and build receipts when reproducing the experiment. Both measured commits are retained by the `codex/retained-whole-span-poll-evidence` branch. The current-source guard above remains directly executable.
