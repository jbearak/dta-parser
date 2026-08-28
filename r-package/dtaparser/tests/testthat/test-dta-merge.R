merge_indicator_labels <- c(
    "x only (1)" = 1,
    "y only (2)" = 2,
    "matched (3)" = 3
)

test_that("1:1 merges match keys under Stata missing-code identity", {
    master <- tibble::tibble(
        id = stata_byte(c(1, NA_real_, tagged_missing("a"))),
        master_value = c("m1", "m2", "m3")
    )
    using <- tibble::tibble(
        id = stata_byte(c(tagged_missing("a"), NA_real_, 7)),
        using_value = c("u1", "u2", "u3")
    )

    result <- dta_merge(master, using, by = "id", relationship = "1:1")

    expect_s3_class(result, "tbl_df")
    expect_identical(names(result),
                     c("id", "master_value", "using_value", "_merge"))
    expect_identical(nrow(result), 4L)

    expect_identical(as.double(result$id)[c(1L, 4L)], c(1, 7))
    expect_identical(missing_tag(result$id), c(NA, NA, "a", NA))
    expect_true(is.na(result$id[2]) && !is_tagged_missing(result$id[2]))

    expect_identical(result$master_value, c("m1", "m2", "m3", NA))
    expect_identical(result$using_value, c(NA, "u2", "u1", "u3"))

    expect_identical(stata_storage_type(result$`_merge`), "byte")
    expect_identical(as.double(result$`_merge`), c(1, 3, 3, 2))
    expect_identical(val_labels(result$`_merge`), merge_indicator_labels)
})

test_that("each of the 27 Stata missing codes matches only itself", {
    codes <- c(NA_real_, tagged_missing(letters))
    master <- tibble::tibble(id = stata_double(codes), row = seq_along(codes))
    scramble <- rev(seq_along(codes))
    using <- tibble::tibble(id = stata_double(codes[scramble]),
                            match = scramble)

    result <- dta_merge(master, using, by = "id", relationship = "1:1")

    expect_identical(nrow(result), 27L)
    expect_identical(as.double(result$`_merge`), rep(3, 27L))
    expect_identical(result$match, result$row)

    disjoint <- dta_merge(
        tibble::tibble(id = tagged_missing("a")),
        tibble::tibble(id = tagged_missing("b")),
        by = "id",
        relationship = "1:1"
    )
    expect_identical(as.double(disjoint$`_merge`), c(1, 2))
})

test_that("NaN key values are rejected with a Stata remedy", {
    master <- tibble::tibble(id = c(1, NaN))
    using <- tibble::tibble(id = c(1, 2))

    expect_error(
        dta_merge(master, using, by = "id", relationship = "1:1"),
        "NaN.*tagged_missing"
    )
    expect_error(
        dta_merge(using, master, by = "id", relationship = "1:1"),
        "NaN.*tagged_missing"
    )
})

test_that("key columns coalesce storage and metadata", {
    master <- tibble::tibble(
        id = set_variable_labels(
            set_value_labels(stata_byte(c(1, 2)), One = 1),
            "Identifier"
        ),
        master_value = c("a", "b")
    )
    using <- tibble::tibble(
        id = set_variable_labels(
            set_value_labels(stata_int(c(2, 200)), TwoHundred = 200),
            "Ident (using)"
        ),
        using_value = c("c", "d")
    )

    warnings <- testthat::capture_warnings(
        result <- dta_merge(master, using, by = "id", relationship = "1:1")
    )
    expect_match(
        warnings, "variable labels differ for 1 coalesced variable.*id",
        all = FALSE
    )
    expect_match(
        warnings, "value labels differ for 1 coalesced variable.*id",
        all = FALSE
    )

    expect_identical(as.double(result$id), c(1, 2, 200))
    expect_identical(stata_storage_type(result$id), "int")
    expect_identical(var_label(result$id), "Identifier")
    expect_identical(val_labels(result$id), c(One = 1, TwoHundred = 200))
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(result$id))

    conflicting <- tibble::tibble(
        id = set_value_labels(stata_byte(1), Uno = 1)
    )
    warnings <- testthat::capture_warnings(
        dta_merge(master, conflicting, by = "id", relationship = "1:1")
    )
    expect_match(warnings, "conflicting value labels", all = FALSE)
    expect_match(
        warnings, "value labels differ for 1 coalesced variable",
        all = FALSE
    )
    expect_no_match(warnings, "variable labels differ")
})

test_that("coalesced variables with matching metadata merge silently", {
    master <- tibble::tibble(
        id = set_variable_labels(
            set_value_labels(stata_byte(c(1, 2)), One = 1),
            "Identifier"
        ),
        score = c(10, 20)
    )
    using <- tibble::tibble(
        id = set_variable_labels(
            set_value_labels(stata_int(c(1, 2)), One = 1),
            "Identifier"
        ),
        group = c("a", "b")
    )

    expect_silent(
        dta_merge(master, using, by = "id", relationship = "1:1")
    )

    unlabelled_using <- tibble::tibble(
        id = stata_int(c(1, 2)),
        group = c("a", "b")
    )
    warnings <- testthat::capture_warnings(
        dta_merge(master, unlabelled_using, by = "id",
                    relationship = "1:1")
    )
    expect_no_match(warnings, "variable labels differ")
    expect_match(
        warnings, "value labels differ for 1 coalesced variable",
        all = FALSE
    )
})

test_that("overlapping non-key variables follow the master-wins rule", {
    master <- tibble::tibble(
        id = c(1, 2),
        score = stata_byte(c(10, NA_real_))
    )
    using <- tibble::tibble(
        id = c(2, 3),
        score = stata_int(c(99, 300))
    )

    expect_warning(
        result <- dta_merge(master, using, by = "id", relationship = "1:1"),
        "1 variable is in both inputs besides the keys.*`x` values: score"
    )

    expect_identical(names(result), c("id", "score", "_merge"))
    expect_identical(as.double(result$score), c(10, NA_real_, 300))
    expect_identical(stata_storage_type(result$score), "int")

    wide_master <- tibble::tibble(
        id = 1, a = 1, b = 1, c = 1, d = 1, e = 1, f = 1, g = 1
    )
    wide_using <- tibble::tibble(
        id = 1, a = 2, b = 2, c = 2, d = 2, e = 2, f = 2, g = 2
    )
    expect_warning(
        dta_merge(wide_master, wide_using, by = "id",
                    relationship = "1:1"),
        "7 variables are in both inputs besides the keys.*e, and 2 more"
    )
})

test_that("compact variables retain values across merge partitions", {
    constructors <- list(
        byte = stata_byte,
        int = stata_int,
        long = stata_long,
        float = stata_float
    )
    master <- tibble::tibble(id = c(1, 2))
    using <- tibble::tibble(id = c(2, 3))
    for (name in names(constructors)) {
        master[[name]] <- constructors[[name]](
            c(10, tagged_missing("a"))
        )
        using[[name]] <- constructors[[name]](
            c(tagged_missing("b"), 20)
        )
    }

    result <- suppressWarnings(dta_merge(
        master, using, by = "id", relationship = "1:1"
    ))

    for (name in names(constructors)) {
        expect_identical(stata_storage_type(result[[name]]), name)
        expect_true(
            dtaparser:::.is_unmaterialized_numeric_altrep(result[[name]])
        )
        expect_identical(
            missing_tag(result[[name]]), c(NA, "a", NA)
        )
        expect_identical(as.double(result[[name]])[c(1L, 3L)], c(10, 20))
    }
})

test_that("Stata doubles retain values and metadata across merge partitions", {
    master <- tibble::tibble(
        id = c(1, 2),
        ordinary_x = c("a", "b"),
        double_x = set_variable_labels(
            stata_double(c(10, tagged_missing("a"))),
            "Master double"
        ),
        ordinary_shared = c(100L, 200L),
        shared = set_value_labels(
            stata_double(c(1, NA_real_)), One = 1
        )
    )
    using <- tibble::tibble(
        id = c(2, 3),
        ordinary_y = c(TRUE, FALSE),
        double_y = set_variable_labels(
            stata_double(c(20, 30)),
            "Using double"
        ),
        ordinary_shared = c(999L, 300L),
        shared = set_value_labels(
            stata_double(c(99, 3)), Three = 3
        )
    )

    result <- suppressWarnings(dta_merge(
        master, using, by = "id", relationship = "1:1"
    ))

    expect_identical(result$ordinary_x, c("a", "b", NA))
    expect_identical(result$ordinary_y, c(NA, TRUE, FALSE))
    expect_identical(result$ordinary_shared, c(100L, 200L, 300L))
    expect_identical(as.double(result$double_x)[c(1L, 3L)], c(10, NA))
    expect_identical(missing_tag(result$double_x), c(NA, "a", NA))
    expect_identical(as.double(result$double_y), c(NA, 20, 30))
    expect_identical(as.double(result$shared), c(1, NA, 3))
    expect_identical(
        vapply(
            result[c("double_x", "double_y", "shared")],
            stata_storage_type,
            character(1)
        ),
        c(double_x = "double", double_y = "double", shared = "double")
    )
    expect_identical(var_label(result$double_x), "Master double")
    expect_identical(var_label(result$double_y), "Using double")
    expect_identical(val_labels(result$shared), c(One = 1, Three = 3))
})

test_that("compact variables keep legacy observed encodings", {
    legacy <- read_dta(fixture("synthetic_v111.dta"))
    master <- tibble::tibble(id = c(1, 2), value = legacy$b[1:2])
    using <- tibble::tibble(id = c(2, 3), other = c("a", "b"))

    result <- dta_merge(master, using, by = "id", relationship = "1:1")

    expect_identical(as.double(result$value), c(1, 101, NA_real_))
    expect_true(
        dtaparser:::.is_unmaterialized_numeric_altrep(result$value)
    )
})

test_that("compact coalescing handles legacy and modern missing layouts", {
    legacy <- read_dta(fixture("synthetic_v111.dta"))
    master <- tibble::tibble(
        id = c(1, 2), value = legacy$b[c(1L, 4L)]
    )
    using <- tibble::tibble(
        id = c(2, 3), value = stata_byte(c(2, tagged_missing("a")))
    )

    result <- suppressWarnings(dta_merge(
        master, using, by = "id", relationship = "1:1"
    ))

    expect_identical(as.double(result$value)[1], 1)
    expect_identical(missing_tag(result$value), c(NA, NA, "a"))
    expect_true(
        dtaparser:::.is_unmaterialized_numeric_altrep(result$value)
    )
})

test_that("merge relationships are validated with explicit diagnostics", {
    unique_keys <- tibble::tibble(id = c(1, 2))
    duplicated_keys <- tibble::tibble(id = c(2, 2))
    duplicated_missing <- tibble::tibble(
        id = tagged_missing(c("a", "a"))
    )

    expect_error(
        dta_merge(duplicated_keys, unique_keys,
                    by = "id", relationship = "1:1"),
        "unique keys in `x`"
    )
    expect_error(
        dta_merge(unique_keys, duplicated_keys,
                    by = "id", relationship = "1:1"),
        "unique keys in `y`"
    )
    expect_error(
        dta_merge(unique_keys, duplicated_keys,
                    by = "id", relationship = "m:1"),
        "unique keys in `y`"
    )
    expect_error(
        dta_merge(duplicated_keys, unique_keys,
                    by = "id", relationship = "1:m"),
        "unique keys in `x`"
    )
    expect_error(
        dta_merge(unique_keys, duplicated_missing,
                    by = "id", relationship = "m:1"),
        "unique keys in `y`"
    )
    expect_error(
        dta_merge(unique_keys, unique_keys,
                    by = "id", relationship = "m:m"),
        "m:m"
    )

    many <- tibble::tibble(id = c(1, 1, 2), tag = c("x", "y", "z"))
    lookup <- tibble::tibble(id = c(1, 2), value = c(10, 20))
    m_to_1 <- dta_merge(many, lookup, by = "id", relationship = "m:1")
    expect_identical(m_to_1$value, c(10, 10, 20))

    one_to_m <- dta_merge(lookup, many, by = "id", relationship = "1:m")
    expect_identical(one_to_m$id, c(1, 1, 2))
    expect_identical(one_to_m$value, c(10, 10, 20))
    expect_identical(one_to_m$tag, c("x", "y", "z"))
})

test_that("keep filters match results and assert validates them", {
    master <- tibble::tibble(id = c(1, 2), master_value = c("a", "b"))
    using <- tibble::tibble(id = c(2, 3), using_value = c("c", "d"))

    kept <- dta_merge(
        master, using, by = "id", relationship = "1:1",
        keep = c("master", "match")
    )
    expect_identical(kept$id, c(1, 2))
    expect_identical(as.double(kept$`_merge`), c(1, 3))

    matches_only <- dta_merge(
        master, using, by = "id", relationship = "1:1", keep = "match"
    )
    expect_identical(matches_only$id, 2)

    expect_error(
        dta_merge(master, using, by = "id", relationship = "1:1",
                    assert = "match"),
        "x only"
    )
    expect_error(
        dta_merge(master, using, by = "id", relationship = "1:1",
                    assert = c("master", "match")),
        "y only"
    )
    asserted <- dta_merge(
        master, using, by = "id", relationship = "1:1",
        assert = c("master", "using", "match")
    )
    expect_identical(nrow(asserted), 3L)

    x_tokens <- dta_merge(
        master, using, by = "id", relationship = "1:1",
        keep = c("x", "match")
    )
    expect_identical(data_values(x_tokens), data_values(kept))
    expect_error(
        dta_merge(master, using, by = "id", relationship = "1:1",
                    assert = "y"),
        "x only"
    )

    expect_error(
        dta_merge(master, using, by = "id", relationship = "1:1",
                    keep = "matched"),
        "keep"
    )
    expect_error(
        dta_merge(master, using, by = "id", relationship = "1:1",
                    keep = c("x", "master")),
        "aliases"
    )
})

test_that("inputs and by keys are validated", {
    master <- tibble::tibble(id = 1, `_merge` = 1)
    plain <- tibble::tibble(id = 1)

    expect_error(
        dta_merge(master, plain, by = "id", relationship = "1:1"),
        "_merge"
    )
    expect_error(
        dta_merge(plain, master, by = "id", relationship = "1:1"),
        "_merge"
    )
    expect_error(
        dta_merge(plain, plain, by = "missing", relationship = "1:1"),
        "missing"
    )
    expect_error(
        dta_merge(plain, plain, by = character(), relationship = "1:1"),
        "by"
    )
    expect_error(
        dta_merge(plain, plain, by = "id", relationship = "one-to-one"),
        "relationship"
    )
    expect_error(dta_merge(plain, plain, by = "id"), "relationship")
    expect_error(
        dta_merge(1, plain, by = "id", relationship = "1:1"),
        "`x` must be a data frame"
    )
})

test_that("zero-row inputs merge cleanly", {
    master <- tibble::tibble(
        id = stata_byte(double()), master_value = character()
    )
    using <- tibble::tibble(id = stata_byte(c(1, 2)),
                            using_value = c("a", "b"))

    result <- dta_merge(master, using, by = "id", relationship = "1:1")
    expect_identical(nrow(result), 2L)
    expect_identical(as.double(result$`_merge`), c(2, 2))
    expect_identical(result$master_value, c(NA_character_, NA_character_))

    empty <- dta_merge(
        master,
        tibble::tibble(id = stata_byte(double()), using_value = character()),
        by = "id",
        relationship = "1:1"
    )
    expect_identical(nrow(empty), 0L)
    expect_identical(stata_storage_type(empty$`_merge`), "byte")

    compact_empty <- suppressWarnings(dta_merge(
        tibble::tibble(
            id = stata_byte(double()), value = stata_byte(double())
        ),
        tibble::tibble(
            id = stata_byte(double()), value = stata_byte(double())
        ),
        by = "id", relationship = "1:1"
    ))
    expect_identical(nrow(compact_empty), 0L)
    expect_true(
        dtaparser:::.is_unmaterialized_numeric_altrep(compact_empty$value)
    )
})

test_that("temporal keys merge with promoted storage", {
    byte_path <- fixture_with_temporal_storage("foreign")
    int_path <- fixture_with_temporal_storage("price")
    on.exit(unlink(c(byte_path, int_path)), add = TRUE)
    byte_date <- read_dta(byte_path)$foreign[1]
    int_date <- read_dta(int_path)$price[1]

    warnings <- testthat::capture_warnings(
        result <- dta_merge(
            tibble::tibble(id = byte_date, master_value = "m"),
            tibble::tibble(id = int_date, using_value = "u"),
            by = "id",
            relationship = "1:1"
        )
    )
    expect_match(warnings, "variable labels differ", all = FALSE)
    expect_match(warnings, "value labels differ", all = FALSE)

    expect_s3_class(result$id, "Date")
    expect_identical(stata_storage_type(result$id), "int")
    expect_identical(
        sort(as.double(result$id)),
        sort(c(as.double(byte_date), as.double(int_date)))
    )
})

test_that("dataset label and notes come from the master", {
    master <- tibble::tibble(id = 1)
    dataset_label(master) <- "Master survey"
    attr(master, "notes") <- c("master note")
    using <- tibble::tibble(id = 1)
    dataset_label(using) <- "Using survey"
    attr(using, "notes") <- c("using note")

    result <- dta_merge(master, using, by = "id", relationship = "1:1")

    expect_identical(dataset_label(result), "Master survey")
    expect_identical(attr(result, "notes", exact = TRUE), "master note")
})

test_that("master and using accept DTA file paths in any combination", {
    master <- tibble::tibble(
        id = stata_byte(c(1, tagged_missing("a"))),
        master_value = c(10, 20)
    )
    using <- tibble::tibble(
        id = stata_byte(c(tagged_missing("a"), 7)),
        using_value = c("u1", "u2")
    )
    master_path <- tempfile(fileext = ".dta")
    using_path <- tempfile(fileext = ".dta")
    on.exit(unlink(c(master_path, using_path)), add = TRUE)
    write_dta(master, master_path)
    write_dta(using, using_path)

    from_frames <- dta_merge(master, using, by = "id",
                               relationship = "1:1")
    combinations <- list(
        list(master_path, using),
        list(master, using_path),
        list(master_path, using_path)
    )
    for (inputs in combinations) {
        result <- dta_merge(
            inputs[[1L]], inputs[[2L]], by = "id", relationship = "1:1"
        )
        expect_identical(names(result), names(from_frames))
        expect_identical(data_values(result), data_values(from_frames))
        expect_identical(
            missing_tag(result$id), missing_tag(from_frames$id)
        )
    }

    expect_error(
        dta_merge(master, NA_character_, by = "id", relationship = "1:1"),
        "`y` must be a data frame"
    )
    expect_error(
        dta_merge(c(master_path, using_path), using,
                    by = "id", relationship = "1:1"),
        "`x` must be a data frame"
    )
})

test_that("multiple keys match jointly under missing-code identity", {
    master <- tibble::tibble(
        region = c(1, 1, 2),
        wave = stata_byte(c(1, tagged_missing("a"), 1)),
        master_value = c("a", "b", "c")
    )
    using <- tibble::tibble(
        region = c(1, 1, 2),
        wave = stata_byte(c(tagged_missing("a"), tagged_missing("b"), 1)),
        using_value = c("x", "y", "z")
    )

    result <- dta_merge(
        master, using, by = c("region", "wave"), relationship = "1:1"
    )

    expect_identical(as.double(result$`_merge`), c(1, 3, 3, 2))
    expect_identical(result$using_value, c(NA, "x", "z", "y"))
})
