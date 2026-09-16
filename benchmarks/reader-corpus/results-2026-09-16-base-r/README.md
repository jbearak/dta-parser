# Full-corpus reader rerun, September 16, 2026

This run measures `read_dta()` and verified `read_arrow()` with default
settings and a base-R timing worker. It replaces the
[earlier September 16 run](../results-2026-09-16/README.md) for current
performance summaries. The earlier worker loaded `jsonlite` to read its job
description, which changed when R performed garbage collection during some
reads. The new worker accepts command-line arguments and prints its results
using base R. It checks that `jsonlite` is absent before and after each read.

All 1,821 readable DTA inputs produced Arrow files with matching full
value-and-metadata signatures. The same two malformed DTA inputs failed.
The run completed 3,644 timed read attempts, one per file and format.

## Comparable corpus totals

The table uses the same 1,812-file comparison set as previous reports.
The nine other readable inputs remain outside every comparator total.
Times sum one fresh-process read per file. They are not repeated-run medians.

| Corpus | Files | DTA input size | `read_dta()` | `read_arrow()` | haven | Stata `use` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| DHS | 641 | 46.903 GB | 38.684 s | 26.878 s | 2727.051 s | 68.806 s |
| MICS | 949 | 3.690 GB | 6.575 s | 5.656 s | 216.732 s | 1.155 s |
| NSFG | 222 | 5.772 GB | 8.724 s | 6.602 s | 234.588 s | 0.885 s |

Across this comparison set, `read_dta()` totaled 53.983 seconds
and `read_arrow()` totaled 39.136 seconds. Both readers were
faster than the retained haven time on every comparable file.

Across all 1,821 readable inputs, `read_dta()` totaled
54.130 seconds and `read_arrow()` totaled
39.268 seconds.

Haven and Stata measurements remain unchanged from
[August 24](../../r-corpus-performance/results-2026-08-24.md).
Neither comparator was rerun. Comparisons against them span measurement dates.
Arrow conversion and qualification are outside all timed reads.

## CPU and peak memory

Read CPU covers the read call. Process CPU and peak RSS cover the whole fresh
process, including startup, package loading, result checks and shutdown.
CPU columns sum over the comparable files. RSS is the largest individual
process peak. Memory uses decimal GB.

| Corpus | Reader | Read CPU | Process CPU | Maximum peak RSS |
| --- | --- | ---: | ---: | ---: |
| DHS | `read_dta()` | 75.979 s | 175.693 s | 5.236 GB |
| DHS | `read_arrow()` | 67.419 s | 167.118 s | 5.410 GB |
| MICS | `read_dta()` | 12.606 s | 156.226 s | 0.241 GB |
| MICS | `read_arrow()` | 11.600 s | 155.235 s | 0.230 GB |
| NSFG | `read_dta()` | 12.671 s | 46.326 s | 0.553 GB |
| NSFG | `read_arrow()` | 13.769 s | 47.437 s | 0.949 GB |

## Earlier DTA measurements

| Corpus | September 13 | Earlier September 16, JSON worker | This rerun | Change from September 13 |
| --- | ---: | ---: | ---: | ---: |
| DHS | 39.438 s | 39.708 s | 38.684 s | -1.9% |
| MICS | 6.658 s | 7.874 s | 6.575 s | -1.2% |
| NSFG | 8.959 s | 8.883 s | 8.724 s | -2.6% |

The [September 13 run](../../reader-startup/results-2026-09-13/README.md)
also used base R for worker setup and reporting. The runs were collected
separately. This rerun explicitly warms each DTA/Arrow pair and uses the
newer reader. These differences prevent attributing every timing change
solely to the reader code. The earlier measurements remain intact.

## Method and source

- Reader source is [`137b503a`](https://github.com/jbearak/dta-parser/commit/137b503a6200e4cb4be9c224089376736bcf697e),
  the installation used in the preceding corpus run. The package tree matches
  merge commit `3347e95b`. Subsequent package changes before this rerun are documentation only.
- Worker source is [`2402fb93`](https://github.com/jbearak/dta-parser/commit/2402fb93f9cf8da841ff91d6e144dfae08dc3d5f).
  The installed package and benchmark scripts are bound by hashes in the provenance.
- Host is an Apple M4 Max with 16 logical CPUs and 128 GiB RAM,
  running macOS 26.6.2 and R 4.6.1. The host was shared.
  This session ran no builds, tests or other benchmarks during timed reads.
- All Arrow files were created and qualified in a separate process before
  timing began. That preparation process uses `jsonlite` and exits before
  the first timed process starts.
- Files and formats run sequentially. Each read starts a fresh R process.
  Read time excludes package loading and includes first-reader initialization.
  There is no in-process warmup or forced garbage collection before reading.
- Hashing both inputs before each pair warms the filesystem cache.
  Format order alternates across files. These are warm-cache measurements.
- Both readers use automatic thread selection and default dibble output.
  Arrow checksum verification is enabled. Results remain live until process exit.
- Python checks each worker's status, dimensions and finite, nonnegative
  clocks before recording it. All common-file dimensions match the retained comparators.
- Source, installed package, workers, archived evidence, input size and
  modification time, and full input hashes are checked before completion.

## Evidence and reproduction

- [Aggregate measurements](corpus-summary.csv).
- [Sanitized provenance](provenance.json).
- [Controller and protocol](../README.md).

Survey copies, paths, signatures and individual child logs remain private.
The published CSV contains corpus aggregates.
