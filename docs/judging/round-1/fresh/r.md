# dtatools (R) docs check

Source used: `docs.md` only. Scripts: `t1_2.R`, `t3_5.R`, `t6_10.R` in this directory. Run with `Rscript`, library at `scratch/lib` first in `.libPaths()`.

## 1. Install and load: succeeded
```sh
R CMD INSTALL --library=$S/lib <checkout>/r/dtatools     # docs: R CMD INSTALL dta-parser/r/dtatools
```
```r
library(dtatools); packageVersion("dtatools")   # '1.0.0'
```
Built with cargo in a few seconds, loaded fine. Docs gap: the install line has no `--library`/`R_LIBS_USER` hint for a non-default library (obvious to R users, so minor). The `OMP: Warning #179` lines are machine noise.

## 2. Write and read back a mixed table: succeeded
```r
df <- dibble(i = 1:4, f = c(1.5,2.5,3.5,4.5), s = c("a","bb","ccc","dddd"),
             d = as.Date(c("2024-01-01","2024-02-01","2024-03-01","2024-04-01")))
save_dta(df, "t2.dta"); back <- read_dta("t2.dta")
```
Saw: class `dibble/tbl_df/tbl/data.frame`. Column types: `i` dta_num (storage long, `%12.0g`), `f` dta_num (double, `%10.0g`), `s` character (`%-4s`), `d` dta_num (long, `%td`, prints as 23376...). `typeof` is double for every numeric column.
Docs: fine and accurate ("R keeps every date as a number"). Note the docs never state the default display formats (`%12.0g` for long, `%8.0g` for byte, `%10.0g` for double); only `%10.0g` appears in a comment.

## 3. Select columns in reverse order; unknown column: succeeded
```r
names(read_dta("t2.dta", col_select = c(d, i)))        # "d" "i"
names(read_dta("t2.dta", col_select = c("s", "f")))    # "s" "f"
read_dta("t2.dta", col_select = c(i, nope))            # error
```
Order is the order selected. The unknown name gives class `vctrs_error_subscript_oob`: "Can't select columns that don't exist. ✖ Column `nope` doesn't exist." Matches "A name the file does not have is an error naming it."

## 4. Rows 3 to 5; past the end: succeeded (one doc nit)
```r
read_dta("t2.dta", skip = 2, n_max = 3)     # 4-row file: 2 rows (ids 3, 4)
read_dta("t2.dta", skip = 10, n_max = 3)    # 0 rows, 4 columns with right types
```
Past the end: fewer rows, or an empty tibble with the columns kept, no error, no warning. Matches the docs. Nit: the docs' `skip = 2, n_max = 3` means rows 3 to 5, but that is not spelled out (skip is 0-based count, not a start index). A reader going from "rows 3 to 5" has to work out `skip = start - 1`.

## 5. Variable labels, data label, formats, storage types, without reading data: partly
```r
attr(df, "label"); attr(df$income, "label"); attr(df$income, "format"); attr(df$income, "storage")
z <- read_dta("survey.dta", n_max = 0)   # my workaround for "no data"
```
The attributes all work, and `n_max = 0` returns 0 rows with all attributes intact (data label "Household survey (example)", labels, formats, storage). But the docs give no R metadata-only function:
- README: "Reads only what you ask for: ... or the metadata alone" and the support table says "storage types, variable labels ... ✓" for R. performance.md: "**Metadata only** (`read_meta`, or opening a file in TypeScript)". `read_meta` is not exported in R (`exists("read_meta")` is FALSE; exports are the 15 listed in the API reference). releases.md says release is "not exposed" in R.
- `n_max = 0` is never mentioned as the way to get metadata alone; I guessed it. It works, but I did not confirm whether it avoids reading rows.
- Variable `storage` is NULL on character columns (docs say `storage` is "on a numeric column", so that is documented). The string width is only visible through `format` (`%-18s`).

## 6. Value label set; look up code; make a factor: succeeded
```r
t6 <- dibble(id = 1:4, sex = dta_num(c(1,2,2,1), storage="byte", labels=c(Female=1, Male=2)))
save_dta(t6, "t6.dta"); b <- read_dta("t6.dta")
attr(b$sex, "label_set")        # "sex"
val_labels(b$sex)               # Female 1, Male 2
val_label(b$sex, 2)             # "Male"
labels <- val_labels(b$sex)
factor(val_label(b$sex, b$sex), levels = names(labels)[order(labels)])   # Female Male Male Female
```
All as documented. `haven::as_factor(b$sex)` fails ("no applicable method for 'as_factor' applied to an object of class "dta_num""), which the docs imply by showing `factor(val_label(...))` instead; it is not stated outright that `as_factor` does not work. The docs' factor recipe is long for the most common thing one does with labels; no one-call helper exists.

## 7. Date as a date; conversion turned off: partly
```r
d <- read_dta("t2.dta")
as.Date(unclass(d$d), origin = "1960-01-01")    # "2024-01-01" "2024-02-01" "2024-03-01" "2024-04-01"
as.Date(d$d, origin = "1960-01-01")             # error: do not know how to convert 'd$d' to class "Date"
read_dta("t2.dta", dates = FALSE)               # error: unused argument
```
In R there is no conversion to switch off: the column is always numbers plus a `%td` format, and `read_dta` has no `dates` argument (formals: file, col_select, encoding, skip, n_max). The docs say this ("R keeps every date as a number"; readstata13 table: "`convert.dates = TRUE` | not done"), so I count the task as partly: the conversion works by hand, and "turn it off" is the default state. Gotcha worth a doc line: `as.Date()` on the `dta_num` directly errors; `unclass()` is required (the docs do show `unclass`, but never say what happens without it). The `Dates` section says `%tc` uses `as.POSIXct(unclass(x)/1000, ...)` but I did not test `%tc`.

## 8. Write; release and storage types; a documented error: partly
```r
t8 <- dibble(a = 1:3, b = c(1.5,2,3), c = c(TRUE,FALSE,TRUE), s = c("x","yy","zzz"), e = as.Date("2024-01-01") + 0:2)
save_dta(t8, "t8.dta"); b8 <- read_dta("t8.dta")
```
Storage read back: `a` long, `b` double, `c` byte, `e` long (`%td`), `s` strN (attribute NULL; `%-3s`). That matches the docs' mapping table.
Release: R cannot report it ("R | not exposed; `read_dta` reads every release the same way"). The docs promise 118. I confirmed it only by reading the first bytes of my own file (`<release>118</release>`, `LSF`), outside the library. So the library does what the docs say, but "report which release was written" has no R route.
Errors, all with the documented behaviour:
- `save_dta(tibble(f = factor(...)), ...)`: "save_dta: convert factors to character or numbers first"
- `save_dta(dibble(x = dta_num(c(1, 500), storage = "byte")), ...)`: "bad.dta: x row 2: 500 does not fit storage type byte"
- `save_dta(tibble(d = as.Date(...)), ...)`: "save_dta: cannot write a column of class Date" (the docs' type table says `Date` is an error; `as_dibble()` converts)
- `dibble(p = as.POSIXct(...))`: "dibble: cannot make column p of class POSIXct a Stata column"
Odd: `dibble(f = factor(...))` does not error, since dibble turns factors into character (documented), so the factor error only appears through a plain tibble. The task text said "try something the docs say is an error"; the docs list this under save_dta, which a dibble avoids. Not a bug, but a first try with `dibble` will not hit it.
Also: the error message for a value that does not fit starts with the output file path ("bad.dta: x row 2: ...") and the file was not left behind (`file.exists("bad.dta")` FALSE).

## 9. Variable label, value label set, data label; check by reading back: succeeded
```r
t9 <- dibble(q = dta_num(c(1,2,1), storage="byte", label="Answer to Q", labels=c(Yes=1, No=2)), z = c(10,20,30))
attr(t9, "label") <- "Task nine data"; attr(t9$z, "label") <- "Zed variable"
save_dta(t9, "t9.dta"); b9 <- read_dta("t9.dta")
```
Read back: data label "Task nine data"; `q` label "Answer to Q"; `z` label "Zed variable" (set with `attr<-` on a plain double column, no `dta_num`); `val_labels(b9$q)` Yes 1, No 2; `label_set` "q".
Shared custom set: set `attr(x, "label_set") <- "yesno"` on two columns with equal labels; read back both show `yesno`, and `labelbook` has 4 rows. Works as documented.

## 10. Ordinary values plus `.`, `.a`, `.z`: succeeded
```r
x <- dta_num(c(5, NA, .a, .z, 1, .a), storage = "double", label = "mix")
save_dta(dibble(id = 1:6, x = x), "t10.dta"); b10 <- read_dta("t10.dta")
```
- Print: `5 . .a .z 1 .a`.
- `is_missing`: F T T T F T. `is_tagged_missing`: F F T T F T; with `"a"`: F F T F F T; with `"z"`: F F F T F F.
- `b10$x == .a`: F F T F F T. `tab(x, missing = TRUE)`: `1:1 5:1 .:1 .a:2 .z:1`.
- Filter `x > 2` (dplyr): rows 5, ., .a, .z, .a (missing are large, as documented). Arrange: `1 5 . .a .a .z`.
- Wrote the sorted and filtered tibbles and read back: sorted `1 5 . .a .a .z`, tagged flags F F F T T T; filtered `5 . .a .z .a`, `.z` found at position 4. The letters survive.
- Base subsetting `b10[b10$x > 2 & !is_missing(b10$x), ]` gives `5`.
- Docs unclear: how to get the letter as text per value. `is_tagged_missing(x, "a")` tests one letter at a time; the docs mention `na_tag()` only as "still works on the numbers" (haven's, with `unclass`). I got `NA NA "a" "z" NA "a"` from `haven::na_tag(unclass(b10$x))`, where plain `.` is NA, so it is not distinguishable from a number without `is_missing`. No dtatools function returns the letter per value.
- Docs' Recipe check: the `.`-before-`.a` order after sorting matches the docs (`sort(x)  # 1850 2100 3200 .d .r .s`).

## Doc problems collected
1. Metadata without data in R: README and performance.md promise it via `read_meta`, which R does not have; `read_dta(n_max = 0)` works but is undocumented.
2. Release written/read is "not exposed" in R, so "which release was written" cannot be answered from R.
3. Default display formats per storage type are not listed.
4. `skip`/`n_max` to rows N..M needs a worked line (`skip = N-1, n_max = M-N+1`).
5. `as.Date(<dta_num>)` without `unclass()` errors; the docs show `unclass` but do not say why. `read_dta(dates = FALSE)` does not exist in R (expected, but the task wording presumes it).
6. `haven::as_factor()` does not work on a `dta_num`; not stated.
7. A factor column is silently turned into character by `dibble()` but errors in `save_dta()` of a plain tibble; the factor error is not reachable through `dibble()`.
8. No per-value letter-as-text function for missing values.
