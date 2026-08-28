test_that("haven opens dtatools output with matching values and metadata", {
    skip_if_not_installed("haven")
    x <- c(1, 2, tagged_missing("a"), NA_real_)
    attr(x, "labels") <- c(One = 1, Two = 2)
    data <- data.frame(x = x, text = c("é", "", "long text", "long text"))
    attr(data, "label") <- "haven compatibility"
    attr(data, "notes") <- c("first note", "second note")
    var_label(data$x) <- "coded value"
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path, strl_threshold = 4L))
    actual <- without_haven_note_count(haven::read_dta(path))
    expect_identical(attr(actual, "label", exact = TRUE), "haven compatibility")
    expect_identical(attr(actual, "notes", exact = TRUE), attr(data, "notes"))
    expect_identical(attr(actual$x, "label", exact = TRUE), "coded value")
    expect_identical(missing_tag(actual$x), c(NA, NA, "a", NA))
    expect_identical(unname(attr(actual$x, "labels")), c(1, 2))
    expect_identical(as.character(actual$text), data$text)
})
