# R Parquet docs check (datakit / dtaparser 3.1.0)

Source used: `/private/tmp/claude-501/gate2/fresh3/r/docs.md` only. Packages built from the checkout copy into
`scratch/lib`. Scripts: `t1_5.R`, `t6_11.R`, `t7b.R` (all in `scratch/`). Install log: `install.log`.
Machine: R 4.6.1, macOS, local time zone America/New_York. pyarrow, polars, DuckDB and nanoparquet are not installed;
R `arrow` 26.0.0 is.

## Task 1: succeeded
```sh
R CMD INSTALL --library=scratch/lib checkout/r/dtaparser
R CMD INSTALL --library=scratch/lib checkout/r/datakit
```
```r
library(dtaparser); library(datakit); packageVersion("datakit")   # 3.1.0, both
```
Both built (Rust and cc present) and loaded. No arrow or other Parquet package needed, as the docs say.
Docs: the "from a clone" block says nothing about installing into a private library (`--library`) and gives no load check
(the CRAN-style block has `library(datakit)`); minor.

## Task 2: succeeded
```r
df <- tibble::tibble(i = 1:6, d = c(1.5,2.5,NA,4.5,5.5,6.5), s = c("a","b","c",NA,"e","f"),
  l = c(TRUE,FALSE,NA,TRUE,TRUE,FALSE), dt = as.Date("2024-01-01") + 0:5,
  ts = as.POSIXct("2024-01-01 12:00:00", tz = "UTC") + 3600*(0:5))
save_parquet(df, "t2.parquet"); back <- read_parquet("t2.parquet")
```
Got a `tbl_df`. Types: i integer, d numeric (double), s character, l logical, dt Date, ts POSIXct/POSIXt. `identical(back, df)` is TRUE.
Docs: none; the "what each type becomes" table matches.

## Task 3: succeeded
```r
read_parquet("t2.parquet", col_select = c("s","i"))   # columns s, i
read_parquet("t2.parquet", col_select = c(3,1))       # columns s, i
read_parquet("t2.parquet", col_select = c("s","nope"))
```
Order is the order given (reversed from file order). The unknown name is an error:
`/…/t2.parquet: column "nope" is not in the file; its columns are "i", "d", "s", "l", "dt", "ts"`.
Docs: the message in the docs omits the leading file path that the real message has (cosmetic).

## Task 4: succeeded
```r
read_parquet("t2.parquet", skip = 2, n_max = 3)       # i = 3,4,5
nrow(read_parquet("t2.parquet", skip = 4, n_max = 10))  # 2
nrow(read_parquet("t2.parquet", skip = 10))             # 0
nrow(read_parquet("t2.parquet", skip = 2, n_max = 100)) # 4
```
Rows past the end give the rows there are, and a `skip` past the end gives 0 rows; no error, as documented.
Docs: "rows 3 to 5" has to be translated by the reader to `skip = 2, n_max = 3`; the docs show that only for `skip = 2, n_max = 2`, but it is easy to infer.

## Task 5: succeeded
```r
info <- read_parquet_info("t2.parquet")
info$rows; info$row_groups; info$compression; info$columns; info$key_value
```
rows 6; one row group (6 rows, 294 compressed / 300 uncompressed bytes); compression "snappy"; created_by "dta-parquet version 0.1.0";
columns with r_type, physical_type, logical_type (ts is `TIMESTAMP(MICROS, UTC)`); key_value keys `dta` (`{"version":1,"columns":{"ts":{"tz":"UTC"}}}`)
and `ARROW:schema` (base64). With `row_group_size = 4, compression = "gzip"`: two groups of 4 and 2; compression "gzip".
Docs: `info$compression` is described as "the codecs its column chunks use" (plural) but is shown as a single string; the docs do not say what a file
with mixed codecs gives (not tested).

## Task 6: succeeded
```r
health <- with_labels(c(1,2,3,2,1,3), c(Poor=1, Fair=2, Good=3), label = "Self-rated health")
age <- structure(c(30L,41L,52L,63L,24L,35L), label = "Age in years")
save_dta(data.frame(id = 1:6, age = age, health = health), "t6.dta")
x <- read_dta("t6.dta"); save_parquet(x, "t6.parquet"); b <- read_parquet("t6.parquet")
var_label(b$health); val_labels(b$health); val_label(b$health, 2); read_parquet("t6.parquet", factors = TRUE)$health
```
Variable label "Self-rated health" (age: "Age in years"). `val_labels`: Poor=1, Fair=2, Good=3. `val_label(b$health, 2)` gives "Fair"; `val_label(b$health)` gives the text of every row.
`factors = TRUE` gives a factor with levels Poor, Fair, Good (the variable label stays as an attribute). `identical(b, x)` TRUE.
Docs: `read_dta`, `save_dta` and `with_labels` are used from `library(datakit)` alone, but the datakit docs never say outright that datakit re-exports
them except in the README ("datakit re-exports dtaparser's functions"). The single-code lookup `val_label(x, 2)` is only implied by the signature `val_label(x, values = x)`; there is no example with a code. "Turn the column into the language's categorical type" is `factors = TRUE`, found under "Labels in Parquet files"; there is no way to convert an already-read column except re-reading (`as.factor` / `factor(x)` follow from the with_labels docs but is not shown for this case).

## Task 7: partly
```r
dd <- tibble::tibble(day = as.Date(c("2024-03-01","2024-03-02")),
  naive = as.POSIXct(c("2024-03-01 09:30:00","2024-03-01 17:05:00")),   # tzone attribute removed
  utc = as.POSIXct(c(...), tz = "UTC"), ny = as.POSIXct(c(...), tz = "America/New_York"))
save_parquet(dd, "t7.parquet"); v <- read_parquet("t7.parquet")
```
Read back: day Date; naive POSIXct, no tzone (prints in local time, 09:30); utc POSIXct, tzone "UTC"; ny POSIXct, tzone "America/New_York" (09:30 EST).
All three timestamps are INT64 `TIMESTAMP(MICROS, UTC)` in the file (microseconds, adjusted to UTC); the zone is kept in the `dta` profile (`"tz":""` for naive, `"UTC"`, `"America/New_York"`).
`identical(v, dd)` is FALSE, because `tz = ""` (R's "local time") reads back as no tzone attribute at all (naive built with a tzone attribute of `""` is not the same as NULL).
arrow reads the file as `timestamp[us, tz=UTC]` for the naive column too, and `America/New_York` for ny.
Why partly: R never writes a Parquet timestamp *without* a zone (isAdjustedToUTC false). The docs' R page says "A `POSIXct` without a `tzone` attribute comes back without one" and the type table says a POSIXct is adjusted to UTC, but nothing says
(a) that the instant is computed from R's local time zone, so a naive column's wall-clock times will shift if read in another zone by arrow, polars or in R on another machine;
(b) that other tools see a naive POSIXct as a UTC-zoned timestamp (above); (c) that `tzone = ""` is not kept. A reader who needs "timestamp without a time zone" in the Parquet sense gets no answer from the R docs.

## Task 8: succeeded
```r
save_parquet(big, "t8.parquet", compression = "zstd", compression_level = 5, row_group_size = 4)
read_parquet_info("t8.parquet")   # compression "zstd"; row groups of 4, 4, 2 rows
save_parquet(big, f, compression = "lzo")                      # error
save_parquet(big, f, compression = "zstd", compression_level = 99) # error
save_parquet(big, f, compression = "snappy", compression_level = 3) # error
save_parquet(data.frame(z = complex(real = 1:2, imaginary = 0)), f)  # error
```
gzip, lz4_raw and none each read back in the file's metadata as chosen, with row groups 3,3,3,1. Errors, exactly as in the docs' table:
`unknown compression "lzo"; use one of "snappy", "zstd", "gzip", "lz4_raw" or "none"`; `zstd levels run from 1 to 22, not 99`; `snappy has no compression levels`;
`save_parquet: cannot write z, a column of class complex`; for `list(1, 2)`: `column "l": element 1 is not a raw vector or NULL; a list column must hold only raw vectors`.
Docs: the Rd says gzip levels are "0 to 10 (6)"; not tested. Docs fine here.

## Task 9: succeeded
```r
smoking <- tibble::tibble(smoker = with_labels(c(1,0,1,0), c(No=0, Yes=1), label = "Smokes daily"), n = c(3L,4L,5L,6L))
attr(smoking$n, "label") <- "Count of things"; attr(smoking, "label") <- "Smoking survey"; attr(smoking, "notes") <- "Wave 2 only."
save_parquet(smoking, "t9.parquet"); s <- read_parquet("t9.parquet")
```
Read back: `var_label(s$smoker)` "Smokes daily", `var_label(s$n)` "Count of things", `val_labels(s$smoker)` No=0, Yes=1, `attr(s, "label")` "Smoking survey", `attr(s, "notes")` "Wave 2 only.".
`read_parquet_info()` shows the same data label and notes, and per column label and value-label set name ("smoker"). `identical(s, smoking)` TRUE.
Docs: the "Write labels" section's example puts the variable label inside `with_labels(..., label =)`; for a plain integer column (my `n`) the docs say only "`label` ... on a column", which is enough.

## Task 10: succeeded
```r
q <- data.frame(id = 1:6, q = with_labels(c(1.5, NA, tagged_na("a"), 7, tagged_na("z"), tagged_na("a")),
       c(Yes = 1, tagged_na(c("Not asked" = "a", "Zero" = "z"))), label = "q"))
save_dta(q, "t10.dta"); r <- read_dta("t10.dta"); save_parquet(r, "t10.parquet"); rb <- read_parquet("t10.parquet")
na_tag(rb$q); is.na(rb$q); val_label(rb$q)
```
Per value: 1.5 and 7 are numbers; `.` (plain NA) has `na_tag` NA and no label; `.a` has tag "a" (label "Not asked"); `.z` tag "z" ("Zero"). `is.na()` is TRUE for all three kinds, so only `na_tag()`, `is_tagged_na()` or `val_label()` tell them apart.
`identical(rb, r)` TRUE; the column is DOUBLE in the file. With `missing_letters = FALSE`, `na_tag` is all NA (letters lost).
What the docs say others see in place of `.a` to `.z`: NaN (pyarrow: NaN not null, pandas: missing; polars: NaN not null; DuckDB SQL: NaN not NULL, but DuckDB in R: tagged NA with letter kept); arrow (R) and nanoparquet: tagged NA, letter kept. `.` and everything else missing is a plain null.
Checked with R arrow: values print as NA and `na_tag()` of arrow's column gives NA NA "a" "z", as documented. I could not check pyarrow, polars or DuckDB (not installed).
Docs: fine; the docs' own `na_tag(read_parquet("survey.parquet")$income)` example was easy to follow.

## Task 11: partly
Looked for: pyarrow (not installed; `import pyarrow` fails), nanoparquet (R package not installed), polars (not installed), DuckDB (no binary). Used R `arrow` 26.0.0 instead
(`arrow::write_parquet(af, "t11.parquet")`, with integer, double, text, logical, Date, POSIXct in Europe/Paris and a factor with levels a, b, c).
```r
a <- read_parquet("t11.parquet")
```
Types: integer, numeric, character, logical, Date, POSIXct with tzone "Europe/Paris" (from `ARROW:schema`), factor. Factor levels "b" "a" "c" (first appearance, all four rows) and "b" "c" with `skip = 2`, as the docs say.
`read_parquet_info()`: key_value keys "r", "ARROW:schema"; created_by "parquet-cpp-arrow version 26.0.0".
Also checked with arrow-written files: list column gives `the file has nested columns, which are not read: "l"; select the columns wanted, or pass nested = "skip"`, and `nested = "skip"` gives the flat columns;
DECIMAL(19,9): `n_max = 1` gives 2.5, `decimal = "character"` gives all digits, default is the documented error. arrow codecs zstd, gzip, uncompressed and lz4 all read.
With arrow attached after datakit, `read_parquet` is masked, and `datakit::read_parquet(..., as_data_frame = FALSE)` fails with `unused argument (as_data_frame = FALSE)`, as documented.
What the docs say this library does not read: FLOAT16, INTERVAL, the Hadoop framing of LZ4, LZO, encryption, values encoded BIT_PACKED (each an error naming the column or type); nested columns (lists, maps, structs) unless `col_select` leaves them out or `nested = "skip"`; datasets of many files, Hive partitions and predicate pushdown; arrow's `r` metadata entry (labels written by arrow, `haven_labelled`) is not read.
Why partly: only one other tool (arrow) was available, so the pandas, polars, pyarrow, DuckDB and nanoparquet claims are unchecked. I did not test the not-read cases that need special files (FLOAT16, LZO, Hadoop LZ4, BIT_PACKED, encryption).
Docs: README/parquet.md lists "These types are read too: ... fixed-length binary, UUID, ENUM and JSON" while r.md's type table says BYTE_ARRAY without annotation and UUID come back as a list of raw vectors; consistent but "read" there means "as bytes". The "does not read" list is in two places (r.md, "What this version does not read", and the Errors table in parquet.md) and the r.md paragraph repeats BIT_PACKED twice (once in the encodings paragraph, once in the not-read list); harmless.

## Summary of doc problems
1. Task 7: R never writes a Parquet timestamp without a zone; a `POSIXct` without `tzone` is written as UTC-adjusted from R's local zone and other tools see it as a UTC-zoned column; `tzone = ""` is not preserved (`identical()` FALSE). Not in the docs.
2. Task 6: no example looks up the text of a single code (`val_label(x, 2)`) or converts an already-read labelled column to a factor; `factors = TRUE` on read is the only route shown.
3. Task 3: the real error message begins with the file path; the docs omit it.
4. Task 1: the clone install shows no private-library option and no check that the packages load.
5. Task 5: `compression` is documented as plural "codecs" but is a single string in every case tried.
