# R cell assignment with set_dta_values() — 2026-09-19

## Result

On a 100,000-row dibble, one `set_dta_values()` call costs about an
eighth of one `repl()` call for a single positional row, and about a
fifth for a whole-column write, with no allocation per call. A loop
of 1,000 single-row writes takes 15 ms through `set_dta_values()`, 126 ms
through `repl()`, and 2 ms through `data.table::set()`. The remaining gap
to `set()` is the Stata storage check on every write and the private
column view the write path opens and releases; both are what make the
assigner refuse a value the column cannot hold rather than coerce it, and
the view is also what lets a value that runs code when it is read be
settled before the table's layout is read.

| Call | Median | Allocation | Iterations |
| --- | ---: | ---: | ---: |
| `repl_whole_column` | 122.6 µs | 781.6 KB | 200 |
| `repl_single_row` | 109.8 µs | 280 B | 200 |
| `set_dta_values_whole_column` | 22.1 µs | 0 B | 200 |
| `set_dta_values_single_row` | 14.3 µs | 0 B | 200 |
| `set_whole_column` | 7.3 µs | 0 B | 200 |
| `set_single_row` | 1.8 µs | 0 B | 200 |
| `repl_row_loop` | 126.3 ms | 310.5 KB | 3 |
| `set_dta_values_row_loop` | 14.5 ms | 9.6 KB | 3 |
| `set_row_loop` | 2.1 ms | 24.0 KB | 3 |

`repl_whole_column` is `repl(d, !!name := 2)` with `name` a runtime string;
`repl_single_row` is `repl(d, x = 3, where = 5L)`; the `set_dta_values_*`
rows are `set_dta_values(d, name, 2)` and `set_dta_values(d, name, 3,
rows = 5L)`; the `set_*` rows are `data.table::set(dt, j = "x", value = 2)`
and `set(dt, i = 5L, j = "x", value = 3)`; the loops write rows 1 through
1,000 one positional call at a time. Row selection is positional on every
side, so no side pays for a predicate scan. The `repl()` rows reproduce the
[earlier report](results-2026-09-19.md) within a microsecond.

## Method

- Host: Darwin 25.6.0 arm64 (Apple silicon)
- R: 4.6.1, `aarch64-apple-darwin25.4.0`
- dtatools: 0.10.0, built by the exact-source installer from source SHA
  `f598dd6d8e8c67c375f89b214a27ed231fe558d5`, package tree
  `af1b879d7f0b757e123f93a23b371dc22ee8df79`, clean checkout; the runner
  validated the installation's provenance sidecar before timing
- data.table: 1.18.6.1; bench: 1.1.4
- Fixture: `dibble(id = 1:100000, x = as.double(1:100000))` and the same
  columns as a `data.table`, built in the runner
- Iterations: 200 per single call, 3 per loop; medians from `bench::mark()`
  with `filter_gc = FALSE`
- Correctness: before timing, each call's landed value and its neighbour's
  were checked on both containers; after the loops, rows 1 through 1,000
  held the written value

Exact command, from the clean checkout at the SHA above:

```sh
Rscript --vanilla benchmarks/r-cell-assignment/run.R
```
