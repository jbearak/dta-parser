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

test_that("arithmetic gives new dta_num values, every code as . (test-stata-math.R)", {
  expect_identical(numbers(x + 1), c(2, NA, NA, NA, 6))
  expect_s3_class(x * 2, "dta_num")
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

test_that("c() takes recursive and use.names as arguments, not values", {
  y <- c(dta_num(c(a = 1)), b = 2, use.names = FALSE)
  expect_identical(as.vector(unclass(y)), c(1, 2))
  expect_null(names(y))
  expect_identical(length(c(dta_num(1), 2, recursive = TRUE)), 2L)
})

test_that("matching keeps codes apart when both sides are dta_num", {
  x <- dta_num(c(NA, .a, 1))
  expect_identical(x %in% c(.a, 1), c(FALSE, TRUE, TRUE))
  expect_identical(c(.a, 1) %in% x, c(TRUE, TRUE))
})

test_that("an empty dta_num formats and prints", {
  expect_identical(format(dta_num()), character())
  expect_silent(capture.output(print(dta_num())))
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

test_that("a tibble shows each labelled value with its label, as haven's labelled columns do", {
  old <- options(width = 80, cli.num_colors = 1)
  on.exit(options(old), add = TRUE)
  d <- dibble(x = dta_num(c(1, 0, .r, NA, 1.5), labels = c(No = 0, Yes = 1, Refused = .r)),
              y = dta_num(c(1, 2, 3, .a, NA)))
  out <- capture.output(print(d))
  expect_match(out[3], "<dta\\+lbl> +<dta>")
  expect_match(out[4], "^1 1.0 \\[Yes\\] ")
  expect_match(out[5], "^2 0.0 \\[No\\] ")
  expect_match(out[6], "^3  .r \\[Refused\\] ")
  expect_match(out[7], "^4   \\. +\\.a")
  expect_match(out[8], "^5 1.5 +\\.")
  # A column without labels shows only its values.
  expect_identical(vctrs::vec_ptype_abbr(d$y), "dta")
  expect_false(any(grepl("[", substring(out[4:8], 18), fixed = TRUE)))
})

test_that("print() lists a dta_num's labels after its values", {
  x <- dta_num(c(1, .r), labels = c(Refused = .r, Yes = 1), label = "Wants")
  out <- capture.output(print(x))
  expect_identical(out[1], "<Wants>")
  labels <- out[(which(out == "Labels:") + 1):length(out)]
  expect_length(labels, 3)
  expect_match(labels[1], "value +label")
  expect_match(labels[2], "1 +Yes")
  expect_match(labels[3], "\\.r +Refused")
  expect_false(any(grepl("Labels:", capture.output(print(dta_num(1))))))
})
