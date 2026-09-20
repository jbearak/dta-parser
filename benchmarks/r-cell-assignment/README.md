# R cell assignment

Report-only benchmark behind [ADR 0041](../../docs/adr/0041-typed-setters-and-stata-verbs-bound-the-mutation-surface.md)
and [ADR 0043](../../docs/adr/0043-set-dta-values-is-the-loop-friendly-assigner.md).
It measures the per-call cost of the package's by-reference value verbs,
`repl()` and the loop-friendly assigner `set_dta_values()`, against
`data.table::set()`: one whole-column write, one single-row write, and a
loop of single-row writes. Each write is checked for its landed value outside the
timed region. It has no thresholds; the results are evidence, not a gate.

Run from a clean checkout:

```sh
Rscript --vanilla benchmarks/r-cell-assignment/run.R 100000 200 1000
```

Without `DTATOOLS_BENCH_LIB` the runner installs `HEAD` into a temporary
library through the exact-source installer
`benchmarks/r-dibble-dplyr/install.R`, which builds from `git archive` and
records a provenance sidecar. With `DTATOOLS_BENCH_LIB` set, that library must
have been installed the same way for the requested revision; the runner validates the
sidecar against the installed files and refuses anything else, so a result is
never attributed to source it was not built from.
Set `DTATOOLS_BENCHMARK_REVISION` to compare an older commit on the same host;
both runners default to `HEAD`.

The arguments are the table's row count (at least 2), the iterations per
single call, and the number of rows the loop writes (at most the row count);
each defaults to the value shown. Row selection is positional on both sides,
so neither side pays for a predicate scan. The runner refuses a modified tree
and prints the source SHA and package tree, the package, `data.table`, and
`bench` versions, the R version and platform, and the host.

See [results-2026-09-19.md](results-2026-09-19.md) for the baseline that
motivated ADR 0041, before the assigner existed, and
[results-2026-09-19-set-dta-values.md](results-2026-09-19-set-dta-values.md)
for the run that measures it.

## Shared mutation measurements

`expanded.R` runs the same matrix against any committed revision. It covers
all four mutation entry points, creation and replacement, scalar and expression
inputs, fits, promotions and a rejected fixed assignment. It includes the
existing fused comparison path, 1-column and 100-column tables, and private
and shared target backing. `data.table::set()` supplies the positional
comparison. Retaining a data.table column does not give it dtatools' separate
result isolation guarantee, so its shared row is a timing comparison only.

```sh
DTATOOLS_BENCHMARK_REVISION=75771518 \
  Rscript --vanilla benchmarks/r-cell-assignment/expanded.R 100000 50 100 /tmp/mutation-baseline
Rscript --vanilla benchmarks/r-cell-assignment/expanded.R 100000 50 100 /tmp/mutation-candidate
```

An unset `DTATOOLS_BENCH_LIB` installs the requested revision through the
exact-source installer. A supplied library must carry matching provenance.
The checkout must be clean. The report records the package source revision
and tree separately from the revision containing the runner.

Each matrix sample builds its fixture before timing, then measures one
assignment with `bench::system_time(eval(call, env))`. The extra base `eval()`
is included for every entry point and revision. A shared fixture is rebuilt
for every sample, so each successful dtatools replacement measures its first
write after sharing. Creation leaves the existing shared columns in place. Private fixtures
are also fresh, with the target made private before timing. Generation adds
one column to a fresh table with spare capacity. Assertions run outside the
timed region, and an untimed call warms each case. These matrix times should
be compared with each other, not subtracted from `run.R`'s direct-call times.

`matrix.csv` records median and quartile times, a separate `profmem` R
allocation observation, and native scratch and payload-copy counters reset
after fixture setup. `native_scratch_bytes` counts heap staging and journals;
stack storage is excluded. `target_copy_bytes` measures old payload copied
to detach a replacement target. A zero R allocation does not imply zero
native allocation. `components.csv` times individual setup helpers, private
view creation/release, the native patch, and scalar generation. These isolated
measurements are evidence about the costly steps, not additive parts of an
end-to-end latency model.
