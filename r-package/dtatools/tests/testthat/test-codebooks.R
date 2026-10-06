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

test_that("labelbook reports a value-label set without mappings", {
    data <- data.frame(x = labelled_for_test(c(1, 2), stats::setNames(numeric(), character())))
    result <- labelbook(data)

    expect_identical(result$tables$table, "x")
    expect_identical(result$tables$mapping_count, 0L)
    expect_identical(result$tables$missing_mapping_count, 0L)
    expect_false(result$tables$malformed)
    expect_identical(result$mappings, labelbook(data.frame(a = 1))$mappings)
    shared <- data.frame(x = data$x, y = labelled_for_test(c(1, 1), c(One = 1)))
    expect_identical(labelbook(shared)$mappings$text, "One")
    expect_identical(nrow(result$diagnostics), 0L)
    expect_identical(result$assignments$variable, "x")
    expect_output(print(result), "Value label x", fixed = TRUE)
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

test_that("codebook string checks read equal strings alike", {
    latin <- "caf\xe9 "
    Encoding(latin) <- "latin1"
    text <- c("ok", enc2utf8(latin), latin, "ok")
    attr(text, "stata.string.storage") <- "str20"
    problems <- codebook(tibble::tibble(text = text), problems = TRUE)$diagnostics
    expect_true("trailing_blanks" %in% problems$code)
    wide <- problems[problems$code == "string_storage_wider_than_required", ]
    expect_identical(wide$details[[1L]][[1L]], list(declared = "str20", required = 6L))

    # An invalid string keeps grepl()'s warnings, which name its position
    # among all the observed strings.
    invalid <- rawToChar(as.raw(c(0x20, 0xff)))
    Encoding(invalid) <- "UTF-8"
    warnings <- character()
    withCallingHandlers(
        codebook(data.frame(text = c("ok", "ok", invalid)), problems = TRUE),
        warning = function(w) {
            warnings <<- c(warnings, conditionMessage(w))
            invokeRestart("muffleWarning")
        }
    )
    expect_true("input string 3 is invalid" %in% warnings)
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

    arrow <- tempfile(fileext = ".arrow")
    on.exit(unlink(arrow), add = TRUE)
    save_arrow(read_dta(dta), arrow)
    expect_identical(labelbook(arrow)$tables$table, dta_labelbook$tables$table)
    expect_identical(codebook(arrow, foreign)$variables$variable, "foreign")
})

test_that("codebook reports declared string storage and a wide declaration", {
    data <- dibble(
        fixed = dta_string(c("ab", "cd"), "str20"),
        snug = dta_string(c("ab", "cd")),
        long = dta_string(c(strrep("x", 2046L), "y")),
        bare = c("ab", "cd"),
        count = dta_byte(c(1, 2))
    )

    result <- codebook(data)
    storage <- stats::setNames(
        result$variables$storage, result$variables$variable
    )
    expect_identical(storage[["fixed"]], "str20")
    expect_identical(storage[["snug"]], "str2")
    expect_identical(storage[["long"]], "strL")
    # `dibble()` declares a bare character column, so it reports `str2` too.
    expect_identical(storage[["bare"]], "str2")
    expect_identical(storage[["count"]], "byte")
    expect_identical(
        codebook(data.frame(plain = c("ab", "cd")))$variables$storage,
        "character"
    )

    problems <- codebook(data, problems = TRUE)$diagnostics
    wide <- problems[problems$code == "string_storage_wider_than_required", ]
    expect_identical(wide$variable, "fixed")
    expect_identical(
        wide$details[[1L]][[1L]], list(declared = "str20", required = 2L)
    )
})

test_that("codebook duplicate rows match vctrs duplicate detection", {
    detect <- dtatools:::.codebook_duplicate_rows
    wide <- as.data.frame(matrix(1, nrow = 4L, ncol = 300L))
    wide[[300L]] <- c(1, 2, 1, 3)
    late <- as.data.frame(matrix(1, nrow = 4L, ncol = 40L))
    late[[40L]] <- c(1, 1, 2, 2)
    listed <- data.frame(a = c(1, 1, 1))
    listed$b <- list(1, 1, "1")
    matrixed <- data.frame(a = c(1, 1, 1))
    matrixed$m <- matrix(c(1, 1, 2, 3, 3, 3), 3L)
    packed <- data.frame(a = c(1, 1, 2))
    packed$df <- data.frame(x = c(1, 1, 1), y = c("a", "a", "b"))
    latin <- "caf\xe9"
    Encoding(latin) <- "latin1"
    tables <- list(
        identifier = data.frame(id = 1:4, x = c(1, 1, 1, 1)),
        missing = data.frame(
            x = dta_double(c(
                1, 1, NA_real_, NA_real_, tagged_missing("a"),
                tagged_missing("a"), tagged_missing("b")
            )),
            y = dta_string(rep("same", 7L))
        ),
        zeros = data.frame(x = c(0, -0, NA, NaN, NA, NaN)),
        mixed = data.frame(
            f = factor(c("u", "v", "u", NA, NA)),
            d = as.Date("2020-01-01") + c(0, 1, 0, NA, NA),
            s = c(latin, "b", enc2utf8(latin), NA, NA),
            l = c(TRUE, FALSE, TRUE, NA, NA)
        ),
        wide = wide, late = late, listed = listed, matrixed = matrixed,
        packed = packed, dibble = dibble(a = dta_byte(c(1, 1, 2)), b = c("x", "x", "y")),
        empty = data.frame(x = double(), y = character()),
        single = data.frame(x = 1, y = "a"),
        strings = data.frame(x = c("a", "b", "a")),
        factor = data.frame(x = factor(c("a", "b", "a"))),
        stata = data.frame(x = dta_double(c(1, NA_real_, tagged_missing("a"), 1))),
        list = data.frame(x = I(list(1, "1", 1)))
    )
    for (name in names(tables)) {
        data <- tables[[name]]
        expect_identical(detect(data), vctrs::vec_duplicate_detect(data), info = name)
        twice <- data[c(seq_len(nrow(data)), seq_len(nrow(data))), , drop = FALSE]
        expect_identical(detect(twice), vctrs::vec_duplicate_detect(twice), info = name)
    }
})

test_that("codebook counts missing codes and NaN payloads in compact columns", {
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    patch_numeric_fixture_row(path, 0L, list(x_float = .raw_little_integer(0x7fc00000, 4L)))
    patch_numeric_fixture_row(path, 1L, list(x_float = .raw_little_integer(0x7f800001, 4L)))
    data <- read_dta(path)
    for (name in c("x_byte", "x_int", "x_long", "x_float", "x_double")) {
        x <- data[[name]]
        values <- dtatools:::.book_numeric_data(x)
        codes <- dtatools:::.tab_missing_codes(x)
        summary <- dtatools:::.codebook_variable(x, name, 1L, 9L, TRUE, is.na(x))$variable
        expect_identical(summary$nan_count, sum(is.nan(values)), info = name)
        expect_identical(summary$system_missing_count, sum(codes == 0L, na.rm = TRUE), info = name)
        expect_identical(
            summary$extended_missing_count,
            sum(codes >= utf8ToInt("a") & codes <= utf8ToInt("z"), na.rm = TRUE),
            info = name
        )
    }
    expect_identical(sum(is.nan(dtatools:::.book_numeric_data(data$x_float))), 2L)
    expect_error(codebook(data), "noncanonical NaN payload")
})

test_that("native missing-code counts match the tabulated codes", {
    native <- function(x) .Call(dtatools:::C_dtatools_missing_code_counts, x)
    tabulated <- function(x) tabulate(dtatools:::.tab_missing_codes(x) + 1L, 257L)
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    patch_numeric_fixture_row(path, 0L, list(x_float = .raw_little_integer(0x7fc00000, 4L)))
    data <- read_dta(path)
    # Rows past the first block of 4,096 decoded codes.
    long <- tempfile(fileext = ".dta")
    on.exit(unlink(long), add = TRUE)
    pattern <- c(1, NA, tagged_missing("a"), 2.5, tagged_missing("z"), -0)
    save_dta(dibble(
        d = dta_double(rep(pattern, length.out = 10001L)),
        b = dta_byte(rep(c(1, NA, 3, tagged_missing("q")), length.out = 10001L))
    ), long)
    columns <- c(as.list(data[c("x_byte", "x_int", "x_long", "x_float", "x_double")]),
                 as.list(read_dta(long)))
    for (name in names(columns)) {
        x <- columns[[name]]
        expect_identical(native(x), tabulated(x), info = name)
        values <- dtatools:::.book_numeric_data(x)
        expect_identical(native(values), tabulated(values), info = name)
        expect_identical(native(x[-1L]), tabulated(x[-1L]), info = name)
    }
    expect_identical(native(columns$x_float)[[257L]], 1L)
    expect_identical(sum(native(columns$d)), 5001L)
    for (x in list(c(NaN, NA, 1, -Inf), c(1L, NA, NA), double(), integer())) {
        expect_identical(native(x), tabulated(x))
    }
    expect_identical(dtatools:::.book_missing_code_counts(columns$d), tabulated(columns$d))
    expect_error(native("a"), "missing-code classification requires a numeric vector")
    expect_error(native(TRUE), "missing-code classification requires a numeric vector")
})

test_that("compact identity parts match the parts of the decoded values", {
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    data <- read_dta(path)
    for (name in c("x_byte", "x_int", "x_long", "x_float", "x_double")) {
        x <- data[[name]]
        values <- dtatools:::.book_numeric_data(x)
        # Reading each element builds an ordinary double vector.
        plain <- vapply(seq_along(values), function(i) values[[i]], double(1))
        expect_identical(
            dtatools:::.dta_identity_parts(x),
            dtatools:::.dta_identity_parts(plain),
            info = name
        )
    }
    patch_numeric_fixture_row(path, 0L, list(x_float = .raw_little_integer(0x7fc00000, 4L)))
    expect_error(
        dtatools:::.dta_identity_parts(read_dta(path)$x_float, "vctrs equality"),
        "`vctrs equality` cannot use a noncanonical NaN payload"
    )
})

test_that("codebook diagnostics bind as one data frame per row would", {
    data <- data.frame(
        constant = rep(1, 4),
        text = c(" a", "b ", "c d", "c d"),
        none = rep(NA_real_, 4)
    )
    result <- codebook(data, problems = TRUE, diagnostic_limit = 1)$diagnostics
    expect_true(nrow(result) > 3L)
    rows <- lapply(seq_len(nrow(result)), function(i) data.frame(
        code = result$code[[i]], scope = result$scope[[i]],
        table = result$table[[i]], variable = result$variable[[i]],
        position = result$position[[i]], severity = result$severity[[i]],
        details = I(result$details[i]), message = result$message[[i]],
        stringsAsFactors = FALSE
    ))
    expected <- do.call(rbind, rows)
    rownames(expected) <- NULL
    expect_identical(result, expected)
    expect_identical(
        codebook(data, problems = TRUE, mv = TRUE)$diagnostics,
        codebook(data, problems = TRUE)$diagnostics
    )
})
