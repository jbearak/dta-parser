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
[Write a file](#write-a-file) ·
[Sets, groups and tabulations](#sets-groups-and-tabulations) ·
[Recipes](#recipes) ·
[Coming from haven](#coming-from-haven) ·
[Coming from readstata13](#coming-from-readstata13) ·
[Troubleshooting](#troubleshooting) ·
[API reference](#api-reference)

The [guide](guide/README.md) explains the Stata concepts behind each
section.

## Install

dtatools needs R 4.2 or later and a Rust toolchain (`cargo` and
`rustc`, from [rustup.rs](https://rustup.rs)), since it compiles the
Rust core when installed. It is not on CRAN. From a shell:

```sh
git clone https://github.com/jbearak/dta-parser
R CMD INSTALL dta-parser/r/dtatools
```

It imports rlang, tibble, tidyselect and vctrs; install them first if R
reports one missing. Check the install:

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
default, for all). Rows past the end give fewer rows or an empty tibble
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

dtatools does not read the file's timestamp, characteristics other than
notes, or sort order. Use the Python, Julia or TypeScript package if you
need them.

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

```r
x <- df$income
x > 3000                           # FALSE TRUE FALSE TRUE TRUE TRUE
x > 3000 & !is_missing(x)          # FALSE FALSE FALSE FALSE FALSE TRUE
x + 100                            # 2200 . 1950 . . 3300
sort(x)                            # 1850 2100 3200 .d .r .s (row 4 is now .s)
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

Any missing value becomes `NA`. The other formats count months (`%tm`),
quarters (`%tq`), half-years (`%th`) or weeks (`%tw`) since 1960; for
example `%tm` month `m` is year `1960 + m %/% 12`, month `m %% 12 + 1`.

To write a date column, give `dibble()` or `as_dibble()` a `Date`
column; it becomes a long with format `%td`. Or set the numbers and
format yourself: `dta_num(days, storage = "long", format = "%td")`.

## Write a file

```r
save_dta(df, "out.dta")
```

`save_dta(data, file)` writes any data frame as release 118 and returns
`file` invisibly. A dibble from `read_dta` writes back with its values,
missing codes, storage types, variable labels, value labels, display
formats, data label and notes.

How columns map to storage types:

| R column | Stata storage |
|---|---|
| numeric with a `storage` attribute | that type; a value that does not fit is an error |
| integer | long |
| double | double |
| logical | byte |
| character | strN up to 2045 bytes, else strL; `NA` becomes `""` (Stata strings have no missing value) |
| factor | an error: convert to character, or to numbers with labels |
| anything else (`Date`, `POSIXct`, lists) | an error; `as_dibble()` converts `Date` |

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
| `as_factor(x)` | `factor(val_label(x, x), levels = ...)`; see [Value labels](#value-labels) |
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
except `Date` columns (convert them with `as_dibble()` first).

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

## Troubleshooting

**Installation fails with "dtatools: building needs cargo".** Install
Rust from [rustup.rs](https://rustup.rs), open a new terminal, and
install again. On Windows you also need Rtools.

**"x holds binary strLs, which dtatools does not read".** The column
stores binary data (an image, say). Leave it out with `col_select`, or
read the file with the Python, Julia or TypeScript package.

**"unsupported .dta release".** The file is not a `.dta` file, or its
release is older than 104 or newer than 119. See
[Releases](guide/releases.md).

**Accented letters are wrong.** The file is older than release 118;
pass `encoding = "latin1"` or `encoding = "utf-8"`.

**`x > 0` is `TRUE` where `x` is missing.** That is Stata's rule, which
dtatools follows on `dta_num` columns. Add `& !is_missing(x)`.

**"save_dta: convert factors to character or numbers first".** Stata has
no factor type. Use `as.character()`, or build a `dta_num` with
`labels`.

**`save_dta` says a value does not fit.** The column's `storage`
attribute names a type too small for a value, usually after arithmetic
on a byte or int column. Set `attr(x, "storage") <- "double"` (or
`"long"`).

**A letter became `.` after `ifelse()` or `c()`.** Base functions that
build new doubles keep the letter; functions that compute (arithmetic,
`pmax()`) do not. Reassign the code with `x[i] <- .d`.

## API reference

Each function has a help page (`?read_dta`). Exports:

- `read_dta(file, col_select = NULL, encoding = NULL, skip = 0, n_max = Inf)`:
  read a file into a dibble.
- `save_dta(data, file)`: write a data frame as release 118.
- `dibble(...)`, `as_dibble(x)`: build or convert a dibble.
- `dta_num(x, labels, label, storage, format)`: a Stata numeric column.
- `.a` ... `.z`: the 26 extended missing values.
- `is_missing(x)`, `is_tagged_missing(x, tag = NULL)`: which values are
  missing.
- `val_labels(x)`, `val_label(x, values)`, `labelbook(data)`: value labels.
- `tab(x, missing = FALSE)`, `dta_group_id(..., missing = FALSE)`,
  `dta_group_tag(..., missing = FALSE)`, `dta_setequal(x, y)`,
  `dta_setdiff(x, y)`: Stata's tabulation, grouping and set operations.
