# save_dta writes release 118 that reads back as written: through
# read_dta, and through haven and readstata13 (independent of us; pandas
# is checked by compat/readback.py).

# NA tags, as in test-read_dta.R: NA for a number, "" for ., or the letter.
tags <- function(x) {
  x <- unclass(x)
  ifelse(is.na(x), ifelse(is.na(haven::na_tag(x)), "", haven::na_tag(x)), NA)
}

roundtrip <- function(data) {
  path <- tempfile(fileext = ".dta")
  save_dta(data, path)
  path
}

test_that("every fixture survives read_dta, save_dta, read_dta", {
  skip_if_not_installed("haven")
  for (fixture in fixtures()) {
    original <- read_dta(fixture)
    path <- roundtrip(original)
    again <- read_dta(path)
    what <- basename(fixture)
    expect_identical(names(again), names(original), label = what)
    expect_identical(attr(again, "label"), attr(original, "label"), label = what)
    for (a in c("notes", "characteristics", "sort_order")) {
      expect_identical(attr(again, a), attr(original, a), label = paste(what, a))
    }
    # A file without a timestamp gets the writer's (the current time).
    if (is.null(attr(original, "timestamp"))) {
      expect_match(attr(again, "timestamp"), "^\\d\\d [A-Z][a-z]{2} \\d{4} \\d\\d:\\d\\d$", label = what)
    } else {
      expect_identical(attr(again, "timestamp"), attr(original, "timestamp"), label = what)
    }
    for (col in names(original)) {
      x <- original[[col]]
      y <- again[[col]]
      expect_identical(as.vector(unclass(y)), as.vector(unclass(x)), label = paste(what, col))
      for (a in c("label", "format", "storage", "labels", "label_set")) {
        expect_identical(attr(y, a, exact = TRUE), attr(x, a, exact = TRUE), label = paste(what, col, a))
      }
      if (is.numeric(x)) expect_identical(tags(y), tags(x), label = paste(what, col))
    }
    # haven and readstata13 read the same values back.
    h <- haven::read_dta(path)
    for (col in names(original)) {
      x <- original[[col]]
      y <- h[[col]]
      if (inherits(y, "Date")) y <- as.numeric(y - as.Date("1960-01-01"))
      if (is.character(x)) {
        # haven 2.5.5 drops trailing blanks from strN values.
        expect_identical(sub(" +$", "", as.vector(y)), sub(" +$", "", as.vector(x)), label = paste(what, col))
      } else {
        expect_identical(as.vector(unclass(y)), as.vector(unclass(x)), label = paste(what, col))
        expect_identical(tags(y), tags(x), label = paste(what, col))
        expect_identical(names(attr(y, "labels")), names(attr(x, "labels")), label = paste(what, col))
      }
    }
    if (requireNamespace("readstata13", quietly = TRUE)) {
      r <- suppressWarnings(readstata13::read.dta13(path, convert.factors = FALSE, convert.dates = FALSE,
                                                    missing.type = TRUE, replace.strl = TRUE))
      for (col in names(original)) {
        x <- original[[col]]
        if (is.character(x)) {
          y <- r[[col]]
          y[is.na(y)] <- ""  # readstata13 reads an empty strL as NA
          expect_identical(y, as.vector(x), label = paste("readstata13", what, col))
        } else {
          numbers <- !is.na(unclass(x))
          expect_identical(as.double(r[[col]][numbers]), as.vector(unclass(x))[numbers], label = paste("readstata13", what, col))
          code <- attr(r, "missing")[[col]]
          letters_read <- ifelse(code == 0, "", letters[pmax(code, 1)])
          expect_identical(letters_read[!numbers], tags(x)[!numbers], label = paste("readstata13", what, col))
        }
      }
    }
  }
})

test_that("plain columns get storage types, and tagged NAs their codes", {
  data <- data.frame(i = c(1L, NA, 3L), d = c(1.5, haven::tagged_na("q"), NA),
                     l = c(TRUE, FALSE, NA), s = c("a", NA, "ccc"))
  again <- read_dta(roundtrip(data))
  expect_identical(attr(again$i, "storage"), "long")
  expect_identical(attr(again$d, "storage"), "double")
  expect_identical(attr(again$l, "storage"), "byte")
  expect_identical(as.vector(unclass(again$l)), c(1, 0, NA))
  expect_identical(tags(again$d), c(NA, "q", ""))
  expect_identical(again$s, structure(c("a", "", "ccc"), format = "%-3s"))
})

test_that("a value outside its storage type is an error, and no file is left", {
  data <- data.frame(x = c(1, 200))
  attr(data$x, "storage") <- "byte"
  path <- tempfile(fileext = ".dta")
  expect_error(save_dta(data, path), "does not fit storage type byte")
  expect_false(file.exists(path))
})

test_that("notes and labels on missing codes round-trip", {
  x <- c(1, 2, haven::tagged_na("d"))
  attr(x, "labels") <- c(Yes = 1, No = 2, `Don't know` = haven::tagged_na("d"))
  data <- structure(list(x = x), class = "data.frame", row.names = c(NA, -3L),
                    label = "Data", notes = c("first", "second"))
  again <- read_dta(roundtrip(data))
  expect_identical(attr(again, "notes"), c("first", "second"))
  expect_identical(attr(again, "label"), "Data")
  expect_identical(names(attr(again$x, "labels")), c("Yes", "No", "Don't know"))
  expect_identical(unname(tags(attr(again$x, "labels"))), c(NA, NA, "d"))
})

with_metadata <- function() {
  data <- dibble(a = c(1, 1, 2), b = c(1, 2, 1), c = c("x", "y", "z"))
  attr(data, "timestamp") <- "05 Mar 2024 09:07"
  attr(data, "notes") <- c("first", "second")
  attr(data, "characteristics") <- data.frame(
    variable = c("_dta", "a", "b", "c"),
    name = c("origin", "note1", "source", "unit"),
    value = c("test", "about a", "survey", "kg")
  )
  attr(data, "sort_order") <- c("a", "b")
  data
}

test_that("timestamp, notes, characteristics and sort order round-trip", {
  data <- with_metadata()
  again <- read_dta(roundtrip(data))
  for (a in c("timestamp", "notes", "characteristics", "sort_order")) {
    expect_identical(attr(again, a), attr(data, a), label = a)
  }
  # and again, from what read_dta returned
  twice <- read_dta(roundtrip(again))
  for (a in c("timestamp", "notes", "characteristics", "sort_order")) {
    expect_identical(attr(twice, a), attr(data, a), label = a)
  }
  # readstata13, independent of us, reads the same timestamp and
  # characteristics (notes among them, as the file holds them).
  skip_if_not_installed("readstata13")
  r <- readstata13::read.dta13(roundtrip(data))
  expect_identical(attr(r, "time.stamp"), "05 Mar 2024 09:07")
  theirs <- vapply(attr(r, "expansion.fields"), paste, "", collapse = "|")
  ours <- c(do.call(paste, c(attr(data, "characteristics"), sep = "|")),
            "_dta|note0|2", "_dta|note1|first", "_dta|note2|second")
  expect_setequal(theirs, ours)
})

test_that("selecting columns keeps their characteristics and the leading sort keys", {
  path <- roundtrip(with_metadata())
  b_c <- read_dta(path, col_select = c("c", "b"))
  expect_identical(attr(b_c, "characteristics"),
                   data.frame(variable = c("_dta", "b", "c"), name = c("origin", "source", "unit"),
                              value = c("test", "survey", "kg")))
  expect_null(attr(b_c, "sort_order"))  # sorted by a first, which is gone
  a_c <- read_dta(path, col_select = c("a", "c"))
  expect_identical(attr(a_c, "sort_order"), "a")
  expect_identical(attr(a_c, "characteristics")$variable, c("_dta", "a", "c"))
  expect_identical(attr(a_c, "notes"), c("first", "second"))
  # save_dta applies the same rule to columns dropped after reading.
  data <- with_metadata()
  data$a <- NULL
  again <- read_dta(roundtrip(data))
  expect_null(attr(again, "sort_order"))
  expect_identical(attr(again, "characteristics")$variable, c("_dta", "b", "c"))
  data <- with_metadata()
  data$b <- NULL
  expect_identical(attr(read_dta(roundtrip(data)), "sort_order"), "a")
})

test_that("a file without metadata reads as NULL attributes, and save_dta stamps the time", {
  again <- read_dta(roundtrip(data.frame(x = 1)))
  expect_null(attr(again, "characteristics"))
  expect_null(attr(again, "sort_order"))
  expect_null(attr(again, "notes"))
  expect_match(attr(again, "timestamp"), "^\\d\\d [A-Z][a-z]{2} \\d{4} \\d\\d:\\d\\d$")
})

test_that("as_dibble keeps the dataset's attributes", {
  data <- with_metadata()
  plain <- as.data.frame(data)
  for (a in c("timestamp", "notes", "characteristics", "sort_order")) attr(plain, a) <- attr(data, a)
  back <- as_dibble(plain)
  for (a in c("timestamp", "notes", "characteristics", "sort_order")) {
    expect_identical(attr(back, a), attr(data, a), label = a)
  }
})

test_that("ALTREP columns (compact sequences, deferred strings) are written", {
  data <- data.frame(i = 1:5, d = as.double(1:5))
  data$s <- as.character(1:5)  # a deferred string vector
  again <- read_dta(roundtrip(data))
  expect_identical(as.vector(unclass(again$i)), as.double(1:5))
  expect_identical(as.vector(again$s), as.character(1:5))
})
