test_that("reads values and metadata written by haven", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    source <- data.frame(id = c(1, 2, 3), text = c("a", "b", "c"))
    attr(source, "label") <- "Example data"
    attr(source$id, "label") <- "Identifier"
    haven::write_dta(source, path, version = 14)

    result <- dtaparser::read_dta(path)

    expect_equal(as.numeric(result$id), c(1, 2, 3))
    expect_equal(as.character(result$text), c("a", "b", "c"))
    expect_identical(attr(result, "label"), "Example data")
    expect_identical(attr(result$id, "label"), "Identifier")
})

test_that("retains extended missing tags", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    haven::write_dta(data.frame(
        value = c(1, haven::tagged_na("a"), NA_real_)
    ), path, version = 14)

    result <- dtaparser::read_dta(path)

    expect_equal(as.numeric(result$value), c(1, NA, NA))
    expect_equal(dta_missing_tags(result$value), c(NA, ".a", "."))
})

test_that("matches haven's read_dta argument names", {
    expect_identical(
        names(formals(dtaparser::read_dta)),
        names(formals(haven::read_dta))
    )
})

test_that("supports skip, n_max, and tidy selection", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    haven::write_dta(data.frame(
        id = 1:5, text = letters[1:5], extra = 11:15
    ), path, version = 14)

    result <- dtaparser::read_dta(
        path, col_select = c(id, text), skip = 1, n_max = 2
    )

    expect_identical(names(result), c("id", "text"))
    expect_equal(as.numeric(result$id), c(2, 3))
    expect_identical(as.character(result$text), c("b", "c"))
})
