# Refresh the historical survey comparison

This driver reruns only dtatools on the recovered 1,812-file DHS/MICS/NSFG
comparison set. It retains all six published Haven and Stata aggregate rows,
including their August 24 dates, without running either comparator. The missing
historical `raw.tsv` is not reconstructed. Membership is fixed by the exact
recovered private manifest and the public [recovery evidence](recover-matched.md).
Its corpus counts and byte totals must match the retained comparison table.

Use a candidate library produced by `r-file-readers/build-snapshot.py`. Prepare
all Arrow copies and full-signature qualifications before starting measurements:

```sh
python3 benchmarks/reader-corpus/refresh-matched.py prepare \
  --candidate-build-work /absolute/candidate-build \
  --membership /absolute/recovered/membership-private.json \
  --recovery /absolute/repo/benchmarks/reader-corpus/results-2026-10-01-matched/recovery \
  --work /absolute/new-results
python3 benchmarks/reader-corpus/refresh-matched.py measure \
  --work /absolute/new-results
```

Run the same commands first with `--smoke` on `prepare` and a separate work
directory. Smoke selects the smallest matched file from each corpus: twelve
qualification reads and twelve timed reads. Its timings are not publishable
performance estimates. Focused tests run with
`python3 -m unittest discover -s benchmarks/reader-corpus -p test_refresh_matched.py`.

Preparation uses one fresh R process per file. It saves Arrow from an explicit
tibble to retain the source's declared string widths, then compares complete
DTA/Arrow signatures and dimensions within both tibble and dibble outputs.
Warnings fail qualification. Cross-container signatures may differ under
existing dibble string-storage normalization. Preparation discovers the shape
that every timed read must match. An optional `--arrow-manifest` maps matched
IDs to existing Arrow paths; reused files must pass the same qualification and
are never overwritten. Fresh files need roughly the corpus size in disk space.

A full measurement contains 7,248 fresh R children: one read per format and
container per file. The base-R worker keeps the historical corpus timer and
`tryCatch` boundary, adding explicit output selection. It loads no jsonlite,
adds no garbage collection or warmup, retains the returned result until exit,
and fails on warnings. Numeric ALTREP and adaptive threads remain at their
defaults; Arrow verification stays enabled. Rotated method orders followed by
their reverses balance each pair's precedence across the 1,812 files.

Both input files are hashed immediately before each group of four reads,
warming the filesystem cache. Read wall and read CPU cover the public reader
call. Whole-process CPU and maximum RSS also include startup, namespace loading,
shape checks, reporting and shutdown. These CPU and wall intervals differ.
Current file bytes, source snapshots, installed package, dependencies, runtime,
worker code, recovery evidence and retained comparator tables are bound before
and after preparation and measurement. The original inventory binds paths,
sizes and modification times; historical per-file content hashes and raw
comparator observations remain unavailable.

Pause other task-owned builds and tests for timing and monitor the shared host
separately. `refresh-matched-monitor.py --work RESULTS --log NEW_LOG` samples
competing processes at 30-second intervals, excluding this measurement's
process tree and omitting command arguments. Its 50% CPU threshold cannot prove
continuous host isolation; a separate finer-grained monitor is also suitable.

Qualification artifacts are sealed before `measure` can start. Timing cannot
restart or discard observations. Each successful read is appended immediately
to `observations.jsonl`; failed attempts retain private logs and stop the run.
`COMPLETE` requires all expected reads, unchanged bindings and sealed artifacts.

Publish only the public JSON/CSV records and a report, with the recovery and
source-patch evidence they reference. Keep `*-private.json`, `prepare-jobs`,
`qualification-private`, `timed-private` and Arrow inputs local. The copied
`historical-summary.csv` is byte-identical to the retained source table;
`historical-comparators.csv` preserves its six comparator rows, and the full
`comparison.csv` joins those dated rows with twelve fresh dtatools rows. Report
the dates and host differences: this is a refresh using historical comparators,
not a contemporary paired comparison with those tools.
