column_capacity <- function(x) .Call(dtatools:::C_dtatools_column_capacity, x)
expect_physical_table <- function(x, expected = names(x)) {
    expect_identical(length(unclass(x)), length(expected))
    expect_identical(ncol(x), length(expected))
    expect_identical(names(x), expected)
    expect_identical(names(.subset(x)), expected)
    expect_identical(attributes(x)$names, expected)
    for (i in seq_along(expected)) expect_identical(.subset2(x, i), x[[i]])
}
legacy_column_table <- function(structural = FALSE) {
    data <- dibble(x = c(3L, 1L, 2L), z = c(30L, 10L, 20L))
    state <- dtatools:::.reference_state(data)
    if (structural) {
        cols <- list(y = dta_long(c(6L, 2L, 4L)), x = data$x)
        state <- dtatools:::.new_structural_reference_state(
            cols, 3L, state$classes, dibble = TRUE
        )
        dtatools:::.mark_reference_data(data, state)
    } else {
        dtatools:::.append_generated_column(state, "y", dta_long(c(6L, 2L, 4L)))
        data
    }
}

test_that("capacity reserves spare pointers and validates the option", {
    withr::local_options(dtatools.alloccol = NULL)
    x <- dibble(x = 1:2)
    expect_equal(column_capacity(x), 5001)
    for (n in c(0, 1, 13)) {
        withr::local_options(dtatools.alloccol = n)
        expect_equal(column_capacity(dibble(x = 1:2)), n + 1)
        expect_equal(column_capacity(reserve_columns(data.frame(x = 1:2))), n + 1)
    }
    for (n in list(-1, Inf, NA_real_, NaN, 0.5, "5", TRUE, numeric(), c(1, 2), 2^52)) {
        expect_error(reserve_columns(data.frame(x = 1), n), "whole number")
        withr::local_options(dtatools.alloccol = n)
        expect_error(dibble(x = 1), "whole number")
    }
})

test_that("preparation preserves each container and payload identity", {
    for (x in list(data.frame(x = 1:100), tibble::tibble(x = 1:100), dibble(x = 1:100))) {
        address <- rlang::obj_address(x$x)
        y <- reserve_columns(x, 5)
        expect_identical(class(y), class(x))
        expect_identical(is_dibble(y), is_dibble(x))
        expect_identical(rlang::obj_address(y$x), address)
        expect_false(identical(rlang::obj_address(y), rlang::obj_address(x)))
        expect_equal(column_capacity(y), 6)
        expect_physical_table(y)
    }
    skip_if_not_installed("data.table")
    x <- data.table::data.table(x = 1:100)
    y <- reserve_columns(x, 5)
    expect_identical(class(y), class(x))
    expect_identical(rlang::obj_address(x$x), rlang::obj_address(y$x))
    expect_equal(column_capacity(y), 6)
    gen(y, z = .data$x + 1L)
    expect_physical_table(y, c("x", "z"))
    expect_physical_table(x, "x")
})

test_that("append consumes capacity then rebinds without partial aliases", {
    withr::local_options(dtatools.alloccol = 1L)
    x <- dibble(x = 1:2)
    old <- x
    address <- rlang::obj_address(x)
    expect_silent(gen(x, y = .data$x + 1L))
    expect_identical(rlang::obj_address(x), address)
    expect_physical_table(old, c("x", "y"))
    expect_warning(gen(x, z = .data$x + 2L), "reallocation")
    expect_false(identical(rlang::obj_address(x), address))
    expect_physical_table(x, c("x", "y", "z"))
    expect_physical_table(old, c("x", "y"))
    newer <- x
    expect_silent(gen(x, w = .data$x + 3L))
    expect_physical_table(newer, c("x", "y", "z", "w"))
})

test_that("all supported mutation targets are rebound", {
    withr::local_options(dtatools.alloccol = 0L)
    x <- data.frame(x = 1:2)
    expect_warning(gen(x, y = .data$x + 1), "reallocation")
    expect_physical_table(x, c("x", "y"))
    box <- list(data = data.frame(x = 1:2))
    expect_warning(gen(box$data, y = .data$x + 1), "reallocation")
    expect_physical_table(box$data, c("x", "y"))
    box <- list(data = data.frame(x = 1:2))
    key <- "data"
    expect_warning(gen(box[[key]], y = .data$x + 1), "reallocation")
    expect_physical_table(box[[key]], c("x", "y"))
    e <- new.env()
    e$data <- data.frame(x = 1:2)
    expect_warning(gen(e$data, y = .data$x + 1), "reallocation")
    expect_physical_table(e$data, c("x", "y"))
    for (getter in c("get", "get0")) {
        e$data <- data.frame(x = 1:2)
        call <- substitute(gen(FUN("data", envir = e), y = .data$x + 1), list(FUN = as.name(getter)))
        expect_warning(eval(call), "reallocation")
        expect_physical_table(e$data, c("x", "y"))
    }
    x <- data.frame(x = 1:2)
    expect_warning(gen(get("x"), y = .data$x + 1), "reallocation")
    expect_physical_table(x, c("x", "y"))
})

test_that("function parameter rebuilding is local and returned for assignment", {
    x <- reserve_columns(data.frame(x = 1:2), 0)
    alias <- x
    f <- function(data) { gen(data, y = .data$x + 1); data }
    expect_warning(result <- f(x), "reallocation")
    expect_physical_table(x, "x")
    expect_physical_table(alias, "x")
    expect_physical_table(result, c("x", "y"))
    prepared <- reserve_columns(x, 2)
    expect_silent(f(prepared))
    expect_physical_table(prepared, c("x", "y"))
})

test_that("serialized dibble preparation repairs current-object replacement aliases", {
    x <- unserialize(serialize(dibble(x = 1:3), NULL))
    expect_equal(column_capacity(x), -1)
    x <- reserve_columns(x, 2)
    alias <- x
    x$y <- 4:6
    expect_physical_table(alias, c("x", "y"))
    expect_identical(dta_storage_type(alias$y), "long")
    x$x <- 9:11
    expect_identical(as.integer(alias$x), 9:11)
    expect_identical(dtatools:::.reference_state(x)$object, x)
    restored <- unserialize(serialize(dibble(x = 1:3), NULL))
    expect_warning(gen(restored, y = .data$x + 1L), "reallocation")
    expect_physical_table(restored, c("x", "y"))
})

test_that("all structural operations rebuild both kinds of legacy overlays", {
    for (structural in c(FALSE, TRUE)) {
        x <- legacy_column_table(structural)
        y <- reserve_columns(x, 3)
        expect_physical_table(y)
        expect_identical(as.integer(y$y), c(6L, 2L, 4L))
        operations <- list(
            function(data) { gen(data, extra = .data$y + 1L); data },
            function(data) { keep_vars(data, x); data },
            function(data) { drop_vars(data, y); data },
            function(data) { order_vars(data, x); data },
            function(data) { rename_vars(data, renamed = y); data },
            function(data) { data$extra <- 1:3; data },
            function(data) { data[["extra"]] <- 1:3; data },
            function(data) { data["extra"] <- list(1:3); data },
            function(data) { reorder_dta_rows(data, c(2L, 3L, 1L)); data },
            function(data) { gen(data, extra = .data$y + 1L, bysort = x); data },
            function(data) { data[, extra := .data$y + 1L]; data }
        )
        for (op in operations) {
            x <- legacy_column_table(structural)
            expect_warning(y <- op(x), "reallocation")
            expect_physical_table(y)
            expect_false(dtatools:::.has_column_overlay(y))
        }
        x <- legacy_column_table(structural)
        expect_warning(reorder_dta_rows(x, c(2L, 3L, 1L)), "reallocation")
        expect_identical(as.integer(x$x), 1:3)
        expect_identical(as.integer(x$y), c(2L, 4L, 6L))
    }
})

test_that("direct consumers retain columns and rows after reallocation", {
    withr::local_options(dtatools.alloccol = 0L)
    x <- dibble(x = c(3L, 1L, 2L))
    expect_warning(gen(x, y = .data$x * 2L), "reallocation")
    reorder_dta_rows(x, c(2L, 3L, 1L))
    expect_physical_table(x, c("x", "y"))
    expect_identical(names(dplyr::bind_rows(x, x)), c("x", "y"))
    expect_identical(names(dplyr::bind_cols(x, tibble::tibble(z = 1:3))), c("x", "y", "z"))
    if (requireNamespace("purrr", quietly = TRUE)) expect_named(purrr::map(x, as.integer), c("x", "y"))
    if (requireNamespace("jsonlite", quietly = TRUE)) {
        json <- jsonlite::fromJSON(jsonlite::toJSON(x))
        expect_named(json, c("x", "y"))
        expect_identical(json$x, 1:3)
    }
    path <- tempfile(fileext = ".csv")
    on.exit(unlink(path))
    write.csv(x, path, row.names = FALSE)
    csv <- read.csv(path)
    expect_named(csv, c("x", "y"))
    expect_identical(csv$y, c(2L, 4L, 6L))
})

test_that("validation and warning interruptions leave the old object complete", {
    withr::local_options(dtatools.alloccol = 0L)
    x <- dibble(x = 1:3)
    alias <- x
    before <- serialize(x, NULL)
    expect_error(gen(x, y = stop("bad values")), "bad values")
    expect_identical(serialize(x, NULL), before)
    expect_error(withCallingHandlers(gen(x, y = .data$x + 1), warning = function(w) stop("interrupted")), "interrupted")
    expect_identical(serialize(alias, NULL), before)
    expect_physical_table(x, "x")
    expect_error(keep_vars(x, missing), "not found|Unknown|exist")
    expect_physical_table(alias, "x")
})

test_that("replacement and bracket growth rebind at capacity boundaries", {
    withr::local_options(dtatools.alloccol = 0L)
    for (op in list(
        function(data) { data$y <- 4:6; data },
        function(data) { data[["y"]] <- 4:6; data },
        function(data) { data["y"] <- list(4:6); data },
        function(data) { data[, y := 4:6]; data }
    )) {
        x <- dibble(x = 1:3)
        expect_warning(y <- op(x), "reallocation")
        expect_physical_table(x, "x")
        expect_physical_table(y, c("x", "y"))
        expect_true(is_dibble(y))
        expect_identical(dta_storage_type(y$y), "long")
    }
})

test_that("no-op selections still rebuild legacy overlays", {
    for (structural in c(FALSE, TRUE)) {
        for (op in list(
            function(data) { keep_vars(data, tidyselect::all_of(names(data))); data },
            function(data) { order_vars(data, tidyselect::all_of(names(data))); data },
            function(data) { rename_vars(data, .names = names(data)); data },
            function(data) { rename_vars(data, y = y); data }
        )) {
            x <- legacy_column_table(structural)
            expect_warning(y <- op(x), "reallocation")
            expect_physical_table(y)
        }
    }
})
