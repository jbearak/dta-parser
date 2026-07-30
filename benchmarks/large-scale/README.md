# Large-scale R benchmark

This report-only benchmark compares three readers in the same R process:

- `direct-r`: the public `dtaparser::read_dta()` path;
- `rust-vectors`: the retained internal `dtaparser:::.read_dta_rust_vectors()` baseline;
- `haven`: `haven::read_dta()`.

It measures full reads and a fixed eight-column projection on deterministic
approximately 100 MB and 1 GB Stata files. The default is 101 measured
iterations per implementation, workload, and size. Each path is warmed first,
execution order reverses on alternating iterations, and garbage collection runs
outside timed regions. There are no timing assertions or CI gates.

Before timing, the runner requires exact identity between the direct-R and
Rust-vector collectors for both workloads. It also compares 32-row projected
windows at the beginning, middle, and end of each file with haven, allowing only
`1e-7` numeric tolerance. The obsolete parser-only `dta_format_version`
attribute is normalized uniformly for the haven comparison; direct-R versus
Rust-vector identity is checked before that normalization. The manifest binds
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

Pass an iteration count only for local validation. For example, this executes
the complete two-size matrix once:

```sh
benchmarks/large-scale/benchmark.sh 1
```

All generated inputs and reports are written beneath an ignored checkout-local
private artifact root. Dataset files and the manifest are replaced atomically,
and rerunning the orchestration script recreates the same datasets and a
duplicate-free manifest. Completed report bundles are immutable and privately
selected. Python is invoked with bytecode generation disabled.

The default raw report has 1,212 rows:

```text
2 sizes × 2 workloads × 3 implementations × 101 iterations
```

`summary.tsv` has four rows, one per size/workload combination, with median,
5th percentile, 95th percentile, and median input throughput for all three
implementations plus pairwise median speedups.
