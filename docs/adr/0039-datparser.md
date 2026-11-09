# `read_fixed_width` moves to datparser, which reads in memory

On 2026-11-09 the user asked for R's `read_fixed_width` to move into a
package of its own, datparser, so that someone who only reads
fixed-width files does not install dtaparser and datakit, with datakit
importing both. Under ADR 0018 that move alone would not have helped:
R's `read_fixed_width` wrote a temporary release 118 file through
dtaparser's C callable and read it back with `dtaparser::read_dta`, so
datparser would still have needed dtaparser. So datparser builds its
columns from the core's fixed-width reader directly, and for R this
replaces ADR 0018's temporary file. Python, Julia, and TypeScript still
convert through release 118.

**The core.** `crates/dta`'s fixed-width reader now stops at a
`FixedWidth`: the kept records and, per variable, its name, label,
value labels, storage type, and values, read on demand. A
`FixedWidthSetup` is the parsed setup, so a caller can learn the
variables' names before choosing which to read; `FixedWidth::read`
takes the columns wanted and reads and warns about only those.
`fixed_width_to_dta` builds its `Dataset` from a `FixedWidth`, with its
output unchanged.

**datparser.** It compiles its own copy of `crates/dta`, as dtaparser
does, kept in `src/rust/dta` by `configure` and checked against
`crates/dta` in CI. The core needs no crate from crates.io, so the
package builds offline with nothing vendored. The Rust bridge never
calls R: C makes every R vector and asks Rust to fill it, and Rust
fills the numeric columns on several threads (`threads::resolve`, as
the readers do). The table Rust holds lives in an external pointer
whose finalizer frees it, so an R error cannot leak it. datparser
imports rlang, tibble, tidyselect, stats, and utils, and nothing of
dta-parser's.

**What a column is.** The values and types are those `read_dta` gave
for the converted file: integers when every value is a whole number
within long's range and the rows read hold no `.a` to `.z`, doubles
otherwise, with the letters as haven's tagged NAs. A column with value
labels is a plain integer or double vector with attributes `label` and
`labels` (in code order). datakit's `read_fixed_width` calls
datparser's and makes such columns a `dtaparser_labelled`, as
`read_dta` does, without `with_labels()`' checks, since setups label
codes with empty text. Variable labels are no longer cut to 320 bytes:
that was the release 118 field's size.

**Checked.** On all 21 NSFG female respondent and pregnancy files from
1973 to 2017-2019, each read with `recodes` "setup", "tagged", and
"none", with `factors = TRUE` in two of them, and with a selection of
columns, `skip`, and `n_max`, datakit's new `read_fixed_width` gives
the same column names, row counts, warnings, values (1.3 billion), and
attributes as the old one, and datparser's the same apart from the
class. On the largest, 1995's female respondents (10,847 rows, 5,754
columns), it takes 1.27 s against 1.60 s, with less memory. datparser's
tests also check the synthetic file of `compat/fixed_width` against
asciiSetupReader and haven (ADR 0005).

**Versions and ABI.** dtaparser no longer registers
`dtaparser_fixed_width`, and datakit no longer fetches it. The ABI
number stays 3: no 3.2.0 package fetches the callable, and a datakit
3.1.0 that does fails to link, which its `.onLoad` reports as a
mismatched dtaparser. The four R packages share version 3.2.0 and the
`r-v<version>` tag.

## Considered options

- **datparser over dtaparser's callable.** The smallest move, but
  datparser would import dtaparser and so install its Rust build,
  Parquet included: what the user wanted to avoid.
- **Give labelled columns dtaparser's class when dtaparser is loaded.**
  One function for both packages, but what a call returns would depend
  on what else happened to be loaded; the test suite saw that at once.
- **Write the temporary file from datparser's own Rust and read it with
  its own reader.** It keeps ADR 0018's single path, but puts a `.dta`
  reader in a package that reads no `.dta` files.
- **Materialise every column in Rust, then copy it to R.** Simpler, but
  holds each value twice; filling R's vectors in place does not.

## Consequences

- `library(datparser)` loads no other dta-parser package. Installing
  datakit or dtatools installs datparser.
- datparser's warnings have class `datparser_fixed_width_warning` and
  also `datakit_fixed_width_warning`, the class datakit's had;
  `factors = TRUE` losing `.a` to `.z` warns with
  `datparser_extended_missing` and also `dtaparser_extended_missing`,
  as `read_dta` does.
- `col_select` now chooses which columns are read: unselected columns
  are not parsed and not warned about.
- Parsing the setup is now most of a read: 0.55 s of 1.27 s for 1995's
  1.5 MB setup. Making it faster would help every language.
