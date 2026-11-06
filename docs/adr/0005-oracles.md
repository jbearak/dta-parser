# Which open-source reader is the oracle when they disagree

Expected values come from haven, readstata13 and pandas (`compat/expected`).
pandas and readstata13 are independent of each other and of ReadStat.
haven wraps ReadStat. Where a reader is known to be wrong, its value is not
used. Each such case is listed in `crates/dta/tests/compat.rs` and in the R
tests:

- **haven 2.5.5 drops trailing blanks from strN values.** pandas,
  readstata13 and ReadStat's development branch keep them, and so do we.
  Stata stores them deliberately.
- **haven 2.5.5 reads strL references in 119 files with the 118 layout**
  (2 bytes for the variable, 6 for the observation, instead of 3 and 5). It
  reads 119 files from other writers wrongly, and it writes its own 119
  files that way. We read the 119 layout, as pandas and readstata13 do. When
  a reference is not found that way, we retry it with the 118 split, so
  haven's own 119 files read as haven reads them.
- **pandas decodes text before 118 as Latin-1** (see ADR 0004).
- **readstata13 reads an empty strL as `NA`** where the others read `""`.
  We read `""`.
- **Value labels before 108**: haven 2.5.5 fails on 105 and reads 104 as
  empty; readstata13 does not read them; pandas reads them, and is the
  oracle there. haven also reads 108's tables as empty.
- **readstata13 returns pre-113 missing values as the stored sentinel**
  (the type's largest value); `compat/expected.R` maps those to `.` by
  each variable's storage type.
- **pyreadstat** (used by the Python tests, read live rather than from
  `compat/expected`) wraps ReadStat like haven, so it reads haven's 119
  strL references with the 119 layout and finds no text.
- **pandas 2** (which the Python tests meet on Python 3.10) reads the one
  missing value of int and long before 113 as `.z`, reads 105 and 108
  value labels as empty, and cannot read 104, 110 or big-endian 118 and
  119 files. pandas 3 has none of these.

**Fixed-width files read through a SAS setup file** (plan 0009) have
their own oracle: asciiSetupReader (R, MIT), which reads such files and
applies their missing-value recodes. `compat/fixed_width/` holds a
synthetic setup and data file, and `compat/expected/fixed_width.json`
what asciiSetupReader reads from them. It cannot read fixed-length
records without line breaks, two record types in one file, or a setup
split over several files, and it turns variable labels into column
names; `scripts/check-nsfg.R`, which compares the NSFG female
respondent and pregnancy files of 1973 to 2017-2019 themselves, gives
it equivalent input for the first three (2002's three setup files
joined into one) and compares labels by their letters and digits. It
reads the `PROC FORMAT` step and `FORMAT` statement that the setups of
2006-2010 on wrap in block comments. Where the rules of plan 0009 and
ADR 0030 differ from it, the script compares by those rules: it drops
value labels whose keys are ranges or `.`, and those of `$` formats,
which Stata cannot hold. Two of its limits are allowed only where the
setup holds our text as written: a double-quoted variable label with a
quote inside, which it ends at that quote as SAS does, is compared up
to there, and a value label with runs of spaces, which it makes one
space, is compared that way. Its other limits there (a label written
twice, a `VALUE` with no space after a label, `LABEL` without `=`) are
listed in that script, each checked against the setup text. For `recodes = "tagged"`, the expected values
are asciiSetupReader's codes read without the recodes, made into haven
tagged NAs in the order its `parse_setup()` lists the recodes; the
converted file is also read with haven, readstata13, pandas and
pyreadstat.

`compat/README.md` lists, per release, which readers are the oracle.
