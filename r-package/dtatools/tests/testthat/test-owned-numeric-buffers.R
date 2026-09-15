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
