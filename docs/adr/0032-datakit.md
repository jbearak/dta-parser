# datakit holds what goes beyond the format: `:=` and `read_fixed_width`

Superseded in part by ADR 0039: `read_fixed_width` moves to datparser,
which datakit imports and wraps, and dtaparser no longer registers
`dtaparser_fixed_width`.

dtaparser grew from a `.dta` reader into a reader with `:=` (ADR 0027)
and a reader of fixed-width text through SAS setup files (ADR 0018).
Neither is about the `.dta` format, and a do-file translated to R needs
both, so they move to a new package, datakit. dtaparser keeps reading
and writing `.dta` files (ADR 0031) and how it represents them in R.

| package | exports |
|---|---|
| dtaparser | `read_dta`, `save_dta`; `na_tag`, `is_tagged_na`, `tagged_na`, `var_label`, `val_labels`, `val_label`, `with_labels` and the `dtaparser_labelled` class |
| datakit | `read_fixed_width`; `:=` and `colon_equals()` with its default, data frame and data.table methods |
| dtatools | as before; it re-exports dtaparser's `save_dta` and datakit's `:=`, and registers `colon_equals.dibble` |

The label and tagged-NA helpers and the labelled class stay in
dtaparser. They are how `read_dta` represents a file's codes, value
labels and missing codes, `save_dta` reads them back, and the class's
vctrs methods (`x == "Yes"`, `x[i] <- "No"`, `bind_rows()`) must live
with the class.

**Dependencies.** datakit imports dtaparser; dtatools imports both.
Nothing imports datakit but dtatools, so there is no cycle. datakit's
`:=` used five of dtaparser's internal functions for labelled columns;
it now goes through exported functions instead: `vctrs::vec_cast()`
for a label assigned as its code, `vctrs::vec_ptype2()` for the union
of two columns' labels, and `with_labels()` and `val_labels()`.

**Native code.** The Rust core and bridge stay in dtaparser only; the
fixed-width parser is part of the core (ADR 0018). dtaparser registers
the conversion as a C callable, `dtaparser_fixed_width`, and datakit's
small C file fetches it with `R_GetCCallable`, as dtatools does for
reading (ADR 0016). datakit builds no Rust and needs no cargo. The ABI
number goes from 1 to 2, since the callables changed: `dtaparser_write`
went (dtatools calls `save_dta`, ADR 0031) and `dtaparser_fixed_width`
came. datakit and dtatools both check it when they load.

**Versions.** Taking exports out of dtaparser breaks code written for
2.x, so dtaparser, datakit and dtatools are 3.0.0. They share one
version because one tag, `r-v<version>`, builds and publishes all three.

**Attach order.** A translated script attaches
`library(dtaparser); library(datakit)`, datakit after dplyr and tidyr,
so that its `:=` masks rlang's, which dplyr re-exports. The load-order
rule of ADR 0021 is unchanged, with datakit in place of dtaparser.

**Raven.** datakit ships `inst/raven/nse.toml`, a file for the Raven
language server that declares `:=` an operator of form `subset-assign`
whose `by` argument, like `i` and the value, is evaluated among the
columns. Raven reads entries only for names a package exports, so
dtatools, which re-exports `:=`, ships the same file. Neither declares
a `[subset]`: datakit's `[` is base R's and a dibble's is tibble's.
Raven versions without this support ignore the file. A test checks
that the file is installed and parses; CI does not run Raven.

## Considered options

- **Keep both in dtaparser.** An analyst who only reads and writes
  `.dta` files gets a data-manipulation operator and a SAS parser, and
  dtaparser's scope keeps growing with each do-file construct.
- **Move `read_fixed_width` with its own copy of the Rust bridge.** Two
  packages would compile Rust; ADR 0016 rejected that for dtatools.
- **dtaparser exports a low-level fixed-width converter for datakit to
  call.** No C in datakit, but dtaparser would still export a
  fixed-width function, only a harder one to use.
- **Move the labelled class too.** `read_dta` would then need datakit
  to return its columns, and the dependency would point both ways.
- **Stubs in dtaparser 3.0.0 that stop with "moved to datakit".** A
  stub named `read_fixed_width` or `colon_equals` in dtaparser would be
  masked by datakit's, or would mask it, so every script attaching both
  would print a masking note, and attaching them in the wrong order
  would break the call. The move is documented in the docs and here
  instead.

## Consequences

- Code that called `dtaparser::read_fixed_width()` or relied on
  dtaparser's `:=` must install datakit and call `datakit::` or attach
  it. The warning class `dtaparser_fixed_width_warning` is now
  `datakit_fixed_width_warning`.
- Installing dtatools installs datakit too.
- Reinstalling dtaparser in a session where datakit is loaded leaves
  datakit's pointer stale, as for dtatools; restart R.
- The r-packages workflow builds, tests and publishes three packages.
