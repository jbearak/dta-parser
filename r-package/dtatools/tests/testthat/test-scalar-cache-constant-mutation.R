test_that("scalar admission rechecks in-place compiled helper constants", {
    skip_if_not(.dtatools_numeric_entry_expected("scalar"))

    ns <- asNamespace("dtatools")
    state <- get(".numeric_helper_state", ns)
    helper <- get(".dta_storage_candidates", ns)
    source_before <- serialize(body(helper), NULL)
    helper_address <- rlang::obj_address(helper)
    code_address <- rlang::obj_address(.Internal(bodyCode(helper)))
    source <- dta_long(rep(c(1, 2), length.out = 2048L))
    seed <- dta_double(rep(c(1, 2), length.out = 2048L))
    operation <- function() source + 1
    for (i in seq_len(5L)) invisible(seed + 1)
    for (i in seq_len(5L)) invisible(operation())

    capture <- function() {
        invisible(.dtatools_numeric_entry_counts(TRUE))
        result <- operation()
        list(result = result, counts = .dtatools_numeric_entry_counts(FALSE))
    }
    positive <- capture()
    expect_identical(unname(positive$counts[["scalar"]]), 1)
    expect_identical(dta_storage_type(positive$result), "long")

    returned <- helper("long")
    expect_identical(returned, c("long", "double"))
    old_first <- paste0(returned[[1L]])
    holder <- structure(list(value = returned), class = "data.frame",
                        row.names = .set_row_names(length(returned)))
    on.exit(data.table::set(holder, i = 1L, j = "value", value = old_first), add = TRUE)
    data.table::set(holder, i = 1L, j = "value", value = "double")
    expect_identical(helper("long"), c("double", "double"))
    expect_identical(rlang::obj_address(helper), helper_address)
    expect_identical(rlang::obj_address(.Internal(bodyCode(helper))), code_address)
    expect_identical(serialize(body(helper), NULL), source_before)

    actual <- capture()
    saved <- state$dependencies
    state$dependencies <- NULL
    on.exit(state$dependencies <- saved, add = TRUE)
    fallback <- capture()
    expect_identical(unname(actual$counts[["scalar"]]), 0)
    expect_identical(unname(fallback$counts[["scalar"]]), 0)
    expect_identical(dta_storage_type(actual$result), "double")
    expect_identical(dta_storage_type(fallback$result), "double")
    expect_identical(as.double(actual$result), as.double(fallback$result))
    expect_identical(attributes(actual$result), attributes(fallback$result))
})
