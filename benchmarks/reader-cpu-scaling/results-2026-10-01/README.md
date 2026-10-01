# India reader CPU and thread scaling

Completed 2026-10-01 on macOS 26.7, arm64, with 16 logical CPUs reported to the
controller. R was 4.6.1; Stata was 18/MP with an eight-processor license. The
candidate is `cbabff67950308f67595af1808af4f99cdb9bc59` plus the grouped-mutate
allocation-capacity correction, not an unchanged release build. Its complete
production-source and installed-package inventories are in
[provenance.json](provenance.json). The installed DLL SHA-256 is
`ceecbf65aea0b898d8a99a729154508df08f7d344248caa1d102332f42a9ea06`.

The workload has 724,115 rows and 5,972 columns. The DTA is 5,196,403,097 bytes;
the equivalent Arrow file is 5,559,834,970 bytes. Complete input hashes identify
them without publishing private paths. Every R thread setting independently
matched canonical signature `724115:5972:e404e6f1cf51f55a` before measurement.
[Thread qualification](thread-qualification.csv),
[runtime settings](runtimes.json), [completion record](completion.json).

## Results

Each row summarizes ten fresh-process reads with warm filesystem cache.
Elapsed and CPU time cover the same read interval. CPU/wall is the median of
the ten per-observation ratios, not a ratio of two medians. Automatic means
requested `threads = 0L`; the actual worker count was not measured.

| Reader setting | Read wall, s | Read CPU, s | CPU/wall | Process CPU, s | Peak RSS, decimal GB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Stata/MP, 1 processor | 0.468593 | 0.468445 | 1.000 | 0.500404 | 5.257 |
| Stata/MP, 8 processors | 0.467940 | 0.467735 | 1.000 | 0.500572 | 5.257 |
| `read_dta()`, 1 thread | 2.456500 | 2.456000 | 1.000 | 2.764211 | 5.237 |
| `read_dta()`, 2 threads | 1.330000 | 2.501000 | 1.885 | 2.808240 | 5.245 |
| `read_dta()`, 4 threads | 1.031500 | 3.109000 | 3.012 | 3.414714 | 5.244 |
| `read_dta()`, 8 threads | 0.711000 | 3.620000 | 5.090 | 3.930726 | 5.247 |
| `read_dta()`, automatic | 0.634000 | 4.834500 | 7.667 | 5.143285 | 5.249 |
| `read_arrow()`, 1 thread | 1.312500 | 1.311500 | 1.000 | 1.633804 | 5.440 |
| `read_arrow()`, automatic | 0.262000 | 2.699500 | 10.328 | 3.042472 | 5.441 |

All entries are medians. Full observations, ranges and exact precision are in
[observations.csv](observations.csv) and [summary.csv](summary.csv).

Stata's one- and eight-processor settings produced nearly identical read
latency and CPU consumption, with about one CPU-second per elapsed second.
The previously reported high R CPU is also present over the read interval;
it is not explained by process startup. Automatic DTA reading consumed about
10.3 times Stata's read CPU while taking about 1.35 times its elapsed time in
this workload.

R's tradeoff is visible across explicit limits. Two DTA threads nearly halved
elapsed time versus one with little additional aggregate CPU. Eight threads
used about 25% less read CPU than automatic, at about 12% more elapsed time.
These are ratios of the reported medians, not confidence bounds or universal
thread recommendations. Automatic Arrow reading was faster than Stata here,
but still consumed more aggregate CPU. The Arrow comparison excludes the
cost of creating the Arrow file and retains checksum verification during read.

## Controls and qualification

- Ninety clean reads completed, ten per setting. Five rotated orders were
  paired with their reversals, giving each pair of settings five observations
  in each precedence order. Nine settings over ten rounds do not give exact
  position balance; positions are retained in the raw observations.
- All requested R settings were qualified in separate fresh processes using
  complete `datasig()` traversals. Their CPU and memory are not in the timed
  children. Each timed result also checked its dimensions after the clock
  stopped. The candidate installation, source and input hashes match the
  independently retained I/O qualification records bound in provenance.
- Stata's native plugin used `CLOCK_MONOTONIC` and `getrusage(RUSAGE_SELF)`
  directly in the Stata process. R used `proc.time()`. Whole-process CPU and
  peak RSS came from `wait4`, separately from read clocks. No shell-launched
  CPU sampler or process-CPU/read-wall ratio was used.
- One hundred empty intervals per Stata processor setting and one hundred
  R empty intervals were retained in [empty-intervals.csv](empty-intervals.csv).
  Stata's maximum empty wall interval was 3 microseconds and maximum empty CPU
  was 4 microseconds. All R empty intervals reported zero at its timer
  resolution; this means below resolution, not zero overhead. Nothing was
  subtracted from the observations.
- The native sampler compiled successfully. Seven harness tests and an
  all-nine-setting smoke run on the qualified 100 MB fixture passed before
  the India run. The smoke measurements remain private and are excluded here.
  An additional parser regression later brought the harness tests to eight,
  all passing.
- No other task builds, tests or benchmarks ran during the exclusive window.
  The host was not isolated from ordinary operating-system activity. Every
  observation is retained; there was no outlier removal. Initial and final
  source, installed-package, input and clean-harness fingerprints matched.

The [harness instructions](../README.md) describe how to repeat the run.
These results apply to this wide, byte-heavy input and this host. They do not
establish a best default for other files, cold cache, projections, process
reuse, simultaneous jobs, or first full downstream consumption. They measure
CPU time, not energy.

## Separate stack sampling

After all clean timings, the same candidate performed repeated India DTA reads
with one requested thread and with automatic threads. Each diagnostic ran for
at least twelve seconds; macOS `sample` observed five seconds at a one-ms
sampling interval. Both successful captures retained matching input and full
installed-package fingerprints. Only sanitized function names and collapsed
leaf-stack counts are published.

| Reader function identified in native symbols | One thread: leaf samples | Automatic: leaf samples |
| --- | ---: | ---: |
| `try_push_byte_rows` | 2,365 | 21,841 |
| `try_push_numeric_rows` | 224 | 2,293 |
| `decode_worker_block_with_batches` | 237 | 1,442 |
| `read` | 320 | 1,520 |
| `RunGenCollect` | 71 | 392 |

The byte-batch path is the leading reader function in both captures. That
supports investigating its row-strided gathering and per-value classification
work. It does not by itself establish a profitable replacement or a percentage
of CPU that an optimization could save. The automatic capture also contains
many semaphore waits. Sampling observes all threads, including idle ones, and
the diagnostic includes repeated-call allocation and collection. Counts across
settings are not normalized by work completed and must not be treated as CPU
time percentages. [Serial function counts](profile-one-summary/leaf-functions.csv),
[automatic function counts](profile-auto/leaf-functions.csv).

The first sandboxed sample could not inspect its R child and is explicitly
unavailable in [profile-one/provenance.json](profile-one/provenance.json).
It contributes no profile evidence. An approved, same-user execution outside
the sandbox succeeded without `sudo`. The initial parser expected leading
counts, while this macOS report puts counts after symbols. A failing regression
captured that format, the parser was corrected, and the saved successful serial
report was reprocessed without repeating its workload.

The original empty parser result is retained in
[profile-one-permitted](profile-one-permitted/provenance.json); use
[profile-one-summary](profile-one-summary/provenance.json) for the corrected
serial aggregate. The latter binds the capture, raw-sample hash, postprocessor
and corrected parser. The automatic aggregate was generated with the corrected
parser. Raw stacks, commands and logs remain private.

Only the optional profile parser and its tests changed after the clean run.
Their original versions are archived under [timing-harness](timing-harness/)
and match the clean provenance's hashes. The read worker, Stata clock and clean
timing controller were unchanged. The added postprocessor did not execute in
any clean timed child.

The profiler and tests used for the successful captures are retained at
[revision ebc7204b](https://github.com/jbearak/dta-parser/tree/ebc7204bb46c8459c047abca213e48e72a9abf35/benchmarks/reader-cpu-scaling).
Later sampler-timeout handling in the current runner does not change these
measurements or their recorded hashes.
