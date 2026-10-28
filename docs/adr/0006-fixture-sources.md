# Fixtures are written by haven and pandas from data we make

Every fixture in `compat/fixtures` is written without Stata, by
`compat/make_fixtures.R` (haven: releases 113, 114, 115, 117, 118, 119) and
`compat/make_fixtures.py` (pandas: releases 114, 117, 118, 119, in both
byte orders), from data those scripts generate. Releases 104 to 111 and
big-endian files before 114, which neither writes, come later, from
ReadStat's writer or from pandas' own test files (BSD-3), with credit. The
fixtures are small and committed, so the tests need neither R nor Python.
The expected values are regenerated with `compat/expected.R` and
`compat/expected.py`.
