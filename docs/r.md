# R: dtatools

dtatools reads Stata `.dta` files into tibbles and writes data frames as
`.dta` files. It reads every release from 104 to 119 and writes release
118. Numeric columns keep Stata's missing values `.a` to `.z` and follow
Stata's rules when you compare, sort, group or tabulate them, so code
ported from a Stata do-file gives the same answers.

Contents:
[Install](#install) ·
[The example file](#the-example-file) ·
[Read a file](#read-a-file) ·
[Select columns](#select-columns) ·
[Read some rows](#read-some-rows) ·
[Metadata](#metadata) ·
[Missing values](#missing-values) ·
[Value labels](#value-labels) ·
[Dates](#dates) ·
[Make and change columns](#make-and-change-columns) ·
[Write a file](#write-a-file) ·
[Sets, groups and tabulations](#sets-groups-and-tabulations) ·
[egen in R](#egen-in-r) ·
[Recipes](#recipes) ·
[Coming from haven](#coming-from-haven) ·
[Coming from readstata13](#coming-from-readstata13) ·
[Plain R types: dtaparser](#plain-r-types-dtaparser) ·
[From a do-file to R](#from-a-do-file-to-r) ·
[Fixed-width files](#fixed-width-files-with-a-sas-setup-file) ·
[Parquet files](#parquet-files) ·
[polars frames](#polars-frames) ·
[Threads](#threads) ·
[Troubleshooting](#troubleshooting) ·
[API reference](#api-reference)

The [guide](guide/README.md) explains the Stata concepts behind each
section.

## Install

dtatools needs R 4.2 or later. It reads and writes through dtaparser
and takes `:=` from datakit, and installing it installs both, and
datparser, which datakit includes. None of the four is on CRAN. Each release is published as an R package
repository on GitHub, with binaries for macOS (arm64), Windows (x86_64)
and Ubuntu 24.04 (x86_64) for the current and previous R releases. On
macOS and Windows:

```r norun
install.packages("dtatools", repos = c("https://jbearak.github.io/dta-parser", "https://cloud.r-project.org"))
```

To analyse or prepare data under R's rules, without dibbles, install datakit instead, which installs dtaparser and datparser:

```r norun
install.packages("datakit", repos = c("https://jbearak.github.io/dta-parser", "https://cloud.r-project.org"))
```

To read fixed-width files and nothing else, install datparser alone
(see [Fixed-width files](#fixed-width-files-with-a-sas-setup-file)):

```r norun
install.packages("datparser", repos = c("https://jbearak.github.io/dta-parser", "https://cloud.r-project.org"))
```

On Ubuntu 24.04:

```r norun
install.packages("dtatools", repos = c(
  sprintf("https://jbearak.github.io/dta-parser/bin/linux/noble-x86_64/%s", getRversion()[, 1:2]),
  "https://cloud.r-project.org"
))
```

pak uses the same repository once it is in `repos`, so a project whose
DESCRIPTION imports dtatools installs it with

```r norun
options(repos = c(dta = "https://jbearak.github.io/dta-parser", getOption("repos")))
pak::local_install_deps()
```

Elsewhere, and for the code on `main`, build from source, which needs a
Rust toolchain (`cargo` and `rustc`, from
[rustup.rs](https://rustup.rs)):

```r norun
pak::pak("jbearak/dta-parser/r/dtatools")
```

`remotes::install_github("jbearak/dta-parser", subdir = "r/dtatools")`
does the same; a DESCRIPTION can name the source in
`Remotes: dtatools=jbearak/dta-parser/r/dtatools`. From a clone, install
dtaparser first, then datakit:

```sh
git clone https://github.com/jbearak/dta-parser
R CMD INSTALL dta-parser/r/dtaparser
R CMD INSTALL dta-parser/r/datakit
R CMD INSTALL dta-parser/r/dtatools
```

This way, install rlang, tibble, tidyselect and vctrs first if R reports
one missing. After reinstalling dtaparser, restart R before using
dtatools or datakit. Check the install:

```r norun
library(dtatools)
packageVersion("dtatools")
```

## The example file

Every example on this page reads `survey.dta`. This block makes it; run
it first. It also shows most of what writing can do, which
[Write a file](#write-a-file) explains.

```r
library(dtatools)

survey <- dibble(
  id = 1:6,
  region = dta_num(c(1, 2, 2, 3, 4, 1), storage = "byte", label = "Region",
                   labels = c(North = 1, South = 2, East = 3, West = 4)),
  age = dta_num(c(34, 51, 29, 62, 45, 38), storage = "byte", label = "Age in years"),
  # .d = "don't know", .r = "refused"; NA is Stata's `.`
  income = dta_num(c(2100, .d, 1850, NA, .r, 3200), label = "Monthly income",
                   labels = c("Don't know" = .d, Refused = .r)),
  interviewed = as.Date(c("2024-03-01", "2024-03-01", "2024-03-02",
                          "2024-03-04", "2024-03-04", "2024-03-05")),
  comment = c("", "moved in 2023", "", "", "asked to call back", "")
)
attr(survey, "label") <- "Household survey (example)"
attr(survey, "notes") <- "Made up for the dtatools documentation."
save_dta(survey, "survey.dta")
```

## Read a file

```r
df <- read_dta("survey.dta")
df
```

```text
# A tibble: 6 × 6
  id    region    age   income            interviewed comment             
  <dta> <dta+lbl> <dta> <dta+lbl>         <dta>       <chr>               
1 1     1 [North] 34    2100              23436       ""                  
2 2     2 [South] 51      .d [Don't know] 23436       "moved in 2023"     
3 3     2 [South] 29    1850              23437       ""                  
4 4     3 [East]  62       .              23439       ""                  
5 5     4 [West]  45      .r [Refused]    23439       "asked to call back"
6 6     1 [North] 38    3200              23440       ""                  
```

`read_dta(file)` returns a *dibble*: a tibble whose numeric columns are
`dta_num` vectors. Use it as any tibble, with base R or dplyr. A column
with value labels (`<dta+lbl>`) shows each value with its label, as
haven's labelled columns do; `print(df$region)` lists its labels.

| in the file | in R |
|---|---|
| byte, int, long, float, double | `dta_num`: a double vector; the `storage` attribute names the type |
| `.` | `NA` |
| `.a` to `.z` | `NA` carrying the letter (the same bits as haven's `tagged_na()`) |
| strN, strL text | character |
| strL with binary values | an error; leave the column out with `col_select` |
| `%td`, `%tc` and other date formats | numbers, with the format in the `format` attribute (see [Dates](#dates)) |

Every numeric type becomes double because R integers have a single
`NA`, which could not hold `.a` to `.z`. Every value converts exactly.

String columns are read *packed*: dtatools keeps the bytes from the file
and makes each R string when it is first used. Reading is fast, and
printing or slicing a few rows stays cheap; the first operation over
every value of a long column (`==`, `unique()`, sorting) pays for
making the strings. This is invisible to your code.

## Select columns

```r
df <- read_dta("survey.dta", col_select = c(income, id))
names(df)   # "income" "id"
```

`col_select` takes tidyselect expressions over the column names, as
`dplyr::select()` does: bare names, a character vector, or helpers such
as `starts_with("inc")`. Helpers that look at values, such as
`where()`, do not work, since nothing has been read yet. Columns come
back in the order selected. A name the file does not have is an error naming it. A
character vector in a variable works directly:

```r
wanted <- c("id", "age")
names(read_dta("survey.dta", col_select = wanted))   # "id" "age"
```

## Read some rows

```r
part <- read_dta("survey.dta", skip = 2, n_max = 3)
part$id   # 3 4 5
```

`skip` rows are skipped, then at most `n_max` are read (`Inf`, the
default, for all). So rows `k` to `m`, counting from 1, are
`skip = k - 1, n_max = m - k + 1`. Rows past the end give fewer rows or an empty tibble
with the right columns. The reader seeks to row `skip`, so reading a
window near the end of a large file costs no more than one at the
start. To process a large file in pieces:

```r
for (start in seq(0, 5, by = 4)) {
  chunk <- read_dta("survey.dta", skip = start, n_max = 4)
  print(nrow(chunk))
}
```

## Metadata

Metadata lives in attributes, as in haven:

```r
df <- read_dta("survey.dta")
attr(df, "label")              # "Household survey (example)"
attr(df, "notes")              # "Made up for the dtatools documentation."
attr(df$income, "label")       # "Monthly income"
attr(df$income, "format")      # "%10.0g"
attr(df$income, "storage")     # "double"
attr(df$region, "label_set")   # "region"
attr(df$comment, "format")     # "%-18s"
```

| attribute | on | holds |
|---|---|---|
| `label` | the data frame | the data label (`NULL` if none) |
| `notes` | the data frame | the dataset's notes (`NULL` if none) |
| `label` | a column | its variable label (`NULL` if none) |
| `format` | a column | its display format |
| `storage` | a numeric column | `"byte"`, `"int"`, `"long"`, `"float"` or `"double"` |
| `labels` | a numeric column | its value labels: the codes, named by their text |
| `label_set` | a numeric column | the name of its value label set |

To get the metadata without the data, read no rows:
`read_dta("survey.dta", n_max = 0)` gives a zero-row dibble with every
attribute above.

The file's timestamp, characteristics and sort order are attributes of
the data frame too:

| attribute | holds |
|---|---|
| `timestamp` | the file's text, such as `"28 Oct 2026 14:38"` (`NULL` if none) |
| `characteristics` | a data frame with character columns `variable`, `name` and `value`; `variable` is `"_dta"` for the dataset's own; notes are not among them (`NULL` if none) |
| `sort_order` | the names of the columns the data is sorted by (`NULL` if none) |

With `col_select`, characteristics keep only those of the columns read
and `_dta`'s, and the sort order only its leading keys that were read.

`dta_num` columns keep their attributes through subsetting, `c()`,
`rep()` and dplyr verbs. Arithmetic gives a new `dta_num` without labels
or format.

## Missing values

Stata has 27 numeric missing values: `.` and `.a` to `.z` (see the
[guide](guide/missing-values.md)). In a `dta_num`, `.` is `NA` and `.a`
to `.z` are `NA`s that carry their letter. dtatools exports the 26
letters as `.a` to `.z`, so you can write them in code:

```r
df <- read_dta("survey.dta")
df$income                          # 2100 .d 1850 . .r 3200
is_missing(df$income)              # FALSE TRUE FALSE TRUE TRUE FALSE
is_tagged_missing(df$income)       # FALSE TRUE FALSE FALSE TRUE FALSE
is_tagged_missing(df$income, "r")  # FALSE FALSE FALSE FALSE TRUE FALSE
df$income == .r                    # FALSE FALSE FALSE FALSE TRUE FALSE
df$income[4] <- .s                 # assign a letter
```

On a `dta_num`, missing values behave as in Stata:

- **Comparisons never give `NA`.** Missing values are larger than every
  number, and `.` < `.a` < ... < `.z`. So `df$income > 3000` is `TRUE`
  for every missing income, as `income > 3000` is in Stata. Add
  `& !is_missing(df$income)` when you mean "known and above 3000".
- **Sorting** (`order()`, `sort()`, `dplyr::arrange()`) puts missing
  values last, in that order.
- **Arithmetic** gives `.` for any missing operand, and for results Stata
  cannot hold (`NaN`, `Inf`); `round()`, `log()` and other math functions
  likewise.
- **Logic** (`&`, `|`, `!`) treats a value as true when it is nonzero or
  missing, as Stata's `if` does.
- **`unique()`, `duplicated()`, `%in%` and `match()`** keep `.a` apart
  from `.b`.
- `sum()`, `mean()`, `max()` and friends keep R's rules (`NA` unless
  `na.rm = TRUE`).
- **`dta_pmax()` and `dta_pmin()`** are `pmax()` and `pmin()` with
  arithmetic's rule: a missing result is `.`, and the result has no
  labels. With `na.rm = TRUE` they skip missing values, as Stata's row
  maximum does. Base `pmax()` on a `dta_num` can return the last
  argument's `.a` to `.z` and the first argument's labels.

```r
x <- df$income
x > 3000                           # FALSE TRUE FALSE TRUE TRUE TRUE
x > 3000 & !is_missing(x)          # FALSE FALSE FALSE FALSE FALSE TRUE
x + 100                            # 2200 . 1950 . . 3300
sort(x)                            # 1850 2100 3200 .d .r .s (row 4 is now .s)
dta_pmax(c(2, .a, .b), c(1, 5, NA), na.rm = TRUE)   # 2 5 .
dta_pmax(c(2, .a, .b), c(1, 5, NA))                 # 2 . .
```

Plain doubles hold the codes too, so `c(NA, .i)` is a vector with `.`
and `.i`, and `is_tagged_missing()` reads it. One trap: `%in%` with a
plain double on the right, such as `x %in% c(1, .a)`, treats `.a` as
`NA`, because base R only compares classed values by their codes. Put a
code first (`c(.a, 1)`, which is a `dta_num`) or use `dta_setdiff()`.

## Value labels

```r
df <- read_dta("survey.dta")
val_labels(df$region)               # North 1, South 2, East 3, West 4 (a named dta_num)
val_label(df$region, df$region)     # "North" "South" "South" "East" "West" "North"
val_label(df$income, .d)            # "Don't know"
labelbook(df)$mappings              # every labelled column, one row per label
```

`val_labels(x)` gives a column's labels as a named `dta_num`;
`val_label(x, values)` gives the text of each value, `NA` where a value
has no label. `labelbook(df)` lists every label of every column, as
Stata's `labelbook` does.

To get a factor with the labels as levels, in code order:

```r
labels <- val_labels(df$region)
region <- factor(val_label(df$region, df$region), levels = names(labels)[order(labels)])
levels(region)                      # "North" "South" "East" "West"
```

Values without a label become `NA` in the factor. To keep them as text,
use `ifelse(is.na(t <- val_label(x, x)), as.character(x), t)`.

## Dates

dtatools keeps dates as numbers, with their display format, so a column
read and written comes back identical (including `.a` to `.z`). Stata
counts `%td` dates in days since 1 January 1960 and `%tc` times in
milliseconds since then (see the [guide](guide/dates.md)). To convert:

```r
df <- read_dta("survey.dta")
attr(df$interviewed, "format")                               # "%td"
as.Date(unclass(df$interviewed), origin = "1960-01-01")      # "2024-03-01" ...
clock <- dta_num(c(0, 1.7e12), format = "%tc")
as.POSIXct(unclass(clock) / 1000, origin = "1960-01-01", tz = "UTC")
```

`unclass()` comes first because `as.Date()` does not accept a
`dta_num`. Any missing value becomes `NA`. dtatools has no switch to
turn dates into `Date` on read. The other formats count months (`%tm`),
quarters (`%tq`), half-years (`%th`) or weeks (`%tw`) since 1960; for
example `%tm` month `m` is year `1960 + m %/% 12`, month `m %% 12 + 1`.

To write a date column, give `dibble()` or `as_dibble()` a `Date`
column; it becomes a long with format `%td`. Or set the numbers and
format yourself: `dta_num(days, storage = "long", format = "%td")`.

## Make and change columns

`df[i, name] := value` does what Stata's `generate` and `replace` do
with `if`, and changes `df` itself; add `by` for `bysort`:

```r
df <- read_dta("survey.dta")
df[age >= 40, older] := TRUE           # gen older = 1 if age >= 40
df$older                               # . 1 . 1 1 .
df[income > 3000, high] := 1           # missing incomes count as > 3000
df$high                                # . 1 . 1 1 1
df[income == .r, income] := .d         # replace income = .d if income == .r
df[age >= 40, over40] := age - 40      # gen over40 = age - 40 if age >= 40
df$over40                              # . 11 . 22 5 .
df[, n, by = region] := .N             # bysort region: gen n = _N
df$n                                   # 2 2 2 1 1 2
```

`i` (before the comma) picks rows with Stata's comparisons; a new column
is `.` (strings `""`) on the rows it leaves out. A changed column keeps
its labels and format, and its storage widens when the new values need
it (a byte given 0.5 becomes a double). The value is evaluated among the
columns, and sees only the rows `i` picks, as in data.table: `.N` counts
them in each group, so `.N` is Stata's `_N` only without `i`, and the
rows are not sorted as `bysort` sorts them. `by` takes `g`,
`c("g", "h")` or `.(g, h)`, and a value of `NULL` drops the column. The
column is a name, a string, or `(nm)` for a variable that holds one; a
bare name is the column even if a variable has the same name. Write one
line per column, and to keep `df` as it was, copy it first:
`e <- df; e[i, name] := value`.

data.table writes `:=` inside the brackets, `df[i, name := value]`. On
a dibble that is an error that shows the line to write instead, since
it used to return a changed copy and leave `df` as it was.

`:=` is datakit's; dtatools re-exports it and adds the rules for
dibbles. rlang and data.table also export a `:=`, and R uses the one
from the package attached last, so attach dtatools after them. Tests that call
`dtatools::` functions without attaching dtatools can bind it in a
helper file: `` `:=` <- dtatools::`:=` ``. See `?"dibble-assign"`.
On a data frame that is not a dibble, the same `:=` follows R's rules
instead; see [From a do-file to R](#from-a-do-file-to-r).

When the new value doesn't use any columns, R's own assignment works
too, without attaching dtatools:

```r
df[age < 30, young] <- 1               # gen young = 1 if age < 30
df$young                               # . . 1 . . .
df[income == .d, income] <- .r         # replace income = .r if income == .d
```

R evaluates the value before the dibble sees it, among your variables,
not the columns, so `df[i, y] <- x * 2` can't use the column `x`; use
`:=` for that, and for `by`. Otherwise this works as
`df[i, name] := value` does, except that a bare name that is a variable
but not a column is an error, since tibble would read it as the
variable; so a loop or helper that writes `df[i, col] <- v` needs
`df[i, (col)] <- v`, and a new column named like a built-in such as
`pi` or `T` needs quotes (`df[, "pi"] <- 1`). To add a row, write
`df[nrow(df) + 1, ] <- list(...)`. Any other `[<-`, such as
`df[1, 2] <- 0` or several columns, is tibble's.

## Write a file

```r
save_dta(df, "out.dta")
```

`save_dta(data, file)` writes any data frame as release 118 and returns
`file` invisibly. It is dtaparser's; dtatools re-exports it. It goes by
each column's type and attributes only, so it writes a dibble and
dtaparser's plain tibble alike. A dibble from `read_dta` writes back with its values,
missing codes, numeric storage types, variable labels, value labels, display
formats, data label, notes, characteristics and sort order. The
`timestamp` attribute is written as given; without one, the file gets
the current time. String columns are written as narrow as their values allow ([storage types](guide/storage-types.md)).

How columns map to storage types:

| R column | Stata storage |
|---|---|
| numeric with a `storage` attribute | that type; a value that does not fit is an error |
| integer | long |
| double | double |
| logical | byte |
| character | strN up to 2045 bytes, else strL; `NA` becomes `""` (Stata strings have no missing value) |
| factor | long codes 1 to k, labelled with the levels, as Stata's `encode` makes them |
| `Date` | days since 1960 with format `%td`: long when every day is whole, else double |
| `POSIXct` | milliseconds since 1960 as double, with format `%tc`; the UTC clock time |
| anything else (`POSIXlt`, `difftime`, lists) | an error |

`NA` in a numeric column is `.`; tagged `NA`s (dtatools' or haven's) are
`.a` to `.z`. Strings must be UTF-8; `enc2utf8()` converts others.

Labels are attributes: `label` for a variable label, `labels` (a named
numeric vector) for value labels, `label_set` to name the set (default:
the column's name; columns that share a set must carry the same
labels), `format` for the display format, and the data frame's `label`
and `notes`. `dta_num()` sets them in one call:

```r
out <- dibble(
  id = 1:3,
  smoker = dta_num(c(1, 0, .d), storage = "byte", label = "Smokes daily",
                   labels = c(No = 0, Yes = 1, "Don't know" = .d))
)
attr(out, "label") <- "Smoking"
save_dta(out, "smokers.dta")

back <- read_dta("smokers.dta")
attr(back, "label")                  # "Smoking"
attr(back$smoker, "label")           # "Smokes daily"
val_label(back$smoker, back$smoker)  # "Yes" "No" "Don't know"
```

`dibble()` builds a dibble from plain columns, like `tibble()`:
doubles, integers and logicals become `dta_num`; `.a` to `.z` written
inline keep their codes; a factor becomes character; a `Date` becomes
`%td`; a haven `labelled` column keeps its labels. `as_dibble(df)`
converts an existing data frame by the same rules.

## Sets, groups and tabulations

These treat `.`, `.a`, ..., `.z` as distinct values, as Stata does, and
accept `dta_num`, plain doubles and character vectors:

```r
df <- read_dta("survey.dta")
tab(df$income, missing = TRUE)        # counts: 1850 2100 3200 . .d .r, one each
tab(df$region)                        # 1: 2, 2: 2, 3: 1, 4: 1
dta_group_id(df$region)               # 1 2 2 3 4 1, as egen group()
dta_group_tag(df$region)              # 1 1 0 1 1 0, as egen tag()
dta_setequal(c(1, .a), c(.a, 1))      # TRUE
dta_setdiff(c(.a, .b, 1), .b)         # .a 1
```

`dta_group_id(..., missing = FALSE)` numbers the groups of one or more
columns (or a data frame) 1, 2, ... in sorted order; rows with a missing
value get `NA` unless `missing = TRUE`. `dta_group_tag()` marks the
first row of each group. `tab(x, missing = FALSE)` counts each value in
Stata's order, named as Stata writes the value.

## egen in R

An `egen` line becomes `df[i, v, by = g] := value`, with an R function
as the value. `by(g)` or `by g:` is `by = g`, and `if c` is `i`: the
value sees only the rows `c` picks, and the other rows get `.`, as with
`egen`. R's reductions keep missing values unless told otherwise, so
write `na.rm = TRUE` where `egen` skips them.

| Stata | value | a group or row with only missing values |
|---|---|---|
| `egen v = mean(x)` | `mean(x, na.rm = TRUE)` | `.` |
| `egen v = total(x)` | `sum(x, na.rm = TRUE)` | 0 |
| `egen v = count(x)` | `sum(!is_missing(x))` | 0 |
| `egen v = median(x)` | `median(x, na.rm = TRUE)` | `.` |
| `egen v = sd(x)` | `sd(x, na.rm = TRUE)` | `.` (also with one value) |
| `egen v = max(x)`, `min(x)` | `max(x, na.rm = TRUE)`, `min(...)` | `.`, and R warns once per such group; wrap the value in `suppressWarnings()` |
| `egen v = rowtotal(x y)` | `rowSums(cbind(x, y), na.rm = TRUE)` | 0 |
| `egen v = rowmean(x y)` | `rowMeans(cbind(x, y), na.rm = TRUE)` | `.` |
| `egen v = rowmax(x y)`, `rowmin(...)` | `dta_pmax(x, y, na.rm = TRUE)`, `dta_pmin(...)` | `.` |
| `egen v = rowmiss(x y)` | `rowSums(cbind(is_missing(x), is_missing(y)))` | 2, the number of columns |
| `egen v = rownonmiss(x y)` | `rowSums(!cbind(is_missing(x), is_missing(y)))` | 0 |
| `egen v = group(g)`, `tag(g)` | `dta_group_id(g)`, `dta_group_tag(g)` | `.` and 0 where `g` is missing; `missing = TRUE` makes it a group |
| `by g: gen v = _n` | `seq_len(.N)`, counting rows in file order | |

```r
df <- read_dta("survey.dta")
df[, avg, by = region] := mean(income, na.rm = TRUE)      # egen avg = mean(income), by(region)
df$avg                                                    # 2650 1850 1850 . . 2650
df[age < 40, young, by = region] := mean(income, na.rm = TRUE)  # ... if age < 40
df$young                                                  # 2650 . 1850 . . 2650
df[, known, by = region] := sum(!is_missing(income))      # egen known = count(income), by(region)
df$known                                                  # 2 1 1 0 0 2
df[, top, by = region] := suppressWarnings(max(income, na.rm = TRUE))
df$top                                                    # 3200 1850 1850 . . 3200
df[, both] := rowSums(cbind(age, income), na.rm = TRUE)   # egen both = rowtotal(age income)
df$both                                                   # 2134 51 1879 62 45 3238
df[, nth, by = region] := seq_len(.N)                     # by region: gen nth = _n
df$nth                                                    # 1 1 2 1 1 2
```

`rank()`, `pctile()`, `mode()` and `cut()` have no row. Their rules for
ties and percentiles could not be checked against an open-source
implementation, so R's `rank()` and `quantile()` may disagree with them.

dtaparser's columns are plain R types, so the same `na.rm = TRUE`
values work with its `:=` (see [From a do-file to R](#from-a-do-file-to-r)),
dplyr's `mutate(.by = g)` or data.table's `by`. There an all-missing
group gives R's own results, such as `NaN` from `mean()` and `-Inf`
from `max()`, not `.`.

## Recipes

**Keep `.a` to `.z` through dplyr and back to a file.**

```r
library(dplyr, warn.conflicts = FALSE)
older <- read_dta("survey.dta") |>
  filter(age >= 40) |>
  arrange(income)
save_dta(older, "older.dta")
read_dta("older.dta")$income          # . .d .r
```

**Recode a missing reason.** Turn "refused" into "don't know":

```r
df <- read_dta("survey.dta")
df$income[is_tagged_missing(df$income, "r")] <- .d
tab(df$income, missing = TRUE)
```

**Read a file from an old Stata in another encoding.** Files before
release 118 do not record their encoding. The default is Windows-1252;
pass `encoding = "latin1"` or `encoding = "utf-8"` if text looks wrong
(see the [guide](guide/encodings.md)).

**Hand a column to code that expects plain numbers.**
`as.double(unclass(x))` drops the class; missing values stay `NA`, and
haven's `na_tag()` can still read the letters.

## Coming from haven

dtatools' `read_dta()` takes the same `col_select`, `skip`, `n_max` and
`encoding` arguments as haven's, and its tagged `NA`s use haven's bits,
so most code carries over. The differences:

| haven | dtatools |
|---|---|
| `haven::read_dta(file)` | `read_dta(file)`; numeric columns are `dta_num` |
| `labelled` columns with a `labels` attribute | `dta_num` with a `labels` attribute; `label_set` names the set |
| `%td` columns as `Date`, `%tc` as `POSIXct` | numbers with their `format`; see [Dates](#dates) |
| `as_factor(x)` | `factor(val_label(x, x), levels = ...)`; see [Value labels](#value-labels). `haven::as_factor()` does not accept a `dta_num` |
| `tagged_na("d")` | `.d` |
| `na_tag(x)` | `is_tagged_missing(x, "d")`; `na_tag()` still works on the numbers |
| `is_tagged_na(x)` | `is_tagged_missing(x)` |
| comparisons give `NA` for missing values | comparisons follow Stata: missing values are large |
| `print_labels(x)` | `val_labels(x)`, or `labelbook(df)` for every column |
| `zap_labels(x)` | `attr(x, "labels") <- NULL` |
| `write_dta(data, path, version = 14, label = ...)` | `attr(data, "label") <- ...; save_dta(data, path)`; always release 118 |
| `write_dta(..., strl_threshold = 2045)` | automatic: text over 2045 bytes is a strL |

`as_dibble()` converts a haven data frame: `labelled` columns keep their
labels, `Date` columns become `%td` numbers, and tagged `NA`s keep their
letters. `save_dta()` also writes a plain haven data frame directly,
`Date` columns as `%td`.

## Coming from readstata13

| readstata13 | dtatools |
|---|---|
| `read.dta13(file)` | `read_dta(file)` |
| `select.cols = c("a", "b")` | `col_select = c(a, b)` |
| `select.rows = c(101, 200)` | `skip = 100, n_max = 100` |
| `convert.factors = TRUE` (the default) | not done; codes stay numbers; see [Value labels](#value-labels) |
| `convert.dates = TRUE` | not done; see [Dates](#dates) |
| `missing.type = TRUE` and `attr(df, "missing")` | always: `.a` to `.z` are in the values; `is_tagged_missing()` |
| `encoding = "latin1"`, `fromEncoding` | `encoding = "latin1"` |
| `replace.strl = TRUE` | always: strLs come back as text |
| `attr(df, "var.labels")`, `varlabel(df)` | `attr(df$x, "label")` per column |
| `attr(df, "datalabel")` | `attr(df, "label")` |
| `attr(df, "formats")`, `attr(df, "types")` | `attr(df$x, "format")`, `attr(df$x, "storage")` |
| `get.label(df, "set")`, `get.label.name(df, "x")` | `val_labels(df$x)`, `attr(df$x, "label_set")` |
| `save.dta13(df, file, data.label = ...)` | `attr(df, "label") <- ...; save_dta(df, file)` |

## Plain R types: dtaparser

dtatools follows Stata's rules, which is what tests of a Stata pipeline
need. To analyse a file under R's rules instead, read it with
dtaparser, which dtatools installs alongside:

```r
df <- dtaparser::read_dta("survey.dta")
df$region             # 1 [North] 2 [South] 2 [South] 3 [East] 4 [West] 1 [North]
df$income             # 2100 NA 1850 NA NA 3200
df$income > 2000      # TRUE NA FALSE NA NA TRUE
class(df$interviewed) # "Date"
```

| in the file | dtaparser |
|---|---|
| byte, int, long | integer; double if the rows read hold `.a` to `.z` |
| float, double | double |
| `.` and `.a` to `.z` | `NA`; in doubles `.a` to `.z` keep their letter as haven's tagged NAs (`na_tag()`) |
| value labels | a `dtaparser_labelled`: the numbers, with a `labels` attribute that keeps through dplyr, labels on `.a` to `.z` included (see [Labelled columns](#labelled-columns)). `factors = TRUE` makes a factor: levels in order of value, unlabelled values as their number; missing values are `NA`, with a warning when `.a` to `.z` lose their letter (`warn_extended_missing = FALSE` silences it) |
| `%td`, `%d...` | `Date` (`dates = FALSE` keeps numbers) |
| `%tc` | `POSIXct` in UTC; `%tC`, which counts leap seconds, stays numbers |
| strN, strL text | character, packed as in dtatools; `""` stays `""` |

`read_dta()` takes the same `col_select`, `encoding`, `skip` and
`n_max` arguments. Columns keep their variable label in `label`; the
tibble keeps `label` and `notes`. `save_dta()` writes the tibble back:
`Date` as `%td`, `POSIXct` as `%tc`, labelled columns with their labels,
and `.a` to `.z` with their letters. A display format other than the
default, such as `%9.2f`, is kept in a column's `format` attribute and
written back. Storage types are not kept, so integers come back long
and doubles double:

```r
dtaparser::save_dta(df, "again.dta")
again <- dtaparser::read_dta("again.dta")
identical(again$interviewed, df$interviewed)  # TRUE
dtaparser::na_tag(again$income)               # NA "d" NA NA "r" NA
```

A factor is written as codes 1 to k labelled with its levels, and marked
with a characteristic, `dtaparser_factor`, so that `read_dta()` reads it
back as the same factor, ordered or not, with its unused levels, even
with `factors = FALSE` (plan 0020). If the file has changed since (its
label set renamed, a value without a label, or `.a` to `.z` added), the
column reads as an unmarked one would, with a warning. dtatools reads
such a column as a `dta_num`, and saving that drops the mark. A factor
from `read_dta(factors = TRUE)` comes back with codes 1 to k, not the
file's own codes, which that read did not keep; to write the file's
codes, read with `factors = FALSE`, the default.

TypeScript's datakit, and `save_dta()` given a polars frame, mark a
categorical they write to `.dta` with another characteristic, `dtaparser_categorical`, of the same
form (plan 0023). Unlike a factor, a categorical may hold `.a` to `.z`.
`read_dta()` reads such a column as a factor, ordered if the marker
says so, with every level of its value labels, when the rows read hold
no `.a` to `.z`; when they do, it keeps the numbers as a
`dtaparser_labelled`, with the letters and their labels, and gives no
warning, whatever `factors` says. The type can therefore depend on
`skip` and `n_max`. The checks are a factor's, with letters and labels
on letters allowed, and a few more: the column is stored as numbers, it
is not read as a date (a `%td`, `%d` or `%tc` format fails only with
`dates = TRUE`), its value label set labels no `.`, and its codes are
whole numbers within long's range. A column that fails one, or carries
both markers, reads as an unmarked one would (with `factors = TRUE`, as
a factor from its labels), with one warning of class
`dtaparser_stale_categorical`. `save_dta()` drops both markers from the
`characteristics` attribute and writes `dtaparser_factor` afresh on
each factor.

`read_meta(file)` reads what the file says about itself, without its
rows: each variable's storage type and display format, and the
dataset's sort order. Comparing two files needs these: `float` and
`double` hold different precision, and the sort keys pair rows.

```r
meta <- dtaparser::read_meta("survey.dta")
meta$nobs                 # 6
meta$variables$storage    # "long" "byte" "byte" "double" "long" "str18"
meta$variables$label_set  # "" "region" "" "income" "" ""
meta$sort_order           # character(0): the file records no sort order
```

The list also holds `release`, `label`, `timestamp`, `value_labels`
(each set's codes, named by their text), `notes` and `characteristics`.
`variables` is a tibble with columns `name`, `storage`, `format`,
`label` and `label_set`. Text fields hold `""` when the file has none.

Code that compares with labels, as in `region == "South"`, reads more
clearly than code that compares with codes. For that, read with
`factors = TRUE`, at the cost of `.a` to `.z` in labelled columns:

```r
labelled <- dtaparser::read_dta("survey.dta", factors = TRUE)
labelled$region       # a factor: North South South East West North
labelled$region == "South"  # FALSE TRUE TRUE FALSE FALSE FALSE
```

Five functions read back what the file says about a column:

```r
dtaparser::var_label(df$income)  # "Monthly income"
dtaparser::na_tag(df$income)     # NA "d" NA NA "r" NA
dtaparser::is_tagged_na(df$income, "r") # FALSE FALSE FALSE FALSE TRUE FALSE
dtaparser::val_labels(df$income) # Don't know = NA, Refused = NA (.d and .r)
dtaparser::val_label(df$income)  # NA "Don't know" NA NA "Refused" NA
unlist(dtaparser::var_label(df)) # region "Region", age "Age in years", ...
```

`na_tag(x)` gives each value's letter (`NA` for numbers and for `.`),
and `is_tagged_na(x, tag)` says which values are `.a` to `.z`, or the
letters in `tag`. An integer, logical or factor gives `NA`
throughout, since it cannot hold a letter. `var_label(x)` gives the
variable label, and `val_labels(x)` the value labels: the codes, named
by their text. Given a data frame, both give a list with one element
per column. `val_label(x, values = x)` gives the text of each value,
matching `.a` to `.z` by letter, so it says why each missing value is
missing. A factor's levels are its labels, so it has no `val_labels()`:

```r
dtaparser::val_labels(df$region)       # North = 1, South = 2, East = 3, West = 4
dtaparser::val_label(df$region)        # "North" "South" "South" "East" "West" "North"
dtaparser::val_labels(labelled$region) # NULL
```

The names are haven's and labelled's. haven's `na_tag()` stops on
anything but a double, and labelled's `val_labels()` and `val_label()`
read only its `haven_labelled` class, so on dtaparser's columns they
give `NULL`. dtatools has its own `val_labels()` and `val_label()` for
`dta_num` columns; with both packages attached, write
`dtaparser::val_label()` or `dtatools::val_label()`.

`tagged_na(x)` makes `.a` to `.z`, for values and labels of your own.
It takes a character vector of letters `"a"` to `"z"` and keeps its
names, so it can build a labels vector:

```r
labels <- c(No = 0, Yes = 1, dtaparser::tagged_na(c(Refused = "r", "Don't know" = "d")))
x <- structure(c(1, dtaparser::tagged_na("r"), 0, NA), labels = labels)
dtaparser::val_label(x)  # "Yes" "Refused" "No" NA
```

haven's `tagged_na()` drops names, so with haven attached too, write
`dtaparser::tagged_na()`. It also takes its letters as `...` and makes
a tag from any character, where dtaparser's takes one vector and only
`"a"` to `"z"`.

R's comparisons give `NA` for a missing value. For comparisons that
follow Stata's missing-value order instead (numbers < `.` < `.a` < ...
< `.z`), `missing_rank(x)` gives each value's place in it: 0 for a
number, 1 for `NA` or `NaN`, and 2 to 27 for `.a` to `.z`. It returns a
plain integer vector, never `NA`, so Stata's `x > .a` is one line:

```r
x <- c(5, NA, dtaparser::tagged_na(c("a", "d")))
dtaparser::missing_rank(x)                                         # 0 1 2 5
dtaparser::missing_rank(x) > dtaparser::missing_rank(dtaparser::tagged_na("a"))  # FALSE FALSE FALSE TRUE
```

It takes doubles, integers, logicals, `Date`, `POSIXct` and labelled
columns. Integers and logicals hold no letters, so they rank only 0 or
1. Every number ranks 0, so compare numbers with each other as usual.

R's grouping and matching treat every `NA` as one value, so they put
`.` and `.a` to `.z` together. These all do: base `unique()`,
`duplicated()`, `match()`, `%in%`, `table()`, `factor()` and
`split()`; vctrs' `vec_unique()`, `vec_group_id()` and `vec_in()`; and
dplyr's `group_by()`, `distinct()`, `count()` and joins, where an `.a`
row matches both `.a` and `.b` rows of the other table. Sorting,
subsetting, `ifelse()`, `if_else()`, arithmetic and `bind_rows()` keep
each letter. To group or join by the letter too, add it as a column of
its own. datakit's `datakit_by()` does that: it returns each column it
is given and, beside each one that can hold a letter, `<name>_letter`
(`na_tag()` of it). dplyr splices the result into columns:

```r
library(dplyr)
x <- c(1, dtaparser::tagged_na("a"), dtaparser::tagged_na("b"), NA)
unique(x)                                    # 1 NA: the letters merged
d <- tibble::tibble(x = x, w = 1:4)
count(d, x, letter = dtaparser::na_tag(x))   # 1, .a, .b and . apart
count(d, datakit::datakit_by(x))             # the same, as x and x_letter
d |> group_by(datakit::datakit_by(x)) |> summarise(w = sum(w), .groups = "drop")
lookup <- tibble::tibble(x = c(dtaparser::tagged_na("a"), NA), why = c("refused", "skipped"))
d |> mutate(datakit::datakit_by(x)) |>
  left_join(mutate(lookup, datakit::datakit_by(x)), by = c("x", "x_letter"))
```

`summarise()` keeps `x`'s letters, but by default it drops the last
grouping column, the letter column, so give `.groups = "drop"` (or a
later grouped step merges the letters again). `.by =` and `join_by()`
take names, not calls: `summarise(d, n = n(), .by = datakit_by(x))`
fails with "object 'x' not found", so `mutate()` first and name both
columns. Keep a join's default `na_matches = "na"`: with `"never"`, the
`NA` letter column of every number matches nothing. The columns that
get a letter column are doubles, labelled doubles, `Date` and `POSIXct`;
an existing column with the letter column's name is replaced, as for
any named result in dplyr.

`drop_labels(x)` takes off a column's value labels and variable label
and keeps everything else, for copying a column without its labels as
Stata's `gen y = x` does. A labelled column becomes its plain codes,
`.a` to `.z` kept; a `Date` stays a `Date` and a `POSIXct` keeps its
time zone, where `as.vector(x)` would give bare numbers. A column with
no labels comes back as it is:

```r
when <- structure(as.Date("2024-01-31"), label = "Interview date")
dtaparser::drop_labels(when)         # "2024-01-31", a Date with no label
dtaparser::na_tag(dtaparser::drop_labels(df$income))  # NA "d" NA NA "r" NA
```

### Labelled columns

A column with value labels is a `dtaparser_labelled`: its codes, with
the labels as attributes. vctrs drops attributes from plain vectors
when it combines them, so dplyr's `bind_rows()`, `case_when()` and
`if_else()` would lose a plain `labels` attribute; the class keeps it.
`with_labels(x, labels, label = NULL)` makes one from your own codes:

```r
x <- dtaparser::with_labels(c(1, 0, dtaparser::tagged_na("r"), 1, NA),
                            c(No = 0, Yes = 1, dtaparser::tagged_na(c(Refused = "r"))))
x                  # 1 [Yes] 0 [No] NA(r) [Refused] 1 [Yes] NA
x == 1             # TRUE FALSE NA TRUE NA
as.character(x)    # "Yes" "No" NA "Yes" NA
table(x)           # No 1, Yes 2: no missing value is a level
pooled <- dplyr::bind_rows(df, df)  # two files stacked
dtaparser::val_labels(pooled$region)  # North = 1, South = 2, East = 3, West = 4
```

- Missing values, `.` and `.a` to `.z` alike, are `NA` to R.
  `val_label(x)` says why each is missing; `count(d, val_label(x))`
  counts them by reason, since `count(d, x)` puts them in one group.
- Comparisons and `%in%` use the codes, and a label stands for its code
  in `==`, `!=` and assignment: `x == "Yes"`, `x[i] <- "No"`,
  `d[i, x] := "Refused"`. A missing value's label is an error in `==`,
  since `NA` compares as `NA`: write `is_tagged_na(x, "r")`. `%in%`
  compares codes with text and finds nothing, so write
  `val_label(x) %in% c("Yes", "No")`. Arithmetic and summaries give
  plain numbers.
- The survey package sees a number: `svymean(~x, design)` averages the
  codes. For the share of each answer, write
  `svymean(~factor(x), design, na.rm = TRUE)`.
- Combining two columns whose labels give one code two texts is an
  error; relabel one with `with_labels()` first.
- `as.numeric(x)` gives the plain codes. Base `ifelse()` drops the class;
  `dplyr::if_else()` keeps it.

`?with_labels` has the rest: casting, `:=`, and why a new code keeps
the old code's label.

## From a do-file to R

datakit's `:=` works on any data frame or tibble, so a do-file can
become an R script one line at a time without dibbles. A translated
script starts with `library(datakit)`, which also gives dtaparser's
`read_dta`, `save_dta`, and label functions, after dplyr and tidyr if it
uses them: attached last, datakit's `:=` masks rlang's,
which dplyr re-exports. It is the same `:=` as dtatools' (dtatools
re-exports it), but on a data frame it follows R's rules: missing values compare as `NA`, and `NA` in `i`
selects no row. Compare with labels, which needs `factors = TRUE`:

```r
df <- dtaparser::read_dta("survey.dta", factors = TRUE)
df[age >= 40, older] := 1                      # gen older = 1 if age >= 40
df$older                                       # NA 1 NA 1 1 NA
df[income > 2000, high] := 1                   # missing incomes are left out
df$high                                        # 1 NA NA NA NA 1
df[region == "East", region] := "South"        # replace region = 2 if region == 3
df[, n, by = region] := .N                     # bysort region: gen n = _N
df$n                                           # 2 3 3 3 1 2
df[, avg, by = region] := mean(income, na.rm = TRUE)  # egen avg = mean(income), by(region)
df$avg                                         # 2650 1850 1850 1850 NaN 2650
```

Where Stata and R differ, the line follows R:

- `income > 2000` is `NA` where income is missing, so those rows are
  not selected. In Stata they would be, since missing values are larger
  than every number. Add `| is.na(income)` to keep Stata's answer.
- A new column is `NA` on the rows `i` leaves out, and `NaN` and `Inf`
  stay as they are.
- A column widens when it cannot hold the new values, as `replace`
  promotes storage: logical to integer to double. An integer column
  given whole numbers stays integer.
- A factor column takes labels. A label that is not a level is an error,
  so a typo cannot add a category; add a level first with
  `levels(df$region) <- c(levels(df$region), "Abroad")`. A number is an
  error too. Beware `i`: `region == 3` on a factor compares with the
  level text and matches nothing, without an error.
- `by` puts `NA`, `NaN` and each of `.a` to `.z` in a group of its own,
  as `bysort` does.
- A data.table is an error; use its own `dt[i, name := value]`.

The rest is as in [Make and change columns](#make-and-change-columns):
`by`, `.N`, the forms of `name`, `NULL` to drop a column, and where R
finds `:=` when rlang or data.table is attached. Without dtatools,
attach datakit or bind `` `:=` <- datakit::`:=` ``. See
`?datakit::":="`.

datakit ships a file for the Raven language server,
`inst/raven/nse.toml`, which says that `i`, `by` and the value of
`d[i, name, by = g] := value` are evaluated among `d`'s columns, so
Raven can treat the names in them as columns rather than variables.
dtatools ships the same file.

To save a snapshot for comparison with Stata's output, write the data
frame with `dtaparser::save_dta()`; dates, labelled columns and `.a` to
`.z` written by `:=` read back as they were (see
[Plain R types](#plain-r-types-dtaparser)).

## Fixed-width files with a SAS setup file

Some surveys are published as fixed-width text with a SAS program, the
*setup file*, that says where each variable sits. CDC publishes the
National Survey of Family Growth this way, from 1973 to 2017-2019.
`read_fixed_width()` reads such data through its setup file: columns
from `INPUT`, variable labels from `LABEL`, value labels
from `PROC FORMAT` and `FORMAT`, record types from
`IF rec_type < 5 THEN DELETE; ELSE INPUT ...`, and the setup's
*missing-value recodes*, such as `IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;`.

It lives in datparser, a package of its own that needs neither
dtaparser nor datakit, and datakit includes it. The two differ in one
way: datparser gives a column with value labels as a plain integer or
double vector with a `labels` attribute, and datakit's
`read_fixed_width()` gives it as a `dtaparser_labelled`, as
`read_dta()` does, whose labels survive `x[i]` and dplyr and whose
`.a` to `.z` `val_label()` and `na_tag()` read. The examples below use
datakit's; datparser's reads the same values (see
[datparser alone](#datparser-alone)).

```r
writeLines(c(
  "PROC FORMAT;",
  "  VALUE kidsf 0='(0) None' 98='(98) DK' 99='(99) Not ascertained';",
  "DATA;",
  "INPUT ID 1-3 KIDS 4-5;",
  "LABEL KIDS = 'Number of children';",
  "IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;",
  "FORMAT KIDS kidsf.;"
), "survey.sas")
writeLines(c("001 2", "00298", "00399", "004 0"), "survey.dat")
```

By default the recodes apply as the setup writes them, so 98 and 99 are
`NA`, and the columns are as `read_dta()` returns them:

```r
df <- datakit::read_fixed_width("survey.dat", "survey.sas")
df$KIDS               # 2 NA NA 0
dtaparser::var_label(df$KIDS) # "Number of children"
```

`recodes = "tagged"` keeps why each value is missing, as labelled
missing values: per variable, the codes recoded to `.` become haven's
tagged NAs `.a`, `.b`, ... in the order the setup names them, and each
code's value label moves to its letter:

```r
df <- datakit::read_fixed_width("survey.dat", "survey.sas", recodes = "tagged")
dtaparser::na_tag(df$KIDS)     # NA "a" "b" NA
is.na(df$KIDS)                 # FALSE TRUE TRUE FALSE
dtaparser::val_label(df$KIDS)  # NA "(98) DK" "(99) Not ascertained" "(0) None"
dtaparser::na_tag(dtaparser::val_labels(df$KIDS)) # (0) None = NA, (98) DK = "a", (99) ... = "b"
```

A letter means what that variable's labels say: `.a` is 98 "DK" here,
but in a variable whose setup recodes 97 "Refused" first, `.a` is
"Refused". `recodes = "none"` ignores the recodes, keeping the codes as
numbers.

### datparser alone

datparser reads the file in memory, with its own copy of the Rust
core, and gives labelled columns as plain vectors:

```r
d <- datparser::read_fixed_width("survey.dat", "survey.sas", recodes = "tagged")
class(d$KIDS)           # "numeric"
attr(d$KIDS, "labels")  # (0) None = 0, (98) DK = NA, (99) Not ascertained = NA
dtaparser::na_tag(attr(d$KIDS, "labels")) # NA "a" "b"
```

Numeric columns take the smallest type that holds their values, and
records shorter than the setup's columns read as blank (`NA`).
Statements the reader does not run, such as other data-step code or a
range in `VALUE`, are skipped with one warning; the tibble's
`warnings` attribute lists them all. A `LENGTH` statement for numbers, which sets only how SAS stores them, is skipped without one. A variable label with stray quotes
inside it, such as `X = "WHETHER " SAME AS LAST MONTH" WAS ANSWERED"`
in CDC's 2011-2013 to 2015-2017 setups, is read from its first quote to
its last, without a warning. `col_select`, `skip` and `n_max` work as
in `read_dta()`: only the columns selected are read and warned about,
and `skip` and `n_max` count the records the setup keeps.

CDC's setups from 2002 on differ in two ways, and `read_fixed_width()`
reads both. The 2002 setups come in three files (`2002FemPregInput.sas`,
`2002FemPregVarLabel.sas`, `2002FemPregValueLabel.sas`); give `setup`
the paths in that order, and they are read as one setup. A statement
may not run from one file into the next, and errors and warnings name a
file by its place (`"file 2 line 8"`):

```r
writeLines(c("DATA;", "INPUT ID 1-3 KIDS 4-5;", "RUN;"), "input.sas")
writeLines(c(
  "PROC FORMAT;",
  "  VALUE kidsf 0='(0) None' 98='(98) DK';",
  "RUN;",
  "FORMAT KIDS kidsf.;"
), "labels.sas")
df <- datakit::read_fixed_width("survey.dat", c("input.sas", "labels.sas"),
                                  recodes = "none")
attr(df$KIDS, "labels")  # (0) None = 0, (98) DK = 98
```

From 2006-2010 on, CDC puts the `PROC FORMAT` step and the `FORMAT`
statement each in a block comment (`/* ... */`), so that SAS users
without CDC's format catalog can run the file as published. The value
labels are still there, so by default a comment that holds nothing but
a `PROC FORMAT` step or a `FORMAT` statement is read as code; a comment
that only mentions them stays a comment. `commented_formats = FALSE`
reads every comment as a comment, and those files then have no value
labels:

```r
writeLines(c(
  "/*", "PROC FORMAT;", "  VALUE kidsf 0='(0) None' 98='(98) DK';", "*/",
  "DATA;", "INPUT ID 1-3 KIDS 4-5;",
  "/*", "FORMAT KIDS kidsf.;", "*/"
), "commented.sas")
df <- datakit::read_fixed_width("survey.dat", "commented.sas", recodes = "none")
attr(df$KIDS, "labels")  # (0) None = 0, (98) DK = 98
df <- datakit::read_fixed_width("survey.dat", "commented.sas", recodes = "none",
                                  commented_formats = FALSE)
attr(df$KIDS, "labels")  # NULL
```

## Parquet files

datakit's `read_parquet()` and `save_parquet()` read and write Parquet
files that keep what a `.dta` file says: value labels, variable labels,
display formats, `.a` to `.z`, the data label and notes, and also factor
levels and time zones. `read_parquet()` returns what
`dtaparser::read_dta()` returns, and a tibble `read_dta()` gave comes
back `identical()` after `save_parquet()`. arrow and nanoparquet each
export a `read_parquet()` too: where either is attached after datakit,
write `datakit::read_parquet()`. An argument only arrow's has, such as
`as_data_frame`, then fails as an unused argument. The files are plain
Parquet that pyarrow, polars, DuckDB, arrow and nanoparquet read;
[docs/parquet.md](parquet.md) says what each of them sees, and gives the
file's specification. Only flat tables are read and written: for lists,
maps or structs, use arrow. The open-source projects studied for this
code, and the codec crates dtaparser compiles in, are listed with their
licenses in [docs/acknowledgements.md](acknowledgements.md).

Contents:
[Install](#parquet-install) ·
[Read a Parquet file](#read-a-parquet-file) ·
[Read some columns](#read-some-columns-of-a-parquet-file) ·
[Read a range of rows](#read-a-range-of-rows-of-a-parquet-file) ·
[Schema and metadata](#a-parquet-files-schema-and-metadata) ·
[Labels](#labels-in-parquet-files) ·
[Dates and time zones](#dates-and-time-zones-in-parquet-files) ·
[Write a Parquet file](#write-a-parquet-file) ·
[Write labels](#write-labels-to-a-parquet-file) ·
[Keep .a to .z](#keep-a-to-z-in-a-parquet-file) ·
[Categoricals with .a to .z](#categoricals-that-hold-a-to-z) ·
[Files from other tools](#parquet-files-from-other-tools) ·
[What each type becomes](#what-each-parquet-type-becomes-in-r) ·
[Coming from arrow or nanoparquet](#coming-from-arrow-or-nanoparquet)

### Parquet: install

Parquet is in datakit, which needs dtaparser; it reads and writes
through dtaparser's Rust core, with no arrow or other Parquet package.
Install the two from the project's R package repository (binaries for
macOS, Windows and Ubuntu 24.04; see [Install](#install) for Ubuntu's
URL):

```r norun
install.packages(c("dtaparser", "datakit"), repos = c("https://jbearak.github.io/dta-parser", "https://cloud.r-project.org"))
library(datakit)
```

dtatools installs both too. Elsewhere, build from a clone, dtaparser
first; that needs Rust (`cargo`, from [rustup.rs](https://rustup.rs))
and a C compiler, which builds the zstd library:

```sh
R CMD INSTALL dta-parser/r/dtaparser
R CMD INSTALL dta-parser/r/datakit
```

A source package (`datakit_*.tar.gz` and `dtaparser_*.tar.gz` from the
releases) carries the Rust crates it needs and builds offline; an
install from GitHub fetches them from crates.io. If the build stops
with "building needs cargo", see [Troubleshooting](#troubleshooting).

### Read a Parquet file

This writes the example file as Parquet and reads it back:

```r
library(datakit)

df <- read_dta("survey.dta")
save_parquet(df, "survey.parquet")
back <- read_parquet("survey.parquet")
identical(back, df)   # TRUE
back$income           # 2100 NA(d) [Don't know] 1850 NA NA(r) [Refused] 3200
class(back$region)    # "dtaparser_labelled" "vctrs_vctr"
class(back$interviewed) # "Date"
```

Every missing value is `NA`; in doubles `.a` to `.z` keep their letter
(`na_tag()`), and a double `NaN` stays `NaN`. Columns with value labels
are `dtaparser_labelled` (see [Labelled columns](#labelled-columns)),
and `factors = TRUE` makes them factors as in `read_dta()`, except a
categorical holding `.a` to `.z` ([below](#categoricals-that-hold-a-to-z)),
which stays a labelled double. String
columns come back packed, as `read_dta()`'s do. `file` may also be a raw
vector holding a whole file. [What each type becomes](#what-each-parquet-type-becomes-in-r)
gives the type of each Parquet column.

### Read some columns of a Parquet file

`col_select` takes names, 1-based positions or a tidyselect
expression, and returns the columns in the order given; only those
columns are read from the file:

```r
read_parquet("survey.parquet", col_select = c("income", "id"))    # income, id
read_parquet("survey.parquet", col_select = c(4, 1))              # income, id
read_parquet("survey.parquet", col_select = tidyselect::starts_with("i"))  # id, income, interviewed
```

An unknown name is an error that lists the file's columns:
`column "weight" is not in the file; its columns are "id", "region", ...`.

### Read a range of rows of a Parquet file

`skip` and `n_max` work as in `read_dta()`. Only the row groups that
hold the rows are read, and within them only the pages that do, so a
window of a large file is quick:

```r
read_parquet("survey.parquet", skip = 2, n_max = 2)$id   # 3 4
nrow(read_parquet("survey.parquet", skip = 4, n_max = 10))  # 2
nrow(read_parquet("survey.parquet", skip = 10))             # 0
```

A window that runs past the last row gives the rows there are, and a
`skip` past the end gives a tibble with no rows; neither is an error.

### A Parquet file's schema and metadata

`read_parquet_info()` reads the footer only. It gives the number of
rows, the row groups, the writer, the codecs, the data label and notes,
per column the R type `read_parquet()` gives it, and the footer's
key-value entries:

```r
info <- read_parquet_info("survey.parquet")
info$rows          # 6
info$compression   # "snappy"
info$label         # "Household survey (example)"
info$columns$name          # "id" "region" "age" "income" "interviewed" "comment"
info$columns$r_type        # "integer" "dtaparser_labelled" "integer" "dtaparser_labelled" "Date" "character"
info$columns$physical_type # "INT32" "INT32" "INT32" "DOUBLE" "INT32" "BYTE_ARRAY"
info$columns$value_labels  # NA "region" NA "income" NA NA
info$key_value$key         # "dta" "ARROW:schema"
```

`key_value` is a tibble of every key-value entry, `key` and `value`
(the value as text): here the `dta` entry with the labels
([the profile](parquet.md#the-profile)) and arrow's schema; a file from
another tool has that tool's entries.

`role` is `"nested"` for a list, map or group, which is not read, and
`storage` and `logical` show what a column written as DOUBLE because it
holds `.a` to `.z` was: `"byte"`, `"int"`, `"long"` or `"float"`, or
`"date"` or `"timestamp"`. `logical` is `"categorical"` for a
categorical, whether it is text or, holding `.a` to `.z`, DOUBLE.

### Labels in Parquet files

The variable label is attribute `label`, value labels attribute
`labels`, the data label and notes attributes of the tibble, as for
`read_dta()`, and the same functions read them:

```r
var_label(back$age)        # "Age in years"
val_label(back$income)     # NA "Don't know" NA NA "Refused" NA
attr(back, "label")        # "Household survey (example)"
read_parquet("survey.parquet", factors = TRUE)$region  # North South South East West North
```

Other tools do not read labels: they see the codes. A file from another
tool has none, unless it was written by `save_parquet()` (or another
library writing the same `dta` entry; see [docs/parquet.md](parquet.md#the-profile)).

### Dates and time zones in Parquet files

A `Date` is a Parquet DATE, and a `POSIXct` a TIMESTAMP in
microseconds, with its time zone kept:

```r
visits <- tibble::tibble(
  at = as.POSIXct(c("2024-03-01 09:30:00", "2024-03-01 17:05:00"), tz = "America/New_York")
)
save_parquet(visits, "visits.parquet")
v <- read_parquet("visits.parquet")
v$at                  # "2024-03-01 09:30:00 EST" "2024-03-01 17:05:00 EST"
attr(v$at, "tzone")   # "America/New_York"
```

arrow, pyarrow and polars read the zone too. A `POSIXct` is always an
instant, so R writes no timestamp without a zone: one with no `tzone`
(or `tzone = ""`, the session's zone) is written as an instant adjusted
to UTC, the same moment, and comes back with no `tzone` attribute, shown
in the session's zone. Two cases are written as
numbers so that they come back unchanged: a `Date` with a fraction of a
day, and a `POSIXct` whose seconds no whole number of microseconds gives
back exactly (such as `Sys.time()`'s, at times). Those columns are
DOUBLE days or seconds since 1970, with `logical` `"date"` or
`"timestamp"` in `read_parquet_info()`; other tools see numbers.

Timestamps from other tools come back as `POSIXct`, INT96 ones too.
One in nanoseconds that is not a whole number of microseconds is an
error that says to pass `timestamps = "truncate"`, which drops the
nanoseconds below a microsecond. The zone is the one `save_parquet()`
recorded, else the one the file's arrow schema gives (arrow's, pyarrow's
and polars' zoned timestamps), else UTC. A clock time without a zone,
as polars and pandas write a naive datetime (`TIMESTAMP(..., local)`),
comes back as that clock reading in UTC. A TIME (a clock time without a
date) comes back as a `difftime` in seconds since midnight.

### Write a Parquet file

`save_parquet(data, file)` writes any data frame: what `save_dta()`
writes, and also factors with their levels (ordered or not), logicals,
time zones, text of any length, lists of raw vectors (binary) and
bit64's `integer64`. It returns `data` invisibly. Compression is snappy
by default, which pyarrow, polars and DuckDB read fastest;
`compression` takes `"snappy"`, `"zstd"`, `"gzip"`, `"lz4_raw"` or
`"none"`, and `compression_level` the codec's level. zstd makes a file
smaller (by about a sixth for survey data) and slower to read.
Row groups hold up to 262,144 rows and about 1 GiB of values;
`row_group_size` sets the rows:

```r
save_parquet(df, "small.parquet", compression = "snappy", row_group_size = 2)
read_parquet_info("small.parquet")$row_groups$rows  # 2 2 2
```

A column of another type (a list that is not of raw vectors, a nested
data frame, complex numbers, `POSIXlt`, `difftime`) is an error naming
it, and an unknown `compression` an error that lists the codecs.
[docs/parquet.md](parquet.md#defaults-and-the-measurements-behind-them)
gives the measurements behind the defaults.

### Write labels to a Parquet file

Labels are written from the same attributes `save_dta()` reads: `label`
and `format` on a column; `labels` (with `label_set`, else the column's
name) on a labelled column; `label`, `notes`, `characteristics` and
`sort_order` on the data frame:

```r
smoking <- tibble::tibble(
  smoker = with_labels(c(1, 0, tagged_na("d")),
                       c(No = 0, Yes = 1, tagged_na(c("Don't know" = "d"))),
                       label = "Smokes daily")
)
attr(smoking, "label") <- "Smoking"
attr(smoking, "notes") <- "Wave 2 only."
save_parquet(smoking, "smoking.parquet")
s <- read_parquet("smoking.parquet")
s$smoker              # 1 [Yes] 0 [No] NA(d) [Don't know]
val_labels(s$smoker)  # No = 0, Yes = 1, Don't know = NA(d)
attr(s, "notes")      # "Wave 2 only."
```

Columns that share a label set must have the same labels, as for
`save_dta()`.

### Keep .a to .z in a Parquet file

`.a` to `.z` are written as tagged NaNs, the bits R holds them in, so a
column holding any is DOUBLE. They come back with their letters, from
`read_parquet()` and also from arrow and nanoparquet:

```r
na_tag(read_parquet("survey.parquet")$income)   # NA "d" NA NA "r" NA
```

Other tools see NaN, which some count as a value rather than a missing
one (DuckDB SQL, polars: [docs/parquet.md](parquet.md#what-other-tools-see-in-our-files)
gives the query that treats them as missing). For files meant for those
tools, `missing_letters = FALSE` writes `.a` to `.z` as plain nulls,
and the letters are lost:

```r
save_parquet(df, "nulls.parquet", missing_letters = FALSE)
na_tag(read_parquet("nulls.parquet")$income)    # NA NA NA NA NA NA
```

### Categoricals that hold .a to .z

TypeScript's datakit writes a categorical that holds `.a` to `.z` as
DOUBLE level numbers (1 for the first level) with tagged
NaNs for the letters ([docs/parquet.md](parquet.md)). A factor cannot
hold the letters, so `read_parquet()` gives such a column as a
`dtaparser_labelled` double: the numbers 1 to k, `.a` to `.z` as tagged
NAs, `labels` from its value label set (each level, and any labels on
letters) and attribute `label_set` the set's name. It stays a labelled
double with `factors = TRUE`, and gives no warning about lost letters.
For a column `grade` with levels low, mid and high, written by
TypeScript:

```r norun
g <- read_parquet("grades.parquet")$grade
g                        # 1 [low] NA(a) 3 [high] NA NA(z) 2 [mid]
attr(g, "label_set")     # "grade"
read_parquet_info("grades.parquet")$columns$logical   # "categorical"
```

A value that is not a level number (another tool rewrote the column,
say, and left 1.5 in it) reads as `NA`, with one warning per call that
names the column and the first such row read.

R has no categorical type that holds `.a` to `.z`, so `save_parquet()`
writes the column back as labelled numbers with its letters and value
label set, not as a categorical. TypeScript then reads it as labelled
numbers too.

In `.dta` files, TypeScript's datakit marks such columns with
`dtaparser_categorical`, which `read_dta()` reads as a labelled
double the same way when the rows read hold a letter, and as a factor
when they do not ([Plain R types](#plain-r-types-dtaparser)).

### Parquet files from other tools

`read_parquet()` reads the files pyarrow, pandas, polars, DuckDB,
arrow, nanoparquet, fastparquet and others write: the encodings
dictionary, PLAIN, RLE, the DELTA encodings and BYTE_STREAM_SPLIT, data
pages v1 and v2, and the codecs none, snappy, gzip, zstd, lz4_raw and
brotli. The one encoding not read is BIT_PACKED for values, which the
format has deprecated and current writers do not use; reading such a
column is an error (BIT_PACKED repetition and definition levels are
read).
A column that pandas, polars or arrow wrote as a category or factor (a
dictionary of strings in the file's arrow schema) is a factor:

```r
if (requireNamespace("arrow", quietly = TRUE)) {
  arrow::write_parquet(data.frame(f = factor(c("b", "a", "b"), levels = c("a", "b", "c"))), "from_arrow.parquet")
  levels(read_parquet("from_arrow.parquet")$f)            # "b" "a"
  levels(read_parquet("from_arrow.parquet", skip = 2)$f)  # "b"
}
```

Its levels are the distinct values of the rows read, in the order they
first appear, and it is not ordered: the file does not say which levels
the writer had or in what order. Reading another window of rows can
give other levels; reading every row gives them all. A file
`save_parquet()` wrote has every level, in order, whatever rows are
read. `factors` does not change these columns.

DECIMAL columns read as the nearest double to each value. A value with
more than 15 significant digits, which a double cannot give back, is an
error naming the column and row; `decimal = "character"` reads every
digit as text:

```r
if (requireNamespace("arrow", quietly = TRUE)) {
  price <- arrow::Array$create(c("2.50", "1234567890.123456789"))$cast(arrow::decimal128(19, 9))
  arrow::write_parquet(arrow::arrow_table(price = price), "prices.parquet")
  read_parquet("prices.parquet", n_max = 1)$price             # 2.5
  read_parquet("prices.parquet", decimal = "character")$price # "2.500000000" "1234567890.123456789"
  # read_parquet("prices.parquet") is an error: row 2 has 19 significant digits
}
```

Unsigned 8- and 16-bit integers read as integers; unsigned 32- and
64-bit ones follow the INT64 rules, so `int64 = "character"` keeps every
digit (and an unsigned value of 2^63 or more is an error for
`int64 = "integer64"`, which cannot hold it).

What this version does not read, each an error that names the column
and its type: FLOAT16, INTERVAL, the Hadoop framing of LZ4, LZO,
encryption. Values encoded BIT_PACKED are an error too. Nested columns (lists, maps, structs) are an error unless
`col_select` leaves them out or `nested = "skip"` is given. Datasets of
many files, Hive partitions and predicate pushdown are not part of
datakit; use arrow's `open_dataset()` or DuckDB for those.

### What each Parquet type becomes in R

Every conversion is exact or an error that names the column, the row
and the option that keeps the value, with one exception: DECIMAL reads
by default as the nearest double, which may not equal the decimal
value exactly (`decimal = "character"` keeps every digit).

| Parquet | R |
|---|---|
| INT32: INT(8), INT(16) or none | integer; double where `.a` to `.z` appear in the rows read of a column written wider for them; a value of -2147483648, R's integer `NA`, is an error |
| unsigned 8 and 16 bits | integer |
| INT64, unsigned 32 and 64 bits | `int64 = "double"` (default): double, and a value a double does not hold exactly is an error naming the column, the row and the option; `"integer64"` (bit64) or `"character"` keep every digit (`"character"` only, for unsigned values of 2^63 or more) |
| FLOAT, DOUBLE | double; `.a` to `.z` are tagged NAs, other NaN stay NaN |
| DECIMAL, precision 15 or less | double, the nearest to each value |
| DECIMAL, precision above 15 | `decimal = "double"` (default): double, and a value with more than 15 significant digits is an error naming the column, the row and `decimal = "character"`; `"character"` keeps every digit |
| BOOLEAN | logical |
| DATE | `Date` |
| TIMESTAMP (milli-, micro-, nanoseconds), INT96 | `POSIXct`, in the zone `save_parquet()` recorded, else the one in `ARROW:schema`, else UTC; nanoseconds that are not whole microseconds are an error naming `timestamps = "truncate"` |
| TIME (milli-, micro-, nanoseconds) | `difftime` in seconds since midnight |
| STRING, ENUM, JSON | character |
| BYTE_ARRAY or FIXED_LEN_BYTE_ARRAY without a text annotation, UUID | a list of raw vectors, `NULL` for null |
| a categorical `save_parquet()` wrote | factor, ordered if it was, every level kept |
| a categorical holding `.a` to `.z` (DOUBLE level numbers, which TypeScript's datakit writes) | `dtaparser_labelled` double: codes 1 to k, `.a` to `.z` as tagged NAs, `labels` and `label_set` from its value label set; `factors = TRUE` leaves it so; a value that is not a level number is `NA` with a warning |
| a dictionary of strings in `ARROW:schema`, with no levels in the profile (an arrow factor, a pandas `category`, a polars `Categorical`) | factor, unordered; levels are the distinct values of the rows read, in order of first appearance |
| a dictionary of another type in `ARROW:schema` | its values' type, by the rows above |
| FLOAT16, INTERVAL | not read: an error naming the column and type |

### Coming from arrow or nanoparquet

| arrow | nanoparquet | datakit | what changes |
|---|---|---|---|
| `read_parquet(file)` | `read_parquet(file)` | `read_parquet(file)` | labels, `.a` to `.z`, formats, notes kept; a tibble of `read_dta()`'s types |
| `read_parquet(file, col_select = c(a, b))` | `read_parquet(file, col_select = c("a", "b"))` | `read_parquet(file, col_select = c(a, b))` | names, positions or tidyselect; an unknown name lists the file's columns |
| `open_dataset(file) \|> ... \|> head(n)` or `$ReadRowGroup()` | (no rows) | `read_parquet(file, skip = 100, n_max = 50)` | only the pages that hold the rows are read |
| `read_parquet(file, as_data_frame = FALSE)` | (none) | (none) | no Arrow tables; use arrow for those |
| `ParquetFileReader$create(file)$GetSchema()` | `read_parquet_schema(file)`, `read_parquet_info(file)` | `read_parquet_info(file)` | one call: rows, row groups, codecs, key-value entries, labels, and the R type of each column |
| `write_parquet(x, sink)` (snappy) | `write_parquet(x, file)` (snappy) | `save_parquet(x, file)` (snappy) | labels, letters, zones, ordered factors written; returns `x` invisibly |
| `compression = "zstd", compression_level = 3` | `compression = "zstd", options = parquet_options(compression_level = 3)` | `compression = "zstd", compression_level = 3` | |
| `chunk_size = n` | `options = parquet_options(num_rows_per_row_group = n)` | `row_group_size = n` | |
| `options(arrow.int64_downcast = FALSE)` | `options = parquet_options(read_int64_type = "integer64")` | `int64 = "integer64"` | a lossy double is an error, not a silent change |
| `options(arrow.use_threads = FALSE)` | (one thread) | `options(dtaparser.threads = 1)` | |

arrow writes R attributes into its own `r` metadata entry, which only
arrow reads; datakit neither writes nor reads it, so labels written by
arrow are not read here, and arrow's `haven_labelled` columns come back
as plain numbers. nanoparquet drops labels and time zones.

## polars frames

datakit's `read_parquet_pl()`, `read_dta_pl()`, and `read_fixed_width_pl()`
read into a polars DataFrame instead of a tibble. Each returns
`list(df, meta)`: the frame, and a `datakit_meta` holding what a polars
frame cannot, such as variable labels, display formats, value labels,
notes, and the data label. `save_parquet()` and `save_dta()` take the
frame and its `meta` back. The tibble functions in the sections above
are unchanged.

Contents:
[Install](#polars-install) ·
[Read into polars](#read-into-polars) ·
[.a to .z in a polars frame](#a-to-z-in-a-polars-frame) ·
[Save a polars frame](#save-a-polars-frame)

### polars: install

The polars functions need R 4.3 or later, nanoarrow from CRAN, and
polars from R-multiverse, since polars is not on CRAN:

```r norun
install.packages("nanoarrow")
install.packages("polars", repos = c("https://community.r-multiverse.org", "https://cloud.r-project.org"))
```

R-multiverse has binaries for macOS and Windows. On Linux, polars
installs from source: run `Sys.setenv(NOT_CRAN = "true")` first, and
the install downloads polars' prebuilt Rust library instead of
compiling it. datakit installs and works without either package; the
polars functions say which one is missing.

### Read into polars

```r polars
library(polars)

res <- read_parquet_pl("survey.parquet")
df <- res$df
meta <- res$meta
df$schema$income                         # Float64
meta$columns$income$label                # "Monthly income"
read_dta_pl("survey.dta")$df$schema$age  # Int8
```

In a `.dta` file, byte, int, long, float, and double become Int8,
Int16, Int32, Float32, and Float64; strN and text strLs become String;
a `%td` column becomes a Date, and a `%tc` column a Datetime in
milliseconds. `survey.parquet` was saved from a tibble, where byte
columns are R integers, so its `age` is Int32. `col_select`, `skip`, `n_max`, and `factors` work as in
`read_parquet()`; `factors = TRUE` makes each labelled column an Enum.
`read_fixed_width_pl(file, setup)` reads fixed-width text through its
SAS setup file into the same pair.

`meta` is a list with these fields: `label`, `notes`, `characteristics`, `sort`, `timestamp`,
`columns`, `value_labels`, `rows`, and `storage`. Change it as you
would any list. It does not follow polars operations: when you rename,
drop, or add a column, change `meta$columns` to match.

**Lifetime.** A frame read this way keeps its values in memory that
dtaparser allocated, and polars calls into dtaparser's library to free
it. Do not unload dtaparser (with `unloadNamespace()`, or by reloading
it during development) while such frames exist. datakit imports
dtaparser, so R does not unload it on its own.

### .a to .z in a polars frame

Every read keeps `.a` to `.z` in the frame. A
column holding any of them in the rows read is Float64, and each letter
is a NaN tagged with it: R's `NA_real_` with the letter's code in its
fifth byte, as `tagged_na()` makes. `.` is a null. An Int8, Int16,
Int32, or Float32 column holding letters is cast to Float64, and
`meta$storage` keeps its dtype, so that saving writes it back as byte,
int, long, or float when its values still fit. `letters = FALSE` reads
the letters as nulls instead, and the column keeps its dtype. These
functions read, make, and test letters:

- `na_tag_pl(x)`: the letter of each row of `x` (a column name, a
  polars expression or a Series), as an Enum of `".a"` to `".z"`, null
  where the row has none;
- `is_tagged_na_pl(x, letter = NULL)`: true where a row holds a letter,
  or the letter given;
- `tagged_na_pl(letter)`: an expression holding the letter, for
  anywhere polars takes one. `pl$lit(tagged_na("a"))` does not work:
  polars reads an R `NA` as a null;
- `is_missing(x)`, or `is_na(x)`: true where a row is `.` or one of
  `.a` to `.z`, as R's `is.na()` says;
- `datakit_by_pl(..., .suffix = "_letter")`: each column and its
  letters, to group and join with the letters kept apart.

```r polars
as.character(df$select(na_tag_pl("income"))$to_series()$to_r_vector())   # NA ".d" NA NA ".r" NA
df$filter(is_tagged_na_pl("income", ".d"))$get_column("id")$to_r_vector() # 2
na_tag(df$get_column("income")$to_r_vector())                              # NA "d" NA NA "r" NA
```

A Float64 Series turned into an R vector gives each letter as a tagged
`NA`, which `na_tag()` reads, as the last line shows. A letter is a
value in its row, so it follows the row through `$filter()`, `$sort()`,
`$join()`, and `$group_by()`, and it survives arithmetic: `x * 2` keeps
`.d` where `x` held it, as Stata's `gen y = x * 2` does.

**What polars counts.** polars treats a NaN as a number.
`$null_count()` and `$is_null()` see only `.`, `$count()` counts the
letters, and `$mean()` is NaN. `$fill_nan(NA)` makes every letter a
null, which is how R and Stata treat them:

```r polars
x <- pl$col("income")
df$select(x$null_count())$to_series()$to_r_vector()          # 1
df$select(x$count())$to_series()$to_r_vector()               # 5
df$select(x$fill_nan(NA)$count())$to_series()$to_r_vector()  # 3
df$select(x$mean()$is_nan())$to_series()$to_r_vector()       # TRUE
df$select(x$fill_nan(NA)$mean())$to_series()$to_r_vector()  # 2383.333
```

**The rules.** polars compares a NaN as a number greater than every
other and equal to every other NaN. `.` is a null, which polars treats
as missing. For `x <- pl$col("x")` and the rows `1, 5000, .a, .b, .`:

| expression | rows `$filter()` keeps |
|---|---|
| `x != 1` | 3: `5000`, `.a`, and `.b` |
| `x != 1 & x$is_not_null()`, R's `x != 1 & !is.na(x)` written naively | 3: `$is_not_null()` sees only `.` |
| `x != 1 & !is_na(x)` | 1: `5000` |
| `x$fill_nan(NA) != 1` | 1: `5000` |
| `x$is_null()` | `.` only |
| `x$is_nan()` | `.a` and `.b` only |
| `is_na(x)`, R's `is.na(x)` | `.`, `.a`, and `.b` |

So where R code tests `is.na()`, write `is_na()` (or `is_missing()`),
not `$is_null()`:

```r polars
ids <- function(rows) rows$get_column("id")$to_r_vector()
ids(df$filter(x != 1850 & x$is_not_null()))   # 1 2 5 6: the letters stay
ids(df$filter(x != 1850 & !is_na(x)))          # 1 6
ids(df$filter(x > 3000))                       # 2 5 6
ids(df$filter(x > 3000 & !is_na(x)))           # 6
```

`x > 3000` is true for a letter, as Stata's `income > 3000` is, since
Stata's missing values are greater than every number too;
`& !is_na(x)` leaves them out. `.` is a null, so a comparison is null
there and `$filter()` drops the row.

`is_na()` takes an R vector, a polars expression, or a Series. Given an
expression, it builds one, which works on number, Boolean, Decimal,
date and time, Categorical, and Enum columns. On a text column it would
count the text `"nan"` as missing, and on Binary, List, or Struct
columns polars refuses it: there, use `$is_null()`, or pass the Series,
which `is_na()` tests by its dtype:

```r polars
is_na(df$get_column("income"))$to_r_vector()   # FALSE TRUE FALSE TRUE TRUE FALSE
is_na(c(1, NA, tagged_na("a")))                # FALSE TRUE TRUE
```

rlang exports an `is_na()` (a test for one `NA`) and an `is_missing()`
(a test for a missing argument), and dtatools an `is_missing()` for its
columns, where `""` is missing text, as in Stata. R uses the one from
the package attached last: after `library(dtatools)` or `library(rlang)`
following `library(datakit)`, `is_missing()` is no longer datakit's.
Write `datakit::is_na()` to be sure.

**Grouping.** polars puts every NaN in one group, so `$group_by()`,
`$unique()`, and `$value_counts()` merge `.d` with `.r`.
`datakit_by_pl()` adds each column's letters as a column of its own,
in a list that polars takes spliced with `!!!`:

```r polars
df$group_by("income")$agg(pl$len())$height                   # 5: .d and .r in one group
df$group_by(!!!datakit_by_pl("income"))$agg(pl$len())$height # 6
df$with_columns(!!!datakit_by_pl("income"))$unique(subset = c("income", "income_letter"))$height  # 6
```

Each argument gets a letter column, all null for a column that is not
Float64. polars groups nulls together, so `.` is a group of its own.

**Joins.** A key holding letters joins as it groups: polars matches
every NaN with every other, so `.a` on one side meets both `.a` and
`.b` on the other, and `.`, a null, meets nothing unless the join says
`nulls_equal = TRUE`. To keep the letters apart, join on the key and
its letter column from `datakit_by_pl()`, with `nulls_equal = TRUE`.
Without it, a row with no letter, whose letter column is null, matches
nothing:

```r polars
k <- pl$col("k")
left <- pl$DataFrame(k = c(1, 2, 3, NA))$with_columns(
  pl$when(k == 2)$then(tagged_na_pl("a"))$when(k == 3)$then(tagged_na_pl("b"))$otherwise(k)$alias("k")
)
right <- left$with_columns(name = pl$lit(c("one", "a", "b", "dot")))
left$join(right, on = "k")$height                       # 5: 1 meets 1, and .a and .b meet each other
left$join(right, on = "k", nulls_equal = TRUE)$height   # 6: and . meets .
left <- left$with_columns(!!!datakit_by_pl("k"))
right <- right$with_columns(!!!datakit_by_pl("k"))
left$join(right, on = c("k", "k_letter"), nulls_equal = TRUE, maintain_order = "left")$get_column("name")$to_r_vector()
# "one" "a" "b" "dot"
left$join(right, on = c("k", "k_letter"), maintain_order = "left")$get_column("name")$to_r_vector()
# "a" "b": 1 and . have no letter, so they match nothing
```

**Set a letter** (Stata's `replace income = .r if age > 60`):

```r polars
df2 <- df$with_columns(
  pl$when(pl$col("age") > 60)$then(tagged_na_pl("r"))$otherwise(pl$col("income"))$alias("income")
)
as.character(df2$select(na_tag_pl("income"))$to_series()$to_r_vector())   # NA ".d" NA ".r" ".r" NA
```

In an integer column polars makes the result Float64, and the letter is
kept. To replace a letter with a value, test for it:
`pl$when(is_tagged_na_pl("income", ".d"))$then(0)$otherwise(pl$col("income"))`.
A new column (Stata's `gen y = .a`) is `tagged_na_pl("a")$alias("y")`.

**Sort as Stata does** (values, then `.`, then `.a` to `.z`):

```r polars
stata <- df$sort(pl$col("income")$fill_nan(NA), na_tag_pl("income"), nulls_last = c(TRUE, FALSE),
                 maintain_order = TRUE)
na_tag(stata$get_column("income")$to_r_vector())   # NA NA NA NA "d" "r"
ids(stata)                                         # 3 1 6 4 2 5
```

polars' own `df$sort("income")` puts `.` first and the letters last,
with no order among the letters.

**What loses them.** Only Float64 holds a letter: a cast to Float32 or
an integer type loses it, and so does `$fill_nan()`. When two letters
meet in arithmetic (`x + y`, both holding one), the result keeps one of
the two.

**Dates, timestamps, and categoricals.** A polars Date, Datetime, or Enum
cannot hold a NaN. A column of one of these types that holds `.a` to
`.z` in the rows read is read as numbers instead: a date as Stata's
days since 1960 (format `%td`), a timestamp as its milliseconds since
1960 (`%tc`), and a categorical as its level numbers from 1, labelled
by its value label set, as `read_parquet()` reads such a categorical.
`letters = FALSE` gives the Date, Datetime, or Enum, with the letters as
nulls.

### Save a polars frame

```r polars
save_parquet(df2, "survey_pl.parquet", meta = meta)
save_dta(df2, "survey_pl.dta", meta = meta)
na_tag(read_dta("survey_pl.dta")$income)   # NA "d" NA "r" "r" NA
```

The frame's letters are written as `.a` to `.z`, `meta`'s labels,
formats, and notes with them, and a column a read widened to Float64 is
written as its old type when its values still fit. `meta = NULL`, the
default, writes the frame alone; `missing_letters = FALSE` writes every
letter as `.`. A polars LazyFrame is an error: call `$collect()` on it
first. The other arguments are those of the tibble methods.

## Threads

Reading and writing large files uses up to three threads: workers decode and fill numeric columns while R makes the strings. On x86, where processors pair their hardware threads, the most is half the processor count, up to three. Reads that need a strL column, small reads and writes (under 16 MB of selected data) and every read on Windows use one thread. In our measurements the threads together used at most 15% more CPU time than one thread doing the same work.

Parquet reads and writes of 16 MB or more use two threads or more, which decode or compress column chunks while R makes the strings. Survey files use two: a third added less than half a thread's worth of speed. Larger work uses more: a read one thread per 176 MiB of values, up to eight, and a write one per 256 MiB, up to six. The rule and the numbers are in [docs/parquet.md](parquet.md#defaults-and-the-measurements-behind-them) and [bench/RESULTS.md](../bench/RESULTS.md#parquet).

Set `options(dtaparser.threads = 1)` to use one thread, or another number to change the most; the `DTA_THREADS` environment variable does the same when the option is unset. Under `R CMD check` (`_R_CHECK_LIMIT_CORES_` set), at most two are used.

## Troubleshooting

**Installation fails with "dtaparser: building needs cargo".** Install
Rust from [rustup.rs](https://rustup.rs), open a new terminal, and
install again. On Windows you also need Rtools.

**"dtatools needs dtaparser built from the same release".** The
installed dtaparser was built from a different checkout than dtatools.
Install `r/dtaparser` from the same checkout, restart R, then install
dtatools again.

**"x holds binary strLs, which dtaparser does not read".** The column
stores binary data (an image, say). Leave it out with `col_select`, or
read the file with the TypeScript package.

**"unsupported .dta release".** The file is not a `.dta` file, or its
release is older than 104 or newer than 119. See
[Releases](guide/releases.md).

**Accented letters are wrong.** The file is older than release 118;
pass `encoding = "latin1"` or `encoding = "utf-8"`.

**`x > 0` is `TRUE` where `x` is missing.** That is Stata's rule, which
dtatools follows on `dta_num` columns. Add `& !is_missing(x)`.

**A factor's codes changed after `save_dta`.** Stata has no factor
type, so `save_dta` writes codes 1 to k labelled with the levels. To
keep a file's own codes, read it with `factors = FALSE`.

**`save_dta` says a value does not fit.** The column's `storage`
attribute names a type too small for a value, usually after arithmetic
on a byte or int column. Set `attr(x, "storage") <- "double"` (or
`"long"`).

**A letter became `.` after `ifelse()` or `c()`.** Base functions that
build new doubles keep the letter; computing (arithmetic, math
functions, `dta_pmax()`) gives `.`. Reassign the code with `x[i] <- .d`.
Base `pmax()` and `pmin()` on a `dta_num` keep the last argument's
letter where every argument is missing; use `dta_pmax()` and
`dta_pmin()`.

## API reference

Each function has a help page (`?read_dta`). Exports:

- `read_dta(file, col_select = NULL, encoding = NULL, skip = 0, n_max = Inf)`:
  read a file into a dibble.
- `save_dta(data, file)`: write a data frame as release 118.
- `dibble(...)`, `as_dibble(x)`: build or convert a dibble.
- `d[i, name, by = ] := value`, `d[i, name] <- value`: make or change a
  column (`?"dibble-assign"`).
- `dta_num(x, labels, label, storage, format)`: a Stata numeric column.
- `dta_pmax(..., na.rm = FALSE)`, `dta_pmin(..., na.rm = FALSE)`:
  parallel maxima and minima whose missing results are `.`.
- `.a` ... `.z`: the 26 extended missing values.
- `is_missing(x)`, `is_tagged_missing(x, tag = NULL)`: which values are
  missing.
- `val_labels(x)`, `val_label(x, values)`, `labelbook(data)`: value labels.
- `tab(x, missing = FALSE)`, `dta_group_id(..., missing = FALSE)`,
  `dta_group_tag(..., missing = FALSE)`, `dta_setequal(x, y)`,
  `dta_setdiff(x, y)`: Stata's tabulation, grouping and set operations.

dtaparser exports `read_dta()` and `read_meta(file, encoding = NULL)`
(see [Plain R types](#plain-r-types-dtaparser)), `save_dta()` (which
dtatools re-exports), five accessors for the columns `read_dta()`
returns, `tagged_na(x)` to make
`.a` to `.z`, and `with_labels(x, labels, label = NULL)` to make a
labelled column (see [Labelled columns](#labelled-columns)):

- `na_tag(x)`, `is_tagged_na(x, tag = NULL)`: the letters of `.a` to
  `.z`. `tagged_na(x)`: `.a` to `.z` from their letters.
- `missing_rank(x)`: each value's place in Stata's missing-value order,
  0 for a number, 1 for `.`, 2 to 27 for `.a` to `.z`.
- `var_label(x)`, `val_labels(x)`, `val_label(x, values = x)`: variable
  and value labels.
- `drop_labels(x)`: `x` without its variable and value labels, its
  other attributes and class kept.

datakit exports:

- `read_fixed_width(file, setup, recodes = "setup", ...)`: read
  fixed-width text through its SAS setup file (see
  [Fixed-width files](#fixed-width-files-with-a-sas-setup-file)), with
  labelled columns as `dtaparser_labelled`. datparser exports the same
  function, with labelled columns as plain vectors and a `labels`
  attribute, and nothing else.
- `d[i, name, by = ] := value`: make or change a column of a data
  frame under R's rules (`?datakit::":="`; see
  [From a do-file to R](#from-a-do-file-to-r)). `colon_equals()` is the
  generic behind it; dtatools adds the method for dibbles.
- `datakit_by(..., .suffix = "_letter")`: columns and their `.a` to `.z`
  letters, for dplyr's `group_by()`, `count()`, `distinct()` and joins
  to keep the letters apart (see [Plain R types](#plain-r-types-dtaparser)).
- `read_parquet(file, col_select = NULL, skip = 0, n_max = Inf, factors = FALSE, int64 = "double", decimal = "double", timestamps = "error", nested = "error", warn_extended_missing = TRUE)`:
  read a Parquet file into `read_dta()`'s types (see
  [Parquet files](#parquet-files)).
- `read_parquet_info(file)`: a Parquet file's rows, row groups, codecs,
  labels and columns, from its footer.
- `save_parquet(data, file, compression = "snappy", compression_level = NULL, row_group_size = NULL, missing_letters = TRUE)`:
  write a data frame as Parquet, labels and `.a` to `.z` kept.
- `save_dta(data, file, ...)`: dtaparser's `save_dta()` for a data
  frame; for a polars DataFrame, `meta`, `missing_letters` and
  `timestamps` by name.

datakit's polars functions (R 4.3 or later, with polars from
R-multiverse and nanoarrow) read into a polars DataFrame and a
`datakit_meta`, with `.a` to `.z` as tagged
NaNs in Float64 columns; each has a help page:

- `read_parquet_pl(file, ...)`, `read_dta_pl(file, ...)`,
  `read_fixed_width_pl(file, setup, ...)`: `list(df, meta)`.
- `save_parquet()` and `save_dta()` take the frame back, with `meta =`.
- `is_missing(x)` and `is_na(x)`: what `is.na()` says, for R vectors
  and for polars expressions and Series, where `$is_null()` sees only
  `.`.
- `tagged_na_pl(letter)`, `na_tag_pl(x)`, `is_tagged_na_pl(x, letter = NULL)`:
  make and read `.a` to `.z` in polars.
- `datakit_by_pl(..., .suffix = "_letter")`: columns and their letters,
  to group, `unique()` or join without merging `.a` and `.b`.
