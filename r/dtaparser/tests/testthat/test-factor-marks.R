# A factor written by save_dta reads back as the same factor, ordered
# and unused levels included, whatever `factors` says (plan 0020), and
# so does a categorical Python's or TypeScript's datakit marked, unless
# the rows read hold .a to .z (plan 0023). A marked column the file no
# longer holds as written reads as unmarked, with a warning. Stale files
# are made by editing a saved file's bytes, as a change in Stata would.

factors_frame <- function() {
  data.frame(
    id = 1:4,
    size = factor(c("small", "large", NA, "small"), levels = c("small", "medium", "large"), ordered = TRUE),
    group = factor(c("b", "a", "b", "a"))
  )
}

saved_factors <- function() {
  path <- tempfile(fileext = ".dta")
  save_dta(factors_frame(), path)
  path
}

# Replace the first occurrence of `from` in the file with `to`, as long,
# after each of `after` in turn.
patch <- function(path, from, to, after = NULL) {
  bytes <- readBin(path, "raw", file.size(path))
  from <- if (is.character(from)) charToRaw(from) else from
  to <- if (is.character(to)) charToRaw(to) else to
  stopifnot(length(from) == length(to))
  start <- 1
  for (a in after) start <- find_bytes(bytes, charToRaw(a), start)
  at <- find_bytes(bytes, from, start)
  bytes[at:(at + length(from) - 1)] <- to
  writeBin(bytes, path)
}

find_bytes <- function(bytes, pattern, start) {
  for (i in start:(length(bytes) - length(pattern) + 1)) {
    if (identical(bytes[i:(i + length(pattern) - 1)], pattern)) return(i)
  }
  stop("not found")
}

# The 4-byte little-endian long `value`.
long_bytes <- function(value) writeBin(as.integer(value), raw(), size = 4, endian = "little")

test_that("factors and ordered factors read back as written, unused levels and NA included", {
  path <- saved_factors()
  expect_identical(as.data.frame(read_dta(path)), factors_frame())
  expect_identical(as.data.frame(read_dta(path, factors = TRUE)), factors_frame())
  # And again, through a second save.
  again <- tempfile(fileext = ".dta")
  save_dta(read_dta(path), again)
  expect_identical(as.data.frame(read_dta(again)), factors_frame())
})

test_that("save_dta marks each factor, replacing marks already in characteristics", {
  data <- factors_frame()
  data$group <- as.integer(data$group)
  attr(data, "characteristics") <- data.frame(
    variable = c("group", "id"), name = c("dtaparser_factor", "unit"), value = c("unordered group", "person"),
    stringsAsFactors = FALSE
  )
  path <- tempfile(fileext = ".dta")
  save_dta(data, path)
  chars <- as.data.frame(.Call(dtaparser:::C_dta_meta, path, NULL)$characteristics, stringsAsFactors = FALSE)
  expect_setequal(paste(chars$variable, chars$name, chars$value),
                  c("id unit person", "size dtaparser_factor ordered size"))
  expect_type(read_dta(path)$group, "integer")
})

test_that("a stale mark reads the column as unmarked, with one warning naming it", {
  stale <- list(
    "renamed set" = function(p) patch(p, "ordered size", "ordered sizz"),
    "unlabelled value" = function(p) patch(p, long_bytes(3), long_bytes(7), after = "<data>"),
    ".a" = function(p) patch(p, long_bytes(3), long_bytes(2147483622), after = "<data>"),
    "shared text" = function(p) {
      patch(p, c(charToRaw("medium"), as.raw(0)), c(charToRaw("large"), as.raw(c(0, 0))), after = "<value_labels>")
    }
  )
  for (why in names(stale)) {
    path <- saved_factors()
    stale[[why]](path)
    expect_warning(got <- read_dta(path), "`size` as factors", class = "dtaparser_stale_factor", label = why)
    expect_false(is.factor(got$size), label = why)
    expect_identical(got$group, factors_frame()$group, label = why)
  }
})

test_that("haven and readstata13 read a marked file's codes and labels as an unmarked one's", {
  path <- saved_factors()
  h <- haven::read_dta(path)
  expect_identical(as.numeric(h$size), c(1, 3, NA, 1))
  expect_identical(attr(h$size, "labels"), c(small = 1, medium = 2, large = 3))
  r <- suppressWarnings(readstata13::read.dta13(path))
  expect_identical(levels(r$size), c("small", "medium", "large"))
  expect_identical(as.character(r$group), c("b", "a", "b", "a"))
  chars <- attr(r, "expansion.fields")
  expect_true(list(c("size", "dtaparser_factor", "ordered size")) %in% chars)
})

test_that("a factor without levels reads back as one, without a warning", {
  data <- data.frame(e = factor(c(NA, NA), levels = character()))
  path <- tempfile(fileext = ".dta")
  save_dta(data, path)
  expect_no_warning(back <- read_dta(path))
  expect_identical(back$e, data$e)
})

# Categoricals (plan 0023). save_dta() drops `dtaparser_categorical`, so
# the fixture is saved with a characteristic one letter off and patched.

categorical_frame <- function() {
  grade <- with_labels(c(1, 3, tagged_na("a"), 1, tagged_na("r")),
                       c(low = 1, mid = 2, high = 3, tagged_na(c(Refused = "r"))))
  attr(grade, "label_set") <- "gl"
  attr(grade, "storage") <- "long"
  data <- data.frame(id = 1:5)
  data$grade <- grade
  # A label on a letter no row holds is allowed.
  data$region <- with_labels(c(2L, 1L, 2L, 3L, 1L),
                             c(North = 1, South = 2, East = 3, West = 4, tagged_na(c("Not asked" = "z"))))
  data
}

# Save `data` with a categorical marker on each of `marks` (column =
# marker value) and a factor marker on each of `factor_marks`.
saved_categoricals <- function(data = categorical_frame(),
                               marks = c(grade = "ordered gl", region = "unordered region"),
                               factor_marks = character()) {
  attr(data, "characteristics") <- data.frame(
    variable = c(names(marks), names(factor_marks)),
    name = c(rep("dtaparser_categoricaX", length(marks)), rep("dtaparser_factoX", length(factor_marks))),
    value = unname(c(marks, factor_marks))
  )
  path <- tempfile(fileext = ".dta")
  save_dta(data, path)
  bytes <- readBin(path, "raw", file.size(path))
  for (name in c("dtaparser_categorical", "dtaparser_factor")) {
    wrong <- charToRaw(paste0(substr(name, 1, nchar(name) - 1), "X"))
    for (at in grepRaw(wrong, bytes, fixed = TRUE, all = TRUE)) bytes[at + length(wrong) - 1] <- charToRaw(substring(name, nchar(name)))
  }
  writeBin(bytes, path)
  path
}

grade_factor <- function(x) factor(x, levels = c("low", "mid", "high"), ordered = TRUE)
region_factor <- function(x) factor(x, levels = c("North", "South", "East", "West"))

test_that("a categorical without .a to .z in the rows read is a factor, ordered from its marker", {
  path <- saved_categoricals()
  chars <- .Call(dtaparser:::C_dta_meta, path, NULL)$characteristics
  expect_identical(unique(chars$name), "dtaparser_categorical")
  for (factors in c(FALSE, TRUE)) {
    expect_no_warning(got <- read_dta(path, factors = factors))
    expect_identical(got$region, region_factor(c("South", "North", "South", "East", "North")))
    # A window without the letters is a factor too.
    expect_no_warning(window <- read_dta(path, n_max = 2, factors = factors))
    expect_identical(window$grade, grade_factor(c("low", "high")))
    expect_identical(read_dta(path, skip = 3, n_max = 1, factors = factors)$grade, grade_factor("low"))
  }
})

test_that("a categorical with .a to .z in the rows read keeps its numbers, letters and labels, without a warning", {
  path <- saved_categoricals()
  expected <- with_labels(c(1, 3, tagged_na("a"), 1, tagged_na("r")),
                          c(low = 1, mid = 2, high = 3, tagged_na(c(Refused = "r"))))
  for (factors in c(FALSE, TRUE)) {
    expect_no_warning(got <- read_dta(path, factors = factors))
    expect_s3_class(got$grade, "dtaparser_labelled")
    expect_identical(as.numeric(got$grade), as.numeric(expected))
    expect_identical(na_tag(got$grade), c(NA, NA, "a", NA, "r"))
    expect_identical(val_labels(got$grade), val_labels(expected))
    expect_identical(val_label(got$grade), c("low", "high", NA, "low", "Refused"))
    expect_true(is.factor(got$region))
  }
  # A window holding only a letter keeps it too.
  expect_identical(na_tag(read_dta(path, skip = 4)$grade), "r")
})

test_that("a stale categorical reads as unmarked, with one warning naming it", {
  stale <- list(
    "renamed set" = function(p) patch(p, "ordered gl", "ordered gx"),
    "unlabelled value" = function(p) patch(p, long_bytes(3), long_bytes(7), after = "<data>"),
    "shared text" = function(p) patch(p, c(charToRaw("mid"), as.raw(0)), c(charToRaw("low"), as.raw(0)),
                                      after = "<value_labels>"),
    "code past long's range" = function(p) patch(p, long_bytes(2), as.raw(c(0, 0, 0, 0x80)), # -2147483648
                                                  after = c("<value_labels>", "gl")),
    "label on ." = function(p) patch(p, long_bytes(2147483639), long_bytes(2147483621), after = "<value_labels>")
  )
  for (why in names(stale)) {
    path <- saved_categoricals()
    stale[[why]](path)
    expect_warning(got <- read_dta(path, n_max = 2), "`grade` as categoricals",
                   class = "dtaparser_stale_categorical", label = why)
    expect_false(is.factor(got$grade), label = why)
    expect_true(is.factor(got$region), label = why)
    expect_warning(got <- read_dta(path), class = "dtaparser_stale_categorical", label = why)
    expect_false(is.factor(got$grade), label = why)
  }
  # With factors = TRUE a stale one is a factor as any labelled column
  # is: unordered, and losing its letters with that warning.
  path <- saved_categoricals()
  patch(path, "ordered gl", "ordered gx")
  expect_warning(expect_warning(got <- read_dta(path, factors = TRUE), class = "dtaparser_stale_categorical"),
                 class = "dtaparser_extended_missing")
  expect_identical(got$grade, factor(c("low", "high", NA, "low", NA), levels = c("low", "mid", "high")))
})

test_that("a categorical with a date format is stale when dates are read, and not otherwise", {
  for (format in c("%td", "%d", "%tc", "%-tdCCYY")) {
    data <- categorical_frame()
    attr(data$grade, "format") <- format
    path <- saved_categoricals(data)
    expect_warning(got <- read_dta(path, n_max = 2), "`grade`", class = "dtaparser_stale_categorical", label = format)
    expect_false(is.factor(got$grade), label = format)
    expect_no_warning(got <- read_dta(path, n_max = 2, dates = FALSE))
    expect_identical(got$grade, grade_factor(c("low", "high")), label = format)
  }
})

test_that("a marked string column is stale, whatever the rows read", {
  data <- categorical_frame()
  data$s <- c("x", "", "y", "x", "")
  path <- saved_categoricals(data, marks = c(s = "unordered s"))
  expect_warning(got <- read_dta(path), "`s` as categoricals", class = "dtaparser_stale_categorical")
  expect_identical(got$s, data$s)
  expect_warning(read_dta(path, skip = 5), class = "dtaparser_stale_categorical")
})

test_that("a column with both markers trusts neither and is named in the categorical warning", {
  path <- saved_categoricals(marks = c(grade = "ordered gl", region = "unordered region"),
                             factor_marks = c(region = "unordered region"))
  chars <- .Call(dtaparser:::C_dta_meta, path, NULL)$characteristics
  expect_setequal(chars$name[chars$variable == "region"], c("dtaparser_categorical", "dtaparser_factor"))
  expect_warning(got <- read_dta(path, n_max = 2), "`region` as categoricals", class = "dtaparser_stale_categorical")
  expect_type(got$region, "integer")
  expect_s3_class(got$region, "dtaparser_labelled")
  expect_identical(got$grade, grade_factor(c("low", "high")))
})

test_that("a factor marker still fails on .a to .z", {
  path <- saved_categoricals(marks = character(), factor_marks = c(grade = "ordered gl"))
  expect_warning(got <- read_dta(path), "`grade` as factors", class = "dtaparser_stale_factor")
  expect_false(is.factor(got$grade))
  expect_identical(read_dta(path, n_max = 2)$grade, grade_factor(c("low", "high")))
})

test_that("save_dta drops categorical markers from characteristics", {
  data <- read_dta(saved_categoricals(), n_max = 2)
  data$region <- as.integer(data$region)
  attr(data, "characteristics") <- data.frame(
    variable = c("region", "id"), name = c("dtaparser_categorical", "unit"), value = c("unordered region", "person")
  )
  path <- tempfile(fileext = ".dta")
  save_dta(data, path)
  chars <- as.data.frame(.Call(dtaparser:::C_dta_meta, path, NULL)$characteristics, stringsAsFactors = FALSE)
  expect_setequal(paste(chars$variable, chars$name, chars$value),
                  c("id unit person", "grade dtaparser_factor ordered grade"))
  expect_type(read_dta(path)$region, "integer")
})
