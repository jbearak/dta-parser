# Reader-only documentation refresh

This refresh measures the current `dtatools::read_dta()` and
`dtatools::read_arrow()` on the inputs behind the published comparisons. It
reuses the archived haven and Stata observations. Neither comparator is run.
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
