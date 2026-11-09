# datakit's read_fixed_width is datparser's (ADR 0039), whose tests cover
# the reading; here, that labelled columns come back as dtaparser's class
# and everything else as datparser gives it.

fw_files <- function() {
  dir <- tempfile()
  dir.create(dir)
  writeLines(c(
    "PROC FORMAT; VALUE kidsf 0='None' 98='DK' 99='Not ascertained';",
    "DATA; INPUT ID 1-3 KIDS 4-5 NAME $ 6-8;",
    "LABEL KIDS = 'Number of children';",
    "IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;",
    "FORMAT KIDS kidsf.;"
  ), file.path(dir, "s.sas"))
  writeLines(c("001 2ann", "00298bob", "00399   ", "004 0cy "), file.path(dir, "s.dat"))
  c(data = file.path(dir, "s.dat"), setup = file.path(dir, "s.sas"))
}

test_that("read_fixed_width's tagged recodes read back through the accessors", {
  f <- fw_files()
  df <- read_fixed_width(f[["data"]], f[["setup"]], recodes = "tagged")
  expect_s3_class(df$KIDS, "dtaparser_labelled")
  expect_identical(na_tag(df$KIDS), c(NA, "a", "b", NA))
  expect_identical(val_label(df$KIDS), c(NA, "DK", "Not ascertained", "None"))
  expect_identical(var_label(df$KIDS), "Number of children")
  expect_identical(na_tag(val_labels(df$KIDS)), c(None = NA, DK = "a", "Not ascertained" = "b"))
})

test_that("apart from the class, it is datparser's result", {
  f <- fw_files()
  for (recodes in c("setup", "tagged", "none")) {
    ours <- read_fixed_width(f[["data"]], f[["setup"]], recodes = recodes, col_select = c(KIDS, NAME), skip = 1)
    theirs <- datparser::read_fixed_width(f[["data"]], f[["setup"]], recodes = recodes,
                                          col_select = c(KIDS, NAME), skip = 1)
    expect_identical(ours$NAME, theirs$NAME)
    expect_identical(unclass(ours$KIDS), unclass(theirs$KIDS))
    expect_identical(lapply(ours, vctrs::vec_data), lapply(theirs, vctrs::vec_data))
  }
  names <- c("KIDS", "ID")
  expect_named(read_fixed_width(f[["data"]], f[["setup"]], col_select = names), names)
  expect_s3_class(read_fixed_width(f[["data"]], f[["setup"]], factors = TRUE)$KIDS, "factor")
})

test_that("datakit's read_fixed_width is the one library(datakit) finds", {
  expect_identical(getExportedValue("datakit", "read_fixed_width"), read_fixed_width)
  expect_false(identical(read_fixed_width, datparser::read_fixed_width))
})
