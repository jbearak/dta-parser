test_that("slice_stata_rows matches imported Stata column slicing", {
    data <- read_dta(fixture("all_types_v118.dta"))
    class(data) <- "data.frame"
    data <- set_stata_note(data, 4, "dataset note")
    data <- set_stata_characteristic(data, "source", "fixture")
    data <- set_stata_note(data, 7, "variable note", variable = "v_double")
    data <- set_stata_characteristic(
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
            actual <- slice_stata_rows(container, rows)

            expect_identical(actual, expected, info = deparse(rows))
        }
    }
    character_rows <- c("row5", "row2", "row2")
    expect_identical(
        slice_stata_rows(data, character_rows),
        data[character_rows, , drop = FALSE]
    )

    selected <- slice_stata_rows(data, c(5L, 2L, NA_integer_, 2L))
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

test_that("slice_stata_rows preserves every numeric storage and missing tag", {
    values <- c(1, NA_real_, tagged_missing("a"), tagged_missing("z"), -1)
    data <- data.frame(
        byte = stata_byte(values),
        int = stata_int(values),
        long = stata_long(values),
        float = stata_float(values),
        double = stata_double(values)
    )
    data <- set_stata_note(data, 3, "numeric note", variable = "int")
    data <- set_stata_characteristic(
        data, "source", "generated", variable = "int"
    )
    attr(data$float, "label") <- "Float value"
    attr(data$float, "labels") <- c(One = 1, Minus_one = -1)
    attr(data$float, "format.stata") <- "%9.2f"

    rows <- c(4L, 2L, 3L, NA_integer_, 1L, 4L)
    expected <- data[rows, , drop = FALSE]
    actual <- slice_stata_rows(data, rows)

    expect_identical(actual, expected)
    expect_identical(
        vapply(actual, stata_storage_type, character(1)),
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

test_that("slice_stata_rows preserves temporal and ordinary columns", {
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
    actual <- slice_stata_rows(data, rows)

    expect_identical(actual, expected)
    expect_s3_class(actual$dates, "Date")
    expect_s3_class(actual$times, "POSIXct")
    expect_identical(stata_storage_type(actual$dates), "byte")
    expect_identical(stata_storage_type(actual$times), "int")
})

test_that("slice_stata_rows handles named and empty columns", {
    named <- stata_int(c(1, 2, NA_real_, tagged_missing("a"), 5))
    names(named) <- letters[seq_along(named)]
    data <- structure(
        list(named = named),
        class = "data.frame",
        row.names = .set_row_names(length(named))
    )
    rows <- c(5L, 2L, NA_integer_, 2L)

    expect_identical(
        slice_stata_rows(data, rows),
        data[rows, , drop = FALSE]
    )

    empty_columns <- data.frame(row.names = letters[1:4])
    attr(empty_columns, "label") <- "Empty-column dataset"
    expect_identical(
        slice_stata_rows(empty_columns, c(4L, 1L)),
        empty_columns[c(4L, 1L), , drop = FALSE]
    )
    expect_identical(
        slice_stata_rows(data[integer(), , drop = FALSE], integer()),
        data[integer(), , drop = FALSE]
    )
})

test_that("slice_stata_rows slices ordinary data.tables", {
    data <- read_dta(fixture("all_types_v118.dta"), output = "data.table")
    data <- set_stata_note(data, 4, "dataset note")
    data <- set_stata_characteristic(data, "source", "fixture")
    data <- set_stata_note(data, 7, "variable note", variable = "v_double")
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
        actual <- slice_stata_rows(data, rows)

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

    selected <- slice_stata_rows(data, c(5L, 2L, NA_integer_, 2L))
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
        stata_characteristic(selected, "source"), "fixture"
    )
    expect_silent(data.table::set(
        selected, j = "v_byte", value = as.list(selected)$v_byte
    ))

    tagged_table <- data.table::data.table(
        value = stata_int(c(1, NA_real_, tagged_missing("a")))
    )
    tagged <- slice_stata_rows(tagged_table, c(3L, 1L, 2L))
    expect_identical(missing_tag(tagged$value), c("a", NA, NA))
    expect_identical(stata_storage_type(tagged$value), "int")
})

test_that("slice_stata_rows validates its container and locations", {
    expect_error(
        slice_stata_rows(1:3, 1L),
        "must be a base data frame, tibble, or data.table"
    )
    subclass <- structure(
        data.frame(x = 1:3),
        class = c("custom_data_frame", "data.frame")
    )
    expect_error(
        slice_stata_rows(subclass, 1L),
        "ordinary base data frame, tibble, or data.table"
    )
    table_subclass <- data.table::data.table(x = 1:3)
    data.table::setattr(
        table_subclass, "class",
        c("custom_table", class(table_subclass))
    )
    expect_error(
        slice_stata_rows(table_subclass, 1L),
        "ordinary base data frame, tibble, or data.table"
    )
    expect_error(
        slice_stata_rows(data.frame(x = 1:3), 4L),
        "Location 4"
    )
    expect_error(
        slice_stata_rows(data.frame(x = 1:3), "unknown"),
        "doesn't exist"
    )
})

test_that("reorder_stata_rows permutes a data.table in place", {
    data <- read_dta(fixture("all_types_v118.dta"), output = "data.table")
    data.table::setattr(data, "sorted", "v_byte")
    frame <- as.data.frame(data)
    class(frame) <- "data.frame"
    rows <- rev(seq_len(nrow(data)))
    expected <- frame[rows, , drop = FALSE]
    compact_names <- c("v_byte", "v_int", "v_long", "v_float")

    before <- data.table::address(data)
    result <- withVisible(reorder_stata_rows(data, rows))
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
        value = stata_int(c(1, NA_real_, tagged_missing("a")))
    )
    reorder_stata_rows(tagged_table, c(3L, 1L, 2L))
    expect_identical(missing_tag(tagged_table$value), c("a", NA, NA))
    expect_identical(stata_storage_type(tagged_table$value), "int")
})

test_that("reorder_stata_rows validates its container and permutation", {
    frame <- data.frame(x = 1:3)
    expect_error(
        reorder_stata_rows(frame, 1:3),
        "ordinary data.table"
    )
    data <- data.table::data.table(x = 1:3)
    expect_error(
        reorder_stata_rows(data, c(1L, 1L, 2L)),
        "every row exactly once"
    )
    expect_error(
        reorder_stata_rows(data, 1:2),
        "every row exactly once"
    )
    expect_error(reorder_stata_rows(data, c(NA_integer_, 2L, 3L)))
    expect_error(reorder_stata_rows(data, c(1L, 2L, 4L)))
    expect_identical(data$x, 1:3)
})
