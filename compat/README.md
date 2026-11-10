# Compatibility fixtures and oracles

`fixtures/` holds small `.dta` files made without Stata. `expected/` holds
what haven, readstata13 and pandas read from each one, as JSON. The Rust
tests (`crates/dta/tests/compat.rs`), the npm tests and the R tests compare
dta-parser against them.

To regenerate, from the repository root:

    Rscript compat/make_fixtures.R      # haven: 113, 114, 115, 117, 118, 119
    python3 compat/make_fixtures.py     # pandas: 114, 117, 118, 119, both byte orders
    sh compat/make_legacy_fixtures.sh   # ReadStat's writer: 104, 105, 108, 110, 111
    Rscript compat/expected.R           # haven and readstata13
    python3 compat/expected.py          # pandas

`fixtures/README.md` says where each file comes from.

`fixed_width/` holds a synthetic fixed-width data file and its SAS setup
file, in the style CDC publishes for the NSFG (plan 0009), and
`expected/fixed_width.json` what asciiSetupReader reads from them, and
for `recodes = "tagged"` its codes made into haven tagged NAs:

    Rscript compat/fixed_width/make_fixed_width.R
    Rscript compat/fixed_width/expected_fixed_width.R   # needs asciiSetupReader and haven

## Which reader is the oracle, per release

pandas and readstata13 have their own implementations. haven wraps
ReadStat, so it confirms nothing about files ReadStat wrote. Every release
has at least one independent oracle for values and for value labels:

| Release | Fixtures (writer) | Values | Value labels |
|---|---|---|---|
| 104 | ReadStat; pandas' tests (big-endian) | pandas, readstata13 | pandas |
| 105 | ReadStat; pandas' tests (big-endian) | pandas, readstata13 | pandas |
| 108 | ReadStat; pandas' tests (big-endian) | pandas, readstata13, haven | pandas, readstata13 |
| 110, 111 | ReadStat; pandas' tests (big-endian) | pandas, readstata13, haven | pandas, readstata13, haven |
| 113 | haven; pandas' tests (big-endian) | pandas, readstata13, haven | pandas, readstata13, haven |
| 114, 117, 118 | haven; pandas (both byte orders) | pandas, readstata13, haven | pandas, readstata13, haven |
| 115 | haven | pandas, readstata13, haven | pandas, readstata13, haven |
| 119 | haven; pandas (both byte orders) | pandas, readstata13 (strLs); haven for its own files | pandas, readstata13, haven |

Where a reader differs, its value is skipped, with the reason, in the
test's `KNOWN` list (see `docs/adr/0005-oracles.md`):

- haven 2.5.5 fails on 105 value labels, reads 104 and 108 value labels as
  empty, drops trailing blanks, and splits 119 strL references as in 118;
- readstata13 does not read value labels before 108, returns pre-113
  missing values as the stored sentinel (`compat/expected.R` maps those
  to `.` by each variable's storage type), and reads an empty strL as
  `NA`;
- pandas decodes text before 118 as Latin-1, not Windows-1252.

None of these is an open bug in that project; see
[docs/other-readers.md](../docs/other-readers.md).

## Our writers, read back by other readers

`readback/` checks every writer we ship against every reader above.
dtaparser and dtatools (R) and the npm package each save the fixtures
again, and also `readback/strls.dta` and `readback/binary.dta`: several
strL variables over many rows, repeated texts, empty strLs, a binary
strL, `.a` to `.z`, value labels with a long text, and a long variable
label. `readback/make_inputs.py` gives the values of both; the files
were written on 2026-11-08 by the Python writer this repository had
then, and are kept as committed. haven, readstata13, pandas and
pyreadstat must then read each copy as they read its input, and the two
strL inputs as `make_inputs.py` describes them. Python runs here only
to call pandas and pyreadstat. CI's `readback` job runs it; locally,
with everything installed and built:

    sh compat/readback/run.sh /tmp/readback

`readback/check.py` lists, in `KNOWN`, each place a reader is no
oracle, with the reason: the input differences above, R's lack of
binary strings, and readers that take every strL for text.

Notes are compared where haven reports them. readstata13's
characteristics are recorded in `expected/` but not yet compared, and
sort order is read but not yet checked against any reader.
