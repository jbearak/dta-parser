test_that("read_dta selects a compact-preserving output container", {
    skip_if_not_installed("data.table")
    path <- fixture("all_types_v118.dta")

    data <- read_dta(path, output = "data.table")
    expect_s3_class(data, "data.table")
    expect_true(dtatools:::.ordinary_data_table(data))
    expect_true(data.table::truelength(data) > length(data))
    expect_false(is.null(attr(data, ".internal.selfref", exact = TRUE)))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$v_byte))

    previous <- options(dtatools.output = "data.table")
    on.exit(options(previous), add = TRUE)
    expect_s3_class(read_dta(path), "data.table")
    expect_s3_class(read_dta(path, output = "tibble"), "tbl_df")
})

test_that("reader output validation never silently falls back", {
    previous <- options(dtatools.output = "matrix")
    on.exit(options(previous), add = TRUE)
    expect_error(
        read_dta(fixture("auto_v118.dta")),
        "dtatools.output.*tibble.*data.table"
    )
    expect_error(
        read_dta(fixture("auto_v118.dta"), output = "matrix"),
        "one of"
    )
})

test_that("data-table output uses the reader name-repair contract", {
    skip_if_not_installed("data.table")
    native <- structure(
        list(1:2, 3:4), names = c("x", "x"),
        class = "data.frame", row.names = .set_row_names(2L)
    )
    tibble <- dtatools:::.finalize_output_container(
        native, "tibble", "unique"
    )
    table <- dtatools:::.finalize_output_container(
        native, "data.table", "unique"
    )
    expect_identical(names(table), names(tibble))
})

test_that("save_arrow restores tibble and data-table provenance", {
    skip_if_not_installed("data.table")
    paths <- vapply(seq_len(3L), function(...) {
        tempfile(fileext = ".arrow")
    }, character(1))
    on.exit(unlink(paths), add = TRUE)

    table <- data.table::data.table(x = dta_byte(c(1, 2)))
    tibble <- tibble::tibble(x = 1:2)
    frame <- data.frame(x = 1:2)
    expect_silent(save_arrow(table, paths[[1L]]))
    save_arrow(tibble, paths[[2L]])
    save_arrow(frame, paths[[3L]])

    expect_s3_class(read_arrow(paths[[1L]]), "data.table")
    expect_s3_class(read_arrow(paths[[2L]]), "tbl_df")
    expect_s3_class(read_arrow(paths[[1L]], output = "tibble"), "tbl_df")
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(
        read_arrow(paths[[1L]])$x
    ))

    previous <- options(dtatools.output = "data.table")
    on.exit(options(previous), add = TRUE)
    expect_s3_class(read_arrow(paths[[3L]]), "data.table")
    options(dtatools.output = "tibble")
    expect_s3_class(
        read_arrow(paths[[1L]], profile = FALSE, verify = FALSE),
        "tbl_df"
    )
})

test_that("a data.table is never a mutation target", {
    skip_if_not_installed("data.table")
    .datatable.aware <- TRUE
    data <- data.table::data.table(x = 1:3)
    data.table::setkeyv(data, "x")
    alias <- data
    before <- data.table::copy(data)
    effects <- 0L
    touch <- function(value) { effects <<- effects + 1L; value }
    for (operation in list(
        function() gen(data, y = touch(1L)),
        function() repl(data, x = touch(9L), where = 1L),
        function() drop_vars(data, tidyselect::all_of(touch("x"))),
        function() set_var_label(data, x, touch("Label")),
        function() set_dta_note(data, touch(1L), "note"),
        function() reserve_columns(data),
        function() copy_data(data)
    )) {
        expect_error(operation(), "must be a dibble")
    }
    expect_identical(effects, 0L)
    expect_equal(alias, before)
    expect_identical(data.table::key(data), "x")
    expect_true(dtatools:::.ordinary_data_table(data))
    # data.table's own operators remain the way to change a data.table.
    data[, y := x * 2L]
    expect_identical(alias$y, c(2L, 4L, 6L))
    # The assigned conversion is an independent dibble.
    converted <- as_dibble(data)
    gen(converted, z = 1L)
    expect_identical(names(data), c("x", "y"))
})

test_that("edge-shaped data-table output containers keep their dimensions", {
    skip_if_not_installed("data.table")
    zero_columns <- dtatools:::.finalize_output_container(
        structure(list(), class = "data.frame", row.names = .set_row_names(0L)),
        "data.table", "unique"
    )
    expect_identical(dim(zero_columns), c(0L, 0L))

    wide <- dtatools:::.finalize_output_container(
        structure(
            rep(list(1L), 10000L),
            names = sprintf("v%05d", seq_len(10000L)),
            class = "data.frame", row.names = .set_row_names(1L)
        ),
        "data.table", "unique"
    )
    expect_identical(dim(wide), c(1L, 10000L))
})

test_that("writers and read-only operations do not mutate data tables", {
    skip_if_not_installed("data.table")
    data <- data.table::data.table(id = 1:3, value = c(2, 2, 3))
    data.table::setkeyv(data, "id")
    data.table::setindexv(data, "value")
    before <- data.table::copy(data)
    paths <- c(tempfile(fileext = ".dta"), tempfile(fileext = ".arrow"))
    on.exit(unlink(paths), add = TRUE)

    save_dta(data, paths[[1L]])
    expect_silent(save_arrow(data, paths[[2L]]))
    expect_identical(datasig(data), datasig(before))
    expect_identical(as.integer(tab(value, data = data)), c(2L, 1L))
    expect_equal(data, before)
    expect_identical(data.table::key(data), "id")
    expect_identical(data.table::indices(data), "value")
})

test_that("dta_merge follows x or an explicit output container", {
    skip_if_not_installed("data.table")
    table <- data.table::data.table(id = 1:2, x = 3:4)
    data.table::setkeyv(table, "id")
    frame <- data.frame(id = 2:3, y = 5:6)

    from_table <- dta_merge(table, frame, by = "id", relationship = "1:1")
    expect_s3_class(from_table, "data.table")
    expect_null(data.table::key(from_table))
    expect_length(data.table::indices(from_table), 0L)

    from_frame <- dta_merge(frame, table, by = "id", relationship = "1:1")
    expect_s3_class(from_frame, "data.frame", exact = TRUE)
    expect_false(inherits(from_frame, "tbl_df"))

    explicit <- dta_merge(
        frame, table, by = "id", relationship = "1:1",
        output = "data.table"
    )
    expect_s3_class(explicit, "data.table")
})

test_that("dataset metadata never marks a data.table with the frame class", {
    skip_if_not_installed("data.table")
    .datatable.aware <- TRUE
    data <- data.frame(x = dta_byte(c(1, 2)), y = c(3, 4))
    dataset_label(data) <- "Example label"
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    save_dta(data, path)

    result <- read_dta(path, output = "data.table")

    expect_true(dtatools:::.ordinary_data_table(result))
    expect_identical(dataset_label(result), "Example label")

    # data.table's own non-standard evaluation must keep working: the
    # frame marker's `[` method used to intercept `:=` and fail.
    result[, doubled := y * 2]
    expect_identical(as.double(result$doubled), c(6, 8))
})

test_that("dataset metadata setters keep data.table output ordinary", {
    skip_if_not_installed("data.table")
    .datatable.aware <- TRUE
    data <- data.frame(x = dta_byte(c(1, 2)))
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    save_dta(data, path)

    result <- read_dta(path, output = "data.table")
    dataset_label(result) <- "Replaced label"

    expect_true(dtatools:::.ordinary_data_table(result))
    expect_identical(dataset_label(result), "Replaced label")
    result[, extra := 1]
    expect_identical(result$extra, c(1, 1))
})
