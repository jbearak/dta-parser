# A factor written by save_dta reads back as the same factor, ordered
# and unused levels included, whatever `factors` says (plan 0020). A
# marked column the file no longer holds as written reads as unmarked,
# with a warning. Stale files are made by editing a saved file's bytes,
# as a change in Stata would.

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

# Replace the only occurrence of `from` in the file with `to`, as long.
patch <- function(path, from, to, after = NULL) {
  bytes <- readBin(path, "raw", file.size(path))
  from <- if (is.character(from)) charToRaw(from) else from
  to <- if (is.character(to)) charToRaw(to) else to
  stopifnot(length(from) == length(to))
  start <- if (is.null(after)) 1 else find_bytes(bytes, charToRaw(after), 1)
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
