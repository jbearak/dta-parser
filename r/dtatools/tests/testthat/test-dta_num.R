# Stata's semantics for dta_num vectors, and where they hold.

x <- dta_num(c(1, NA, .d, .a, 5), labels = c(One = 1, `Don't know` = .d), label = "X")

test_that("comparisons follow Stata and never return NA", {
  expect_identical(x == NA, c(FALSE, TRUE, FALSE, FALSE, FALSE))
  expect_identical(x == .d, c(FALSE, FALSE, TRUE, FALSE, FALSE))
  expect_identical(x != 1, c(FALSE, TRUE, TRUE, TRUE, TRUE))
  # Missing values are above every number; . < .a < .d.
  expect_identical(x > 4, c(FALSE, TRUE, TRUE, TRUE, TRUE))
  expect_identical(x < .a, c(TRUE, TRUE, FALSE, FALSE, TRUE))
  expect_identical(.a < .b & NA < .a, TRUE)
  expect_identical(x == c(1, NA, .d, .a, 5), rep(TRUE, 5))
  expect_identical(x == TRUE, c(TRUE, FALSE, FALSE, FALSE, FALSE))
})

test_that("arithmetic gives plain doubles, every code as NA", {
  expect_identical(x + 1, c(2, NA, NA, NA, 6))
  expect_false(inherits(x * 2, "dta_num"))
})

test_that("subsetting, c, rep, unique and %in% keep codes and attributes", {
  y <- x[c(3, 4, 3)]
  expect_s3_class(y, "dta_num")
  expect_identical(attr(y, "label"), "X")
  expect_identical(is_tagged_missing(y, "d"), c(TRUE, FALSE, TRUE))
  expect_identical(as.character(unique(c(x, x))), c("1", ".", ".d", ".a", "5"))
  expect_identical(as.character(rep(x[3], 2)), c(".d", ".d"))
  expect_identical(x %in% c(.d, 5), c(FALSE, FALSE, TRUE, FALSE, TRUE))
  expect_identical(x %in% NA, c(FALSE, TRUE, FALSE, FALSE, FALSE))
  expect_identical(as.character(sort(x)), c("1", "5", ".", ".a", ".d"))
  expect_identical(x[[3]] == .d, TRUE)
})

test_that("plain doubles with codes (c(NA, .i)) work with dtatools functions", {
  plain <- c(NA, .i)
  expect_false(inherits(plain, "dta_num"))
  expect_identical(is_missing(plain), c(TRUE, TRUE))
  expect_identical(is_tagged_missing(plain, "i"), c(FALSE, TRUE))
  expect_true(dta_setequal(c(.i, NA), plain))
  expect_identical(names(tab(plain, missing = TRUE)), c(".", ".i"))
})

test_that("printing shows the codes", {
  expect_identical(format(x)[3], ".d")
  expect_output(print(x), "\\.d")
  expect_identical(as.character(dta_num(c(100000, 1.5, -2))), c("100000", "1.5", "-2"))
})

test_that("is_missing treats an empty string as missing, as Stata does", {
  expect_identical(is_missing(c("a", "", NA)), c(FALSE, TRUE, FALSE))
  expect_identical(is_missing(c(1L, NA)), c(FALSE, TRUE))
})
