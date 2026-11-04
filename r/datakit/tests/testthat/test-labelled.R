# := on dtaparser's labelled columns (ADR 0028, ADR 0029): codes widen,
# labels join, and a label assigns its code; read_fixed_width makes the class.

test_that(":= widens labelled codes and keeps class, labels and letters", {
  d <- tibble::tibble(g = c(1, 1, 2), v = with_labels(c(1L, 0L, NA), c(No = 0, Yes = 1), label = "V"))
  e <- d
  e[1, v] := 2.5
  expect_s3_class(e$v, "dtaparser_labelled")
  expect_identical(vctrs::vec_data(e$v), c(2.5, 0, NA))
  expect_identical(val_labels(e$v), c(No = 0, Yes = 1))
  expect_identical(var_label(e$v), "V")
  f <- d
  f[g == 2, v, by = g] := tagged_na("a")
  expect_identical(na_tag(f$v), c(NA, NA, "a"))
  expect_s3_class(f$v, "dtaparser_labelled")
  h <- d
  h[, w] := with_labels(c(0, 1, 0), c(No = 0, Yes = 1))
  expect_s3_class(h$w, "dtaparser_labelled")
  expect_identical(val_label(h$w), c("No", "Yes", "No"))
})

test_that(":= assigns a label's code, widening integer codes for .a to .z", {
  d <- tibble::tibble(v = with_labels(c(1L, 0L, NA), c(No = 0, Yes = 1, tagged_na(c(Refused = "r")))))
  e <- d
  e[3, v] := "No"
  expect_identical(vctrs::vec_data(e$v), c(1L, 0L, 0L))
  f <- d
  f[1, v] := "Refused"
  expect_type(vctrs::vec_data(f$v), "double")
  expect_identical(na_tag(f$v), c("r", NA, NA))
  expect_s3_class(f$v, "dtaparser_labelled")
  expect_error(d[1, v] := "Maybe", "not a label")
})

test_that("read_fixed_width gives the class", {
  dir <- tempfile()
  dir.create(dir)
  writeLines(c(
    "PROC FORMAT; VALUE kidsf 0='None' 98='DK';",
    "DATA; INPUT KIDS 1-2;",
    "FORMAT KIDS kidsf.;"
  ), file.path(dir, "s.sas"))
  writeLines(c(" 2", "98", " 0"), file.path(dir, "s.dat"))
  kids <- read_fixed_width(file.path(dir, "s.dat"), file.path(dir, "s.sas"), recodes = "none")$KIDS
  expect_s3_class(kids, "dtaparser_labelled")
  expect_identical(val_label(kids), c(NA, "DK", "None"))
})

test_that(":= keeps a display format on labelled and plain columns, codes widened or not", {
  x <- with_labels(structure(c(1, 0), format = "%3.0f"), c(No = 0, Yes = 1))
  d <- tibble::tibble(v = x, w = structure(c(1L, 2L), format = "%5.0f"))
  d[1, v] := 2.5
  d[1, w] := 0.5
  d[2, v] := "Yes"
  expect_identical(attr(d$v, "format"), "%3.0f")
  expect_identical(attr(d$w, "format"), "%5.0f")
})
