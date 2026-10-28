# read_dta reads every fixture as haven does: values (with .a to .z),
# variable labels, display formats, value labels and the data label.
# Where haven 2.5.5 is known to read a file wrongly the test says so;
# see docs/adr/0005-oracles.md.

# haven's tag for each value: NA for a number, "" for ., or the letter.
tags <- function(x) {
  x <- unclass(x)
  ifelse(is.na(x), ifelse(is.na(haven::na_tag(x)), "", haven::na_tag(x)), NA)
}

test_that("read_dta matches haven on every fixture", {
  skip_if_not_installed("haven")
  for (path in fixtures()) {
    name <- basename(path)
    ours <- read_dta(path)
    theirs <- haven::read_dta(path)
    expect_identical(names(ours), names(theirs), label = name)
    expect_identical(attr(ours, "label"), attr(theirs, "label", exact = TRUE), label = name)
    for (col in names(theirs)) {
      what <- paste(name, col)
      x <- ours[[col]]
      y <- theirs[[col]]
      expect_identical(attr(x, "label", exact = TRUE), attr(y, "label", exact = TRUE), label = what)
      expect_identical(attr(x, "format"), attr(y, "format.stata"), label = what)
      if (is.character(y)) {
        # haven 2.5.5 reads strLs in 119 files with the 118 layout, so
        # it reads 119 files from other writers wrongly.
        if (grepl("^pandas_119", name) && col == "strl") next
        # haven 2.5.5 drops trailing blanks from strN values.
        expect_identical(sub(" +$", "", as.vector(x)), sub(" +$", "", as.vector(y)), label = what)
        next
      }
      if (inherits(y, "Date")) y <- as.numeric(y - as.Date("1960-01-01"))
      expect_identical(as.vector(unclass(x)), as.vector(unclass(y)), label = what)
      expect_identical(tags(x), tags(y), label = what)
      expect_identical(names(attr(x, "labels")), names(attr(y, "labels")), label = what)
      expect_identical(tags(attr(x, "labels")), tags(attr(y, "labels")), label = what)
    }
  }
})

test_that("col_select takes names or tidyselect, in the order given", {
  path <- file.path(fixture_dir, "haven_118.dta")
  skip_if_not(file.exists(path))
  expect_named(read_dta(path, col_select = c("text", "row")), c("text", "row"))
  expect_named(read_dta(path, col_select = tidyselect::all_of(c("day", "num"))), c("day", "num"))
  expect_named(read_dta(path, col_select = tidyselect::starts_with("t")), "text")
  expect_identical(nrow(read_dta(path, col_select = "row")), 6L)
})
