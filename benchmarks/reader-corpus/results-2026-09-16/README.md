# Full-corpus reader results, September 16, 2026

The [base-R worker rerun](../results-2026-09-16-base-r/README.md) supersedes
this run for current performance summaries. This earlier worker loaded
`jsonlite` before timing, which changed garbage-collection costs during some
reads. The original measurements and provenance remain below.

Both default-enabled readers were run across the original DHS, MICS and NSFG
inventory. All 1,821 readable DTA files produced Arrow copies with matching
full value-and-metadata signatures. The two known malformed DTA inputs failed
again and could not produce Arrow files. The run completed 3,644 read attempts.

## Comparable corpus totals

The table uses the same 1,812-file set as the earlier reports. Times are sums
of one fresh-process read per file, not medians of repeated corpus runs. The
nine other readable files remain outside every comparator total.

| Corpus | Files | DTA input size | `read_dta()` | `read_arrow()` | haven | Stata `use` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| DHS | 641 | 46.903 GB | 39.708 s | 28.272 s | 2727.051 s | 68.806 s |
| MICS | 949 | 3.690 GB | 7.874 s | 6.196 s | 216.732 s | 1.155 s |
| NSFG | 222 | 5.772 GB | 8.883 s | 6.671 s | 234.588 s | 0.885 s |

The dtatools measurements are from September 16. Haven and Stata measurements
are retained unchanged from [August 24](../../r-corpus-performance/results-2026-08-24.md);
neither comparator was rerun. These comparisons span measurement dates. Both
dtatools readers were faster than the retained haven time on all 1,812 files.

Across all 1,821 readable inputs, including those outside the comparison set,
`read_dta()` totaled 56.617 seconds and `read_arrow()` totaled 41.261 seconds.

## CPU and peak memory

Read CPU covers the read call. Process CPU and peak RSS include the entire
fresh process, including startup, package loading, result checks and shutdown.
CPU columns sum over the comparable corpus; RSS is the largest individual
process peak, not a sum or a median. Memory uses decimal GB.

| Corpus | Reader | Read CPU | Process CPU | Maximum peak RSS |
| --- | --- | ---: | ---: | ---: |
| DHS | `read_dta()` | 77.103 s | 179.361 s | 5.236 GB |
| DHS | `read_arrow()` | 68.600 s | 171.406 s | 5.451 GB |
| MICS | `read_dta()` | 14.076 s | 164.218 s | 0.241 GB |
| MICS | `read_arrow()` | 12.426 s | 162.203 s | 0.235 GB |
| NSFG | `read_dta()` | 12.719 s | 49.143 s | 0.556 GB |
| NSFG | `read_arrow()` | 13.864 s | 50.326 s | 0.952 GB |

Arrow took less total read time in each corpus. That did not always reduce
CPU or peak memory: for NSFG, Arrow used more read CPU and had a higher
maximum process peak than DTA.

The new DTA totals are not uniformly lower than the
[September 13 totals](../../reader-startup/results-2026-09-13/README.md).
These are separate dated runs, and the new run explicitly warms each DTA/Arrow
pair. They do not isolate the effect of the reader optimizations.

## Method and source

- Source: [`137b503a`](https://github.com/jbearak/dta-parser/commit/137b503a6200e4cb4be9c224089376736bcf697e),
  the reviewed default-enabled reader commit merged in [PR #231](https://github.com/jbearak/dta-parser/pull/231).
  Its package tree matches merge commit `3347e95b`. No experimental reader overrides were enabled.
- Host: Apple M4 Max, 16 logical CPUs, 128 GiB RAM, macOS 26.6.2, R 4.6.1.
  The host was shared, not isolated. This session ran no builds, tests or other
  benchmarks during timing.
- Every Arrow file was created and qualified before the first timed read.
  Conversion and signature checks are excluded from the reported read times.
- Each read starts a fresh R process. Package loading is outside the read-call
  clock; first-reader initialization remains inside it. There is no in-process
  warmup or added pre-read garbage collection.
- Both input files are hashed immediately before each pair to warm their bytes
  in the filesystem cache. Format order alternates across files. These are
  warm-cache measurements, not cold-storage latency measurements.
- Both readers use automatic thread selection and their default dibble output.
  Arrow checksum verification is enabled. Results stay live until process exit.
- Every timed successful read checks dimensions against its qualified input.
  All common-file results must match the retained comparator dimensions.
- The run checked source, installed package, workers, retained evidence, inventory
  size/mtime and input hashes before issuing its completion marker.

## Evidence and reproduction

- [Aggregate measurements](corpus-summary.csv).
- [Sanitized provenance](provenance.json), including source, installation, worker
  and private-evidence hashes.
- [Controller and protocol](../README.md). The installation command and build
  record bind the measured package to its clean source checkout.

The Arrow copies, paths, signatures, individual observations and child logs
remain private. The published CSV contains only corpus aggregates.
