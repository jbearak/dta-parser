test_that("dibble makes Stata columns from plain ones", {
  d <- dibble(dbl = c(1.5, NA, .d), int = c(1L, NA, 3L), lgl = c(TRUE, FALSE, NA),
              chr = c("a", "b", "c"), fct = factor(c("u", "v", "u")),
              day = as.Date(c("1960-01-02", NA, "1959-12-31")), one = 7)
  expect_s3_class(d, c("dibble", "tbl_df"))
  expect_identical(vapply(d[c("dbl", "int", "lgl", "day", "one")], attr, "", "storage"),
                   c(dbl = "double", int = "long", lgl = "byte", day = "long", one = "double"))
  expect_identical(d$dbl == .d, c(FALSE, FALSE, TRUE))
  expect_identical(d$chr, c("a", "b", "c"))
  expect_identical(d$fct, c("u", "v", "u"))
  expect_identical(as.vector(unclass(d$day)), c(1, NA, -1))
  expect_identical(attr(d$day, "format"), "%td")
  expect_identical(as.vector(unclass(d$one)), c(7, 7, 7))
  expect_error(dibble(x = as.POSIXct("2020-01-01")), "POSIXct")
})

test_that("haven labelled columns keep their labels", {
  skip_if_not_installed("haven")
  d <- dibble(x = haven::labelled(c(1, haven::tagged_na("a")), c(Yes = 1, Refused = haven::tagged_na("a")),
                                 label = "Q1"))
  expect_identical(val_label(d$x, d$x), c("Yes", "Refused"))
  expect_identical(attr(d$x, "label"), "Q1")
})

test_that("subsetting a dibble keeps codes and labels", {
  d <- dibble(x = dta_num(c(1, .a, NA), labels = c(A = .a)), s = c("p", "q", "r"))
  sub <- d[c(FALSE, TRUE, TRUE), , drop = FALSE]
  expect_s3_class(sub, "dibble")
  expect_identical(sub$x == .a, c(TRUE, FALSE))
  expect_identical(names(attr(sub$x, "labels")), "A")
  expect_identical(d[["x"]] == .a, c(FALSE, TRUE, FALSE))
  expect_identical(rlang::eval_tidy(quote(x == .a), d), c(FALSE, TRUE, FALSE))
  expect_identical(nrow(d[d$s %in% c("p", "r"), ]), 2L)
})

test_that("dplyr's mutate, filter and group_by keep codes and labels", {
  skip_if_not_installed("dplyr")
  d <- dibble(x = dta_num(c(1, .a, .b, .a, 2), labels = c(A = .a)), g = c(1, 1, 2, 2, 2))
  out <- dplyr::mutate(d, y = x)
  expect_identical(out$y == .b, c(FALSE, FALSE, TRUE, FALSE, FALSE))
  expect_identical(names(attr(out$y, "labels")), "A")
  kept <- dplyr::filter(d, x != .a)
  expect_identical(as.character(kept$x), c("1", ".b", "2"))
  counts <- dplyr::summarise(dplyr::group_by(d, x), n = dplyr::n())
  expect_identical(as.character(counts$x), c("1", "2", ".a", ".b"))
  expect_identical(counts$n, c(1L, 1L, 2L, 1L))
  grouped <- dplyr::mutate(dplyr::group_by(d, g), first = x[1])
  expect_identical(as.character(grouped$first), c("1", "1", ".b", ".b", ".b"))
})

test_that("read_dta returns a dibble, and save_dta writes one", {
  d <- dibble(x = c(1, .z), s = c("a", "b"))
  path <- tempfile(fileext = ".dta")
  save_dta(d, path)
  again <- read_dta(path)
  expect_s3_class(again, "dibble")
  expect_identical(again$x == .z, c(FALSE, TRUE))
})
