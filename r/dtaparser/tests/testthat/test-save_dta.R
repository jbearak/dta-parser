# save_dta writes what read_dta returns, so read_dta(save_dta(read_dta(f)))
# gives the same tibble: dates, labelled columns and .a to .z included
# (ADR 0031). haven, independent of us, reads the dates back too.

saved <- function(data) {
  path <- tempfile(fileext = ".dta")
  save_dta(data, path)
  path
}

storage_of <- function(path) {
  meta <- .Call(dtaparser:::C_dta_meta, path, NULL)
  stats::setNames(meta$storage, meta$names)
}

formats_of <- function(path) {
  meta <- .Call(dtaparser:::C_dta_meta, path, NULL)
  stats::setNames(meta$formats, meta$names)
}

# A file with a date, a datetime, labelled integer and double columns
# holding .a to .z, plain numbers, a logical-like byte and a string.
source_file <- function() {
  ms <- function(s) (s + 3653 * 86400) * 1000
  write_fixture(
    id = col(c(1, 2, 3, 4), "long"),
    born = col(c(0, -3653, NA, 23000), "long", "%td"),
    seen = col(c(ms(0), ms(1.7e9), NA, ms(-86400)), "double", "%tc"),
    smoker = col(c(1, 0, tagged_na("d"), NA), "byte",
                 labels = c(No = 0, Yes = 1, tagged_na(c("Don't know" = "d")))),
    income = col(c(2100.5, tagged_na("r"), 0, NA), "double",
                 labels = c(None = 0, tagged_na(c(Refused = "r")))),
    weight = col(c(1.25, tagged_na("a"), NA, 3), "double"),
    name = col(c("Ana", "", "Zoë", "Bo"), "str", "%9s")
  )
}

test_that("save_dta writes read_dta's tibble so that it reads back the same", {
  original <- read_dta(source_file())
  attr(original, "label") <- "People"
  attr(original, "notes") <- c("first", "second")
  expect_s3_class(original$born, "Date")
  expect_s3_class(original$seen, "POSIXct")
  expect_s3_class(original$smoker, "dtaparser_labelled")
  path <- saved(original)
  again <- read_dta(path)
  expect_identical(again, original)
  expect_identical(na_tag(again$income), c(NA, "r", NA, NA))
  expect_identical(val_label(again$smoker), c("Yes", "No", "Don't know", NA))
  expect_identical(attr(again, "label"), "People")
  expect_identical(attr(again, "notes"), c("first", "second"))
  # read_dta does not keep storage types: the byte column is a double
  # now, as it holds .d, and is written as one. Dates are long,
  # datetimes double.
  expect_identical(unname(storage_of(path)[c("id", "smoker", "born", "seen")]), c("long", "double", "long", "double"))
  expect_identical(unname(formats_of(path)[c("born", "seen")]), c("%td", "%tc"))
})

test_that("haven reads the dates and labels save_dta wrote", {
  skip_if_not_installed("haven")
  d <- tibble::tibble(
    born = as.Date(c("1960-01-01", "1950-01-01", NA, "2023-12-31")),
    seen = as.POSIXct(c("2024-05-06 07:08:09", NA), tz = "UTC")[c(1, 2, 2, 1)],
    smoker = with_labels(c(1L, 0L, NA, 1L), c(No = 0, Yes = 1))
  )
  h <- haven::read_dta(saved(d))
  expect_s3_class(h$born, "Date")
  expect_identical(as.numeric(h$born), as.numeric(d$born))
  expect_equal(as.numeric(h$seen), as.numeric(d$seen))
  expect_identical(attr(h$smoker, "labels"), c(No = 0, Yes = 1))
  expect_identical(as.vector(unclass(h$smoker)), c(1, 0, NA, 1))
})

test_that("a Date is long when every day is whole, double otherwise, and keeps a format", {
  whole <- as.Date(c("2024-01-01", NA))
  part <- structure(c(19723.5, 1), class = "Date")
  formatted <- structure(as.Date(c("2024-01-01", "2024-01-02")), format = "%tdCCYY-NN-DD")
  path <- saved(tibble::tibble(whole = whole, part = part, f = formatted))
  expect_identical(unname(storage_of(path)), c("long", "double", "long"))
  expect_identical(unname(formats_of(path)), c("%td", "%td", "%tdCCYY-NN-DD"))
  back <- read_dta(path)
  expect_identical(back$whole, whole)
  expect_identical(as.numeric(back$part), as.numeric(part))
})

test_that("a POSIXct in another time zone is written as its UTC clock time", {
  t <- as.POSIXct("2024-05-06 07:08:09", tz = "America/New_York")
  back <- read_dta(saved(tibble::tibble(t = t)))$t
  expect_identical(attr(back, "tzone"), "UTC")
  expect_equal(as.numeric(back), as.numeric(t))
})

test_that("a factor is written as codes 1 to k labelled with its levels", {
  path <- write_fixture(region = col(c(3, 7, 3, NA), "byte", labels = c(North = 3, South = 7, East = 9)))
  f <- read_dta(path, factors = TRUE)
  expect_identical(levels(f$region), c("North", "South", "East"))
  path2 <- saved(f)
  expect_identical(unname(storage_of(path2)), "long")
  codes <- read_dta(path2)$region
  # The file's codes were 3 and 7; a factor no longer has them.
  expect_identical(vctrs::vec_data(codes), c(1L, 2L, 1L, NA))
  expect_identical(val_labels(codes), c(North = 1, South = 2, East = 3))
  expect_identical(read_dta(path2, factors = TRUE), f)
})

test_that("a factor keeps its variable label and a given label set", {
  x <- structure(factor(c("b", "a")), label = "Letters", label_set = "abc")
  y <- structure(factor(c("a", "b")), label_set = "abc")
  path <- saved(tibble::tibble(x = x, y = y))
  meta <- .Call(dtaparser:::C_dta_meta, path, NULL)
  expect_identical(meta$label_sets, c("abc", "abc"))
  expect_identical(var_label(read_dta(path)$x), "Letters")
})

test_that("columns sharing a label set must agree, and other classes are errors", {
  a <- with_labels(1, c(Yes = 1))
  b <- with_labels(1, c(No = 1))
  attr(a, "label_set") <- attr(b, "label_set") <- "yn"
  expect_error(saved(tibble::tibble(a = a, b = b)), "label set \"yn\" have different labels")
  expect_error(saved(data.frame(t = I(as.POSIXlt("2024-01-01", tz = "UTC")))), "cannot write t, a column of class")
  expect_error(saved(data.frame(d = as.difftime(1, units = "days"))), "cannot write d, a column of class difftime")
  expect_error(saved(list(x = 1)), "is.data.frame")
})

test_that("metadata attributes are written as given", {
  d <- tibble::tibble(a = 1, b = "x")
  attr(d, "timestamp") <- "01 Feb 2026 03:04"
  attr(d, "sort_order") <- c("a", "gone", "b")
  attr(d, "characteristics") <- data.frame(variable = c("a", "gone", "_dta"), name = c("k", "k", "k"),
                                           value = c("1", "2", "3"))
  path <- saved(d)
  meta <- .Call(dtaparser:::C_dta_meta, path, NULL)
  expect_identical(meta$timestamp, "01 Feb 2026 03:04")
  expect_identical(meta$names[meta$sort_order], "a")
  expect_setequal(paste(meta$characteristics$variable, meta$characteristics$value), c("a 1", "_dta 3"))
})
