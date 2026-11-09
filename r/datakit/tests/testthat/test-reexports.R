# datakit re-exports dtaparser's functions, so that library(datakit) alone
# reads and writes .dta files and reads and sets labels and .a to .z.

reexported <- c("read_dta", "read_meta", "var_label", "val_labels", "val_label",
                "with_labels", "tagged_na", "na_tag", "is_tagged_na", "missing_rank", "drop_labels")

test_that("every function dtaparser exports is datakit's too, the same function but save_dta", {
  expect_setequal(intersect(getNamespaceExports("dtaparser"), getNamespaceExports("datakit")),
                  getNamespaceExports("dtaparser"))
  for (f in reexported) {
    expect_identical(getExportedValue("datakit", f), getExportedValue("dtaparser", f), label = f)
  }
})

test_that("datakit's save_dta, a generic, writes a data frame as dtaparser's does", {
  expect_false(identical(datakit::save_dta, dtaparser::save_dta))
  d <- data.frame(id = 1:3, x = with_labels(c(1, 0, tagged_na("d")), c(No = 0, Yes = 1), label = "Smokes"))
  attr(d, "label") <- "Data"
  ours <- tempfile(fileext = ".dta")
  theirs <- tempfile(fileext = ".dta")
  datakit::save_dta(d, ours)
  dtaparser::save_dta(d, theirs)
  # The files differ only in their time stamps.
  expect_identical(read_dta(ours), read_dta(theirs))
  a <- read_meta(ours)
  b <- read_meta(theirs)
  a$timestamp <- b$timestamp <- NULL
  expect_identical(a, b)
})

test_that("with only datakit attached, a .dta file keeps its labels and letters", {
  out <- fresh_r(c(
    "library(datakit)",
    "d <- data.frame(id = 1:3)",
    "d$smoker <- with_labels(c(1, 0, tagged_na('d')), c(No = 0, Yes = 1), label = 'Smokes')",
    "p <- tempfile(fileext = '.dta')",
    "save_dta(d, p)",
    "x <- read_dta(p)$smoker",
    "cat(var_label(x), val_label(x, 1), na_tag(x)[3], is_tagged_na(x, 'd')[3], names(val_labels(x)), '\\n')",
    "cat('dtaparser' %in% search(), 'package:dtaparser' %in% search(), '\\n')"
  ))
  expect_identical(out, c("Smokes Yes d TRUE No Yes ", "FALSE FALSE "))
})
