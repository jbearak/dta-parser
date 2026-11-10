# datakit reaches dtaparser's Parquet functions through C callables
# (plan 0018), and attached last, its := is the one R finds.

test_that("a dtaparser with another ABI number is refused", {
  expect_invisible(datakit:::check_abi(5L, 5L))
  expect_identical(datakit:::DTAPARSER_ABI, 5L)
  # A dtaparser 3.1.0 still has the Arrow stream callables.
  expect_error(datakit:::check_abi(4L, 5L), "reinstall dtaparser")
  expect_error(datakit:::check_abi(NA_integer_, 5L), "reinstall dtaparser")
  # A dtaparser of the same ABI from before read_parquet_info()$key_value.
  expect_error(datakit:::key_value_table(NULL), "reinstall dtaparser")
})

test_that("attached after dplyr, as a translated script does, datakit's := is found", {
  skip_if_not_installed("dplyr")
  out <- fresh_r(c(
    "suppressPackageStartupMessages({library(dplyr); library(dtaparser); library(datakit)})",
    "d <- tibble::tibble(x = 1:3)",
    "d[x > 1, y] := x * 2",
    "cat(identical(`:=`, datakit::`:=`), d$y, '\\n')"
  ))
  expect_identical(out, "TRUE NA 4 6 ")
})
