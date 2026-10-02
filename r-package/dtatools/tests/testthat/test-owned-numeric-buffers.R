owned_numeric_info <- function(x) .Call(C_dtatools_owned_numeric_info, x)
freeze_numeric <- function(x, chunk_rows = 2) {
    .Call(C_dtatools_owned_numeric_freeze, x, chunk_rows)
}

test_that("compact sums preserve cancellation across interrupt blocks and chunks", {
    # This exceeds even a 113-bit long-double mantissa while remaining an exact
    # observed Stata float. Independent block totals lose the final unit.
    values <- c(rep(0, 65535L), 2^120, 1, -2^120, 1)
    result_bytes <- function(x) writeBin(x, raw(), size = 8L, endian = "little")
    for (include_missing in c(FALSE, TRUE)) {
        expected_values <- if (include_missing) c(values, NA_real_) else values
        for (chunk_rows in c(0, 7, 32768, 65536, 65537)) {
            value <- dta_float(expected_values)
            if (chunk_rows > 0) value <- freeze_numeric(value, chunk_rows)
            view <- as.double(value)
            for (na_rm in c(FALSE, TRUE)) {
                expect_identical(
                    result_bytes(sum(view, na.rm = na_rm)),
                    result_bytes(sum(expected_values, na.rm = na_rm))
                )
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(view))
            }
        }
    }
})

test_that("scalar retained reads cross chunks and survive independent handle writes", {
    values <- c(-1, 0, 1, NA_real_, tagged_missing(letters), 5)
    permutation <- c(seq.int(2L, length(values), by = 2L),
                     seq.int(1L, length(values), by = 2L))
    positions <- c(seq_along(values), rev(seq_along(values)), permutation, 1L, 31L, 2L)
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        for (chunk_rows in c(1, 2, 7, 100)) {
            frozen <- freeze_numeric(constructor(values), chunk_rows)
            snapshot <- as.double(frozen)
            # Base is.na and scalar extraction read through the bare ALTREP
            # handles. The reverse pass revisits chunks after a forward scan.
            expect_identical(is.na(snapshot), is.na(values))
            actual <- vapply(positions, function(i) snapshot[[i]], double(1))
            expect_identical(actual, values[positions])
            expect_identical(missing_tag(actual), missing_tag(values[positions]))
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(snapshot))
            before <- owned_numeric_info(snapshot)

            .Call(C_dtatools_mutate_first_numeric_altrep, frozen, 8)
            gc()
            actual <- vapply(positions, function(i) snapshot[[i]], double(1))
            expect_identical(actual, values[positions])
            expect_identical(missing_tag(actual), missing_tag(values[positions]))
            expect_identical(is.na(snapshot), is.na(values))
            expect_equal(owned_numeric_info(snapshot)[["compatibility_bytes"]],
                         before[["compatibility_bytes"]])

            .force_altrep_materialization(snapshot)
            gc()
            actual <- vapply(rev(positions), function(i) snapshot[[i]], double(1))
            expect_identical(actual, values[rev(positions)])
            expect_identical(missing_tag(actual), missing_tag(values[rev(positions)]))
            expect_identical(is.na(snapshot), is.na(values))
        }
    }
})

test_that("scalar Arrow reads retain native batches after source materialization and GC", {
    rows <- 2L * 65536L + 7L
    values <- rep_len(c(-1, 0, 1, NA_real_, tagged_missing(letters)), rows)
    days <- values - 3653
    # Preserve tagged missing payloads rather than relying on arithmetic NaNs.
    days[is.na(values)] <- values[is.na(values)]
    date <- dtatools:::.construct_dta_numeric(days, NULL, "int", temporal = 1L)
    date <- dtatools:::.attach_dta_temporal(
        date,
        structure(double(), format.stata = "%td",
                  class = c("dta_temporal", "dta_date", "Date")),
        "int"
    )
    source <- tibble::tibble(b = dta_byte(values), i = dta_int(values),
                             l = dta_long(values), f = dta_float(values), day = date)
    expected <- list(b = values, i = values, l = values, f = values, day = days)
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(source, path, threads = 1L)
    imported <- read_arrow(path, output = "tibble", threads = 1L)
    positions <- c(1L, 65535:65538, 131071:131074, rows, 2L, 65536L)
    snapshots <- lapply(imported, as.double)
    for (name in names(snapshots)) {
        snapshot <- snapshots[[name]]
        expect_gt(owned_numeric_info(snapshot)[["chunks"]], 1)
        expect_identical(is.na(snapshot), is.na(expected[[name]]))
        actual <- vapply(positions, function(i) snapshot[[i]], double(1))
        expect_identical(actual, expected[[name]][positions])
        expect_identical(missing_tag(actual), missing_tag(expected[[name]][positions]))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(snapshot))
        .force_altrep_materialization(imported[[name]])
    }
    rm(imported, source, date)
    unlink(path)
    gc()
    for (name in names(snapshots)) {
        snapshot <- snapshots[[name]]
        expect_equal(owned_numeric_info(snapshot)[["owned"]], 1)
        actual <- vapply(rev(positions), function(i) snapshot[[i]], double(1))
        expect_identical(actual, expected[[name]][rev(positions)])
        expect_identical(missing_tag(actual), missing_tag(expected[[name]][rev(positions)]))
        expect_identical(is.na(snapshot), is.na(expected[[name]]))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(snapshot))
    }
})

test_that("immutable compact regions preserve all missing codes and chunk edges", {
    values <- c(-1, 0, 1, NA_real_, tagged_missing(letters), 5)
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        for (chunk_rows in c(1, 2, 7, 100)) {
            source <- constructor(values)
            frozen <- freeze_numeric(source, chunk_rows)
            before <- owned_numeric_info(frozen)
            expect_equal(before[["owned"]], 1)
            expect_equal(before[["chunks"]], ceiling(length(values) / chunk_rows))
            expect_identical(as.double(frozen), as.double(source))
            expect_identical(missing_tag(frozen), missing_tag(source))
            expect_identical(is_tagged_missing(frozen), is_tagged_missing(source))
            for (remove in c(FALSE, TRUE)) {
                for (operation in list(sum, min, max)) {
                    expect_identical(operation(frozen, na.rm = remove), operation(source, na.rm = remove))
                }
            }
            expect_identical(as.double(frozen[c(31L, 2L, NA_integer_, 1L, 8L)]),
                             as.double(source[c(31L, 2L, NA_integer_, 1L, 8L)]))
            expect_equal(owned_numeric_info(frozen)[["owned"]], 1)
            expect_equal(owned_numeric_info(frozen)[["compatibility_bytes"]], before[["compatibility_bytes"]])
        }
        empty <- freeze_numeric(constructor(numeric()))
        expect_identical(as.double(empty), numeric())
        expect_equal(owned_numeric_info(empty)[["chunks"]], 0)
        expect_identical(as.double(sum(empty)), 0)
    }
})

test_that("immutable compact dates preserve conversion and serialization", {
    for (display_format in c("%td", "%tc")) {
        path <- fixture_with_temporal_storage("price", display_format)
        source <- read_dta(path)$price
        unlink(path)
        frozen <- freeze_numeric(source, 7)
        expect_identical(as.double(frozen), as.double(source))
        expect_identical(attributes(frozen), attributes(source))
        restored <- unserialize(serialize(frozen, NULL))
        expect_identical(as.double(restored), as.double(source))
        expect_identical(attributes(restored), attributes(source))
        expect_equal(owned_numeric_info(frozen)[["owned"]], 1)
    }
})

test_that("immutable captures isolate writable pointers and explicit mutations", {
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        frozen <- freeze_numeric(constructor(c(1, NA_real_, 3, 4)))
        captured <- .Call(C_dtatools_metadata_copy, frozen)
        .Call(C_dtatools_mutate_first_numeric_altrep, frozen, 8)
        expect_identical(as.double(frozen), c(8, NA_real_, 3, 4))
        expect_identical(as.double(captured), c(1, NA_real_, 3, 4))
        expect_equal(owned_numeric_info(captured)[["owned"]], 1)

        data <- dibble(x = freeze_numeric(constructor(c(1, NA_real_, 3, 4))))
        saved <- copy_data(data)
        captured <- data$x
        replace_values(data, x = 9, where = c(1L, 3L))
        expect_identical(as.double(data$x), c(9, NA_real_, 9, 4))
        expect_identical(as.double(saved$x), c(1, NA_real_, 3, 4))
        expect_identical(as.double(captured), c(1, NA_real_, 3, 4))
        expect_equal(owned_numeric_info(saved$x)[["owned"]], 1)
        expect_identical(dta_storage_type(data$x), dta_storage_type(saved$x))
    }
})

test_that("failed and interrupted owned-column mutations leave captured values intact", {
    data <- dibble(x = freeze_numeric(dta_byte(c(1, NA_real_, 3, 4))))
    saved <- copy_data(data)
    expect_error(replace_values(data, x = "bad", where = 1L))
    expect_identical(as.double(data$x), c(1, NA_real_, 3, 4))
    .inject_reference_write_interrupt(TRUE)
    on.exit(.inject_reference_write_interrupt(FALSE), add = TRUE)
    condition <- tryCatch(replace_values(data, x = 9, where = c(1L, 3L)), condition = identity)
    .inject_reference_write_interrupt(FALSE)
    expect_s3_class(condition, "interrupt")
    expect_identical(as.double(data$x), c(1, NA_real_, 3, 4))
    expect_identical(as.double(saved$x), c(1, NA_real_, 3, 4))
    replace_values(data, x = 1000, where = 1L)
    expect_identical(dta_storage_type(data$x), "int")
    expect_identical(as.double(saved$x), c(1, NA_real_, 3, 4))
})

test_that("direct owned compact patches commit only after successful completion", {
    for (proxy in c(FALSE, TRUE)) {
        value <- freeze_numeric(dta_int(c(1, NA_real_, 3, 4)))
        if (proxy) value <- .Call(C_dtatools_metadata_copy, value)
        saved <- .Call(C_dtatools_metadata_copy, value)
        expect_error(.Call(C_dtatools_patch_vector, value, 1L, "bad"))
        expect_equal(owned_numeric_info(value)[["owned"]], 1)
        .inject_reference_write_interrupt(TRUE)
        condition <- tryCatch(.Call(C_dtatools_patch_vector, value, c(1L, 3L), 9), condition = identity)
        .inject_reference_write_interrupt(FALSE)
        expect_s3_class(condition, "interrupt")
        expect_equal(owned_numeric_info(value)[["owned"]], 1)
        expect_identical(as.double(value), c(1, NA_real_, 3, 4))
        .Call(C_dtatools_patch_vector, value, c(1L, 3L), 9)
        expect_identical(as.double(value), c(9, NA_real_, 9, 4))
        expect_identical(as.double(saved), c(1, NA_real_, 3, 4))
        expect_equal(owned_numeric_info(value)[["owned"]], 0)
    }
})

test_that("patch alias checks preserve owned row selector backing", {
    for (proxy in c(FALSE, TRUE)) {
        rows <- freeze_numeric(dta_int(c(3, 1)), 1)
        if (proxy) rows <- .Call(C_dtatools_metadata_copy, rows)
        target <- dta_int(c(10, 20, 30, 40))
        before <- owned_numeric_info(rows)[["compatibility_bytes"]]
        .Call(C_dtatools_patch_vector, target, rows, 9)
        expect_identical(as.double(target), c(9, 20, 9, 40))
        expect_identical(as.double(rows), c(3, 1))
        expect_equal(owned_numeric_info(rows)[["owned"]], 1)
        expect_equal(owned_numeric_info(rows)[["compatibility_bytes"]], before)
    }
})

test_that("compact self-selection and independent selector copies patch correctly", {
    for (owned in c(FALSE, TRUE)) {
        for (copied in c(FALSE, TRUE)) {
            target <- dta_int(c(3, 1, 2))
            if (owned) target <- freeze_numeric(target, 1)
            rows <- if (copied) .Call(C_dtatools_metadata_copy, target) else target
            .Call(C_dtatools_patch_vector, target, rows, 9)
            expect_identical(as.double(target), c(9, 9, 9))
            if (copied) expect_identical(as.double(rows), c(3, 1, 2))
            if (owned && copied) expect_equal(owned_numeric_info(rows)[["owned"]], 1)
        }
    }
})

test_that("owned row selectors survive replacement callbacks and collection", {
    rows <- freeze_numeric(dta_int(c(3, 1)), 1)
    target <- dta_int(c(10, 20, 30, 40))
    calls <- 0L
    replacement <- .Call(C_dtatools_callback_double, c(99, 88), function() {
        calls <<- calls + 1L
        .force_altrep_materialization(rows)
        gc()
    }, TRUE)
    .Call(C_dtatools_patch_vector, target, rows, replacement)
    expect_identical(as.double(target), c(88, 20, 99, 40))
    expect_identical(as.double(rows), c(3, 1))
    expect_identical(calls, 1L)
})

test_that("Arrow reads retain owned buffers independently of their source", {
    data <- dibble(
        b = dta_byte(c(1, NA_real_, tagged_missing("a"), 4)),
        i = dta_int(c(1, NA_real_, tagged_missing("z"), 4)),
        l = dta_long(c(1, NA_real_, tagged_missing("a"), 4)),
        f = dta_float(c(1.25, NA_real_, tagged_missing("z"), 4)),
        d = dta_double(c(1, 2, 3, 4))
    )
    for (compression in c("uncompressed", "lz4", "zstd")) {
        path <- tempfile(fileext = ".arrow")
        on.exit(unlink(path), add = TRUE)
        save_arrow(data, path, compression = compression)
        actual <- read_arrow(path)
        expect_true(all(vapply(actual[1:4], function(x) owned_numeric_info(x)[["owned"]] == 1, logical(1))))
        expect_equal(owned_numeric_info(actual$d)[["owned"]], 0)
        native_before <- owned_numeric_info(actual$b)[["native_bytes"]]
        expect_gt(native_before, 0)
        saved <- copy_data(actual)
        unlink(path)
        gc()
        for (name in names(data)) expect_identical(as.double(actual[[name]]), as.double(data[[name]]))
        expect_identical(datasig(actual), datasig(data))
        dta_path <- tempfile(fileext = ".dta")
        on.exit(unlink(dta_path), add = TRUE)
        save_dta(actual, dta_path)
        reread <- read_dta(dta_path)
        for (name in names(data)) expect_identical(as.double(reread[[name]]), as.double(data[[name]]))
        replace_values(actual, b = 9, where = 1L)
        expect_identical(as.double(saved$b), as.double(data$b))
        expect_identical(as.double(actual$b), c(9, NA_real_, tagged_missing("a"), 4))
    }
})

test_that("owned allocation charges are released after final handles disappear", {
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(dibble(x = dta_int(rep(1, 1000))), path)
    gc()
    before <- owned_numeric_info(NULL)
    local({
        actual <- read_arrow(path)
        retained <- copy_data(actual)
        expect_gt(owned_numeric_info(actual$x)[["native_bytes"]], before[["native_bytes"]])
        rm(actual)
        gc()
        expect_equal(as.double(sum(retained$x)), 1000)
    })
    gc()
    after <- owned_numeric_info(NULL)
    expect_equal(after[["native_bytes"]], before[["native_bytes"]])
    expect_equal(after[["live_owners"]], before[["live_owners"]])
})

test_that("parallel owned fills finish exact counts before publishing chunked columns", {
    values <- rep(c(-1, 0, 1, NA_real_, tagged_missing("a"), tagged_missing("z")), 25001)
    data <- dibble(b = dta_byte(values), i = dta_int(values),
                   l = dta_long(values), f = dta_float(values))
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data, path)
    serial <- read_arrow(path, threads = 1L)
    parallel <- read_arrow(path, threads = 4L)
    for (name in names(data)) {
        expect_gt(owned_numeric_info(parallel[[name]])[["chunks"]], 1)
        expect_identical(as.double(parallel[[name]]), as.double(serial[[name]]))
        expect_identical(missing_tag(parallel[[name]]), missing_tag(serial[[name]]))
        expect_identical(sum(parallel[[name]], na.rm = TRUE), sum(serial[[name]], na.rm = TRUE))
        expect_equal(owned_numeric_info(parallel[[name]])[["owned"]], 1)
    }
    window <- read_arrow(path, skip = 65530, n_max = 17, threads = 4L)
    for (name in names(data)) {
        expect_identical(as.double(window[[name]]), as.double(data[[name]][65531:65547]))
    }
})

test_that("repeated owned reads collect unreachable native allocations", {
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(dibble(x = dta_int(rep(1, 10000000))), path)
    gc()
    before <- owned_numeric_info(NULL)[["native_bytes"]]
    for (i in seq_len(8)) actual <- read_arrow(path, threads = 1L)
    outstanding <- owned_numeric_info(actual$x)[["native_bytes"]] - before
    expect_lte(outstanding, 64 * 1024^2 + 20000000)
    expect_equal(as.double(sum(actual$x)), 10000000)
    gc()
    expect_equal(owned_numeric_info(actual$x)[["native_bytes"]] - before, 20000000)
})

test_that("comparisons and gathers read retained regions without compatibility copies", {
    values <- rep(c(-1, 0, 1, NA_real_, tagged_missing("a"), tagged_missing("z")), 17)
    rows <- c(102L, 2L, NA_integer_, 8L, 1L, 101L)
    other_rows <- c(1L, 8L, 3L, NA_integer_, 6L, 1L)
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        ordinary <- constructor(values)
        x <- freeze_numeric(ordinary, 7)
        y <- freeze_numeric(constructor(rev(values)), 11)
        before <- owned_numeric_info(x)[["compatibility_bytes"]]
        for (threads in c(1L, 4L)) for (op in 0:5) {
            expect_identical(.Call(C_dtatools_dta_compare, op, x, y, NULL, threads),
                .Call(C_dtatools_dta_compare, op, ordinary, constructor(rev(values)), NULL, threads))
            expect_identical(.Call(C_dtatools_dta_compare, op, x, NULL, c(0, 0), threads),
                .Call(C_dtatools_dta_compare, op, ordinary, NULL, c(0, 0), threads))
        }
        actual <- .Call(C_dtatools_gather_numeric, x, y, rows, other_rows)
        expected <- .Call(C_dtatools_gather_numeric, ordinary, constructor(rev(values)), rows, other_rows)
        expect_identical(as.double(actual), as.double(expected))
        actual <- .Call(C_dtatools_gather_numeric_columns, list(x, y), list(y, x), rows, other_rows)
        expected <- .Call(C_dtatools_gather_numeric_columns, list(ordinary, constructor(rev(values))),
                          list(constructor(rev(values)), ordinary), rows, other_rows)
        expect_identical(lapply(actual, as.double), lapply(expected, as.double))
        target <- constructor(rep(0, length(values)))
        expected_target <- constructor(rep(0, length(values)))
        .Call(C_dtatools_fused_compare_patch, target, 4L, x, NULL, c(0, 0), y, NULL, 1L)
        .Call(C_dtatools_fused_compare_patch, expected_target, 4L, ordinary, NULL, c(0, 0),
              constructor(rev(values)), NULL, 1L)
        expect_identical(as.double(target), as.double(expected_target))
        expect_equal(owned_numeric_info(x)[["compatibility_bytes"]], before)
        expect_equal(owned_numeric_info(x)[["owned"]], 1)
        expect_equal(owned_numeric_info(y)[["owned"]], 1)
    }
})

test_that("read roots survive foreign operand and gather callbacks", {
    for (operation in c("compare", "gather", "columns")) {
        source <- freeze_numeric(dta_int(c(1, 2, 3)), 1)
        calls <- 0L
        callback <- function() {
            calls <<- calls + 1L
            .force_altrep_materialization(source)
            gc()
        }
        if (operation == "compare") {
            right <- .Call(C_dtatools_callback_double, c(1, 2, 3), callback, FALSE)
            result <- .Call(C_dtatools_dta_compare, 0L, source, right, NULL, 1L)
            expect_identical(result, rep(TRUE, 3))
        } else {
            index <- .Call(C_dtatools_callback_integer, c(3L, 1L, 2L), callback)
            if (operation == "gather") result <- .Call(C_dtatools_gather_numeric, source, NULL, index, NULL)
            else result <- .Call(C_dtatools_gather_numeric_columns, list(source), NULL, index, NULL)[[1L]]
            expect_identical(as.double(result), c(3, 1, 2))
        }
        expect_identical(calls, 1L)
        expect_identical(as.double(source), c(1, 2, 3))
    }
})

test_that("row calculations retain owned inputs across foreign element callbacks", {
    source <- freeze_numeric(dta_int(c(1, 2, 3)), 1)
    calls <- 0L
    later <- .Call(C_dtatools_callback_double, c(4, 5, 6), function() {
        calls <<- calls + 1L
        .force_altrep_materialization(source)
        gc()
    }, TRUE)
    expect_identical(as.double(dta_row_total(source, later)), c(5, 7, 9))
    expect_identical(calls, 1L)
    expect_identical(as.double(source), c(1, 2, 3))
})

test_that("row calculations and groups retain compact and proxy backing", {
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        for (owned in c(FALSE, TRUE)) {
            for (proxy in c(FALSE, TRUE)) {
                for (operation in c("total", "maximum", "group", "tag")) {
                    source <- constructor(c(2, 1, 2))
                    if (owned) source <- freeze_numeric(source, 1)
                    if (proxy) source <- .Call(C_dtatools_metadata_copy, source)
                    calls <- 0L
                    callback <- function() {
                        calls <<- calls + 1L
                        .force_altrep_materialization(source)
                        gc()
                    }
                    if (operation %in% c("total", "maximum")) {
                        later <- .Call(C_dtatools_callback_double, c(4, 5, 4),
                                       callback, TRUE)
                        result <- if (operation == "total") dta_row_total(source, later)
                            else dta_row_max(source, later)
                        expected <- if (operation == "total") c(6, 6, 6) else c(4, 5, 4)
                    } else {
                        later <- .Call(C_dtatools_callback_character, c("b", "a", "b"),
                                       callback)
                        result <- if (operation == "group") dta_group_id(source, later)
                            else dta_group_tag(source, later)
                        expected <- if (operation == "group") c(2, 1, 2) else c(1, 1, 0)
                    }
                    expect_identical(as.double(result), expected)
                    expect_identical(calls, 1L)
                    expect_identical(as.double(source), c(2, 1, 2))
                }
            }
        }
    }
})

test_that("calculation read roots are released after callback errors and interrupts", {
    for (operation in c("total", "group")) {
        for (kind in c("error", "interrupt")) {
            gc()
            before <- owned_numeric_info(NULL)
            local({
                source <- freeze_numeric(dta_int(c(2, 1, 2)), 1)
                later <- .Call(C_dtatools_callback_double, c(4, 5, 4), function() {
                    .force_altrep_materialization(source)
                    gc()
                    stop(structure(list(message = "calculation callback stopped", call = NULL),
                                   class = c(kind, "condition")))
                }, TRUE)
                actual <- tryCatch({
                    if (operation == "total") dta_row_total(source, later)
                    else dta_group_id(source, later)
                }, error = identity, interrupt = identity)
                expect_s3_class(actual, kind)
                expect_identical(conditionMessage(actual), "calculation callback stopped")
                expect_identical(as.double(source), c(2, 1, 2))
            })
            gc()
            after <- owned_numeric_info(NULL)
            expect_equal(after[["native_bytes"]], before[["native_bytes"]])
            expect_equal(after[["live_owners"]], before[["live_owners"]])
        }
    }
})

test_that("calculation callbacks cannot change captured immutable input values", {
    source <- freeze_numeric(dta_int(c(1, 2, 3)), 1)
    later <- .Call(C_dtatools_callback_double, c(4, 5, 6), function() {
        .Call(C_dtatools_mutate_first_numeric_altrep, source, 9)
        gc()
    }, TRUE)
    expect_identical(as.double(dta_row_total(later, source)), c(5, 7, 9))
    expect_identical(as.double(source), c(9, 2, 3))
})

test_that("parallel comparison workers split mismatched owned chunk boundaries", {
    values <- rep(c(-1, 0, 1, NA_real_, tagged_missing("a")), 60001)
    plain_x <- dta_int(values)
    plain_y <- dta_int(rev(values))
    x <- freeze_numeric(plain_x, 65531)
    y <- freeze_numeric(plain_y, 65537)
    before <- owned_numeric_info(x)[["compatibility_bytes"]]
    expect_identical(.Call(C_dtatools_dta_compare, 3L, x, y, NULL, 4L),
                     .Call(C_dtatools_dta_compare, 3L, plain_x, plain_y, NULL, 1L))
    actual <- dta_int(rep(0, length(values)))
    expected <- dta_int(rep(0, length(values)))
    .Call(C_dtatools_fused_compare_patch, actual, 4L, x, y, NULL, y, NULL, 4L)
    .Call(C_dtatools_fused_compare_patch, expected, 4L, plain_x, plain_y, NULL, plain_y, NULL, 1L)
    expect_identical(as.double(actual), as.double(expected))
    expect_equal(owned_numeric_info(x)[["compatibility_bytes"]], before)
})

test_that("writers and signatures retain modern and legacy compact sources", {
    paths <- c(tempfile(fileext = ".arrow"), tempfile(fileext = ".arrow"), tempfile(fileext = ".dta"))
    on.exit(unlink(paths), add = TRUE)
    modern <- dibble(b = dta_byte(rep(c(1, NA_real_, tagged_missing("z")), 25001)),
                     i = dta_int(rep(c(2, NA_real_, tagged_missing("a")), 25001)),
                     l = dta_long(rep(c(3, NA_real_, tagged_missing("z")), 25001)),
                     f = dta_float(rep(c(1.25, NA_real_, tagged_missing("a")), 25001)))
    save_arrow(modern, paths[[1L]])
    native <- read_arrow(paths[[1L]])
    legacy <- read_dta(fixture("synthetic_v111.dta"))
    frozen_legacy <- copy_data(legacy)
    for (name in c("b", "i", "l", "f")) {
        if (name %in% names(frozen_legacy)) frozen_legacy[[name]] <- freeze_numeric(legacy[[name]], 1)
    }
    for (case in list(list(expected = modern, actual = native),
                      list(expected = legacy, actual = frozen_legacy))) {
        expected <- case$expected
        actual <- case$actual
        expected_signature <- datasig(expected)
        before <- owned_numeric_info(NULL)[["compatibility_bytes"]]
        expect_identical(datasig(actual), expected_signature)
        save_arrow(actual, paths[[2L]])
        expect_identical(datasig(paths[[2L]]), expected_signature)
        roundtrip <- read_arrow(paths[[2L]])
        for (name in names(expected)) expect_identical(as.vector(roundtrip[[name]]), as.vector(expected[[name]]))
        # The legacy fixture includes labels with codes outside the modern
        # DTA label-table range. Test its numeric writer independently.
        dta_actual <- copy_data(actual)
        for (name in names(dta_actual)) {
            attr(dta_actual[[name]], "labels") <- NULL
            attr(dta_actual[[name]], "value.label.name") <- NULL
        }
        save_dta(dta_actual, paths[[3L]])
        roundtrip <- read_dta(paths[[3L]])
        for (name in names(expected)) expect_identical(as.vector(roundtrip[[name]]), as.vector(expected[[name]]))
        expect_equal(owned_numeric_info(NULL)[["compatibility_bytes"]], before)
        for (name in c("b", "i", "l", "f")) if (name %in% names(actual)) {
            expect_equal(owned_numeric_info(actual[[name]])[["owned"]], 1)
            expect_true(.is_unmaterialized_numeric_altrep(actual[[name]]))
        }
    }
})

test_that("DTA writer pins owned sources while later callbacks materialize them", {
    source <- freeze_numeric(dta_int(c(1, 2, 3)), 1)
    called <- FALSE
    later <- .Call(C_dtatools_callback_double, c(4, 5, 6), function() {
        called <<- TRUE
        .force_altrep_materialization(source)
        gc()
    }, TRUE)
    data <- structure(list(x = source, y = later), class = "data.frame", row.names = c(NA_integer_, -3L))
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    save_dta(data, path)
    expect_true(called)
    actual <- read_dta(path)
    expect_identical(as.double(actual$x), c(1, 2, 3))
    expect_identical(as.double(actual$y), c(4, 5, 6))
})

test_that("Arrow writer and signature pins survive later operand callbacks", {
    for (operation in c("save_arrow", "datasig")) {
        source <- freeze_numeric(dta_int(c(1, 2, 3)), 1)
        called <- FALSE
        later <- .Call(C_dtatools_callback_double, c(4, 5, 6), function() {
            called <<- TRUE
            .force_altrep_materialization(source)
            gc()
        }, FALSE)
        data <- structure(list(x = source, y = later), class = "data.frame", row.names = c(NA_integer_, -3L))
        expected <- data.frame(x = dta_int(c(1, 2, 3)), y = c(4, 5, 6))
        signature <- datasig(expected)
        before <- owned_numeric_info(source)[["compatibility_bytes"]]
        if (operation == "save_arrow") {
            path <- tempfile(fileext = ".arrow")
            expected_path <- tempfile(fileext = ".arrow")
            on.exit(unlink(c(path, expected_path)), add = TRUE)
            save_arrow(expected, expected_path)
            save_arrow(data, path)
            expect_identical(datasig(path), datasig(expected_path))
            actual <- read_arrow(path, output = "tibble")
            expect_identical(datasig(actual), signature)
            expect_identical(as.double(actual$x), c(1, 2, 3))
        } else expect_identical(datasig(data), signature)
        expect_true(called)
        expect_equal(owned_numeric_info(NULL)[["compatibility_bytes"]], before)
        expect_identical(as.double(source), c(1, 2, 3))
    }
})

test_that("legacy writer layout considers an observed conflict in a later chunk", {
    legacy <- read_dta(fixture("synthetic_v111.dta"), output = "tibble")
    source <- legacy$b
    values <- as.double(source)
    observed <- which(!is.na(values) & values <= 100)
    conflicts <- which(!is.na(values) & values > 100)
    expect_gt(length(observed), 0)
    expect_gt(length(conflicts), 0)
    source <- source[c(observed[[1L]], conflicts[[1L]])]
    ordinary <- tibble::tibble(b = source)
    retained <- tibble::tibble(b = freeze_numeric(source, 1))
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    before <- owned_numeric_info(retained$b)[["compatibility_bytes"]]
    expect_identical(datasig(retained), datasig(ordinary))
    save_arrow(retained, path)
    expect_identical(datasig(path), datasig(ordinary))
    expect_identical(as.double(read_arrow(path)$b), as.double(source))
    expect_equal(owned_numeric_info(retained$b)[["compatibility_bytes"]], before)
    expect_equal(owned_numeric_info(retained$b)[["owned"]], 1)
})

test_that("owned sums keep one accumulator across cancelling float regions", {
    # 2^100 makes loss of a unit visible even when long double has an
    # extended mantissa. Combining independently summed two-row chunks would
    # produce zero instead of the sequential accumulator's final one.
    for (large in c(2^55, 2^100)) {
        for (values in list(c(large, 1, -large, 1),
                            c(rep(0, 16383), large, 1, -large, 1))) {
            plain <- dta_float(values)
            for (chunk_rows in c(1, 2, 3, 4096, 16384)) {
                owned <- freeze_numeric(plain, chunk_rows)
                before <- owned_numeric_info(owned)[["compatibility_bytes"]]
                for (remove in c(FALSE, TRUE)) {
                    expect_identical(sum(owned, na.rm = remove), sum(plain, na.rm = remove))
                }
                expect_equal(owned_numeric_info(owned)[["compatibility_bytes"]], before)
            }
        }
    }
    expect_identical(as.double(sum(freeze_numeric(dta_float(c(2^100, 1, -2^100, 1)), 2))), 1)
})

test_that("owned extrema preserve signed zero and missing payload order across regions", {
    bytes <- function(value) writeBin(as.double(value), raw(), size = 8L, endian = "little")
    for (values in list(c(-0, 0), c(0, -0), c(3, -0, 0, 2),
                        c(1, NA_real_, tagged_missing("a"), -1),
                        c(tagged_missing("a"), NA_real_, 1, -1))) {
        plain <- dta_float(values)
        for (chunk_rows in c(1, 2, 3)) {
            owned <- freeze_numeric(plain, chunk_rows)
            for (operation in list(sum, min, max)) for (remove in c(FALSE, TRUE)) {
                expect_identical(bytes(operation(owned, na.rm = remove)),
                                 bytes(operation(plain, na.rm = remove)))
            }
        }
    }

    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    patch_numeric_fixture_row(path, 0L,
                              list(x_float = .raw_little_integer(0x7fc00001, 4L)))
    patch_numeric_fixture_row(path, 1L,
                              list(x_float = .raw_little_integer(0x7f000000, 4L)))
    patch_numeric_fixture_row(path, 3L,
                              list(x_float = .raw_little_integer(0x3f800000, 4L)))
    source <- read_dta(path, col_select = "x_float", n_max = 4L)$x_float
    for (rows in list(c(1L, 2L, 3L, 4L), c(2L, 1L, 3L, 4L), c(3L, 1L, 2L, 4L))) {
        plain <- source[rows]
        owned <- freeze_numeric(plain, 1)
        for (operation in list(sum, min, max)) for (remove in c(FALSE, TRUE)) {
            expect_identical(bytes(operation(owned, na.rm = remove)),
                             bytes(operation(plain, na.rm = remove)))
        }
    }
})

# These stress normal allocation paths, not an exact private detachment window.
with_numeric_gc_stress <- function(code) {
    previous <- gctorture2(1L)
    on.exit(gctorture2(previous), add = TRUE)
    force(code)
}

test_that("retained captures and mutation views survive allocation GC", {
    expected <- c(1, NA_real_, 3, 4)
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        source <- freeze_numeric(constructor(expected), 2)
        expected_attributes <- attributes(source)
        captured <- with_numeric_gc_stress(.Call(C_dtatools_metadata_copy, source))
        nested <- with_numeric_gc_stress(.Call(C_dtatools_metadata_copy, captured))
        data <- list(x = source)
        views <- with_numeric_gc_stress(.Call(C_dtatools_mutation_views, data))
        single <- with_numeric_gc_stress(.Call(C_dtatools_mutation_column_view, data, 1L))
        expect_identical(.Call(C_dtatools_mutation_column_current, data, 1L, single), TRUE)
        expect_identical(attr(views, ".dtatools_mutation_sizes"), 4)
        expect_identical(attr(single, ".dtatools_mutation_sizes"), 4)

        .Call(C_dtatools_mutate_first_numeric_altrep, source, 8)
        gc()
        expect_identical(as.double(source), c(8, NA_real_, 3, 4))
        for (value in list(captured, nested, views[[1L]], single[[1L]])) {
            expect_identical(as.double(value), expected)
            expect_identical(attributes(value), expected_attributes)
        }
        data[[1L]] <- constructor(c(9, NA_real_, 3, 4))
        expect_identical(.Call(C_dtatools_mutation_column_current, data, 1L, single), FALSE)
        expect_identical(as.double(single[[1L]]), expected)
    }
})

test_that("public copying and replacement preserve retained aliases under GC", {
    expected <- c(1, NA_real_, 3, 4)
    data <- dibble(x = freeze_numeric(dta_int(expected), 2))
    saved <- with_numeric_gc_stress(copy_data(data))
    captured <- data$x
    with_numeric_gc_stress(replace_values(data, x = 9, where = c(1L, 3L)))
    gc()
    expect_identical(as.double(data$x), c(9, NA_real_, 9, 4))
    expect_identical(as.double(saved$x), expected)
    expect_identical(as.double(captured), expected)
    expect_identical(names(data), "x")
    expect_identical(names(saved), "x")
    expect_identical(attributes(saved$x), attributes(captured))
    expect_identical(dta_storage_type(data$x), "int")
})

# Use a native REAL_ELT traversal of the original proxy, since public casts
# can create another handle and miss the exact forwarding path.
local({
    owned_scalar_call <- function(name, ...) {
        .Call(get(name, envir = asNamespace("dtatools"), inherits = FALSE), ...)
    }
    owned_scalar_sum <- function(x) owned_scalar_call("C_dtatools_summarize_sum", x)
    owned_scalar_compact <- function(x) {
        get(".is_unmaterialized_numeric_altrep", asNamespace("dtatools"))(x)
    }
    owned_scalar_constructors <- list(
        dtatools::dta_byte, dtatools::dta_int,
        dtatools::dta_long, dtatools::dta_float
    )

    testthat::test_that("metadata scalar forwarding preserves isolated compact captures", {
        for (constructor in owned_scalar_constructors) {
            for (retained in c(FALSE, TRUE)) {
                source <- constructor(c(1, 3, 5))
                if (retained) {
                    source <- owned_scalar_call("C_dtatools_owned_numeric_freeze", source, 2)
                }
                proxy <- owned_scalar_call("C_dtatools_metadata_copy", source)
                attributes_before <- attributes(proxy)
                testthat::expect_identical(
                    owned_scalar_call("C_dtatools_metadata_proxy_depth", proxy), 1L)
                testthat::expect_identical(owned_scalar_sum(proxy), 9)
                testthat::expect_true(owned_scalar_compact(proxy))
                owned_scalar_call("C_dtatools_mutate_first_numeric_altrep", source, 7)
                gc()
                testthat::expect_identical(owned_scalar_sum(source), 15)
                testthat::expect_identical(owned_scalar_sum(proxy), 9)
                testthat::expect_identical(attributes(proxy), attributes_before)
                testthat::expect_true(owned_scalar_compact(proxy))

                tagged <- constructor(c(1, dtatools::tagged_missing("z"), 5))
                if (retained) {
                    tagged <- owned_scalar_call("C_dtatools_owned_numeric_freeze", tagged, 1)
                }
                tagged_proxy <- owned_scalar_call("C_dtatools_metadata_copy", tagged)
                testthat::expect_true(
                    owned_scalar_call("C_dtatools_has_tagged_na", tagged_proxy))
                testthat::expect_true(owned_scalar_compact(tagged_proxy))
            }
        }
    })

    testthat::test_that("metadata scalar forwarding respects both materialized states", {
        for (constructor in owned_scalar_constructors) {
            source <- constructor(c(1, 3, 5))
            # The two-slot view intentionally follows this physical source handle.
            proxy <- owned_scalar_call("C_dtatools_metadata_view", source)
            testthat::expect_identical(owned_scalar_sum(proxy), 9)
            owned_scalar_call("C_dtatools_mutate_first_numeric_altrep", source, 7)
            testthat::expect_identical(owned_scalar_sum(proxy), 15)

            # Once the proxy has its own data2, it must take priority over source.
            owned_scalar_call("C_dtatools_force_altrep_materialization", proxy)
            owned_scalar_call("C_dtatools_mutate_first_numeric_altrep", proxy, 11)
            testthat::expect_identical(owned_scalar_sum(proxy), 19)
            testthat::expect_identical(owned_scalar_sum(source), 15)
            testthat::expect_false(owned_scalar_compact(proxy))
        }
    })

    testthat::test_that("three-slot scalar views track live compact values and missing counts", {
        for (constructor in owned_scalar_constructors) {
            source <- constructor(c(1, 2, 3))
            views <- owned_scalar_call("C_dtatools_mutation_views", list(x = source))
            proxy <- views[[1L]]
            testthat::expect_identical(owned_scalar_sum(proxy), 6)
            testthat::expect_false(anyNA(proxy))

            # No public capture occurs before these writes: the private descriptor
            # shares the original compact bytes and synchronizes missing_count.
            owned_scalar_call("C_dtatools_patch_vector", source, 2L, NA_real_)
            testthat::expect_true(is.na(owned_scalar_sum(proxy)))
            testthat::expect_true(anyNA(proxy))
            owned_scalar_call("C_dtatools_patch_vector", source, 2L, 4)
            testthat::expect_identical(owned_scalar_sum(proxy), 8)
            testthat::expect_false(anyNA(proxy))

            # Physical source materialization must not invalidate the descriptor's
            # retained raw allocation or redirect it to the new writable doubles.
            owned_scalar_call("C_dtatools_mutate_first_numeric_altrep", source, 9)
            gc()
            testthat::expect_identical(owned_scalar_sum(source), 16)
            testthat::expect_identical(owned_scalar_sum(proxy), 8)
            testthat::expect_true(owned_scalar_compact(proxy))
        }
    })

    testthat::test_that("native scalar forwarding does not inspect foreign class metadata", {
        calls <- 0L
        source <- dtatools::dta_int(c(1, 3, 5))
        classes <- owned_scalar_call(
            "C_dtatools_callback_character", class(source), function() NULL)
        attr(source, "class") <- classes
        proxy <- owned_scalar_call("C_dtatools_metadata_view", source)
        owned_scalar_call("C_dtatools_arm_callback_character", classes, function() {
            calls <<- calls + 1L
            stop("foreign scalar class metadata callback")
        })
        testthat::expect_identical(owned_scalar_sum(proxy), 9)
        testthat::expect_identical(calls, 0L)
        testthat::expect_error(classes[[1L]], "foreign scalar class metadata callback")
        testthat::expect_identical(calls, 1L)
    })
})


# Public missing predicates and the guarded native mask producer must agree.
# The native assertion catches a return to generic scalar fallback independently
# of machine speed; the public assertions keep the semantic contract primary.
test_that("compact missing masks cover all tags tails and retained chunk boundaries", {
    constructors <- list(dta_byte, dta_int, dta_long, dta_float)
    pattern <- c(-1, 0, 1, NA_real_, tagged_missing(letters), 5)
    for (constructor in constructors) {
        for (length in c(0:9, 15:17, 31:33, 65)) {
            expected <- rep_len(pattern, length)
            for (chunk_rows in c(0, 1, 7, 32)) {
                value <- constructor(expected)
                if (chunk_rows > 0) value <- freeze_numeric(value, chunk_rows)
                before <- owned_numeric_info(value)[["compatibility_bytes"]]
                expect_identical(is.na(value), is.na(expected))
                expect_identical(is_missing(value), is.na(expected))
                bare <- dtatools:::.dta_data(value)
                expect_identical(.Call(C_dtatools_owned_missing_mask, bare),
                                 is.na(expected))
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(bare))
                expect_equal(owned_numeric_info(value)[["compatibility_bytes"]], before)
            }
        }
    }
})

test_that("compact missing predicates merge columns without changing recycling or names", {
    left_plain <- rep_len(c(1, NA_real_, tagged_missing("a"), 4), 35L)
    right_plain <- rep_len(c(tagged_missing("z"), 2, 3, NA_real_, 5), 35L)
    expected <- is.na(left_plain) | is.na(right_plain)
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        left <- freeze_numeric(constructor(left_plain), 7)
        right <- freeze_numeric(constructor(right_plain), 3)
        expect_identical(is_missing(left, right), expected)
        expect_identical(is_missing(right, left), expected)
        expect_identical(is_missing(left, right, "seen"), expected)
        expect_identical(is_missing(left, right, ""), rep(TRUE, length(expected)))
        names(left) <- paste0("left", seq_along(left))
        names(right) <- paste0("right", seq_along(right))
        expect_identical(is_missing(left, right), setNames(expected, names(left)))
        expect_identical(is_missing(right, left), setNames(expected, names(right)))
        expect_identical(is.na(left), setNames(is.na(left_plain), names(left)))
        expect_identical(.Call(C_dtatools_owned_missing_mask, dtatools:::.dta_data(left)),
                         setNames(is.na(left_plain), names(left)))
        expect_error(is_missing(left, right[-1L]), "size-one recycling")
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(left))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(right))
    }
})

test_that("compact missing masks preserve shape class and materialized fallbacks", {
    plain <- c(1, NA_real_, tagged_missing("b"), 4)
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        value <- freeze_numeric(constructor(plain), 3)
        names(value) <- letters[1:4]
        expect_identical(is.na(value), setNames(is.na(plain), letters[1:4]))
        bare <- as.double(value)
        dim(bare) <- c(2L, 2L)
        dimnames(bare) <- list(c("a", "b"), c("x", "y"))
        ordinary <- matrix(plain, 2L, dimnames = dimnames(bare))
        expect_identical(dtatools:::.dta_read_is_na(bare), is.na(ordinary))
        expect_error(is_missing(bare), "matrix or array")
        class(bare) <- "compact_missing_dispatch"
        rlang::local_bindings(
            is.na.compact_missing_dispatch = function(x) "custom missing dispatch",
            .env = globalenv())
        expect_identical(dtatools:::.dta_read_is_na(bare), "custom missing dispatch")
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))

        materialized <- as.double(value)
        names(materialized) <- letters[1:4]
        .force_altrep_materialization(materialized)
        .Call(C_dtatools_mutate_first_numeric_altrep, materialized, NA_real_)
        expected <- setNames(c(TRUE, TRUE, TRUE, FALSE), letters[1:4])
        expect_identical(dtatools:::.dta_read_is_na(materialized), expected)
        expect_identical(is_missing(materialized), expected)
        expect_identical(is.na(value), setNames(is.na(plain), letters[1:4]))
    }
})

test_that("compact missing masks agree with eager decoding for legacy and modern floats", {
    # Include both IEEE NaN signs, infinities, finite values adjacent to Stata's
    # missing ladder, and entries just outside its modern upper endpoint.
    bits <- c(0, 0x80000000, 0x3f800000, 0xbf800000,
              0x7effffff, 0x7f000000, 0x7f000001, 0x7f0007ff,
              0x7f000800, 0x7f00d000, 0x7f00d001, 0x7f7fffff,
              0x7f800000, 0xff800000, 0x7fc00001, 0xffc00001,
              0x7f800001, 0xff800001, 0xffffffff, 0xff7fffff)
    raw_bits <- function(value) as.raw(floor(value / 256^(0:3)) %% 256)
    paths <- character()
    on.exit(unlink(paths), add = TRUE)
    modern <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    paths <- c(paths, modern)
    for (index in seq_along(bits)) {
        patch_numeric_fixture_row(modern, index - 1L,
                                  list(x_float = raw_bits(bits[[index]])))
    }
    modern_compact <- read_dta(modern, col_select = "x_float", n_max = length(bits))$x_float
    modern_plain <- as.double(read_dta(modern, col_select = "x_float",
                                      n_max = length(bits), use_numeric_altrep = FALSE)$x_float)
    for (value in list(modern_compact, freeze_numeric(modern_compact, 3))) {
        expect_identical(is.na(value), is.na(modern_plain))
        expect_identical(is_missing(value), is.na(modern_plain))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
    }

    # The first row's complete numeric prefix identifies the data block in the
    # redistributable release-111 fixture without assuming header byte offsets.
    original <- readBin(fixture("synthetic_v111.dta"), "raw",
                        n = file.info(fixture("synthetic_v111.dta"))[["size"]])
    prefix <- c(as.raw(1), writeBin(321L, raw(), size = 2L, endian = "little"),
                writeBin(-123456L, raw(), size = 4L, endian = "little"),
                writeBin(1.5, raw(), size = 4L, endian = "little"),
                writeBin(-2.25, raw(), size = 8L, endian = "little"))
    start <- grepRaw(prefix, original, fixed = TRUE, all = TRUE)
    expect_length(start, 1L)
    legacy <- tempfile(fileext = ".dta")
    paths <- c(paths, legacy)
    for (batch in split(bits, ceiling(seq_along(bits) / 4L))) {
        bytes <- original
        for (row in seq_along(batch)) {
            location <- start + (row - 1L) * 25L + 7L
            bytes[location + 0:3] <- raw_bits(batch[[row]])
        }
        writeBin(bytes, legacy)
        compact <- read_dta(legacy, col_select = "f", n_max = length(batch))$f
        plain <- as.double(read_dta(legacy, col_select = "f", n_max = length(batch),
                                    use_numeric_altrep = FALSE)$f)
        for (value in list(compact, freeze_numeric(compact, 1))) {
            expect_identical(is.na(value), is.na(plain))
            expect_identical(is_missing(value), is.na(plain))
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
        }
    }
})

test_that("compact missing masks keep legacy integer missing domains", {
    for (version in c(105L, 108L, 110L, 111L)) {
        path <- fixture(paste0("synthetic_v", version, ".dta"))
        compact <- read_dta(path, output = "tibble")
        eager <- read_dta(path, output = "tibble", use_numeric_altrep = FALSE)
        for (name in names(compact)) {
            source <- compact[[name]]
            if (!dtatools:::.is_unmaterialized_numeric_altrep(source)) next
            expected <- is.na(as.double(eager[[name]]))
            for (value in list(source, freeze_numeric(source, 1))) {
                expect_identical(is.na(value), expected)
                expect_identical(is_missing(value), expected)
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
            }
        }
    }
})

test_that("compact missing predicates preserve foreign callbacks and short circuits", {
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        calls <- 0L
        source <- freeze_numeric(constructor(c(1, NA_real_, 3, 4)), 2)
        later <- .Call(C_dtatools_callback_double, c(NA_real_, 2, NA_real_, 4),
                       function() {
                           calls <<- calls + 1L
                           .force_altrep_materialization(source)
                           gc()
                       }, TRUE)
        expect_identical(is_missing(source, later), c(TRUE, TRUE, TRUE, FALSE))
        expect_gt(calls, 0L)
        calls <- 0L
        all_missing <- freeze_numeric(constructor(rep(NA_real_, 4L)), 3)
        untouched <- .Call(C_dtatools_callback_double, rep(1, 4L),
                           function() calls <<- calls + 1L, TRUE)
        expect_identical(is_missing(all_missing, untouched), rep(TRUE, 4L))
        expect_identical(calls, 0L)
        expect_identical(is_missing(source, untouched, NA_real_), rep(TRUE, 4L))
        expect_identical(calls, 0L)
    }
})

test_that("compact missing masks retain sources and live view facts across GC", {
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        source <- freeze_numeric(constructor(c(1, NA_real_, tagged_missing("z"), 4)), 2)
        expected <- c(FALSE, TRUE, TRUE, FALSE)
        expect_identical(with_numeric_gc_stress(is.na(source)), expected)
        expect_identical(with_numeric_gc_stress(is_missing(source)), expected)
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(source))

        live <- constructor(c(1, 2, 3, 4))
        views <- .Call(C_dtatools_mutation_views, list(x = live))
        proxy <- views[[1L]]
        expect_identical(is.na(proxy), rep(FALSE, 4L))
        .Call(C_dtatools_patch_vector, live, 2L, NA_real_)
        expect_identical(is.na(proxy), c(FALSE, TRUE, FALSE, FALSE))
        expect_identical(is_missing(proxy), c(FALSE, TRUE, FALSE, FALSE))
        .Call(C_dtatools_patch_vector, live, 2L, 8)
        expect_identical(is.na(proxy), rep(FALSE, 4L))
        expect_identical(is_missing(proxy), rep(FALSE, 4L))
    }
})


test_that("compact missing predicates survive reentrant materialization finalizers", {
    arm_finalizer <- function(finalizer) {
        token <- new.env(parent = emptyenv())
        reg.finalizer(token, finalizer, onexit = FALSE)
        invisible(NULL)
    }
    # The finalizer may run before, during, or after the scan. Explicit GC
    # makes collection deterministic without claiming a private allocation window.
    for (predicate in list(is.na, is_missing)) {
        for (retained in c(FALSE, TRUE)) {
            source <- dta_int(c(1, NA_real_, tagged_missing("z"), 4))
            if (retained) source <- freeze_numeric(source, 2)
            fired <- 0L
            prior <- gctorture2(1L)
            tryCatch({
                arm_finalizer(function(key) {
                    fired <<- fired + 1L
                    .force_altrep_materialization(source)
                })
                result <- predicate(source)
                invisible(gc())
            }, finally = gctorture2(prior))
            expect_identical(fired, 1L)
            expect_identical(result, c(FALSE, TRUE, TRUE, FALSE))
            expect_identical(as.double(source), c(1, NA_real_, tagged_missing("z"), 4))
        }
    }
})


test_that("compact temporal missing predicates preserve converted values and all tags", {
    specifications <- list(
        list(kind = 1L, storage = "int", origin = -3653,
             prototype = structure(double(), format.stata = "%td",
                                   class = c("dta_temporal", "dta_date", "Date"))),
        list(kind = 2L, storage = "long", origin = -315619200,
             prototype = structure(double(), format.stata = "%tc", tzone = "UTC",
                                   class = c("dta_temporal", "dta_datetime", "POSIXct", "POSIXt")))
    )
    for (spec in specifications) {
        values <- c(spec$origin + c(-1, 0, 1), NA_real_, tagged_missing(letters))
        source <- dtatools:::.construct_dta_numeric(
            values, NULL, spec$storage, temporal = spec$kind)
        source <- dtatools:::.attach_dta_temporal(source, spec$prototype, spec$storage)
        for (value in list(source, freeze_numeric(source, 2))) {
            names(value) <- paste0("time", seq_along(value))
            before <- attributes(value)
            expect_identical(is.na(value), is.na(values))
            expect_identical(is_missing(value), setNames(is.na(values), names(value)))
            expect_identical(attributes(value), before)
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
            expect_identical(as.double(value), values)
        }
    }
})


test_that("compact sums match ordered ordinary sums across types and missing permutations", {
    sum_bytes <- function(x, remove) {
        writeBin(sum(as.double(x), na.rm = remove), raw(), size = 8L, endian = "little")
    }
    fixtures <- list(numeric(), -0, c(-0, 0), c(0, -0), c(-1, 0, 1),
                     c(NA_real_, tagged_missing("a"), tagged_missing("z")),
                     c(tagged_missing("a"), NA_real_, tagged_missing("z")),
                     c(tagged_missing("z"), tagged_missing("a"), NA_real_),
                     c(1, tagged_missing("a"), -1, NA_real_, tagged_missing("z")),
                     rep_len(c(7, -3, 1, 0, -1), 65L))
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        for (values in fixtures) {
            source <- constructor(values)
            for (chunk_rows in c(0, 1, 3, 16)) {
                value <- if (chunk_rows == 0) source else freeze_numeric(source, chunk_rows)
                before <- owned_numeric_info(value)[["compatibility_bytes"]]
                for (remove in c(FALSE, TRUE)) {
                    expect_identical(sum_bytes(value, remove), sum_bytes(values, remove))
                }
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
                expect_equal(owned_numeric_info(value)[["compatibility_bytes"]], before)
            }
        }
    }
})

test_that("compact sums retain legacy integer domains and non-Stata float payloads", {
    sum_bytes <- function(x, remove) {
        writeBin(sum(as.double(x), na.rm = remove), raw(), size = 8L, endian = "little")
    }
    ordinary <- function(x) {
        readBin(writeBin(as.double(x), raw(), size = 8L), "double", n = length(x))
    }
    for (version in c(105L, 108L, 110L, 111L)) {
        columns <- read_dta(fixture(paste0("synthetic_v", version, ".dta")), output = "tibble")
        for (source in columns) {
            if (!dtatools:::.is_unmaterialized_numeric_altrep(source)) next
            plain <- ordinary(source)
            for (value in list(source, freeze_numeric(source, 1), freeze_numeric(source, 3))) {
                for (remove in c(FALSE, TRUE)) {
                    expect_identical(sum_bytes(value, remove), sum_bytes(plain, remove))
                }
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
            }
        }
    }

    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    bits <- c(0x7fc00001, 0xffc00001, 0x3f800000, 0x7f000000,
              0x7f000800, 0x7f00d000, 0x7f800000, 0xff800000, 0x80000000)
    for (index in seq_along(bits)) {
        raw <- as.raw(floor(bits[[index]] / 256^(0:3)) %% 256)
        patch_numeric_fixture_row(path, index - 1L, list(x_float = raw))
    }
    source <- read_dta(path, col_select = "x_float", n_max = length(bits))$x_float
    for (rows in list(1:9, 9:1, c(4L, 1L, 5L, 2L, 6L),
                      c(5L, 1L, 4L, 2L, 6L), c(6L, 2L, 1L, 5L, 4L),
                      c(7L, 8L, 3L), c(8L, 7L, 3L), c(9L, 3L))) {
        selected <- source[rows]
        plain <- ordinary(selected)
        for (value in list(selected, freeze_numeric(selected, 1), freeze_numeric(selected, 4))) {
            for (remove in c(FALSE, TRUE)) {
                expect_identical(sum_bytes(value, remove), sum_bytes(plain, remove))
            }
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
        }
    }
})

test_that("compact sums apply date and datetime conversion before ordered accumulation", {
    sum_bytes <- function(x, remove) {
        writeBin(sum(as.double(x), na.rm = remove), raw(), size = 8L, endian = "little")
    }
    specifications <- list(
        list(kind = 1L, origin = -3653, storages = c("byte", "int", "long", "float")),
        list(kind = 2L, origin = -315619200, storages = c("int", "long", "float"))
    )
    for (spec in specifications) {
        fixtures <- list(numeric(), spec$origin + c(-1, 0, 1),
                         c(NA_real_, tagged_missing("a"), tagged_missing("z")),
                         c(spec$origin - 1, tagged_missing("z"), spec$origin + 1, NA_real_))
        for (storage in spec$storages) {
            for (values in fixtures) {
                source <- dtatools:::.construct_dta_numeric(values, NULL, storage, temporal = spec$kind)
                for (value in list(source, freeze_numeric(source, 1), freeze_numeric(source, 3))) {
                    for (remove in c(FALSE, TRUE)) {
                        expect_identical(sum_bytes(value, remove), sum_bytes(values, remove))
                    }
                    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
                }
            }
        }
    }
})
