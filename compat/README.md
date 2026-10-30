# Compatibility fixtures and oracles

`fixtures/` holds small `.dta` files made without Stata. `expected/` holds
what haven, readstata13 and pandas read from each one, as JSON. The Rust
tests (`crates/dta/tests/compat.rs`), the npm tests and the R tests compare
dta-parser against them. The Python tests (`python/tests/test_compat.py`)
read each fixture with pandas and pyreadstat as they run and compare
against those.

To regenerate, from the repository root:

    Rscript compat/make_fixtures.R      # haven: 113, 114, 115, 117, 118, 119
    python3 compat/make_fixtures.py     # pandas: 114, 117, 118, 119, both byte orders
    sh compat/make_legacy_fixtures.sh   # ReadStat's writer: 104, 105, 108, 110, 111
    Rscript compat/expected.R           # haven and readstata13
    python3 compat/expected.py          # pandas

`fixtures/README.md` says where each file comes from.

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

## Where readers differ from us

Where a reader's value is not a usable oracle, the test skips it, with
the reason, in its `KNOWN` list (see `docs/adr/0005-oracles.md`). None
of these differences is an open bug in another project. Each was either
fixed upstream already, or is a choice the other library is entitled
to make:

| difference | status |
|---|---|
| haven 2.5.5 fails on 105 value labels and reads 104 and 108 value labels wrongly | fixed upstream: the bug was in the ReadStat code haven bundles, fixed on ReadStat `dev` (69d8f91, September 2026) and in haven `main` since it vendored that (tidyverse/haven#851); not yet on CRAN |
| haven 2.5.5 drops trailing blanks from `str#` values | fixed upstream the same way (ReadStat 725bb90) |
| haven 2.5.5 writes and reads 119 strL references in the 118 layout | fixed upstream the same way (ReadStat 69d8f91) |
| readstata13 does not read value labels before release 108 | a deliberate limit: it reads labels only for releases after 105 |
| readstata13 returns pre-113 missing values as the stored number with `missing.type = TRUE` | documented: it warns that the option applies only to newer files; the default gives `NA` (`compat/expected.R` maps the stored numbers to `.`) |
| readstata13 reads an empty strL as `NA` (an empty `str#` as `""`) | defensible: Stata has no separate missing string and treats `""` as missing |
| pandas decodes text before release 118 as Latin-1, not Windows-1252 | defensible: those files do not record their encoding, so every reader guesses; we and haven guess Windows-1252 |

### Before reporting a difference to another project

A different answer from another reader is not, by itself, a bug in that
reader. In October 2026 we drafted reports for the rows above that
looked like bugs: three were already fixed upstream and two were
defensible choices, and one went out as a bug report before that was
checked (it is now a question, sjewo/readstata13#96). So, before
calling a difference a bug:

1. Reproduce it on the project's current development branch, not only
   the release we pin; fixes often wait for a release.
2. Ask whether the format settles the question. If it does not (no
   recorded encoding, no missing string), the other library's choice is
   a convention: record it here, don't report it.
3. Search the project's issues, open and closed.
4. Never file an issue, pull request or comment in another project
   without the user's approval of that specific report, and phrase a
   difference of convention as a question.

Notes are compared where haven reports them. readstata13's
characteristics are recorded in `expected/` but not yet compared, and
sort order is read but not yet checked against any reader.
