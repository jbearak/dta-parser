fixture <- function(name) {
    system.file("extdata", name, package = "dtaparser", mustWork = TRUE)
}

fixture_with_all_numeric_missing_codes <- function(name) {
    input <- fixture(name)
    bytes <- readBin(input, "raw", n = file.info(input)[["size"]])
    row_width <- 19L
    row_count <- 30L
    if (identical(name, "missing_values_v115.dta")) {
        data_start <- length(bytes) - row_width * row_count + 1L
    } else {
        data_tag <- charToRaw("<data>")
        matches <- grepRaw(data_tag, bytes, fixed = TRUE, all = TRUE)
        stopifnot(length(matches) == 1L)
        data_start <- matches[[1L]] + length(data_tag)
        closing_tag <- charToRaw("</data>")
        closing_start <- data_start + row_width * row_count
        stopifnot(identical(
            bytes[closing_start + seq_along(closing_tag) - 1L],
            closing_tag
        ))
    }

    raw_integer <- function(value, size) {
        writeBin(as.integer(value), raw(), size = size, endian = "little")
    }
    assign_raw <- function(row, offset, value) {
        start <- data_start + row * row_width + offset
        bytes[start + seq_along(value) - 1L] <<- value
    }
    for (code in 0:26) {
        assign_raw(
            code, 0L,
            c(raw(4L), raw_integer(0x7fe00000 + code * 0x100, 4L))
        )
        assign_raw(code, 8L, as.raw(101L + code))
        assign_raw(code, 9L, raw_integer(32741L + code, 2L))
        assign_raw(code, 11L, raw_integer(2147483621 + code, 4L))
        assign_raw(
            code, 15L,
            raw_integer(0x7f000000 + code * 0x800, 4L)
        )
    }

    output <- tempfile(fileext = ".dta")
    writeBin(bytes, output)
    output
}

replace_first_byte <- function(bytes, text, replacement) {
    needle <- charToRaw(text)
    starts <- seq_len(length(bytes) - length(needle) + 1L)
    matches <- vapply(starts, function(start) {
        identical(bytes[start:(start + length(needle) - 1L)], needle)
    }, logical(1))
    stopifnot(any(matches))
    bytes[starts[which(matches)[[1L]]]] <- as.raw(replacement)
    bytes
}

test_that("read_dta extends the haven-compatible public signature", {
    expected <- c(
        "file", "encoding", "col_select", "skip", "n_max", ".name_repair",
        "threads", "use_numeric_altrep"
    )
    expect_identical(names(formals(read_dta)), expected)
    expect_null(formals(read_dta)$encoding)
    expect_null(formals(read_dta)$col_select)
    expect_identical(formals(read_dta)$skip, 0)
    expect_identical(formals(read_dta)$n_max, Inf)
    expect_identical(formals(read_dta)$.name_repair, "unique")
    expect_identical(
        formals(read_dta)$threads,
        quote(getOption("dtaparser.threads", 0L))
    )
    expect_identical(
        formals(read_dta)$use_numeric_altrep,
        quote(getOption("dtaparser.numeric_altrep", TRUE))
    )
    expect_identical(nrow(read_dta(fixture("auto_v118.dta"), n = 2)), 2L)
})

test_that("numeric ALTREP can be disabled explicitly or by option", {
    path <- fixture("all_types_v118.dta")
    reference <- dtaparser:::.read_dta_rust_vectors(path)
    explicit <- read_dta(path, use_numeric_altrep = FALSE, threads = 1L)
    parallel <- read_dta(path, use_numeric_altrep = FALSE, threads = 4L)

    expect_identical(explicit, reference)
    expect_identical(parallel, explicit)
    numeric_columns <- vapply(explicit, is.numeric, logical(1))
    expect_false(any(vapply(
        explicit[numeric_columns],
        dtaparser:::.is_numeric_altrep,
        logical(1)
    )))

    previous <- options(dtaparser.numeric_altrep = FALSE)
    on.exit(options(previous), add = TRUE)
    from_option <- read_dta(path)
    expect_identical(from_option, explicit)
    expect_false(any(vapply(
        from_option[numeric_columns],
        dtaparser:::.is_numeric_altrep,
        logical(1)
    )))

    empty <- read_dta(
        path,
        col_select = c(v_byte, v_double),
        n_max = 0,
        use_numeric_altrep = FALSE
    )
    expect_identical(empty, dtaparser:::.read_dta_rust_vectors(
        path, col_select = c(v_byte, v_double), n_max = 0
    ))
    expect_false(any(vapply(
        empty, dtaparser:::.is_numeric_altrep, logical(1)
    )))
})

test_that("R and haven recognize every Stata numeric missing code", {
    skip_if_not_installed("haven")
    expected_tags <- c(NA_character_, letters)
    expected_tagged <- c(FALSE, rep(TRUE, 26L))
    expected_system <- c(TRUE, rep(FALSE, 26L))

    paths <- character()
    on.exit(unlink(paths), add = TRUE)
    for (name in c("missing_values_v115.dta", "missing_values_v118.dta")) {
        path <- fixture_with_all_numeric_missing_codes(name)
        paths <- c(paths, path)
        storage <- attr(dtaparser:::.dta_metadata(path), "dta_storage")
        numeric_indices <- which(storage != "character")

        for (use_numeric_altrep in c(TRUE, FALSE)) {
            actual <- read_dta(
                path,
                n_max = 27,
                use_numeric_altrep = use_numeric_altrep
            )
            mode <- if (use_numeric_altrep) "default" else "eager"
            for (index in numeric_indices) {
                values <- unclass(actual[[index]])
                info <- paste(name, storage[[index]], mode)

                expect_identical(
                    dtaparser:::.is_numeric_altrep(values),
                    use_numeric_altrep && storage[[index]] != "double",
                    info = paste(info, "representation")
                )
                expect_true(all(is.na(values)), info = paste(info, "is.na"))
                expect_identical(
                    haven::na_tag(values),
                    expected_tags,
                    info = paste(info, "na_tag")
                )
                expect_identical(
                    haven::is_tagged_na(values),
                    expected_tagged,
                    info = paste(info, "is_tagged_na")
                )
                expect_identical(
                    is.na(values) & !is.nan(values) &
                        !haven::is_tagged_na(values),
                    expected_system,
                    info = paste(info, "system missing")
                )
                for (tag in letters) {
                    expected_match <- seq_along(expected_tags) ==
                        match(tag, letters) + 1L
                    expect_identical(
                        haven::is_tagged_na(values, tag),
                        expected_match,
                        info = paste(info, "tag", tag)
                    )
                }
            }
        }
    }
})

test_that("base R recoding preserves tags with complete predicates", {
    skip_if_not_installed("haven")
    expected_tags <- c(NA_character_, letters)

    paths <- character()
    on.exit(unlink(paths), add = TRUE)
    for (name in c("missing_values_v115.dta", "missing_values_v118.dta")) {
        path <- fixture_with_all_numeric_missing_codes(name)
        paths <- c(paths, path)
        storage <- attr(dtaparser:::.dta_metadata(path), "dta_storage")

        for (use_numeric_altrep in c(TRUE, FALSE)) {
            actual <- read_dta(
                path,
                n_max = 30,
                use_numeric_altrep = use_numeric_altrep
            )
            mode <- if (use_numeric_altrep) "default" else "eager"

            for (index in seq_along(actual)) {
                original <- actual[[index]]
                selected <- !is.na(original) & original == original[[28L]]
                info <- paste(name, storage[[index]], mode)
                expect_false(anyNA(selected), info = paste(info, "predicate"))

                assigned <- original
                assigned[selected] <- -1
                expect_identical(
                    haven::na_tag(assigned[seq_len(27L)]),
                    expected_tags,
                    info = paste(info, "subassignment tags")
                )
                expect_identical(
                    attributes(assigned),
                    attributes(original),
                    info = paste(info, "subassignment attributes")
                )

                replaced <- replace(original, selected, -1)
                expect_identical(
                    haven::na_tag(replaced[seq_len(27L)]),
                    expected_tags,
                    info = paste(info, "replace tags")
                )
                expect_identical(
                    attributes(replaced),
                    attributes(original),
                    info = paste(info, "replace attributes")
                )

                tag_assigned <- original
                tag_assigned[haven::is_tagged_na(tag_assigned, "a")] <- -2
                remaining_tags <- expected_tags
                remaining_tags[[2L]] <- NA_character_
                expect_identical(
                    haven::na_tag(tag_assigned[seq_len(27L)]),
                    remaining_tags,
                    info = paste(info, "tag-specific assignment")
                )

                safe_ifelse <- ifelse(selected, -1, original)
                expect_identical(
                    haven::na_tag(safe_ifelse[seq_len(27L)]),
                    expected_tags,
                    info = paste(info, "complete ifelse predicate")
                )
                expect_null(
                    attributes(safe_ifelse),
                    info = paste(info, "ifelse attributes")
                )

                unsafe_ifelse <- ifelse(
                    original == original[[28L]], -1, original
                )
                expect_identical(
                    haven::na_tag(unsafe_ifelse[seq_len(27L)]),
                    rep(NA_character_, 27L),
                    info = paste(info, "incomplete ifelse predicate")
                )
            }
        }
    }
})

test_that("both recode interfaces preserve every Stata missing code", {
    skip_if_not_installed("haven")
    expected_tags <- c(NA_character_, letters)
    interfaces <- list(
        dtaparser = dtaparser::recode,
        dplyr = dplyr::recode
    )

    paths <- character()
    on.exit(unlink(paths), add = TRUE)
    for (name in c("missing_values_v115.dta", "missing_values_v118.dta")) {
        path <- fixture_with_all_numeric_missing_codes(name)
        paths <- c(paths, path)
        storage <- attr(dtaparser:::.dta_metadata(path), "dta_storage")

        for (use_numeric_altrep in c(TRUE, FALSE)) {
            actual <- read_dta(
                path,
                n_max = 30,
                use_numeric_altrep = use_numeric_altrep
            )
            mode <- if (use_numeric_altrep) "default" else "eager"

            for (index in seq_along(actual)) {
                original <- actual[[index]]
                replacement <- stats::setNames(
                    list(-1), as.character(original[[28L]])
                )

                for (interface in names(interfaces)) {
                    recode_function <- interfaces[[interface]]
                    recoded <- rlang::exec(
                        recode_function, original, !!!replacement
                    )
                    info <- paste(
                        name, storage[[index]], mode, interface
                    )

                    expect_identical(
                        haven::na_tag(recoded[seq_len(27L)]),
                        expected_tags,
                        info = paste(info, "tags")
                    )
                    expect_identical(
                        attributes(recoded),
                        attributes(original),
                        info = paste(info, "attributes")
                    )
                    expect_identical(
                        unname(recoded[[28L]]),
                        -1,
                        info = paste(info, "observed replacement")
                    )
                    expect_false(
                        dtaparser:::.is_numeric_altrep(recoded),
                        info = paste(info, "materialized result")
                    )

                    replaced_missing <- rlang::exec(
                        recode_function,
                        original,
                        !!!replacement,
                        .missing = -99
                    )
                    expect_identical(
                        unname(replaced_missing[seq_len(27L)]),
                        rep(-99, 27L),
                        info = paste(info, "explicit missing replacement")
                    )
                    expect_false(
                        any(haven::is_tagged_na(replaced_missing)),
                        info = paste(info, "explicit replacement tags")
                    )

                    expect_error(
                        rlang::exec(
                            recode_function,
                            original,
                            !!!stats::setNames(
                                list("observed"),
                                as.character(original[[28L]])
                            ),
                            .default = "other"
                        ),
                        "non-numeric recode"
                    )
                    character_result <- rlang::exec(
                        recode_function,
                        original,
                        !!!stats::setNames(
                            list("observed"),
                            as.character(original[[28L]])
                        ),
                        .default = "other",
                        .missing = "missing"
                    )
                    expect_identical(
                        character_result[seq_len(27L)],
                        rep("missing", 27L),
                        info = paste(info, "type-changing missing choice")
                    )
                }
            }

            mutated <- dplyr::mutate(
                actual,
                dplyr::across(
                    dplyr::everything(),
                    function(values) {
                        dynamic_replacement <- stats::setNames(
                            list(-1), as.character(values[[28L]])
                        )
                        do.call(
                            dplyr::recode,
                            c(list(values), dynamic_replacement)
                        )
                    }
                )
            )
            for (index in seq_along(mutated)) {
                info <- paste(name, storage[[index]], mode, "mutate")
                expect_identical(
                    haven::na_tag(mutated[[index]][seq_len(27L)]),
                    expected_tags,
                    info = paste(info, "tags")
                )
                expect_identical(
                    attributes(mutated[[index]]),
                    attributes(actual[[index]]),
                    info = paste(info, "attributes")
                )
                expect_identical(
                    unname(mutated[[index]][[28L]]),
                    -1,
                    info = paste(info, "observed replacement")
                )
            }
        }
    }
})

test_that("dplyr recode keeps its ordinary numeric behavior", {
    dplyr_numeric <- get(
        "recode.numeric", envir = asNamespace("dplyr"), inherits = FALSE
    )
    cases <- list(
        list(
            source = c(1, 2, 3), replacements = list(10, 20),
            default = NULL, missing = NULL
        ),
        list(
            source = c(1, 2, 3),
            replacements = stats::setNames(list(10), "1"),
            default = -1, missing = NULL
        ),
        list(
            source = c(1, NA_real_, 2),
            replacements = stats::setNames(list(10), "1"),
            default = NULL, missing = -99
        ),
        list(
            source = c(1L, 2L, NA_integer_),
            replacements = stats::setNames(list(10L), "1"),
            default = NULL, missing = NULL
        ),
        list(
            source = c(1L, 2L, NA_integer_),
            replacements = stats::setNames(list(10), "1"),
            default = NULL, missing = NULL
        ),
        list(
            source = c(1, 2),
            replacements = stats::setNames(
                list("one", "two"), c("1", "2")
            ),
            default = "other", missing = "missing"
        ),
        list(
            source = c(1, NA_real_),
            replacements = stats::setNames(list("one"), "1"),
            default = "other", missing = NULL
        ),
        list(
            source = c(1, NaN, 2),
            replacements = stats::setNames(list(10), "1"),
            default = NULL, missing = NULL
        ),
        list(
            source = structure(c(1, 2), label = "ordinary numeric"),
            replacements = stats::setNames(list(10), "1"),
            default = NULL, missing = NULL
        )
    )

    call_recode <- function(recode_function, specification) {
        rlang::exec(
            recode_function,
            specification$source,
            !!!specification$replacements,
            .default = specification$default,
            .missing = specification$missing
        )
    }
    for (index in seq_along(cases)) {
        if (index == 5L) {
            expect_warning(
                actual <- call_recode(dplyr::recode, cases[[index]]),
                "Unreplaced values treated as NA"
            )
            expect_warning(
                expected <- call_recode(dplyr_numeric, cases[[index]]),
                "Unreplaced values treated as NA"
            )
        } else {
            actual <- call_recode(dplyr::recode, cases[[index]])
            expected <- call_recode(dplyr_numeric, cases[[index]])
        }
        expect_identical(
            actual,
            expected,
            info = paste("ordinary numeric case", index)
        )
    }
})

test_that("tag detection distinguishes R missing payloads", {
    skip_if_not_installed("haven")
    expect_false(dtaparser:::.has_tagged_na(c(1, NA_real_, NaN)))
    expect_true(dtaparser:::.has_tagged_na(haven::tagged_na("a")))
    expect_true(dtaparser:::.has_tagged_na(haven::tagged_na("z")))
    expect_false(dtaparser:::.has_tagged_na(c(1L, NA_integer_)))

    created <- 1:3
    created[[2L]] <- haven::tagged_na("f")
    expect_type(created, "double")
    expect_identical(
        haven::na_tag(dplyr::recode(created, `1` = 10)),
        c(NA_character_, "f", NA_character_)
    )
})

test_that("dtaparser recode retains the familiar vector interface", {
    skip_if_not_installed("haven")
    expect_true("recode" %in% getNamespaceExports("dtaparser"))
    expect_identical(
        names(formals(dtaparser::recode)),
        c(".x", "...", ".default", ".missing")
    )

    expect_identical(
        dtaparser::recode(c(1, 2, 3), 10, 20),
        c(10, 20, 3)
    )
    expect_identical(
        dtaparser::recode(c(1L, 2L, NA_integer_), `1` = 10L),
        c(10L, 2L, NA_integer_)
    )
    expect_identical(
        dtaparser::recode(c(1L, 2L, NA_integer_), `1` = 10),
        c(10L, 2L, NA_integer_)
    )
    expect_identical(
        dtaparser::recode(c(1L, 2L, NA_integer_), `1` = 10.5),
        c(10.5, 2, NA_real_)
    )
    expect_identical(
        dtaparser::recode(c("a", "b", NA_character_), a = "A"),
        c("A", "b", NA_character_)
    )
    expect_identical(
        dtaparser::recode(factor(c("a", "b", NA_character_)), a = "A"),
        factor(c("A", "b", NA_character_))
    )
    expect_error(
        dtaparser::recode(
            factor(c("a", NA_character_)), a = "A", .missing = "missing"
        ),
        "not supported for factors"
    )
    expect_error(
        dtaparser::recode(c(1, 2), first = 10, 20),
        "Either all values must be named"
    )
    expect_error(
        dtaparser::recode(
            c(1, 2), `1` = as.Date("2020-01-01"),
            `2` = as.Date("2020-01-02")
        ),
        "Class-changing numeric replacements"
    )
    expect_error(
        dtaparser::recode(c(1, 2), `1` = factor("one")),
        "Class-changing numeric replacements"
    )

    missing_values <- c(
        NaN, NA_real_, haven::tagged_na("a"), haven::tagged_na("z")
    )
    preserved <- dtaparser::recode(
        c(1, missing_values), `1` = 10
    )[-1L]
    expect_identical(preserved, missing_values)

    retagged <- dtaparser::recode(
        missing_values,
        .default = missing_values,
        .missing = haven::tagged_na("f")
    )
    expect_identical(
        haven::na_tag(retagged),
        rep("f", length(missing_values))
    )

    integer_labelled <- haven::labelled(
        c(1L, 2L, NA_integer_), labels = c(one = 1L, two = 2L)
    )
    integer_result <- dtaparser::recode(integer_labelled, `1` = 10)
    expect_s3_class(integer_result, "haven_labelled")
    expect_identical(
        vctrs::vec_data(integer_result), c(10L, 2L, NA_integer_)
    )
    expect_identical(attr(integer_result, "labels"), c(one = 1L, two = 2L))

    widened_result <- dtaparser::recode(integer_labelled, `1` = 10.5)
    expect_s3_class(widened_result, "haven_labelled")
    expect_identical(
        vctrs::vec_data(widened_result), c(10.5, 2, NA_real_)
    )
    expect_identical(attr(widened_result, "labels"), c(one = 1, two = 2))

    tagged_integer_result <- dtaparser::recode(
        integer_labelled, `1` = 10L, .missing = haven::tagged_na("f")
    )
    expect_s3_class(tagged_integer_result, "haven_labelled")
    expect_identical(
        haven::na_tag(vctrs::vec_data(tagged_integer_result)),
        c(NA_character_, NA_character_, "f")
    )
    expect_identical(
        attr(tagged_integer_result, "labels"), c(one = 1, two = 2)
    )

    nan_result <- dtaparser::recode(
        c(1L, 2L, NA_integer_), `1` = NaN
    )
    expect_identical(is.nan(nan_result), c(TRUE, FALSE, FALSE))
    expect_identical(is.na(nan_result), c(TRUE, FALSE, TRUE))

    tagged_date <- structure(
        c(1, haven::tagged_na("a")),
        class = "Date",
        format.stata = "%td"
    )
    recoded_date <- dtaparser::recode(tagged_date, `1` = 10L)
    expect_s3_class(recoded_date, "Date")
    expect_identical(attr(recoded_date, "format.stata"), "%td")
    expect_identical(haven::na_tag(unclass(recoded_date)), c(NA, "a"))

    same_class_date <- dtaparser::recode(
        tagged_date, `1` = as.Date("1970-01-11")
    )
    expect_s3_class(same_class_date, "Date")
    expect_identical(unclass(same_class_date)[[1L]], 10)
    expect_identical(
        haven::na_tag(unclass(same_class_date)), c(NA, "a")
    )
})

test_that("dplyr recoding preserves unselected Stata missing codes", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("haven")
    expected_tags <- c(NA_character_, letters)
    recoded_tags <- expected_tags
    recoded_tags[c(2L, 7L)] <- NA_character_
    recoded_missing <- rep(TRUE, 27L)
    recoded_missing[c(2L, 7L)] <- FALSE

    recode_tags <- function(data) {
        dplyr::mutate(
            data,
            dplyr::across(
                dplyr::everything(),
                function(values) {
                    dplyr::case_when(
                        haven::is_tagged_na(values, "a") ~ -1,
                        haven::is_tagged_na(values, "f") ~ -6,
                        .default = values
                    )
                }
            )
        )
    }
    recode_observed <- function(data) {
        dplyr::mutate(
            data,
            dplyr::across(
                dplyr::everything(),
                function(values) {
                    dplyr::if_else(is.na(values), values, values + 1)
                }
            )
        )
    }

    paths <- character()
    on.exit(unlink(paths), add = TRUE)
    for (name in c("missing_values_v115.dta", "missing_values_v118.dta")) {
        path <- fixture_with_all_numeric_missing_codes(name)
        paths <- c(paths, path)
        storage <- attr(dtaparser:::.dta_metadata(path), "dta_storage")
        reference_tags <- recode_tags(haven::read_dta(path, n_max = 27))
        reference_observed <- recode_observed(
            haven::read_dta(path, n_max = 30)
        )

        for (use_numeric_altrep in c(TRUE, FALSE)) {
            tagged <- recode_tags(read_dta(
                path,
                n_max = 27,
                use_numeric_altrep = use_numeric_altrep
            ))
            source <- read_dta(
                path,
                n_max = 30,
                use_numeric_altrep = use_numeric_altrep
            )
            observed <- recode_observed(source)
            mode <- if (use_numeric_altrep) "default" else "eager"

            for (index in seq_along(tagged)) {
                info <- paste(name, storage[[index]], mode)
                expect_identical(
                    tagged[[index]],
                    reference_tags[[index]],
                    info = paste(info, "selective recode matches haven")
                )
                expect_identical(
                    haven::na_tag(tagged[[index]]),
                    recoded_tags,
                    info = paste(info, "unselected tags")
                )
                expect_identical(
                    is.na(tagged[[index]]),
                    recoded_missing,
                    info = paste(info, "missing positions")
                )
                expect_identical(
                    unname(tagged[[index]][c(2L, 7L)]),
                    c(-1, -6),
                    info = paste(info, "selected replacements")
                )
                expect_identical(
                    observed[[index]],
                    reference_observed[[index]],
                    info = paste(info, "observed recode matches haven")
                )
                expect_identical(
                    haven::na_tag(observed[[index]][seq_len(27L)]),
                    expected_tags,
                    info = paste(info, "observed recode tags")
                )

                condition <- source[[index]] == source[[index]][[28L]]
                unsafe_if_else <- dplyr::if_else(
                    condition, -1, source[[index]]
                )
                expect_identical(
                    haven::na_tag(unsafe_if_else[seq_len(27L)]),
                    rep(NA_character_, 27L),
                    info = paste(info, "if_else missing condition")
                )
                safe_if_else <- dplyr::if_else(
                    condition, -1, source[[index]], missing = source[[index]]
                )
                expect_identical(
                    haven::na_tag(safe_if_else[seq_len(27L)]),
                    expected_tags,
                    info = paste(info, "if_else missing branch")
                )

                registered_recode <- rlang::exec(
                    dplyr::recode,
                    source[[index]],
                    !!!stats::setNames(
                        list(-1), as.character(source[[index]][[28L]])
                    )
                )
                expect_identical(
                    haven::na_tag(registered_recode[seq_len(27L)]),
                    expected_tags,
                    info = paste(info, "registered recode tags")
                )
                expect_identical(
                    unname(registered_recode[[28L]]),
                    -1,
                    info = paste(info, "registered recode replacement")
                )
            }
        }
    }
})

test_that("dplyr manipulation matches haven for every storage type", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("haven")

    manipulate <- function(data) {
        dplyr::mutate(
            data,
            dplyr::across(
                dplyr::everything(),
                function(values) {
                    if (is.character(values)) {
                        dplyr::if_else(
                            is.na(values), values, paste0(values, "-recoded")
                        )
                    } else {
                        dplyr::if_else(is.na(values), values, values + 1)
                    }
                }
            )
        )
    }

    for (name in c("all_types_v115.dta", "all_types_v118.dta")) {
        path <- fixture(name)
        expected <- manipulate(haven::read_dta(path))
        storage <- attr(dtaparser:::.dta_metadata(path), "dta_storage")

        for (use_numeric_altrep in c(TRUE, FALSE)) {
            actual <- manipulate(read_dta(
                path,
                use_numeric_altrep = use_numeric_altrep
            ))
            mode <- if (use_numeric_altrep) "default" else "eager"
            expect_identical(names(actual), names(expected))
            for (index in seq_along(actual)) {
                expect_identical(
                    actual[[index]],
                    expected[[index]],
                    info = paste(name, storage[[index]], mode)
                )
            }
        }
    }
})

test_that("dplyr manipulation matches haven for labelled and temporal data", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    tagged_date <- structure(
        c(0, unclass(haven::tagged_na("a")), NA_real_),
        class = "Date"
    )
    tagged_instant <- structure(
        c(0, unclass(haven::tagged_na("b")), NA_real_),
        class = c("POSIXct", "POSIXt"),
        tzone = "UTC"
    )
    input <- tibble::tibble(
        labelled = haven::labelled(
            c(1, haven::tagged_na("c"), NA_real_),
            labels = c(one = 1)
        ),
        date = tagged_date,
        instant = tagged_instant,
        text = c("alpha", "", "omega")
    )
    haven::write_dta(input, path, version = 15)

    manipulate <- function(data) {
        dplyr::mutate(
            data,
            labelled = dplyr::case_when(
                labelled == 1 ~ 2,
                .default = labelled
            ),
            date = dplyr::if_else(is.na(date), date, date + 1),
            instant = dplyr::if_else(
                is.na(instant), instant, instant + 1
            ),
            text = dplyr::if_else(text == "alpha", "recoded", text)
        )
    }
    expected <- manipulate(haven::read_dta(path))
    unmanipulated <- read_dta(path)

    classed_labelled <- dplyr::recode(unmanipulated$labelled, `1` = 2)
    classed_date <- dplyr::recode(unmanipulated$date, `0` = 1)
    classed_instant <- dplyr::recode(unmanipulated$instant, `0` = 1)
    expect_s3_class(classed_labelled, "haven_labelled")
    expect_s3_class(classed_date, "Date")
    expect_s3_class(classed_instant, "POSIXct")
    expect_identical(
        haven::na_tag(unclass(classed_labelled)),
        c(NA_character_, "c", NA_character_)
    )
    expect_identical(
        haven::na_tag(unclass(classed_date)),
        c(NA_character_, "a", NA_character_)
    )
    expect_identical(
        haven::na_tag(unclass(classed_instant)),
        c(NA_character_, "b", NA_character_)
    )

    for (use_numeric_altrep in c(TRUE, FALSE)) {
        actual <- manipulate(read_dta(
            path,
            use_numeric_altrep = use_numeric_altrep
        ))
        mode <- if (use_numeric_altrep) "default" else "eager"
        expect_identical(actual, expected, info = mode)
        expect_s3_class(actual$labelled, "haven_labelled")
        expect_s3_class(actual$date, "Date")
        expect_s3_class(actual$instant, "POSIXct")
        expect_identical(
            haven::na_tag(unclass(actual$labelled)),
            c(NA_character_, "c", NA_character_),
            info = paste(mode, "labelled tag")
        )
        expect_identical(
            haven::na_tag(unclass(actual$date)),
            c(NA_character_, "a", NA_character_),
            info = paste(mode, "Date tag")
        )
        expect_identical(
            haven::na_tag(unclass(actual$instant)),
            c(NA_character_, "b", NA_character_),
            info = paste(mode, "POSIXct tag")
        )
    }

    source <- fixture("auto_v118.dta")
    bytes <- readBin(source, "raw", n = file.info(source)[["size"]])
    data_tag <- charToRaw("<data>")
    data_start <- grepRaw(data_tag, bytes, fixed = TRUE)[[1L]] +
        length(data_tag)
    closing_start <- grepRaw(
        charToRaw("</data>"), bytes, fixed = TRUE
    )[[1L]]
    row_width <- as.integer((closing_start - data_start) / 74L)
    expect_identical(row_width, 43L)

    # `foreign` is the final one-byte field; make its first value `.a` while
    # retaining its value-label table and haven_labelled class.
    bytes[[data_start + row_width - 1L]] <- as.raw(102L)

    # `price` follows the 18-byte `make` field and is a two-byte int. Change
    # its first value to `.a` and its display format to `%td`, making it an
    # integer-backed Date. The second format match is `price`; the first occurs
    # outside its fixed-width format entry in this fixture.
    bytes[data_start + 18L + 0:1] <- writeBin(
        as.integer(32742L), raw(), size = 2L, endian = "little"
    )
    old_format <- charToRaw("%8.0gc")
    format_matches <- grepRaw(old_format, bytes, fixed = TRUE, all = TRUE)
    expect_gte(length(format_matches), 2L)
    price_format <- format_matches[[2L]]
    bytes[price_format + seq_along(old_format) - 1L] <- c(
        charToRaw("%td"), raw(length(old_format) - 3L)
    )

    narrow_path <- tempfile(fileext = ".dta")
    on.exit(unlink(narrow_path), add = TRUE)
    writeBin(bytes, narrow_path)
    narrow <- read_dta(narrow_path)
    narrow_reference <- haven::read_dta(narrow_path)
    expect_true(dtaparser:::.is_numeric_altrep(narrow$foreign))
    expect_true(dtaparser:::.is_numeric_altrep(narrow$price))
    expect_s3_class(narrow$foreign, "haven_labelled")
    expect_s3_class(narrow$price, "Date")
    expect_identical(haven::na_tag(unclass(narrow$foreign))[[1L]], "a")
    expect_identical(haven::na_tag(unclass(narrow$price))[[1L]], "a")

    manipulate_narrow <- function(data) {
        dplyr::mutate(
            data,
            foreign = dplyr::case_when(
                foreign == 0 ~ 2,
                .default = foreign
            ),
            price = dplyr::if_else(is.na(price), price, price + 1)
        )
    }
    narrow_input <- read_dta(narrow_path)
    expect_true(dtaparser:::.is_numeric_altrep(narrow_input$foreign))
    expect_true(dtaparser:::.is_numeric_altrep(narrow_input$price))
    narrow_transformed <- manipulate_narrow(narrow_input)
    narrow_expected <- manipulate_narrow(narrow_reference)
    expect_identical(
        narrow_transformed,
        narrow_expected
    )
    expect_identical(
        haven::na_tag(unclass(narrow_transformed$foreign))[[1L]],
        "a"
    )
    expect_identical(
        haven::na_tag(unclass(narrow_transformed$price))[[1L]],
        "a"
    )
})

test_that("parallel decoding is identical across supported releases", {
    modern <- fixture("auto_v118.dta")
    serial <- read_dta(modern, threads = 1L)
    parallel <- read_dta(modern, threads = 4L)
    projected <- read_dta(
        modern,
        col_select = c(text = make, number = price),
        threads = 4L
    )
    expect_identical(parallel, serial)
    expect_identical(
        projected,
        read_dta(
            modern,
            col_select = c(text = make, number = price),
            threads = 1L
        )
    )

    for (name in c("all_types_v115.dta", "all_types_v117.dta")) {
        expect_identical(
            read_dta(fixture(name), threads = 4L),
            read_dta(fixture(name), threads = 1L),
            info = name
        )
    }
    expect_identical(
        read_dta(fixture("strl_test_v118.dta"), threads = 4L),
        read_dta(fixture("strl_test_v118.dta"), threads = 1L)
    )
})

test_that("internal metadata projection is bounded and preserves attributes", {
    path <- fixture("all_types_v118.dta")
    full <- dtaparser:::.dta_metadata(path)
    middle <- dtaparser:::.dta_metadata(path, column_start = 3L, column_count = 2L)
    suffix <- dtaparser:::.dta_metadata(path, column_start = 7L)
    empty <- dtaparser:::.dta_metadata(path, column_start = 2L, column_count = 0L)
    past <- dtaparser:::.dta_metadata(path, column_start = 100L, column_count = 2L)

    expect_identical(as.character(middle), as.character(full[3:4]))
    expect_identical(attr(middle, "dta_storage"), attr(full, "dta_storage")[3:4])
    expect_identical(attr(middle, "dta_format_version"),
                     attr(full, "dta_format_version"))
    expect_identical(as.character(suffix), as.character(full[7:8]))
    expect_length(empty, 0L)
    expect_length(attr(empty, "dta_storage"), 0L)
    expect_length(past, 0L)

    invalid <- list(-1, 1.5, NA_real_, NaN, c(1, 2), "1")
    for (value in invalid) {
        expect_error(dtaparser:::.dta_metadata(path, column_start = value))
        expect_error(dtaparser:::.dta_metadata(path, column_count = value))
    }
})

test_that("all bundled fixtures agree with haven", {
    skip_if_not_installed("haven")
    paths <- list.files(
        system.file("extdata", package = "dtaparser"),
        pattern = "[.]dta$",
        full.names = TRUE
    )
    expect_gt(length(paths), 20L)

    for (path in paths) {
        actual <- read_dta(path)
        rust_vectors <- dtaparser:::.read_dta_rust_vectors(path)
        expected <- haven::read_dta(path)
        info <- basename(path)
        metadata <- dtaparser:::.dta_metadata(normalizePath(path))
        storage <- stats::setNames(
            attr(metadata, "dta_storage", exact = TRUE),
            as.character(metadata)
        )

        expect_identical(actual, rust_vectors,
                         info = paste(info, "direct and Rust-vector collectors"))
        expect_identical(dim(actual), dim(expected), info = info)
        expect_identical(names(actual), names(expected), info = info)
        expect_identical(attr(actual, "label", exact = TRUE),
                         attr(expected, "label", exact = TRUE), info = info)
        expect_identical(attr(actual, "notes", exact = TRUE),
                         attr(expected, "notes", exact = TRUE), info = info)
        expect_null(attr(actual, "dta_format_version", exact = TRUE), info = info)
        expect_identical(attributes(actual), attributes(expected), info = info)
        expect_true(attr(metadata, "dta_format_version", exact = TRUE) %in%
                    c(105L, 108L, 110L, 111L, 113L, 114L, 115L,
                      117L, 118L, 119L), info = info)

        for (name in names(actual)) {
            if (storage[[name]] %in% c("float", "double")) {
                expect_equal(actual[[name]], expected[[name]], tolerance = 1e-7,
                             info = paste(info, name))
            } else {
                expect_equal(actual[[name]], expected[[name]], tolerance = 0,
                             info = paste(info, name, "exact"))
            }
            expect_identical(is.na(actual[[name]]), is.na(expected[[name]]),
                             info = paste(info, name, "missing positions"))
            if (is.numeric(actual[[name]])) {
                expect_identical(
                    haven::na_tag(actual[[name]]),
                    haven::na_tag(expected[[name]]),
                    info = paste(info, name, "missing tags")
                )
            }
        }
    }
})

test_that("dataset-note cardinality, ordering, and empty values match haven", {
    skip_if_not_installed("haven")
    source <- fixture("auto_v118.dta")
    multiple <- readBin(source, "raw", file.info(source)$size)
    one <- replace_first_byte(multiple, "note0", utf8ToInt("x"))
    empty <- replace_first_byte(
        multiple, "From Consumer Reports with permission", 0
    )
    zero <- replace_first_byte(one, "note1", utf8ToInt("x"))

    for (variant in list(multiple = multiple, one = one, empty = empty,
                         zero = zero)) {
        expected <- haven::read_dta(
            variant, col_select = make, skip = 2, n_max = 3
        )
        actual <- read_dta(
            variant, col_select = make, skip = 2, n_max = 3
        )
        rust_vectors <- dtaparser:::.read_dta_rust_vectors(
            variant, col_select = make, skip = 2, n_max = 3
        )

        expect_identical(actual, rust_vectors)
        expect_identical(attr(actual, "notes", exact = TRUE),
                         attr(expected, "notes", exact = TRUE))
    }
})

test_that("projection, renaming, and row bounds match haven", {
    skip_if_not_installed("haven")
    path <- fixture("auto_v118.dta")
    actual <- read_dta(
        path,
        col_select = c(origin = foreign, make, price),
        skip = 5,
        n_max = 4
    )
    rust_vectors <- dtaparser:::.read_dta_rust_vectors(
        path,
        col_select = c(origin = foreign, make, price),
        skip = 5,
        n_max = 4
    )
    expected <- haven::read_dta(path, skip = 5, n_max = 4)

    expect_identical(actual, rust_vectors)
    expect_identical(names(actual), c("origin", "make", "price"))
    expect_equal(actual$origin, expected$foreign)
    expect_equal(actual$make, expected$make)
    expect_equal(actual$price, expected$price)
    expect_identical(attr(actual, "label"), attr(expected, "label"))
    expect_identical(attr(actual, "notes"), attr(expected, "notes"))
    expect_null(attr(actual, "dta_format_version", exact = TRUE))
})

test_that("an empty projection retains the selected row count", {
    path <- fixture("auto_v118.dta")
    result <- read_dta(path, col_select = character(), skip = 2, n_max = 3)
    rust_vectors <- dtaparser:::.read_dta_rust_vectors(
        path, col_select = character(), skip = 2, n_max = 3
    )
    expect_identical(result, rust_vectors)
    expect_identical(dim(result), c(3L, 0L))
})

test_that("safe row-window inputs align with haven in both collectors", {
    skip_if_not_installed("haven")
    path <- fixture("auto_v118.dta")
    cases <- list(
        integer = list(skip = 2L, n_max = 3L),
        integer_valued_double = list(skip = 2, n_max = 3),
        zero = list(skip = 0, n_max = 0),
        skip_beyond_rows = list(skip = 1000, n_max = 3),
        n_max_beyond_rows = list(skip = 72, n_max = 1000),
        bare_na_unlimited = list(skip = 2, n_max = NA),
        real_na_unlimited = list(skip = 2, n_max = NA_real_),
        positive_infinity_unlimited = list(skip = 2, n_max = Inf),
        negative_infinity_unlimited = list(skip = 2, n_max = -Inf),
        negative_integer_unlimited = list(skip = 2, n_max = -1L),
        negative_double_unlimited = list(skip = 2, n_max = -1.5)
    )

    for (name in names(cases)) {
        arguments <- c(
            list(path, col_select = c("make", "price")), cases[[name]]
        )
        actual <- do.call(read_dta, arguments)
        rust_vectors <- do.call(
            dtaparser:::.read_dta_rust_vectors, arguments
        )
        expected <- do.call(haven::read_dta, arguments)

        expect_identical(actual, rust_vectors,
                         info = paste(name, "materialization"))
        expect_identical(actual, expected, info = name)
    }
})

test_that("the largest exact skip is deterministic in both collectors", {
    path <- fixture("auto_v118.dta")
    actual <- read_dta(
        path, col_select = c("make", "price"), skip = 2^53, n_max = 3
    )
    rust_vectors <- dtaparser:::.read_dta_rust_vectors(
        path, col_select = c("make", "price"), skip = 2^53, n_max = 3
    )

    expect_identical(actual, rust_vectors)
    expect_identical(dim(actual), c(0L, 2L))
})

test_that("normalized windows cover empty data and zero-column projections", {
    skip_if_not_installed("haven")
    empty <- tempfile(fileext = ".dta")
    on.exit(unlink(empty), add = TRUE)
    haven::write_dta(data.frame(number = double(), text = character()), empty)

    for (n_max in list(0L, NA, Inf, -Inf, -1)) {
        actual <- read_dta(empty, n_max = n_max)
        rust_vectors <- dtaparser:::.read_dta_rust_vectors(
            empty, n_max = n_max
        )
        expected <- haven::read_dta(empty, n_max = n_max)
        expect_identical(actual, rust_vectors)
        expect_identical(actual, expected)
    }

    path <- fixture("auto_v118.dta")
    windows <- list(
        zero = list(skip = 0, n_max = 0),
        unlimited = list(skip = 2, n_max = NA),
        out_of_range = list(skip = 1000, n_max = 10)
    )
    for (name in names(windows)) {
        arguments <- c(
            list(path, col_select = character()), windows[[name]]
        )
        actual <- do.call(read_dta, arguments)
        rust_vectors <- do.call(
            dtaparser:::.read_dta_rust_vectors, arguments
        )
        expected_rows <- do.call(
            haven::read_dta, c(list(path), windows[[name]])
        )
        expect_identical(actual, rust_vectors, info = name)
        expect_identical(nrow(actual), nrow(expected_rows), info = name)
        expect_identical(ncol(actual), 0L, info = name)
    }
})

test_that("typed predicates and duplicate selections are deterministic", {
    path <- fixture("auto_v118.dta")

    strings <- read_dta(path, col_select = where(is.character), n_max = 2)
    expect_identical(names(strings), "make")
    expect_type(strings$make, "character")

    numerics <- read_dta(path, col_select = where(is.numeric), n_max = 2)
    expect_identical(names(numerics), setdiff(
        names(read_dta(path, n_max = 0)), "make"
    ))
    expect_true(all(vapply(numerics, is.numeric, logical(1))))

    duplicated <- read_dta(
        path,
        col_select = c(first_price = price, price, make),
        n_max = 2
    )
    expect_identical(names(duplicated), c("first_price", "make"))
    expect_equal(duplicated$first_price, read_dta(path, n_max = 2)$price)
})

test_that("native materialization survives forced garbage collection", {
    path <- normalizePath(fixture("auto_v118.dta"))
    gctorture(TRUE)
    on.exit(gctorture(FALSE), add = TRUE)

    result <- read_dta(path, col_select = c(make, price), n_max = 1)
    expect_identical(dim(result), c(1L, 2L))
    expect_identical(result$make[[1L]], "AMC Concord")
    expect_true(dtaparser:::.is_numeric_altrep(result$price))
    expect_identical(result$price[[1L]], 4099)
})

test_that("native strings serialize and preserve copy-on-modify semantics", {
    path <- normalizePath(fixture("auto_v118.dta"))
    reference <- dtaparser:::.read_dta_rust_vectors(path)

    encoded <- serialize(read_dta(path), NULL)
    invisible(gc())
    expect_identical(unserialize(encoded), reference)

    original <- read_dta(path)
    modified <- original
    modified$make[[1L]] <- "replacement"
    expect_identical(original$make[[1L]], reference$make[[1L]])
    expect_identical(modified$make[[1L]], "replacement")

    with_missing <- read_dta(path)$make
    expect_false(anyNA(with_missing))
    with_missing[[1L]] <- NA_character_
    expect_true(anyNA(with_missing))
    expect_identical(with_missing[[1L]], NA_character_)

    retained <- read_dta(path)$make
    invisible(gc())
    expect_identical(retained[[2L]], reference$make[[2L]])
})

test_that("native numerics use width-aware storage with R value semantics", {
    skip_if_not_installed("haven")
    path <- normalizePath(fixture("auto_v118.dta"))
    reference <- dtaparser:::.read_dta_rust_vectors(path)
    actual <- read_dta(path)

    numeric_columns <- vapply(reference, is.numeric, logical(1))
    expect_true(all(vapply(
        actual[numeric_columns], dtaparser:::.is_numeric_altrep, logical(1)
    )))
    expect_false(dtaparser:::.is_numeric_altrep(actual$make))

    encoded <- serialize(actual$price, NULL)
    invisible(gc())
    expect_identical(unserialize(encoded), reference$price)

    original <- actual$price
    modified <- original
    modified[[1L]] <- NA_real_
    expect_identical(original[[1L]], reference$price[[1L]])
    expect_false(anyNA(original))
    expect_true(anyNA(modified))
    expect_identical(modified[[1L]], NA_real_)

    retained <- read_dta(path)$price
    invisible(gc())
    expect_identical(retained[[2L]], reference$price[[2L]])

    empty <- read_dta(path, col_select = price, n_max = 0)$price
    expect_true(dtaparser:::.is_numeric_altrep(empty))
    expect_length(empty, 0L)
    expect_false(anyNA(empty))
    expect_warning(
        expect_identical(min(empty), Inf),
        "no non-missing arguments to min"
    )
    expect_warning(
        expect_identical(max(empty), -Inf),
        "no non-missing arguments to max"
    )

    fixture_names <- c(
        "all_types_v115.dta", "all_types_v118.dta",
        "missing_values_v115.dta", "missing_values_v118.dta"
    )
    paths <- vapply(fixture_names, function(name) {
        if (startsWith(name, "missing_values_")) {
            fixture_with_all_numeric_missing_codes(name)
        } else {
            fixture(name)
        }
    }, character(1))
    on.exit(
        unlink(paths[startsWith(fixture_names, "missing_values_")]),
        add = TRUE
    )
    for (case in seq_along(paths)) {
        name <- fixture_names[[case]]
        path <- normalizePath(paths[[case]])
        actual <- read_dta(path)
        eager <- read_dta(path, use_numeric_altrep = FALSE)
        reference <- dtaparser:::.read_dta_rust_vectors(path)
        expect_identical(eager, reference, info = paste(name, "eager"))
        storage <- attr(dtaparser:::.dta_metadata(path), "dta_storage")
        numeric_indices <- which(storage != "character")
        if (startsWith(name, "missing_values_")) {
            expected_tags <- c(NA_character_, letters)
            for (index in numeric_indices) {
                expect_identical(
                    haven::na_tag(reference[[index]][seq_along(expected_tags)]),
                    expected_tags,
                    info = paste(name, storage[[index]], "missing codes")
                )
                expect_identical(
                    haven::na_tag(actual[[index]][seq_along(expected_tags)]),
                    expected_tags,
                    info = paste(
                        name, storage[[index]], "native missing codes"
                    )
                )
                expect_identical(
                    haven::na_tag(eager[[index]][seq_along(expected_tags)]),
                    expected_tags,
                    info = paste(
                        name, storage[[index]], "eager missing codes"
                    )
                )
            }
            for (code in seq_along(expected_tags)) {
                tagged <- read_dta(path, skip = code - 1L, n_max = 1L)
                tagged_eager <- read_dta(
                    path,
                    skip = code - 1L,
                    n_max = 1L,
                    use_numeric_altrep = FALSE
                )
                for (index in numeric_indices) {
                    for (summary_name in c("min", "max")) {
                        summary_function <- match.fun(summary_name)
                        actual_tag <- haven::na_tag(summary_function(
                            unclass(tagged[[index]])
                        ))
                        eager_tag <- haven::na_tag(summary_function(
                            unclass(tagged_eager[[index]])
                        ))
                        expect_identical(
                            actual_tag,
                            expected_tags[[code]],
                            info = paste(
                                name, storage[[index]], summary_name,
                                "single missing code", code - 1L
                            )
                        )
                        expect_identical(
                            actual_tag,
                            eager_tag,
                            info = paste(
                                name, storage[[index]], summary_name,
                                "eager missing code", code - 1L
                            )
                        )
                    }
                }
            }
        }
        altrep_indices <- which(storage %in% c("byte", "int", "long", "float"))
        eager_indices <- which(storage == "double")
        expect_true(all(vapply(
            actual[altrep_indices],
            dtaparser:::.is_numeric_altrep,
            logical(1)
        )), info = name)
        expect_false(any(vapply(
            actual[eager_indices],
            dtaparser:::.is_numeric_altrep,
            logical(1)
        )), info = name)
        expect_false(any(vapply(
            eager[numeric_indices],
            dtaparser:::.is_numeric_altrep,
            logical(1)
        )), info = paste(name, "eager"))
        if (startsWith(name, "missing_values_")) {
            missing_only <- read_dta(path, n_max = 27)
            for (index in altrep_indices) {
                expect_warning(
                    expect_identical(
                        min(unclass(missing_only[[index]]), na.rm = TRUE),
                        Inf
                    ),
                    "no non-missing arguments to min"
                )
                expect_warning(
                    expect_identical(
                        max(unclass(missing_only[[index]]), na.rm = TRUE),
                        -Inf
                    ),
                    "no non-missing arguments to max"
                )
            }
        }
        for (index in numeric_indices) {
            actual_column <- unclass(actual[[index]])
            reference_column <- unclass(reference[[index]])
            expect_identical(
                dtaparser:::.is_numeric_altrep(actual_column),
                storage[[index]] != "double"
            )
            for (na_rm in c(FALSE, TRUE)) {
                expect_identical(
                    sum(actual_column, na.rm = na_rm),
                    sum(reference_column, na.rm = na_rm),
                    info = paste(name, storage[[index]], "sum", na_rm)
                )
                for (summary_name in c("min", "max")) {
                    summary_function <- match.fun(summary_name)
                    expect_identical(
                        summary_function(actual_column, na.rm = na_rm),
                        summary_function(reference_column, na.rm = na_rm),
                        info = paste(
                            name, storage[[index]], summary_name, na_rm
                        )
                    )
                }
            }
            expect_identical(actual[[index]][], reference[[index]][],
                             info = paste(name, storage[[index]]))
            expect_identical(anyNA(actual[[index]]),
                             anyNA(reference[[index]]),
                             info = paste(name, storage[[index]], "missing"))
        }
    }
})

test_that("repeated string patterns can diverge without changing values", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    values <- c("alpha", "beta", "alpha", "beta", "alpha", "gamma",
                "alpha", "beta", rep(c("delta", "epsilon", "zeta"), 8L))
    haven::write_dta(data.frame(value = values), path, version = 15)

    actual <- read_dta(path)
    expect_identical(as.vector(actual$value), values)
    expect_identical(actual, dtaparser:::.read_dta_rust_vectors(path))
})

test_that("wide materialization uses bounded native protection", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    column_count <- 5500L
    input <- as.data.frame(
        stats::setNames(rep.int(list(1), column_count),
                        sprintf("v%05d", seq_len(column_count))),
        check.names = FALSE
    )
    haven::write_dta(input, path, version = 15)

    result <- read_dta(path)
    expect_identical(dim(result), c(1L, column_count))
    expect_identical(as.double(result[[column_count]]), 1)
})

test_that("date and datetime storage become native R temporal vectors", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    input <- data.frame(
        date = as.Date(c("1960-01-01", "2024-02-29")),
        instant = as.POSIXct(c("1960-01-01 00:00:00", "2024-02-29 12:34:56"),
                            tz = "UTC")
    )
    haven::write_dta(input, path, version = 15)

    actual <- read_dta(path)
    eager <- read_dta(path, use_numeric_altrep = FALSE)
    expected <- haven::read_dta(path)
    expect_equal(actual$date, expected$date)
    expect_s3_class(actual$date, "Date")
    expect_equal(actual$instant, expected$instant)
    expect_s3_class(actual$instant, "POSIXct")
    expect_identical(attr(actual$instant, "tzone"), "UTC")
    expect_identical(eager, actual)
    expect_false(any(vapply(
        eager, dtaparser:::.is_numeric_altrep, logical(1)
    )))
})

test_that("legacy and custom daily-date formats match haven", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    formats <- c(
        daily_td = "%td",
        daily_d = "%d",
        daily_custom = "%dCY-N-D",
        daily_unusual = "%dollars",
        daily_other = "%dfoo",
        datetime_tc = "%tc",
        datetime_tC = "%tC",
        near_uppercase_d = "%D",
        near_width_d = "%9d",
        weekly = "%tw",
        monthly = "%tm",
        quarterly = "%tq",
        halfyear = "%th",
        yearly = "%ty",
        incomplete_temporal = "%t",
        bare_d = "d"
    )
    values <- c(0, 3653, haven::tagged_na("a"), NA_real_)
    input <- as.data.frame(lapply(formats, function(format) {
        column <- values
        attr(column, "format.stata") <- format
        column
    }), check.names = FALSE)
    haven::write_dta(input, path, version = 15)

    actual <- read_dta(path)
    rust_vectors <- dtaparser:::.read_dta_rust_vectors(path)
    expected <- haven::read_dta(path)

    expect_identical(actual, rust_vectors)
    for (name in names(formats)) {
        expect_identical(actual[[name]], expected[[name]], info = name)
        expect_identical(attr(actual[[name]], "format.stata"), formats[[name]],
                         info = name)
        expect_identical(haven::na_tag(actual[[name]]),
                         haven::na_tag(expected[[name]]), info = name)
    }

    date_names <- names(formats)[startsWith(formats, "%d") |
                                 startsWith(formats, "%td")]
    datetime_names <- names(formats)[startsWith(formats, "%tc") |
                                     startsWith(formats, "%tC")]
    numeric_names <- setdiff(names(formats), c(date_names, datetime_names))
    expect_true(all(vapply(actual[date_names], inherits, logical(1), "Date")))
    expect_true(all(vapply(actual[datetime_names], inherits, logical(1),
                           "POSIXct")))
    expect_true(all(vapply(actual[datetime_names], function(column) {
        identical(attr(column, "tzone"), "UTC")
    }, logical(1))))
    expect_true(all(vapply(actual[numeric_names], function(column) {
        identical(class(column), "numeric")
    }, logical(1))))

    selected_names <- c("daily_custom", "datetime_tC", "near_uppercase_d")
    selected <- read_dta(
        path,
        col_select = all_of(selected_names),
        skip = 1,
        n_max = 2
    )
    selected_rust_vectors <- dtaparser:::.read_dta_rust_vectors(
        path,
        col_select = all_of(selected_names),
        skip = 1,
        n_max = 2
    )
    selected_expected <- haven::read_dta(
        path,
        col_select = all_of(selected_names),
        skip = 1,
        n_max = 2
    )
    expect_identical(selected, selected_rust_vectors)
    expect_identical(selected, selected_expected)
})

test_that("explicit encodings match haven across ordinary textual surfaces", {
    skip_if_not_installed("haven")
    for (version in c(115L, 118L)) local({
        source <- fixture(sprintf("auto_v%d.dta", version))
        bytes <- readBin(source, "raw", file.info(source)$size)
        for (text in c(
            "1978 automobile data", "Make and model", "AMC Concord", "Domestic"
        )) {
            bytes <- replace_first_byte(bytes, text, 0x80)
        }
        path <- tempfile(fileext = ".dta")
        on.exit(unlink(path), add = TRUE)
        writeBin(bytes, path)

        for (encoding in c("Windows-1252", "ISO-8859-1")) {
            actual <- read_dta(path, encoding = encoding)
            rust_vectors <- dtaparser:::.read_dta_rust_vectors(
                path, encoding = encoding
            )
            expected <- haven::read_dta(path, encoding = encoding)
            info <- paste("release", version, encoding)

            expect_identical(actual, rust_vectors,
                             info = paste(info, "materialization"))
            expect_identical(actual$make, expected$make,
                             info = paste(info, "fixed string"))
            expect_identical(attr(actual, "label"), attr(expected, "label"),
                             info = paste(info, "dataset label"))
            expect_identical(attr(actual$make, "label"),
                             attr(expected$make, "label"),
                             info = paste(info, "variable label"))
            expect_identical(attr(actual$foreign, "labels"),
                             attr(expected$foreign, "labels"),
                             info = paste(info, "value labels"))
        }
    })

    modern <- fixture("auto_v118.dta")
    expect_identical(read_dta(modern, encoding = "utf_8"),
                     read_dta(modern, encoding = "UTF8"))
    expect_identical(read_dta(modern, encoding = "UTF-8")$make,
                     haven::read_dta(modern, encoding = "UTF-8")$make)

    note_bytes <- readBin(modern, "raw", file.info(modern)$size)
    note_bytes <- replace_first_byte(
        note_bytes, "From Consumer Reports with permission", 0x80
    )
    cp1252 <- read_dta(note_bytes, encoding = "Windows-1252")
    latin1 <- read_dta(note_bytes, encoding = "ISO-8859-1")
    expect_identical(cp1252, dtaparser:::.read_dta_rust_vectors(
        note_bytes, encoding = "CP1252"
    ))
    expect_identical(latin1, dtaparser:::.read_dta_rust_vectors(
        note_bytes, encoding = "latin1"
    ))
    expect_true(startsWith(attr(cp1252, "notes")[[1L]], "\u20ac"))
    expect_true(startsWith(attr(latin1, "notes")[[1L]], "\u0080"))
})

test_that("explicit encodings apply consistently to strL text", {
    source <- fixture("strl_test_v118.dta")
    bytes <- readBin(source, "raw", file.info(source)$size)
    bytes <- replace_first_byte(bytes, "This is observation 1", 0x80)
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    writeBin(bytes, path)

    cp1252 <- read_dta(path, encoding = "CP1252")
    latin1 <- read_dta(path, encoding = "latin-1")
    expect_identical(cp1252, dtaparser:::.read_dta_rust_vectors(
        path, encoding = "windows_1252"
    ))
    expect_identical(latin1, dtaparser:::.read_dta_rust_vectors(
        path, encoding = "ISO 8859 1"
    ))
    expect_true(startsWith(cp1252$long_text[[1L]], "\u20ac"))
    expect_true(startsWith(latin1$long_text[[1L]], "\u0080"))
})

test_that("explicit UTF-8 replaces malformed sequences in both collectors", {
    source <- fixture("auto_v118.dta")
    bytes <- readBin(source, "raw", file.info(source)$size)
    bytes <- replace_first_byte(bytes, "1978 automobile data", 0xff)
    bytes <- replace_first_byte(bytes, "AMC Concord", 0xff)
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    writeBin(bytes, path)

    direct <- read_dta(path, encoding = "UTF-8")
    rust_vectors <- dtaparser:::.read_dta_rust_vectors(
        path, encoding = "UTF8"
    )
    expect_identical(direct, rust_vectors)
    expect_true(startsWith(attr(direct, "label"), "\ufffd"))
    expect_true(startsWith(direct$make[[1L]], "\ufffd"))
})

test_that("argument and native parse failures are ordinary R errors", {
    path <- fixture("auto_v118.dta")
    expect_error(read_dta(path, encoding = "KOI8-R"), "unsupported.*encoding")
    expect_error(read_dta(path, encoding = NA_character_), "non-missing")
    expect_error(read_dta(path, encoding = character()), "one non-missing")
    expect_error(read_dta(path, encoding = c("UTF-8", "latin1")),
                 "one non-missing")
    expect_error(read_dta(path, encoding = 1), "one non-missing")
    for (threads in list(-1, 1.5, NA_real_, Inf, c(1, 2), "2")) {
        expect_error(read_dta(path, threads = threads), "threads.*non-negative")
    }
    for (use_numeric_altrep in list(
        NULL, NA, logical(), c(TRUE, FALSE), 1, "TRUE"
    )) {
        expect_error(
            read_dta(path, use_numeric_altrep = use_numeric_altrep),
            "use_numeric_altrep.*non-missing logical"
        )
    }
    expect_error(read_dta(path, col_select = absent), "absent")

    corrupt <- tempfile(fileext = ".dta")
    on.exit(unlink(corrupt), add = TRUE)
    writeBin(as.raw(1:8), corrupt)
    expect_error(read_dta(corrupt), "header|format|small|read|I/O", ignore.case = TRUE)
    expect_error(dtaparser:::.read_dta_rust_vectors(corrupt),
                 "header|format|small|read|I/O", ignore.case = TRUE)
})

test_that("unsafe row-window coercions fail before parsing", {
    missing_path <- tempfile(fileext = ".dta")
    invalid <- list(
        list(arguments = list(skip = -1), error = "non-negative whole"),
        list(arguments = list(skip = NA_real_), error = "non-negative whole"),
        list(arguments = list(skip = NaN), error = "non-negative whole"),
        list(arguments = list(skip = Inf), error = "non-negative whole"),
        list(arguments = list(skip = -Inf), error = "non-negative whole"),
        list(arguments = list(skip = 1.5), error = "non-negative whole"),
        list(arguments = list(skip = 2^53 + 2), error = "no larger than"),
        list(arguments = list(skip = c(1, 2)), error = "length 1"),
        list(arguments = list(skip = TRUE), error = "integer or double"),
        list(arguments = list(skip = "1"), error = "integer or double"),
        list(arguments = list(n_max = 1.5), error = "whole number"),
        list(arguments = list(n_max = NaN), error = "must not be NaN"),
        list(arguments = list(n_max = 2^53 + 2), error = "no larger than"),
        list(arguments = list(n_max = c(1, 2)), error = "length 1"),
        list(arguments = list(n_max = TRUE), error = "integer or double"),
        list(arguments = list(n_max = NA_character_), error = "integer or double")
    )
    readers <- list(read_dta, dtaparser:::.read_dta_rust_vectors)

    for (reader in readers) {
        for (case in invalid) {
            expect_error(
                do.call(reader, c(list(missing_path), case$arguments)),
                case$error
            )
        }
    }
})

test_that("deliberate row-window divergences from haven are stable", {
    skip_if_not_installed("haven")
    path <- fixture("auto_v118.dta")

    expect_identical(nrow(haven::read_dta(path, n_max = 2.9)), 2L)
    expect_error(read_dta(path, n_max = 2.9), "whole number")
    expect_identical(nrow(haven::read_dta(path, n_max = NaN)), 74L)
    expect_error(read_dta(path, n_max = NaN), "must not be NaN")

    expect_identical(nrow(haven::read_dta(path, skip = -1, n_max = 2)), 2L)
    expect_error(read_dta(path, skip = -1, n_max = 2), "non-negative whole")
    expect_identical(nrow(haven::read_dta(path, skip = NA, n_max = 2)), 2L)
    expect_error(read_dta(path, skip = NA, n_max = 2), "integer or double")
    expect_s3_class(haven::read_dta(path, skip = Inf, n_max = 2), "tbl_df")
    expect_error(read_dta(path, skip = Inf, n_max = 2), "non-negative whole")
    expect_error(haven::read_dta(path, skip = 2.9, n_max = 2),
                 "single integer")
    expect_error(read_dta(path, skip = 2.9, n_max = 2),
                 "non-negative whole")
})
