# A string R cannot hold (here one with a NUL in it) is an ordinary error
# at read time, and the session carries on. Errors raised partway through
# a read must not jump through dtatools' Rust code; see the comments in
# src/init.c.

test_that("an error mid-read is an ordinary error", {
  path <- file.path(fixture_dir, "haven_118.dta")
  skip_if_not(file.exists(path))
  bytes <- readBin(path, "raw", file.size(path))
  strls <- grepRaw("<strls>", bytes, fixed = TRUE)
  text <- strls + grepRaw("long text", bytes[-seq_len(strls)], fixed = TRUE)
  bytes[text + 2] <- as.raw(0)
  damaged <- tempfile(fileext = ".dta")
  writeBin(bytes, damaged)

  expect_error(read_dta(damaged, col_select = "big"), "nul")
  # Everything still works afterwards, including a read of the same file
  # that avoids the damaged column.
  expect_identical(nrow(read_dta(damaged, col_select = "row")), 6L)
  expect_identical(read_dta(path, col_select = "text")$text[[2]], "café")
})
