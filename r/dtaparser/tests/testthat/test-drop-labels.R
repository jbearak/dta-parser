# drop_labels() takes off value labels and the variable label and keeps
# everything else, for copying a column without its labels while keeping
# its date class.

test_that("a labelled double loses its labels, class and variable label, and keeps its letters", {
  x <- with_labels(c(1, 0, tagged_na("r"), NA, tagged_na("d")),
                   c(No = 0, Yes = 1, tagged_na(c(Refused = "r", "Don't know" = "d"))),
                   label = "Wants a baby")
  y <- drop_labels(x)
  expect_identical(attributes(y), NULL)
  expect_type(y, "double")
  expect_identical(na_tag(y), na_tag(x))
  expect_identical(na_tag(y), c(NA, NA, "r", NA, "d"))
  expect_identical(y, vctrs::vec_data(x))
  expect_null(val_labels(y))
  expect_null(var_label(y))
  expect_identical(val_label(y), rep(NA_character_, 5))
})

test_that("a labelled integer becomes its integer codes, keeping names and format", {
  x <- with_labels(c(1L, 0L, NA), c(No = 0, Yes = 1), label = "V")
  names(x) <- c("a", "b", "c")
  attr(x, "format") <- "%8.0f"
  y <- drop_labels(x)
  expect_identical(y, structure(c(a = 1L, b = 0L, c = NA), format = "%8.0f"))
})

test_that("a labelled column read from a file loses its labels", {
  path <- tempfile(fileext = ".dta")
  save_dta(data.frame(k = with_labels(c(2, tagged_na("a"), 0), c(None = 0, tagged_na(c(DK = "a"))),
                                      label = "Kids")), path)
  k <- read_dta(path)$k
  expect_s3_class(k, "dtaparser_labelled")
  y <- drop_labels(k)
  expect_false(is.object(y))
  expect_null(attr(y, "labels"))
  expect_null(attr(y, "label"))
  expect_identical(na_tag(y), c(NA, "a", NA))
  expect_identical(as.numeric(y), as.numeric(k))
})

test_that("a Date with a variable label keeps its class and values", {
  d <- structure(as.Date(c("2024-01-31", NA, "1960-01-01")), label = "Interview date")
  y <- drop_labels(d)
  expect_identical(y, as.Date(c("2024-01-31", NA, "1960-01-01")))
  expect_s3_class(y, "Date")
  expect_null(var_label(y))
})

test_that("a Date keeps .a to .z", {
  d <- structure(c(19753, tagged_na("b")), class = "Date", label = "When")
  y <- drop_labels(d)
  expect_s3_class(y, "Date")
  expect_identical(na_tag(unclass(y)), c(NA, "b"))
})

test_that("a POSIXct with a variable label keeps its class, time zone and values", {
  t <- as.POSIXct(c("2024-01-31 12:34:56", "1960-01-01 00:00:00"), tz = "America/New_York")
  labelled <- structure(t, label = "Start time")
  y <- drop_labels(labelled)
  expect_identical(y, t)
  expect_s3_class(y, "POSIXct")
  expect_identical(attr(y, "tzone"), "America/New_York")
  expect_null(var_label(y))
})

test_that("double, integer, logical and character vectors lose only their labels", {
  inputs <- list(c(a = 1.5, b = NA), c(3L, NA), c(TRUE, NA), c(x = "a", y = NA))
  for (v in inputs) {
    labelled <- structure(v, label = "L", labels = c(One = 1))
    expect_identical(drop_labels(labelled), v)
  }
})

test_that("a factor loses its variable label and keeps its levels", {
  f <- factor(c("b", "a", NA))
  expect_identical(drop_labels(structure(f, label = "F")), f)
})

test_that("a vector without labels comes back identical", {
  inputs <- list(c(1, tagged_na("a"), NA), c(a = 1L, b = 2L), c(TRUE, FALSE, NA), c("x", NA),
                 as.Date("2024-01-31"), as.POSIXct("2024-01-31 12:00:00", tz = "UTC"),
                 factor(c("a", "b")), structure(c(1, 2), format = "%5.1f"), double(), character())
  for (v in inputs) expect_identical(drop_labels(v), v)
})

test_that("a list or data frame is an error", {
  expect_error(drop_labels(data.frame(x = 1)), "must be a column")
  expect_error(drop_labels(list(1)), "must be a column")
})

test_that("the result works as a data frame column and writes without labels", {
  x <- with_labels(c(1, 0, tagged_na("r")), c(No = 0, Yes = 1), label = "Wants")
  d <- tibble::tibble(x = x, when = structure(as.Date(c("2024-01-01", "2024-02-01", NA)), label = "When"))
  d$y <- drop_labels(d$x)
  d$when2 <- drop_labels(d$when)
  expect_s3_class(d$x, "dtaparser_labelled")
  expect_s3_class(d$when2, "Date")
  path <- tempfile(fileext = ".dta")
  save_dta(d, path)
  back <- read_dta(path)
  expect_s3_class(back$x, "dtaparser_labelled")
  expect_false(inherits(back$y, "dtaparser_labelled"))
  expect_null(var_label(back$y))
  expect_identical(na_tag(back$y), c(NA, NA, "r"))
  expect_s3_class(back$when2, "Date")
  expect_null(var_label(back$when2))
  expect_identical(var_label(back$when), "When")
})
