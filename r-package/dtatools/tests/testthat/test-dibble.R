dibble_classes <- c("dtatools_ref_data", "tbl_df", "tbl", "data.frame")

test_that("dibble() builds a tibble that carries reference state", {
    data <- dibble(x = 1:3, y = c("a", "b", "c"), .rows = 3)
    state <- dtatools:::.reference_state(data)

    expect_identical(class(data), dibble_classes)
    expect_true(is_dibble(data))
    expect_false(is.null(state))
    expect_identical(state$classes, c("tbl_df", "tbl", "data.frame"))
    expect_identical(state$physical_count, 2L)
    expect_identical(state$generated_count, 0L)
    expect_identical(names(data), c("x", "y"))
    expect_identical(dim(data), c(3L, 2L))
    expect_identical(data$x, 1:3)
    expect_identical(data[["y"]], c("a", "b", "c"))
    expect_identical(
        as.data.frame(data), data.frame(x = 1:3, y = c("a", "b", "c"))
    )

    alias <- data
    gen(data, z = x * 2)
    expect_true(is_dibble(data))
    expect_identical(names(alias), c("x", "y", "z"))
    expect_identical(as.double(alias$z), c(2, 4, 6))

    printed <- capture.output(print(data))
    expect_true(any(grepl("A tibble: 3", printed, fixed = TRUE)))
})

test_that("is_dibble distinguishes dibbles from other reference frames", {
    expect_false(is_dibble(tibble::tibble(x = 1)))
    expect_false(is_dibble(data.frame(x = 1)))
    expect_false(is_dibble(1:3))
    expect_false(is_dibble(NULL))

    frame <- data.frame(x = 1:2)
    gen(frame, y = x + 1)
    expect_s3_class(frame, "dtatools_ref_data")
    expect_false(is_dibble(frame))

    marked <- tibble::tibble(x = 1:2)
    gen(marked, y = x + 1)
    expect_true(is_dibble(marked))
    expect_identical(class(marked), dibble_classes)
})

test_that("as_dibble converts frames, tibbles, and data tables", {
    frame <- data.frame(x = 1:2, y = c("a", "b"))
    attr(frame, "label") <- "frame label"
    from_frame <- as_dibble(frame)
    expect_identical(class(from_frame), dibble_classes)
    expect_identical(attr(from_frame, "label", exact = TRUE), "frame label")
    expect_identical(from_frame$x, 1:2)
    expect_identical(class(frame), "data.frame")

    tbl <- tibble::tibble(x = 1:2)
    from_tibble <- as_dibble(tbl)
    expect_true(is_dibble(from_tibble))
    expect_identical(class(tbl), c("tbl_df", "tbl", "data.frame"))
    expect_identical(from_tibble, as_dibble(from_tibble))

    reference_frame <- data.frame(x = 1:2)
    gen(reference_frame, y = x + 1L)
    from_reference <- as_dibble(reference_frame)
    expect_true(is_dibble(from_reference))
    expect_identical(names(from_reference), c("x", "y"))
    expect_identical(as.double(from_reference$y), c(2, 3))

    expect_error(as_dibble(1:3), "data frame, tibble, or data table")
    expect_error(
        as_dibble(tibble::tibble(a = 1, a = 2, .name_repair = "minimal")),
        "unique, non-missing column names"
    )
    expect_error(
        dibble(a = 1, a = 2, .name_repair = "minimal"),
        "unique, non-missing column names"
    )
})

test_that("as_dibble copies a data table without its runtime state", {
    skip_if_not_installed("data.table")
    table <- data.table::data.table(id = c(2L, 1L), value = c("b", "a"))
    data.table::setkey(table, id)
    data.table::setindex(table, value)
    attr(table, "label") <- "table label"

    converted <- as_dibble(table)
    expect_identical(class(converted), dibble_classes)
    expect_identical(names(converted), c("id", "value"))
    expect_null(attr(converted, ".internal.selfref", exact = TRUE))
    expect_null(attr(converted, "sorted", exact = TRUE))
    expect_null(attr(converted, "index", exact = TRUE))
    expect_identical(attr(converted, "label", exact = TRUE), "table label")
    expect_identical(data.table::key(table), "id")

    gen(converted, doubled = id * 2)
    expect_identical(names(table), c("id", "value"))

    # The dibble owns its columns: a replacement through it leaves the
    # data.table's vectors, and therefore its key, untouched.
    repl(converted, id = c(9L, 8L))
    expect_identical(table$id, c(1L, 2L))
    expect_identical(data.table::key(table), "id")
    # data.table's `[` treats a caller outside a data.table-aware
    # namespace as base `[`, so check the keyed order directly.
    expect_identical(table$value[match(1L, table$id)], "a")
    expect_true(!is.unsorted(table$id))

    subclass <- data.table::data.table(x = 1)
    class(subclass) <- c("custom", class(subclass))
    expect_error(as_dibble(subclass), "ordinary data.table")
})

test_that("dibble construction keeps compact columns unmaterialized", {
    path <- fixture("all_types_v118.dta")
    compact_names <- c("v_byte", "v_int", "v_long", "v_float")
    string_names <- c("v_str5", "v_str20", "v_strL")
    is_compact <- function(data) {
        expect_true(all(vapply(
            compact_names,
            function(name) dtatools:::.is_unmaterialized_numeric_altrep(
                data[[name]]
            ),
            logical(1)
        )))
        expect_true(all(vapply(
            string_names,
            function(name) dtatools:::.is_unmaterialized_dictstring(
                data[[name]]
            ),
            logical(1)
        )))
    }

    read <- read_dta(path)
    expect_true(is_dibble(read))
    is_compact(read)

    tbl <- read_dta(path, output = "tibble")
    is_compact(as_dibble(tbl))
    is_compact(tbl)

    # as.data.frame() on a tibble materializes dictionary strings itself, so
    # the base frame is assembled from the columns directly.
    frame <- vctrs::new_data_frame(as.list(tbl))
    is_compact(frame)
    is_compact(as_dibble(frame))

    is_compact(dibble(!!!as.list(tbl)))

    skip_if_not_installed("data.table")
    table <- read_dta(path, output = "data.table")
    is_compact(as_dibble(table))
    is_compact(table)
})

test_that("grouping keeps a dibble a dibble", {
    data <- dibble(group = c("a", "b", "a"), value = 1:3)

    grouped <- dplyr::group_by(data, group)
    expect_true(is_dibble(grouped))
    expect_s3_class(grouped, "grouped_df")
    expect_identical(
        class(grouped),
        c("dtatools_ref_data", "grouped_df", "tbl_df", "tbl", "data.frame")
    )
    expect_identical(dplyr::group_vars(grouped), "group")
    expect_identical(
        dtatools:::.reference_state(grouped)$classes,
        c("grouped_df", "tbl_df", "tbl", "data.frame")
    )
    expect_true(is_dibble(data))
    expect_false(inherits(data, "grouped_df"))

    summarised <- dplyr::summarise(grouped, total = sum(value))
    expect_identical(summarised$total, c(4L, 2L))

    ungrouped <- dplyr::ungroup(grouped)
    expect_true(is_dibble(ungrouped))
    expect_identical(class(ungrouped), dibble_classes)
    expect_identical(dplyr::group_vars(ungrouped), character())

    from_grouped <- as_dibble(dplyr::group_by(
        tibble::tibble(group = c("a", "b"), value = 1:2), group
    ))
    expect_true(is_dibble(from_grouped))
    expect_identical(dplyr::group_vars(from_grouped), "group")
    expect_identical(
        dplyr::group_vars(dplyr::ungroup(from_grouped)), character()
    )

    # Reconstruction from a grouped dibble template restores dplyr grouping,
    # and other verbs still return plain tibbles.
    expect_identical(
        class(dplyr::filter(grouped, value > 1)),
        c("grouped_df", "tbl_df", "tbl", "data.frame")
    )
    expect_identical(
        class(dplyr::mutate(data, next_value = value + 1L)),
        c("tbl_df", "tbl", "data.frame")
    )
    # Group-wise assignment uses the dplyr groups, and the result stays a
    # grouped dibble.
    gen(grouped, within = .n)
    expect_identical(as.double(grouped$within), c(1, 1, 2))
    expect_true(is_dibble(grouped))
    expect_identical(dplyr::group_vars(grouped), "group")
    expect_error(gen(grouped, again = 1, by = group), "already grouped")
})

test_that("readers, save_arrow, and dta_merge take the dibble container", {
    # This fixture has no notes or characteristics, so the class vector is
    # the bare container's; a file with notes adds the metadata marker.
    path <- fixture("all_types_v118.dta")
    expect_identical(class(read_dta(path)), dibble_classes)
    with_notes <- read_dta(fixture("auto_v118.dta"))
    expect_true(is_dibble(with_notes))
    expect_identical(
        class(with_notes),
        c("dtatools_ref_data", "dtatools_stata_metadata", "tbl_df", "tbl",
          "data.frame")
    )
    expect_identical(
        class(read_dta(path, output = "tibble")),
        c("tbl_df", "tbl", "data.frame")
    )
    expect_identical(class(read_dta(path, output = "dibble")), dibble_classes)
    expect_identical(
        dtatools:::.output_container_choices,
        c("default", "dibble", "tibble", "data.table")
    )
    expect_identical(
        formals(read_dta)$output,
        quote(c("default", "dibble", "tibble", "data.table"))
    )
    expect_identical(formals(read_arrow)$output, formals(read_dta)$output)
    expect_identical(formals(dta_append)$output, formals(read_dta)$output)
    expect_identical(
        formals(dta_merge)$output,
        quote(c("x", "dibble", "tibble", "data.table"))
    )

    withr::local_options(dtatools.output = "tibble")
    expect_identical(
        class(read_dta(path)), c("tbl_df", "tbl", "data.frame")
    )
    withr::local_options(dtatools.output = "dibble")
    read <- read_dta(path)
    expect_identical(class(read), dibble_classes)
    expect_identical(
        attr(with_notes, "label", exact = TRUE), "1978 automobile data"
    )

    arrow_path <- tempfile(fileext = ".arrow")
    on.exit(unlink(arrow_path), add = TRUE)
    save_arrow(read, arrow_path)
    expect_true(is_dibble(read))
    restored <- read_arrow(arrow_path)
    expect_identical(class(restored), dibble_classes)
    expect_identical(
        class(read_arrow(arrow_path, output = "tibble")),
        c("tbl_df", "tbl", "data.frame")
    )
    withr::local_options(dtatools.output = "tibble")
    expect_identical(class(read_arrow(arrow_path)), dibble_classes)
    expect_identical(datasig(restored), datasig(read))

    save_arrow(tibble::tibble(x = 1:2), arrow_path)
    expect_identical(
        class(read_arrow(arrow_path)), c("tbl_df", "tbl", "data.frame")
    )
    expect_identical(
        class(read_arrow(arrow_path, output = "dibble")), dibble_classes
    )

    master <- dibble(id = 1:2, x = c(1, 2))
    using <- dibble(id = 1:2, y = c(3, 4))
    merged <- dta_merge(master, using, by = "id", relationship = "1:1")
    expect_identical(class(merged), dibble_classes)
    expect_identical(names(merged), c("id", "x", "y", "_merge"))
    expect_true(is_dibble(master))
    expect_identical(
        class(dta_merge(
            tibble::tibble(id = 1:2, x = 1), using, by = "id",
            relationship = "1:1"
        )),
        c("tbl_df", "tbl", "data.frame")
    )
    expect_identical(
        class(dta_merge(
            tibble::tibble(id = 1:2, x = 1), using, by = "id",
            relationship = "1:1", output = "dibble"
        )),
        dibble_classes
    )
    expect_identical(
        class(dta_merge(
            master, using, by = "id", relationship = "1:1",
            output = "tibble"
        )),
        c("tbl_df", "tbl", "data.frame")
    )

    # The option is "tibble" here, so file sources follow it; the default
    # and an explicit request both produce dibbles.
    expect_identical(
        class(dta_append(list(path, path))), c("tbl_df", "tbl", "data.frame")
    )
    expect_identical(
        class(dta_append(list(path, path), output = "dibble")), dibble_classes
    )
    withr::local_options(dtatools.output = NULL)
    expect_identical(class(dta_append(list(path, path))), dibble_classes)
    expect_identical(class(dta_append(list(master, using))), dibble_classes)
    expect_identical(
        class(dta_append(list(master, using), output = "tibble")),
        c("tbl_df", "tbl", "data.frame")
    )
})

test_that("a file recording an unknown container still reads", {
    skip_if_not_installed("arrow")
    path <- tempfile(fileext = ".arrow")
    future <- tempfile(fileext = ".arrow")
    on.exit(unlink(c(path, future)), add = TRUE)
    save_arrow(dibble(x = 1:2), path)
    # Rewrite the recorded container to a value this release does not
    # know, as a file from a newer dtatools might carry. The copy goes to
    # a second path: arrow memory-maps the source, so overwriting it in
    # place is refused on Windows and reads back zeros elsewhere.
    table <- arrow::read_ipc_file(path, as_data_frame = FALSE)
    metadata <- table$metadata
    key <- grep("dataset", names(metadata), value = TRUE)[[1L]]
    metadata[[key]] <- sub(
        "\"output_container\":\"dibble\"",
        "\"output_container\":\"matrix\"", metadata[[key]], fixed = FALSE
    )
    expect_true(grepl("matrix", metadata[[key]], fixed = TRUE))
    table$metadata <- metadata
    arrow::write_ipc_file(table, future, compression = "uncompressed")
    restored <- read_arrow(future, verify = FALSE)
    expect_false(is_dibble(restored))
    expect_identical(class(restored), c("tbl_df", "tbl", "data.frame"))
    expect_identical(restored$x, 1:2)
})

test_that("unknown stored containers fall back to a tibble", {
    expect_identical(
        dtatools:::.normalize_output_container("default", stored = "matrix"),
        "tibble"
    )
    expect_identical(
        dtatools:::.normalize_output_container("default", stored = "dibble"),
        "dibble"
    )
    expect_identical(
        dtatools:::.normalize_output_container("default", stored = NULL),
        "dibble"
    )
    expect_identical(
        dtatools:::.normalize_output_container("tibble", stored = "dibble"),
        "tibble"
    )
    withr::local_options(dtatools.output = "matrix")
    expect_error(
        dtatools:::.normalize_output_container("default"),
        "dibble.*tibble.*data.table"
    )
})
