# Draft: readstata13 reads an empty strL as `NA`

Not filed. For <https://github.com/sjewo/readstata13/issues>, as a new
issue (no existing report found by searching the tracker for "strl",
"empty string" and "strL NA").

---

**Title:** `read.dta13()` reads an empty strL as `NA`

Thank you for readstata13. We use it as one of the reference readers in
our tests for a `.dta` reader, and found one case where it reads a value
differently from other readers.

A strL holding the empty string is stored in the data as the reference
(v, o) = (0, 0), with no GSO record. `read.dta13()` returns `NA` for it
rather than `""`. readstata13's own writer produces such a file, so it
does not read back its own empty strings:

```r
library(readstata13)

path <- tempfile(fileext = ".dta")
df <- data.frame(x = c(strrep("a", 3000), "", "b"))
save.dta13(df, path, version = 118)

# The empty string is written as the strL reference (0, 0) ...
read.dta13(path, replace.strl = FALSE)$x
#> [1] "1_1" "0_0" "1_3"

# ... which reads back as NA.
nchar(read.dta13(path)$x)
#> [1] 3000   NA    1
```

The same happens with `version = 117` and `version = 119`.

**Expected:** `""` for the second row.

- `read.dta13()` already means to map the (0, 0) reference to `""`: it
  adds an entry named `"00000000000000000000"` before replacing the
  references
  ([R/read.R#L353-L354](https://github.com/sjewo/readstata13/blob/5c02468ef1213c86b7a86260ec6f83f7e40d7d60/R/read.R#L353-L354)).
  The references are built as `v_o`
  ([src/read_data.cpp#L167](https://github.com/sjewo/readstata13/blob/5c02468ef1213c86b7a86260ec6f83f7e40d7d60/src/read_data.cpp#L167)),
  so the empty reference is `"0_0"` and that lookup finds nothing.
- pandas writes `""` as (0, 0) and reads (0, 0) as `""`
  ([pandas/io/stata.py#L3294](https://github.com/pandas-dev/pandas/blob/092d58891fe0effeb8adf0635c52d3c6a7270670/pandas/io/stata.py#L3294),
  [#L1614](https://github.com/pandas-dev/pandas/blob/092d58891fe0effeb8adf0635c52d3c6a7270670/pandas/io/stata.py#L1614)).
  pandas 3.1.0 and pyreadstat 1.3.7 both read the second row of the
  file above as `""`.

**A possible fix:** name that entry `"0_0"` instead:

```r
names(strl) <- "0_0"
```

With that one change, the example above gives `3000 0 1` for releases
117, 118 and 119.

readstata13 0.11.0 (CRAN), R 4.6.1, macOS 26.7.1 (arm64). The code
quoted is the same on `main` at 5c02468.
