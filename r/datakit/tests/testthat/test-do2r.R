# The path a do-file translated by do2r takes: dtaparser reads, datakit's
# := recodes, dtaparser's save_dta writes a snapshot, and the snapshot
# reads back as the data was.

test_that("read_dta, then :=, then save_dta reads back the same tibble", {
  src <- tempfile(fileext = ".dta")
  dtaparser::save_dta(tibble::tibble(
    x = c(1L, 2L, 3L, 4L),
    smoker = with_labels(c(1, 0, tagged_na("d"), NA), c(No = 0, Yes = 1, tagged_na(c("Don't know" = "d"))),
                         label = "Smokes daily"),
    seen = as.Date(c("2024-01-15", "2024-02-01", NA, "2023-12-31"))
  ), src)
  d <- dtaparser::read_dta(src)
  d[x > 1, y] := 1
  d[x == 4, smoker] := "Don't know"
  d[seen < as.Date("2024-01-20"), early] := 1L
  expect_identical(d$y, c(NA, 1, 1, 1))
  expect_identical(na_tag(d$smoker), c(NA, NA, "d", "d"))

  out <- tempfile(fileext = ".dta")
  dtaparser::save_dta(d, out)
  back <- dtaparser::read_dta(out)
  expect_identical(back, d)
  expect_s3_class(back$seen, "Date")
  expect_s3_class(back$smoker, "dtaparser_labelled")
  expect_identical(val_label(back$smoker), c("Yes", "No", "Don't know", "Don't know"))
  expect_identical(var_label(back$smoker), "Smokes daily")
  expect_identical(back$early, c(1L, NA, NA, 1L))
})
