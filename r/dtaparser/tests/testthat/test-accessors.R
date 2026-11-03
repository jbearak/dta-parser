# na_tag, is_tagged_na, var_label, val_labels and val_label (plan 0013),
# and tagged_na (plan 0015).
# Files come from this library's writer; .a to .z from haven's
# tagged_na(), and the expected letters from haven's na_tag() on the same
# doubles. Other expected values are the labels the tests wrote.

tna <- function(letter) haven::tagged_na(letter)

test_that("na_tag gives the letters haven gives, keeping names", {
  skip_if_not_installed("haven")
  d <- c(1.5, NA, tna("a"), tna("z"), -2)
  path <- write_fixture(d = col(d, "double"), td = col(c(0, tna("d"), 1, 2, 3), "long", "%td"))
  df <- read_dta(path)
  expect_identical(na_tag(df$d), haven::na_tag(d))
  expect_identical(na_tag(df$d), c(NA, NA, "a", "z", NA))
  expect_s3_class(df$td, "Date")
  expect_identical(na_tag(df$td), c(NA, "d", NA, NA, NA))
  expect_identical(na_tag(c(x = 1, y = tna("q"))), c(x = NA, y = "q"))
  expect_identical(na_tag(double()), character())
})

test_that("an integer column has no letters until the rows read hold one", {
  skip_if_not_installed("haven")
  path <- write_fixture(b = col(c(1, 2, tna("a"), 4), "byte"))
  head <- read_dta(path, n_max = 2)$b
  expect_type(head, "integer")
  expect_identical(na_tag(head), c(NA_character_, NA_character_))
  expect_identical(is_tagged_na(head), c(FALSE, FALSE))
  all <- read_dta(path)$b
  expect_type(all, "double")
  expect_identical(na_tag(all), c(NA, NA, "a", NA))
})

test_that("na_tag gives NA for logicals and factors and stops on other types", {
  expect_identical(na_tag(c(NA, TRUE)), c(NA_character_, NA_character_))
  expect_identical(na_tag(factor(c("a", NA))), c(NA_character_, NA_character_))
  expect_error(na_tag(c("a", "b")), "not character")
  expect_error(na_tag(list(1)), "not list")
  expect_error(na_tag(data.frame(x = 1)), "not data.frame")
  expect_error(is_tagged_na("a"), "not character")
})

test_that("is_tagged_na picks out .a to .z, or the letters in tag", {
  skip_if_not_installed("haven")
  x <- c(1, NA, tna("a"), tna("d"), tna("r"))
  expect_identical(is_tagged_na(x), haven::is_tagged_na(x))
  expect_identical(is_tagged_na(x, "d"), haven::is_tagged_na(x, "d"))
  expect_identical(is_tagged_na(x, c("d", "r")), c(FALSE, FALSE, FALSE, TRUE, TRUE))
  expect_identical(is_tagged_na(c(a = 1, b = tna("a"))), c(FALSE, TRUE))
  for (bad in list("D", ".d", "dd", character(), NA_character_, 1)) {
    expect_error(is_tagged_na(x, bad), "tag must be letters")
  }
})

test_that("val_label matches numbers by value and .a to .z by letter", {
  skip_if_not_installed("haven")
  labels <- c(None = 0, One = 1, "Don't know" = tna("d"), Refused = tna("r"))
  path <- write_fixture(x = col(c(0, 1, 2, NA, tna("d"), tna("r"), tna("a")), "double", labels = labels))
  x <- read_dta(path, factors = FALSE)$x
  expect_identical(val_labels(x), labels)
  # `.` is NA, as is .a, which has no label; neither matches a code.
  expect_identical(val_label(x), c("None", "One", NA, NA, "Don't know", "Refused", NA))
  expect_identical(val_label(x, c(1, tna("r"), tna("d"), NA)), c("One", "Refused", "Don't know", NA))
  expect_identical(val_label(x, 1L), "One")
  expect_identical(val_label(x, NA), NA_character_)
  expect_identical(val_label(x, double()), character())
  expect_error(val_label(x, "1"), "values must be")
  expect_error(val_label(x, list(1)), "values must be")
  expect_error(val_label(x, factor(1)), "values must be")
})

test_that("val_label is NA for columns without labels, and stops on data frames", {
  skip_if_not_installed("haven")
  path <- write_fixture(
    f = col(c(1, 2), "byte", labels = c(a = 1, b = 2)),
    td = col(c(0, 1), "long", "%td", labels = c("Don't know" = tna("d"))),
    n = col(c(1, 2), "double")
  )
  df <- read_dta(path, factors = TRUE)
  expect_s3_class(df$f, "factor")
  expect_null(val_labels(df$f))
  expect_identical(val_label(df$f), c(NA_character_, NA_character_))
  expect_s3_class(df$td, "Date")
  expect_identical(val_label(df$td), c(NA_character_, NA_character_))
  expect_identical(val_label(df$n), c(NA_character_, NA_character_))
  expect_identical(val_label(df$n, "x"), NA_character_)
  expect_identical(lapply(df, val_label), list(f = c(NA_character_, NA_character_),
                                               td = c(NA_character_, NA_character_),
                                               n = c(NA_character_, NA_character_)))
  expect_error(val_label(df), "not a tbl_df")
  expect_error(val_label(list(1)), "not a list")
})

test_that("a column labelled only on missing values keeps its labels for val_label", {
  skip_if_not_installed("haven")
  path <- write_fixture(l = col(c(1, 2, tna("d")), "int", labels = c("Don't know" = tna("d"))))
  l <- read_dta(path)$l
  expect_identical(val_label(l), c(NA, NA, "Don't know"))
})

test_that("var_label and val_labels give one element per column of a data frame", {
  skip_if_not_installed("haven")
  path <- write_fixture(a = col(c(1, 2), "byte", labels = c(Yes = 1, No = 2)), b = col(c(1, 2), "double"))
  df <- read_dta(path, factors = FALSE)
  attr(df$a, "label") <- "Answer"
  expect_identical(var_label(df$a), "Answer")
  expect_null(var_label(df$b))
  expect_identical(var_label(df), list(a = "Answer", b = NULL))
  expect_identical(unlist(var_label(df)), c(a = "Answer"))
  expect_identical(val_labels(df), list(a = c(Yes = 1, No = 2), b = NULL))
  expect_null(val_labels(df$b))
})

test_that("var_label reads the label read_dta keeps from the file", {
  skip_if_not_installed("haven")
  path <- tempfile(fileext = ".dta")
  haven::write_dta(data.frame(x = structure(c(1, 2), label = "Score")), path)
  expect_identical(var_label(read_dta(path)$x), "Score")
})

test_that("read_fixed_width's tagged recodes read back through the accessors", {
  dir <- tempfile()
  dir.create(dir)
  writeLines(c(
    "PROC FORMAT; VALUE kidsf 0='None' 98='DK' 99='Not ascertained';",
    "DATA; INPUT ID 1-3 KIDS 4-5;",
    "LABEL KIDS = 'Number of children';",
    "IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;",
    "FORMAT KIDS kidsf.;"
  ), file.path(dir, "s.sas"))
  writeLines(c("001 2", "00298", "00399", "004 0"), file.path(dir, "s.dat"))
  df <- read_fixed_width(file.path(dir, "s.dat"), file.path(dir, "s.sas"), recodes = "tagged")
  expect_identical(na_tag(df$KIDS), c(NA, "a", "b", NA))
  expect_identical(val_label(df$KIDS), c(NA, "DK", "Not ascertained", "None"))
  expect_identical(var_label(df$KIDS), "Number of children")
  expect_identical(na_tag(val_labels(df$KIDS)), c(None = NA, DK = "a", "Not ascertained" = "b"))
})

test_that("tagged_na makes the bits haven's tagged_na makes", {
  skip_if_not_installed("haven")
  expect_identical(writeBin(tagged_na(letters), raw()), writeBin(haven::tagged_na(letters), raw()))
})

test_that("tagged_na's values read back as their letters", {
  x <- tagged_na(letters)
  expect_type(x, "double")
  expect_identical(na_tag(x), letters)
  expect_true(all(is.na(x)))
  expect_identical(is_tagged_na(tagged_na(c("d", "r")), "d"), c(TRUE, FALSE))
  expect_identical(tagged_na(character()), numeric())
})

test_that("tagged_na keeps names exactly", {
  expect_identical(names(tagged_na(c(Refused = "r", "d"))), c("Refused", ""))
  expect_null(names(tagged_na(c("r", "d"))))
})

test_that("tagged_na takes only lowercase letters, in one character vector", {
  for (bad in list(NA_character_, "", "ab", "A", ".d", "é")) {
    expect_error(tagged_na(c("a", bad)), "x must be lowercase letters \"a\" to \"z\", not ", fixed = TRUE)
  }
  expect_error(tagged_na(c("a", "ab", "A")), "not \"ab\"", fixed = TRUE)
  expect_error(tagged_na(NA_character_), "not NA", fixed = TRUE)
  expect_error(tagged_na(1), "x must be a character vector, not numeric")
  expect_error(tagged_na(factor("a")), "not factor")
  expect_error(tagged_na(list("a")), "not list")
  expect_error(tagged_na(NULL), "not NULL")
  expect_error(tagged_na("a", "b"), "unused argument")
  expect_error(tagged_na(), "missing")
})

test_that("a letter survives what a recode does to a column", {
  x <- c(1, tagged_na("r"), NA)
  expect_identical(na_tag(x), c(NA, "r", NA))
  expect_identical(na_tag(x[2:3]), c("r", NA))
  attr(x, "labels") <- c(Refused = tagged_na("r"))
  expect_identical(na_tag(x), c(NA, "r", NA))
})

test_that("val_label reads labels made with tagged_na", {
  labels <- c(No = 0, Yes = 1, tagged_na(c(Refused = "r", "Not asked" = "n")))
  x <- structure(c(0, 1, tagged_na(c("r", "n")), NA, 2), labels = labels)
  expect_identical(val_label(x), c("No", "Yes", "Refused", "Not asked", NA, NA))
})
