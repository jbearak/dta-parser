# Draft: haven NEWS could list three Stata fixes from the ReadStat update

Not filed, and optional. For <https://github.com/tidyverse/haven/issues>.

All three haven bugs we found are already fixed in ReadStat's `dev`
branch (69d8f91 and 725bb90, September 2026), which haven's `main`
vendors since "Update to ReadStat dev (0dc2aee)" (#851). haven built
from `main` at 66a332a no longer shows any of them. So there is nothing
to report to ReadStat or to haven as a bug. The one gap is that haven's
NEWS for the development version does not mention them, and each
changes what existing code gets back. No existing issue was found for any of
the three (searching haven's tracker for "trailing whitespace",
"trailing spaces", "trim", "strl" and "value labels 108", and
ReadStat's for "trailing", "strL", "119", "108" and "value labels").

---

**Title:** NEWS: mention the Stata reader and writer fixes that came
with ReadStat dev

Thank you for haven, and for updating it to ReadStat dev. Comparing
haven 2.5.5 with `main` (66a332a), three Stata changes from that update
are not in NEWS. Each changes what users get back, so they may be
worth a line each under "Updated to ReadStat dev (0dc2aee)":

1. **`read_dta()` keeps trailing blanks in `str#` values.** 2.5.5
   dropped them. pandas and readstata13 keep them.
2. **Version 15 (format 119) files use the 119 strL reference layout**
   (3 bytes for the variable, 5 for the observation, rather than 118's
   2 and 6). `write_dta(version = 15)` in 2.5.5 wrote 118's layout, so
   pandas 3.1.0 fails on those files and readstata13 0.11.0 reads their
   strLs as `NA`. `read_dta()` in 2.5.5 also read other writers' 119
   files with the 118 layout, giving `""` for every strL. pandas and
   readstata13 both use the 3 + 5 split for 119
   ([pandas/io/stata.py#L1624](https://github.com/pandas-dev/pandas/blob/092d58891fe0effeb8adf0635c52d3c6a7270670/pandas/io/stata.py#L1624)).
3. **Value labels in format 104, 105 and 108 files are read.** haven
   can't write these releases, so the example uses pandas' test files
   `stata4_104.dta`, `stata4_105.dta` and `stata4_108.dta` (BSD-3).
   On those, 2.5.5 returns one stray label (`"\003"` for 0) for 104,
   none for 108, and fails on 105 with "Unable to allocate memory".
   `main` returns the ten labels "one" to "ten", as pandas does.
   ReadStat's commit 69d8f91 describes the layouts.

```r
library(haven)

# 1. Trailing blanks in str# values
path <- tempfile(fileext = ".dta")
write_dta(data.frame(x = c("a  ", " b ")), path)
nchar(read_dta(path)$x)
#> haven 2.5.5:  [1] 1 2
#> haven main:   [1] 3 3

# 2. strL references in version 15 (format 119) files
path <- tempfile(fileext = ".dta")
write_dta(data.frame(x = c(strrep("a", 3000), strrep("b", 3000))), path, version = 15)
bytes <- readBin(path, "raw", file.size(path))
start <- grepRaw("<data>", bytes) + 6
bytes[start:(start + 15)]
#> haven 2.5.5:  01 00 01 00 00 00 00 00 01 00 02 00 00 00 00 00   (2 + 6)
#> haven main:   01 00 00 01 00 00 00 00 01 00 00 02 00 00 00 00   (3 + 5)

# 3. Value labels in format 104, 105 and 108 files, using pandas' test files
base <- paste0("https://raw.githubusercontent.com/pandas-dev/pandas/",
               "092d58891fe0effeb8adf0635c52d3c6a7270670/pandas/tests/io/data/stata/")
for (release in c(104, 105, 108)) {
  path <- tempfile(fileext = ".dta")
  download.file(paste0(base, "stata4_", release, ".dta"), path, mode = "wb", quiet = TRUE)
  labels <- tryCatch(attr(read_dta(path)$fulllab, "labels"), error = conditionMessage)
  cat(release, ":", if (is.character(labels)) labels else encodeString(names(labels)), "\n")
}
#> haven 2.5.5:  104 : \003
#>               105 : Failed to parse ...: Unable to allocate memory.
#>               108 :
#> haven main:   104 : one two three four five six seven eight nine ten
#>               105 : one two three four five six seven eight nine ten
#>               108 : one two three four five six seven eight nine ten
```

R 4.6.1, macOS 26.7.1 (arm64).
