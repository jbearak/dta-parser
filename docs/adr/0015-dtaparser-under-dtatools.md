# dtaparser reads files; dtatools builds Stata's rules on top of it

dtatools gives R Stata's missing-value rules, which a test suite for a
Stata pipeline needs and an analyst does not. So the R reader is split.
`dtaparser` holds the Rust bridge, the packed string columns and the
reader and writer, and its `read_dta` returns plain R types: integers,
doubles, character, factors, `Date`, `POSIXct`, with every numeric
missing value `NA`. `dtatools` imports dtaparser and no longer builds
any Rust; it reads through dtaparser in a mode that gives today's
`dta_num` columns, and keeps its own comparison, arithmetic and set
code.

dtatools reaches dtaparser's C code through `R_RegisterCCallable` and
`R_GetCCallable`, R's supported way for one package to call another's C
functions. An integer ABI number, checked when dtatools loads, stops a
mismatched pair from running. The two packages live in this repository
and are released together.

The layering is not clean in one place: dtaparser's read has a mode that
builds dtatools' `dta_num` columns (tagged doubles, the class and its
attributes). Building them in dtatools would copy every numeric column
after the read, which ADR 0007 avoided on purpose.

## Considered options

- **A setting on `dtatools::read_dta`.** One function whose results
  follow Stata's rules or R's depending on an argument; the difference
  is easy to miss in a test, and an analyst still installs a package
  built around dibbles.
- **Two independent packages, each compiling the bridge.** No seam to
  version, but anyone using both compiles the Rust code twice, and every
  bridge change lands in two packages.
- **dtatools calling dtaparser's routines with `:::`.** Works, but R's
  checks flag it and it gives no version check.

## Consequences

- Installing dtatools no longer needs cargo, but dtaparser does, and
  dtaparser must be installed first; neither is on a registry.
- A change to a callable's signature must bump the ABI number.
- dtatools holds pointers into dtaparser's library. Reinstalling
  dtaparser in a session where dtatools is loaded leaves them stale;
  restart R after reinstalling.
