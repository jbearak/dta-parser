# Large-scale R benchmark

This report-only benchmark compares three readers in the same R process:

- `dta-tools`: the public `dtatools::read_dta()` path (recorded as `direct-r`
  in raw machine-readable output);
- `rust-vectors`: the retained internal `dtatools:::.read_dta_rust_vectors()` baseline;
- `haven`: `haven::read_dta()`.

It measures full reads and a fixed eight-column projection on Stata-authored,
schema-deterministic approximately 100 MB and 1 GB files. The default is 101 measured
iterations per implementation, workload, and size. Each path is warmed first,
execution order reverses on alternating iterations, and garbage collection runs
outside timed regions. There are no timing assertions or CI gates.

The same run has two synthetic write benchmarks. In every primary iteration, a
fresh Stata process generates the data in memory and times its first `save`.
dtatools then loads and saves that exact Stata output. This rules out timing an
unchanged-file save after `use`. The 40 columns cover every numeric Stata
storage type: 4 `byte`, 4 `int`,
9 `long`, 4 `float`, and 9 `double` columns, plus 10 fixed-width strings. Four
of the longs have value labels; two doubles are Stata dates and two are Stata
datetimes. the dtatools package's reader retains those storage declarations, while Stata
creates them directly with storage-qualified `generate` commands. The canonical
100 MB and 1 GB inputs used by the read benchmarks come from the same Stata
generator.

The secondary benchmark compares dtatools with Haven on the exact same
freshly constructed ordinary R data frame. Its 40 columns are 11 doubles, 11
integers, 4 logicals, 2 `Date` columns, 2 UTC `POSIXct` columns, and 10 character
columns. They have no Stata storage, format, label, or value-label attributes.
Its checked-in row counts are independent of the primary DTA fixture, so a
change to the primary storage mix cannot silently change the secondary workload.
Stata is excluded because it cannot receive an in-memory R data frame, and
Haven is excluded from the primary matrix because its reader widens Stata
numeric storage into ordinary R vectors.

Every writer runs in a fresh process. Stata's primary operation timer covers
only its first `save`; the dtatools package's starts after it reads Stata's output. The
secondary timer starts after the R input has been constructed. Peak RSS
covers the whole fresh process because the in-memory input is part of the write
workload. Stata necessarily precedes dtatools in each primary pair; writer order
rotates in the independent secondary matrix. Raw primary rows retain the exact
paired input SHA-256 in addition to elapsed time, peak RSS, and output size. The
default is seven iterations per writer and size.

The [2026-08-28 write report](results-2026-08-28.md) records the latest complete
seven-iteration comparison. The [2026-08-27 report](results-2026-08-27.md) is
retained as the historical baseline.

Before timing, the runner requires exact identity between the dta-tools and
Rust-vector collectors for both workloads. It also compares 32-row projected
windows at the beginning, middle, and end of each file with haven, allowing only
`1e-7` numeric tolerance. Parser-only DTA storage classes and attributes are
removed uniformly for the haven comparison while labels and display formats
remain checked; dta-tools versus Rust-vector identity is checked before that
normalization. The manifest selects one immutable fixture generation and binds
each dataset path to its exact byte size, row width, row count,
fixed-file overhead, and SHA-256. Those invariants and hashes are verified both
before timing and immediately before atomic raw-result publication.

## Run

From the checkout root, run:

```sh
benchmarks/large-scale/benchmark.sh
```

The orchestration script builds the current package source, installs it into a
fresh ignored private library, and sets `DTATOOLS_BENCH_LIB` itself. It also
writes a private build-provenance record containing the commit, dirty state,
package version, canonical checkout and library identities, the built
source tarball SHA-256, and digests of every non-ignored package input,
large-scale harness input, and installed `library/dtatools/` file. Package
source is digested before the build and again after installation; any change
aborts the run before provenance is recorded. `run.R` recomputes and verifies
that provenance before
loading dtatools, then verifies the loaded namespace path itself, so direct
invocations reject missing records, copied records, source changes, modified,
swapped, or symlinked installations, and preloaded foreign namespaces. Orchestrated R
processes disable user profiles and environment files as defense in depth.

Each run also writes `run-provenance.tsv`. Its stable provenance ID binds the
build provenance ID, exact iteration count, manifest and dataset SHA-256 values,
sizes, row counts, full-column count, and projected-column count, R
version/platform, OS/kernel and CPU identity,
and versions plus resolved paths for dtatools, haven, tidyselect, readr, rlang,
and tibble. Every raw timing row carries the run and build IDs and its dataset
SHA-256; summaries retain all three fields. The summarizer accepts the runtime
provenance explicitly and rejects missing, duplicate, non-contiguous, nonfinite,
or metadata-inconsistent cells rather than summarizing a partial matrix.

Raw timings, summary, runtime provenance, and a copy of build provenance are
staged together. Only after the runner and strict summarizer both succeed is an
immutable private bundle published and its private selection updated atomically.
Failed reruns leave the prior completed bundle selected, and replacing the
working benchmark library cannot alter the build record copied into an older
bundle. Preserve the complete content-bound bundle with any dated report.

Pass read and write iteration counts for local validation. For example, this
executes both complete two-size matrices once:

```sh
benchmarks/large-scale/benchmark.sh 1 1
```

After a complete comparison, rerun only the primary dtatools writes while
retaining the selected run's Haven and Stata measurements:

```sh
benchmarks/large-scale/dtatools-write-only.sh 7
```

The dtatools-only runner rebuilds the current package, verifies the primary
synthetic hashes against the fixed reference rows, and publishes both its raw
measurements and a combined dtatools/Stata comparison beneath
`target/large-scale/dtatools-write-runs/`. Pass a complete run directory as
the second argument to override `target/large-scale/CURRENT`.

Run only the complete paired primary matrix with:

```sh
benchmarks/large-scale/primary-write-only.sh 7
```

This runner rebuilds dtatools, asks Stata to publish a complete immutable
synthetic-input generation, and publishes the dtatools, Haven, and Stata results
under `target/large-scale/primary-write-runs/`. It runs neither the read
benchmark nor the large corpus suite.

Run only the secondary ordinary-R matrix with:

```sh
benchmarks/large-scale/standard-r-write-only.sh 7
```

This runner rebuilds dtatools and publishes its dtatools/Haven results under
`target/large-scale/standard-r-write-runs/`. It does not execute Stata or the
large corpus benchmark.

All generated inputs and reports are written beneath an ignored checkout-local
private artifact root. Each complete dataset pair is published under an
immutable content-addressed generation directory, and the exact hash manifest
atomically selects that generation only after both files pass shape and size
checks.
Stata leaves volatile padding in some metadata fields, so semantic content and
storage are deterministic while file hashes bind the exact files created in
that run. Completed report bundles are immutable and privately selected.

The default raw report has 1,212 rows:

```text
2 sizes × 2 workloads × 3 implementations × 101 iterations
```

The primary `write-raw.tsv` has 42 rows by default:

```text
2 sizes × 3 writers × 7 iterations
```

The secondary `r-write-raw.tsv` also has 28 rows:

```text
2 sizes × 2 writers × 7 iterations
```

Each corresponding summary has one row per size and writer. Stata is required
only for the primary write matrix; `STATA_BIN` may override executable
discovery.

`summary.tsv` has four rows, one per size/workload combination, with median,
5th percentile, 95th percentile, and median input throughput for all three
implementations plus pairwise median time ratios, with the named implementation
in the numerator.

The public reader interns each distinct character value once per column and
returns a dictionary-backed ALTREP vector with compact row-to-dictionary
indices. Byte, int, long, and float columns also retain their source storage
width behind ALTREP until R requests a double data pointer; source doubles are
eager because ALTREP would not reduce their storage. Workloads that immediately
require contiguous double vectors can set `use_numeric_altrep = FALSE` (or option
`dtatools.numeric_altrep = FALSE`) to widen numeric values during decoding.
Timed reads therefore
measure dataset loading and tibble construction; the dimension check
materializes neither the full row-level string-pointer vector nor widened
numeric vectors. The exact
dta-tools/Rust-vector comparison and the haven window comparisons before timing
do access values, so laziness cannot hide correctness differences.
Use the separate `benchmarks/r-materialization/string-workloads.R` and
`benchmarks/r-materialization/memory-worker.R` harnesses for matched string-access and
fresh-process peak-memory measurements, including workloads that force the
complete returned object.

Stata 18 can be measured on the same generated input with internal `use`
timing and fresh-process peak RSS. `STATA_BIN` may override executable
discovery:

```sh
stata_1gb=$(Rscript --vanilla -e \
  'x <- read.delim("target/large-scale/datasets.tsv"); cat(x$path[x$dataset == "1gb"])')
Rscript benchmarks/large-scale/stata.R \
  "$stata_1gb" target/large-scale/stata-1gb-full.tsv 7 full

Rscript benchmarks/large-scale/stata.R \
  "$stata_1gb" target/large-scale/stata-1gb-projected.tsv 7 projected-eight-columns
```
