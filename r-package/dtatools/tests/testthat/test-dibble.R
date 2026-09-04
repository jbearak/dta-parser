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
    # Every column of a dibble carries Stata storage from construction.
    expect_identical(dta_storage_type(data$x), "long")
    expect_identical(as.integer(data$x), 1:3)
    expect_identical(attr(data[["y"]], "stata.string.storage"), "str1")
    expect_identical(as.character(data[["y"]]), c("a", "b", "c"))
    plain <- as.data.frame(data)
    expect_identical(class(plain), "data.frame")
    expect_identical(as.integer(plain$x), 1:3)

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
    expect_identical(dta_storage_type(from_frame$x), "long")
    expect_identical(as.integer(from_frame$x), 1:2)
    # The source is untouched: its columns stay bare R vectors.
    expect_identical(class(frame), "data.frame")
    expect_identical(frame$x, 1:2)

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
    expect_true(is_dibble(summarised))
    expect_identical(as.integer(summarised$total), c(4L, 2L))

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

    # A dibble is closed under dplyr verbs: reconstruction from a grouped
    # dibble template gives a grouped dibble, and from an ungrouped one a
    # dibble.
    expect_identical(
        class(dplyr::filter(grouped, value > 1)),
        c("dtatools_ref_data", "grouped_df", "tbl_df", "tbl", "data.frame")
    )
    expect_identical(class(dplyr::filter(data, value > 1)), dibble_classes)
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
    # The column was typed when the dibble was built, so the file holds a
    # Stata long and the tibble reads it back as one.
    expect_identical(dta_storage_type(restored$x), "long")
    expect_identical(as.integer(restored$x), 1:2)
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

test_that("dataset metadata setters keep a dibble's bracket dispatch", {
    data <- set_dta_note(dibble(x = 1:2), 1, "a note")
    expect_true(is_dibble(data))
    expect_identical(class(data)[[1L]], "dtatools_ref_data")
    expect_s3_class(data, "dtatools_stata_metadata")
    data[x > 1, y := 9]
    expect_identical(as.double(data$y), c(NA, 9))
    expect_identical(dta_notes(data)[[1L]], "a note")
    # The snapshot still carries the marker, so a subset keeps the notes.
    subset <- data[1, ]
    expect_s3_class(subset, "dtatools_stata_metadata")
    expect_identical(dta_notes(subset)[[1L]], "a note")
    variable_scoped <- set_dta_note(dibble(x = 1:2), 1, "on x", variable = "x")
    expect_true(is_dibble(variable_scoped))
    variable_scoped[x > 1, y := 5]
    expect_identical(as.double(variable_scoped$y), c(NA, 5))
    expect_identical(dta_notes(variable_scoped, "x")[[1L]], "on x")
    with_characteristic <- set_dta_characteristic(dibble(x = 1), "k", "v")
    expect_identical(class(with_characteristic)[[1L]], "dtatools_ref_data")
    with_characteristic[, z := 1]
    expect_identical(as.double(with_characteristic$z), 1)
})

test_that("slice_dta_rows accepts the default read container", {
    path <- fixture("auto_v118.dta")
    data <- read_dta(path)
    expect_true(is_dibble(data))
    sliced <- slice_dta_rows(data, 1:2)
    expect_true(is_dibble(sliced))
    expect_identical(nrow(sliced), 2L)
    expect_identical(
        as.data.frame(sliced),
        as.data.frame(slice_dta_rows(read_dta(path, output = "tibble"), 1:2))
    )
    expect_identical(dta_notes(sliced), dta_notes(data))
    gen(data, flag = 1)
    marked <- data.frame(x = 1:3)
    gen(marked, y = x)
    plain <- slice_dta_rows(marked, 2:3)
    expect_identical(class(plain), "data.frame")
    expect_identical(as.double(plain$y), c(2, 3))
})

test_that("dataset-scoped metadata setters give a dibble its own state", {
    data <- read_dta(fixture("auto_v118.dta"))
    changed <- set_dta_note(data, 1, "note")
    expect_true(is_dibble(changed))
    expect_identical(dta_notes(changed), c(`1` = "note"))
    gen(changed, y = 1)
    expect_true("y" %in% names(changed))
    expect_false("y" %in% names(data))
    gen(data, z = 2)
    expect_false("z" %in% names(changed))
    expect_identical(dta_notes(data), dta_notes(read_dta(fixture("auto_v118.dta"))))
})

test_that("slicing a grouped dibble keeps dataset metadata", {
    data <- dplyr::group_by(read_dta(fixture("auto_v118.dta")), foreign)
    sliced <- slice_dta_rows(data, 1:3)
    expect_true(is_dibble(sliced))
    expect_identical(dplyr::group_vars(sliced), "foreign")
    expect_identical(attr(sliced, "label"), attr(data, "label"))
    expect_identical(dta_notes(sliced), dta_notes(data))
    expect_identical(nrow(sliced), 3L)
})

test_that("slice_dta_rows keeps a grouped dibble's grouping", {
    data <- dplyr::group_by(dibble(g = c(1, 1, 2, 2), x = 1:4), g)
    sliced <- slice_dta_rows(data, c(2L, 4L))
    expect_true(is_dibble(sliced))
    expect_identical(dplyr::group_vars(sliced), "g")
    expect_identical(as.double(sliced$x), c(2, 4))
    expect_identical(dplyr::group_size(sliced), c(1L, 1L))
    repl(sliced, x = .N)
    expect_identical(as.double(sliced$x), c(1, 1))
    expect_identical(dplyr::group_vars(data), "g")
    expect_identical(nrow(data), 4L)
})

test_that("mutate and transmute type new columns as gen() does", {
    data <- dibble(
        id = 1:3, income = c(10, 20, 30), name = c("a", "bb", "ccc")
    )
    result <- dplyr::mutate(
        data,
        flag = id > 1,
        count = id * 2L,
        adjusted = income * 1.1,
        declared = dta_int(id),
        day = as.Date("2024-01-01") + id,
        stamp = as.POSIXct("2024-01-01 12:00:00", tz = "UTC") + id,
        label = paste0(name, "!"),
        kind = factor(name)
    )
    expect_true(is_dibble(result))
    expect_identical(class(result), dibble_classes)
    # The input follows copy-on-modify: nothing was added to it.
    expect_identical(names(data), c("id", "income", "name"))
    expect_true(is_dibble(data))

    # One mapping from bare R vectors: logical stays logical, integer
    # is long, double is double, Date is a float date, POSIXct a double
    # datetime, character the smallest fitting width.
    expect_identical(result$flag, c(FALSE, TRUE, TRUE))
    expect_identical(dta_storage_type(result$count), "long")
    expect_identical(dta_storage_type(result$adjusted), "double")
    expect_identical(dta_storage_type(result$declared), "int")
    expect_identical(dta_storage_type(result$day), "float")
    expect_s3_class(result$day, "stata_date")
    expect_identical(dta_storage_type(result$stamp), "double")
    expect_s3_class(result$stamp, "stata_datetime")
    expect_identical(
        attr(result$label, "stata.string.storage", exact = TRUE), "str4"
    )
    expect_true(is.factor(result$kind))
    expect_identical(as.double(result$adjusted), c(11, 22, 33))

    # The result matches what gen() gives the same expression.
    generated <- dibble(id = 1:3)
    gen(generated, count = id * 2L)
    expect_identical(
        attributes(result$count), attributes(generated$count)
    )

    # Input columns the verb leaves alone are the same vectors.
    expect_identical(result$id, data$id)
    expect_identical(result$income, data$income)
    expect_identical(result$name, data$name)

    # A changed column keeps its storage when the new values fit and is
    # widened to the narrowest storage that holds them exactly otherwise;
    # a declared column that arithmetic preserved keeps its storage.
    changed <- dplyr::mutate(
        result,
        declared = declared + 1L, id = id + 0.5, name = paste0(name, "xyz")
    )
    expect_identical(dta_storage_type(changed$declared), "int")
    expect_identical(dta_storage_type(changed$id), "double")
    expect_identical(
        attr(changed$name, "stata.string.storage", exact = TRUE), "str6"
    )
    narrowed <- dplyr::mutate(dibble(x = c(100000, 2)), x = c(1, 2))
    expect_identical(dta_storage_type(narrowed$x), "double")
    widened <- dplyr::mutate(dibble(x = dta_byte(1:3)), x = x * 1000L)
    expect_identical(dta_storage_type(widened$x), "int")
    fractional <- dplyr::mutate(dibble(x = dta_int(1:3)), x = x + 0.5)
    expect_identical(dta_storage_type(fractional$x), "float")
    huge <- dplyr::mutate(dibble(x = dta_long(1:3)), x = x + 2^40)
    expect_identical(dta_storage_type(huge$x), "double")

    transmuted <- dplyr::transmute(data, doubled = income * 2)
    expect_true(is_dibble(transmuted))
    expect_identical(names(transmuted), "doubled")
    expect_identical(dta_storage_type(transmuted$doubled), "double")

    # The verb's result is a dibble, so bracket assignment follows on.
    transmuted[doubled > 20, big := 1]
    expect_identical(as.double(transmuted$big), c(NA, 1, 1))

    # Long strings take strL. Columns no Stata storage can hold pass
    # through unchanged; save_dta() refuses them, as it does today.
    long <- dplyr::mutate(data, text = strrep("x", 3000))
    expect_identical(
        attr(long$text, "stata.string.storage", exact = TRUE), "strL"
    )
    carried <- dplyr::mutate(
        data,
        span = as.difftime(as.double(id), units = "days"),
        listed = as.list(id), bytes = as.raw(id)
    )
    expect_true(is_dibble(carried))
    expect_s3_class(carried$span, "difftime")
    expect_type(carried$listed, "list")
    expect_type(carried$bytes, "raw")
    expect_error(gen(data, span = as.difftime(1, units = "days")))

    # A grouped dibble stays grouped and evaluates within groups.
    grouped <- dplyr::group_by(dibble(g = c(1, 1, 2), v = c(1, 2, 3)), g)
    per_group <- dplyr::mutate(grouped, total = sum(v))
    expect_true(is_dibble(per_group))
    expect_identical(dplyr::group_vars(per_group), "g")
    expect_identical(as.double(per_group$total), c(3, 3, 3))
    expect_identical(dta_storage_type(per_group$total), "double")

    # A base frame carrying reference state is not a dibble and gets the
    # ordinary result.
    frame <- data.frame(x = 1:2)
    gen(frame, y = x + 1L)
    plain <- dplyr::mutate(frame, z = 1)
    expect_identical(class(plain), "data.frame")
    expect_identical(plain$z, c(1, 1))
})

test_that("mutate keeps untouched compact columns compact", {
    data <- read_dta(fixture("all_types_v118.dta"))
    result <- dplyr::mutate(data, extra = 1)
    expect_true(is_dibble(result))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(result$v_byte))
    expect_true(dtatools:::.is_unmaterialized_dictstring(result$v_str5))
    expect_identical(dta_storage_type(result$extra), "double")
    expect_identical(
        attributes(result$v_int), attributes(data$v_int)
    )
})

test_that("a dibble is closed under dataset operations", {
    data <- dibble(id = 1:3, x = c(1.5, 2, 3), s = c("a", "b", "c"))
    other <- tibble::tibble(id = 1:3, z = c(TRUE, FALSE, TRUE))
    closed <- list(
        arrange = dplyr::arrange(data, dplyr::desc(x)),
        select = dplyr::select(data, x),
        slice = dplyr::slice(data, 1:2),
        relocate = dplyr::relocate(data, s),
        rename = dplyr::rename(data, value = x),
        distinct = dplyr::distinct(data, s),
        summarise = dplyr::summarise(data, n = dplyr::n()),
        left_join = dplyr::left_join(data, other, by = "id"),
        bind_rows = dplyr::bind_rows(data, data),
        subset = subset(data, x > 1),
        transform = transform(data, w = x + 1),
        within = within(data, w <- x + 1),
        head = head(data, 2),
        rbind = rbind(data, data),
        cbind = cbind(data, extra = 10:12),
        bracket_rows = data[1:2, ],
        bracket_cols = data[c("id", "s")]
    )
    for (name in names(closed)) {
        expect_true(is_dibble(closed[[name]]), info = name)
    }
    # New columns from base verbs and joins carry Stata storage; the
    # logical from the join stays logical.
    expect_identical(dta_storage_type(closed$transform$w), "double")
    expect_identical(dta_storage_type(closed$within$w), "double")
    expect_identical(dta_storage_type(closed$cbind$extra), "long")
    expect_identical(closed$left_join$z, other$z)
    expect_identical(dta_storage_type(closed$summarise$n), "long")
    # Non-dataset results are returned as they are.
    expect_identical(with(data, sum(as.double(x))), 6.5)
    expect_identical(as.list(data)$s, data$s)
})

test_that("replacement operators type their columns and keep the dibble", {
    data <- dibble(id = 1:3)
    data$score <- c(1.5, 2, 3)
    data[["count"]] <- 4:6
    data[["flag"]] <- c(TRUE, NA, FALSE)
    data[, "text"] <- c("x", "yy", "zzz")
    expect_true(is_dibble(data))
    expect_identical(dta_storage_type(data$score), "double")
    expect_identical(dta_storage_type(data$count), "long")
    expect_identical(data$flag, c(TRUE, NA, FALSE))
    expect_identical(
        attr(data$text, "stata.string.storage", exact = TRUE), "str3"
    )
    # Overwriting keeps fitting storage and widens otherwise.
    data$count <- c(1L, 2L, 3L)
    expect_identical(dta_storage_type(data$count), "long")
    data$id <- data$id + 0.5
    expect_identical(dta_storage_type(data$id), "double")
    names(data)[1] <- "key"
    expect_true(is_dibble(data))
    expect_identical(names(data)[1], "key")
    # A tibble that becomes a dibble at its first gen() types its
    # existing columns for every binding.
    tbl <- tibble::tibble(n = 1:2, s = c("a", "b"), keep = c(TRUE, FALSE))
    alias <- tbl
    gen(tbl, y = n * 2L)
    expect_true(is_dibble(tbl))
    expect_identical(dta_storage_type(alias$n), "long")
    expect_identical(attr(alias$s, "stata.string.storage"), "str1")
    expect_identical(alias$keep, c(TRUE, FALSE))
})

test_that("logical columns stay logical in a dibble", {
    data <- dibble(flag = c(TRUE, FALSE, TRUE), x = 1:3)
    expect_identical(data$flag, c(TRUE, FALSE, TRUE))
    expect_identical(nrow(dplyr::filter(data, flag)), 2L)
    gen(data, y = 1, where = flag)
    expect_identical(as.double(data$y), c(1, NA, 1))
    data[flag, z := x]
    expect_identical(as.double(data$z), c(1, NA, 3))
    gen(data, w = x > 1)
    expect_identical(data$w, c(FALSE, TRUE, TRUE))
    gen(data, v = TRUE, where = x == 2)
    expect_identical(data$v, c(NA, TRUE, NA))
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    save_dta(data, path)
    expect_identical(dta_storage_type(read_dta(path)$flag), "byte")
})

test_that("Arrow strings enter a dibble compact with an inferred width", {
    skip_if_not_installed("arrow")
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data.frame(text = c("alpha", "b", "alpha"), n = 1:3), path)
    data <- read_arrow(path)
    expect_true(is_dibble(data))
    expect_s3_class(data$text, "stata_string")
    expect_identical(attr(data$text, "stata.string.storage"), "str5")
    expect_true(dtatools:::.is_unmaterialized_dictstring(data$text))
    expect_identical(dta_storage_type(data$n), "long")
    # Plain Arrow files, and unprofiled reads, carry no Stata semantics
    # and default to a tibble; an explicit dibble request types them.
    plain <- tempfile(fileext = ".arrow")
    on.exit(unlink(plain), add = TRUE)
    arrow::write_ipc_file(data.frame(x = 1:2), plain)
    expect_identical(class(read_arrow(plain)), c("tbl_df", "tbl", "data.frame"))
    expect_identical(read_arrow(plain)$x, 1:2)
    typed <- read_arrow(plain, output = "dibble")
    expect_true(is_dibble(typed))
    expect_identical(dta_storage_type(typed$x), "long")
    expect_identical(
        class(read_arrow(path, profile = FALSE)),
        c("tbl_df", "tbl", "data.frame")
    )
})

test_that("Stata numerics coerce to integer and logical and add to dates", {
    long <- dta_long(c(1, 2, tagged_missing("a")))
    expect_identical(as.integer(long), c(1L, 2L, NA))
    expect_identical(vctrs::vec_cast(long, integer()), c(1L, 2L, NA))
    expect_identical(as.logical(dta_byte(c(1, 0, NA))), c(TRUE, FALSE, NA))
    day <- as.Date("2024-01-01")
    expect_identical(day + dta_long(1:2), day + 1:2)
    expect_identical(dta_long(1:2) + day, day + 1:2)
    stamp <- as.POSIXct("2024-01-01", tz = "UTC")
    expect_identical(stamp + dta_int(60), stamp + 60)
})

test_that("bracket assignment and partial replacement promote storage", {
    data <- dibble(x = dta_byte(c(1, 2)), s = c("a", "b"), n = 1:2)
    data[, x := 1000L]
    expect_identical(dta_storage_type(data$x), "int")
    expect_identical(as.double(data$x), c(1000, 1000))
    data[1, x := 100000L]
    expect_identical(dta_storage_type(data$x), "long")
    expect_identical(as.double(data$x), c(100000, 1000))
    # 100000 and 0.5 both fit float exactly, so float is the narrowest.
    data[2, x := 0.5]
    expect_identical(dta_storage_type(data$x), "float")
    data[1, x := 0.1]
    expect_identical(dta_storage_type(data$x), "double")
    data[1, s := "longer"]
    expect_identical(attr(data$s, "stata.string.storage"), "str6")
    expect_identical(as.character(data$s), c("longer", "b"))
    # A fitting value keeps the storage and the compact path.
    compact <- dibble(x = dta_byte(1:3))
    compact[2, x := 9L]
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact$x))
    expect_identical(dta_storage_type(compact$x), "byte")
    # replace_values() stays strict.
    expect_error(replace_values(compact, x, 1000L, where = 1), "byte")
    # Cell assignment through `[<-` promotes too, and untouched compact
    # columns keep their vectors.
    cells <- dibble(x = dta_byte(c(1, 2)), y = dta_byte(c(3, 4)),
                    s = c("a", "b"))
    y_before <- cells$y
    cells[1, "x"] <- 1000L
    expect_true(is_dibble(cells))
    expect_identical(dta_storage_type(cells$x), "int")
    expect_identical(as.double(cells$x), c(1000, 2))
    expect_identical(cells$y, y_before)
    cells[2, "s"] <- "long"
    expect_identical(attr(cells$s, "stata.string.storage"), "str4")
    expect_identical(as.character(cells$s), c("a", "long"))
    cells[1, "y"] <- 5L
    expect_identical(dta_storage_type(cells$y), "byte")
    expect_error(cells[1, "x"] <- "text")
    # Subscripts are evaluated once, even when the promoting retry runs.
    counter <- 0L
    pick <- function() {
        counter <<- counter + 1L
        counter
    }
    once <- dibble(x = dta_byte(c(1, 2, 3)))
    once[pick(), "x"] <- 1000L
    expect_identical(counter, 1L)
    expect_identical(as.double(once$x), c(1000, 2, 3))
    once[pick(), ] <- list(5L)
    expect_identical(counter, 2L)
    expect_identical(as.double(once$x), c(1000, 5, 3))
    # A `NULL` subscript selects nothing, as it does on a tibble.
    none <- NULL
    once[none, "x"] <- 9L
    expect_identical(as.double(once$x), c(1000, 5, 3))
    once[1, none] <- 9L
    expect_identical(as.double(once$x), c(1000, 5, 3))
})

test_that("gen and := accept factors as mutate does", {
    data <- dibble(x = 1:3)
    gen(data, f = factor(c("a", "b", "a")))
    expect_s3_class(data$f, "factor")
    expect_identical(levels(data$f), c("a", "b"))
    expect_identical(as.character(data$f), c("a", "b", "a"))
    data[x > 1L, g := factor("z")]
    expect_s3_class(data$g, "factor")
    expect_identical(as.character(data$g), c(NA, "z", "z"))
    labelled <- factor(c("lo", "hi", "lo"), levels = c("lo", "hi"))
    attr(labelled, "label") <- "Level"
    gen(data, h = labelled)
    expect_identical(attr(data$h, "label"), "Level")
    expect_identical(levels(data$h), c("lo", "hi"))
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    save_dta(data, path)
    back <- read_dta(path)
    expect_identical(dta_storage_type(back$f), "long")
    expect_identical(as.double(back$f), c(1, 2, 1))
    expect_identical(as.double(back$g), c(NA, 1, 1))
})

test_that("computed distinct and group_by type columns as mutate does", {
    data <- dibble(x = dta_byte(1:3), s = c("a", "b", "a"))
    unique_wide <- dplyr::distinct(data, x = 1000L)
    expect_true(is_dibble(unique_wide))
    expect_identical(dta_storage_type(unique_wide$x), "int")
    keyed <- dplyr::group_by(data, x = 1000L)
    expect_true(is_dibble(keyed))
    expect_identical(dta_storage_type(keyed$x), "int")
    fresh <- dplyr::group_by(data, big = as.integer(x) * 1000L)
    expect_identical(dta_storage_type(fresh$big), "long")
    expect_identical(dplyr::group_vars(fresh), "big")
    by_flag <- dplyr::distinct(data, flag = x > 1, .keep_all = TRUE)
    expect_identical(by_flag$flag, c(FALSE, TRUE))
    expect_identical(dta_storage_type(by_flag$x), "byte")
})

test_that("a logical overwriting a Stata numeric keeps its storage", {
    data <- dibble(x = dta_byte(1:3), n = dta_long(1:3))
    flagged <- dplyr::mutate(data, x = x > 1)
    expect_identical(dta_storage_type(flagged$x), "byte")
    expect_identical(as.double(flagged$x), c(0, 1, 1))
    data$n <- c(TRUE, FALSE, NA)
    expect_identical(dta_storage_type(data$n), "long")
    expect_identical(as.double(data$n), c(1, 0, NA))
    data[, x := x == 2]
    expect_identical(dta_storage_type(data$x), "byte")
    expect_identical(as.double(data$x), c(0, 1, 0))
    # A logical replacing a logical, a date, or a factor stays logical.
    mixed <- dibble(flag = c(TRUE, FALSE), day = as.Date("2024-01-01") + 0:1)
    mixed <- dplyr::mutate(
        mixed, flag = !flag, day = day > as.Date("2024-01-01")
    )
    expect_identical(mixed$flag, c(FALSE, TRUE))
    expect_identical(mixed$day, c(FALSE, TRUE))
})

test_that("overwriting a typed column with an untypable one passes through", {
    data <- dibble(x = 1:3, s = c("a", "b", "c"))
    listed <- dplyr::mutate(data, x = as.list(as.integer(x)))
    expect_type(listed$x, "list")
    spanned <- dplyr::mutate(
        data, x = as.difftime(as.double(x), units = "days")
    )
    expect_s3_class(spanned$x, "difftime")
    data$s <- as.raw(1:3)
    expect_type(data$s, "raw")
    expect_true(is_dibble(data))
})

test_that("reframe, group_modify, and nest_by return dibbles", {
    data <- dibble(g = c("a", "a", "b"), v = c(1, 2, 3))
    reframed <- dplyr::reframe(data, total = sum(as.double(v)), .by = g)
    expect_true(is_dibble(reframed))
    expect_identical(dta_storage_type(reframed$total), "double")
    grouped <- dplyr::group_by(data, g)
    modified <- dplyr::group_modify(grouped, ~ dplyr::mutate(.x, w = 1L))
    expect_true(is_dibble(modified))
    expect_identical(dplyr::group_vars(modified), "g")
    expect_identical(dta_storage_type(modified$w), "long")
    nested <- dplyr::nest_by(data, g)
    expect_true(is_dibble(nested))
    expect_type(nested$data, "list")
    group_nested <- dplyr::group_nest(grouped)
    expect_true(is_dibble(group_nested))
    expect_identical(attr(group_nested$g, "stata.string.storage"), "str1")
    expect_type(group_nested$data, "list")
    by_key <- dplyr::group_nest(data, g, .key = "rows")
    expect_true(is_dibble(by_key))
    expect_identical(names(by_key), c("g", "rows"))
})

test_that("a := value with declared storage widens the column to it", {
    data <- dibble(x = dta_byte(1:3), s = c("a", "b", "c"))
    data[, x := dta_double(1)]
    expect_identical(dta_storage_type(data$x), "double")
    expect_identical(as.double(data$x), c(1, 1, 1))
    data <- dibble(x = dta_byte(1:3))
    data[2, x := dta_double(1000)]
    expect_identical(dta_storage_type(data$x), "double")
    expect_identical(as.double(data$x), c(1, 1000, 3))
    # Typed arithmetic declares storage too.
    data <- dibble(x = dta_int(1:3), y = dta_long(1:3))
    data[, x := y * 2L]
    expect_identical(dta_storage_type(data$x), "long")
    # A selection of no rows changes nothing, storage included, and a
    # compact column stays compact.
    untouched <- dibble(x = dta_byte(1:2), s = c("a", "b"))
    untouched[FALSE, x := dta_double(1)]
    untouched[FALSE, s := dta_string("z", "str20")]
    untouched[FALSE, s := "longer"]
    expect_identical(dta_storage_type(untouched$x), "byte")
    expect_identical(attr(untouched$s, "stata.string.storage"), "str1")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    save_dta(dibble(s = c("a", "b")), path)
    compact <- read_dta(path)
    compact[FALSE, s := "longer"]
    expect_true(dtatools:::.is_unmaterialized_dictstring(compact$s))
    expect_identical(attr(compact$s, "stata.string.storage"), "str1")
    # A narrower declaration keeps the column's storage.
    data <- dibble(x = dta_long(1:3))
    data[1, x := dta_byte(7)]
    expect_identical(dta_storage_type(data$x), "long")
    expect_identical(as.double(data$x), c(7, 2, 3))
    # Strings widen to a declared `str#` as well.
    data <- dibble(s = c("a", "b"))
    data[1, s := dta_string("z", "str20")]
    expect_identical(attr(data$s, "stata.string.storage"), "str20")
    expect_identical(as.character(data$s), c("z", "b"))
    data[2, s := dta_string("y", "str5")]
    expect_identical(attr(data$s, "stata.string.storage"), "str20")
    # Variable metadata survives the widening.
    labelled <- dibble(x = dta_byte(1:2))
    var_label(labelled$x) <- "Count"
    labelled[, x := dta_double(0.5)]
    expect_identical(var_label(labelled$x), "Count")
    expect_identical(dta_storage_type(labelled$x), "double")
    # A declared float beside a retained integer float cannot hold goes
    # up to double, never back down the ladder.
    big <- dibble(x = dta_long(c(16777217L, 2L)))
    big[2, x := dta_float(1)]
    expect_identical(dta_storage_type(big$x), "double")
    expect_identical(as.double(big$x), c(16777217, 1))
    # replace_values() stays strict about the target's storage.
    strict <- dibble(x = dta_byte(1:2))
    replace_values(strict, x, dta_double(1))
    expect_identical(dta_storage_type(strict$x), "byte")
})

test_that("grouped and rowwise row verbs return dibbles", {
    grouped <- dplyr::group_by(dibble(g = c("a", "b"), v = 1:2), g)
    kept <- dplyr::semi_join(grouped, tibble::tibble(g = "a"), by = "g")
    expect_true(is_dibble(kept))
    expect_s3_class(kept, "grouped_df")
    expect_identical(as.integer(kept$v), 1L)
    dropped <- dplyr::anti_join(grouped, tibble::tibble(g = "a"), by = "g")
    expect_true(is_dibble(dropped))
    expect_identical(as.integer(dropped$v), 2L)
    keyed <- dplyr::group_by(dibble(id = 1:2, v = 1:2), id)
    updated <- dplyr::rows_update(
        keyed, tibble::tibble(id = 1L, v = 9L), by = "id"
    )
    expect_true(is_dibble(updated))
    expect_identical(dta_storage_type(updated$v), "long")
    expect_identical(as.integer(updated$v), c(9L, 2L))
    updated[, v := 0L]
    expect_identical(as.integer(updated$v), c(0L, 0L))
    expect_identical(as.integer(keyed$v), 1:2)
    patched <- dplyr::rows_patch(
        dplyr::group_by(dibble(id = 1:2, flag = c(NA, TRUE)), id),
        tibble::tibble(id = 1L, flag = FALSE), by = "id"
    )
    expect_true(is_dibble(patched))
    expect_identical(patched$flag, c(FALSE, TRUE))
    wise <- dplyr::rows_delete(
        dplyr::rowwise(dibble(id = 1:2)), tibble::tibble(id = 1L), by = "id"
    )
    expect_true(is_dibble(wise))
    expect_s3_class(wise, "rowwise_df")
    expect_identical(as.integer(wise$id), 2L)
})

test_that("difftime arithmetic with Stata numerics works", {
    data <- dibble(span = as.difftime(1:2, units = "days"), id = 1:2)
    result <- dplyr::mutate(data, later = span + id, scaled = span * id)
    expect_s3_class(result$later, "difftime")
    expect_identical(as.double(result$later), c(2, 4))
    expect_s3_class(result$scaled, "difftime")
    expect_identical(
        dta_long(2L) + as.difftime(1, units = "days"),
        as.difftime(3, units = "days")
    )
})

test_that("the first gen on a tibble types columns transactionally", {
    tbl <- tibble::tibble(ok = 1:2, bad = c(Inf, Inf))
    alias <- tbl
    expect_error(gen(tbl, y = 1))
    expect_identical(tbl$ok, 1:2)
    expect_identical(alias$ok, 1:2)
    expect_false(is_dibble(tbl))
    expect_identical(names(tbl), c("ok", "bad"))
})

test_that("a stale string declaration is redone on entering a dibble", {
    left <- dibble(id = 1:2, s = c("a", "b"))
    # A join pads the str1 column with NA; the dibble restores Stata's ""
    # and keeps the width that fits.
    joined <- dplyr::full_join(left, tibble::tibble(id = 3L), by = "id")
    expect_true(is_dibble(joined))
    expect_identical(as.character(joined$s), c("a", "b", ""))
    expect_identical(attr(joined$s, "stata.string.storage"), "str1")
    # rbind() carries the first frame's declaration onto wider values.
    stacked <- rbind(left, tibble::tibble(id = 3L, s = "longer"))
    expect_identical(attr(stacked$s, "stata.string.storage"), "str6")
    expect_identical(as.character(stacked$s), c("a", "b", "longer"))
    bound <- dplyr::bind_rows(left, tibble::tibble(id = 3L, s = "wide"))
    expect_identical(attr(bound$s, "stata.string.storage"), "str4")
    # A malformed declaration is replaced, not trusted.
    bad <- tibble::tibble(
        s = structure(c("a", "b"), stata.string.storage = "str0")
    )
    fixed <- as_dibble(bad)
    expect_identical(attr(fixed$s, "stata.string.storage"), "str1")
    # A compact column's stale declaration is checked against the
    # dictionary and repaired without materializing it.
    dta_path <- tempfile(fileext = ".dta")
    on.exit(unlink(dta_path), add = TRUE)
    save_dta(dibble(s = c("a", "long")), dta_path)
    compact <- read_dta(dta_path, output = "tibble")
    attr(compact$s, "stata.string.storage") <- "str1"
    expect_true(dtatools:::.is_unmaterialized_dictstring(compact$s))
    repaired <- as_dibble(compact)
    expect_true(dtatools:::.is_unmaterialized_dictstring(repaired$s))
    expect_identical(attr(repaired$s, "stata.string.storage"), "str4")
    expect_identical(as.character(repaired$s), c("a", "long"))
    expect_no_warning(save_dta(repaired, dta_path))
    # The repaired column survives an Arrow round trip.
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(joined, path)
    back <- read_arrow(path)
    expect_identical(as.character(back$s), c("a", "b", ""))
    expect_identical(attr(back$s, "stata.string.storage"), "str1")
})

test_that("a derived dibble owns its columns", {
    source <- dibble(x = 1:3, s = c("a", "b", "c"), flag = c(TRUE, FALSE, TRUE))
    derived <- list(
        select = dplyr::select(source, x, s),
        relocate = dplyr::relocate(source, s),
        mutate = dplyr::mutate(source, y = x + 1L),
        rename = dplyr::rename(source, id = x),
        group_by = dplyr::group_by(source, flag),
        bind_cols = dplyr::bind_cols(source, dibble(z = 4:6)),
        noted = add_dta_note(source, "a note", variable = "s")
    )
    for (name in names(derived)) {
        piece <- derived[[name]]
        x_name <- if (identical(name, "rename")) "id" else "x"
        expect_true(is_dibble(piece), info = name)
        # A by-reference write through the derived dibble stays there.
        piece[, !!x_name := 9L]
        repl(piece, s = "z")
        expect_identical(as.integer(source$x), 1:3, info = name)
        expect_identical(as.character(source$s), c("a", "b", "c"), info = name)
        expect_identical(
            as.integer(piece[[x_name]]), c(9L, 9L, 9L), info = name
        )
        expect_identical(as.character(piece$s), c("z", "z", "z"), info = name)
    }
    # And a write through the source leaves an earlier derived dibble alone.
    piece <- dplyr::select(source, x, flag)
    source[, x := 0L]
    repl(source, flag = FALSE)
    expect_identical(as.integer(piece$x), 1:3)
    expect_identical(piece$flag, c(TRUE, FALSE, TRUE))
    expect_identical(as.integer(source$x), c(0L, 0L, 0L))
    # Compact columns stay compact on both sides until one is written.
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    save_dta(dibble(n = 1:4, s = c("aa", "bb", "aa", "cc")), path)
    data <- read_dta(path)
    piece <- dplyr::select(data, n, s)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(piece$n))
    expect_true(dtatools:::.is_unmaterialized_dictstring(piece$s))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$n))
    expect_true(dtatools:::.is_unmaterialized_dictstring(data$s))
    piece[n == 2L, n := 20L]
    repl(piece, s = "dd", where = n == 20L)
    expect_identical(as.integer(data$n), 1:4)
    expect_identical(as.character(data$s), c("aa", "bb", "aa", "cc"))
    expect_identical(as.integer(piece$n), c(1L, 20L, 3L, 4L))
    expect_identical(as.character(piece$s), c("aa", "dd", "aa", "cc"))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$n))
    expect_true(dtatools:::.is_unmaterialized_dictstring(data$s))
})

test_that("a stata_string column padded with NA is retyped on closure", {
    left <- dibble(id = 1:2, s = dta_string(c("a", "b")))
    right <- dibble(id = 2:4, t = dta_string(c("x", "y", "z")))
    joined <- dplyr::full_join(left, right, by = "id")
    expect_true(is_dibble(joined))
    expect_false(anyNA(joined$s))
    expect_identical(as.character(joined$s), c("a", "b", "", ""))
    expect_identical(joined$s == "", c(FALSE, FALSE, TRUE, TRUE))
    expect_identical(attr(joined$s, "stata.string.storage"), "str1")
    expect_identical(as.character(joined$t), c("", "x", "y", "z"))
    righted <- dplyr::right_join(left, right, by = "id")
    expect_identical(as.character(righted$s), c("b", "", ""))
    bound <- dplyr::bind_rows(left, dibble(id = 5L))
    expect_identical(as.character(bound$s), c("a", "b", ""))
    expect_identical(attr(bound$s, "stata.string.storage"), "str1")
    # The declaration also gives way when the padding column is wider.
    wider <- dplyr::bind_rows(
        left, dibble(id = 5L, s = dta_string("long"))
    )
    expect_identical(attr(wider$s, "stata.string.storage"), "str4")
    expect_identical(as.character(wider$s), c("a", "b", "long"))
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    expect_no_warning(save_dta(joined, path))
    expect_identical(as.character(read_dta(path)$s), c("a", "b", "", ""))
})

test_that("subsetting keeps compact dictionary strings compact", {
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    save_dta(dibble(n = 1:5, s = c("aa", "bb", "aa", "cc", "bb")), path)
    data <- read_dta(path)
    compact <- function(value) dtatools:::.is_unmaterialized_dictstring(value)
    expect_true(compact(data$s))

    filtered <- dplyr::filter(data, n > 2L)
    expect_true(compact(filtered$s))
    expect_true(compact(data$s))
    expect_identical(as.character(filtered$s), c("aa", "cc", "bb"))
    expect_identical(attr(filtered$s, "stata.string.storage"), "str2")
    expect_true(inherits(filtered$s, "stata_string"))

    sliced <- vctrs::vec_slice(data$s, c(5L, 1L))
    expect_true(compact(sliced))
    expect_identical(as.character(sliced), c("bb", "aa"))

    bracket <- data$s[c(2, 4)]
    expect_true(compact(bracket))
    expect_identical(as.character(bracket), c("bb", "cc"))
    expect_true(compact(data$s[-1L]))
    expect_true(compact(data$s[data$n %% 2L == 1L]))
    odd <- data$s[data$n %% 2L == 1L]
    expect_identical(as.character(odd), c("aa", "aa", "bb"))
    rows <- data[2:3, ]
    expect_true(is_dibble(rows))
    expect_true(compact(rows$s))
    expect_true(compact(data$s))
    expect_identical(as.character(rows$s), c("bb", "aa"))
    expect_identical(as.character(head(data, 2)$s), c("aa", "bb"))
    expect_true(compact(head(data, 2)$s))
    expect_identical(as.character(dplyr::arrange(data, dplyr::desc(n))$s),
        c("bb", "cc", "aa", "bb", "aa"))
    expect_true(compact(dplyr::arrange(data, dplyr::desc(n))$s))

    # An index outside the vector needs `NA`, which the dictionary cannot
    # hold, so that subset materializes as R's `[` would.
    beyond <- data$s[c(1L, 9L)]
    expect_false(compact(beyond))
    expect_identical(as.character(beyond), c("aa", NA))
    expect_identical(as.character(data$s[[3L]]), "aa")
    expect_identical(as.character(data$s), c("aa", "bb", "aa", "cc", "bb"))

    # A subset is its own vector: writing into it leaves the source alone.
    piece <- dplyr::filter(data, n <= 2L)
    repl(piece, s = "zz")
    expect_identical(as.character(piece$s), c("zz", "zz"))
    expect_identical(as.character(data$s), c("aa", "bb", "aa", "cc", "bb"))
    expect_true(compact(data$s))
    # And the source can still be written after subsets were taken.
    repl(data, s = "yy", where = n == 4L)
    expect_identical(as.character(data$s), c("aa", "bb", "aa", "yy", "bb"))
    expect_identical(as.character(filtered$s), c("aa", "cc", "bb"))
})

test_that("generated columns reach consumers that read the column list", {
    data <- dibble(x = 1:2)
    gen(data, y = x * 2L)
    gen(data, s = "a")
    expect_true(is_dibble(data))
    expect_identical(names(data), c("x", "y", "s"))
    # The physical list holds every column, so vctrs' binders see them.
    expect_identical(names(unclass(data)), c("x", "y", "s"))
    stacked <- dplyr::bind_rows(data, data)
    expect_true(is_dibble(stacked))
    expect_identical(names(stacked), c("x", "y", "s"))
    expect_identical(as.integer(stacked$y), c(2L, 4L, 2L, 4L))
    beside <- dplyr::bind_cols(data, dibble(z = 3:4))
    expect_identical(names(beside), c("x", "y", "s", "z"))
    expect_identical(names(vctrs::vec_rbind(data, data)), c("x", "y", "s"))
    expect_identical(names(lapply(data, class)), c("x", "y", "s"))
    # Other bindings to the same object see the appended columns too.
    alias <- data
    gen(data, w = 1L)
    expect_identical(names(alias), c("x", "y", "s", "w"))
    expect_identical(as.integer(alias$w), c(1L, 1L))
    # Past the spare capacity, generated columns live in the state, and
    # the visible dataset is still complete.
    wide <- dibble(x = 1L)
    capacity <- dtatools:::.dibble_column_capacity
    for (index in seq_len(capacity + 1L)) {
        gen(wide, !!paste0("v", index), x)
    }
    last <- paste0("v", capacity + 1L)
    expect_identical(length(names(wide)), capacity + 2L)
    expect_identical(length(unclass(wide)), capacity + 1L)
    expect_identical(names(wide)[[capacity + 2L]], last)
    expect_identical(as.integer(wide[[last]]), 1L)
    expect_identical(ncol(tibble::as_tibble(wide)), capacity + 2L)
    # A tibble that becomes a dibble at its first gen() has no spare
    # capacity, so that column lives in the state and later ones follow.
    tbl <- tibble::tibble(a = 1:2)
    gen(tbl, b = a)
    gen(tbl, c = a)
    expect_identical(names(tbl), c("a", "b", "c"))
    expect_identical(names(unclass(tbl)), "a")
    # Such a dibble hands non-generic consumers its snapshot, as documented.
    expect_identical(
        names(dplyr::bind_rows(tibble::as_tibble(tbl), tbl)),
        c("a", "b", "c")
    )
    state <- dtatools:::.reference_state(tbl)
    expect_identical(state$generated_count, 2L)
    expect_identical(names(dtatools:::.data_columns(tbl)), c("a", "b", "c"))
})

test_that("column binding isolates every input, not only the first", {
    left <- dibble(x = 1:2)
    right <- tibble::tibble(flag = c(TRUE, FALSE), s = c("a", "b"))
    other <- dibble(z = dta_long(5:6))
    bound <- dplyr::bind_cols(left, right, other)
    repl(bound, flag = FALSE)
    repl(bound, s = "z")
    bound[, z := 0L]
    expect_identical(right$flag, c(TRUE, FALSE))
    expect_identical(right$s, c("a", "b"))
    expect_identical(as.integer(other$z), 5:6)
    expect_identical(bound$flag, c(FALSE, FALSE))
    stacked <- cbind(left, right)
    repl(stacked, flag = FALSE)
    expect_identical(right$flag, c(TRUE, FALSE))
    # cbind() takes bare vectors too.
    vectors <- cbind(left, flag = right$flag, z = other$z)
    repl(vectors, flag = FALSE)
    vectors[, z := 0L]
    expect_identical(right$flag, c(TRUE, FALSE))
    expect_identical(as.integer(other$z), 5:6)
    expect_identical(vectors$flag, c(FALSE, FALSE))
    stacked_rows <- rbind(left, dibble(x = 3L))
    stacked_rows[, x := 0L]
    expect_identical(as.integer(left$x), 1:2)
    joined <- dplyr::left_join(
        left, tibble::tibble(x = 1:2, w = c(TRUE, TRUE)), by = "x"
    )
    joined_source <- tibble::tibble(x = 1:2, w = c(TRUE, TRUE))
    joined <- dplyr::left_join(left, joined_source, by = "x")
    repl(joined, w = FALSE)
    expect_identical(joined_source$w, c(TRUE, TRUE))
    # A data-masked verb can bring a vector in from any frame.
    masked <- dplyr::mutate(left, copied = right$flag)
    masked[, copied := FALSE]
    expect_identical(right$flag, c(TRUE, FALSE))
    keyed <- dplyr::group_by(left, g = right$flag)
    keyed[, g := FALSE]
    expect_identical(right$flag, c(TRUE, FALSE))
    # Binding a bare column onto a narrow Stata column widens it by the
    # bare vector's own mapping instead of failing the cast.
    widened <- dplyr::bind_rows(
        dibble(x = dta_byte(1)), tibble::tibble(x = 1000L)
    )
    expect_true(is_dibble(widened))
    expect_identical(dta_storage_type(widened$x), "long")
    expect_identical(as.double(widened$x), c(1, 1000))
    joined_wide <- dplyr::full_join(
        dibble(id = 1L, x = dta_byte(1)), tibble::tibble(id = 2L, x = 0.5),
        by = c("id", "x")
    )
    expect_identical(dta_storage_type(joined_wide$x), "double")
    # A Stata string key meeting a bare character key in an outer join
    # is padded with Stata's `""`, and the result is a dibble.
    keyed <- dplyr::full_join(
        dibble(id = 1:2, s = dta_string(c("a", "b"))),
        tibble::tibble(s = c("b", "c"), w = 1:2), by = "s"
    )
    expect_true(is_dibble(keyed))
    expect_identical(as.character(keyed$s), c("a", "b", "c"))
    expect_identical(as.integer(keyed$id), c(1L, 2L, NA))
    righted <- dplyr::right_join(
        dibble(s = dta_string(c("a", "b")), v = 1:2),
        tibble::tibble(s = c("b", "c")), by = "s"
    )
    expect_identical(as.character(righted$s), c("b", "c"))
    expect_identical(as.integer(righted$v), c(2L, NA))
    # Base rbind() widens by the same mapping.
    stacked_num <- rbind(dibble(x = dta_byte(1)), data.frame(x = 1000L))
    expect_true(is_dibble(stacked_num))
    expect_identical(dta_storage_type(stacked_num$x), "long")
    expect_identical(as.double(stacked_num$x), c(1, 1000))
    stacked_str <- rbind(dibble(s = dta_string("a")), data.frame(s = "longer"))
    expect_identical(attr(stacked_str$s, "stata.string.storage"), "str6")
    expect_identical(as.character(stacked_str$s), c("a", "longer"))
    # `data["s"] <- NULL` deletes a column.
    dropped <- dibble(x = 1:2, s = c("a", "b"))
    dropped["s"] <- NULL
    expect_true(is_dibble(dropped))
    expect_identical(names(dropped), "x")
    # bind_rows() with a single input shares nothing that can leak either.
    rows <- dplyr::bind_rows(left, tibble::tibble(x = 3L))
    rows[, x := 0L]
    expect_identical(as.integer(left$x), 1:2)
})

test_that("the first gen on a tibble evaluates against typed columns", {
    tbl <- tibble::tibble(g = c(NA_character_, ""), v = 1:2)
    gen(tbl, n = .N, by = g)
    # NA and "" are one Stata string value, so one group of two.
    expect_true(is_dibble(tbl))
    expect_identical(as.integer(tbl$n), c(2L, 2L))
    expect_identical(as.character(tbl$g), c("", ""))
    grouped <- dplyr::group_by(
        tibble::tibble(g = c(NA_character_, ""), v = 1:2), g
    )
    gen(grouped, n = .N)
    expect_identical(as.integer(grouped$n), c(2L, 2L))
    expect_identical(nrow(attr(grouped, "groups")), 1L)
    flagged <- tibble::tibble(g = c(NA_character_, ""), v = 1:2)
    gen(flagged, empty = g == "")
    expect_identical(flagged$empty, c(TRUE, TRUE))
    # A failing first gen with `bysort` undoes the sort on every column,
    # typed or not, so rows stay aligned.
    sorted <- tibble::tibble(
        k = c(2L, 1L), flag = c(TRUE, FALSE), f = factor(c("b", "a"))
    )
    expect_error(gen(sorted, y = Inf, bysort = k))
    expect_false(is_dibble(sorted))
    expect_identical(sorted$k, c(2L, 1L))
    expect_identical(sorted$flag, c(TRUE, FALSE))
    expect_identical(as.character(sorted$f), c("b", "a"))
    # A failing first gen leaves the tibble as it was, grouping included.
    bad <- dplyr::group_by(
        tibble::tibble(g = c(NA_character_, "b"), v = 1:2), g
    )
    alias <- bad
    expect_error(gen(bad, y = stop("boom")), "boom")
    expect_false(is_dibble(bad))
    expect_identical(bad$g, c(NA_character_, "b"))
    expect_identical(alias$g, c(NA_character_, "b"))
    expect_identical(nrow(attr(bad, "groups")), 2L)
})
