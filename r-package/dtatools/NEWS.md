# dtatools (development version)

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
