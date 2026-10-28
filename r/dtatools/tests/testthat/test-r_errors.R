# An R error raised while read_dta builds its result (here R refusing a
# string with a NUL in it) comes back as an ordinary R error, and the
# session carries on. dtatools must not let R's error jump through its
# Rust code; see the comments in src/init.c.

test_that("an R error mid-read is an ordinary error", {
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
