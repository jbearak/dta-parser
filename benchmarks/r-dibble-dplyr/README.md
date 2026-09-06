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
mkdir -p "$benchmark_root/source" "$benchmark_root/library"
git archive "$benchmark_source" r-package/dtatools | tar -x -C "$benchmark_root/source"
R CMD INSTALL --preclean --library="$benchmark_root/library" \
  "$benchmark_root/source/r-package/dtatools"
R_LIBS="$benchmark_root/library" Rscript --vanilla -e \
  'library(dtatools); testthat::test_local(commandArgs(TRUE)[1], filter="dibble|reference-copy|dta-string|dta-numeric|mutate-data|slice-dta-rows", load_package="installed", stop_on_failure=TRUE)' \
  "$benchmark_root/source/r-package/dtatools"
Rscript --vanilla benchmarks/r-dibble-dplyr/run.R \
  "$benchmark_root/library" "$benchmark_root/results" "$benchmark_source" 7
Rscript --vanilla benchmarks/r-dibble-dplyr/prototype.R \
  "$benchmark_root/library" "$benchmark_root/prototype"
```

The baseline command requires clean tracked package source and exports only
tracked files from that revision. For an implementation comparison, build the
candidate's recorded commit the same way. `DTATOOLS_BENCH_KINDS` can restrict
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
expresses the future goal that renaming a column must not allocate its complete
retained numeric payload. It is not enabled as a current CI gate.

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
