# R cell assignment

Report-only benchmark behind [ADR 0041](../../docs/adr/0041-typed-setters-and-stata-verbs-bound-the-mutation-surface.md).
It measures the per-call cost of the package's by-reference value verb
`repl()` against `data.table::set()`, the loop-friendly assigner the ADR
declines to add: one whole-column write, one single-row write, and a loop of
single-row writes. Each write is checked for its landed value outside the
timed region. It has no thresholds; the results are evidence, not a gate.

Run from a clean checkout:

```sh
Rscript --vanilla benchmarks/r-cell-assignment/run.R 100000 200 1000
```

Without `DTATOOLS_BENCH_LIB` the runner installs `HEAD` into a temporary
library through the exact-source installer
`benchmarks/r-dibble-dplyr/install.R`, which builds from `git archive` and
records a provenance sidecar. With `DTATOOLS_BENCH_LIB` set, that library must
have been installed the same way for the same `HEAD`; the runner validates the
sidecar against the installed files and refuses anything else, so a result is
never attributed to source it was not built from.

The arguments are the table's row count (at least 2), the iterations per
single call, and the number of rows the loop writes (at most the row count);
each defaults to the value shown. Row selection is positional on both sides,
so neither side pays for a predicate scan. The runner refuses a modified tree
and prints the source SHA and package tree, the package, `data.table`, and
`bench` versions, the R version and platform, and the host.

See [results-2026-09-19.md](results-2026-09-19.md) for the dated baseline.
