# Reader benchmark refresh

The [September 12 adaptive-default report](results-2026-09-12-defaults/README.md)
refreshes `dtatools::read_dta()` and `dtatools::read_arrow()` on the retained
benchmark inputs. Haven and Stata results keep their original measurement
provenance. These drivers never run either comparator or regenerate inputs.
Write and conversion benchmarks also retain their original dates.

Earlier results remain available in the [initial refresh](results-2026-09-12/README.md),
[ten-run four-tool India comparison](results-2026-09-12/india-10x.md), and
[available-CPU refresh](results-2026-09-12-auto/README.md).

## Running the refresh

The drivers require `--data-root`, pointing to the
original repository's `target` directory, and `--build-record`, pointing to the
JSON emitted by `install.py SOURCE LIBRARY RECORD`. The build record must match
the complete installed package. Its source commit may precede the benchmark
commit only when the package tree is identical. Run the phases sequentially
once conformance and installation have finished:

```sh
python3 benchmarks/reader-refresh/refresh.py "$LIBRARY" "$OUT/corpus" --phase corpus --data-root "$DATA_ROOT" --build-record "$BUILD_RECORD"
python3 benchmarks/reader-refresh/refresh.py "$LIBRARY" "$OUT/reads" --phase reads --data-root "$DATA_ROOT" --build-record "$BUILD_RECORD"
python3 benchmarks/reader-refresh/repeat-india.py "$LIBRARY" "$OUT/india-10x" --dtatools-only --dta "$INDIA_DTA" --arrow "$INDIA_ARROW" --data-root "$DATA_ROOT" --build-record "$BUILD_RECORD"
python3 benchmarks/reader-refresh/projection-control.py "$LIBRARY" "$OUT/projection-control" --data-root "$DATA_ROOT" --build-record "$BUILD_RECORD"
python3 benchmarks/reader-refresh/supplement.py "$LIBRARY" "$OUT/coverage" --phase coverage --data-root "$DATA_ROOT" --build-record "$BUILD_RECORD"
python3 benchmarks/reader-refresh/supplement.py "$LIBRARY" "$OUT/fresh" --phase fresh --data-root "$DATA_ROOT" --build-record "$BUILD_RECORD"
python3 benchmarks/reader-refresh/summarize.py "$OUT/corpus" "$OUT/reads" "$PUBLIC_OUT" --data-root "$DATA_ROOT"
```

Set `--source-root` when the installed package comes from another checkout.
All children discard `DTATOOLS_EXPERIMENT_*` and `DTA_READ_PERF_*` overrides.
No driver invokes haven or Stata. The India driver now requires
`--dtatools-only`; the historical four-tool driver is retained in Git history.
Read-call CPU clocks are user plus system time over the same interval as the
elapsed clock. The jobs also retain whole-process CPU time and peak RSS.
Startup, qualification, warmups and GC outside the read call belong only to
those process measurements. Retained comparator CPU values are unavailable.

The corpus, projection and fresh India protocols are unchanged. New warm-read
runs use six cohorts, covering all six orders of DTA, verified Arrow and
unverified Arrow for every input. Case order rotates across cohorts. Each reader
therefore occupies each position twice per case, and each pair runs in either
order equally often. Every worker still performs one warmup, then 11 measured
reads for a synthetic input or five for India, with full GC between reads.
The complete warm phase has 54 worker processes and 486 timed observations.
All three DTA/Arrow equality checks finish before any warm worker starts;
qualification I/O does not occur between timed warm cases. Those checks exclude
value-label names, declared string widths and notes absent from the retained
August Arrow files. Projection uses 11 `any_of()` and
11 `all_of()` reads after warmups. The corpus attempts all 1,823 inputs and requires the same
1,812 comparison files to succeed with matching dimensions. Its comparator
rows are copied unchanged. Input sizes and modification times must match the
original corpus inventory before and after the run. The fresh India timer still has no added pre-read
GC. The projection control keeps ten reads per configuration and both selection
methods, now combining automatic mode and all six explicit limits in one run.

Warm observations retain the cohort, case position, method position, scheduled
position and actual timed execution position. The latter comes from the attempt
history, including retries. Pooled summaries and separate per-cohort summaries
are both written. Dated reports retain their original fixed-order observations;
the new balanced cohort is separate evidence. To publish just that cohort
without rerunning an older corpus, use:

```sh
python3 benchmarks/reader-refresh/summarize.py "$OLD_CORPUS" "$OUT/reads" "$BALANCED_PUBLIC_OUT" --data-root "$DATA_ROOT" --warm-only
```

The corpus argument is ignored in this mode. A reads-phase retry repeats all
equality checks and the complete balanced schedule. Each child attempt keeps
its own immutable log, and `jobs.jsonl` retains successful and failed attempts.
Publication requires the latest attempt of every required key to succeed;
an earlier failed qualification does not invalidate a later successful retry.
Malformed histories, incomplete cohorts, changed order records, changed logs
and final failed attempts are rejected. Run the focused driver tests without
loading readers using `python3 benchmarks/reader-refresh/test_drivers.py`.

Supplemental coverage reuses all 15 direct-dibble fixtures and compares current
snapshots with the retained candidate snapshots before timing. It preserves
three processes per input, two warmups, calibration to 150 ms, seven measured
batches, and three separate fresh-process memory observations. The default
fixture directory is `/private/tmp/direct-dibble-readers/run-01/fixtures`;
`--dibble-fixtures` can relocate the unchanged fixtures and adjacent snapshots.
Hashes must match the published fixture record.

The supplemental synthetic full/eight-column matrix uses seven warm reads on
the retained Stata-first-save inputs. It does not reuse the August 24 synthetic
comparator times, which used different row counts and bytes. That historical
matrix remains dated. The current main warm DTA/Arrow matrix covers those
same retained inputs with its original 11-read protocol.

Four small checked DTA fixtures cover modern all-types, wide, strL and legacy
full reads and two-column windows. Their supplementary timings average 100
calls after GC. Separate metadata-only rows measure `n_max = 0` on those four
fixtures and India. They are coverage measurements, not replacements for data
read timings or the original R microbenchmark's comparator rows.

The fresh supplement records three individual no-warmup reads for synthetic
DTA and verified/unverified Arrow, unverified India Arrow, and the four known-
present projections. It has no pre-read GC, but uses a separate configuration wrapper. Compare
verification settings within that wrapper; do not compare its unverified India
latency directly with the verified ten-read worker. This supplements the ten-read India
protocol without mixing process peaks from repeated warm reads into fresh RSS.
Private outputs retain paths and snapshots; publish summaries, hashes and
sanitized provenance only.
