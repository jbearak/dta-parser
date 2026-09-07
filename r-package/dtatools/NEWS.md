# Development version

* Dibble mutate, transmute and grouping now use the package-owned expression
  and grouping modules, retaining sequential Stata typing and later-write
  isolation. The dplyr minimum is 1.2.1 on the supported R 4.6.0 floor.
* Unnamed across now follows dplyr's column-first expansion and evaluates a
  function factory once overall. The prior typing wrapper instead ran by group
  and repeated factory side effects. Named, aliased and unpacked calls keep
  their runtime helper behavior. Earlier within-call captures now resolve their
  original group and column generation; deferred reads after the call retain
  the obsolete-data-mask error.
