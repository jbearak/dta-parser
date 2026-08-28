test_that("factor_from_labels matches installed haven on its simple seam", {
    skip_if_not_installed("haven")
    x <- labelled_for_test(c(2, 1, 2), c(Yes = 1, No = 2))

    ours <- factor_from_labels(x)
    theirs <- haven::as_factor(x)

    expect_identical(as.character(ours), as.character(theirs))
    expect_identical(levels(ours), levels(theirs))
})
