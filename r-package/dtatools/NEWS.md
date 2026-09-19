# dtatools (development version)

* `gen()` gains `before` and `after`, Stata's `generate ..., before(varname)`
  and `after(varname)`: the new column is inserted beside an existing column
  instead of appended, with the same column-name spellings `egen()` accepts.
  A call that names both, or names a column that does not exist, changes
  nothing.
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
