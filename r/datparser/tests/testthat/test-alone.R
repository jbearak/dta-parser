# datparser stands alone (ADR 0039): it loads neither dtaparser nor
# datakit, and labelled columns are plain vectors with attributes.

alone_setup <- c(
  "PROC FORMAT; VALUE kidsf 0='None' 98='DK';",
  "DATA; INPUT KIDS 1-2;",
  "IF KIDS = 98 THEN KIDS = .;",
  "FORMAT KIDS kidsf.;"
)

test_that("read_fixed_width loads neither dtaparser nor datakit", {
  out <- fresh_r(c(
    "library(datparser)",
    "dir <- tempfile(); dir.create(dir)",
    sprintf("writeLines(%s, file.path(dir, 's.sas'))", deparse1(alone_setup)),
    "writeLines(c(' 2', '98', ' 0'), file.path(dir, 's.dat'))",
    "d <- read_fixed_width(file.path(dir, 's.dat'), file.path(dir, 's.sas'), recodes = 'tagged')",
    "cat(isNamespaceLoaded('dtaparser'), isNamespaceLoaded('datakit'), class(d$KIDS), names(attr(d$KIDS, 'labels')), '\\n')"
  ))
  expect_identical(out, "FALSE FALSE numeric None DK ")
})
