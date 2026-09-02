test_that("labelbook reports assigned tables as structured data", {
    shared <- c(No = 0, Yes = 1, Refused = tagged_missing("a"))
    data <- data.frame(
        first = labelled_for_test(c(0, 1), shared),
        second = labelled_for_test(c(1, 0), shared),
        plain = 1:2
    )
    attr(data$first, "value.label.name") <- "answer"
    attr(data$second, "value.label.name") <- "answer"

    result <- labelbook(data)
    expect_s3_class(result, "dtatools_labelbook")
    expect_named(result, c(
        "tables", "mappings", "assignments", "diagnostics", "options", "source"
    ))
    expect_identical(result$tables$table, "answer")
    expect_identical(result$tables$mapping_count, 3L)
    expect_identical(result$mappings$code_text, c("0", "1", ".a"))
    expect_identical(result$assignments$variable, c("first", "second"))
    expect_identical(result$assignments$position, 1:2)
    expect_equal(result$tables$minimum, 0)
    expect_equal(result$tables$maximum, 1)
    expect_identical(result$tables$missing_mapping_count, 1L)
    expect_true(result$tables$unique_full)
    expect_true(result$tables$unique_truncated)
})

test_that("labelbook selection, ordering, and print limits are deterministic", {
    data <- data.frame(
        x = labelled_for_test(1:3, c(zebra = 3, alpha = 1, middle = 2)),
        y = labelled_for_test(rep(1, 3), c(One = 1))
    )

    alpha <- labelbook(data, x, order = "alpha", list_limit = 1)
    expect_identical(alpha$mappings$text, c("alpha", "middle", "zebra"))
    expect_output(print(alpha), "Value label x", fixed = TRUE)

    definition <- labelbook(data, .tables = "x", order = "definition")
    expect_identical(definition$mappings$text, c("zebra", "alpha", "middle"))
    expect_error(labelbook(data, x, .tables = "x"), "cannot be combined")
    expect_error(labelbook(data, absent), "unknown value-label table")
    expect_s3_class(labelbook(data, .tables = character()), "dtatools_labelbook")
    expect_equal(nrow(labelbook(data, .tables = character())$tables), 0)
})

test_that("labelbook diagnoses table problems and malformed sharing", {
    labels <- stats::setNames(
        c(1, 3, 4, 5, 7),
        c(" leading", "duplicate", "duplicate", "5", "")
    )
    data <- data.frame(x = labelled_for_test(1, labels))
    result <- labelbook(data, problems = TRUE, length = 3)
    expect_setequal(result$diagnostics$code, c(
        "gaps", "leading_or_trailing_blanks", "duplicate_label_text",
        "duplicate_truncated_text", "numeric_label_text", "empty_label_text"
    ))
    expect_output(print(result), "Potential problems", fixed = TRUE)

    conflict <- data.frame(
        a = labelled_for_test(1, c(One = 1)),
        b = labelled_for_test(2, c(Two = 2))
    )
    attr(conflict$a, "value.label.name") <- "shared"
    attr(conflict$b, "value.label.name") <- "shared"
    malformed <- labelbook(conflict)
    expect_true(malformed$tables$malformed)
    expect_equal(nrow(malformed$mappings), 0)
    expect_true("inconsistent_resolved_mappings" %in% malformed$diagnostics$code)
})

test_that("labelbook diagnoses missing value-label names as malformed", {
    labels <- stats::setNames(c(1, 2), c("One", NA_character_))
    data <- data.frame(x = labelled_for_test(1, labels))

    result <- labelbook(data)

    expect_true(result$tables$malformed)
    expect_equal(nrow(result$mappings), 0L)
    expect_identical(result$diagnostics$code, "malformed_value_labels")
    expect_identical(result$diagnostics$scope, "variable")
})

test_that("labelbook diagnoses malformed registry entries", {
    labels <- stats::setNames(c(1, 2), c("One", NA_character_))
    local_mocked_bindings(
        .labelbook_input = function(data) list(
            data = data.frame(), registry = list(answer = labels), source = NULL
        ),
        .package = "dtatools"
    )

    result <- labelbook(data.frame())

    expect_true(result$tables$malformed)
    expect_equal(nrow(result$mappings), 0L)
    expect_identical(result$diagnostics$code, "malformed_value_labels")
    expect_identical(result$diagnostics$scope, "table")
})

test_that("labelbook detail restores the normal report", {
    data <- data.frame(x = labelled_for_test(1, c(One = 1, Three = 3)))
    summary <- labelbook(data, problems = TRUE)
    detailed <- labelbook(data, problems = TRUE, detail = TRUE)

    expect_identical(summary$diagnostics$details, detailed$diagnostics$details)
    expect_true(any(lengths(detailed$diagnostics$details) > 0L))
    expect_false(any(grepl("Value label x", capture.output(print(summary)), fixed = TRUE)))
    expect_output(print(detailed), "Value label x", fixed = TRUE)
})

test_that("codebook classifies and summarizes numeric and string variables", {
    data <- data.frame(
        category = c(rep(c(1, 2), length.out = 9), NA_real_, tagged_missing("a")),
        continuous = c(1:10, NA_real_),
        text = c("first", "", NA, " second", rep("other", 7)),
        logical = c(TRUE, FALSE, NA, rep(TRUE, 8))
    )
    result <- codebook(data)
    expect_s3_class(result, "dtatools_codebook")
    expect_identical(
        result$variables$report_type,
        c("categorical", "continuous", "examples", "categorical")
    )
    category <- result$variables[result$variables$variable == "category", ]
    expect_identical(category$missing_count, 2L)
    expect_identical(category$system_missing_count, 1L)
    expect_identical(category$extended_missing_count, 1L)
    expect_identical(category$unique_nonmissing, 2L)
    continuous <- result$variables[result$variables$variable == "continuous", ]
    expect_equal(continuous$mean, 5.5)
    expect_equal(continuous$sd, stats::sd(1:10))
    expect_equal(unname(unlist(continuous[c("p10", "p25", "p50", "p75", "p90")])),
                 stats::quantile(1:10, c(.1, .25, .5, .75, .9), type = 2, names = FALSE))
    expect_identical(result$examples$example, c("first", " second", "other"))
})

test_that("codebook handles string variables containing only Stata missing values", {
    result <- codebook(data.frame(empty = rep("", 3)))

    expect_identical(result$variables$report_type, "examples")
    expect_identical(result$variables$missing_count, 3L)
    expect_equal(nrow(result$examples), 0L)
})

test_that("codebook selections and where use report semantics", {
    data <- data.frame(x = 1:5, y = 6:10, eligible = c(TRUE, FALSE, TRUE, TRUE, FALSE))
    selected <- codebook(data, x, where = eligible)
    expect_identical(selected$variables$variable, "x")
    expect_identical(selected$variables$observations, 3L)
    expect_equal(selected$variables$mean, mean(c(1, 3, 4)))

    positions <- codebook(data, x, where = c(2, 2, 4))
    expect_identical(positions$variables$observations, 2L)
    expect_equal(positions$variables$mean, 3)
    expect_identical(codebook(data, .vars = character())$variables$variable, character())
    expect_error(codebook(data, x, .vars = "x"), "cannot be combined")
    expect_error(codebook(data, absent), "unknown variable")
})

test_that("codebook distinguishes duplicate names by position", {
    data <- data.frame(first = 1:2, second = 3:4)
    names(data) <- c("same", "same")
    result <- codebook(data)
    expect_identical(result$variables$position, 1:2)
    expect_identical(result$variables$variable, c("same", "same"))
    expect_error(codebook(data, same), "ambiguous")
})

test_that("codebook detects duplicate rows under Stata missing identity", {
    data <- data.frame(
        x = dta_double(c(
            1, 1, NA_real_, NA_real_, tagged_missing("a"),
            tagged_missing("a"), tagged_missing("b")
        )),
        y = rep("same", 7)
    )
    result <- codebook(data, diagnostic_limit = Inf)
    duplicate <- result$diagnostics[
        result$diagnostics$code == "duplicate_observations", ]
    payload <- duplicate$details[[1L]][[1L]]

    expect_identical(payload$count, 6L)
    expect_identical(payload$rows, 1:6)
})

test_that("codebook returns Stata-style missingness relationships", {
    data <- data.frame(
        x = c(1, NA, 3, NA),
        y = c(1, NA, NA, NA),
        z = c(1, NA, 3, NA)
    )
    result <- codebook(data, mv = TRUE)
    expect_true(any(
        result$missing_relationships$left_variable == "x" &
            result$missing_relationships$relationship == "equivalent" &
            result$missing_relationships$right_variable == "z"
    ))
    expect_true(any(
        result$missing_relationships$left_variable == "x" &
            result$missing_relationships$relationship == "implies" &
            result$missing_relationships$right_variable == "y"
    ))
    expect_equal(nrow(codebook(data[0, ], mv = TRUE)$missing_relationships), 0)
})

test_that("codebook retains diagnostics and bounds row evidence", {
    data <- data.frame(
        constant = rep(1, 5),
        text = c(" lead", "trail ", "embedded space", "", "ok"),
        all_missing = rep(NA_real_, 5)
    )
    result <- codebook(data, problems = TRUE, detail = TRUE, diagnostic_limit = 2)
    expect_true("constant_or_all_missing" %in% result$diagnostics$code)
    expect_true("leading_blanks" %in% result$diagnostics$code)
    expect_true("trailing_blanks" %in% result$diagnostics$code)
    expect_true("embedded_blanks" %in% result$diagnostics$code)
    expect_output(print(result), "few_unique_strings", fixed = TRUE)
    summary <- codebook(data, problems = TRUE, diagnostic_limit = 2)
    expect_identical(summary$diagnostics$details, result$diagnostics$details)
    expect_false(any(grepl("observations", capture.output(print(summary)), fixed = TRUE)))
    expect_output(print(result), "observations", fixed = TRUE)
    missing_result <- codebook(
        data, all_missing, problems = TRUE, diagnostic_limit = 2
    )
    row_problem <- missing_result$diagnostics[
        missing_result$diagnostics$code == "all_selected_variables_missing", ]
    payload <- row_problem$details[[1L]][[1L]]
    expect_identical(payload$count, 5L)
    expect_length(payload$rows, 2L)
})

test_that("codebook compact mode enforces Stata option combinations", {
    data <- data.frame(x = 1:3, y = letters[1:3])
    compact <- codebook(data, compact = TRUE)
    expect_identical(compact$options$mode, "compact")
    expect_equal(nrow(compact$tabulations), 0)
    expect_equal(nrow(compact$examples), 0)
    expect_output(print(compact), "unique_nonmissing", fixed = TRUE)
    expect_error(codebook(data, compact = TRUE, mv = TRUE), "combined only")
    expect_error(codebook(data, dots = TRUE), "requires")
    expect_error(codebook(data, detail = TRUE), "requires")
})

test_that("codebooks accept DTA and Arrow paths", {
    dta <- fixture("auto_v118.dta")
    ordinary_metadata <- dtatools:::.dta_metadata(dta)
    registry_metadata <- dtatools:::.dta_metadata(
        dta, include_value_labels = TRUE
    )
    expect_null(attr(ordinary_metadata, "dta_value_label_registry", exact = TRUE))
    expect_named(attr(registry_metadata, "dta_value_label_registry", exact = TRUE))
    dta_labelbook <- labelbook(dta)
    dta_codebook <- codebook(dta, foreign)
    expect_s3_class(dta_labelbook, "dtatools_labelbook")
    expect_identical(dta_codebook$variables$variable, "foreign")

    skip_if_not_installed("arrow")
    arrow <- tempfile(fileext = ".arrow")
    on.exit(unlink(arrow), add = TRUE)
    save_arrow(read_dta(dta), arrow)
    expect_identical(labelbook(arrow)$tables$table, dta_labelbook$tables$table)
    expect_identical(codebook(arrow, foreign)$variables$variable, "foreign")
})
