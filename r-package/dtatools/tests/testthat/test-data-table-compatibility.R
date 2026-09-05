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

test_that("gen installs a physical data-table column", {
    skip_if_not_installed("data.table")
    .datatable.aware <- TRUE
    data <- data.table::data.table(x = 1:3)
    alias <- data

    expect_identical(expect_invisible(gen(data, y, x * 2)), data)
    expect_false(inherits(data, "dtatools_ref_data"))
    expect_identical(names(data), c("x", "y"))
    expect_identical(as.double(data$y), c(2, 4, 6))
    expect_identical(names(alias), c("x", "y"))

    data[, z := y + 1]
    data.table::set(data, j = "w", value = data$z + 1)
    data.table::setnames(data, "w", "renamed")
    data.table::setcolorder(data, c("renamed", "x", "y", "z"))
    subset <- data[y >= 4]
    expect_identical(names(data), c("renamed", "x", "y", "z"))
    expect_identical(subset$x, 2:3)
})

test_that("repl invalidates only affected data-table lookup state", {
    skip_if_not_installed("data.table")
    data <- data.table::data.table(
        key_column = 1:4,
        indexed = letters[1:4],
        compound = 11:14,
        ordinary = 21:24
    )
    data.table::setkeyv(data, "key_column")
    data.table::setindexv(data, "indexed")
    data.table::setindexv(data, c("compound", "ordinary"))

    repl(data, ordinary, 99L, where = 1L)
    expect_identical(data.table::key(data), "key_column")
    expect_identical(data.table::indices(data, vectors = TRUE), list("indexed"))

    data.table::setindexv(data, c("compound", "ordinary"))
    repl(data, indexed, "z", where = 1L)
    expect_identical(
        data.table::indices(data, vectors = TRUE),
        list(c("compound", "ordinary"))
    )

    repl(data, key_column, 100L, where = 1L)
    expect_null(data.table::key(data))
    expect_identical(data$key_column, c(100L, 2:4))
})

test_that("repl retains aliases and copy_data isolates data tables", {
    skip_if_not_installed("data.table")
    data <- data.table::data.table(x = 1:3)
    data.table::setkeyv(data, "x")
    alias <- data
    column_alias <- data$x
    isolated <- copy_data(data)

    repl(data, x, 9L, where = 1L)
    expect_identical(alias$x, c(9L, 2L, 3L))
    expect_identical(column_alias, 1:3)
    expect_identical(isolated$x, 1:3)
    expect_identical(data.table::key(isolated), "x")
    expect_false(is.null(attr(isolated, ".internal.selfref", exact = TRUE)))
})

test_that("whole-table mutations reject data-table subclasses", {
    skip_if_not_installed("data.table")
    data <- data.table::data.table(x = 1:2)
    class(data) <- c("custom_table", class(data))

    expect_error(gen(data, y, x), "ordinary data.table")
    expect_error(repl(data, x, 1L), "ordinary data.table")
    expect_error(drop_vars(data, x), "ordinary data.table")
    expect_error(copy_data(data), "ordinary data.table")
})

test_that("metadata changes preserve data-table lookup state", {
    skip_if_not_installed("data.table")
    data <- data.table::data.table(id = 1:3, value = 4:6)
    data.table::setkeyv(data, "id")
    data.table::setindexv(data, "value")

    data <- set_var_label(data, value, "Value")
    data <- set_val_labels(data, value = c(Four = 4))
    data <- set_dta_note(data, 1L, "dataset note")
    dataset_label(data) <- "Dataset"

    expect_s3_class(data, "data.table")
    expect_identical(data.table::key(data), "id")
    expect_identical(data.table::indices(data), "value")
    expect_false(is.null(attr(data, ".internal.selfref", exact = TRUE)))
    expect_identical(var_label(data$value), "Value")
    expect_identical(val_labels(data$value), c(Four = 4))
})

test_that("keep and drop preserve unaffected data-table lookup state", {
    skip_if_not_installed("data.table")
    data <- data.table::data.table(id = 1:3, indexed = 3:1, discard = 4:6)
    data.table::setkeyv(data, "id")
    data.table::setindexv(data, "indexed")

    drop_vars(data, discard)
    expect_identical(data.table::key(data), "id")
    expect_identical(data.table::indices(data), "indexed")
    data.table::set(data, j = "later", value = 7:9)
    expect_identical(names(data), c("id", "indexed", "later"))
})

test_that("repaired and edge-shaped data tables remain usable", {
    skip_if_not_installed("data.table")
    restored <- unserialize(serialize(
        data.table::data.table(x = 1:2), NULL
    ))
    data.table::setalloccol(restored)
    gen(restored, y, x + 1)
    repl(restored, x, 9L, where = 1L)
    expect_identical(restored$x, c(9L, 2L))
    expect_identical(as.double(restored$y), c(2, 3))

    empty <- data.table::data.table(x = integer())
    gen(empty, y, integer())
    expect_identical(dim(empty), c(0L, 2L))

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

test_that("setDT() on a read result drops the stale reference state", {
    skip_if_not_installed("data.table")
    .datatable.aware <- TRUE
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    save_dta(data.frame(hh1 = dta_long(1:3)), path)

    data <- read_dta(path, encoding = "UTF-8")
    # The regression needs a real dibble going in, or the case below
    # would pass without ever exercising a stale mark.
    expect_true(inherits(data, "dtatools_ref_data"))
    expect_true(is.environment(
        attr(data, ".dtatools_ref_state", exact = TRUE)
    ))
    data.table::setDT(data)

    # `setDT()` rewrites the class in place and leaves the mark behind,
    # so the mutators must judge the object by its class alone.
    expect_false(inherits(data, "dtatools_ref_data"))
    expect_null(dtatools:::.reference_state(data))

    gen(data, cluster = NA_real_)
    expect_identical(names(data), c("hh1", "cluster"))
    set_var_label(data, cluster, "Cluster ID")
    expect_identical(var_label(data, cluster), "Cluster ID")
    repl(data, cluster = hh1)
    expect_identical(as.double(data$cluster), c(1, 2, 3))
    expect_true(dtatools:::.ordinary_data_table(data))
})

test_that("promotion invalidates affected data-table keys and indexes", {
    skip_if_not_installed("data.table")
    .datatable.aware <- TRUE
    keyed <- data.table::data.table(x = dta_byte(1:3), y = 11:13)
    data.table::setkeyv(keyed, "x")
    alias <- keyed
    suppressMessages(repl(keyed, x = 1000, where = x == 1))
    expect_null(data.table::key(keyed))
    expect_null(data.table::key(alias))
    expect_identical(keyed[list(1000), on = "x"]$y, 11L)
    expect_identical(dta_storage_type(keyed$x), "int")

    indexed <- data.table::data.table(
        x = dta_byte(c(3, 1, 2)), y = 11:13, z = c(3, 1, 2)
    )
    data.table::setindexv(indexed, "x")
    data.table::setindexv(indexed, "z")
    suppressMessages(repl(indexed, x = 1000, where = x == 1))
    expect_identical(data.table::indices(indexed), "z")
    expect_identical(indexed[x == 1000]$y, 12L)
    expect_identical(indexed[z == 1]$y, 12L)

    strings <- data.table::data.table(x = dta_string(c("a", "b")), y = 1:2)
    data.table::setkeyv(strings, "x")
    suppressMessages(repl(strings, x = "wide", where = 1L))
    expect_null(data.table::key(strings))
    expect_identical(strings[list("wide"), on = "x"]$y, 1L)
})

test_that("clearing a replaced data-table key preserves unrelated indexes", {
    skip_if_not_installed("data.table")
    .datatable.aware <- TRUE
    for (replacement in c(5, 1000)) {
        data <- data.table::data.table(x = dta_byte(1:3), z = c(3L, 1L, 2L))
        data.table::setkeyv(data, "x")
        data.table::setindexv(data, "z")
        suppressMessages(repl(data, x = replacement, where = 1L))
        expect_null(data.table::key(data))
        expect_identical(data.table::indices(data), "z")
        expect_identical(as.integer(data[z == 3L]$x), as.integer(replacement))
        data.table::setkeyv(data, "x")
        data.table::setindexv(data, "z")
        suppressMessages(repl(data, x = replacement, where = x == 2))
        expect_null(data.table::key(data))
        expect_identical(data.table::indices(data), "z")
        expect_identical(as.integer(data[z == 1L]$x), as.integer(replacement))
    }
})


test_that("strict zero-row replacement preserves data-table lookup state", {
    skip_if_not_installed("data.table")
    .datatable.aware <- TRUE
    for (typed in c(FALSE, TRUE)) {
        data <- data.table::data.table(
            x = if (typed) dta_byte(1:3) else 1:3, z = c(3L, 1L, 2L)
        )
        data.table::setkeyv(data, "x")
        data.table::setindexv(data, "z")
        alias <- data
        for (selected in list(FALSE, integer())) {
            repl(data, x = 5L, where = selected, promote = FALSE)
            expect_identical(data.table::key(data), "x")
            expect_identical(data.table::indices(data), "z")
            expect_identical(data.table::key(alias), "x")
            expect_identical(as.integer(data$x), 1:3)
        }
    }
})
