# dtatools reads through dtaparser's C functions (ADR 0016).

test_that("dtatools loads and reads in a fresh R without dtaparser attached", {
  path <- file.path(fixture_dir, "haven_118.dta")
  skip_if_not(file.exists(path))
  # The code goes in a file and R_LIBS through the environment, since
  # system2() quotes differently on Windows and ignores its `env` there.
  script <- tempfile(fileext = ".R")
  writeLines(c(
    'library(dtatools)',
    sprintf('e <- tryCatch(read_dta(%s), error = function(e) "error")', deparse(paste0(path, ".missing"))),
    sprintf('x <- read_dta(%s, col_select = "row")', deparse(path)),
    'cat(e, class(x)[[1]], class(x$row), "package:dtaparser" %in% search(), sep = ",")'
  ), script)
  old <- Sys.getenv("R_LIBS", unset = NA)
  Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  on.exit(if (is.na(old)) Sys.unsetenv("R_LIBS") else Sys.setenv(R_LIBS = old))
  rscript <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(rscript, shQuote(script), stdout = TRUE, stderr = TRUE))
  out <- out[!grepl("^OMP:", out)]
  expect_identical(out, "error,dibble,dta_num,FALSE")
})

test_that("a dtaparser with another ABI number is refused", {
  expect_invisible(dtatools:::check_abi(1L, 1L))
  expect_error(dtatools:::check_abi(2L, 1L), "reinstall dtaparser")
  expect_error(dtatools:::check_abi(NA_integer_, 1L), "reinstall dtaparser")
  expect_identical(dtatools:::DTAPARSER_ABI, 5L)
})
