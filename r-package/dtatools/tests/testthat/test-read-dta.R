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
        quote(getOption("dtatools.threads", 0L))
    )
    expect_identical(
        formals(read_dta)$use_numeric_altrep,
        quote(getOption("dtatools.numeric_altrep", TRUE))
    )
    expect_identical(nrow(read_dta(fixture("auto_v118.dta"), n = 2)), 2L)
})

test_that("numeric ALTREP can be disabled explicitly or by option", {
    path <- fixture("all_types_v118.dta")
    reference <- dtatools:::.read_dta_rust_vectors(path)
    explicit <- read_dta(path, use_numeric_altrep = FALSE, threads = 1L)
    parallel <- read_dta(path, use_numeric_altrep = FALSE, threads = 4L)

    expect_identical(explicit, reference)
    expect_identical(parallel, explicit)
    numeric_columns <- vapply(explicit, is.numeric, logical(1))
    expect_false(any(vapply(
        explicit[numeric_columns],
        dtatools:::.is_numeric_altrep,
        logical(1)
    )))

    previous <- options(dtatools.numeric_altrep = FALSE)
    on.exit(options(previous), add = TRUE)
    from_option <- read_dta(path)
    expect_identical(from_option, explicit)
    expect_false(any(vapply(
        from_option[numeric_columns],
        dtatools:::.is_numeric_altrep,
        logical(1)
    )))

    empty <- read_dta(
        path,
        col_select = c(v_byte, v_double),
        n_max = 0,
        use_numeric_altrep = FALSE
    )
    expect_identical(empty, dtatools:::.read_dta_rust_vectors(
        path, col_select = c(v_byte, v_double), n_max = 0
    ))
    expect_false(any(vapply(
        empty, dtatools:::.is_numeric_altrep, logical(1)
    )))
})

test_that("dtatools recognizes every Stata numeric missing code", {
    expected_tags <- c(NA_character_, letters)
    expected_tagged <- c(FALSE, rep(TRUE, 26L))
    expected_system <- c(TRUE, rep(FALSE, 26L))

    paths <- character()
    on.exit(unlink(paths), add = TRUE)
    for (name in c("missing_values_v115.dta", "missing_values_v118.dta")) {
        path <- fixture_with_all_numeric_missing_codes(name)
        paths <- c(paths, path)
        storage <- attr(dtatools:::.dta_metadata(path), "dta_storage")
        numeric_indices <- which(storage != "character")

        for (use_numeric_altrep in c(TRUE, FALSE)) {
            actual <- read_dta(
                path,
                n_max = 27,
                use_numeric_altrep = use_numeric_altrep
            )
            mode <- if (use_numeric_altrep) "default" else "eager"
            for (index in numeric_indices) {
                values <- actual[[index]]
                info <- paste(name, storage[[index]], mode)

                expect_identical(
                    dtatools:::.is_numeric_altrep(values),
                    use_numeric_altrep && storage[[index]] != "double",
                    info = paste(info, "representation")
                )
                expect_true(all(is.na(values)), info = paste(info, "is.na"))
                expect_identical(
                    missing_tag(values),
                    expected_tags,
                    info = paste(info, "na_tag")
                )
                expect_identical(
                    is_tagged_missing(values),
                    expected_tagged,
                    info = paste(info, "is_tagged_na")
                )
                expect_identical(
                    is.na(values) & !is.nan(values) &
                        !is_tagged_missing(values),
                    expected_system,
                    info = paste(info, "system missing")
                )
                for (tag in letters) {
                    expected_match <- seq_along(expected_tags) ==
                        match(tag, letters) + 1L
                    expect_identical(
                        is_tagged_missing(values, tag),
                        expected_match,
                        info = paste(info, "tag", tag)
                    )
                }
            }
        }
    }
})

test_that("base R recoding preserves tags with complete predicates", {
    expected_tags <- c(NA_character_, letters)

    paths <- character()
    on.exit(unlink(paths), add = TRUE)
    for (name in c("missing_values_v115.dta", "missing_values_v118.dta")) {
        path <- fixture_with_all_numeric_missing_codes(name)
        paths <- c(paths, path)
        storage <- attr(dtatools:::.dta_metadata(path), "dta_storage")

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
                    missing_tag(assigned[seq_len(27L)]),
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
                    missing_tag(replaced[seq_len(27L)]),
                    expected_tags,
                    info = paste(info, "replace tags")
                )
                expect_identical(
                    attributes(replaced),
                    attributes(original),
                    info = paste(info, "replace attributes")
                )

                tag_assigned <- original
                tag_assigned[is_tagged_missing(tag_assigned, "a")] <- -2
                remaining_tags <- expected_tags
                remaining_tags[[2L]] <- NA_character_
                expect_identical(
                    missing_tag(tag_assigned[seq_len(27L)]),
                    remaining_tags,
                    info = paste(info, "tag-specific assignment")
                )

                safe_ifelse <- ifelse(selected, -1, original)
                expect_identical(
                    missing_tag(safe_ifelse[seq_len(27L)]),
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
                    missing_tag(unsafe_ifelse[seq_len(27L)]),
                    rep(NA_character_, 27L),
                    info = paste(info, "incomplete ifelse predicate")
                )
            }
        }
    }
})

test_that("both recode interfaces preserve every Stata missing code", {
    expected_tags <- c(NA_character_, letters)
    interfaces <- list(
        dtatools = dtatools::recode,
        dplyr = dplyr::recode
    )

    paths <- character()
    on.exit(unlink(paths), add = TRUE)
    for (name in c("missing_values_v115.dta", "missing_values_v118.dta")) {
        path <- fixture_with_all_numeric_missing_codes(name)
        paths <- c(paths, path)
        storage <- attr(dtatools:::.dta_metadata(path), "dta_storage")

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
                        missing_tag(recoded[seq_len(27L)]),
                        expected_tags,
                        info = paste(info, "tags")
                    )
                    expect_identical(
                        attributes(recoded),
                        attributes(original),
                        info = paste(info, "attributes")
                    )
                expect_identical(
                    unname(as.double(recoded[[28L]])),
                        -1,
                        info = paste(info, "observed replacement")
                    )
                    expect_false(
                        dtatools:::.is_numeric_altrep(recoded),
                        info = paste(info, "materialized result")
                    )

                    replaced_missing <- rlang::exec(
                        recode_function,
                        original,
                        !!!replacement,
                        .missing = -99
                    )
                expect_identical(
                    unname(as.double(replaced_missing[seq_len(27L)])),
                        rep(-99, 27L),
                        info = paste(info, "explicit missing replacement")
                    )
                    expect_false(
                        any(is_tagged_missing(replaced_missing)),
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
                    missing_tag(mutated[[index]][seq_len(27L)]),
                    expected_tags,
                    info = paste(info, "tags")
                )
                expect_identical(
                    attributes(mutated[[index]]),
                    attributes(actual[[index]]),
                    info = paste(info, "attributes")
                )
                expect_identical(
                    unname(as.double(mutated[[index]][[28L]])),
                    -1,
                    info = paste(info, "observed replacement")
                )
            }
        }
    }
})

test_that("dplyr recode keeps its ordinary numeric behavior", {
    cases <- list(
        list(
            source = c(1, 2, 3), replacements = list(10, 20),
            default = NULL, missing = NULL,
            expected = c(10, 20, 3)
        ),
        list(
            source = c(1, 2, 3),
            replacements = stats::setNames(list(10), "1"),
            default = -1, missing = NULL,
            expected = c(10, -1, -1)
        ),
        list(
            source = c(1, NA_real_, 2),
            replacements = stats::setNames(list(10), "1"),
            default = NULL, missing = -99,
            expected = c(10, -99, 2)
        ),
        list(
            source = c(1L, 2L, NA_integer_),
            replacements = stats::setNames(list(10L), "1"),
            default = NULL, missing = NULL,
            expected = c(10L, 2L, NA_integer_)
        ),
        list(
            source = c(1L, 2L, NA_integer_),
            replacements = stats::setNames(list(10), "1"),
            default = NULL, missing = NULL,
            expected = c(10, NA_real_, NA_real_),
            expected_warning = "Unreplaced values treated as NA"
        ),
        list(
            source = c(1, 2),
            replacements = stats::setNames(
                list("one", "two"), c("1", "2")
            ),
            default = "other", missing = "missing",
            expected = c("one", "two")
        ),
        list(
            source = c(1, NA_real_),
            replacements = stats::setNames(list("one"), "1"),
            default = "other", missing = NULL,
            expected = c("one", NA_character_)
        ),
        list(
            source = c(1, NaN, 2),
            replacements = stats::setNames(list(10), "1"),
            default = NULL, missing = NULL,
            expected = c(10, NA_real_, 2)
        ),
        list(
            source = structure(c(1, 2), label = "ordinary numeric"),
            replacements = stats::setNames(list(10), "1"),
            default = NULL, missing = NULL,
            expected = c(10, 2)
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
        expected_warning <- cases[[index]]$expected_warning
        if (!is.null(expected_warning)) {
            expect_warning(
                actual <- call_recode(dplyr::recode, cases[[index]]),
                expected_warning
            )
        } else {
            actual <- call_recode(dplyr::recode, cases[[index]])
        }
        expect_identical(
            actual,
            cases[[index]]$expected,
            info = paste("ordinary numeric case", index)
        )
    }
})

test_that("tag detection distinguishes R missing payloads", {
    untagged <- c(
        1, NA_real_, NA_real_ + 0, -NA_real_, -(NA_real_ + 0), NaN, -NaN
    )
    expect_false(dtatools:::.has_tagged_na(untagged))
    expect_true(dtatools:::.has_tagged_na(tagged_missing("a")))
    expect_true(dtatools:::.has_tagged_na(tagged_missing("z")))
    expect_false(dtatools:::.has_tagged_na(c(1L, NA_integer_)))

    expected_tags <- c(NA_character_, letters)
    canonical <- c(NA_real_, tagged_missing(letters))
    variants <- list(
        canonical = canonical,
        quiet = canonical + 0,
        signed = -canonical,
        signed_quiet = -(canonical + 0)
    )
    for (name in names(variants)) {
        values <- variants[[name]]
        expect_identical(
            missing_tag(values), expected_tags,
            info = paste(name, "recognized by missing_tag")
        )
        expect_true(
            dtatools:::.has_tagged_na(values),
            info = paste(name, "detected by dtatools")
        )
        recoded <- dplyr::recode(c(values, 1), `1` = 10)
        expect_identical(
            missing_tag(recoded[seq_along(values)]), expected_tags,
            info = paste(name, "preserved by dplyr recode")
        )
    }

    created <- 1:3
    created[[2L]] <- tagged_missing("f")
    expect_type(created, "double")
    expect_identical(
        missing_tag(dplyr::recode(created, `1` = 10)),
        c(NA_character_, "f", NA_character_)
    )
})

test_that("dtatools recode retains the familiar vector interface", {
    expect_true("recode" %in% getNamespaceExports("dtatools"))
    expect_identical(
        names(formals(dtatools::recode)),
        c(".x", "...", ".default", ".missing")
    )

    expect_identical(
        dtatools::recode(c(1, 2, 3), 10, 20),
        c(10, 20, 3)
    )
    expect_identical(
        dtatools::recode(c(1L, 2L, NA_integer_), `1` = 10L),
        c(10L, 2L, NA_integer_)
    )
    expect_identical(
        dtatools::recode(c(1L, 2L, NA_integer_), `1` = 10),
        c(10L, 2L, NA_integer_)
    )
    expect_identical(
        dtatools::recode(c(1L, 2L, NA_integer_), `1` = 10.5),
        c(10.5, 2, NA_real_)
    )
    expect_identical(
        dtatools::recode(c("a", "b", NA_character_), a = "A"),
        c("A", "b", NA_character_)
    )
    expect_identical(
        dtatools::recode(factor(c("a", "b", NA_character_)), a = "A"),
        factor(c("A", "b", NA_character_))
    )
    expect_error(
        dtatools::recode(
            factor(c("a", NA_character_)), a = "A", .missing = "missing"
        ),
        "not supported for factors"
    )
    expect_error(
        dtatools::recode(c(1, 2), first = 10, 20),
        "Either all values must be named"
    )
    expect_error(
        dtatools::recode(
            c(1, 2), `1` = as.Date("2020-01-01"),
            `2` = as.Date("2020-01-02")
        ),
        "Class-changing numeric replacements"
    )
    expect_error(
        dtatools::recode(c(1, 2), `1` = factor("one")),
        "Class-changing numeric replacements"
    )

    missing_values <- c(
        NaN, NA_real_, tagged_missing("a"), tagged_missing("z")
    )
    preserved <- dtatools::recode(
        c(1, missing_values), `1` = 10
    )[-1L]
    expect_identical(preserved, missing_values)

    retagged <- dtatools::recode(
        missing_values,
        .default = missing_values,
        .missing = tagged_missing("f")
    )
    expect_identical(
        missing_tag(retagged),
        rep("f", length(missing_values))
    )

    integer_labelled <- labelled_for_test(
        c(1L, 2L, NA_integer_), labels = c(one = 1L, two = 2L)
    )
    integer_result <- dtatools::recode(integer_labelled, `1` = 10)
    expect_s3_class(integer_result, "haven_labelled")
    expect_identical(
        vctrs::vec_data(integer_result), c(10L, 2L, NA_integer_)
    )
    expect_identical(attr(integer_result, "labels"), c(one = 1L, two = 2L))

    widened_result <- dtatools::recode(integer_labelled, `1` = 10.5)
    expect_s3_class(widened_result, "haven_labelled")
    expect_identical(
        vctrs::vec_data(widened_result), c(10.5, 2, NA_real_)
    )
    expect_identical(attr(widened_result, "labels"), c(one = 1, two = 2))

    tagged_integer_result <- dtatools::recode(
        integer_labelled, `1` = 10L, .missing = tagged_missing("f")
    )
    expect_s3_class(tagged_integer_result, "haven_labelled")
    expect_identical(
        missing_tag(vctrs::vec_data(tagged_integer_result)),
        c(NA_character_, NA_character_, "f")
    )
    expect_identical(
        attr(tagged_integer_result, "labels"), c(one = 1, two = 2)
    )

    nan_result <- dtatools::recode(
        c(1L, 2L, NA_integer_), `1` = NaN
    )
    expect_identical(is.nan(nan_result), c(TRUE, FALSE, FALSE))
    expect_identical(is.na(nan_result), c(TRUE, FALSE, TRUE))

    tagged_date <- structure(
        c(1, tagged_missing("a")),
        class = "Date",
        format.stata = "%td"
    )
    recoded_date <- dtatools::recode(tagged_date, `1` = 10L)
    expect_s3_class(recoded_date, "Date")
    expect_identical(attr(recoded_date, "format.stata"), "%td")
    expect_identical(missing_tag(unclass(recoded_date)), c(NA, "a"))

    same_class_date <- dtatools::recode(
        tagged_date, `1` = as.Date("1970-01-11")
    )
    expect_s3_class(same_class_date, "Date")
    expect_identical(unclass(same_class_date)[[1L]], 10)
    expect_identical(
        missing_tag(unclass(same_class_date)), c(NA, "a")
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
    full <- dtatools:::.dta_metadata(path)
    middle <- dtatools:::.dta_metadata(path, column_start = 3L, column_count = 2L)
    suffix <- dtatools:::.dta_metadata(path, column_start = 7L)
    empty <- dtatools:::.dta_metadata(path, column_start = 2L, column_count = 0L)
    past <- dtatools:::.dta_metadata(path, column_start = 100L, column_count = 2L)

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
        expect_error(dtatools:::.dta_metadata(path, column_start = value))
        expect_error(dtatools:::.dta_metadata(path, column_count = value))
    }
})




test_that("an empty projection retains the selected row count", {
    path <- fixture("auto_v118.dta")
    result <- read_dta(path, col_select = character(), skip = 2, n_max = 3)
    rust_vectors <- dtatools:::.read_dta_rust_vectors(
        path, col_select = character(), skip = 2, n_max = 3
    )
    expect_identical(result, rust_vectors)
    expect_identical(dim(result), c(3L, 0L))
})


test_that("the largest exact skip is deterministic in both collectors", {
    path <- fixture("auto_v118.dta")
    actual <- read_dta(
        path, col_select = c("make", "price"), skip = 2^53, n_max = 3
    )
    rust_vectors <- dtatools:::.read_dta_rust_vectors(
        path, col_select = c("make", "price"), skip = 2^53, n_max = 3
    )

    expect_identical(actual, rust_vectors)
    expect_identical(dim(actual), c(0L, 2L))
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
    expect_true(dtatools:::.is_numeric_altrep(result$price))
    expect_identical(as.double(result$price[[1L]]), 4099)
})

test_that("native strings serialize and preserve copy-on-modify semantics", {
    path <- normalizePath(fixture("auto_v118.dta"))
    reference <- dtatools:::.read_dta_rust_vectors(path)

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
    path <- normalizePath(fixture("auto_v118.dta"))
    reference <- dtatools:::.read_dta_rust_vectors(path)
    actual <- read_dta(path)

    numeric_columns <- vapply(reference, is.numeric, logical(1))
    expect_true(all(vapply(
        actual[numeric_columns], dtatools:::.is_numeric_altrep, logical(1)
    )))
    expect_false(dtatools:::.is_numeric_altrep(actual$make))

    encoded <- serialize(actual$price, NULL)
    invisible(gc())
    expect_identical(unserialize(encoded), reference$price)

    original <- actual$price
    modified <- original
    modified[[1L]] <- NA_real_
    expect_identical(original[[1L]], reference$price[[1L]])
    expect_false(anyNA(original))
    expect_true(anyNA(modified))
    expect_identical(as.double(modified[[1L]]), NA_real_)

    retained <- read_dta(path)$price
    invisible(gc())
    expect_identical(retained[[2L]], reference$price[[2L]])

    empty <- read_dta(path, col_select = price, n_max = 0)$price
    expect_true(dtatools:::.is_numeric_altrep(empty))
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
        reference <- dtatools:::.read_dta_rust_vectors(path)
        expect_identical(eager, reference, info = paste(name, "eager"))
        storage <- attr(dtatools:::.dta_metadata(path), "dta_storage")
        numeric_indices <- which(storage != "character")
        if (startsWith(name, "missing_values_")) {
            expected_tags <- c(NA_character_, letters)
            for (index in numeric_indices) {
                expect_identical(
                    missing_tag(reference[[index]][seq_along(expected_tags)]),
                    expected_tags,
                    info = paste(name, storage[[index]], "missing codes")
                )
                expect_identical(
                    missing_tag(actual[[index]][seq_along(expected_tags)]),
                    expected_tags,
                    info = paste(
                        name, storage[[index]], "native missing codes"
                    )
                )
                expect_identical(
                    missing_tag(eager[[index]][seq_along(expected_tags)]),
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
                        actual_tag <- missing_tag(summary_function(
                            unclass(tagged[[index]])
                        ))
                        eager_tag <- missing_tag(summary_function(
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
            dtatools:::.is_numeric_altrep,
            logical(1)
        )), info = name)
        expect_false(any(vapply(
            actual[eager_indices],
            dtatools:::.is_numeric_altrep,
            logical(1)
        )), info = name)
        expect_false(any(vapply(
            eager[numeric_indices],
            dtatools:::.is_numeric_altrep,
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
            actual_column <- actual[[index]]
            reference_column <- reference[[index]]
            expect_identical(
                dtatools:::.is_numeric_altrep(actual_column),
                storage[[index]] != "double"
            )
            for (na_rm in c(FALSE, TRUE)) {
                expect_identical(
                    as.double(sum(actual_column, na.rm = na_rm)),
                    as.double(sum(reference_column, na.rm = na_rm)),
                    info = paste(name, storage[[index]], "sum", na_rm)
                )
                for (summary_name in c("min", "max")) {
                    summary_function <- match.fun(summary_name)
                    expect_identical(
                        as.double(summary_function(
                            actual_column, na.rm = na_rm
                        )),
                        as.double(summary_function(
                            reference_column, na.rm = na_rm
                        )),
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






test_that("explicit encodings apply consistently to strL text", {
    source <- fixture("strl_test_v118.dta")
    bytes <- readBin(source, "raw", file.info(source)$size)
    bytes <- replace_first_byte(bytes, "This is observation 1", 0x80)
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    writeBin(bytes, path)

    cp1252 <- read_dta(path, encoding = "CP1252")
    latin1 <- read_dta(path, encoding = "latin-1")
    expect_identical(cp1252, dtatools:::.read_dta_rust_vectors(
        path, encoding = "windows_1252"
    ))
    expect_identical(latin1, dtatools:::.read_dta_rust_vectors(
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
    rust_vectors <- dtatools:::.read_dta_rust_vectors(
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
    expect_error(dtatools:::.read_dta_rust_vectors(corrupt),
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
    readers <- list(read_dta, dtatools:::.read_dta_rust_vectors)

    for (reader in readers) {
        for (case in invalid) {
            expect_error(
                do.call(reader, c(list(missing_path), case$arguments)),
                case$error
            )
        }
    }
})
