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

    expect_identical(result$master_value, c("m1", "m2", "m3", ""))
    expect_identical(result$using_value, c("", "u2", "u1", "u3"))

    expect_identical(stata_storage_type(result$`_merge`), "byte")
    expect_identical(as.double(result$`_merge`), c(1, 3, 3, 2))
    expect_identical(val_labels(result$`_merge`), merge_indicator_labels)
})

test_that("compact gathers retain exact missing counts", {
    master <- tibble::tibble(
        id = c(1L, 2L),
        master_value = stata_byte(c(NA_real_, 20))
    )
    using <- tibble::tibble(
        id = c(2L, 3L),
        using_value = stata_byte(c(NA_real_, 40))
    )

    result <- dta_merge(master, using, by = "id", relationship = "1:1")
    expect_true(anyNA(result$master_value))
    expect_true(anyNA(result$using_value))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(
        result$master_value
    ))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(
        result$using_value
    ))

    replace_values(result, master_value, 9, where = c(1, 3))
    replace_values(result, using_value, 9, where = c(1, 2))
    expect_false(anyNA(result$master_value))
    expect_false(anyNA(result$using_value))
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

test_that("character missing keys require Stata's empty string", {
    missing_key <- tibble::tibble(id = c("a", NA_character_))
    empty_key <- tibble::tibble(id = c("a", ""))

    expect_error(
        dta_merge(missing_key, empty_key, by = "id", relationship = "1:1"),
        "NA_character_.*empty string.*use.*\\\"\\\""
    )
    expect_error(
        dta_merge(empty_key, missing_key, by = "id", relationship = "1:1"),
        "NA_character_.*empty string.*use.*\\\"\\\""
    )
    expect_error(
        dta_merge(
            tibble::tibble(id = c(NA_character_, "")),
            tibble::tibble(id = "x"),
            by = "id", relationship = "1:1"
        ),
        "NA_character_.*empty string"
    )
})

test_that("key columns coalesce storage and metadata", {
    master <- tibble::tibble(
        id = set_var_labels(
            set_val_labels(stata_byte(c(1, 2)), One = 1),
            "Identifier"
        ),
        master_value = c("a", "b")
    )
    using <- tibble::tibble(
        id = set_var_labels(
            set_val_labels(stata_int(c(2, 200)), TwoHundred = 200),
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
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(result$id))

    conflicting <- tibble::tibble(
        id = set_val_labels(stata_byte(1), Uno = 1)
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

test_that("ordinary coalesced columns use y's label when x has none", {
    master <- tibble::tibble(
        id = c("a", "b"),
        group = c("master a", "master b")
    )
    using <- tibble::tibble(
        id = c("b", "c"),
        group = c("using b", "using c")
    )
    var_label(using$id) <- "Identifier"
    var_label(using$group) <- "Group"

    result <- suppressWarnings(dta_merge(
        master, using, by = "id", relationship = "1:1"
    ))

    expect_identical(as.vector(result$id), c("a", "b", "c"))
    expect_identical(
        as.vector(result$group), c("master a", "master b", "using c")
    )
    expect_identical(var_label(result$id), "Identifier")
    expect_identical(var_label(result$group), "Group")
})

test_that("coalesced variables reconcile notes and characteristics x first", {
    master_id <- set_stata_note(c("a", "b"), 4, "master note")
    master_id <- set_stata_characteristic(master_id, "source", "master")
    using_id <- set_stata_note(c("b", "c"), 8, "using note")
    using_id <- set_stata_characteristic(using_id, "source", "using")

    expect_warning(
        result <- dta_merge(
            tibble::tibble(id = master_id),
            tibble::tibble(id = using_id),
            by = "id", relationship = "1:1"
        ),
        "notes or characteristics differ.*metadata wins"
    )
    expect_identical(stata_notes(result$id), c(`4` = "master note"))
    expect_identical(stata_characteristics(result$id), c(source = "master"))

    expect_no_warning(
        fallback <- dta_merge(
            tibble::tibble(id = c("a", "b")),
            tibble::tibble(id = using_id),
            by = "id", relationship = "1:1"
        )
    )
    expect_identical(stata_notes(fallback$id), c(`8` = "using note"))
    expect_identical(stata_characteristics(fallback$id), c(source = "using"))
})

test_that("explicit empty metadata falls back without a conflict warning", {
    master_id <- set_stata_note(c("a", "b"), 1, "temporary")
    master_id <- set_stata_characteristic(master_id, "source", "temporary")
    attr(master_id, "notes") <- character()
    attr(master_id, "stata.note.numbers") <- integer()
    attr(master_id, "stata.characteristics") <- stats::setNames(
        character(), character()
    )
    using_id <- set_stata_note(c("b", "c"), 8, "using note")
    using_id <- set_stata_characteristic(using_id, "source", "using")

    expect_no_warning(
        result <- dta_merge(
            tibble::tibble(id = master_id),
            tibble::tibble(id = using_id),
            by = "id", relationship = "1:1"
        )
    )
    expect_identical(stata_notes(result$id), c(`8` = "using note"))
    expect_identical(stata_characteristics(result$id), c(source = "using"))
})

test_that("coalesced metadata scanning stays width-linear", {
    lookups <- new.env(parent = emptyenv())
    lookups$count <- 0L
    method_name <- "[[.dtatools_merge_lookup_probe"
    method <- function(x, index, ...) {
        if (is.character(index)) {
            stop("coalesced columns must be resolved before scanning")
        }
        lookups$count <- lookups$count + 1L
        NextMethod()
    }
    assign(method_name, method, envir = .GlobalEnv)
    withr::defer(rm(list = method_name, envir = .GlobalEnv))

    work <- integer()
    for (width in c(4000L, 8000L)) {
        data <- structure(
            rep(list(integer()), width),
            names = paste0("v", seq_len(width)),
            row.names = .set_row_names(0L),
            class = c("dtatools_merge_lookup_probe", "data.frame")
        )
        lookups$count <- 0L
        dtatools:::.warn_coalesced_metadata(data, data, names(data))
        work <- c(work, lookups$count)
    }
    expect_identical(work, c(8000L, 16000L))
})

test_that("coalesced variables with matching metadata merge silently", {
    master <- tibble::tibble(
        id = set_var_labels(
            set_val_labels(stata_byte(c(1, 2)), One = 1),
            "Identifier"
        ),
        score = c(10, 20)
    )
    using <- tibble::tibble(
        id = set_var_labels(
            set_val_labels(stata_int(c(1, 2)), One = 1),
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
            dtatools:::.is_unmaterialized_numeric_altrep(result[[name]])
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
        double_x = set_var_labels(
            stata_double(c(10, tagged_missing("a"))),
            "Master double"
        ),
        ordinary_shared = c(100L, 200L),
        shared = set_val_labels(
            stata_double(c(1, NA_real_)), One = 1
        )
    )
    using <- tibble::tibble(
        id = c(2, 3),
        ordinary_y = c(TRUE, FALSE),
        double_y = set_var_labels(
            stata_double(c(20, 30)),
            "Using double"
        ),
        ordinary_shared = c(999L, 300L),
        shared = set_val_labels(
            stata_double(c(99, 3)), Three = 3
        )
    )

    result <- suppressWarnings(dta_merge(
        master, using, by = "id", relationship = "1:1"
    ))

    expect_identical(result$ordinary_x, c("a", "b", ""))
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
        dtatools:::.is_unmaterialized_numeric_altrep(result$value)
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
        dtatools:::.is_unmaterialized_numeric_altrep(result$value)
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

    duplicated_key <- data.frame(first = 1, second = 2, check.names = FALSE)
    names(duplicated_key) <- c("id", "id")
    expect_error(
        dta_merge(duplicated_key, plain, by = "id", relationship = "1:1"),
        "`x` must have unique"
    )

    duplicated_value <- data.frame(
        id = 1, first = 2, second = 3, check.names = FALSE
    )
    names(duplicated_value) <- c("id", "value", "value")
    expect_error(
        dta_merge(plain, duplicated_value, by = "id", relationship = "1:1"),
        "`y` must have unique"
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
    expect_identical(result$master_value, c("", ""))

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
        dtatools:::.is_unmaterialized_numeric_altrep(compact_empty$value)
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

test_that("dataset notes append master then using with stable numbering", {
    master <- tibble::tibble(id = 1)
    dataset_label(master) <- "Master survey"
    attr(master, "notes") <- c("master note")
    using <- tibble::tibble(id = 1)
    dataset_label(using) <- "Using survey"
    attr(using, "notes") <- c("using note")

    result <- dta_merge(master, using, by = "id", relationship = "1:1")

    expect_identical(dataset_label(result), "Master survey")
    expect_identical(
        attr(result, "notes", exact = TRUE),
        c("master note", "using note")
    )
    expect_null(attr(result, "stata.note.numbers", exact = TRUE))
    expect_identical(
        stata_notes(result),
        c(`1` = "master note", `2` = "using note")
    )
})

test_that("dataset-note merge preserves one side and renumbers using notes", {
    empty <- tibble::tibble(id = 1)
    master <- set_stata_note(empty, 3, "master three")
    master <- set_stata_note(master, 7, "same text")
    using <- set_stata_note(empty, 2, "same text")
    using <- set_stata_note(using, 8, "using eight")

    master_only <- dta_merge(
        master, empty, by = "id", relationship = "1:1"
    )
    using_only <- dta_merge(
        empty, using, by = "id", relationship = "1:1"
    )
    combined <- dta_merge(
        master, using, by = "id", relationship = "1:1"
    )
    explicit_empty <- empty
    attr(explicit_empty, "notes") <- character()
    attr(explicit_empty, "stata.note.numbers") <- integer()
    neither <- dta_merge(
        explicit_empty, empty, by = "id", relationship = "1:1"
    )

    expect_identical(stata_notes(master_only), stata_notes(master))
    expect_identical(
        attr(master_only, "stata.note.numbers", exact = TRUE), c(3L, 7L)
    )
    expect_identical(stata_notes(using_only), stata_notes(using))
    expect_identical(
        attr(using_only, "stata.note.numbers", exact = TRUE), c(2L, 8L)
    )
    expect_identical(
        stata_notes(combined),
        c(
            `3` = "master three", `7` = "same text",
            `8` = "same text", `9` = "using eight"
        )
    )
    expect_null(attr(neither, "notes", exact = TRUE))
    expect_null(attr(neither, "stata.note.numbers", exact = TRUE))
})

test_that("dataset-note merge rejects Stata note-number exhaustion", {
    master <- set_stata_note(tibble::tibble(id = 1), 9999, "last")
    using <- set_stata_note(tibble::tibble(id = 1), 1, "using")

    expect_error(
        dta_merge(master, using, by = "id", relationship = "1:1"),
        "cannot be appended.*9,999"
    )
})

test_that("base, tibble, and data.table inputs merge identically", {
    skip_if_not_installed("data.table")
    make_input <- function(side, kind) {
        data <- if (identical(side, "x")) {
            data.frame(
                id = c(1L, 2L), shared = c("x1", "x2"),
                x_only = c(10L, 20L)
            )
        } else {
            data.frame(
                id = c(2L, 3L), shared = c("y2", "y3"),
                y_only = c(30L, 40L)
            )
        }
        data <- switch(kind,
            base = data,
            tibble = tibble::as_tibble(data),
            data.table = data.table::as.data.table(data)
        )
        dataset_label(data) <- paste(side, "dataset")
        data <- set_stata_note(data, 2, paste(side, "note"))
        data <- set_stata_characteristic(data, "source", side)
        data[["shared"]] <- set_stata_note(
            data[["shared"]], 4, paste(side, "variable note")
        )
        data
    }
    kinds <- c("base", "tibble", "data.table")
    reference <- suppressWarnings(dta_merge(
        make_input("x", "base"), make_input("y", "base"),
        by = "id", relationship = "1:1"
    ))

    for (x_kind in kinds) {
        for (y_kind in kinds) {
            x <- make_input("x", x_kind)
            y <- make_input("y", y_kind)
            x_before <- data.table::copy(x)
            y_before <- data.table::copy(y)
            x_alias <- x
            y_alias <- y
            result <- suppressWarnings(dta_merge(
                x, y, by = "id", relationship = "1:1"
            ))
            info <- sprintf("x = %s, y = %s", x_kind, y_kind)

            if (identical(x_kind, "tibble")) {
                expect_s3_class(result, "tbl_df")
            } else if (identical(x_kind, "data.table")) {
                expect_s3_class(result, "data.table")
                expect_null(data.table::key(result))
                expect_length(data.table::indices(result), 0L)
            } else {
                expect_false(inherits(result, c("tbl_df", "data.table")))
            }
            expect_identical(data_values(result), data_values(reference),
                             info = info)
            expect_identical(stata_notes(result), stata_notes(reference),
                             info = info)
            expect_identical(
                stata_notes(result$shared), stata_notes(reference$shared),
                info = info
            )
            expect_identical(
                stata_characteristics(result),
                stata_characteristics(reference), info = info
            )
            expect_equal(x, x_before, info = info)
            expect_equal(y, y_before, info = info)
            expect_equal(x_alias, x_before, info = info)
            expect_equal(y_alias, y_before, info = info)
        }
    }
})

test_that("plain keyed data.tables retain their values, aliases, and keys", {
    skip_if_not_installed("data.table")
    master <- data.table::data.table(
        id = c(1L, 2L), shared = c("x1", "x2"), x_only = c(10L, 20L)
    )
    using <- data.table::data.table(
        id = c(2L, 3L), shared = c("y2", "y3"), y_only = c(30L, 40L)
    )
    data.table::setkey(master, id)
    data.table::setkey(using, id)
    master_before <- data.table::copy(master)
    using_before <- data.table::copy(using)
    master_alias <- master
    using_alias <- using

    result <- suppressWarnings(dta_merge(
        master, using, by = "id", relationship = "1:1"
    ))

    expect_s3_class(result, "data.table")
    expect_null(data.table::key(result))
    expect_length(data.table::indices(result), 0L)
    expect_identical(
        data_values(result),
        list(
            id = c(1, 2, 3),
            shared = c("x1", "x2", "y3"),
            x_only = c(10, 20, NA_real_),
            y_only = c(NA_real_, 30, 40),
            `_merge` = c(1, 3, 2)
        )
    )
    expect_equal(master, master_before)
    expect_equal(using, using_before)
    expect_equal(master_alias, master_before)
    expect_equal(using_alias, using_before)
    expect_identical(data.table::key(master), "id")
    expect_identical(data.table::key(using), "id")
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
    save_dta(master, master_path)
    save_dta(using, using_path)

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

test_that("every x and y source combination merges identically", {
    master <- tibble::tibble(
        id = stata_byte(c(1, 2, NA_real_, tagged_missing("a"), 5)),
        score = stata_int(c(10, 20, 30, 40, 50)),
        city = c("ny", "la", "", "sf", "dc")
    )
    using <- tibble::tibble(
        id = stata_byte(c(2, tagged_missing("a"), 7, NA_real_, 6)),
        group = c("g1", "g2", "g3", "g4", "g5")
    )

    # Five representations of the same content: a .dta path, an .arrow
    # path, the read_dta() read model (compact ALTREP numerics and deferred
    # strings), bare R vectors (tagged payloads survive as.double()), and a
    # frame mixing read-model and bare columns.
    make_sources <- function(data) {
        dta_path <- tempfile(fileext = ".dta")
        arrow_path <- tempfile(fileext = ".arrow")
        save_dta(data, dta_path)
        save_arrow(data, arrow_path)
        stata_memory <- read_dta(dta_path)
        r_memory <- tibble::as_tibble(data_values(data))
        mixed <- stata_memory
        for (index in seq_along(mixed)) {
            if (index %% 2L == 0L) mixed[[index]] <- r_memory[[index]]
        }
        list(dta = dta_path, arrow = arrow_path, stata = stata_memory,
             r = r_memory, mixed = mixed)
    }

    x_sources <- make_sources(master)
    y_sources <- make_sources(using)
    on.exit(unlink(c(x_sources$dta, x_sources$arrow,
                     y_sources$dta, y_sources$arrow)), add = TRUE)
    reference <- dta_merge(master, using, by = "id", relationship = "1:1")
    expect_identical(as.double(reference$`_merge`), c(1, 3, 3, 3, 1, 2, 2))

    for (x_name in names(x_sources)) {
        for (y_name in names(y_sources)) {
            result <- dta_merge(
                x_sources[[x_name]], y_sources[[y_name]],
                by = "id", relationship = "1:1"
            )
            info <- sprintf("x = %s, y = %s", x_name, y_name)
            expect_identical(names(result), names(reference), info = info)
            expect_identical(data_values(result), data_values(reference),
                             info = info)
            expect_identical(missing_tag(result$id),
                             missing_tag(reference$id), info = info)
        }
    }
})

test_that("Arrow URLs with query strings dispatch to read_arrow", {
    expected <- tibble::tibble(id = 1L)
    seen <- character()
    local_mocked_bindings(
        read_arrow = function(file, ...) {
            seen <<- c(seen, file)
            expected
        },
        read_dta = function(...) stop("dispatched to read_dta"),
        .package = "dtatools"
    )
    url <- paste0(
        "https://example.test/data.arrow?",
        "X-Amz-Signature=0123456789abcdef"
    )

    actual <- dtatools:::.resolve_merge_input(url, "x")

    expect_identical(actual, expected)
    expect_identical(seen, url)
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
    expect_identical(result$using_value, c("", "x", "z", "y"))
})

test_that("unmatched rows fill string columns with the empty string", {
    master <- tibble::tibble(
        id = stata_long(c(1, 2)),
        master_name = stata_string(c("a", "b")),
        plain_name = c("p", "q")
    )
    using <- tibble::tibble(
        id = stata_long(c(2, 3)),
        using_name = stata_string(c("c", "d"))
    )

    result <- dta_merge(master, using, by = "id", relationship = "1:1")

    expect_identical(vctrs::vec_data(result$using_name), c("", "c", "d"))
    expect_identical(vctrs::vec_data(result$master_name), c("a", "b", ""))
    expect_identical(result$plain_name, c("p", "q", ""))
    # The filled columns must stay valid stata strings: a downstream
    # comparison casts them and rejects any `NA_character_`.
    expect_identical(
        result$master_name == result$using_name,
        c(FALSE, FALSE, FALSE)
    )
})
