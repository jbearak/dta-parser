# datakit re-exports dtaparser's functions, so that library(datakit) alone
# reads and writes .dta files and reads and sets labels and .a to .z.

reexported <- c("read_dta", "save_dta", "read_meta", "var_label", "val_labels", "val_label",
                "with_labels", "tagged_na", "na_tag", "is_tagged_na", "missing_rank", "drop_labels")

test_that("every function dtaparser exports is datakit's too, the same function", {
  expect_setequal(intersect(getNamespaceExports("dtaparser"), getNamespaceExports("datakit")),
                  getNamespaceExports("dtaparser"))
  for (f in reexported) {
    expect_identical(getExportedValue("datakit", f), getExportedValue("dtaparser", f), label = f)
  }
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
