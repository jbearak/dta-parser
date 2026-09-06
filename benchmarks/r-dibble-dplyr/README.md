# Dibble dplyr overhead

This benchmark compares the same Stata column objects in a tibble and a dibble.
It separates container restoration from Stata vector semantics. Fixture creation
and correctness checks are outside the timed expressions. Timings include GC;
memory is cumulative R allocation, not peak RSS or total native allocation.

The [2026-09-05 report](results-2026-09-05.md) records the baseline and a narrow
validation prototype. The [implementation plan](../../docs/plans/dibble-result-performance.md)
describes the proposed architecture. No production optimization is included here.

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
