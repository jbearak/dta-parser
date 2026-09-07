# Dibble dplyr overhead

This benchmark compares the same Stata column objects in a tibble and a dibble.
It separates container restoration from Stata vector semantics. Fixture creation
and correctness checks are outside the timed expressions. Timings include GC;
memory is cumulative R allocation, not peak RSS or total native allocation.

The [2026-09-05 report](results-2026-09-05.md) records the baseline and a narrow
validation prototype. The [implementation plan](../../docs/plans/dibble-result-performance.md)
describes the staged architecture. Later dated reports record production changes
and keep their exact source revisions separate from the initial prototype.

## Reproduce

Run from the repository root. Install `bench`, `dplyr`, and the package's test
dependencies first. Build the package source being measured into an isolated
library; do not use an older globally installed dtatools.

```sh
benchmark_source=$(git rev-parse HEAD)
git diff --exit-code "$benchmark_source" -- r-package/dtatools
benchmark_root=$(mktemp -d /tmp/dibble-dplyr-benchmark.XXXXXX)
Rscript --vanilla benchmarks/r-dibble-dplyr/install.R \
  "$benchmark_root/library" "$benchmark_source"
R_LIBS="$benchmark_root/library" Rscript --vanilla -e \
  'library(dtatools); testthat::test_local(commandArgs(TRUE)[1], filter="dibble|reference-copy|dta-string|dta-numeric|mutate-data|slice-dta-rows", load_package="installed", stop_on_failure=TRUE)' \
  "r-package/dtatools"
Rscript --vanilla benchmarks/r-dibble-dplyr/run.R \
  "$benchmark_root/library" "$benchmark_root/results" "$benchmark_source" 7
Rscript --vanilla benchmarks/r-dibble-dplyr/prototype.R \
  "$benchmark_root/library" "$benchmark_root/prototype"
```

The installer exports only tracked package files from the resolved revision,
builds its source archive and installs into a library without an existing
dtatools package. After successful installation it records the full source SHA,
package-tree ID, archive hash and installed-file hashes in a sidecar. Runners
that accept SOURCE_SHA validate that sidecar before creating result directories
or writing measurements, and retain the loaded-library path assertion. Missing
provenance, a mismatched SHA or a changed installation fails before output.
For an implementation comparison, install each recorded commit this way. `DTATOOLS_BENCH_KINDS` can restrict
the comma-separated storage kinds for a targeted rerun.

`run.R` checks equivalent result values and column attributes, input preservation,
and compact source backing before every paired timing. It measures rename,
selection, symbol replacement, row filtering, five successive mutations, and
numeric arithmetic across tall, wide, compact, ordinary, and mixed tables.
`stages.csv` measures constituent routines separately; those medians are not an
additive profile of the complete operation.

`prototype.R` changes no installed namespace or package source. It clones the
existing constructor into a private environment, bypasses validation after
proving that rename returned the source vectors, and retains all current column
isolation. It verifies output metadata and both directions of later mutation.
It is an experiment for column-only operations, not a general implementation.

`check-rename-allocation.R LIBRARY` intentionally fails on the baseline. It
requires that renaming an owned double column does not allocate its complete
retained payload. Stage 3 requires this check to pass; it remains separate from
the current CI workflow.

The dated result directory contains raw CSV files and package versions. The
package build/check result and exact baseline revision are recorded in the report.

## Direct column stage

`columns.R LIBRARY OUTPUT_DIRECTORY SOURCE_SHA` compares direct column methods
with whole-verb delegation through the same installed safe finalizer. It checks
values and metadata before timing, records nominal retained R object sizes
separately, and enforces the stage 1 limit of 130 MB for a 1M by 16 ordinary
string rename. It does not replace the future owned-backing allocation gate.
Run from the repository root with an isolated build of the recorded revision.
The historical reports and their revision labels remain unchanged.


## Direct row stage

`run-rows.R LIBRARY OUTPUT_DIRECTORY SOURCE_SHA [ITERATIONS]` measures ordinary
row brackets, the explicit helper, the dplyr row hook and the shared gatherer.
Tall and wide fixtures cover ordinary doubles/strings, compact integers and
dictionary strings, mixed columns, logicals and converted factors. Grouped
fixtures separately measure reconstruction, validation and delegated filter/
mutate consumers at 10,000, 100,000 and 1,000,000 rows. The default is nine
iterations with GC included. All fixtures and public equivalence checks are
outside timing; the runner rejects an unintended library, asserts dibble and
compact fixture preconditions, and records its own file hash.

The source oracle is serialized before operations and compared afterward.
Full-row result comparisons use a separate deserialized oracle so they cannot
materialize source ALTREP columns through a shared comparison target. Source
values, attributes and compact state are checked before and after timing.
`gather_only` isolates the common gather path but is not an additive timing
component of the public operation.

`row-memory.R LIBRARY KIND SOURCE_SHA` records the retained R vector-heap
increase after GC for a one-million-row, sixteen-column half-row subset.
Wrap that separate process with the platform's peak-RSS tool, such as
`/usr/bin/time -l` on macOS. Its peak includes startup, fixtures and validation;
it is not peak memory attributable only to the row operation. These retained
and process-peak measurements are distinct from `bench` cumulative allocation.

The [Stage 2 report](results-2026-09-06-stage2.md) records the exact final pair,
the small grouped-reconstruction regression, retained heap and process peaks.
`repeat-group-reconstruct.R LIBRARY OUTPUT_CSV SOURCE_SHA` repeats that
10,000-row, 1,000-group case with three independent fixtures and fifteen
iterations, retaining source and output guards outside timing.

Run `test-provenance.R LIBRARY SOURCE_SHA` against a fresh `install.R` library
for the bounded guard checks. It exercises every SOURCE_SHA runner with missing,
mismatched, malformed and changed installation metadata, asserts no result
output on rejection, and checks locale-independent fingerprints and matching
result output. Older dated artifacts keep their recorded runner versions and
manual exact-install verification; do not add provenance to an old library.

## Owned ordinary-double stage

The [Stage 3 report](results-2026-09-06-stage3.md) records the exact final pair,
the rejected first candidate and its read regressions, native mutation gates,
retained heap and process peaks. Run the following from a clean checkout with
the runner files from the candidate revision. Each library is created by the
provenance installer described above; the reported comparison uses Stage 2
`fd069a36832ed7c1bdedeed52a4281ecabb36e25` and candidate
`45f2ba489a6e0a2f25d1728eef0a84a6b2fde7b7`.

```sh
owned_bench_root=$(mktemp -d /tmp/dibble-owned-benchmark.XXXXXX)
owned_baseline=fd069a36832ed7c1bdedeed52a4281ecabb36e25
owned_candidate=45f2ba489a6e0a2f25d1728eef0a84a6b2fde7b7
Rscript --vanilla benchmarks/r-dibble-dplyr/install.R \
  "$owned_bench_root/baseline-library" "$owned_baseline"
Rscript --vanilla benchmarks/r-dibble-dplyr/install.R \
  "$owned_bench_root/candidate-library" "$owned_candidate"
Rscript --vanilla benchmarks/r-dibble-dplyr/owned-double.R \
  "$owned_bench_root/baseline-library" "$owned_bench_root/baseline" \
  "$owned_baseline" baseline 7
Rscript --vanilla benchmarks/r-dibble-dplyr/owned-double.R \
  "$owned_bench_root/candidate-library" "$owned_bench_root/candidate" \
  "$owned_candidate" candidate 7
Rscript --vanilla benchmarks/r-dibble-dplyr/check-rename-allocation.R \
  "$owned_bench_root/candidate-library"
```

`owned-double.R` checks tenfold row scaling for selectors, direct and safe
delegated five-verb pipelines, aggregates, arithmetic, filtering, coercion and
DTA/Arrow reads and writes. Every read/export is followed by a selector that
checks backing and allocation. First shared capture, subsequent private sparse
writes and full replacement are measured separately. Nested string RHS and
arithmetic row expressions retain their separate snapshot cost and alias checks.
Fixtures and independent source/result checks stay outside measurements.

`owned-double-memory.R LIBRARY SOURCE_SHA baseline|candidate OPERATION ROWS`
measures retained heap and release after rename, `pipeline_five` or `pipeline_50`.
Run each operation at 100,000 and 1,000,000 rows in its own process, for both
libraries. On macOS, one case is:

```sh
/usr/bin/time -l Rscript --vanilla benchmarks/r-dibble-dplyr/owned-double-memory.R \
  "$owned_bench_root/candidate-library" "$owned_candidate" candidate \
  pipeline_50 1000000
```

Run timed processes serially, without concurrent builds or tests. Retained heap,
nominal object sizes and whole-process peak RSS answer different questions.
Native copy counters overlap R allocation and one another; do not add them into
a total. The [reference-mutation runner](../r-reference-mutation/README.md)
also qualifies assigned capacity preparation and separately measured borrowed
capture before strict private writes. It preserves all 159 original assertions
and their original numerical limits. Zero Rprofmem bytes above a threshold does
not mean zero total allocation.
