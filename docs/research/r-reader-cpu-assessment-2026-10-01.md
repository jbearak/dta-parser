# R reader CPU assessment

Research date: 2026-10-01. Source inspected: `cbabff67950308f67595af1808af4f99cdb9bc59`.
This note combines official Stata documentation, retained measurements,
the October 1 release comparison and source inspection. It separates elapsed
read time from aggregate CPU cost and identifies work worth profiling before
changing the reader.

## Stata was not accidentally restricted to SE

The September 16 India comparison records Stata 18 with `c(MP)=1`,
`c(processors)=8` and `c(processors_lic)=8`. Its `c(edition)="BE"` does **not**
mean that the executable was Stata/BE. Stata documents that field as BE-or-better;
`c(SE)=1` likewise includes MP. `c(MP)` distinguishes MP, and newer documentation
also provides `c(edition_real)`. [Recorded configuration](../../benchmarks/reader-parity/results-2026-09-16-india/stata-configuration.json),
[official creturn reference](https://www.stata.com/manuals/pcreturn.pdf#page=2).

For MP, `set processors` controls the permitted core count. Its default is the
smaller of machine availability and the license limit. Non-MP editions report
one for `c(processors)`; setting MP to one is a useful same-executable control,
not a change of edition. An enabled count is not evidence that every command
uses that many cores. [System settings](https://www.stata.com/manuals/rset.pdf#page=13),
[processor fields](https://www.stata.com/manuals/pcreturn.pdf#page=3).

More specifically, Stata's MP performance report, revision 3.4.0 dated
25 September 2023, says file-I/O commands are not parallelized and explicitly
lists `use`. Thus native DTA loading is documented as serial for the Stata 18
era, even in MP. Generic MP estimation speedups do not apply to this command.
The current one-versus-eight control below also finds serial CPU consumption.
This is evidence for the measured executable, not a promise that all future
releases retain this implementation.
[MP report, Appendix E, page 367](https://www.stata.com/statamp/performance-report/report.pdf#page=367).

Local inventory found `/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp`;
both `stata` and `stata-mp` shell launchers resolve to MP. No SE executable was
found in `/Applications` or on the command search path. The current scaling run
records the live MP and processor fields. The older corpus worker uses
`timer` around `use`, without recording processor settings or CPU time; the
September 16 configuration is stronger evidence for that later comparison.
[Historical worker](../../benchmarks/r-corpus-performance/stata-worker.do),
[historical executable selection](../../benchmarks/r-corpus-performance/benchmark.sh).

## Earlier CPU measurements

The September 16 India comparison uses ten fresh processes per
tool, warm filesystem cache, 724,115 rows and 5,972 columns. The reader source
is `d6b0ae45`, with optimizations subsequently enabled by default, not today's
checkout. Read wall time excludes process startup. Process CPU includes
startup, loading, checks and shutdown. The R worker additionally records
read-call CPU. [Method and results](../../benchmarks/reader-parity/results-2026-09-16-india/README.md),
[raw observations](../../benchmarks/reader-parity/results-2026-09-16-india/observations.csv).

| Reader | Median read wall, seconds | Median read CPU, seconds | Median whole-process CPU, seconds |
| --- | ---: | ---: | ---: |
| `read_dta()` | 0.6135 | 4.9350 | 5.1551 |
| Stata `use` | 0.4725 | Not recorded | 0.5070 |

The R read-CPU median above is recomputed from the ten CSV rows. Startup and
other out-of-read work explain about 0.22 seconds of the R process CPU, not
the roughly tenfold process-CPU difference. For example, one matched-boundary
R observation uses 4.943 CPU-seconds during 0.611 elapsed seconds, about 8.1
CPU-seconds per elapsed second. That reflects concurrent CPU consumption, not
eightfold useful speedup or an energy measurement. Dividing the table's process
CPU by its read wall time would mix intervals. Stata's timer measures elapsed
time, not aggregate CPU. [Raw clocks](../../benchmarks/reader-parity/results-2026-09-16-india/observations.csv),
[Stata timer reference](https://www.stata.com/manuals/ptimer.pdf).

There is already a measured example of lower latency costing more CPU. The
September 12 India 100-column `any_of()` projection took 0.305 seconds wall and
0.306 CPU at one worker, versus 0.236 wall and 0.3455 CPU at two. Sixteen workers
took 0.2645 wall and 0.5185 CPU, losing on both measures to two. These are older
source/projection results, not a current full-read scaling curve.
[Controlled observations and settings](../../benchmarks/reader-refresh/results-2026-09-12-defaults/README.md#projection-and-thread-control),
[exact summary](../../benchmarks/reader-refresh/results-2026-09-12-defaults/projection-control-summary.csv).

Small-file conclusions are different. The default-enabled corpus rerun records
12.606 seconds of read CPU but 156.226 seconds of process CPU across 949 MICS
files, each in a fresh R process. Process reuse can address that deployment
cost; it cannot explain the India read-call CPU. Corpus Stata wall comparators
remain August measurements, not matched September reruns.
[Corpus boundaries and totals](../../benchmarks/reader-corpus/results-2026-09-16-base-r/README.md).

## Current CPU and thread scaling

The October 1 comparison uses the reviewed build plus the allocation-capacity
fix, the same India DTA, and a qualified Arrow conversion. Each of nine settings
has ten fresh-process reads with warm filesystem cache. No builds or tests ran
during measurement. Every selected R thread setting passed a separate full
canonical-signature check; timed processes only check dimensions afterward.
Pairwise setting precedence is balanced across rounds, though exact position
counts are not. [Harness and boundaries](../../benchmarks/reader-cpu-scaling/README.md),
[observations](../../benchmarks/reader-cpu-scaling/results-2026-10-01/observations.csv),
[summaries](../../benchmarks/reader-cpu-scaling/results-2026-10-01/summary.csv).

| Reader and requested setting | Median read wall, seconds | Median read CPU, seconds | Median CPU seconds per elapsed second |
| --- | ---: | ---: | ---: |
| Stata/MP, 1 processor | 0.469 | 0.468 | 1.00 |
| Stata/MP, 8 processors | 0.468 | 0.468 | 1.00 |
| DTA, 1 thread | 2.457 | 2.456 | 1.00 |
| DTA, 2 threads | 1.330 | 2.501 | 1.89 |
| DTA, 4 threads | 1.032 | 3.109 | 3.01 |
| DTA, 8 threads | 0.711 | 3.620 | 5.09 |
| DTA, automatic | 0.634 | 4.835 | 7.67 |
| Arrow, 1 thread | 1.313 | 1.312 | 1.00 |
| Arrow, automatic | 0.262 | 2.700 | 10.33 |

CPU and wall clocks cover the same read interval. A native Stata plugin reads
the calling process's `getrusage(RUSAGE_SELF)` and monotonic wall clock around
`use`; it does not time a shell helper. R uses `proc.time()`. Empty-interval
measurements are retained, not subtracted. The last column is the median of
per-observation ratios, not the ratio of rounded table entries. Automatic
means `threads = 0L`, not a measured worker count.
[Clock implementation](../../benchmarks/reader-cpu-scaling/cpuclock.c),
[empty intervals](../../benchmarks/reader-cpu-scaling/results-2026-10-01/empty-intervals.csv),
[R clock definition](https://stat.ethz.ch/R-manual/R-devel/library/base/html/proc.time.html),
[Apple resource-usage reference](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/getrusage.2.html).

Stata's one- and eight-processor observations consume about one CPU-second per
elapsed second, with nearly identical latency. There is no evidence of missed
multicore DTA loading in this comparison. Automatic DTA is about 35% slower
than Stata and consumes about 10.3 times its read CPU, using ratios of the
unrounded medians. Even the one-thread DTA call uses about 5.3 times Stata's
CPU, so scheduling overhead alone cannot explain the gap.

Within dtatools, automatic DTA is 3.9 times faster than one thread but uses
nearly twice the CPU. Eight threads use about 25% less CPU than automatic at
about 12% more elapsed time. Two threads nearly halve one-thread latency for
little additional CPU. Those are workload-specific tradeoffs, not a reason to
change the global default from this one file. Arrow's lower latency also costs
more CPU with automatic threading; its distinct file representation and
checksum work make it a separate workload. CPU seconds are resource usage,
not a measurement of energy.

Separate five-second stack samples of repeated one-thread and automatic DTA
reads put `try_push_byte_rows` first among reader functions in both captures.
Numeric-row decoding and `read` also appear; the automatic capture includes
many semaphore waits. This supports investigating the byte-column gather and
classification loop first. These are collapsed leaf-stack counts across all
threads, including idle waits, GC and loop overhead, not CPU percentages or a
prediction of an optimization's speedup. The serial capture's parser was
corrected and its retained raw sample reprocessed without rerunning the read.
[Serial function counts](../../benchmarks/reader-cpu-scaling/results-2026-10-01/profile-one-summary/leaf-functions.csv),
[automatic function counts](../../benchmarks/reader-cpu-scaling/results-2026-10-01/profile-auto/leaf-functions.csv).

## Startup work added since v0.10.0

The current package initializes numeric and mutation admission profiles during
`.onLoad()`, even for a read-only session. Version 0.10.0 only installed optional
hooks and registered methods for an already-loaded dplyr. Ten balanced
load-only pairs measured namespace loading at 0.083 seconds wall and CPU in
v0.10.0, versus 0.195 seconds in the reviewed build. Median whole-process peak
RSS rose from 96.7 to 122.5 MB. This isolates an added startup cost but does
not attribute all of it to any one initializer.
[Load-only observations and method](../../benchmarks/io-merge-review/results-2026-10-01/README.md),
[Current initialization](../../r-package/dtatools/R/zzz.R#L179),
[v0.10.0 initialization](https://github.com/jbearak/dta-parser/blob/v0.10.0/r-package/dtatools/R/zzz.R).

On the supported R 4.6.1 revision 90187, rlang 1.3.0 and vctrs 0.7.3 build,
with matching recorded artifacts and successful preceding profile checks,
initialization scans the same six external files five times: the base, rlang
and vctrs R databases, and the R, rlang and vctrs native libraries. Public,
generation, grouped-generation and plain-column setup each call
`.probe_installed_public_profile()`; bracket setup repeats its artifact checks
separately. Each successful call also creates fresh lazy-load environments and
fetches canonical closures. Generation and grouped-generation discard the
shared function's returned 58-closure list before loading their own extra roots.
Unsupported builds or failed checks can exit earlier, so five full passes is
not a universal startup count.
[Shared profile](../../r-package/dtatools/R/probe-public-source-profile.R#L25),
[generation initializers](../../r-package/dtatools/R/probe-gen-extra-profile.R#L25),
[plain-column initializer](../../r-package/dtatools/R/probe-plain-public-profile.R#L6),
[bracket profile](../../r-package/dtatools/R/probe-bracket-public-source-profile.R#L35).

The fingerprint routine reads every byte and has no cache. Closure qualification
also walks attributes, formals, source and bytecode. This is repeated validation
and deserialization, not runtime recompilation of all the profiles.
[Fingerprint loop](../../r-package/dtatools/src/probe-profile-file-fingerprint.c#L9),
[closure comparison](../../r-package/dtatools/src/probe-public48-code.c#L155),
[build-time compilation](../../r-package/dtatools/R/z-metadata-profile.R#L1).

This does **not** eagerly load dplyr. Registration and both dplyr profile
initializers return when its namespace is absent. If it is already loaded,
grouped and ungrouped setup perform additional artifact and closure checks.
[Registration guard](../../r-package/dtatools/R/dplyr-registration.R#L61),
[grouped guard](../../r-package/dtatools/R/zz-grouped-dplyr-profile.R#L9),
[ungrouped guard](../../r-package/dtatools/R/zz-ungrouped-mutate-profile.R#L9).

Assess sharing one validated canonical profile snapshot within initialization
before considering deferred mutation-only setup. Either change must preserve
failure, tracing, dispatch and fallback contracts; deferral must not treat a
later modified live closure as canonical. Test those contracts and measure
load-only CPU, wall time and RSS before claiming a gain. Neither proposal
reduces the reader's measured in-call decoding CPU by itself.

## Current implementation and priorities

The current reader already has compact numeric backing, direct reader-to-dibble
construction, prepared selected reads, adaptive workers, compact numeric batch
kernels and a four-slot observation ring. Each slot targets 4 MiB under a
16 MiB staging budget. One coordinator reads full-width observation blocks;
persistent workers own disjoint columns. These are existing controls, not new
optimization proposals. [Executor defaults and ring](../../r-package/dtatools/src/dta-tools/src/file.rs#L1686),
[worker policy](../../r-package/dtatools/src/dta-tools/src/file.rs#L774),
[R read completion](../../r-package/dtatools/src/rust/src/lib.rs#L3753),
[reader container](../../r-package/dtatools/R/dibble.R#L225).

The next priorities are hypotheses until measured on the current build:

1. **Test CPU-aware worker selection across workloads.** The current matrix
   establishes a CPU/wall tradeoff, not a universally best worker count. The
   policy estimates useful work; it does not optimize aggregate CPU or promise
   the fastest count. Test whether a resource-saving policy can retain most
   latency gains across file sizes and schemas. Report both measures instead
   of describing either as an unconditional speedup.
   [Policy and workload estimates](../../r-package/dtatools/src/dta-tools/src/file.rs#L700).

2. **Attribute wide-file CPU to gathering, classification, allocation and
   scheduling.** Compact batch loops still gather one cell at a row-width stride
   and classify missingness for every value. India's 5,518 byte columns contain
   almost four billion values. Reducing this repeated work or memory traffic is
   a more specific hypothesis than adding workers. Measure phase CPU as well as
   wall before choosing a kernel change. Borrowed microtiles and numeric row
   tasks already have local prototypes; inspect them before repeating that
   experiment. Contiguous weighted column groups previously failed to improve
   the byte-batch screen. Neither tiling nor SIMD has a newly established gain
   here. [Current byte loop](../../r-package/dtatools/src/rust/src/lib.rs#L3236),
   [batching measurements and negative grouping result](../../benchmarks/dta-reader-performance/README.md#alternatives-measured),
   [prior prototype inventory](parser-exploration-local-evidence-2026-09-15.md#work-already-explored).

3. **Treat projections separately.** The observation executor still reads
   complete rows while decoding selected columns. Reducing selected decode work
   cannot eliminate those source bytes. Test clustered and scattered selections,
   worker counts and ring geometry independently of full imports. Prepared
   selection already retains one open file and reuses its plan; do not count
   implementing that again as an opportunity.
   [Block length and column assignment](../../r-package/dtatools/src/dta-tools/src/file.rs#L2759),
   [coordinator reads](../../r-package/dtatools/src/dta-tools/src/file.rs#L1880),
   [prepared source](../../r-package/dtatools/src/rust/src/lib.rs#L3949).

4. **Add an eager-double batch experiment only for suitable inputs.** The R
   bulk hook accepts compact int/long/float, with byte handled separately. Eager
   doubles decline it and retain the scalar fallback with per-value sink checks.
   A bulk eager-double kernel could reduce dispatch/checking CPU on double-heavy
   inputs, preserving temporal conversion and missing tags. India has only two
   double columns, so this cannot plausibly explain most of its gap.
   [Bulk admission](../../r-package/dtatools/src/rust/src/lib.rs#L3074),
   [scalar eager writes](../../r-package/dtatools/src/rust/src/lib.rs#L2953),
   [India schema](../../benchmarks/dta-reader-performance/INVESTIGATION.md).

5. **Profile metadata and strings on their own regimes.** Output allocation
   and R metadata publication remain serial; strings build column dictionaries.
   These merit separate tiny/wide and high-distinct-string measurements, not
   extrapolation from India's byte-heavy schema. Local-source namespace loading
   and general reader-container conversion have already been optimized. Earlier
   deferred row-backed numerics returned sooner but lost every full-traversal
   comparison against direct eager construction; moving work after return is
   not an established CPU saving.
   [Allocation and finalization](../../r-package/dtatools/src/rust/src/lib.rs#L2738),
   [startup result](../../benchmarks/reader-startup/results-2026-09-13/README.md),
   [deferred-reader evidence](read-dta-construction-and-deferred-decoding.md#recommendation).

Do not remove missing-value, encoding, malformed-input or metadata validation
to improve the timing. R's column conversion is visible in the source, but
Stata's proprietary in-memory implementation was not inspected; attributing
its advantage to a particular memcpy or memory layout would be speculation.
The required result remains semantic read parity and owned output, as defined
in [CONTEXT](../../CONTEXT.md) and the compact-storage
[ADR](../adr/0005-construct-compact-stata-numerics.md).

## Next experiments

The full India scaling control is complete. Extend it to a double-heavy
synthetic input and clustered/scattered India projections before changing a
default. Keep source data unchanged and qualify values, missing tags and
metadata outside timing. Preserve matched CPU/wall intervals and separate
whole-process deployment measurements. The retained input hashes identify
private fixtures without publishing their paths or values.

For kernel experiments, measure read plus first full consumption as well as
the public read call, retaining owned output and verification contracts.
Collect phase profiles in separate runs so instrumentation does not contaminate
clean timings. Explicitly distinguish first-reader initialization, repeated
reads, warm filesystem cache and any later cold-cache control. Keep every
observation and run without competing builds or tests.

The measured serial Stata reader and the R scaling curve justify investigating
CPU efficiency. They do not establish a particular unimplemented optimization
or show that additional Stata processors were omitted from earlier comparisons.
