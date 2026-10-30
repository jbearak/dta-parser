# dtatools reads through dtaparser's C functions (ADR 0016).

test_that("dtatools loads and reads in a fresh R without dtaparser attached", {
  path <- file.path(fixture_dir, "haven_118.dta")
  skip_if_not(file.exists(path))
  rscript <- file.path(R.home("bin"), "Rscript")
  libs <- paste0("R_LIBS=", paste(.libPaths(), collapse = .Platform$path.sep))
  code <- sprintf(paste(
    'library(dtatools)',
    'e <- tryCatch(read_dta("%s.missing"), error = function(e) "error")',
    'x <- read_dta("%s", col_select = "row")',
    'cat(e, class(x)[[1]], class(x$row), "package:dtaparser" %%in%% search(), sep = ",")',
    sep = "; "), path, path)
  out <- suppressWarnings(system2(rscript, c("-e", shQuote(code)), stdout = TRUE, stderr = TRUE, env = libs))
  out <- out[!grepl("^OMP:", out)]
  expect_identical(out, "error,dibble,dta_num,FALSE")
})

test_that("a dtaparser with another ABI number is refused", {
  expect_invisible(dtatools:::check_abi(1L, 1L))
  expect_error(dtatools:::check_abi(2L, 1L), "reinstall dtaparser")
  expect_error(dtatools:::check_abi(NA_integer_, 1L), "reinstall dtaparser")
})
