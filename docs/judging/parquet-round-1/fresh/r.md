# R Parquet docs check (datakit 3.1.0 / dtaparser, from the checkout)

Source of truth: `/private/tmp/claude-501/gate2/fresh/r/docs.md` only. Scripts are in this directory
(`t2_5.R`, `t5b.R`, `t6_10.R`, `t11.R`); their output is in `t*.out`; files written are in `work/`.
Everything installed went into `scratch/lib`. R 4.6.1, arrow (R) was already installed; nanoparquet,
duckdb, pyarrow, polars were not (pandas 3.0.5 is, but cannot write Parquet without pyarrow).

## Summary table

| # | outcome | doc problem |
|---|---|---|
| 1 | succeeded | install steps are right, but R's Parquet section says only "Parquet needs nothing beyond datakit, which Install covers", and Install says "install dtaparser first, then datakit" without saying to point `R CMD INSTALL` at a private library (`--library=`) |
| 2 | succeeded | none (types shown in table match) |
| 3 | succeeded | none |
| 4 | succeeded | docs never say what rows past the end do (no error: short or empty tibble) |
| 5 | partly | key-value metadata is not returned by `read_parquet_info()` in R, and R's section never says so (docs.md says the Julia one has "the footer's key-value entries") |
| 6 | succeeded | "Bring it into Parquet as the docs show" and "turn into categorical" have to be pieced together from different sections; no one-line recipe |
| 7 | succeeded | no R-side statement of how a "timestamp without a time zone" is handled |
| 8 | succeeded | none for the task itself; `compression_level` ranges only in the .Rd |
| 9 | succeeded | none |
| 10 | succeeded | minor: "what other tools see" is split across three places, and the summary table's claim for arrow was checked only for arrow |
| 11 | succeeded | brotli/lz4 claims partly checkable only; "not read" list is spread over two places |

## Task 1 — install: succeeded

Docs (r.md, Install): "From a clone, install dtaparser first, then datakit: `R CMD INSTALL dta-parser/r/dtaparser` ...". Parquet section: "Parquet needs nothing beyond datakit ... it reads and writes through dtaparser's Rust core, with no arrow or other library."

```sh
export R_LIBS_USER=.../scratch/lib
R CMD INSTALL --library=.../scratch/lib ../checkout/r/dtaparser
R CMD INSTALL --library=.../scratch/lib ../checkout/r/datakit
Rscript -e '.libPaths(c("<scratch>/lib", .libPaths())); library(datakit); packageVersion("datakit")'
```

Saw: both built with cargo (many harmless `ld: warning ... built for newer 'macOS' version (26.5) than being linked (26.0)`),
`library(datakit)` loads, `packageVersion("datakit")` is 3.1.0, `read_parquet` is `datakit`'s. rlang, tibble, tidyselect, vctrs, bit64, dplyr
were already installed, so I could not test the "install rlang, tibble, tidyselect and vctrs first if R reports one missing" advice.

Doc problems: (a) the brief says "install the package(s) the docs say Parquet needs": the answer ("nothing beyond datakit") is clear but
datakit's own dependency on dtaparser being installed first is only in the generic Install section. (b) The sample commands don't show
`--library=`/`R_LIBS_USER`; trivial. (c) First build output of the build leaves `src/rust/target` inside the checkout (build output; fine).

## Task 2 — write six column types, read back: succeeded

```r
tb <- tibble::tibble(i = 1:6, d = c(1.5,2.5,NA,4.5,5.5,6.5), s = letters[1:6], l = c(TRUE,FALSE,NA,TRUE,TRUE,FALSE),
                     day = as.Date("2024-01-01") + 0:5, ts = as.POSIXct("2024-01-01 12:00:00", tz = "UTC") + 3600*(0:5))
save_parquet(tb, f); back <- read_parquet(f)
```

Saw: a `tbl_df`; types `integer`, `numeric` (double), `character`, `logical`, `Date`, `POSIXct/POSIXt`; `identical(back, tb)` is `TRUE`.
`read_parquet_info()` shows INT32, DOUBLE, BYTE_ARRAY/STRING, BOOLEAN, INT32/DATE, INT64/TIMESTAMP(MICROS, UTC).
Docs matched. No problems.

## Task 3 — some columns, reversed: succeeded

```r
read_parquet(f, col_select = c("s", "i"))        # names: "s" "i"
read_parquet(f, col_select = c("s", "nope"))
```

Saw: columns come back in the order given (`s`, `i`), as documented. Unknown name:
`<path>: column "nope" is not in the file; its columns are "i", "d", "s", "l", "day", "ts"` (an error). Matches docs, including the path prefix
(which the docs omit from the quoted message; trivial).

## Task 4 — rows 3 to 5: succeeded

```r
read_parquet(f, skip = 2, n_max = 3)             # rows 3, 4, 5
read_parquet(f, skip = 4, n_max = 10)            # 2 rows (5, 6)
read_parquet(f, skip = 10, n_max = 3)            # 0 rows, 6 columns
read_parquet(f, skip = 6, n_max = 3)             # 0 rows
```

Saw: rows 3 to 5 correct. Past the end is not an error and not a warning: a request that runs over returns what exists, and one that starts past
the end returns a 0-row tibble with all the columns and types.
Doc problem: the R section says "`skip` and `n_max` work as in `read_dta()`" and the .Rd gives "n_max: The most rows to read; Inf for all" but nothing says what
happens past the end. I had to run it to find out.

## Task 5 — schema and metadata without reading data: partly

```r
info <- read_parquet_info(f)
info$columns[, c("name","r_type","physical_type","logical_type")]; info$rows; info$row_groups; info$compression; info$created_by; info$label; info$notes
```

Saw: names, types (R and Parquet), `rows` 6, `row_groups` (a tibble: rows 6, compressed 298, uncompressed 305), `compression` "snappy",
`created_by` "dta-parquet version 0.1.0", `label` NULL, `notes` character(0).
The key-value metadata is **not** returned: `names(info)` is `rows, row_groups, created_by, compression, label, notes, columns`.
Only the dta profile's contents appear, split into `label`, `notes` and per-column `label`/`value_labels`/`storage`/`logical`. Other keys (e.g. ones another tool wrote)
and the raw `dta` JSON (version, `sort`, `characteristics`, `timestamp`, `tz`, `format`) cannot be seen without reading data.
As a workaround I read the footer with arrow (`arrow::read_parquet(f, as_data_frame = FALSE)$schema$metadata`), which gave the key `dta` and the JSON, e.g.
`{"version":1,"label":"Smoking","notes":[...],"columns":{...},"value_labels":{...}}` (t5b.out). Arrow hid `ARROW:schema`.
Doc problems: R's section says it gives "the number of rows, the row groups, the writer, the codecs, the data label and notes" and never mentions
key-value metadata; parquet.md says of Julia: "`read_parquet_info`, with the footer's key-value entries", which invites the same expectation for R.
The docs should either say the R one has no key-value entries or add them. Also `info$compression` is described as "the codecs its column chunks use, such as "zstd""
without saying what it looks like when chunks differ (vector? one string?). Also the `read_parquet_info()` table in r.md uses `info$columns$value_labels`
and in the .Rd calls it "the name of its value label set", fine.

## Task 6 — .dta with value labels → Parquet: succeeded

```r
region <- with_labels(c(1,2,2,3,1), c(North=1, South=2, East=3), label = "Region of residence")
age <- structure(c(30L,41L,25L,60L,18L), label = "Age in years")
save_dta(tibble::tibble(id = 1:5, region = region, age = age), dta)
df <- read_dta(dta); save_parquet(df, pq); back <- read_parquet(pq)
var_label(back$region)            # "Region of residence"
val_labels(back$region)           # North=1 South=2 East=3
val_label(back$region, 2)         # "South"   (also val_label(x, values = 3) "East")
read_parquet(pq, factors = TRUE)$region   # factor, levels North South East
```

Saw all as documented; `identical(back, df)` `TRUE`. `factor(back$region)` (labelled → factor) also gives levels North, South, East; with `factors = TRUE` the variable label stays as attribute `label`.
Doc problems: the recipe is spread over "Read a Parquet file", "Labels in Parquet files" and the `val_labels.Rd`; "looking up the code" is only shown via `val_label(x)` per row, and
`val_label(x, values = 2)` is only in the .Rd usage (`val_label(x, values = x)`), not in a Parquet example. `val_labels(back$region)["South"]` also works, but the docs don't show it. Also the docs
call it "the language's categorical type" only implicitly (`factors = TRUE`); there is no sentence that says "factor is R's categorical".
Note the README says both `datakit` and `dtaparser` offer `read_dta`; `datakit::read_dta`/`save_dta` worked after `library(datakit)`, consistent with "datakit re-exports dtaparser's functions".

## Task 7 — date, naive timestamp, UTC timestamp, zoned timestamp: succeeded

```r
tz <- tibble::tibble(d = as.Date(c("2024-03-01","2024-03-02")),
  naive = <POSIXct, tzone attribute NULL>, utc = <POSIXct tz "UTC">, ny = <POSIXct tz "America/New_York">)
save_parquet(tz, f7); v <- read_parquet(f7); read_parquet_info(f7)$columns
```

Saw (R session tz America/New_York): `d` is `Date`, INT32 DATE; `naive` is `POSIXct` with no tzone, written INT64 TIMESTAMP(MICROS, UTC);
`utc` POSIXct with tzone "UTC"; `ny` POSIXct with tzone "America/New_York". Units: microseconds for all timestamps (shown by `logical_type`, and by arrow: `timestamp[us, tz=UTC]`, `timestamp[us, tz=America/New_York]`, `date32[day]`).
`identical(v, tz)` is `TRUE`.
Other tools see: arrow shows the naive column as `tz=UTC` with the value 14:30 UTC for a 09:30 local time (the naive value is treated as session-time-zone local when written).
Doc problems: (a) "A `POSIXct` without a `tzone` attribute comes back without one" is all the docs say; they don't say that the instant is taken in the session's time zone
and stored as UTC-adjusted, so `logical_type` says `TIMESTAMP(MICROS, UTC)` for a "no zone" column and an outside reader sees a UTC zone. (b) The docs' mapping table (parquet.md) says a polars `Datetime` without a zone is "TIMESTAMP(its unit, not adjusted to UTC)", but R has no such type and nothing in the R section says how to write a not-adjusted (naive) timestamp from R: only reading is covered (see task 11 where it reads as POSIXct with tzone "UTC"). (c) The read-side docs say the zone is "the one save_parquet() recorded" and the docs' `""` tz profile entry for "an instant without one" isn't connected to R's "no tzone attribute" anywhere.

## Task 8 — codec and row group size; an error: succeeded

```r
save_parquet(big, f8, compression = "zstd", compression_level = 5, row_group_size = 4)   # 10 rows
read_parquet_info(f8)$compression  # "zstd"
read_parquet_info(f8)$row_groups   # rows 4, 4, 2
```

Saw: `compression` "zstd"; 3 row groups with 4, 4, 2 rows; `identical(read_parquet(f8), big)` `TRUE`. Errors (all as documented):
`unknown compression "lzo"; use one of "snappy", "zstd", "gzip", "lz4_raw" or "none"`; `zstd levels run from 1 to 22, not 99`; `snappy has no compression levels`;
`save_parquet: cannot write z, a column of class complex` (also POSIXlt and difftime).
Doc problems: `compression_level` ranges (zstd 1 to 22, gzip 0 to 10) are only in the .Rd; the docs' R guide says only "`compression_level` the codec's level". The error messages in docs.md omit the leading `save_parquet:` on some; trivial.
Also, `compression = "lz4_raw"` for writing is listed but I did not write it (no need).

## Task 9 — labels written and checked: succeeded

```r
smoker <- with_labels(c(1,0,1), c(No=0, Yes=1), label = "Smokes daily"); n <- structure(1:3, label = "Count", format = "%9.2f")
attr(lab, "label") <- "Smoking"; attr(lab, "notes") <- c("Wave 2 only.", "Second note")
save_parquet(lab, f9); s <- read_parquet(f9)
```

Saw: `var_label(s$smoker)` "Smokes daily", `val_labels(s$smoker)` No=0, Yes=1, `var_label(s$n)` "Count", `attr(s$n,"format")` "%9.2f", `attr(s,"label")` "Smoking", `attr(s,"notes")`
both notes; `identical(s, lab)` `TRUE`. `read_parquet_info()` gives `label` "Smoking", `notes`, and per-column `label`/`value_labels` ("smoker"). Another tool (arrow) sees just the codes and column names, as documented.
No problems. (Note the docs example `attr(smoking, "notes") <- "Wave 2 only."` is a length-1 string; a vector worked too.)

## Task 10 — `.`, `.a`, `.z`: succeeded

```r
x <- c(1, 2.5, NA, tagged_na("a"), tagged_na("z"), 7)
save_dta(tibble::tibble(id = 1:6, x = x), f10dta); r10 <- read_dta(f10dta)
save_parquet(r10, f10); b <- read_parquet(f10)
na_tag(b$x); is_tagged_na(b$x); missing_rank(b$x)
```

Saw: printing `b$x` shows `1.0 2.5 NA NA NA 7.0` — all three missings print as `NA`. `na_tag(b$x)` is `NA NA NA "a" "z" NA`; `is.na` is `TRUE` for all three; `missing_rank` is `0 0 1 2 27 0`, so
`.`=1, `.a`=2, `.z`=27. Per value: number / plain `.` / `.a` / `.z` / number. `identical(b, r10)` `TRUE`. Column is DOUBLE in the file (`read_parquet_info`'s `storage` was `NA` here, since the source was an R double, so no storage record).
Other tools: arrow (R) gives `NA` for all three values with `is.nan()` `FALSE`, i.e. arrow R reads them as (tagged) NA, as the docs say ("arrow and nanoparquet as tagged NAs"); pyarrow/polars/DuckDB SQL give NaN per the docs (not run: not installed).
`save_parquet(..., missing_letters = FALSE)` gives `NA NA NA NA NA NA` for `na_tag`, letters lost, as documented. Writing the tibble directly (no .dta) also kept the letters.
Doc problems: the question "what other tools see in place of .a to .z" has an answer only in the parquet.md table (NaN / tagged NA depending on the tool) and `save_parquet.Rd`; the R section says "Other tools see NaN, which some count as a value rather than a missing one", but the paragraph before it says arrow and nanoparquet read tagged NAs. Both are true (the first means pyarrow, polars and DuckDB SQL), but the sentence doesn't say which tools, so it reads as contradicting the one before. Also the docs' example doesn't show telling `.` from `.a` from a number in one expression; I used `na_tag()`.
Also: `is_tagged_na(b$x)` marks `.a`/`.z` but not `.`, while `is.na()` marks all: documented only in `na_tag.Rd`.

## Task 11 — Parquet written by another tool: succeeded

No pyarrow, polars, DuckDB, nanoparquet or fastparquet on this machine (pandas 3.0.5 can't write Parquet without one of them), so the other tool was the R **arrow** package (it prints "Some features are not enabled in this build of Arrow", unrelated).

```r
write_parquet(arrow_table(i=1:4, d=..., s=..., l=..., day=..., ts_utc=..., f=<factor>, u8=<uint8>, u64=<uint64>,
                          dec=<decimal128(9,2)>, naive=<timestamp[us]>, tm=<time32[s]>), p, compression = codec)
datakit::read_parquet(p)
```

Saw: all four codecs (snappy, zstd, gzip, uncompressed) read to identical tibbles; `read_parquet_info()$compression` agrees ("none" for uncompressed). Types: `integer`, double, character, logical, `Date`,
`POSIXct` (tzone "UTC"), factor (levels "b" "a" — in order of first appearance, not ordered, as documented), uint8 integer, uint64 double, decimal double, timestamp without zone → `POSIXct` tzone "UTC" (physical `TIMESTAMP(MICROS, local)`), time32 → `difftime` seconds.
What the docs say is not read, and what I saw:
- FLOAT16: `column "h" is FLOAT16, which is not read` — as documented; leaving it out with `col_select` worked.
- nested list column: error `the file has nested columns, which are not read: "l"; select the columns wanted, or pass nested = "skip"`; `nested = "skip"` and `col_select = "a"` both worked; `read_parquet_info()` shows `role` "nested" and `r_type` NA.
- INT64 value 2^53+1: error with the documented message; `int64 = "character"` gave "9007199254740993".
- Labels written by arrow (`label` attribute): not read (`var_label()` NULL), as documented in "Coming from arrow".
- brotli and arrow's `lz4` read OK here (I did not check which LZ4 framing arrow's `lz4` wrote); arrow could not write `compression = "lz4_raw"` with this build (an R-side `match.arg()` error in arrow, which left an empty file that datakit then rejected as "not a Parquet file: it is shorter than 12 bytes"). I did not test LZO, BIT_PACKED, or encryption.
- Datasets of many files, Hive partitions, predicate pushdown: not part of datakit (not run).
- `read_parquet(f, as_data_frame = FALSE)` after `library(arrow)` → arrow's `read_parquet` is the one found (`environmentName` "arrow") and `datakit::read_parquet(..., as_data_frame = FALSE)` errors `unused argument (as_data_frame = FALSE)`, as documented.
Doc problems: (a) the "what is not read" list is in two places ("What this version does not read: FLOAT16, INTERVAL, the Hadoop framing of LZ4, LZO, encryption. Nested columns... Datasets...") and the .Rd says only "FLOAT16 and INTERVAL", so a reader of the .Rd alone would miss the codecs and datasets; the docs' error table also lists `BIT_PACKED` which the R section omits. (b) The R section lists "brotli" among readable codecs while `save_parquet()` cannot write it; that is implied, never stated. (c) The docs never say a Parquet timestamp that is *not* adjusted to UTC (`isAdjustedToUTC = false`) reads as a `POSIXct` in UTC (it does; stated only as "else UTC"), so a naive wall-clock reading is shown as UTC instants.

## Other observations

- `library(arrow)` after datakit masks `read_parquet`: the docs warn about this and the warning is accurate.
- Sandbox note: arrow printed `cpu_info.cc ... sysctlbyname failed ... Operation not permitted` messages; sandbox, not the library.
