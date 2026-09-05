test_that("resolve_var_name resolves exact names and unique abbreviations", {
    data <- data.frame(id = 1, identifier = 2, outcome = 3)

    expect_identical(resolve_var_name(data, "id"), "id")
    expect_identical(resolve_var_name(data, "out"), "outcome")
    expect_identical(resolve_var_name(data, "outcome", exact = TRUE), "outcome")
})

test_that("resolve_var_name reports absent and ambiguous references", {
    data <- data.frame(alpha = 1, alpine = 2)

    expect_identical(resolve_var_name(data, "missing"), NA_character_)
    expect_identical(resolve_var_name(data, "al"), NA_character_)
    expect_identical(resolve_var_name(data, "alph", exact = TRUE), NA_character_)

    expect_error(
        resolve_var_name(data, "missing", on_failure = "error"),
        "Variable `missing` not found",
        class = "dtatools_variable_not_found_error"
    )
    expect_error(
        resolve_var_name(data, "al", on_failure = "error"),
        "ambiguous.*alpha, alpine",
        class = "dtatools_ambiguous_variable_error"
    )
})

test_that("confirm_var returns logical results and errors by default", {
    data <- data.frame(alpha = 1, alpine = 2, beta = 3)

    expect_true(confirm_var(data, "bet"))
    expect_false(confirm_var(data, "missing", on_failure = "false"))
    expect_false(confirm_var(data, "al", on_failure = "false"))
    expect_false(confirm_var(data, "bet", exact = TRUE,
                             on_failure = "false"))

    expect_error(
        confirm_var(data, "missing"),
        "Variable `missing` not found",
        class = "dtatools_variable_not_found_error"
    )
    expect_error(
        confirm_var(data, "al"),
        "ambiguous",
        class = "dtatools_ambiguous_variable_error"
    )
})

test_that("variable names are read from each supported container", {
    containers <- list(
        data.frame(target = 1),
        tibble::tibble(target = 1)
    )
    if (requireNamespace("data.table", quietly = TRUE)) {
        containers <- append(containers, list(data.table::data.table(target = 1)))
    }
    reference_data <- reserve_columns(data.frame(source = 1))
    gen(reference_data, target, source + 1)
    containers <- append(containers, list(reference_data))

    for (data in containers) {
        expect_identical(resolve_var_name(data, "tar"), "target")
        expect_true(confirm_var(data, "target"))
    }
})

test_that("resolution observes current names without modifying data", {
    data <- data.frame(alpha = 1, beta = 2)
    before <- serialize(data, NULL)

    expect_identical(resolve_var_name(data, "bet"), "beta")
    expect_identical(serialize(data, NULL), before)

    data$better <- 3
    expect_identical(resolve_var_name(data, "bet"), NA_character_)

    data$beta <- NULL
    expect_identical(resolve_var_name(data, "bet"), "better")
})

test_that("zero-column data has no resolvable variables", {
    data <- data.frame(row.names = 1:2)

    expect_identical(resolve_var_name(data, "x"), NA_character_)
    expect_false(confirm_var(data, "x", on_failure = "false"))
})

test_that("missing column names do not become prefix candidates", {
    data <- data.frame(first = 1, target = 2, check.names = FALSE)
    names(data)[[1L]] <- NA_character_

    expect_identical(resolve_var_name(data, "tar"), "target")
    expect_identical(resolve_var_name(data, "absent"), NA_character_)
})

test_that("variable-name helpers validate their arguments", {
    data <- data.frame(alpha = 1)

    invalid_data <- list(NULL, list(alpha = 1), matrix(1, ncol = 1))
    for (value in invalid_data) {
        expect_error(resolve_var_name(value, "alpha"), "`data`")
    }

    invalid_names <- list(NULL, character(), NA_character_, "", c("a", "b"), 1)
    for (value in invalid_names) {
        expect_error(resolve_var_name(data, value), "`name`")
    }

    invalid_exact <- list(NULL, NA, c(TRUE, FALSE), 1)
    for (value in invalid_exact) {
        expect_error(resolve_var_name(data, "alpha", exact = value), "`exact`")
    }

    expect_error(resolve_var_name(data, "alpha", on_failure = "other"),
                 "on_failure")
    expect_error(confirm_var(data, "alpha", on_failure = "missing"),
                 "on_failure")
})
