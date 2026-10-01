test_that("generated indicator labels match Stata's metadata", {
    expected <- grep("^x==", readLines(test_path("fixtures", "tabulate-indicators.log")), value = TRUE)
    labels <- function(result) vapply(attr(result, "generated"),
                                      attr, character(1), which = "label")
    x <- c(-1e20, -123456789, -12345.6789, -1, -.00000001, 0,
           .00000001, .0001, .001234567, .123456789, 1.23456789,
           1234.56789, 12345.6789, 123456.789, 1234567.89,
           12345678.9, 123456789, 1e20, NA_real_, tagged_missing("a"))
    expect_identical(unname(labels(tab(x, missing = TRUE, generate = "z"))), expected[1:20])
    x <- c(1, 2, 3, NA_real_, tagged_missing("a"))
    attr(x, "labels") <- stats::setNames(c(1, 3, tagged_missing("a")), c("One", "", "Refused"))
    expect_identical(unname(labels(tab(x, missing = TRUE, nolabel = TRUE, generate = "z"))), expected[21:25])
    expect_identical(unname(labels(tab(x, missing = TRUE, generate = "u"))), expected[26:30])
})
