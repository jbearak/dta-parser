x <- dta_num(c(0, 1, .d, 2, .g), labels = c(No = 0, Yes = 1, `Not in universe` = .g, `No response` = .d))

test_that("val_labels gives the codes named by their text", {
  labels <- val_labels(x)
  expect_s3_class(labels, "dta_num")
  code <- labels[names(labels) == "Not in universe"]
  expect_identical(x == code, c(FALSE, FALSE, FALSE, FALSE, TRUE))
  expect_null(val_labels(dta_num(1)))
})

test_that("val_label looks up each value, NA where unlabelled", {
  expect_identical(val_label(x, x), c("No", "Yes", "No response", NA, "Not in universe"))
  expect_identical(val_label(x, .g), "Not in universe")
  expect_identical(val_label(dta_num(1), 1), NA_character_)
})

test_that("labelbook lists labels in Stata's order", {
  data <- dibble(x = x, s = "a")
  m <- labelbook(data)$mappings
  expect_identical(m$code_text, c("0", "1", ".d", ".g"))
  expect_identical(m$text, c("No", "Yes", "No response", "Not in universe"))
  expect_identical(unique(m$variable), "x")
})

test_that("dta_setequal and dta_setdiff keep codes apart", {
  expect_true(dta_setequal(c(1, .a), c(.a, 1, 1)))
  expect_false(dta_setequal(.a, .b))
  expect_false(dta_setequal(NA, .a))
  expect_true(dta_setequal(unique(x[3]), .d))
  expect_identical(as.character(dta_setdiff(x, c(0, NA, .g))), c("1", ".d", "2"))
  expect_identical(dta_setdiff(c("a", "b", "a"), "b"), "a")
  expect_true(dta_setequal(c("India 2021", "x"), c("x", "India 2021")))
  # Against character values, numbers compare as Stata writes them.
  expect_identical(length(dta_setdiff(c(NA, .a), character())), 2L)
  expect_false(dta_setequal(c(NA, .a), NA_character_))
  expect_true(dta_setequal(c(NA, .a), c(".", ".a")))
})

test_that("an NA string is a group of its own and does not spoil later groups", {
  expect_identical(dta_group_id(c(1, 1, 2), c("a", NA, "b")), c(1L, 2L, 3L))
  expect_identical(dta_group_tag(c(1, 1, 2), c("a", NA, "b")), c(1L, 1L, 1L))
})

test_that("dta_group_id numbers groups in sorted order; missing values are NA unless missing = TRUE", {
  a <- c(2, 1, NA, 2, .a)
  b <- c("x", "y", "x", "x", "x")
  expect_identical(dta_group_id(a, b, missing = TRUE), c(2L, 1L, 3L, 2L, 4L))
  expect_identical(dta_group_id(a, b), c(2L, 1L, NA, 2L, NA))
  expect_identical(dta_group_id(data.frame(a = a, b = b), missing = TRUE), dta_group_id(a, b, missing = TRUE))
  expect_identical(dta_group_tag(a, b, missing = TRUE), c(1L, 1L, 1L, 0L, 1L))
  expect_identical(dta_group_tag(a, b), c(1L, 1L, 0L, 0L, 0L))
})

test_that("tab counts each value, named as Stata writes it", {
  expect_identical(tab(x), c(`0` = 1L, `1` = 1L, `2` = 1L))
  expect_identical(tab(x, missing = TRUE), c(`0` = 1L, `1` = 1L, `2` = 1L, .d = 1L, .g = 1L))
  expect_identical(tab(c("b", "a", "b", "")), c(a = 1L, b = 2L))
})
