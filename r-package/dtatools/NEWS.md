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
