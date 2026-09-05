test_that("slice_dta_rows matches imported Stata column slicing", {
    data <- read_dta(fixture("all_types_v118.dta"))
    class(data) <- "data.frame"
    data <- set_dta_note(data, 4, "dataset note")
    data <- set_dta_characteristic(data, "source", "fixture")
    data <- set_dta_note(data, 7, "variable note", variable = "v_double")
    data <- set_dta_characteristic(
        data, "role", "measure", variable = "v_double"
    )
    row.names(data) <- paste0("row", seq_len(nrow(data)))

    compact_names <- c("v_byte", "v_int", "v_long", "v_float")
    string_names <- c("v_str5", "v_str20", "v_strL")
    expect_true(all(vapply(
        data[compact_names],
        dtatools:::.is_unmaterialized_numeric_altrep,
        logical(1)
    )))
    expect_true(all(vapply(
        data[string_names],
        dtatools:::.is_unmaterialized_dictstring,
        logical(1)
    )))

    locations <- list(
        c(5L, 2L, NA_integer_, 2L),
        -c(1L, 3L),
        rep(c(TRUE, FALSE), length.out = nrow(data)),
        integer()
    )
    for (container in list(data, tibble::as_tibble(data))) {
        for (rows in locations) {
            expected <- container[rows, , drop = FALSE]
            actual <- slice_dta_rows(container, rows)

            expect_identical(actual, expected, info = deparse(rows))
        }
    }
    character_rows <- c("row5", "row2", "row2")
    expect_identical(
        slice_dta_rows(data, character_rows),
        data[character_rows, , drop = FALSE]
    )

    selected <- slice_dta_rows(data, c(5L, 2L, NA_integer_, 2L))
    expect_true(all(vapply(
        data[compact_names],
        dtatools:::.is_unmaterialized_numeric_altrep,
        logical(1)
    )))
    expect_true(all(vapply(
        selected[compact_names],
        dtatools:::.is_unmaterialized_numeric_altrep,
        logical(1)
    )))
    expect_true(all(vapply(
        data[string_names],
        dtatools:::.is_unmaterialized_dictstring,
        logical(1)
    )))
    expect_false(any(vapply(
        selected[string_names],
        dtatools:::.is_unmaterialized_dictstring,
        logical(1)
    )))
})

test_that("slice_dta_rows preserves every numeric storage and missing tag", {
    values <- c(1, NA_real_, tagged_missing("a"), tagged_missing("z"), -1)
    data <- data.frame(
        byte = dta_byte(values),
        int = dta_int(values),
        long = dta_long(values),
        float = dta_float(values),
        double = dta_double(values)
    )
    data <- set_dta_note(data, 3, "numeric note", variable = "int")
    data <- set_dta_characteristic(
        data, "source", "generated", variable = "int"
    )
    attr(data$float, "label") <- "Float value"
    attr(data$float, "labels") <- c(One = 1, Minus_one = -1)
    attr(data$float, "format.stata") <- "%9.2f"

    rows <- c(4L, 2L, 3L, NA_integer_, 1L, 4L)
    expected <- data[rows, , drop = FALSE]
    actual <- slice_dta_rows(data, rows)

    expect_identical(actual, expected)
    expect_identical(
        vapply(actual, dta_storage_type, character(1)),
        c(
            byte = "byte", int = "int", long = "long",
            float = "float", double = "double"
        )
    )
    for (name in names(actual)) {
        expect_identical(
            writeBin(as.double(actual[[name]]), raw(), size = 8L),
            writeBin(as.double(expected[[name]]), raw(), size = 8L),
            info = name
        )
        expect_identical(
            missing_tag(actual[[name]]),
            c("z", NA, "a", NA, NA, "z"),
            info = name
        )
    }
})

test_that("slice_dta_rows preserves temporal and ordinary columns", {
    date_path <- fixture_with_temporal_storage("foreign")
    time_path <- fixture_with_temporal_storage("price", "%tc")
    on.exit(unlink(c(date_path, time_path)), add = TRUE)
    dates <- read_dta(date_path)$foreign
    times <- read_dta(time_path)$price
    count <- length(dates)
    matrix_column <- matrix(seq_len(count * 2L), ncol = 2L)
    data <- tibble::tibble(
        dates = dates,
        times = times,
        text = paste0("row", seq_len(count)),
        category = factor(rep(c("a", "b"), length.out = count)),
        matrix_column = matrix_column
    )

    rows <- c(5L, 2L, NA_integer_, 2L)
    expected <- data[rows, , drop = FALSE]
    actual <- slice_dta_rows(data, rows)

    expect_identical(actual, expected)
    expect_s3_class(actual$dates, "Date")
    expect_s3_class(actual$times, "POSIXct")
    expect_identical(dta_storage_type(actual$dates), "byte")
    expect_identical(dta_storage_type(actual$times), "int")
})

test_that("slice_dta_rows handles named and empty columns", {
    named <- dta_int(c(1, 2, NA_real_, tagged_missing("a"), 5))
    names(named) <- letters[seq_along(named)]
    data <- structure(
        list(named = named),
        class = "data.frame",
        row.names = .set_row_names(length(named))
    )
    rows <- c(5L, 2L, NA_integer_, 2L)

    expect_identical(
        slice_dta_rows(data, rows),
        data[rows, , drop = FALSE]
    )

    # Zero-column frames take a shortcut through base `[`, which keeps
    # dataset-level metadata there even though it drops it once
    # columns are present. Guard that the shortcut stays safe.
    empty_columns <- data.frame(row.names = letters[1:4])
    attr(empty_columns, "label") <- "Empty-column dataset"
    sliced <- slice_dta_rows(empty_columns, c(4L, 1L))
    expect_identical(
        attr(sliced, "label", exact = TRUE), "Empty-column dataset"
    )
    expect_identical(dim(sliced), c(2L, 0L))
    expect_identical(
        attr(sliced, "row.names", exact = TRUE),
        attr(empty_columns[c(4L, 1L), , drop = FALSE], "row.names",
             exact = TRUE)
    )
    expect_identical(
        slice_dta_rows(data[integer(), , drop = FALSE], integer()),
        data[integer(), , drop = FALSE]
    )
})

test_that("slice_dta_rows slices ordinary data.tables", {
    skip_if_not_installed("data.table")
    data <- read_dta(fixture("all_types_v118.dta"), output = "data.table")
    data <- set_dta_note(data, 4, "dataset note")
    data <- set_dta_characteristic(data, "source", "fixture")
    data <- set_dta_note(data, 7, "variable note", variable = "v_double")
    data.table::setattr(data, "sorted", "v_byte")

    frame <- as.data.frame(data)
    class(frame) <- "data.frame"
    locations <- list(
        c(5L, 2L, NA_integer_, 2L),
        -c(1L, 3L),
        rep(c(TRUE, FALSE), length.out = nrow(data)),
        integer()
    )
    for (rows in locations) {
        expected <- frame[rows, , drop = FALSE]
        actual <- slice_dta_rows(data, rows)

        expect_identical(
            class(actual), c("data.table", "data.frame"),
            info = deparse(rows)
        )
        expect_null(attr(actual, "sorted"))
        expect_null(attr(actual, "index"))
        expect_identical(
            as.list(actual), as.list(expected), info = deparse(rows)
        )
    }

    selected <- slice_dta_rows(data, c(5L, 2L, NA_integer_, 2L))
    compact_names <- c("v_byte", "v_int", "v_long", "v_float")
    expect_true(all(vapply(
        as.list(selected)[compact_names],
        dtatools:::.is_unmaterialized_numeric_altrep,
        logical(1)
    )))
    expect_true(all(vapply(
        as.list(data)[compact_names],
        dtatools:::.is_unmaterialized_numeric_altrep,
        logical(1)
    )))
    expect_identical(attr(data, "sorted"), "v_byte")
    expect_identical(
        attr(selected, "notes"), attr(data, "notes")
    )
    expect_identical(
        dta_characteristic(selected, "source"), "fixture"
    )
    expect_silent(data.table::set(
        selected, j = "v_byte", value = as.list(selected)$v_byte
    ))

    tagged_table <- data.table::data.table(
        value = dta_int(c(1, NA_real_, tagged_missing("a")))
    )
    tagged <- slice_dta_rows(tagged_table, c(3L, 1L, 2L))
    expect_identical(missing_tag(tagged$value), c("a", NA, NA))
    expect_identical(dta_storage_type(tagged$value), "int")
})

test_that("slice_dta_rows validates its container and locations", {
    expect_error(
        slice_dta_rows(1:3, 1L),
        "must be a base data frame, tibble, or data.table"
    )
    subclass <- structure(
        data.frame(x = 1:3),
        class = c("custom_data_frame", "data.frame")
    )
    expect_error(
        slice_dta_rows(subclass, 1L),
        "ordinary base data frame, tibble, or data.table"
    )
    expect_error(
        slice_dta_rows(data.frame(x = 1:3), 4L),
        "Location 4"
    )
    expect_error(
        slice_dta_rows(data.frame(x = 1:3), "unknown"),
        "doesn't exist"
    )
})

test_that("slice_dta_rows rejects data.table subclasses", {
    skip_if_not_installed("data.table")
    table_subclass <- data.table::data.table(x = 1:3)
    data.table::setattr(
        table_subclass, "class",
        c("custom_table", class(table_subclass))
    )
    expect_error(
        slice_dta_rows(table_subclass, 1L),
        "ordinary base data frame, tibble, or data.table"
    )
})

test_that("reorder_dta_rows permutes a data.table in place", {
    skip_if_not_installed("data.table")
    data <- read_dta(fixture("all_types_v118.dta"), output = "data.table")
    data.table::setattr(data, "sorted", "v_byte")
    frame <- as.data.frame(data)
    class(frame) <- "data.frame"
    rows <- rev(seq_len(nrow(data)))
    expected <- frame[rows, , drop = FALSE]
    compact_names <- c("v_byte", "v_int", "v_long", "v_float")

    before <- data.table::address(data)
    result <- withVisible(reorder_dta_rows(data, rows))
    expect_false(result$visible)
    expect_identical(data.table::address(data), before)
    # Checked before any content comparison: base identical() reads
    # column DATAPTRs, which materializes compact ALTREP columns.
    expect_true(all(vapply(
        as.list(data)[compact_names],
        dtatools:::.is_unmaterialized_numeric_altrep,
        logical(1)
    )))
    expect_identical(as.list(data), as.list(expected))
    expect_null(attr(data, "sorted"))
    expect_null(attr(data, "index"))
    expect_silent(data.table::set(
        data, j = "v_str5", value = as.list(data)$v_str5
    ))

    tagged_table <- data.table::data.table(
        value = dta_int(c(1, NA_real_, tagged_missing("a")))
    )
    reorder_dta_rows(tagged_table, c(3L, 1L, 2L))
    expect_identical(missing_tag(tagged_table$value), c("a", NA, NA))
    expect_identical(dta_storage_type(tagged_table$value), "int")
})

test_that("reorder_dta_rows permutes other ordinary containers", {
    rows <- c(3L, 1L, 2L)
    frame <- data.frame(x = dta_int(1:3), label = c("a", "b", "c"))
    reorder_dta_rows(frame, rows)
    expect_identical(as.double(vctrs::vec_data(frame$x)), c(3, 1, 2))
    expect_identical(frame$label, c("c", "a", "b"))
    expect_identical(row.names(frame), c("1", "2", "3"))

    table <- tibble::tibble(x = dta_int(1:3), label = c("a", "b", "c"))
    reorder_dta_rows(table, rows)
    expect_identical(as.double(vctrs::vec_data(table$x)), c(3, 1, 2))
    expect_identical(table$label, c("c", "a", "b"))
    expect_s3_class(table, "tbl_df")
})

test_that("reorder_dta_rows permutes reference-state columns", {
    data <- read_dta(fixture("all_types_v118.dta"), output = "tibble")
    rows <- rev(seq_len(nrow(data)))
    expected <- vctrs::vec_slice(
        as.double(vctrs::vec_data(data$v_byte)), rows
    )
    gen(data, doubled, v_byte * 2)
    expect_s3_class(data, "dtatools_ref_data")
    names_before <- names(data)
    # A generated column lives only in the reference state, so the
    # overlay and the physical columns must move together.
    alias <- data
    reorder_dta_rows(data, rows)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(
        as.list(data)$v_byte
    ))
    expect_identical(names(data), names_before)
    expect_identical(as.double(vctrs::vec_data(data$v_byte)), expected)
    expect_identical(as.double(vctrs::vec_data(data$doubled)), expected * 2)
    # Reference semantics: the reorder is visible through every binding.
    expect_identical(as.double(vctrs::vec_data(alias$doubled)), expected * 2)
})

test_that("reorder_dta_rows permutes a physically complete generated table", {
    data <- read_dta(fixture("all_types_v118.dta"), output = "tibble")
    rows <- rev(seq_len(nrow(data)))
    expected <- vctrs::vec_slice(
        as.double(vctrs::vec_data(data$v_byte)), rows
    )
    gen(data, doubled, v_byte * 2)
    gen(data, tripled, v_byte * 3)
    # Structural operations keep all surviving columns physically present.
    drop_vars(data, v_int)
    state <- attr(data, ".dtatools_ref_state", exact = TRUE)
    expect_false(isTRUE(state$physical_overlay))
    names_before <- names(data)

    reorder_dta_rows(data, rows)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(
        as.list(data)$v_byte
    ))
    expect_identical(names(data), names_before)
    expect_identical(as.double(vctrs::vec_data(data$v_byte)), expected)
    expect_identical(as.double(vctrs::vec_data(data$doubled)), expected * 2)
    expect_identical(as.double(vctrs::vec_data(data$tripled)), expected * 3)
})

test_that("reorder_dta_rows validates its container", {
    expect_error(
        reorder_dta_rows(1:3, 1:3),
        "base data frame, tibble, or data.table"
    )
    expect_error(
        reorder_dta_rows(
            dplyr::group_by(tibble::tibble(x = 1:3), x), 1:3
        ),
        "ordinary base data frame"
    )
})

test_that("reorder_dta_rows validates data.table permutations", {
    skip_if_not_installed("data.table")
    data <- data.table::data.table(x = 1:3)
    expect_error(
        reorder_dta_rows(data, c(1L, 1L, 2L)),
        "every row exactly once"
    )
    expect_error(
        reorder_dta_rows(data, 1:2),
        "every row exactly once"
    )
    expect_error(reorder_dta_rows(data, c(NA_integer_, 2L, 3L)))
    expect_error(reorder_dta_rows(data, c(1L, 2L, 4L)))
    expect_identical(data$x, 1:3)
})
