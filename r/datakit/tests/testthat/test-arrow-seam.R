# dtaparser's Arrow stream callables (plan 0025, stage 3), which
# datakit's polars functions call: here through nanoarrow alone, so that
# what the native layer owns and releases is tested without polars.

arrow_streams <- function() {
  list(data = nanoarrow::nanoarrow_allocate_array_stream(), letters = nanoarrow::nanoarrow_allocate_array_stream())
}

no_meta <- function() {
  list(NULL, NULL, character(), character(), list(character(), character(), character()),
       list(character(), character(), character(), character(), logical()), list(character(), list(), list()),
       list(character(), list()))
}

letters_parquet <- function() {
  p <- tempfile(fileext = ".parquet")
  d <- data.frame(id = 1:4, x = with_labels(c(1, tagged_na("a"), NA, tagged_na("b")),
                                            c(One = 1, tagged_na(c(Refused = "a")))))
  attr(d, "label") <- "Survey"
  save_parquet(d, p)
  p
}

test_that("a Parquet read fills both streams and returns the metadata list", {
  skip_if_not_installed("nanoarrow")
  s <- arrow_streams()
  m <- .Call(C_dta_parquet_read_arrow, letters_parquet(), NULL, 0, Inf, c("error", "error"), s$data, s$letters)
  expect_identical(m$rows, 4)
  expect_identical(m$names, c("id", "x"))
  expect_identical(m$label, "Survey")
  expect_identical(m$letter_columns, "x")
  expect_identical(m$columns$value_labels, c(NA, "x"))
  expect_identical(names(m$value_labels$x), c("One", "Refused"))
  expect_identical(na_tag(unname(m$value_labels$x)), c(NA, "a"))
  df <- as.data.frame(s$data)
  expect_identical(df$id, 1:4)
  # The letters are nulls in the frame; their stream holds them.
  expect_identical(df$x, c(1, NA, NA, NA))
  # A dictionary of .a to .z (polars' Enum), by its keys: nanoarrow's
  # conversion of an ordered dictionary fails.
  x <- s$letters$get_next()$children$x
  expect_identical(x$null_count, 2L)
  levels <- nanoarrow::convert_array(x$dictionary)
  expect_identical(levels, paste0(".", letters))
  keys <- nanoarrow::convert_buffer(x$buffers[[2]])
  expect_identical(levels[keys[c(2, 4)] + 1], c(".a", ".b"))
})

test_that("a .dta read gives its release, and no letters stream when no column holds one", {
  skip_if_not_installed("nanoarrow")
  p <- tempfile(fileext = ".dta")
  save_dta(data.frame(a = c(1, NA), s = c("x", "y")), p)
  s <- arrow_streams()
  m <- .Call(C_dta_dta_read_arrow, p, "s", 1, Inf, NULL, "error", s$data, s$letters)
  expect_identical(m$release, 118)
  expect_identical(m$names, "s")
  expect_identical(as.data.frame(s$data)$s, "y")
  expect_identical(m$letter_columns, character())
  expect_false(nanoarrow::nanoarrow_pointer_is_valid(s$letters))
})

test_that("a failing read leaves both streams empty", {
  skip_if_not_installed("nanoarrow")
  s <- arrow_streams()
  expect_error(.Call(C_dta_parquet_read_arrow, letters_parquet(), "nope", 0, Inf, c("error", "error"),
                     s$data, s$letters), "nope")
  expect_false(nanoarrow::nanoarrow_pointer_is_valid(s$data))
  expect_false(nanoarrow::nanoarrow_pointer_is_valid(s$letters))
  expect_error(.Call(C_dta_dta_read_arrow, tempfile(), NULL, 0, Inf, NULL, "error", s$data, s$letters))
  expect_false(nanoarrow::nanoarrow_pointer_is_valid(s$data))
  # A stream that already holds one is refused, not overwritten.
  full <- nanoarrow::as_nanoarrow_array_stream(data.frame(a = 1))
  expect_error(.Call(C_dta_parquet_read_arrow, letters_parquet(), NULL, 0, Inf, c("error", "error"),
                     full, s$letters), "already holds a stream")
  expect_true(nanoarrow::nanoarrow_pointer_is_valid(full))
})

test_that("arrays outlive the stream that gave them", {
  skip_if_not_installed("nanoarrow")
  s <- arrow_streams()
  .Call(C_dta_parquet_read_arrow, letters_parquet(), NULL, 0, Inf, c("error", "error"), s$data, s$letters)
  batch <- s$data$get_next()
  nanoarrow::nanoarrow_pointer_release(s$data)
  rm(s)
  for (i in 1:5) gc()
  expect_identical(as.data.frame(batch)$id, 1:4)
})

test_that("a write takes the stream: a second write of it is an error", {
  skip_if_not_installed("nanoarrow")
  st <- nanoarrow::as_nanoarrow_array_stream(data.frame(a = c(1.5, NA), b = c("u", "v")))
  q <- tempfile(fileext = ".parquet")
  .Call(C_dta_parquet_write_arrow, st, q, no_meta(), list("snappy", NULL, NULL, TRUE, "error"))
  expect_false(nanoarrow::nanoarrow_pointer_is_valid(st))
  expect_identical(read_parquet(q)$b, c("u", "v"))
  expect_error(.Call(C_dta_parquet_write_arrow, st, q, no_meta(), list("snappy", NULL, NULL, TRUE, "error")),
               "this stream was consumed")
  expect_error(.Call(C_dta_dta_write_arrow, st, tempfile(), no_meta(), list(TRUE, "error")),
               "this stream was consumed")
})

test_that("a failing write releases the stream once, and the letters' streams it took", {
  skip_if_not_installed("nanoarrow")
  # A column name Stata cannot hold fails the .dta write after the take.
  st <- nanoarrow::as_nanoarrow_array_stream(data.frame(`1bad` = 1, check.names = FALSE))
  expect_error(.Call(C_dta_dta_write_arrow, st, tempfile(fileext = ".dta"), no_meta(), list(TRUE, "error")),
               "not a name Stata can hold")
  expect_false(nanoarrow::nanoarrow_pointer_is_valid(st))
  # A letters stream of the wrong length fails after both were taken.
  st <- nanoarrow::as_nanoarrow_array_stream(data.frame(x = c(NA_real_, NA_real_)))
  lt <- nanoarrow::as_nanoarrow_array_stream(data.frame(x = ".a"))
  meta <- no_meta()
  meta[[8]] <- list("x", list(lt))
  q <- tempfile(fileext = ".parquet")
  expect_error(.Call(C_dta_parquet_write_arrow, st, q, meta, list("snappy", NULL, NULL, TRUE, "error")), "1 rows")
  expect_false(nanoarrow::nanoarrow_pointer_is_valid(st))
  expect_false(nanoarrow::nanoarrow_pointer_is_valid(lt))
  expect_false(file.exists(q))
  for (i in 1:3) gc()
  # A letters stream already taken is refused before anything is.
  st <- nanoarrow::as_nanoarrow_array_stream(data.frame(x = NA_real_))
  expect_error(.Call(C_dta_parquet_write_arrow, st, q, meta, list("snappy", NULL, NULL, TRUE, "error")),
               "this stream was consumed")
  expect_true(nanoarrow::nanoarrow_pointer_is_valid(st))
})

test_that("a write keeps the letters and meta it is given", {
  skip_if_not_installed("nanoarrow")
  st <- nanoarrow::as_nanoarrow_array_stream(data.frame(x = c(1, NA, NA)))
  lt <- nanoarrow::as_nanoarrow_array_stream(data.frame(x = c(NA, ".d", NA)))
  meta <- no_meta()
  meta[[1]] <- "Data"
  meta[[5]] <- list("x", "note", "hello")
  meta[[6]] <- list("x", "Smokes", NA_character_, "yesno", NA)
  meta[[7]] <- list("yesno", list(c(1, tagged_na("d"))), list(c("Yes", "Don't know")))
  meta[[8]] <- list("x", list(lt))
  p <- tempfile(fileext = ".dta")
  .Call(C_dta_dta_write_arrow, st, p, meta, list(TRUE, "error"))
  back <- read_dta(p)
  expect_identical(na_tag(back$x), c(NA, "d", NA))
  expect_identical(var_label(back$x), "Smokes")
  expect_identical(attr(back, "label"), "Data")
  expect_identical(val_label(back$x), c("Yes", "Don't know", NA))
})

test_that("a fixed-width file becomes a .dta file, with the setup's warnings", {
  dir <- tempfile()
  dir.create(dir)
  writeLines(c("DATA; INPUT ID 1-3 KIDS 4-5;", "IF (KIDS = 98) THEN KIDS = .;", "RUN;", "PROC PRINT; RUN;"),
             file.path(dir, "s.sas"))
  writeLines(c("001 2", "00298"), file.path(dir, "s.dat"))
  out <- file.path(dir, "s.dta")
  w <- .Call(C_dta_fixed_width_dta, file.path(dir, "s.dat"), file.path(dir, "s.sas"), out, "tagged", TRUE)
  expect_type(w, "character")
  expect_true(length(w) >= 1)
  expect_identical(na_tag(read_dta(out)$KIDS), c(NA, "a"))
  # The file must be new.
  expect_error(.Call(C_dta_fixed_width_dta, file.path(dir, "s.dat"), file.path(dir, "s.sas"), out, "tagged", TRUE))
})
