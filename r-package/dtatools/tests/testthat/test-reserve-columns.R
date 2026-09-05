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

test_that("preparation preserves containers and isolates column values", {
    for (x in list(data.frame(x = 1:100), tibble::tibble(x = 1:100), dibble(x = 1:100))) {
        address <- rlang::obj_address(x$x)
        y <- reserve_columns(x, 5)
        expect_identical(class(y), class(x))
        expect_identical(is_dibble(y), is_dibble(x))
        expect_false(identical(rlang::obj_address(y$x), address))
        expect_identical(as.integer(y$x), as.integer(x$x))
        expect_false(identical(rlang::obj_address(y), rlang::obj_address(x)))
        expect_equal(column_capacity(y), 6)
        expect_physical_table(y)
    }
    skip_if_not_installed("data.table")
    x <- data.table::data.table(x = 1:100)
    y <- reserve_columns(x, 5)
    expect_identical(class(y), class(x))
    expect_false(identical(rlang::obj_address(x$x), rlang::obj_address(y$x)))
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

test_that("serialized dibble preparation repairs explicit mutation aliases", {
    x <- unserialize(serialize(dibble(x = 1:3), NULL))
    expect_equal(column_capacity(x), -1)
    x <- reserve_columns(x, 2)
    alias <- x
    gen(x, y = 4:6)
    expect_physical_table(alias, c("x", "y"))
    expect_identical(dta_storage_type(alias$y), "long")
    repl(x, x = 9:11)
    expect_identical(as.integer(alias$x), 9:11)
    expect_true(dtatools:::.reference_state_valid(x))
    expect_null(dtatools:::.reference_state(x)$object)
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
        for (replace in list(
            function(data) { data$extra <- 1:3; data },
            function(data) { data[["extra"]] <- 1:3; data },
            function(data) { data["extra"] <- list(1:3); data }
        )) {
            x <- legacy_column_table(structural)
            before <- serialize(x, NULL)
            expect_silent(y <- replace(x))
            expect_true(is_dibble(y))
            expect_physical_table(y)
            expect_identical(as.integer(y$extra), 1:3)
            expect_identical(serialize(x, NULL), before)
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
        function(data) { data["y"] <- list(4:6); data }
    )) {
        x <- dibble(x = 1:3)
        expect_silent(y <- op(x))
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

test_that("get and get0 destinations are evaluated only once", {
    withr::local_options(dtatools.alloccol = 0L)
    for (getter in c("get", "get0")) {
        a <- data.frame(x = 1:2)
        b <- data.frame(z = 3:4)
        calls <- 0L
        name <- function() { calls <<- calls + 1L; c("a", "b")[[calls]] }
        call <- substitute(gen(FUN(name()), y = .data$x + 1L), list(FUN = as.name(getter)))
        expect_warning(eval(call), "reallocation")
        expect_identical(calls, 1L)
        expect_physical_table(a, c("x", "y"))
        expect_physical_table(b, "z")
        e1 <- new.env(); e2 <- new.env()
        e1$a <- data.frame(x = 1:2); e2$a <- data.frame(z = 3:4)
        calls <- 0L
        environment <- function() { calls <<- calls + 1L; if (calls == 1L) e1 else e2 }
        call <- substitute(gen(FUN("a", envir = environment()), y = .data$x + 1L), list(FUN = as.name(getter)))
        expect_warning(eval(call), "reallocation")
        expect_identical(calls, 1L)
        expect_physical_table(e1$a, c("x", "y"))
        expect_physical_table(e2$a, "z")
    }
})

test_that("captured extraction indices do not change when values run", {
    withr::local_options(dtatools.alloccol = 0L)
    box <- list(a = data.frame(x = 1:2), b = data.frame(z = 3:4))
    index <- "a"
    values <- function() { index <<- "b"; 1L }
    expect_warning(gen(box[[index]], y = values()), "reallocation")
    expect_physical_table(box$a, c("x", "y"))
    expect_physical_table(box$b, "z")
    expect_identical(index, "b")
})

test_that("a changed getter destination is never overwritten", {
    withr::local_options(dtatools.alloccol = 0L)
    a <- data.frame(x = 1:2)
    values <- function() { a <<- data.frame(z = 3:4); 1L }
    warnings <- character()
    result <- withCallingHandlers(gen(get("a"), y = values()), warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
    })
    expect_true(any(grepl("target changed", warnings)))
    expect_physical_table(a, "z")
    expect_physical_table(result, c("x", "y"))
})

test_that("bracket dispatch does not reevaluate computed getters", {
    withr::local_options(dtatools.alloccol = 0L)
    a <- dibble(x = 1:2)
    b <- dibble(z = 3:4)
    calls <- 0L
    name <- function() { calls <<- calls + 1L; c("a", "b")[[calls]] }
    expect_warning(result <- get(name())[, y := 1L], "reallocation")
    expect_identical(calls, 1L)
    expect_physical_table(a, "x")
    expect_physical_table(b, "z")
    expect_physical_table(result, c("x", "y"))
})

test_that("literal bracket getters rebind without rerunning their lookup", {
    withr::local_options(dtatools.alloccol = 0L)
    for (getter in c("get", "get0")) {
        a <- dibble(x = 1:2)
        alias <- a
        call <- substitute(FUN("a")[, y := 1L], list(FUN = as.name(getter)))
        expect_warning(eval(call), "reallocation")
        expect_physical_table(a, c("x", "y"))
        expect_physical_table(alias, "x")
        e <- new.env(); e$a <- dibble(x = 1:2)
        call <- substitute(FUN("a", envir = e)[, y := 1L], list(FUN = as.name(getter)))
        expect_warning(eval(call), "reallocation")
        expect_physical_table(e$a, c("x", "y"))
    }
})

test_that("replaced extraction containers are never read or overwritten", {
    withr::local_options(dtatools.alloccol = 0L)
    for (extraction in c("$", "[[")) {
        for (replacement in list(42L, list(data = data.frame(z = 3:4)))) {
            box <- list(data = data.frame(x = 1:2))
            original <- box$data
            values <- function() { box <<- replacement; 1L }
            target <- as.call(list(as.name(extraction), quote(box), "data"))
            call <- substitute(gen(TARGET, y = values()), list(TARGET = target))
            warnings <- character()
            result <- withCallingHandlers(eval(call), warning = function(w) {
                warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
            })
            expect_true(any(grepl("target changed", warnings)))
            expect_identical(box, replacement)
            expect_physical_table(original, "x")
            expect_physical_table(result, c("x", "y"))
        }
        # A new container holding the same original table is still a changed
        # destination. Rebinding must not modify it behind the values' back.
        box <- list(data = data.frame(x = 1:2))
        original <- box$data
        values <- function() { box <<- list(data = original, sibling = 99L); 1L }
        target <- as.call(list(as.name(extraction), quote(box), "data"))
        call <- substitute(gen(TARGET, y = values()), list(TARGET = target))
        warnings <- character()
        result <- withCallingHandlers(eval(call), warning = function(w) {
            warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
        })
        expect_true(any(grepl("target changed", warnings)))
        expect_physical_table(box$data, "x")
        expect_identical(box$sibling, 99L)
        expect_physical_table(result, c("x", "y"))
    }
})
