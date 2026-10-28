# Fixture provenance

| Files | Written by | From |
|---|---|---|
| `haven_*.dta` | haven `write_dta` (`compat/make_fixtures.R`) | data made in that script |
| `pandas_*.dta` | pandas `to_stata` (`compat/make_fixtures.py`) | data made in that script |
| `readstat_*.dta` | ReadStat's writer, commit 1434a07 (`compat/make_legacy_fixtures.sh`, `compat/readstat/write_fixture.c`) | data made in that program |
| `pandastest_be_*.dta` | copied from pandas' test suite, `pandas/tests/io/data/stata/stata-compat-be-<release>.dta`, commit 2aaaec5 | pandas (BSD-3-Clause, Copyright (c) the pandas development team) |

The pandas files are big-endian files of releases 104 to 113, which none of
haven, pandas or ReadStat can write. They are used only as inputs; their
expected values come from the open-source readers, like every other
fixture's.
