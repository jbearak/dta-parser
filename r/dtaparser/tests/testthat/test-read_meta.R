# read_meta gives what the file says about itself. Files from dtaparser's
# writer are checked against what the test wrote; readstata13 is the
# oracle for storage types, formats and labels (AGENTS.md).

# readstata13's storage type codes as names (as in compat/expected.R).
rs13_type <- function(t, release) {
  if (release >= 117) {
    switch(as.character(t), `65530` = "byte", `65529` = "int", `65528` = "long",
           `65527` = "float", `65526` = "double", `32768` = "strL", paste0("str", t))
  } else {
    switch(as.character(t), `251` = "byte", `252` = "int", `253` = "long",
           `254` = "float", `255` = "double", paste0("str", t))
  }
}

test_that("read_meta gives each storage type, format and label", {
  long <- strrep("x", 3000)
  path <- write_fixture(
    b = col(1:2, "byte"), i = col(1:2, "int", "%8.0g"), l = col(1:2, "long", "%12.0g"),
    f = col(c(1.5, 2), "float"), d = col(c(1, 2), "double", "%10.0g"),
    s = col(c("abc", "a"), "", "%-9s"), sl = col(c(long, "a"), "", "%-9s"),
    yn = col(c(1, 0), "byte", "%8.0g", labels = c(No = 0, Yes = 1)),
    data_label = "Storage types"
  )
  on.exit(unlink(path))
  meta <- read_meta(path)
  expect_named(meta, c("release", "nobs", "label", "timestamp", "variables", "sort_order", "value_labels",
                       "notes", "characteristics"))
  expect_identical(meta$release, 118L)
  expect_identical(meta$nobs, 2)
  expect_identical(meta$label, "Storage types")
  expect_identical(meta$timestamp, "01 Jan 2026 00:00")
  v <- meta$variables
  expect_s3_class(v, "tbl_df")
  expect_identical(v$name, c("b", "i", "l", "f", "d", "s", "sl", "yn"))
  expect_identical(v$storage, c("byte", "int", "long", "float", "double", "str3", "strL", "byte"))
  expect_identical(v$format, c("%9.0g", "%8.0g", "%12.0g", "%9.0g", "%10.0g", "%-9s", "%-9s", "%8.0g"))
  expect_identical(v$label, rep("", 8))
  expect_identical(v$label_set, c(rep("", 7), "yn"))
  expect_identical(meta$value_labels, list(yn = c(No = 0, Yes = 1)))
  expect_identical(meta$sort_order, character())
  expect_identical(meta$notes, character())
  expect_identical(nrow(meta$characteristics), 0L)

  skip_if_not_installed("readstata13")
  r <- attributes(suppressWarnings(readstata13::read.dta13(path, convert.factors = FALSE)))
  expect_identical(v$storage, vapply(r$types, rs13_type, "", r$version))
})

test_that("read_meta gives the sort order by name, empty when unsorted", {
  cols <- list(id = col(1:3, "long"), wave = col(c(1L, 1L, 2L), "byte"), x = col(c(0.5, 1, 2), "double"))
  unsorted <- do.call(write_fixture, cols)
  one <- do.call(write_fixture, c(cols, list(sort_order = "id")))
  # Keys in an order other than the file's.
  two <- do.call(write_fixture, c(cols, list(sort_order = c("wave", "id"))))
  on.exit(unlink(c(unsorted, one, two)))
  expect_identical(read_meta(unsorted)$sort_order, character())
  expect_identical(read_meta(one)$sort_order, "id")
  expect_identical(read_meta(two)$sort_order, c("wave", "id"))
})

test_that("read_meta keeps value labels on .a to .z, notes and characteristics", {
  path <- write_fixture(x = col(c(1, tagged_na("d")), "double", labels = c(Yes = 1, tagged_na(c(DK = "d")))))
  on.exit(unlink(path))
  labels <- read_meta(path)$value_labels$x
  expect_identical(names(labels), c("Yes", "DK"))
  expect_identical(na_tag(labels), c(Yes = NA, DK = "d"))
  expect_identical(labels, val_labels(read_dta(path)$x))

  df <- data.frame(x = structure(1:2, label = "An x"))
  attr(df, "notes") <- c("first", "second")
  attr(df, "characteristics") <- data.frame(variable = c("_dta", "x"), name = c("source", "unit"),
                                            value = c("made up", "cm"))
  attr(df, "timestamp") <- ""
  path2 <- tempfile(fileext = ".dta")
  on.exit(unlink(path2), add = TRUE)
  save_dta(df, path2)
  meta <- read_meta(path2)
  expect_identical(meta$timestamp, "")
  expect_identical(meta$variables$label, "An x")
  expect_identical(meta$notes, c("first", "second"))
  expect_identical(meta$characteristics,
                   tibble::tibble(variable = c("_dta", "x"), name = c("source", "unit"), value = c("made up", "cm")))
})

test_that("read_meta matches readstata13 on every fixture", {
  skip_if_not_installed("readstata13")
  for (path in fixtures()) {
    name <- basename(path)
    meta <- read_meta(path)
    d <- suppressWarnings(readstata13::read.dta13(path, convert.factors = FALSE, missing.type = TRUE))
    r <- attributes(d)
    v <- meta$variables
    expect_identical(v$name, names(d), label = name)
    expect_identical(v$storage, vapply(r$types, rs13_type, "", r$version, USE.NAMES = FALSE), label = name)
    expect_identical(v$format, r$formats, label = name)
    expect_identical(v$label, r$var.labels, label = name)
    expect_identical(v$label_set, unname(r$val.labels), label = name)
    expect_identical(meta$release, r$version, label = name)
    expect_identical(meta$nobs, as.double(nrow(d)), label = name)
    expect_identical(meta$label, r$datalabel, label = name)
    expect_identical(read_meta(path)$sort_order, character(), label = name)
  }
})

test_that("read_meta reads no rows and checks its file", {
  path <- write_fixture(x = col(seq_len(1e5), "long"))
  on.exit(unlink(path))
  expect_identical(read_meta(path)$nobs, 1e5)
  expect_error(read_meta(tempfile(fileext = ".dta")))
})
