owned_numeric_info <- function(x) .Call(C_dtatools_owned_numeric_info, x)
freeze_numeric <- function(x, chunk_rows = 2) {
    .Call(C_dtatools_owned_numeric_freeze, x, chunk_rows)
}

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

test_that("owned Arrow experiment retains buffers independently of its source", {
    withr::local_envvar(DTATOOLS_EXPERIMENT_ARROW_OWNED = "1")
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
    withr::local_envvar(DTATOOLS_EXPERIMENT_ARROW_OWNED = "1")
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
    withr::local_envvar(DTATOOLS_EXPERIMENT_ARROW_OWNED = "1")
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
    withr::local_envvar(DTATOOLS_EXPERIMENT_ARROW_OWNED = "1")
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
    withr::local_envvar(DTATOOLS_EXPERIMENT_ARROW_OWNED = "1")
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
