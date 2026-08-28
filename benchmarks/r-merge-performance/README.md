# R merge performance

This report-only benchmark compares `dta_merge()`, dplyr, base R, and Stata on
a deterministic wide merge. It measures both columns read from DTA files and
ordinary base R columns containing the same values.

Install the package under test into an isolated library, then run from the
repository root:

```sh
export DTAPARSER_BENCH_LIB=/path/to/isolated-library
Rscript --vanilla benchmarks/r-merge-performance/run.R 9 5
```

The first argument is the iteration count for `dta_merge()` and dplyr. The
second is the lower iteration count for the much slower base R cases. The
runner writes generated fixtures and a CSV summary below
`target/r-merge-performance/`. Fixture generation and correctness checks are
outside the timed regions. It executes and validates all 12 timed expressions
once before measurement, including row and column counts, key multiplicities,
merge-indicator counts, and representative shared-column values.

To collect Stata timings after the R runner creates the DTA fixtures:

```sh
stata-mp -b do benchmarks/r-merge-performance/stata-1m.do \
  target/r-merge-performance
stata-mp -b do benchmarks/r-merge-performance/stata-m1.do \
  target/r-merge-performance
```

The Stata timer includes reading the using file. The R timers start with both
inputs loaded. Allocated memory reported by `bench::mark()` is cumulative R
allocation, not peak resident memory. There are no timing assertions.

Each Stata script validates row-key uniqueness and `_merge` counts after every
timer. It writes the full timer log beside the generated fixtures.

See [results-2026-08-28.md](results-2026-08-28.md) for the dated baseline and
links to its tracked R summary and Stata timer outputs.
