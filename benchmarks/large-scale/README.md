# Large-scale R benchmark

This report-only benchmark compares three readers in the same R process:

- `dta-parser`: the public `dtaparser::read_dta()` path (recorded as `direct-r`
  in raw machine-readable output);
- `rust-vectors`: the retained internal `dtaparser:::.read_dta_rust_vectors()` baseline;
- `haven`: `haven::read_dta()`.

It measures full reads and a fixed eight-column projection on deterministic
approximately 100 MB and 1 GB Stata files. The default is 101 measured
iterations per implementation, workload, and size. Each path is warmed first,
execution order reverses on alternating iterations, and garbage collection runs
outside timed regions. There are no timing assertions or CI gates.

The same run has two synthetic write benchmarks. The primary benchmark compares
dtaparser with Stata by loading and saving the deterministic 100 MB and 1 GB DTA
files. Its 40 columns cover every numeric Stata storage type: 4 `byte`, 4 `int`,
9 `long`, 4 `float`, and 9 `double` columns, plus 10 fixed-width strings. Four
of the longs have value labels; two doubles are Stata dates and two are Stata
datetimes. dtaparser's reader retains those storage declarations, while Stata
uses its native in-memory storage. Each worker changes the first `id` value
before timing so the benchmark measures serialization of dirty data rather than
any unchanged-file save shortcut.

The secondary benchmark compares dtaparser with Haven on the exact same
freshly constructed ordinary R data frame. Its 40 columns are 11 doubles, 11
integers, 4 logicals, 2 `Date` columns, 2 UTC `POSIXct` columns, and 10 character
columns. They have no Stata storage, format, label, or value-label attributes.
Its checked-in row counts are independent of the primary DTA fixture, so a
change to the primary storage mix cannot silently change the secondary workload.
Stata is excluded because it cannot receive an in-memory R data frame, and
Haven is excluded from the primary matrix because its reader widens Stata
numeric storage into ordinary R vectors.

Every writer runs in a fresh process. Operation timing starts after the primary
input has been read or the secondary R input has been constructed. Peak RSS
covers the whole fresh process because the in-memory input is part of the write
workload. Writer order rotates, and raw and summary reports retain elapsed write
time, peak RSS, and output size. The default is seven iterations per writer and
size.

The [2026-08-27 write report](results-2026-08-27.md) records the first complete
seven-iteration comparison.

Before timing, the runner requires exact identity between the dta-parser and
Rust-vector collectors for both workloads. It also compares 32-row projected
windows at the beginning, middle, and end of each file with haven, allowing only
`1e-7` numeric tolerance. Parser-only DTA storage classes and attributes are
removed uniformly for the haven comparison while labels and display formats
remain checked; dta-parser versus Rust-vector identity is checked before that
normalization. The manifest binds
each canonical dataset path to its exact byte size, row width, row count,
fixed-file overhead, and SHA-256. Those invariants and hashes are verified both
before timing and immediately before atomic raw-result publication.

## Run

From the checkout root, run:

```sh
benchmarks/large-scale/benchmark.sh
```

The orchestration script builds the current package source, installs it into a
fresh ignored private library, and sets `DTAPARSER_BENCH_LIB` itself. It also
writes a private build-provenance record containing the commit, dirty state,
package version, canonical checkout and library identities, the built
source tarball SHA-256, and digests of every non-ignored package input,
large-scale harness input, and installed `library/dtaparser/` file. Package
source is digested before the build and again after installation; any change
aborts the run before provenance is recorded. `run.R` recomputes and verifies
that provenance before
loading dtaparser, then verifies the loaded namespace path itself, so direct
invocations reject missing records, copied records, source changes, modified,
swapped, or symlinked installations, and preloaded foreign namespaces. Orchestrated R
processes disable user profiles and environment files as defense in depth.

Each run also writes `run-provenance.tsv`. Its stable provenance ID binds the
build provenance ID, exact iteration count, manifest and dataset SHA-256 values,
sizes, row counts, full-column count, and projected-column count, R
version/platform, OS/kernel and CPU identity, Python version/path,
and versions plus resolved paths for dtaparser, haven, tidyselect, readr, rlang,
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

After a complete comparison, rerun only the primary dtaparser writes while
retaining the selected run's Stata measurements:

```sh
benchmarks/large-scale/dtaparser-write-only.sh 7
```

The dtaparser-only runner rebuilds the current package, verifies the primary
synthetic hashes against the fixed reference rows, and publishes both its raw
measurements and a combined dtaparser/Stata comparison beneath
`target/large-scale/dtaparser-write-runs/`. Pass a complete run directory as
the second argument to override `target/large-scale/CURRENT`.

Run only the secondary ordinary-R matrix with:

```sh
benchmarks/large-scale/standard-r-write-only.sh 7
```

This runner rebuilds dtaparser and publishes its dtaparser/Haven results under
`target/large-scale/standard-r-write-runs/`. It does not execute Stata or the
large corpus benchmark.

All generated inputs and reports are written beneath an ignored checkout-local
private artifact root. Dataset files and the manifest are replaced atomically,
and rerunning the orchestration script recreates the same datasets and a
duplicate-free manifest. Completed report bundles are immutable and privately
selected. Python is invoked with bytecode generation disabled.

The default raw report has 1,212 rows:

```text
2 sizes × 2 workloads × 3 implementations × 101 iterations
```

The primary `write-raw.tsv` has 28 rows by default:

```text
2 sizes × 2 writers × 7 iterations
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
`dtaparser.numeric_altrep = FALSE`) to widen numeric values during decoding.
Timed reads therefore
measure dataset loading and tibble construction; the dimension check
materializes neither the full row-level string-pointer vector nor widened
numeric vectors. The exact
dta-parser/Rust-vector comparison and the haven window comparisons before timing
do access values, so laziness cannot hide correctness differences.
Use the separate `benchmarks/r-materialization/string-workloads.R` and
`benchmarks/r-materialization/memory-worker.R` harnesses for matched string-access and
fresh-process peak-memory measurements, including workloads that force the
complete returned object.

Stata 18 can be measured on the same generated input with internal `use`
timing and fresh-process peak RSS. `STATA_BIN` may override executable
discovery:

```sh
Rscript benchmarks/large-scale/stata.R \
  target/large-scale/synthetic-1gb.dta \
  target/large-scale/stata-1gb-full.tsv 7 full

Rscript benchmarks/large-scale/stata.R \
  target/large-scale/synthetic-1gb.dta \
  target/large-scale/stata-1gb-projected.tsv 7 projected-eight-columns
```
