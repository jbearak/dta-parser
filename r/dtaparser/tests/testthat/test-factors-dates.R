# Value labels become factors; date and datetime formats become Date and
# POSIXct. See read_dta's documentation for the rules.

test_that("labelled columns become factors in order of value", {
  skip_if_not_installed("haven")
  labels <- c(a = 1, b = 2, a = 3, "Don't know" = haven::tagged_na("d"))
  x <- c(3, 1, 2, 5, 100000, -100000, haven::tagged_na("d"), NA)
  path <- write_fixture(l = col(x, "long", labels = labels), d = col(c(1.5, 1, NA, 1, 1, 1, 1, 1), "double",
                                                                   labels = c(one = 1)))
  got <- read_dta(path)
  # Repeated texts share a level; labelled missing values are NA; an
  # unlabelled integer's level is as.character() of the integer, where
  # haven's as_factor() gives "1e+05" and "-1e+05".
  expect_identical(levels(got$l), c("-100000", "a", "b", "5", "100000"))
  expect_identical(as.character(got$l), c("a", "a", "b", "5", "100000", "-100000", NA, NA))
  expect_identical(levels(got$d), c("one", "1.5"))
})

test_that("factor levels come from the rows read", {
  path <- write_fixture(l = col(c(1, 7, 9), "byte", labels = c(one = 1)))
  expect_identical(levels(read_dta(path)$l), c("one", "7", "9"))
  expect_identical(levels(read_dta(path, n_max = 2)$l), c("one", "7"))
})

test_that("factors = FALSE keeps numbers and the non-missing labels", {
  skip_if_not_installed("haven")
  labels <- c(a = 1, b = 2, dk = haven::tagged_na("d"))
  path <- write_fixture(l = col(c(1, 2, haven::tagged_na("d")), "int", labels = labels))
  x <- read_dta(path, factors = FALSE)$l
  expect_identical(as.vector(x), c(1L, 2L, NA))
  expect_identical(attr(x, "labels"), c(a = 1, b = 2))
})

test_that("date formats give Date and datetime formats POSIXct in UTC", {
  days <- c(0, 21915, NA)
  ms <- c(0, 1500, NA)
  path <- write_fixture(
    td = col(days, "long", "%td"),
    d = col(days, "long", "%d"),
    dlong = col(days, "int", "%dDlY"),
    left = col(days, "double", "%-td"),
    custom = col(days, "long", "%tdDD/NN/CCYY"),
    tc = col(ms, "double", "%tc"),
    lefttc = col(ms, "double", "%-tc"),
    tC = col(ms, "double", "%tC"),
    tw = col(c(1, 2, NA), "int", "%tw"),
    labelled = col(c(0, 1, NA), "long", "%td", labels = c(start = 0))
  )
  x <- read_dta(path)
  want <- as.Date(c("1960-01-01", "2020-01-01", NA))
  for (name in c("td", "d", "dlong", "left", "custom")) {
    expect_identical(x[[name]], want, label = name)
    expect_type(unclass(x[[name]]), "double")
  }
  want <- as.POSIXct(c("1960-01-01 00:00:00", "1960-01-01 00:00:01.5", NA), tz = "UTC")
  for (name in c("tc", "lefttc")) {
    expect_s3_class(x[[name]], "POSIXct")
    expect_identical(attr(x[[name]], "tzone"), "UTC")
    expect_equal(as.double(x[[name]]), as.double(want), label = name)
  }
  # %tC counts leap seconds; it and the other %t formats stay numbers.
  expect_identical(x$tC, ms)
  expect_identical(x$tw, c(1L, 2L, NA))
  expect_s3_class(x$labelled, "factor")
  expect_identical(read_dta(path, dates = FALSE)$td, c(0L, 21915L, NA))
})

test_that("haven agrees on Date and POSIXct values", {
  skip_if_not_installed("haven")
  df <- data.frame(d = as.Date(c("2020-01-02", NA)),
                   t = as.POSIXct(c("2020-01-02 03:04:05.25", NA), tz = "UTC"))
  path <- tempfile(fileext = ".dta")
  haven::write_dta(df, path)
  ours <- read_dta(path)
  theirs <- haven::read_dta(path)
  expect_identical(class(ours$d), class(theirs$d))
  expect_identical(unclass(ours$d), as.vector(unclass(theirs$d)))
  expect_identical(class(ours$t), class(theirs$t))
  expect_identical(attr(ours$t, "tzone"), attr(theirs$t, "tzone"))
  expect_equal(as.double(ours$t), as.double(theirs$t))
})
