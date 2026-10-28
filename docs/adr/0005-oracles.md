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
