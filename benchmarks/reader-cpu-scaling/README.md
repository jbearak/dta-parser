# Reader CPU and thread scaling

Run this harness only while builds, tests and other benchmarks are paused. It
measures one full read in each fresh process, with warm filesystem cache and
first-reader initialization included. It is a diagnostic, not a release gate.

The default nine settings are Stata/MP at 1 and 8 processors, `read_dta()` at
1, 2, 4, 8 and automatic threads, and verified `read_arrow()` at 1 and automatic.
Automatic means requested `threads = 0L`, not an observed worker count. Each of
ten rounds has every setting. Rotations paired with their reversals give each
pair of settings five observations in each precedence order. Position counts
are not exactly balanced; every observation retains its position.

## Same-interval clocks

The Stata plugin records `CLOCK_MONOTONIC` and `getrusage(RUSAGE_SELF)` immediately
around `use`. R records `proc.time()` around the reader. Both measure user and
system CPU over the read interval. The controller records whole-process
`wait4` CPU and peak RSS separately. Do not divide process CPU by read wall.
No data conversion, reporting, validation or result-file write is inside the
read interval. Each child validates dimensions afterward.

Stata plugin parsing/call overhead is part of its measured interval. The
harness retains 100 empty intervals for each Stata processor setting and R's
sampler; it does not subtract them. Reads include the reader's own normal input
validation and Arrow checksum verification.

Before clean measurements, every selected R thread setting runs in a separate
qualification process. Its complete canonical `datasig()` must match the
already-qualified input signature. These traversals never run in timed
children, so neither their CPU nor their memory enters the timing observations.

## Prepare and run

Download the unmodified official [stplugin.c](https://www.stata.com/plugins/stplugin.c)
and [stplugin.h](https://www.stata.com/plugins/stplugin.h) into a private SDK
directory. `build-plugin.py` checks the inspected SPI 3.0 hashes. The build uses
Stata's [documented plugin interface](https://www.stata.com/plugins/), with a
native-architecture macOS bundle or Linux shared library.

```sh
python3 benchmarks/reader-cpu-scaling/build-plugin.py \
  --sdk "$SCALING_SDK" --output "$SCALING_PRIVATE/cpuclock.plugin"
python3 benchmarks/reader-cpu-scaling/test_harness.py
python3 benchmarks/reader-cpu-scaling/run.py \
  --library "$SCALING_LIBRARY" --dta "$SCALING_DTA" --arrow "$SCALING_ARROW" \
  --reference-provenance "$SCALING_BUILD_RECORD" --qualification "$SCALING_QUALIFICATION" \
  --case-id india \
  --plugin "$SCALING_PRIVATE/cpuclock.plugin" --rows 724115 --columns 5972 \
  --output "$SCALING_PUBLIC" --work "$SCALING_PRIVATE/jobs"
```

Use a qualified fixture and `--smoke` first, with fresh output/work directories.
The supplied provenance and qualification records use the October I/O review's
schema. Candidate installed inventory and production-source inventory must
match that build record, and both input hashes, dimensions and canonical DTA /
Arrow signatures must match the selected case. The option
`--settings stata-1 stata-8 dta-1 dta-auto` selects an initial diagnostic subset;
omit it for all nine settings. Never combine smoke rows with full measurements.

Input paths belong only in the private work directory. Published provenance
contains complete input hashes, dimensions, the installed package inventory,
tracked R/native source hashes, runtime executable hashes, plugin build details
and worker hashes. Initial and final bindings must match. Input hashing warms
the cache before timing. The separate canonical qualification records are
hash-bound to the run. Raw Stata do-files and
process logs can contain private paths and must not be published.

## Optional stack sampling

After all clean timings, `profile.py` runs repeated public India `read_dta()`
calls for at least 12 seconds and invokes macOS `/usr/bin/sample` for five
seconds. Run it separately with `--threads 1` and `--threads 0`, supplying the
same library, DTA, dimensions, public output and private work arguments, plus
`--timing-provenance` pointing to the completed, non-smoke clean run's
`provenance.json`. The input and full installed package must match that run. This
diagnostic is optional if sampling is unavailable or useful symbols are absent.

Only sanitized function names and collapsed leaf-stack counts are published.
Raw stacks remain private. Sampling includes all threads, including idle waits,
and repeated reads include collection and loop overhead. These counts are not
CPU-time percentages, attribution of elapsed time, or energy measurements.
