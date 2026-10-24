# dtatools (development version)

* Breaking: dtatools no longer exports `summarize()` or `summarise()` to avoid
  conflicts with `dplyr::summarise()` and its alias `dplyr::summarize()`.
  Use `summ()` for Stata's `summarize` command, with the same arguments and
  return value.

* `mean()` of a Stata byte, int, long or float vector in dtatools' compact
  form no longer checks, before its native call, that the base functions
  `mean.default()` calls are unchanged. That check took about half of the
  call's admission. It still checks the `mean()` generic and methods. Over
  the 42,739 women in the first 100,000 rows of the India 2021 DHS births
  file, `summarise(b, m = mean(b2), .by = caseid)` falls from about 0.45 to
  0.41 seconds and `mutate(b, m = mean(b2), .by = caseid)` from 0.41 to
  0.37. Results are unchanged. A traced or replaced `isTRUE()`, `is.na()`
  or another base function that `mean.default()` calls no longer sees these
  means (ADR 0057).

* `==`, `!=`, `<`, `<=`, `>` and `>=` on a Stata numeric that is not a date
  or time run in one native call when the other operand is a number or a
  Stata numeric or double vector of the same length. They had converted a
  length-one operand, settled the thread option and tried the comparison
  kernel up to three ways through several R helpers. `x == 2016` on a
  three-value int falls from about 4.6 to 0.9 microseconds. Over the 42,739
  women in the first 100,000 rows of the India 2021 DHS births file,
  `filter(b, b2 == max(b2), .by = caseid)` falls from about 0.93 to 0.54
  seconds and `mutate(b, k = b11 >= 24, .by = caseid)` from 0.50 to 0.30.
  Results, warnings and errors are unchanged. A traced or replaced
  `.dta_compare()` or another helper of these comparisons no longer sees
  these calls (ADR 0060).

* `+`, `-`, `*` and `/` on a Stata numeric of fewer than 2,048 values, such
  as each group's column in a grouped verb, compute their result in one
  native call. They had captured the values and built the result through
  several R helpers. `x + 1` on a three-value int falls from about 10.5 to
  4.2 microseconds. Over the 42,739 women in the first 100,000 rows of the
  India 2021 DHS births file, `mutate(b, m = b2 + 1, .by = caseid)` falls
  from about 0.84 to 0.52 seconds and
  `mutate(b, m = (b2 - b4) / 12, .by = caseid)` from 1.52 to 0.90. Results
  are unchanged. A traced or replaced `.dta_data()`, `.dta_computed()` or
  another helper of this arithmetic no longer sees these calls (ADR 0059).

* Grouped `summarise()` scans its results' attributes in one native call
  when it looks for the results that can change their common type. It had
  looped over the results in R, up to twice per expression, calling
  `attributes()` and `identical()` for each one. Over the 42,739 women in
  the first 100,000 rows of the India 2021 DHS births file,
  `summarise(b, s = sum(b11, na.rm = TRUE), .by = caseid)` falls from about
  0.49 to 0.41 seconds and
  `summarise(b, m = mean(b2), x = max(bord), .by = caseid)` from 1.05 to
  0.98. Results are unchanged. A traced or replaced `identical()` no longer
  sees these scans (ADR 0056).

* `mean()`, `min()`, `max()` and `sum()` of one Stata byte, int, long or
  float vector in dtatools' compact form, as columns read from a file are,
  compute their result in one native call. They had captured the values
  and built the result through several R helpers, and `min()`, `max()` and
  `sum()` also listed and reduced their inputs in R. Over the 42,739 women
  in the first 100,000 rows of the India 2021 DHS births file,
  `summarise(b, m = mean(b2), .by = caseid)` falls from about 0.68 to 0.48
  seconds, `summarise(b, m = max(bord), .by = caseid)` from 0.92 to 0.40,
  and `mutate(b, m = mean(b2), .by = caseid)` from 0.61 to 0.41. Results,
  warnings and errors are unchanged. A traced or replaced `.dta_data()`,
  `.dta_computed()` or another helper of these methods no longer sees these
  calls (ADR 0054).

* Grouped `summarise()` copies each group's result in one native call when
  it is an atomic vector, and checks once per expression instead of once
  per group whether the result replaces a column. Over the 42,739 women in
  the first 100,000 rows of the India 2021 DHS births file,
  `summarise(b, m = mean(b2), .by = caseid)` falls from about 0.83 to 0.69
  seconds, `summarise(b, m = max(bord), .by = caseid)` from 1.10 to 0.92,
  and `summarise(b, n = n(), k = n(), .by = caseid)` from 1.17 to 0.87.
  Results are unchanged. A traced or replaced `.metadata_copy()` no longer
  sees these copies (ADR 0055).

* Verbs on a dibble type a new result in one native call when it is a
  Stata numeric, temporal or factor value or a bare logical, and in two
  when it is a bare integer or double scalar such as `n()` or a constant.
  Each such result had gone through several R helpers that decide its
  Stata type, and grouped verbs type one result per group. Over the 42,739
  women in the first 100,000 rows of the India 2021 DHS births file,
  `summarise(b, n = n(), .by = caseid)` falls from about 0.60 to 0.45
  seconds, `summarise(b, k = 2.5, .by = caseid)` from 0.52 to 0.38, and
  `summarise(b, n = n(), k = n(), .by = caseid)` from 1.48 to 1.17.
  Results are unchanged. A traced or replaced `.typed_column()`, or a
  helper it calls, no longer sees these results (ADR 0053).

* Compact Stata numerics built from R's own bytes, by the `dta_*()`
  constructors, computed results such as `mean()`, subsets, gathers,
  copies, `dta_append()` and unserialization, keep their descriptor on R's
  heap and register no finalizer. R scans every finalizer at each
  collection, so a grouped verb, which keeps one such result per group,
  had made each collection slower. Over the 42,739 women in the first
  100,000 rows of the India 2021 DHS births file, `summarise(b, m =
  mean(b2), x = max(bord), .by = caseid)` falls from about 3.07 to 2.59
  seconds and `summarise(b, m = max(bord), .by = caseid)` from 1.51 to
  1.33. Results are unchanged.

* Grouped `summarise()` and `mutate()` find the size of each group's result
  in one native call when it is a bare vector or a Stata numeric. They had
  called `vctrs::obj_is_vector()` and `vctrs::vec_size()`, which run
  `vec_proxy.dta_numeric()` in R for each group. `summarise()` also skips
  its second size check when every group's result has size one. Over the
  42,739 women in the first 100,000 rows of the India 2021 DHS births file,
  `summarise(b, m = mean(b2), .by = caseid)` falls from about 1.22 to 0.93
  seconds, `mutate(b, m = mean(b2), .by = caseid)` from 0.95 to 0.75, and
  `summarise(b, n = n(), .by = caseid)` from 0.87 to 0.61. Results and error
  messages are unchanged. A `vec_proxy.dta_numeric()` defined in the global
  environment no longer sees these checks (ADR 0052).

* `mean()` and `range()` on Stata numerics look up the names their checks
  need once per session instead of on every call, and `mean()` checks for
  user-defined `mean.numeric()` and `mean.double()` methods in the global
  environment once instead of twice. `mean()` of a three-value int falls
  from about 8.0 to 6.7 microseconds. Over the 42,739 women in the first
  100,000 rows of the India 2021 DHS births file, `mutate(b, m = mean(b2),
  .by = caseid)` falls from about 1.29 to 1.21 seconds. Results are
  unchanged.

* Grouped verbs on a dibble split each Stata numeric column they read into
  its groups in one native call. They had gathered each group's rows with a
  separate call to an R helper that decided again, for every group, how to
  gather the column. Over the 42,739 women in the first 100,000 rows of the
  India 2021 DHS births file, `summarise(b, m = mean(b2), .by = caseid)`
  falls from about 1.58 to 1.22 seconds, `mutate(b, m = mean(b2), .by =
  caseid)` from 1.26 to 0.95, and `filter(b, b2 == max(b2), .by = caseid)`
  from 1.79 to 1.50. Results are unchanged. When the split applies, a
  traced or replaced `.gather_dta_columns()` no longer sees the read, and
  the helpers it decides with see one call per column read instead of one
  per group. When the split declines, as for strings, those helpers see one
  more call per column read before the per-group calls (ADR 0051).

* Arithmetic, summaries such as `mean()`, and math functions on Stata
  numerics build a result of fewer than 2,048 values in one native call.
  Such a result had gone through the package's R code for choosing its
  storage, which took longer than the computation. `mean()` of a
  three-value int falls from about 14.7 to 8.1 microseconds, and `x * 0.5`
  on a three-value byte from 21.4 to 10.8. Grouped verbs make one such call
  per group. Over the 42,739 women in the first 100,000 rows of the India
  2021 DHS births file, `summarise(b, m = mean(b2), .by = caseid)` falls
  from about 2.01 to 1.66 seconds, `mutate(b, m = mean(b2), .by = caseid)`
  from 1.70 to 1.26, and `summarise(b, m = sum(b11, na.rm = TRUE), .by =
  caseid)` from 2.34 to 1.91. Results are unchanged. For these small
  results, a traced or replaced internal helper or base function that the
  R code calls, a replaced `.Machine`, and a `names<-` method for the
  package's classes no longer see the computation (ADR 0050).

* Restoring a Stata numeric vector's attributes after vctrs slices, casts,
  or combines it takes one native call, which sets the same attributes in
  the same order. A case that call does not cover, such as an attribute the
  restoration warns about, still runs the R code. A slice of a labelled
  column falls from about 17.4 to 11.4 microseconds, printing the 5,360
  columns of the Senegal 2017 DHS women's file from 0.130 to 0.096 seconds,
  and binding that file to itself from 3.31 to 2.33 seconds. Results and
  warnings are unchanged. A traced or replaced `.dta_attribute_plan()`,
  `.dta_classes_from()`, or `.replace_dta_attributes()` no longer sees these
  restores (ADR 0049).

* Grouped `mutate()` and `summarise()` on a dibble combine group results that
  keep a column's Stata metadata in one pass when every group's result has
  the same attributes. These are the results of `first()`, `last()`, `lag()`,
  `lead()`, and indexing on a labelled column. The verbs had called the
  package's `vec_ptype2()` and `vec_cast()` methods for every group. On the
  first 100,000 rows of the India 2021 DHS births file, with 42,739 women,
  `summarise(b, m = first(b2), .by = caseid)` falls from about 13.1 to 3.6
  seconds, and `mutate(b, m = lag(b2), .by = caseid)` from 9.7 to 2.5.
  Results and warnings are unchanged. Those methods now run two or three
  times per combine, so a traced or replaced method sees fewer calls
  (ADR 0048).

* When a grouped `mutate()` on a dibble gives one value per group, as
  `mean()` and `max()` do, the native combine now writes each value to its
  group's rows. Before, each group's Stata numeric or bare result went
  through `vctrs::vec_recycle()`, one call per group, even when it already
  had the group's size. Over the 42,739 women in the first 100,000 rows of
  the India 2021 DHS births file, `mutate(d, m = max(bord), .by = caseid)`
  falls from about 2.50 to 1.82 seconds, `mutate(d, m = mean(b2), .by =
  caseid)` from 2.32 to 1.65, and `mutate(d, m = b2 + 1, .by = caseid)` from
  1.99 to 1.83. Results are unchanged. The package's vctrs methods for Stata
  numerics no longer run for each group, so a traced method sees fewer calls
  (ADR 0047).

* Before a native route skips R code, it proves that each R function it
  skips is unchanged. It now remembers each proof and walks a function again
  only when its binding holds a different object, as after `trace()` or a
  replacement. Calls made once per group gain most. Over the 42,739 women in
  the first 100,000 rows of the India 2021 DHS births file,
  `mutate(d, m = mean(b2), .by = caseid)` falls from about 3.18 to 2.29
  seconds. On the Senegal 2017 DHS women's file,
  `summarise(d, m = mean(v012), .by = v001)` falls from 0.058 to 0.049
  seconds. Results are unchanged.

* Arithmetic that the native scalar route declines, such as on a column
  with value labels or with `^`, `%%`, and `%/%`, now classifies its
  result's Stata storage natively. So do math functions such as `abs()`,
  `log()`, and `exp()` on the byte, int, and long columns `read_dta()`
  returns. The arithmetic path had passed its result to that step as an
  unevaluated call. Base math had written its result into the column's data
  view, which the native step can't size. Either way every element went
  through R predicates. On the 1,274,250-row India 2021 DHS births file,
  `b4 * 2` on the labelled sex column falls from about 0.056 to 0.013
  seconds, `b4 / 2` from 0.119 to 0.013, `log(bord)` from 0.099 to 0.012,
  and `mutate(d, y = round(b11 / 12))` from 0.144 to 0.055. Results and
  errors are unchanged.

* Every grouped verb on a dibble checks that its grouping metadata matches
  its rows. That check now reads the rows of all groups in one native pass
  when they are ordinary integer vectors, as `group_by()` makes them, rather
  than calling the list's `[[` method, `is.integer()`, and `is.unsorted()`
  through R for each group. On the 1,274,250-row India 2021 DHS births file,
  `group_by(d, caseid)` over its 494,019 women falls from about 0.72 to 0.21
  seconds, and `arrange(g, b2, .by_group = TRUE)` on that grouping from 1.96
  to 0.99 seconds. Results and errors are unchanged.

* When a grouped verb on a dibble checks its grouping metadata, it compares
  each row's numeric grouping key with its group's key in one native pass,
  rather than repeating each group's key for every row and comparing the two
  with vctrs. On the India 2021 DHS births file, `count(d, v024, b4)` falls
  from about 0.10 to 0.05 seconds, grouped `mutate()` by state from 0.064 to
  0.037 seconds, and `group_by(d, v024)` from 0.025 to 0.012 seconds.
  Results and errors are unchanged.

* A Stata string column replaces `NA` with `""` in one native pass when
  vctrs restores, slices, or casts it, as `bind_rows()`, `vctrs::vec_c()`,
  and joins that pad unmatched rows do. Assigning `""` through `[<-` had
  copied a dtatools-owned string and then written each value through
  ALTREP. On the India 2021 DHS births file, `vctrs::vec_c()` of its
  1,274,250-row `caseid` column with itself falls from about 0.20 to 0.13
  seconds, and a `full_join()` of its 724,115 women to their births' `caseid`
  and `bidx` from 0.38 to 0.31 seconds. Results are unchanged.

* Grouped `summarise()`, `reframe()`, `count()`, and `tally()` on a dibble
  type a group's bare integer or double scalar result, such as `n()`, in one
  native call, as `gen()` already did for a scalar. They had built its Stata
  attributes in R for every group. A value that Stata storage can't hold
  still takes the R path and its error. On the 42,944-row Senegal 2017 DHS
  births file, `count(d, caseid)` over its 11,111 women falls from about
  0.48 to 0.34 seconds. Results and errors are unchanged.

* Grouped `summarise()` on a dibble takes its native common type and
  combine steps from a session's first call. Their checks compare each
  function they skip with the package's own copy, and declined while any of
  those functions was still waiting to be loaded. A session's first grouped
  summary, and in a session that had not built a Stata numeric through the
  R constructor every `summarise(n = n())`, then combined each group's
  result through vctrs's R methods. dtatools now loads those functions when
  it loads. On the 1,274,250-row India 2021 DHS births file, a session's
  first `summarise(group_by(d, caseid), n = n())` over its 494,019 women
  falls from about 187 to 34 seconds. Results are unchanged.

* Grouped `mutate()` on a dibble, and grouped `gen()` and `repl()`, combine
  per-group results stored as Stata bytes, ints, longs, or floats in one
  native pass, as they already did for doubles, rather than casting each
  group's result through vctrs's R methods. On the 1,274,250-row India 2021
  DHS births file, `mutate(group_by(d, caseid), v = mean(b2))` over its
  494,019 women falls from about 231 to 66 seconds, and `v = b2 + 1` from
  about 252 to 46 seconds. Results are unchanged.

* Grouped `slice()`, `slice_head()`, `slice_tail()`, `slice_min()`,
  `slice_max()`, and `slice_sample()` on a dibble pass the list of each
  group's rows to `vctrs::vec_c()` as one spliced argument, rather than
  through a call that `rlang::exec()` built with one argument per group.
  That call's cost grew with about the square of the number of groups. On
  the first 100,000 rows of the India 2021 DHS births file,
  `slice_head(group_by(d, caseid), n = 1)` over 42,739 women falls from
  about 16 to 0.6 seconds. Results and errors are unchanged.

* `tab()`, `tab1()`, and `tab2()` copy less on large data. Without `where`
  or `rows`, they take each group's rows as the sample, rather than
  rebuilding it through `sort(unique())` and `match()`. When they drop no
  row for a missing value or a zero or missing weight, they use the inputs
  as they are rather than copying subsets. They find the first row of each
  category, which its label and value come from, in one native pass that
  stops once every category has a row. On the 1,274,250-row India 2021 DHS
  births file, `tab(v024, data = bh)` falls from about 0.083 to 0.025
  seconds and `tab(v024, b4, data = bh)` from 0.12 to 0.036. Results are
  unchanged.

* `copy_data()` keeps a dibble's automatic row names. It stored them as
  explicit row names 1 to n, so `save_arrow()` on a copy, or on a table made
  from one by `keep_vars()` or `gen()`, warned that it dropped the row
  names.

* A string column that `read_dta()` or `read_arrow()` keeps in compact
  dictionary form now stays compact after `filter()`, `arrange()`, `[`, or
  `vctrs::vec_slice()`. Restoring the column's attributes had put it inside
  R's generic attribute wrapper, which hid the dictionary, so the width check
  that follows read every value through the wrapper. That width check, before
  a cast into fixed Stata string storage, now reads byte lengths from the
  dictionary rather than making a string for each value. When vctrs needs all
  of a compact column's values at once, as `vctrs::vec_c()` does, they are
  read from the dictionary directly rather than one at a time through R. On
  the 1,274,250-row, 1,644-column India 2021 DHS births file, `filter()` falls
  from about 0.51 to 0.44 seconds, `arrange()` from 0.57 to 0.47 seconds, and
  taking every other row with `[` from 0.48 to 0.43 seconds. Joining the
  births file's 1,274,250 rows to its 494,019 distinct `caseid` values,
  `left_join()` falls from about 0.60 to 0.35 seconds and `dta_merge()` from
  0.51 to 0.35 seconds. Saving 17 of its columns with `save_dta()` after
  `arrange()` falls from about 0.08 to 0.01 seconds. Results are unchanged.

* Width checks on a compact string column count only the values it holds.
  A slice of a compact column shares its source's whole dictionary, so on
  some slices of fewer than 64 rows, `dibble()` and `save_dta()` widened a
  narrower declaration such as `dta_string(x[rows], "str1")` to fit the
  widest value anywhere in the source.

* `labelbook()` groups each value-label table's variables in one pass,
  rather than finding the table by name for every labelled variable, which
  scanned every table found so far. It also joins the tables' diagnostics
  once and checks a table's codes for gaps without sorting them. On the
  16,787-row, 5,360-column Senegal 2017 DHS women's file, which has a table
  for each of 4,831 labelled variables, `labelbook(d)` falls from about
  0.57 to 0.31 seconds. Results are unchanged.

* `dta_match()`, `dta_in()`, `dta_identical()`, `dta_union()`,
  `dta_intersect()`, `dta_setdiff()`, and `dta_setequal()` compare strings
  as they are, rather than first pasting a prefix onto each one. A compact
  string column from `read_dta()` or `read_arrow()` is copied once into an
  ordinary vector, because `match()` slows down when it reads each value
  through the compact column. On the 1,274,250-row `caseid` column of the
  India 2021 DHS births file, matching it against every other row falls
  from about 0.41 to 0.03 seconds, and `dta_union()` from 0.49 to 0.10
  seconds. On an ordinary character vector holding the same values,
  `dta_match()` falls from 0.16 to 0.02 seconds. An empty string operand
  now matches nothing. Pasting the prefix onto an empty vector had given one
  key, the prefix alone, which also stood for `""`. So
  `dta_in("", character())` returned `TRUE`, `dta_setdiff(c("", "a"),
  character())` dropped `""`, and `dta_union()` with an empty operand
  failed. Other results are unchanged.

* `dta_append()` lines up the variables of its sources with `duplicated()`
  and `match()` over keys made of each name and its occurrence, rather than
  an environment lookup and a growing vector for each column. An ungrouped
  dibble source's zero-row schema is gathered natively by `slice_dta_rows()`
  rather than by `vctrs::vec_slice()`, which ran the vctrs methods of each
  column. Appending the 16,787-row, 5,360-column Senegal 2017 DHS women's
  file to itself falls from about 0.64 to 0.37 seconds, and appending it
  from two file paths from 0.58 to 0.48 seconds. Appending the
  1,274,250-row, 1,644-column India 2021 births file to itself falls from
  0.89 to 0.79 seconds. Results are unchanged, except that a column name
  longer than 10,000 bytes no longer stops the append with R's limit on
  variable names.

* `$<-`, `[[<-`, and the dplyr verbs on a dibble tell which result
  columns are the same vector as a prior column, a source column, or an
  earlier result column by comparing pointers, rather than by formatting
  an address string for every column and matching the strings. On a
  16,787-row, 5,360-column DHS file, `d$z <- value` falls from about 0.025
  to 0.015 seconds, `relocate()` from 0.019 to 0.014, `filter()` from
  0.052 to 0.045, and `left_join()` from 0.066 to 0.053. Results are
  unchanged.

* Subsetting a table with `[`, as `head()` does, checks which columns
  carry Stata notes or characteristics in one native pass, rather than
  with an R call for each column. So do `set_dta_metadata()` and the note
  and characteristic setters, such as `add_dta_note()`. On a 16,787-row,
  5,360-column DHS file, `head(d)` falls from about 0.037 to 0.031 seconds
  and `d[1:10, ]` from 0.039 to 0.033. Results are unchanged.

* Restoring a Stata numeric vector's classes after vctrs slices, casts, or
  combines it reads the storage classes from a fixed table, rather than
  spelling them with `paste0()` on every call. `vctrs::vec_slice()` on one
  labelled column takes about 5% less time, and on a 16,787-row,
  5,360-column DHS file `print(d)` falls from about 0.135 to 0.130
  seconds.

* `copy_data()` looks for environments, functions, bytecode, external
  pointers, and weak references in one native pass over the columns and
  their attributes, rather than an R call per value. On a 16,787-row,
  5,360-column DHS file it falls from about 0.14 to 0.05 seconds. Results
  and errors are unchanged.

* `save_dta()`, `save_arrow()`, and `datasig()` remember up to 32 display
  formats of each kind that passed their check in a write, so a later
  column with one of those formats skips the check. A format that carries
  attributes is still checked every time. They also skip the notes and
  characteristics getters for columns that have neither, and read a
  dibble's columns by position. On a 16,787-row, 5,360-column DHS file,
  `save_dta()` falls from about 0.44 to 0.31 seconds, `save_arrow()` from
  0.46 to 0.31 seconds, and `datasig()` from 0.41 to 0.26 seconds. Results,
  errors, and warnings are unchanged.

* Restoring a Stata numeric vector's attributes after vctrs slices, casts,
  or combines it matches the attribute names directly, rather than through
  `setdiff()` and `intersect()`, which check their arguments on every call.
  `vctrs::vec_slice()` on one column takes about half as long. On a
  16,787-row, 5,360-column DHS file, `print(d)` falls from about 0.23 to
  0.14 seconds and `dta_append(list(d, d))` from about 2.0 to 1.6 seconds.
  Results and warnings are unchanged.

* When `tab()` or `codebook()` group a compact byte column into levels,
  they mark the raw bytes present and write each row's level from a
  256-entry table, rather than decoding each value and hashing it.
  `codebook()` also counts each tabulation's levels and missing values in
  one native pass. On a 16,787-row, 5,360-column DHS file, `codebook(d)`
  falls from 2.2 to 1.6 seconds. Results are unchanged.

* Dibble verbs that evaluate expressions by group, such as `mutate()`,
  `summarise()`, and `filter()`, build one set of column bindings and use it
  for every group, rather than a binding for every column in each group.
  Bindings read the group being evaluated, as dplyr's do. A closure, pronoun,
  or quosure saved in one group and called in another now reads the current
  group's rows, as it would on a tibble. It still reads each column as it
  was when the capture was made. On a 16,787-row, 5,360-column DHS file with
  400 clusters, `summarise(d, m = mean(v012), .by = v001)` falls from 0.47
  to 0.06 seconds, and a `mutate()` of three expressions by cluster from 1.42
  to 0.10 seconds. On the first 100,000 rows of the India 2021 DHS births
  file, `filter(d, n() > 1, .by = caseid)` over 42,739 women falls from 0.73
  to 0.36 seconds.

* `summ()` with a varlist of column names, which includes the default of
  every column, builds each variable's entry from its name and label,
  rather than through the expansion that factor variables, interactions,
  and time-series operators need. On a 16,787-row, 5,360-column DHS file,
  `summ(d)` falls from 1.5 to 0.87 seconds.

* `summ()` does less work for each variable. It copies a group's weights
  once rather than once per variable, and skips the part of an unused
  observation check that cannot fail. Without weights, it reads compact
  byte, int, and long columns directly, sums them in integers, and with
  `detail = TRUE` sorts their observed values by counting them. Detailed
  percentiles find all nine positions with one search rather than nine
  scans of the running totals. On a 16,787-row, 5,360-column DHS file,
  `summ(d)` falls from 0.75 to 0.28 seconds and `summ(d, detail = TRUE)`
  from 2.0 to 0.57 seconds. Results are unchanged.

* Indexing an empty `byte`, `int`, `long`, or `float` Stata numeric returns
  ordinary missing doubles, rather than compact storage of missing values.
  vctrs starts each combined column this way from the zero-length common
  type and then writes every input into it, so the compact result was
  decoded again at once. On a 16,787-row, 5,360-column DHS file,
  `bind_rows(d, d)` falls from 7.0 to 6.4 seconds.

* Replacing a column of a dibble with `$<-`, `[[<-`, or `[<-`, and
  `transform()`, `within()`, `group_modify()`, `summarise()`, and
  `reframe()`, match the result's column names to the prior columns in
  one pass, rather than scanning the names once per column. On a
  5,360-column DHS file, `d$v012 <- d$v012 + 1` falls from 83 to 30
  milliseconds.

* Native arithmetic and summary admission compares dtatools' captured
  helper closures with less work per call. Its comparison table clears only
  its occupancy flags, a shared symbol or environment compares by identity
  without the vector checks, and a helper found again in the base namespace
  is not compared a second time. `x + 1` on a 16,787-value Stata double
  falls from about 111 to 81 microseconds, and `mean()` on 10 values from
  157 to 129. A grouped `summarise(m = mean(x))` over 10,000 groups falls
  from 4.7 to 4.4 seconds.

* `duplicated()`, `anyDuplicated()`, and `unique()` on a Stata numeric,
  date, or datetime vector compare the packed native key that `dta_match()`
  uses, rather than formatting each value as text. On 2 million doubles,
  `unique()` falls from about 2.4 seconds to 0.03 seconds, and `factor()`,
  `table()`, and `tab()` on 2 million bytes each save about 0.4 seconds.
  Results and errors are unchanged.

* `duplicated()`, `anyDuplicated()`, and `unique()` on a dibble compare
  rows through one integer key per row, built with `match()` one column
  at a time, rather than through base's list of cells for every row,
  which dispatched `[[` on each Stata value. On a 16,787-row, 5,360-column
  DHS file with 500 rows repeated, `duplicated()` takes 0.6 seconds, where
  base would take over an hour. Results are those of the base methods.
  Columns the key cannot compare as base does, such as factors, dates, and
  lists, still take the base methods.

* `unique()` on a dibble no longer reads a column named `x` or `fromLast`
  in place of its own argument. It deduplicated by that column alone.

* `mean()` and `range()` on a Stata numeric compare each base R closure
  they depend on once per call, rather than once for every binding that
  holds it, when they check that base dispatch is unchanged. A `mean()` of
  20 values falls from 161 to 44 microseconds. Over 10,000 groups of
  100,000 rows, `gen(d, z = mean(x), by = g)` falls from 2.9 to 1.5 seconds,
  and grouped `summarise()` and `mutate()` with `mean()` from 5.2 to 3.5
  seconds.

* `subset()` on a dibble selects its rows with the native gather that `[`
  on a dibble uses, rather than slicing one column at a time. On a
  16,787-row, 5,360-column DHS file, `subset(d, v012 > 30)` falls from
  about 0.6 to 0.1 seconds. Results, errors and warnings are unchanged.

* `[` and `head()` on a dibble with Stata metadata check each column's
  notes and characteristics without a function call per attribute name.
  On a 16,787-row, 5,360-column DHS file, `head(d, 10)` falls from about
  67 to 53 milliseconds.

* `summ()` and `tab()` slice a column to each group only when `where`,
  `weights`, `subpop`, or `summarize` reads it, rather than slicing every
  column of the data. On a 16,787-row, 5,360-column DHS file,
  `tab(d, v106, by = v024)` falls from about 5 seconds to about 10
  milliseconds and `summ(d, v012)` from about 1 second to 1 millisecond.

* The vctrs equality and ordering proxies for Stata numerics rank missing
  values in one native pass, so duplicate checks, `unique()` and sorting
  through vctrs do less work per column. Detecting duplicate observations
  across a 5,360-column file took 2.2 seconds and now takes 0.5.

* `dta_append()` copies each source's rows of a numeric column into the
  result natively, decoding compact columns in blocks, and no longer copies
  the whole result column on every write. Appending a 5,360-column file to
  itself took 8.4 seconds and now takes 5.7.

* A subset of a string column from `read_dta()` or `read_arrow()` that is
  at most a sixteenth as long as the column's dictionary of distinct values
  is built as ordinary strings, rather than over a copy of the whole
  dictionary. vctrs takes an empty subset of each input it compares,
  combines or casts, and a grouped verb slices each group's rows, so these
  copies added up. A cast into `strL` storage also stops measuring the
  width of each value, since `strL` holds any width, and a cast of a
  compact column no longer scans it for `NA`, which its dictionary cannot
  hold. On the India 2021 DHS birth history file, with 1,274,250 rows and
  494,019 distinct `caseid` values, `caseid == ""` falls from 0.20 to 0.02
  seconds, `codebook()` of `caseid` from 1.09 to 0.60, and a
  `summarise(f = first(caseid))` grouped by cluster over the 14,526 rows
  of 378 clusters from 96 to 0.16.

* A compact subset or copy of a string column from `read_dta()` or
  `read_arrow()` shares the column's dictionary of distinct values, rather
  than rebuilding the dictionary's strings and hash table for itself. On
  the India 2021 DHS birth history file, a subset of every other row of
  `caseid` falls from 19 to 3 milliseconds, `filter(b2 >= 2010)` on three
  columns from 54 to 31, and `arrange(desc(b2))` from 127 to 104.

* Printing or formatting a dibble checks the classes of declared string
  columns only, rather than running a set operation on every column. On a
  5,360-column DHS file, printing falls from 0.25 to 0.21 seconds.

* Grouped `summarise()` and `reframe()` stop folding an expression's
  per-group results into a common type once the type settles. When there are
  at least eight groups, every group returns a plain Stata double with the
  same attributes, and the Stata numeric methods are unchanged, the first
  three groups give the common type. Other results are folded over every
  group as before. On 100,000 rows in 10,000 groups,
  `summarise(m = mean(x))` falls from 4.5 to 2.7 seconds, and
  `summarise(s = sd(x))` from 3.1 to 1.3 seconds.

* Grouped `summarise()` and `reframe()` combine per-group plain Stata
  doubles natively, without casting each group's result to the common type
  twice, when the Stata numeric methods are unchanged. On 100,000 rows in
  10,000 groups, `summarise(s = sd(x))` falls from 1.3 to 0.55 seconds and
  `summarise(m = mean(x))` from 2.7 to 1.9 seconds.

* Grouped `summarise()` and `reframe()` also stop folding per-group results
  into a common type once it settles when the groups return compact Stata
  bytes, ints, longs or floats, or a mix of up to four Stata numeric storage
  types. The mean of a byte column, a byte in groups where it is whole and a
  float elsewhere, now settles too. On 100,000 rows in 10,000 groups,
  `summarise(m = mean(x))` on a byte column falls from 4.5 to 2.8 seconds,
  `summarise(m = max(x))` from 3.1 to 1.3 seconds, and
  `summarise(k = n())` from 2.9 to 1.1 seconds.

* Grouped `summarise()` and `reframe()` also combine per-group compact Stata
  bytes, ints, longs and floats natively when each group's storage widens to
  the common one, as a byte widens to an int or a float. Loading dtatools
  now settles one lazily loaded base function that these checks read, so a
  session that never builds a Stata double takes the native path too. On
  100,000 rows in 10,000 groups, `summarise(m = max(x))` on a byte column
  falls from 1.4 to 0.6 seconds, `summarise(k = n())` from 1.2 to 0.4
  seconds, and `summarise(m = mean(x))` from 2.8 to 1.9 seconds.

* dplyr verbs on wide dibbles set up their data mask in time linear in the
  number of columns. On a 5,360-column file, `filter()`, `mutate()`,
  `summarise()`, `count()` and `arrange()` each took 0.6 to 1.5 seconds and
  now take 0.03 to 0.12 seconds.

* `mutate()` on a dibble reads only the prior values each new column uses,
  rather than every column's value once per new column. On a 5,360-column
  file, `mutate(d, across(1:1000, ~ .x))` falls from 2.9 to 0.25 seconds.

* `dta_group_id()` and `dta_group_tag()` sort rows with a radix sort when
  every key is an ordinary or dtatools numeric vector or a string column
  from `read_dta()` or `read_arrow()`, rather than a merge sort that
  compared keys. Such a string column now ranks its distinct values once and
  sorts by those ranks, where it made an R string for every row and compared
  strings. `egen()` passes such a column to its calculation without a slice
  when it reads every row. On a 1,274,250-row DHS birth history,
  `dta_group_id(caseid)`, with 494,019 distinct values, falls from 0.27 to
  0.05 seconds, `dta_group_id(v001)` from 66 to 20 milliseconds, and
  `egen(d, g = dta_group_id(caseid))` from 0.33 to 0.08 seconds.

* `is.na()` and `is_missing()` scan compact numeric storage directly in typed
  blocks, including retained Arrow chunks and compact dates. Missing tags and
  IEEE NaNs keep their existing meanings, and scans leave inputs compact.
  Compact sums use direct typed blocks while preserving accumulation order
  across blocks and chunks.

* `mutate()` on a dibble grouped with `group_by()` or `rowwise()` assembles
  per-group Stata doubles natively, as it already did with `.by`. dplyr keeps
  each group's rows in a `list_of`, which native assembly declined, so every
  group's result went through vctrs. On 100,000 rows in 10,000 groups,
  `mutate(y = x * 2)` falls from 3.1 to 0.6 seconds and `mutate(m = mean(x))`
  from 4.6 to 2.5 seconds. On 10,000 rowwise rows, `mutate(s = a + b)` falls
  from 3.3 to 0.6 seconds.

* `dta_append()` skips reconciling a Stata numeric or string variable whose
  sources declare it identically apart from value labels. It takes an empty
  Stata numeric or string schema column as its own prototype, unless the
  column carries the class that marks notes and characteristics. It reads a
  dibble or tibble source's columns by position rather than by name.
  Appending a 5,360-column DHS file to itself falls from 5.3 to 2.6 seconds,
  and appending two copies of it on disk from 4.6 to 2.2 seconds.

* `dta_append()` collects a byte, int, long or float variable as raw bytes
  while its sources convert to compact storage of that type, rather than
  decoding every source into doubles and encoding the result again.
  Building a Stata numeric from compact storage of the same type copies
  its bytes. Appending a 16,787-row, 5,360-column DHS file to itself falls
  from 1.9 to 1.3 seconds and its peak memory from 1.6 to 0.5 GB, and
  appending two copies of it on disk falls from 1.6 to 1.0 seconds.

* `dta_append()` builds each byte, int, long or float column from one scan
  of the bytes it collected, where it copied and scanned them twice, and the
  column keeps those bytes as its storage. It also builds a double column
  with the native constructor. The collected buffer now loses its marker
  attributes before any other binding holds it. Removing them later had made
  R wrap the shared buffer. Reading the wrapper's bytes copied them, and the
  native double constructor declined the wrapper, so the slower R checks ran
  instead. The scan of compact byte, int and long values counts in the
  width of the values, which makes it about eight times faster on bytes.
  The loops over columns drop references by assignment rather than with
  `rm()`, which takes about 4.5 microseconds a call. Appending the
  1,274,250-row, 1,644-column India 2021 DHS birth history to itself falls
  from 4.1 to 1.0 seconds, a 16,787-row, 5,360-column DHS file from 1.0 to
  0.75 seconds, and 20 double columns of 1,000,000 rows from 0.73 to 0.09
  seconds.

* `summ()` expands long varlists in linear rather than quadratic time,
  summarizes a full sample without copying each variable, and builds its
  statistics table once. Summarizing all 5,360 variables of a 16,787-row
  DHS file falls from 15.2 to 2.9 seconds, and with `detail = TRUE` from
  17.5 to 4.4 seconds.

* `egen()` with `by`, `bysort`, or a `group_by()` table computes
  `dta_mean()`, `dta_min()`, `dta_max()`, or `dta_total()` of one column
  for every group in one native pass, rather than evaluating the
  calculation once per group. Each group's values are read in the same
  order as before, so the results are unchanged. On a 42,944-row DHS birth
  history file, `egen(d, z = dta_mean(b2), by = caseid)` over 11,111 women
  falls from 0.68 to 0.003 seconds, and on a 1,274,250-row file over
  494,019 women from 38 to 0.15 seconds.

* `dta_merge()` matches a string key that is a column from `read_dta()` or
  `read_arrow()` on both sides through integer codes, one for each distinct
  value, rather than through R strings. Rows get equal codes exactly when
  their values are equal, so the merge matches the same rows. With five
  columns of the 1,274,250-row India 2021 DHS birth history and four of the
  724,115-row women file, a many-to-one merge on `caseid` falls from 0.51
  to 0.26 seconds.

* `dta_merge()` gathers the result's columns by position rather than
  looking each one up and appending it by name. On a 16,787-row,
  5,360-column DHS file, a one-to-one merge that adds one variable falls
  from 0.34 to 0.13 seconds.

* Gathering compact numeric columns by row, as `dta_merge()`, `filter()`,
  `arrange()`, and `[` do, copies each value with a loop fixed to the
  column's width and copies each run of 16 or more consecutive rows as one
  block. Each column decides once, not once per row, how to test its values
  for missing, and each worker takes the next column as it finishes one. On
  the 1,274,250-row, 1,644-column India 2021 DHS birth history file, an
  `m:1` merge on `caseid` falls from 0.78 to 0.35 seconds and
  `arrange(b2)` from 0.46 to 0.29 seconds.

* `save_dta()`, `save_arrow()`, and `datasig()` check each column's display
  format with one `regexpr()` call instead of `regmatches()` over
  `regexec()`, check value-label table names in one call, and find the
  attributes Arrow drops without `setdiff()`. On a 5,360-column DHS file
  `save_dta()` falls from 0.68 to 0.44 seconds, `save_arrow()` from 0.74 to
  0.46 seconds, and `datasig()` from 0.69 to 0.40 seconds. Files,
  signatures, errors, and warnings are unchanged.

* `save_dta()` no longer writes every cell one at a time when one column
  has no buffer the writer can read directly, such as an ordinary character
  column made by `mutate()` or a column with Stata notes after `[`. Such a
  column now fills its cells of each block of rows on the main thread, and
  the other columns still fill theirs on worker threads. On the
  1,274,250-row, 1,644-column India 2021 DHS birth history,
  `save_dta(bh[, names(bh)])` falls from 34 to 1.4 seconds, and saving the
  result of an `m:1` merge with four columns of the women file falls from
  40 to 1.3 seconds. Files are unchanged. A strL column still sends the
  dataset to the row-by-row writer.

* `dta_byte()`, `dta_int()`, `dta_long()`, and `dta_float()` validate and
  encode values about three times faster. The native constructor checks for
  missing and finite values inline instead of calling into R for each value,
  and encodes each storage type in its own loop. Building a byte column from
  10 million values falls from 88 to 30 milliseconds. A non-double vector of
  2,048 or more values also skips the qualification check for the native
  double constructor, which only double storage can pass and which cost
  about 35 microseconds per vector. `dplyr::bind_rows()` of two copies of a
  5,360-column DHS file falls from 8.8 to 7.9 seconds. Results and errors
  are unchanged.

* `save_dta()` no longer takes minutes to write a strL column from an
  ordinary character vector of more than about 350,000 rows. Planning
  rereads the first row of each repeated value. Past the first region of
  string pointers, each reread refilled the region from that earlier row,
  and the next row refilled it again. An earlier row is now read by
  itself. Saving 500,000 rows of 20 DHS columns plus a note column that
  holds either a 3,000-byte value or `"short"` falls from 190 to 0.33
  seconds. Files are unchanged.

* Compact numeric scalar reads forward directly to the native getter and
  resolve wrapper state once. Retained readers cache the entire current chunk
  for forward, reverse, and permuted access.

* `codebook()` tallies a numeric variable's observed values by value when
  they are whole numbers whose range is at most their count plus 65,536.
  One tally gives the distinct values in order of first appearance, the
  minimum, maximum and smallest gap, and the type 2 quantiles, without
  `unique()`, `sort()` or `quantile()`. Other values keep those calls, and
  the results are unchanged. On a 42,944-row, 1,209-column DHS birth
  history file it falls from 2.5 to 2.2 seconds, and on a 16,787-row,
  5,360-column DHS file from 5.1 to 4.7 seconds.

* `codebook()` copies a numeric variable's observed values out of compact
  storage once, so its statistics no longer decode every value on each
  pass. It groups a labelled variable's values once for both the value and
  label columns of its tabulation, checks a string variable's blanks and
  width on its distinct strings, and builds its example rows without a
  data frame per variable. On 1,000,000 rows of 38 synthetic variables it
  falls from 5.2 to 3.5 seconds, on 1,007,220 rows of 100 DHS variables
  from 6.7 to 5.9 seconds, and on a 16,787-row, 5,360-column DHS file from
  8.3 to 6.7 seconds.

* `codebook()` counts each numeric variable's missing codes in compiled
  code, without building a code for every value. For a Stata numeric
  variable it subsets the column's bare values and decodes the observed
  ones once, rather than slicing the column through vctrs and decoding the
  slice in every summary, and it reads a dibble's columns by position. On
  a 16,787-row, 5,360-column DHS file, `codebook(compact = TRUE)` falls
  from 1.5 to 1.2 seconds and `codebook()` from 2.6 to 2.2 seconds.

* `codebook()` collects its problem rows as columns, where it built a data
  frame for each one, and counts each numeric variable's missing codes in
  one pass. It checks for duplicate observations a block of columns at a
  time and drops each row from the comparison once no other row matches
  it, so a table with an identifier column is done after that column.
  Comparing Stata numerics through vctrs decodes compact storage once
  rather than twice. On a 16,787-row, 5,360-column DHS file,
  `codebook(compact = TRUE)` falls from 4.1 to 2.0 seconds and
  `codebook()` from 5.3 to 3.2 seconds.

* `codebook()` finds each numeric variable's distinct values once and
  shares them, and its observed values, with the problem checks. It counts
  NaNs in a Stata numeric variable from its plain values, without building
  a computed vector through vctrs. On a 16,787-row, 5,360-column DHS file
  it falls from 9.9 to 7.9 seconds, and the compact report from 8.8 to
  7.2 seconds.

* `codebook()` computes each variable's missing mask and distinct-value
  count once, counts missing codes and categories without formatting every
  value or calling `table()`, and builds its result tables once. On a
  16,787-row, 5,360-column DHS file it falls from 36 to 13 seconds, and
  the compact report from 32 to 10 seconds.

* `labelbook()` collects each table's summary, mappings, assignment and
  diagnostics as field vectors and builds each result table once, rather
  than one data frame per row. On a 5,360-column DHS file with 4,831
  value-label tables it falls from 4 to 1.1 seconds. A value-label set
  with no mappings is now reported as a table with no mappings rather than
  failing.

* `labelbook()` checks the label text of every table in one pass when all
  strings are valid in a UTF-8 locale, reads each table's codes once for
  its signature and its duplicate check, and reads a dibble's columns by
  position. On the same DHS file it falls from 0.9 to 0.6 seconds.

* `read_dta()` and `read_arrow()` use direct object-identity checks while
  constructing dibbles, reducing setup work for wide tables. Scalar access
  to retained compact Arrow numerics reuses the current immutable chunk,
  reducing repeated native lookups during traversal.

* Validated native paths speed up supported `repl()`/`replace_values()`,
  `gen()`, dibble `:=`, and `mutate()` expressions. Public dependency changes
  retain ordinary evaluation. Bracket fallback preserves an already evaluated
  right-hand side, and generated siblings have independent metadata. These
  paths are limited to their qualified input and runtime profiles; they do
  not imply universal parity with data.table or superiority to dplyr.

* Canonical numeric construction, scalar addition and subtraction, storage
  checks, grouped double assembly, and expression-mask setup use native paths
  when their input and execution profiles are supported. Other profiles keep
  the existing R paths. Owned double buffers cache finite-value checks and
  invalidate that information when their values can change.
* Retained numeric captures now clone their immutable owner before allocating
  R objects and release it correctly if construction is interrupted. Numeric
  and metadata views retain their entry backing and selected columns across
  allocation callbacks. Capture detects a table that grows beyond its saved
  size buffer.
* Whole-column double replacement skips general decoding for finite values,
  while preserving missing tags, range errors and interrupt checks. Double
  generation copies ordinary and package-owned contiguous input in blocks and
  falls back to the existing decoder for exceptional values. Unknown ALTREP
  readers retain the ordinary path. Single-column compact gathers run without
  starting a worker thread.
* New `set_dta_values(data, variable, value, rows = NULL, create = FALSE)`
  is the loop-friendly assigner, `data.table::set()` for a dibble: the
  column as a name or position in an ordinary R value, `rows` and
  `value` as ordinary R values, nothing evaluated against the data, and a
  native fast path for common numeric scalar writes. The target keeps its
  declared storage and a value it cannot
  hold is an error, as `repl(promote = FALSE)` makes it. A missing
  column is an error unless `create = TRUE`. See ADR 0043.
* Numeric scalar replacement shares a native fast path across
  `set_dta_values()`, `repl()`, and dibble `:=`. Single-row and whole-column
  scalar writes use stack staging without native scratch heap allocation.
  `gen()` and `:=` creation share native scalar generation. General expressions,
  callbacks, grouping and promotion retain their existing policies. On the
  recorded 100,000-row fixture, single-row `set_dta_values()` fell from
  14.0 to 1.8 microseconds. See the
  [cell-assignment results](https://github.com/jbearak/dta-parser/blob/main/benchmarks/r-cell-assignment/results-2026-09-20-shared-mutation.md)
  for the API matrix, eligibility and separate native allocation measurements.
* `gen()` gains `before` and `after`, Stata's `generate ..., before(varname)`
  and `after(varname)`: the new column is inserted beside an existing column
  instead of appended, with the same column-name spellings `egen()` accepts.
  A call that names both, or names a column that does not exist, changes
  nothing.
* `tab()` builds the categories of an unlabelled numeric variable from its
  distinct values, formatting each distinct value once rather than every
  observation. On 1,000,000 rows, a one-way table falls from 0.27 to 0.08
  seconds and a two-way table from 0.47 to 0.08 seconds.
* `tab()` prints as Stata prints `tabulate`: a one-way table with
  frequency, percent, cumulative percent, and a total; a two-way table
  with row and column totals. New arguments carry `tabulate`'s options:
  `sort = TRUE` for `sort`, `percent = c("row", "column", "cell")` for
  `row`, `column`, and `cell`, `expected = TRUE` for `expected`, and
  `freq = FALSE` for `nofreq`. The result is a `table` of frequencies
  with class `dta_tab`; `as.table()` gives the plain table,
  `as.data.frame()` adds the percentages and expected frequencies as
  columns, and the printed lines are checked against Stata 19 output in
  the test suite. The [parity matrix](https://github.com/jbearak/dta-parser/blob/main/docs/r-tab-stata-parity.md)
  lists every `tabulate` form and option and how far each is matched.
* Breaking: `tab()` treats the empty string as Stata's string missing,
  so `""` and `NA_character_` are one category, excluded by default and
  shown as a blank level with `missing = TRUE`. Code that compared a
  `tab()` result with `table()` through `expect_identical()` now
  compares `as.table(tab(...))`.
* New `val_label(x, v)` and `val_code(x, label)` look up the label text of
  a code and the code of a label text. Both are vectorised: `val_label()`
  returns a character vector with `NA` where a code has no label, and
  `val_code()` a Stata numeric with `.` where no text matches. A tagged
  missing matches by its tag, so `val_label(x, .a)` finds its label. Each
  takes a labelled vector, a `val_labels()` table, or a data frame and
  column, as `val_label(data, status, 1)`. `val_label()` shares its name
  and `v` argument with `labelled::val_label()`, which returns `NULL` for
  an unlabelled code where dtatools returns `NA`.
* Breaking: `val_labels()` returns a value-label table as a named Stata
  numeric, a `dta_double()` or a `dta_long()` for integer codes, rather
  than a bare named vector. The codes are Stata
  values, so a tagged missing prints as `.a` instead of `NA` and
  `names(labels)[labels == .a]` finds its label, where the bare double
  compared `NA == NA`. The `labels` attribute on the vector is unchanged,
  so files and `haven` see what they always did. Code that compared the
  result with `identical()` against a bare `c(One = 1)` should wrap the
  expected value in `dta_double()`, or read the bare named vector from
  `attr(x, "labels")`. Setting a table back with `val_labels<-` or
  `set_val_labels()` stores the codes as they were, including a named
  empty table, so a read-and-set round trip changes nothing.
* Stata numeric vectors format and print missing values as Stata spells
  them: `.` for system missing and `.a` through `.z` for a tagged
  missing, in a printed vector, a dibble or tibble column, a data frame,
  and a value-label table. A printed vector that carries value labels
  lists them under the values. See ADR 0040.
* Breaking: `gen()` and a new column through `:=` now copy a value's
  values and typing only, as Stata's `generate` does. The new column keeps
  its storage, string storage, and date or datetime class, and drops the
  variable label, value labels, display format, notes, and characteristics
  of whatever vector produced it, whether a bare column reference,
  `gen(data, y = x)`, or a `haven_labelled` value. Author labels on the new
  variable with `set_var_label()` and `set_val_labels()`. `dplyr::mutate()`,
  the replacement operators, `repl()`, `:=` on an existing column, and
  `egen()`'s own labels are unchanged. Previously the metadata came along
  whenever the expression happened to return the column object itself and
  was dropped by any arithmetic. See ADR 0039.
* Three registered native entry points that nothing called are removed:
  `C_dtatools_arrow_datasig`, `C_dtatools_patch_data_column` and
  `C_dtatools_replace_table_columns`. ADR 0038 records why the rest of the
  native surface stays as narrow entry points.
* `save_dta()`, `save_arrow()` and `datasig()` now classify columns with one
  shared ladder, so the two writers accept the same tables and a table
  `datasig()` signs is one `save_dta()` saves unless it holds a `difftime`
  or `raw` column. `save_arrow()` and `datasig()` now export a
  `stata.storage` declaration on an R integer or logical, and a
  `dta_numeric` column without one, as `save_dta()` already did; both
  writers now name a malformed `stata.storage` declaration instead of
  reporting an unsupported class; and neither exports a generic `vctrs_vctr`
  or a labelled date. Existing signatures are unchanged. See ADR 0037.
* `egen()` now evaluates its calculation on private column views, as `gen()`
  and `repl()` do, so an expression that retains a column keeps a copy rather
  than an alias of the dataset. The reference bookkeeping a dibble carries
  now records only its base classes and owner; the unread column and row
  counts are gone.
* Breaking: mutation by reference now requires a dibble. `gen()`, `egen()`,
  `repl()`, `replace_values()`, dibble `:=`, `keep_vars()`, `drop_vars()`,
  `rename_vars()`, `order_vars()`, `reorder_dta_rows()`, the table forms of
  the label, format, metadata, note and characteristic setters, and
  `reserve_columns()`, `copy_data()`, `column_capacity()` and
  `can_add_columns()` reject a base data frame, tibble or data.table with an
  error naming the recovery, `data <- as_dibble(data)`. Data.table users who
  want by-reference mutation without Stata typing use data.table's own
  operators. Plain containers no longer acquire the `dtatools_ref_data` class,
  and legacy overlay reference state is no longer read. `is_dibble()` now
  tests the `dibble` class alone, so serialized objects from before that
  class existed are ordinary tibbles until `as_dibble()` rebuilds them.
  Copying operations such as `slice_dta_rows()` and `dta_merge()`, the
  readers and the writers accept every container as before; `copy_data()`
  is the exception, because it copies a dibble's reference state. The data.table-specific mutation paths (key and index maintenance
  after a write, self-reference repair, `setalloccol()` preparation) are
  removed with the behaviour they supported. See ADR 0036.
* Reading a dibble column with `$` or `[[` no longer makes the next
  by-reference write to that column copy its payload. The accessors handed
  the column back inside a temporary list, which marked its handle shared;
  a `repl()` after `data$x` therefore paid a full copy of a compact column.
* A sparse `repl()` into a dictionary-backed Stata string column no longer
  decodes and copies the whole column to build the empty cast prototype.
* Reader optimizations are now enabled by default. `read_dta()` reuses prepared
  decode plans and selected-file handles, batches all numeric storage widths,
  and overlaps eligible parallel reads through four bounded input buffers.
  `read_arrow()` retains native compact numeric buffers without copying them
  into R byte vectors. The private reader experiment switches are removed;
  existing thread, projection, eager-output and verification options still apply.
* Both readers reuse repeated column attributes within a read and return native
  tibbles directly. Arrow scans compact numeric missing values with narrower
  counters, preserving validation, missing codes, and interrupt checks.
* Reader tibble output now returns only selected file columns, matching dibble
  and data.table output. The global `tibble::rownames` configuration no longer
  adds a row-name column; add one explicitly after reading if needed.
* `save_arrow()` copies ordinary R character columns directly into owned Arrow
  buffers, reducing intermediate allocations. Foreign ALTREP character columns
  retain their existing handling.
* `save_dta()` avoids double conversion for eligible ordinary integer columns.
  R missing values and integers in Stata's reserved range retain their existing
  conversion and warning behavior.
* `read_dta()` and `read_arrow()` avoid loading source-adapter dependencies
  for ordinary local datasets. This removes most first-read overhead on
  small DTA files and reduces repeated-read overhead. Compressed files,
  URLs, raw inputs, connections, and caller-supplied source objects retain
  their existing handling.
* `read_dta(threads = 0)` now limits automatic workers according to selected
  decode work per input block and the requested row count for compact output.
  Narrow projections can use fewer workers without changing explicit thread
  limits or the `dtatools.threads` option. Eager output and strL retain their
  existing automatic policy.
* Single-thread `read_dta()` reads now use compact-byte batches with bounded
  interruption checks. Byte-heavy inputs benefit without requiring tiling or
  parallel workers. Both changes apply without experimental switches.

# dtatools 0.8.0.9000

* `read_dta()` and `read_arrow()` construct dibbles directly from the native
  reader's fresh columns, avoiding repeated table validation and column
  capture. String declarations and ordinary Arrow columns still follow the
  general dibble typing rules.

* New columns added by `gen()`, `egen()` and dibble `:=` automatically reserve
  space when needed. Growth warns, returns an isolated table and rebinds safe
  caller targets; functions must return that table for caller assignment.
  Existing aliases keep the old table after growth. Set
  `options(dtatools.auto_grow = FALSE)` to retain strict early failure.
* The default spare column capacity is now 1,024, configurable with
  `dtatools.alloccol`. Nongrowth structural helpers keep their existing
  preparation requirements.

* The Raven sidecar `inst/raven/nse.toml` now declares the captured
  arguments of egen, the dta_* summary and group helpers, set_var_format,
  set_var_formats, set_var_labels, set_val_labels, var_label, val_labels,
  order_vars and rename_vars, and carries a `[subset]` table naming the
  dibble constructors and converters so Raven treats `[` with `:=` on a
  dibble as data-masking. Callers no longer see undefined-variable
  warnings for bare column names passed to these functions.

# dtatools 0.8.0

* Dplyr is optional. Package-native operations and recoding work independently;
  installing dplyr retains its generic integration and supported foreign recode
  methods. Optional methods register across either package load order and
  unload/reload.
* Grouped and rowwise dibbles retain their restoration, replacement and display
  behavior without dplyr. Existing custom grouping methods remain in control.
* Direct dependency minimums are rlang 1.2.0, vctrs 0.7.3, tibble 3.3.1,
  pillar 1.9.0 and tidyselect 1.2.0. R 4.6.0 remains the supported minimum.
* CI and release checks add isolated native installations with recorded
  dependency libraries, explicit optional-test policies and subprocess checks.

# dtatools 0.7.1.9000

* Dibble filter, filter_out, arrange, distinct and slice helpers now plan rows
  through the shared expression and gathering modules. Filter and slice keep
  temporary bindings across expressions within each group; computed distinct
  keys retain sequential Stata typing. Explicit non-C arrange locales use stringi.
* Dibble mutate, transmute and grouping now use the package-owned expression
  and grouping modules, retaining sequential Stata typing and later-write
  isolation. The dplyr minimum is 1.2.1 on the supported R 4.6.0 floor.
* Wide dibble mutations reduce expression setup overhead while retaining
  column isolation and captured values.
* Unnamed across now follows dplyr's column-first expansion and evaluates a
  function factory once overall. The prior typing wrapper instead ran by group
  and repeated factory side effects. Named, aliased and unpacked calls keep
  their runtime helper behavior. Earlier within-call captures now resolve their
  original group and column generation; deferred reads after the call retain
  the obsolete-data-mask error.
