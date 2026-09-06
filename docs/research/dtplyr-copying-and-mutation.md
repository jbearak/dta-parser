# How dtplyr manages data.table copying and mutation

Research date: 2026-09-06.

## Finding

dtplyr avoids repeated table reconstruction by building a lazy query, translating
it into data.table operations, and executing the query at collection. A normal
immutable chain of five `mutate()` calls can make one initial table copy and
then update that private intermediate with `:=`. It still allocates replacement
columns. This is a useful model for reducing repeated work, but it does not
provide the column ownership and Stata validation guarantees required by an
eager dibble. See the [mutation translator][mutate-source], [query execution][eval-source],
and the local experiments below.

The distinction is measurable. With one million rows and 16 ordinary columns,
five symbol assignments allocated 168 MB when collected once as a data.table,
versus 680 MB when each step was collected and wrapped again. A standalone
immutable rename still copied all 128 MB of column payload. dtplyr does not
make that operation proportional to the number of renamed columns.

## Versions and method

The experiments used installed dtplyr 1.3.3, data.table 1.18.6.1, dplyr 1.2.1,
tibble 3.3.1, bench 1.1.4, and R 4.6.1 on the same Apple M4 Max machine as the
[dibble benchmark](../../benchmarks/r-dibble-dplyr/results-2026-09-05.md).
No packages were installed or changed.

The upstream dtplyr `v1.3.3` tag resolves to
[`2cc627511c34ed461093ae4c5dc94faccffeb93c`][dtplyr-pin]. The data.table `1.18.6`
tag resolves to [`c9d5dbecf9f858b84bf43da830ba83210578e30d`][datatable-pin].
The installed data.table build reports `RemoteSha = "1.18.6.1"`, not a commit
hash. Its exact upstream revision is therefore unverified. The relevant
installed R function bodies and observed behavior agree with the cited 1.18.6
code; experimental claims below apply to the installed 1.18.6.1 build. Current
data.table website pages identify themselves as 1.18.99, so pinned source is
used for implementation details.

The Stata typing comparison used dtatools 0.7.1 freshly built from
`3a8189933a8ddd32a1bc1c5c6194956382586a20` in
`/tmp/dibble-dplyr-benchmark.W2NXPq/library`, matching the earlier benchmark.
Other experiments used ordinary R columns. They isolate dtplyr/data.table
behavior and are not a direct Stata-class performance comparison.

## Query construction and execution

`lazy_dt(DT)` normally retains the source data.table without copying it. It
records column names, grouping names, a parent reference, local expressions,
and copy flags in step objects. A non-data.table is converted first, and
`immutable = FALSE` is rejected for that case. Supplying `key_by` can do work
immediately: an immutable data.table is copied before `setkeyv()`, whereas a
mutable source can be keyed in place. See [construction][first-source] and
[step fields][step-fields].

`dt_eval()` creates an evaluation environment, evaluates local assignments,
and runs the generated data.table expression. `as.data.table()`,
`as.data.frame()`, `as_tibble()`, and `collect()` invoke evaluation. Printing
also evaluates the query before formatting its first rows. `compute()` adds
an intermediate assignment to the translation; it does not eagerly materialize
and cache the result across future collections. See [execution][eval-source],
[collection methods][collection-source], and [printing][print-source].

This matters with mutable sources. Locally, building `mutate(x = x + 1)` and
calling `compute()` left the source unchanged. Collecting that computed query
twice incremented the original twice; subsequently printing the original lazy
query incremented it a third time. A lazy query also retains a live source
reference, rather than capturing an immutable snapshot at construction.

## Where copies enter the translation

The relevant bookkeeping is small. The first step sets `implicit_copy` from
the inverse of `immutable`. A mutate step requests a copy when its parent has
neither an implicit copy nor an existing copy request. The copy request
propagates to the first step, which emits `copy(DT)`. Subset steps mark a
nonempty `i` or `j` as producing an implicit copy. See the
[first-step translator][first-source], [mutate step][mutate-source], and
[subset step][subset-source].

For a source named `D`, installed dtplyr 1.3.3 generated these expressions:

| Lazy operations | Generated data.table expression |
| --- | --- |
| `mutate(x = y)` | `copy(D)[, x := y]` |
| Three successive symbol mutations | `copy(D)[, x := y][, y := x][, x := y]` |
| `filter(x > 1)` then `mutate(x = y)` | `D[x > 1][, x := y]` |
| `select(x, y)` then `mutate(x = y)` | `D[, .(x, y)][, x := y]` |
| `mutate(x = y)` then `select(x)` | `copy(D)[, x := y][, c("y", "g") := NULL]` |
| `group_by(g)` then `mutate(x = mean(x))` | `copy(D)[, x := mean(x), by = .(g)]` |
| `rename(z = x)` | `setnames(copy(D), "x", "z")` |

The chained mutations remain distinct `[` calls. Their benefit is reuse of a
single private table, rather than universal expression fusion. Within one
`mutate()`, dependent expressions can become a brace expression with sequential
local assignments and one final multi-column `:=`. The translator implements
both forms in [step-mutate.R][mutate-source].

Some adjacent operations do merge. A filter followed by a selection can become
one `D[predicate, .(columns)]` call. A selection followed by a filter generally
requires two calls because the filter must see the selected names. A filter
and mutation remain separate, since `D[predicate, x := value]` would update
rows of `D` and return the whole table. Selection after an already copied
intermediate can remove columns by reference. See [subset merging][subset-source],
[selection][select-source], and the [official translation examples][translation].

Copy elision is operation-specific. In this release, `rename()` always requests
an in-place call through `step_call()`, whose copy flag causes an upstream copy.
Both `lazy_dt(D, immutable = FALSE) |> rename(z = x)` and
`lazy_dt(D) |> filter(x > 1) |> rename(z = x)` still emitted `copy(D)`.
The latter copied the full input before subsetting it. This follows directly
from [rename and call construction][call-source] and was verified locally.

`immutable = FALSE` does remove the direct mutate protection, producing
`D[, x := y]`. It does not force every operation to modify the original.
After a real row subset, mutation ordinarily targets that subset. Nor does
the flag promise zero allocations: evaluating expressions, creating a subset,
or copying a referenced RHS still costs memory. data.table's
[native full-column assignment][assign-source] copies a shared or ALTREP RHS
before installing it; an unshared full-length RHS can be installed directly.
The public [reference semantics documentation][reference-semantics] describes
the distinction between `:=`, `set*`, and explicit `copy()`.

## Grouping and collection

Grouping names travel in the lazy step rather than being rebuilt as a grouped
tibble after every verb. Grouped mutate uses data.table `by`. Summarise normally
uses `keyby`, or `by` when grouping requests `arrange = FALSE`. Grouped filters
can compute matching row indices through `.I`, with a local intermediate to
avoid repeating an upstream computation within one evaluation. See the
[grouping implementation][group-source], [mutate translator][mutate-source],
and [grouped subset implementation][subset-source].

Collection is a separate cost and a separate ownership boundary:

- `as.data.table(lazy)` returns `dt_eval(lazy)[]`. It adds no unconditional
  protective copy. An identity query can therefore return the original table.
- `as_tibble(lazy)` evaluates, converts, and removes `.internal.selfref` and
  `sorted`. With the installed tibble version, conversion dispatches through
  `as.data.frame.data.table()`, whose body is `setDF(copy(x), ...)`. This adds a
  full copy of ordinary column payload.
- `collect(lazy)` uses `as_tibble()` and then restores lazy grouping with
  `group_by()` if needed. Plain `as_tibble()` does not restore those groups.
  `as.data.frame(lazy)` also goes through data.table's copying conversion.

These paths are in [dtplyr's collection methods][collection-source] and
[data.table's data-frame conversion][dataframe-source]. The installed tibble
dispatch was inspected with `getS3method("as_tibble", "data.frame")` and
confirmed by address and allocation experiments.

## Immutable input is not symmetric future-write isolation

The intended `immutable = TRUE` behavior protects the input during translated
operations. It is not a blanket promise that every returned data.table has
independent columns for later explicit writes. The identity path proves this
without relying on unusual callbacks:

```r
D <- data.table::data.table(x = c(1, 2), y = c(3, 4))
out <- data.table::as.data.table(dtplyr::lazy_dt(D, immutable = TRUE))
data.table::address(out) == data.table::address(D) # TRUE
data.table::set(out, i = 1L, j = "y", value = 99)
D$y # 99 4
data.table::set(D, i = 2L, j = "y", value = 88)
out$y # 99 88
```

The same aliasing occurred after `select(everything())`, which dtplyr elides.
After `filter(TRUE)`, the returned table object was different but its columns
were shared. Both directions of later `set(..., i = row)` changed the other
table. Real row subsetting, direct immutable rename, and direct immutable
mutate produced independent ordinary columns in the tested examples. Using
`as_tibble()` or `collect()` isolated these examples through the conversion
copy. This is an observed matrix for ordinary atomic columns, not a guarantee
for nested reference objects or every custom ALTREP implementation.

There is also an observed exception to input protection during execution:

```r
D <- data.table::data.table(x = c(1, 2, 3), g = c(1, 1, 2))
q <- dtplyr::lazy_dt(D, name = "D", immutable = TRUE) |>
  dplyr::filter(TRUE) |>
  dplyr::group_by(g) |>
  dplyr::mutate(x = 0)
print(dtplyr:::dt_call(q))
# D[TRUE][, `:=`(x = 0), by = .(g)]
invisible(data.table::as.data.table(q))
D$x # 0 0 0, although the source started as 1 2 3
```

This reproduced independently in two R processes on the recorded versions.
The mechanism is visible in source: dtplyr marks this subset as implicitly
copied, but data.table explicitly returns a shallow table for `DT[TRUE]`.
Grouped assignment then writes the shared column. See [dtplyr's subset flag][subset-source]
and [data.table's shallow subset branch][true-source]. This behavior conflicts
with the intended immutable-input contract. It should be treated as an
observed compatibility defect, not as an architecture to reproduce. No upstream
issue was filed as part of this research.

For dibbles, [ADR 0029](../adr/0029-use-explicit-mutation-and-copy-rebind-replacement.md)
requires later explicit writes to detach shared payload while preserving aliases
to the supplied physical table. dtplyr's flags are useful planning information,
but a node labelled "subset" is insufficient evidence of that ownership.

## Measured allocation costs

Fixtures contained one million rows and 16 distinct ordinary double or character
vectors. Character columns each repeated 1,000 distinct strings, with a separate
pointer vector per column. Setup and correctness checks were outside timing.
There were seven iterations with GC included and one data.table thread.
Memory figures are cumulative R allocations in decimal MB, not peak RSS.
Translation was measured separately; prebuilt-query execution excludes that
cost, while the eager loop includes five translations.

| Operation | Double median, ms | Character median, ms | Double allocation, MB | Character allocation, MB |
| --- | ---: | ---: | ---: | ---: |
| Build five lazy mutations only | 1.092 | 1.096 | 0.005 | 0.005 |
| Identity query to data.table | 0.031 | 0.030 | 0.0004 | 0.0004 |
| Identity query to tibble | 2.147 | 32.328 | 128.171 | 128.018 |
| Rename to data.table | 2.104 | 40.073 | 128.074 | 128.018 |
| Rename to tibble | 4.138 | 91.347 | 256.036 | 256.036 |
| One symbol mutation to data.table | 2.002 | 40.985 | 136.035 | 136.035 |
| Five lazy symbol mutations to data.table | 3.127 | 44.263 | 168.103 | 168.103 |
| Five lazy symbol mutations via `collect()` | 20.293 | 90.969 | 296.128 | 296.121 |
| Five separately executed symbol mutations to data.table | 30.925 | 265.281 | 680.194 | 680.194 |

The allocation arithmetic explains the result. Each ordinary column occupies
about 8 MB, so the initial table copy costs 128 MB. Each `c01 = c02` assignment
copies the referenced RHS, adding 8 MB. Five assignments therefore cost about
`128 + 5 * 8 = 168 MB`. Five independent executions instead cost
`5 * (128 + 8) = 680 MB`. Tibble conversion adds another 128 MB. These are
inferences from the measured allocations, confirmed by the emitted query and
[native assignment's shared-RHS branch][assign-source].

Times include GC and vary with retention and collection. The allocation
difference is more portable than the exact timing ratio. None of these numbers
proves a speedup for Stata validation or custom storage, since those checks were
absent from these ordinary-column fixtures.

## Metadata and Stata semantics

dtplyr tracks output column names and grouping names. Its step objects have no
Stata storage-validation or metadata-reconstruction fields. Expressions execute
as data.table expressions; some dplyr helpers are translated to functions such
as `fifelse`, `fcase`, or `shift`. Thus retaining an S3 class in a selected column
does not establish that all Stata semantics survived later operations. See
[step fields][step-fields] and [expression translation][eval-source].

A small local fixture with a `custom_number` S3 class, a column `label`, and a
table `dataset_label` confirmed that untouched column attributes survived the
tested identity, rename, select, filter, and symbol-mutate paths. The table
attribute survived identity, rename, filter, and symbol mutation, but disappeared
on selection and summarisation. `mean(x)` returned ordinary numeric output.
This experiment is evidence of operation-dependent attribute preservation;
it does not qualify dtatools' labels, tagged missings, string widths, compact
backing, temporal storage, joins, or promotions under dtplyr.

Most importantly, dibbles type values as they enter a sequential data mask.
The difference is observable even without custom input columns:

```r
eager <- dplyr::mutate(
  dtatools::dibble(id = 1:2), y = c(NA_real_, 1), z = y > 0
)
delayed <- dtplyr::lazy_dt(data.table::data.table(id = 1:2)) |>
  dplyr::mutate(y = c(NA_real_, 1), z = y > 0) |>
  data.table::as.data.table()
eager$z                           # TRUE TRUE
delayed$z                         # NA TRUE
dtatools::as_dibble(delayed)$z     # NA TRUE
```

This ran against the exact benchmark build. The corresponding existing contract
is tested in [test-dibble.R](../../r-package/dtatools/tests/testthat/test-dibble.R).
Typing only at collection cannot repair a later expression already evaluated
with different missing-value semantics. A future lazy Stata backend would need
typed expression boundaries, not just a final `as_dibble()` call.

## Recommendation for the five-PR plan

Keep the proposed [finalization and ownership architecture](../plans/dibble-result-performance.md).
The research supports its separation of validation, operation lineage, and
payload ownership. It does not justify replacing eager dplyr dispatch with
dtplyr or dropping isolation.

For PR 1, keep immediate typing of sequential values while centralizing and
reusing validation evidence. For PR 2, require proof about the actual returned
columns before skipping isolation; add the `filter(TRUE)` and grouped-mutation
case to the intended acceptance coverage. For PRs 3 and 4, retain the ownership
module, including future writes in both directions and conversion boundaries.
dtplyr's identity collection and shallow subset show why query flags alone
cannot replace it.

For PR 5, measure query construction, eager execution, conversion, retained
memory, and first-write cost separately. Include long chains, because repeated
finalization can dominate even when each isolated verb looks acceptable.
A separate optional lazy dibble backend could amortize ownership capture over
a chain, but it would introduce deferred evaluation and require an explicit
Stata-aware translator. That is a separate product decision from this eager
performance series and from opting into mutation under issue #189.

These are recommendations; this research changed neither the implementation
plan nor production code.

## Reproduce the measurements

Run this in a fresh R process with the versions above. It reproduces the
fixtures and measured expressions; timing and small first-use allocations will
vary. The complete scratch run and logs for this session are under
`/tmp/dtplyr-research.ruIAjq`.

```r
suppressPackageStartupMessages({
  library(dtplyr); library(dplyr); library(data.table); library(bench)
})
setDTthreads(1L)
pipeline <- function(x) {
  for (i in seq_len(5L)) x <- mutate(x, c01 = c02)
  x
}
eager_pipeline <- function(x) {
  for (i in seq_len(5L))
    x <- as.data.table(mutate(lazy_dt(x), c01 = c02))
  x
}
for (kind in c("double", "character")) {
  n <- 1000000L
  cols <- lapply(seq_len(16L), function(j) {
    if (kind == "double") as.double(seq_len(n)) + j / 16
    else rep(sprintf("v%02d-%06d", j, seq_len(1000L)), length.out = n)
  })
  D <- as.data.table(setNames(cols, sprintf("c%02d", seq_along(cols))))
  rm(cols)
  L <- lazy_dt(D, name = "D")
  one <- mutate(L, c01 = c02)
  five <- pipeline(L)
  renamed <- rename(L, renamed = c01)
  before <- D$c01[[1L]]
  stopifnot(identical(as.data.table(one)$c01, D$c02))
  stopifnot(identical(as.data.table(five)$c01, D$c02))
  stopifnot(identical(eager_pipeline(D)$c01, D$c02))
  stopifnot(identical(D$c01[[1L]], before))
  b <- bench::mark(
    translation_five = pipeline(L),
    identity_to_dt = as.data.table(L),
    identity_to_tibble = as_tibble(L),
    rename_to_dt = as.data.table(renamed),
    rename_to_tibble = as_tibble(renamed),
    mutate_one_to_dt = as.data.table(one),
    mutate_five_to_dt = as.data.table(five),
    mutate_five_to_tibble = collect(five),
    eager_five_to_dt = eager_pipeline(D),
    iterations = 7L, check = FALSE, filter_gc = FALSE
  )
  print(data.frame(
    kind, operation = as.character(b$expression),
    median_ms = as.numeric(b$median) * 1000,
    allocated_MB = as.numeric(b$mem_alloc) / 1e6,
    gc = b$n_gc, iterations = b$n_itr
  ))
  rm(D, L, one, five, renamed, b)
  gc()
}
```

[dtplyr-pin]: https://github.com/tidyverse/dtplyr/tree/2cc627511c34ed461093ae4c5dc94faccffeb93c
[datatable-pin]: https://github.com/Rdatatable/data.table/tree/c9d5dbecf9f858b84bf43da830ba83210578e30d
[first-source]: https://github.com/tidyverse/dtplyr/blob/2cc627511c34ed461093ae4c5dc94faccffeb93c/R/step-first.R#L48-L110
[step-fields]: https://github.com/tidyverse/dtplyr/blob/2cc627511c34ed461093ae4c5dc94faccffeb93c/R/step.R#L10-L37
[eval-source]: https://github.com/tidyverse/dtplyr/blob/2cc627511c34ed461093ae4c5dc94faccffeb93c/R/tidyeval.R
[collection-source]: https://github.com/tidyverse/dtplyr/blob/2cc627511c34ed461093ae4c5dc94faccffeb93c/R/step.R#L111-L155
[print-source]: https://github.com/tidyverse/dtplyr/blob/2cc627511c34ed461093ae4c5dc94faccffeb93c/R/step.R#L179-L204
[mutate-source]: https://github.com/tidyverse/dtplyr/blob/2cc627511c34ed461093ae4c5dc94faccffeb93c/R/step-mutate.R#L1-L54
[subset-source]: https://github.com/tidyverse/dtplyr/blob/2cc627511c34ed461093ae4c5dc94faccffeb93c/R/step-subset.R#L1-L95
[select-source]: https://github.com/tidyverse/dtplyr/blob/2cc627511c34ed461093ae4c5dc94faccffeb93c/R/step-subset-select.R#L19-L53
[call-source]: https://github.com/tidyverse/dtplyr/blob/2cc627511c34ed461093ae4c5dc94faccffeb93c/R/step-call.R#L1-L78
[group-source]: https://github.com/tidyverse/dtplyr/blob/2cc627511c34ed461093ae4c5dc94faccffeb93c/R/step-group.R
[assign-source]: https://github.com/Rdatatable/data.table/blob/c9d5dbecf9f858b84bf43da830ba83210578e30d/src/assign.c#L578-L603
[dataframe-source]: https://github.com/Rdatatable/data.table/blob/c9d5dbecf9f858b84bf43da830ba83210578e30d/R/data.table.R#L2363-L2367
[true-source]: https://github.com/Rdatatable/data.table/blob/c9d5dbecf9f858b84bf43da830ba83210578e30d/R/data.table.R#L691-L697
[translation]: https://dtplyr.tidyverse.org/articles/translation.html
[reference-semantics]: https://r-datatable.com/articles/datatable-reference-semantics.html
