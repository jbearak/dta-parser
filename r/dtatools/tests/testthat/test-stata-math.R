# Missing values in arithmetic, math functions and logic on dta_num
# behave as in Stata: any missing operand, and any result Stata cannot
# hold, is `.`; in `&`, `|` and `!` a value is true when nonzero or
# missing. R's NA on the other side of an operation counts as `.`. The
# operations themselves are R's (ADR 0012).

# Each value as Stata writes it: 3, ., .a.
shown <- function(x) as.character(x)

x <- dta_num(c(3, NA, .a, 0), labels = c(Three = 3), label = "x", storage = "byte")

test_that("arithmetic with a missing operand is .", {
  expect_identical(shown(x + 1), c("4", ".", ".", "1"))
  expect_identical(shown(1 + x), c("4", ".", ".", "1"))
  expect_identical(shown(x - x), c("0", ".", ".", "0"))
  expect_identical(shown(x * 2L), c("6", ".", ".", "0"))
  expect_identical(shown(x + TRUE), c("4", ".", ".", "1"))
  expect_identical(shown(x + NA), rep(".", 4))
  expect_identical(shown(x + c(1, NA, 1, NA)), c("4", ".", ".", "."))
  expect_identical(shown(-x), c("-3", ".", ".", "0"))
  expect_identical(shown(.a + 1), ".")
  expect_identical(shown(x^0), c("1", ".", ".", "1"))
  expect_identical(shown(1^x), c("1", ".", ".", "1"))
  expect_identical(shown(dta_num(0)^0), "1")
  expect_identical(shown(1^dta_num(NA)), ".")
  expect_identical(shown(+x), c("3", ".", ".", "0"))
  expect_identical(shown(x %% 2), c("1", ".", ".", "0"))
  expect_identical(shown(x %/% 2), c("1", ".", ".", "0"))
})

test_that("a plain operand on the left keeps the operation's direction", {
  expect_identical(shown(2 - x), c("-1", ".", ".", "2"))
  expect_identical(shown(6 / x), c("2", ".", ".", "."))
  expect_identical(shown(2^x), c("8", ".", ".", "1"))
  expect_identical(NA < x, c(FALSE, FALSE, TRUE, FALSE))
  expect_identical(5 < x + 3, c(TRUE, TRUE, TRUE, FALSE))
  named <- dta_num(c(1, NA))
  names(named) <- c("a", "b")
  expect_identical(names(named + 1), c("a", "b"))
})

test_that("results Stata cannot hold are .", {
  expect_identical(shown(x / 0), rep(".", 4))
  expect_identical(shown(dta_num(1e308) * 10), ".")
  expect_identical(shown(x %% 0), rep(".", 4))
  expect_identical(shown(log(x - 3)), c(".", ".", ".", "."))
  expect_identical(shown(sqrt(x - 4)), rep(".", 4))
})

test_that("results are new dta_num values that compare as Stata does", {
  y <- x + 1
  expect_s3_class(y, "dta_num")
  expect_identical(attributes(y), list(storage = "double", class = "dta_num"))
  expect_identical(y > 5, c(FALSE, TRUE, TRUE, FALSE))
  expect_identical(y == NA, c(FALSE, TRUE, TRUE, FALSE))
  expect_identical(y == .a, rep(FALSE, 4))
})

test_that("math functions of missing values are .", {
  expect_identical(shown(abs(-x)), c("3", ".", ".", "0"))
  # R's round(), to digits (Stata's round() takes a unit instead).
  expect_identical(shown(round(x / 2, 1)), c("1.5", ".", ".", "0"))
  expect_identical(shown(round(dta_num(2.5))), "2")
  expect_identical(shown(floor(x / 2)), c("1", ".", ".", "0"))
  expect_identical(shown(exp(x * 0)), c("1", ".", ".", "1"))
  expect_s3_class(abs(x), "dta_num")
})

test_that("in logic, missing values are true", {
  expect_identical(x & TRUE, c(TRUE, TRUE, TRUE, FALSE))
  expect_identical(x | FALSE, c(TRUE, TRUE, TRUE, FALSE))
  expect_identical(!x, c(FALSE, FALSE, FALSE, TRUE))
  expect_identical(!.a, FALSE)
  expect_identical(NA | x, rep(TRUE, 4))
  expect_identical(x & NA, c(TRUE, TRUE, TRUE, FALSE))
  expect_identical(x & c(0, 0, 1, 1), c(FALSE, FALSE, TRUE, FALSE))
  expect_identical(x & x, c(TRUE, TRUE, TRUE, FALSE))
  expect_false(anyNA(x | NA))
  # Comparisons give plain logicals, so combining them is R's & as before.
  expect_identical(x >= 1 & x <= 4, c(TRUE, FALSE, FALSE, FALSE))
  expect_identical(x > 4 | x == 0, c(FALSE, TRUE, TRUE, TRUE))
})

test_that("strings", {
  expect_error(x + "a")
  expect_error(x & "a", "needs numbers or logicals")
  expect_error(suppressWarnings(factor("a") & x))
  expect_identical(x == ".a", c(FALSE, FALSE, TRUE, FALSE))
  expect_identical(is_missing(c("a", "", "b")), c(FALSE, TRUE, FALSE))
})

test_that("sum, max and friends keep R's rules", {
  expect_identical(sum(x), NA_real_)
  expect_identical(max(x, na.rm = TRUE), 3)
})

test_that("a computed column in mutate() stays a dta_num", {
  skip_if_not_installed("dplyr")
  d <- dibble(x = x)
  d <- dplyr::mutate(d, y = x * 2, big = y > 4)
  expect_s3_class(d$y, "dta_num")
  expect_identical(d$big, c(TRUE, TRUE, TRUE, FALSE))
})

test_that("mixing with haven's labelled falls back to R's rules", {
  skip_if_not_installed("haven")
  h <- haven::labelled(c(1, 2, NA, 4), c(One = 1))
  # R cannot choose between the two classes' methods: it warns and adds
  # the plain numbers (keeping the first operand's attributes).
  expect_warning(r <- x + h, "Incompatible methods")
  expect_identical(as.vector(unclass(r))[c(1, 4)], c(4, 4))
})
