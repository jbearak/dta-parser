# R's datakit stays on tibbles, and `datakit_by()` tells the letters apart

The user asked on 2026-11-09 whether R's datakit should return and
accept polars frames, and then arrow tables. It does neither. Plan 0024
records the evidence; `docs/research/polars-2.md` holds the probes.

A tibble's doubles hold `.a` to `.z` as tagged NAs, and R treats an
`NA` as missing in every comparison: `x == 1`, `x != 1` and `x > 3000`
are `NA` on a letter, and `filter(x != 1)` drops it. polars and arrow
can hold the letters only as NaNs that are not null, and both treat a
NaN as a value. polars makes every NaN equal to every other and greater
than any number, so `x != 1` and `x > 3000` are true on a letter and
`x == .a` is true on `.b`. Arrow compares a NaN false with everything,
so `x != 1` is true on a letter. Either way, `filter(x != 1)` keeps 3
of the rows `1, 5000, .a, .b, .` where R keeps 1. A null compares as
missing, but neither engine keeps a letter under a null: polars and
arrow write zeros there when they sort or gather. Speed is for
idiomatic R to provide, not a second frame library.

**Grouping is the one place R gets the letters wrong**, and it gets
them wrong everywhere: base `unique()`, `duplicated()`, `match()`,
`%in%`, `table()`, `factor()` and `split()`, vctrs' `vec_unique()`,
`vec_group_id()` and `vec_in()`, and dplyr's `group_by()`, `distinct()`,
`count()` and joins all put `.` and `.a` to `.z` in one group. datakit
adds `datakit_by(..., .suffix = "_letter")`, which returns each column
and, beside each one that can hold a letter, its `na_tag()`. Used in
`group_by()`, `count()`, `distinct()` or `mutate()`, the groups and
join keys keep the letters apart, and only that call pays for it.

## Considered options

- **Polars frames through nanoarrow.** R polars imports R's memory
  without a copy, but its `as_polars_df()` turns every `NA` into a null
  and loses the letters, and polars compares the letters as values.
- **Arrow tables.** Arrow keeps `.a` and `.b` apart when grouping and
  joining, but compares a letter false with every number, and a letter
  changed by arithmetic forms a separate group from one that was not.
- **A vctrs class with comparison proxies on every double that can hold
  a letter** (as dtatools' `dta_num` has). Correct in every verb, but on
  10 million rows it made `group_by() |> summarise()` go from 140 to
  200 ms, `distinct()` from 43 to 120 ms, `arrange()` from 137 to 224
  ms and `filter(x > 500)` from 43 to 229 ms, on every later call.
- **`datakit_by()` returning one column with a proxy class.** 207 ms
  where a letter column took 256 ms (136 ms for the column alone), but
  the class stays on the column after grouping, and later calls pay for
  it.

## Consequences

- R's datakit has no polars or arrow functions, and none are planned.
- `docs/r.md` lists the functions that merge the letters and points to
  `na_tag()` and `datakit_by()`.
- A script that groups or joins by a column holding letters, and must
  keep them apart, has to say so with `datakit_by()`.
