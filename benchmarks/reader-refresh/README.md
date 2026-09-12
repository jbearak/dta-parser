# Reader-only documentation refresh

This refresh measures the current `dtatools::read_dta()` and
`dtatools::read_arrow()` on the inputs behind the published comparisons. It
reuses the archived haven and Stata observations. Neither comparator is run by `refresh.py`.
Writes and Arrow conversion costs retain their original dates and measurements.

Install the desired dtatools revision into an isolated library, then run these
commands from the repository root, one after the other:

```sh
python3 benchmarks/reader-refresh/refresh.py /tmp/reader-library target/reader-refresh-2026-09-12 --phase corpus
python3 benchmarks/reader-refresh/refresh.py /tmp/reader-library target/reader-refresh-2026-09-12-reads --phase reads
python3 benchmarks/reader-refresh/summarize.py target/reader-refresh-2026-09-12 target/reader-refresh-2026-09-12-reads benchmarks/reader-refresh/results-2026-09-12
```

The scripts require the original private corpus inventory and comparator
records under `target/r-corpus-performance/`, the retained synthetic and Arrow
files, and the saved projection fixtures under `target/`. They do not generate
replacement inputs or substitute timings from different files. `--cache` can
select another location for the unchanged corpus files.

The corpus phase checks every input's size and modification time against the
original inventory before and after reading. It uses the existing corpus R
worker, with one current dtatools read per fresh process. The reader alone is
timed, and the result remains live through process exit. `wait4()` records the
child's maximum RSS in bytes on macOS, or converts KiB to bytes on Linux. This
is the same whole-process RSS metric as the archived time-wrapper records.
The corpus phase can resume when its source, installation and archive binding
still matches.

The reads phase reuses the Arrow benchmark worker and its iteration counts:
one warmup followed by 11 timed reads for each synthetic file and five for
India, with garbage collection between reads. Arrow runs with verification
both enabled and disabled. Each DTA/Arrow pair must have matching dimensions,
names and data signatures before timing, after excluding value-label names,
declared string widths and variable notes absent from the retained August Arrow
files. The signatures still cover values, numeric storage types, labels,
formats, remaining notes and characteristics. Separate fresh-process reads refresh
the India and NSFG spot checks and measure India's Arrow peak RSS.

Projection uses the existing worker, with 11 timed `any_of()` and `all_of()`
reads per fixture after warmups. Saved Stata projection medians and ranges are
copied into the report. The synthetic Arrow files use Stata-first-save inputs;
the older synthetic haven read matrix used different rows, so its comparator
times are not attached to these files.

Run the phases without concurrent benchmarks or compilation. Timings reflect
the warm filesystem state of this machine and include the current readers'
default dibble output. Peak RSS includes the language runtime and loaded
result, including native allocations. It excludes the controller process.

Private outputs contain input paths, per-file corpus results and child logs.
The public summary contains corpus aggregates, named representative cases,
synthetic/projection observations and provenance hashes. The summarizer checks
that all 1,812 previously common-readable files still load with the same
dimensions before calculating comparisons, so reused comparator totals retain
the same file population.

The subsequent [India ten-run follow-up](results-2026-09-12/india-10x.md) uses
`repeat-india.py` to rerun all four tools, including haven and native Stata,
in rotated order. It supersedes only the initial single-read India comparison.

For a package built in a separate checkout, pass `--source-root /path/to/checkout`
to either driver. The source checkout must have no uncommitted package changes;
its commit and package tree are recorded alongside the installed library hashes.
To repeat only the two dtatools readers after a code change, use:

```sh
python3 benchmarks/reader-refresh/repeat-india.py /tmp/reader-library target/india-dtatools --dtatools-only --source-root /path/to/checkout --dta "$INDIA_DTA" --arrow "$INDIA_ARROW"
```

This mode retains the original input identities while accepting the new
installation. It alternates DTA/Arrow order across ten rounds and never invokes
haven or Stata. Their existing observations can be carried forward with their
original measurement provenance.

The [post-batching and automatic-thread report](results-2026-09-12-auto/README.md)
contains the latest dtatools measurements and full conformance rerun. To run
the matched projection control, using retained present/union name lists:

```sh
DTATOOLS_BENCH_LIB=/tmp/reader-library Rscript --vanilla benchmarks/reader-refresh/projection-threads.R "$INDIA_DTA" "$PRESENT_NAMES" "$UNION_NAMES" 10 target/projection-control
```

The default compares eight workers with automatic mode. An optional sixth
argument such as `1,2,4,8,12,16` selects explicit limits for a sweep. It warms
each configuration, verifies matching full data signatures outside timing,
alternates configuration order, and binds inputs, workers and installation
before and after. It writes observations and provenance beside the output
prefix. The report also retains the exact worker used before the optional
thread-list argument was added.

## Production-default rerun

The refreshed drivers in this checkout require `--data-root`, pointing to the
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

The main phases preserve the prior corpus, warm DTA/Arrow, projection and
India protocols. The corpus attempts all 1,823 inputs and requires the same
1,812 comparison files to succeed with matching dimensions. Its comparator
rows are copied unchanged. The fresh India timer still has no added pre-read
GC. The projection control keeps ten reads per configuration and both selection
methods, now combining automatic mode and all six explicit limits in one run.

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
present projections. It has no pre-read GC. This supplements the ten-read India
protocol without mixing process peaks from repeated warm reads into fresh RSS.
Private outputs retain paths and snapshots; publish summaries, hashes and
sanitized provenance only.
