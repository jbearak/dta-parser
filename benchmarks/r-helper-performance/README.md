# R helper performance

This report-only benchmark compares package-owned label factorization and
one-way tabulation with the corresponding Haven 2.5.5 workflows. It generates
a deterministic five-million-row Stata integer file, attaches three value
labels without decoding the source, and gives every timed iteration a fresh
compact column.

Install the package version under test into an isolated library, identify that
library explicitly, and run:

```sh
export DTAPARSER_BENCH_LIB=/path/to/isolated-library
Rscript --vanilla benchmarks/r-helper-performance/run.R 12 5000000
```

The first argument is the iteration count and the second is the row count.
Both must be positive decimal integers. The script checks result equivalence
and source materialization outside the timed region. On macOS it also runs
every operation in a fresh process under `/usr/bin/time -l`, reporting maximum
resident set size and peak memory footprint. It has no timing or memory
thresholds; results are evidence, not a release gate.
The runner refuses to use dtaparser from any other library, and the memory
workers inherit the same guard. Other platforms run the elapsed-time and
structural materialization checks and report `NA` for the macOS memory fields.

See [results-2026-08-26.md](results-2026-08-26.md) for the dated baseline.
