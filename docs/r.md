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
[Troubleshooting](#troubleshooting) ·
[API reference](#api-reference)

The [guide](guide/README.md) explains the Stata concepts behind each
section.

## Install

dtatools needs R 4.2 or later, and reads and writes through dtaparser.
Neither is on CRAN. Each release is published as an R package
repository on GitHub, with binaries for macOS (arm64), Windows (x86_64)
and Ubuntu 24.04 (x86_64) for the current and previous R releases. On
macOS and Windows:

```r norun
install.packages("dtatools", repos = c("https://jbearak.github.io/dta-parser", "https://cloud.r-project.org"))
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
dtaparser first:

```sh
git clone https://github.com/jbearak/dta-parser
R CMD INSTALL dta-parser/r/dtaparser
R CMD INSTALL dta-parser/r/dtatools
```

This way, install rlang, tibble, tidyselect and vctrs first if R reports
one missing. After reinstalling dtaparser, restart R before using
dtatools. Check the install:

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
  id    region age   income interviewed comment             
  <dta> <dta>  <dta> <dta>  <dta>       <chr>               
1 1     1      34    2100   23436       ""                  
2 2     2      51    .d     23436       "moved in 2023"     
3 3     2      29    1850   23437       ""                  
4 4     3      62    .      23439       ""                  
5 5     4      45    .r     23439       "asked to call back"
6 6     1      38    3200   23440       ""                  
```

`read_dta(file)` returns a *dibble*: a tibble whose numeric columns are
`dta_num` vectors. Use it as any tibble, with base R or dplyr.

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

rlang and data.table also export a `:=`, and R uses the one from the
package attached last, so attach dtatools after them. Tests that call
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
and `.a` to `.z` with their letters. Storage types and display formats
are not kept by `read_dta()`, so integers come back long and doubles
double:

```r
dtaparser::save_dta(df, "again.dta")
again <- dtaparser::read_dta("again.dta")
identical(again$interviewed, df$interviewed)  # TRUE
dtaparser::na_tag(again$income)               # NA "d" NA NA "r" NA
```

A factor is written as codes 1 to k labelled with its levels. A factor
from `read_dta(factors = TRUE)` therefore comes back with codes 1 to k,
not the file's own codes, which that read did not keep; to write the
file's codes, read with `factors = FALSE`, the default.

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

dtaparser's `:=` works on any data frame or tibble, so a do-file can
become an R script one line at a time without dibbles. It is the same
`:=` as dtatools' (dtatools re-exports it), but on a data frame it
follows R's rules: missing values compare as `NA`, and `NA` in `i`
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
- A data.table is an error; use its own `dt[i, name := value]`.

The rest is as in [Make and change columns](#make-and-change-columns):
`by`, `.N`, the forms of `name`, `NULL` to drop a column, and where R
finds `:=` when rlang or data.table is attached. Without dtatools,
attach dtaparser or bind `` `:=` <- dtaparser::`:=` ``. See
`?dtaparser::":="`.

## Fixed-width files with a SAS setup file

Some surveys are published as fixed-width text with a SAS program, the
*setup file*, that says where each variable sits. CDC publishes the
National Survey of Family Growth this way, from 1973 to 2017-2019.
dtaparser's `read_fixed_width()` reads such data through its setup
file: columns from `INPUT`, variable labels from `LABEL`, value labels
from `PROC FORMAT` and `FORMAT`, record types from
`IF rec_type < 5 THEN DELETE; ELSE INPUT ...`, and the setup's
*missing-value recodes*, such as `IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;`.

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
df <- dtaparser::read_fixed_width("survey.dat", "survey.sas")
df$KIDS               # 2 NA NA 0
dtaparser::var_label(df$KIDS) # "Number of children"
```

`recodes = "tagged"` keeps why each value is missing, as labelled
missing values: per variable, the codes recoded to `.` become haven's
tagged NAs `.a`, `.b`, ... in the order the setup names them, and each
code's value label moves to its letter:

```r
df <- dtaparser::read_fixed_width("survey.dat", "survey.sas", recodes = "tagged")
dtaparser::na_tag(df$KIDS)     # NA "a" "b" NA
is.na(df$KIDS)                 # FALSE TRUE TRUE FALSE
dtaparser::val_label(df$KIDS)  # NA "(98) DK" "(99) Not ascertained" "(0) None"
dtaparser::na_tag(dtaparser::val_labels(df$KIDS)) # (0) None = NA, (98) DK = "a", (99) ... = "b"
```

A letter means what that variable's labels say: `.a` is 98 "DK" here,
but in a variable whose setup recodes 97 "Refused" first, `.a` is
"Refused". `recodes = "none"` ignores the recodes, keeping the codes as
numbers.

Numeric columns take the smallest type that holds their values, and
records shorter than the setup's columns read as blank (`NA`).
Statements the reader does not run, such as other data-step code or a
range in `VALUE`, are skipped with one warning; the tibble's
`warnings` attribute lists them all. A `LENGTH` statement for numbers, which sets only how SAS stores them, is skipped without one. A variable label with stray quotes
inside it, such as `X = "WHETHER " SAME AS LAST MONTH" WAS ANSWERED"`
in CDC's 2011-2013 to 2015-2017 setups, is read from its first quote to
its last, without a warning. `col_select`, `skip` and
`n_max` work as in `read_dta()`, after the whole file is read.

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
df <- dtaparser::read_fixed_width("survey.dat", c("input.sas", "labels.sas"),
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
df <- dtaparser::read_fixed_width("survey.dat", "commented.sas", recodes = "none")
attr(df$KIDS, "labels")  # (0) None = 0, (98) DK = 98
df <- dtaparser::read_fixed_width("survey.dat", "commented.sas", recodes = "none",
                                  commented_formats = FALSE)
attr(df$KIDS, "labels")  # NULL
```

## Threads

Reading and writing large files uses up to three threads: workers decode and fill numeric columns while R makes the strings. On x86, where processors pair their hardware threads, the most is half the processor count, up to three. Reads that need a strL column, small reads and writes (under 16 MB of selected data) and every read on Windows use one thread. In our measurements the threads together used at most 15% more CPU time than one thread doing the same work.

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
read the file with the Python, Julia or TypeScript package.

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

dtaparser exports `read_dta()` (see
[Plain R types](#plain-r-types-dtaparser)), `save_dta()` (which
dtatools re-exports),
`read_fixed_width(file, setup, recodes = "setup", ...)`, which reads
fixed-width text through its SAS setup file (see
[Fixed-width files](#fixed-width-files-with-a-sas-setup-file)), and
five accessors for the columns they return, `tagged_na(x)` to make
`.a` to `.z`, and `with_labels(x, labels, label = NULL)` to make a
labelled column (see [Labelled columns](#labelled-columns)):

- `na_tag(x)`, `is_tagged_na(x, tag = NULL)`: the letters of `.a` to
  `.z`. `tagged_na(x)`: `.a` to `.z` from their letters.
- `var_label(x)`, `val_labels(x)`, `val_label(x, values = x)`: variable
  and value labels.
- `d[i, name, by = ] := value`: make or change a column of a data
  frame under R's rules (`?dtaparser::":="`). `colon_equals()` is the
  generic behind it; dtatools adds the method for dibbles.
