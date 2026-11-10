# Files going between R's datakit and TypeScript's (plan 0019, "Across
# languages"; TypeScript since plan 0021). R's half:
#
#     Rscript compat/parquet/cross_language.R write DIR   # R writes DIR/from_r.parquet
#     Rscript compat/parquet/cross_language.R check DIR   # R reads DIR/from_typescript.parquet
#
# compat/parquet/cross_language.sh runs both halves of each language in
# turn. Every value is made here and in cross_language.mjs, from the same
# literal data, so each side checks the other's file cell by cell: the
# value, the missing code (`.` or which of `.a` to `.z`), and the
# labels, formats and value labels. Exits with status 1 if a check fails.
#
# Needs dtaparser and datakit installed (R_LIBS may point at a scratch
# library holding them).

suppressPackageStartupMessages({
  library(dtaparser)
  library(datakit)
})

args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2, args[1] %in% c("write", "check"))
dir <- args[2]
dir.create(dir, showWarnings = FALSE, recursive = TRUE)

na <- tagged_na

# ---------------------------------------------------------------- R writes

if (args[1] == "write") {
  score <- with_labels(c(1.5, NA, na("a"), -2.25, na("z"), 2^1000),
                       c(Low = 1.5, na(c(Refused = "a", Other = "z"))),
                       label = "A score")
  attr(score, "label_set") <- "scorelab"
  attr(score, "format") <- "%9.2f"
  small <- with_labels(c(1, 0, na("d"), 100, -127, NA), c(No = 0, Yes = 1, na(c("Don't know" = "d"))))
  attr(small, "label_set") <- "yn"
  attr(small, "storage") <- "byte"
  # A long column holding letters: written as DOUBLE, storage "long".
  long <- c(2147483620, -2147483647, na("b"), 0, NA, 7)
  attr(long, "storage") <- "long"
  attr(long, "label") <- "A long"
  fl <- c(0.5, na("c"), 3.25, NA, -1, 2)
  attr(fl, "storage") <- "float"
  count <- c(3L, NA, 0L, -5L, 2147483647L, 1L)
  attr(count, "label") <- "A count"
  day <- as.Date(c("2024-03-01", NA, "1960-01-01", "1900-02-28", "2100-12-31", "1970-01-01"))
  attr(day, "format") <- "%tdCCYY-NN-DD"
  df <- tibble::tibble(
    id = 1:6, score = score, small = small, long = long, fl = fl, count = count,
    word = c("a", NA, "", "\u00e9t\u00e9", "x y", "z"),
    region = factor(c("N", "S", NA, "N", "E", "S"), levels = c("S", "N", "E", "W")),
    day = day,
    when = as.POSIXct(c(0, 1709285400.25, NA, -1, 86400, 1e9), tz = "America/New_York"),
    # The exactness edges: a Date with a fraction of a day, and a POSIXct
    # whose seconds no whole number of microseconds gives back. Both are
    # written as DOUBLE days or seconds since 1970.
    dayfrac = as.Date(c(19000.5, 0, NA, -1.25, 1, 2)),
    whenfrac = as.POSIXct(c(1.0000001, 2, NA, 3.5, -0.0000001, 6), tz = "UTC"),
    # For factors: two codes sharing a text, and numbers as R writes them.
    dup = structure(with_labels(c(1, 2, 3, 1, 5, NA), c(Yes = 1, No = 2, Yes = 3)), label_set = "dupl", storage = "byte"),
    w = structure(with_labels(c(0.5, 2, 1e5, NA, 1e-4, 3), c(three = 3)), label_set = "wl")
  )
  attr(df, "label") <- "From R"
  attr(df, "notes") <- c("First note.", "Second note.")
  save_parquet(df, file.path(dir, "from_r.parquet"))
  cat("R wrote", file.path(dir, "from_r.parquet"), "\n")
  quit(status = 0)
}

# ---------------------------------------------------------------- R checks

failures <- character()
checked <- 0L
check <- function(ok, what) {
  checked <<- checked + 1L
  if (!isTRUE(ok)) failures <<- c(failures, what)
}

# A cell as text: the number to 17 digits, "." or ".a" to ".z".
cell <- function(x, i) {
  v <- unclass(x)[i]
  if (is.na(v) && is.double(v) && !is.nan(v)) {
    tag <- na_tag(v)
    return(if (is.na(tag)) "." else paste0(".", tag))
  }
  if (is.na(v)) return(".")
  if (is.double(v)) sprintf("%.17g", v) else as.character(v)
}

# The same numbers, exactly, and missing in the same rows.
same_num <- function(a, b) {
  a <- as.numeric(a)
  b <- as.numeric(b)
  length(a) == length(b) && identical(is.na(a), is.na(b)) && all(a[!is.na(a)] == b[!is.na(b)])
}

check_cells <- function(x, want, name) {
  check(length(x) == length(want), paste(name, "length"))
  for (i in seq_along(want)) {
    got <- cell(x, i)
    check(identical(got, want[[i]]), sprintf("%s row %d: %s, not %s", name, i, got, want[[i]]))
  }
}

num <- function(...) sprintf("%.17g", c(...))

# TypeScript's file (plan 0021): it writes its date, timestamp and
# categorical holding letters as such.
f <- "from_typescript.parquet"
if (!file.exists(file.path(dir, f))) {
  stop("no ", f, " in ", dir, "; run cross_language.mjs write first")
}
p <- read_parquet(file.path(dir, f))
w <- function(what) paste(f, what)
check(identical(attr(p, "label"), "From TypeScript"), w("data label"))
check(identical(attr(p, "notes"), "A note from TypeScript."), w("notes"))
check(identical(p$id, 1:6), w("id"))
check_cells(p$score, c(num(1.5), ".", ".a", num(-2.25), ".z", num(2^1000)), w("score"))
check(identical(attr(p$score, "label"), "A score") && identical(attr(p$score, "format"), "%9.2f"), w("score label, format"))
labs <- attr(p$score, "labels")
check(identical(unname(labs[names(labs) == "Low"]), 1.5) && identical(unname(na_tag(labs[names(labs) == "Other"])), "z"),
      w("score labels"))
check_cells(p$small, c("1", "0", ".d", "100", "-127", "."), w("small"))
check(identical(na_tag(attr(p$small, "labels")[["Don't know"]]), "d"), w("small labels: .d"))
check_cells(p$long, c(num(2147483620), num(-2147483647), ".b", "0", ".", "7"), w("long"))
check(identical(attr(p$long, "label"), "A long"), w("long label"))
check_cells(p$fl, c(num(0.5), ".c", num(3.25), ".", "-1", "2"), w("fl"))
check_cells(p$count, c("3", ".", "0", "-5", "2147483647", "1"), w("count"))
check(identical(p$word, c("a", NA, "", "été", "x y", "z")), w("word"))
check(identical(levels(p$region), c("S", "N", "E", "W")) &&
      identical(as.character(p$region), c("N", "S", NA, "N", "E", "S")), w("region"))
check(inherits(p$day, "Date") &&
      same_num(p$day, as.Date(c("2024-03-01", NA, "1960-01-01", "1900-02-28", "2100-12-31", "1970-01-01"))), w("day"))
check(identical(attr(p$day, "format"), "%tdCCYY-NN-DD"), w("day format"))
check(inherits(p$when, "POSIXct") && same_num(p$when, c(0, 1709285400.25, NA, -1, 86400, 1e9)) &&
      identical(attr(p$when, "tzone"), "America/New_York"), w("when"))
# A Date and a POSIXct holding letters, as tagged NAs.
check(inherits(p$seen, "Date"), w("seen: Date"))
check_cells(p$seen, c(num(19783), ".d", num(19784), ".", num(-3653), ".z"), w("seen"))
check(inherits(p$stamp, "POSIXct"), w("stamp: POSIXct"))
check_cells(p$stamp, c(num(0.5), ".k", num(1e9), ".", num(-86400.25), num(1000001 / 1e6)), w("stamp"))
check_cells(p$dup, c("1", "2", "3", "1", "5", "."), w("dup"))
check(identical(unname(attr(p$dup, "labels")), c(1, 2, 3)) &&
      identical(names(attr(p$dup, "labels")), c("Yes", "No", "Yes")), w("dup labels"))
# A categorical holding letters (plan 0022): labelled codes with the
# letters. TypeScript writes it as a categorical, which factors = TRUE
# leaves as labelled codes; R names the set (label_set) for it.
check(inherits(p$grade, "dtaparser_labelled") && !is.factor(p$grade), w("grade: labelled"))
check_cells(p$grade, c("1", ".a", "3", ".", ".z", "2"), w("grade"))
check(identical(unname(attr(p$grade, "labels")), c(1, 2, 3)) &&
      identical(names(attr(p$grade, "labels")), c("low", "mid", "high")) &&
      identical(attr(p$grade, "label_set"), "grade"), w("grade labels"))
pf <- read_parquet(file.path(dir, f), factors = TRUE, timestamps = "truncate", warn_extended_missing = FALSE)
check(inherits(pf$grade, "dtaparser_labelled") && !is.factor(pf$grade), w("grade with factors = TRUE"))

cat("R checked", checked, "values and labels in TypeScript's file\n")
if (length(failures)) {
  cat("FAILED:\n", paste0("  ", failures, "\n"), sep = "")
  quit(status = 1)
}
