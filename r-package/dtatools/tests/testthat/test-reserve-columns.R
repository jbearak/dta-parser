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

test_that("public capacity separates type, preparation, and spare slots", {
    withr::local_options(dtatools.alloccol = NULL)
    expect_equal(column_capacity(dibble(x = 1:2)), 5001)
    for (n in c(0, 1, 13)) {
        withr::local_options(dtatools.alloccol = n)
        for (x in list(dibble(x = 1:2), reserve_columns(data.frame(x = 1:2)))) {
            expect_equal(column_capacity(x), n + 1)
            expect_true(can_add_columns(x, n))
            expect_false(can_add_columns(x, n + 1))
        }
    }
    for (x in list(data.frame(x = 1:2), tibble::tibble(x = 1:2),
                   unserialize(serialize(dibble(x = 1:2), NULL)))) {
        expect_identical(column_capacity(x), NA_real_)
        expect_true(can_add_columns(x, 0))
        expect_false(can_add_columns(x))
    }
    x <- unserialize(serialize(dibble(x = 1:2), NULL))
    expect_true(is_dibble(x))
    expect_false(dtatools:::.reference_state_valid(x))
    expect_false(can_add_columns(x))
    for (n in list(-1, Inf, NA_real_, NaN, .5, "5", TRUE, numeric(), c(1, 2), 2^52)) {
        expect_error(reserve_columns(data.frame(x = 1), n), "whole number")
        expect_error(can_add_columns(data.frame(x = 1), n), "whole number")
        withr::local_options(dtatools.alloccol = n)
        expect_error(dibble(x = 1), "whole number")
    }
    expect_error(column_capacity(list(x = 1)), "data frame")
    expect_error(can_add_columns(list(x = 1)), "data frame")
})

test_that("preparation preserves containers and isolates column values", {
    constructors <- list(data.frame, tibble::tibble, dibble)
    if (requireNamespace("data.table", quietly = TRUE)) {
        constructors <- c(constructors, list(data.table::data.table))
    }
    for (make in constructors) {
        x <- make(x = 1:100)
        y <- reserve_columns(x, 5)
        expect_identical(class(y), class(x))
        expect_identical(is_dibble(y), is_dibble(x))
        expect_false(identical(rlang::obj_address(y$x), rlang::obj_address(x$x)))
        expect_identical(as.integer(y$x), as.integer(x$x))
        expect_false(identical(rlang::obj_address(y), rlang::obj_address(x)))
        expect_gte(column_capacity(y), 6)
        expect_true(can_add_columns(y, 5))
        gen(y, z = .data$x + 1L)
        expect_physical_table(y, c("x", "z"))
        expect_physical_table(x, "x")
    }
})

test_that("capacity exhaustion fails before writes and assigned repair isolates aliases", {
    x <- reserve_columns(dibble(x = 1:2), 1)
    alias <- x
    address <- rlang::obj_address(x)
    expect_silent(gen(x, y = .data$x + 1L))
    expect_identical(rlang::obj_address(x), address)
    before <- serialize(x, NULL)
    expect_error(gen(x, z = stop("RHS ran")), "Assign.*reserve_columns")
    expect_identical(serialize(alias, NULL), before)
    x <- reserve_columns(x, 2)
    expect_false(identical(rlang::obj_address(x), address))
    newer <- x
    expect_silent(gen(x, z = .data$x + 2L))
    expect_physical_table(newer, c("x", "y", "z"))
    expect_physical_table(alias, c("x", "y"))
})

test_that("capacity contract is identical for all target expressions", {
    for (prepared in c(FALSE, TRUE)) {
        make <- function() {
            x <- data.frame(x = 1:2)
            if (prepared) reserve_columns(x, 1) else x
        }
        run <- function(call, target) {
            alias <- target
            before <- serialize(alias, NULL)
            if (prepared) {
                expect_silent(eval(call, parent.frame()))
                expect_physical_table(alias, c("x", "y"))
            } else {
                expect_error(eval(call, parent.frame()), "Assign.*reserve_columns")
                expect_identical(serialize(alias, NULL), before)
            }
        }
        x <- make(); run(quote(gen(x, y = .data$x + 1)), x)
        box <- list(data = make()); run(quote(gen(box$data, y = 1)), box$data)
        key <- "data"
        box <- list(data = make()); run(quote(gen(box[[key]], y = 1)), box$data)
        e <- new.env(); e$data <- make(); run(quote(gen(e$data, y = 1)), e$data)
        for (getter in c("get", "get0")) {
            e$data <- make()
            run(substitute(gen(FUN("data", envir = e), y = 1),
                           list(FUN = as.name(getter))), e$data)
        }
        x <- make(); run(quote(gen(get("x"), y = 1)), x)
        x <- make(); f <- function(data) { gen(data, y = 1); invisible(NULL) }
        run(quote(f(x)), x)
        x <- make(); computed <- function() x
        run(quote(gen(computed(), y = 1)), x)
    }
})

test_that("getters run once and RHS target changes cannot redirect writes", {
    for (getter in c("get", "get0")) {
        a <- reserve_columns(data.frame(x = 1:2), 1)
        b <- data.frame(z = 3:4)
        calls <- 0L
        name <- function() { calls <<- calls + 1L; c("a", "b")[[calls]] }
        call <- substitute(gen(FUN(name()), y = 1), list(FUN = as.name(getter)))
        expect_silent(eval(call))
        expect_identical(calls, 1L)
        expect_physical_table(a, c("x", "y"))
        expect_physical_table(b, "z")
    }
    box <- list(a = reserve_columns(data.frame(x = 1:2), 1), b = data.frame(z = 3:4))
    index <- "a"
    values <- function() { index <<- "b"; 1L }
    expect_silent(gen(box[[index]], y = values()))
    expect_physical_table(box$a, c("x", "y"))
    expect_physical_table(box$b, "z")
    expect_identical(index, "b")
    for (replacement in list(42L, list(data = data.frame(z = 3:4)))) {
        box <- list(data = reserve_columns(data.frame(x = 1:2), 1))
        original <- box$data
        values <- function() { box <<- replacement; 1L }
        result <- gen(box$data, y = values())
        expect_identical(box, replacement)
        expect_identical(rlang::obj_address(result), rlang::obj_address(original))
        expect_physical_table(original, c("x", "y"))
    }
})

test_that("growth rejects row selection and sorting before they run", {
    for (make in list(data.frame, tibble::tibble, dibble)) {
        for (operation in c("gen", "egen")) {
            x <- reserve_columns(make(id = c(2L, 1L), x = 3:4), 0)
            alias <- x
            before <- serialize(x, NULL)
            effects <- 0L
            rhs <- function() { effects <<- effects + 1L; 1 }
            call <- substitute(FUN(x, y = rhs(), where = { effects <<- effects + 1L; TRUE }, bysort = id),
                               list(FUN = as.name(operation)))
            expect_error(eval(call), "Assign.*reserve_columns")
            expect_identical(effects, 0L)
            expect_identical(serialize(alias, NULL), before)
        }
        for (operation in c("keep_vars", "drop_vars")) {
            x <- unserialize(serialize(make(id = 1:2, x = 3:4), NULL))
            alias <- x
            before <- serialize(x, NULL)
            effects <- 0L
            selection <- function() { effects <<- effects + 1L; "id" }
            call <- substitute(FUN(x, tidyselect::all_of(selection())), list(FUN = as.name(operation)))
            expect_error(eval(call), "Assign.*reserve_columns")
            expect_identical(effects, 1L)
            expect_error(do.call(operation, list(x, quote(absent))), "does not exist")
            expect_error(do.call(operation, list(x, quote(tidyselect::all_of(character())))), "at least one")
            expect_identical(serialize(alias, NULL), before)
        }
    }
})

test_that("multi-assignment preflights all new names before its first write", {
    x <- reserve_columns(dibble(id = c(2L, 1L), x = 3:4), 1)
    alias <- x
    before <- serialize(x, NULL)
    expect_error(x[stop("selection ran"), `:=`(x = 0, y = 1, z = 2), bysort = id],
                 "Assign.*reserve_columns")
    expect_identical(serialize(alias, NULL), before)
    expect_error(x[, c("y", "y") := list(stop("RHS ran"), 1L)], "names each column once")
    expect_identical(serialize(alias, NULL), before)
    expect_silent(x[, `:=`(x = .data$x + 1L, y = .data$x + 1L)])
    expect_identical(as.integer(alias$y), 5:6)
    expect_physical_table(alias, c("id", "x", "y"))
    expect_error(x[, `:=`(y = 0L, x = stop("later RHS"))], "later RHS")
    expect_identical(as.integer(alias$y), c(0L, 0L))
    a <- reserve_columns(dibble(x = 1:2), 1)
    calls <- 0L
    name <- function() { calls <<- calls + 1L; "a" }
    expect_silent(get(name())[, y := 1])
    expect_identical(calls, 1L)
    expect_physical_table(a, c("x", "y"))
})

test_that("same-size writes need no spare capacity but shrinking needs preparation", {
    for (make in list(data.frame, tibble::tibble, dibble)) {
        x <- unserialize(serialize(make(x = 1:3, y = 4:6), NULL))
        expect_identical(column_capacity(x), NA_real_)
        alias <- x
        expect_silent(repl(x, x = 0L))
        expect_silent(set_var_format(x, x, "%9.0g"))
        expect_silent(rename_vars(x, renamed = x))
        expect_silent(order_vars(x, y))
        expect_silent(reorder_dta_rows(x, 3:1))
        expect_physical_table(alias, c("y", "renamed"))
        expect_identical(as.integer(alias$y), 6:4)
        expect_error(drop_vars(x, y), "Assign.*reserve_columns")
        x <- reserve_columns(x, 0)
        newer <- x
        expect_silent(drop_vars(x, y))
        expect_physical_table(newer, "renamed")
        expect_physical_table(alias, c("y", "renamed"))
    }
})

test_that("copying, subsetting, and serialization have assigned preparation paths", {
    for (make in list(data.frame, tibble::tibble, dibble)) {
        original <- reserve_columns(make(x = 1:3, y = 4:6), 2)
        copied <- copy_data(original)
        expect_true(can_add_columns(copied))
        expect_identical(class(copied), class(original))
        for (copy in list(function(x) { attr(x, "notes") <- "note"; x },
                         function(x) x[1:2, ], function(x) x["x"],
                         function(x) unserialize(serialize(x, NULL)),
                         function(x) { path <- tempfile(); on.exit(unlink(path)); saveRDS(x, path); readRDS(path) })) {
            x <- copy(original)
            before <- serialize(original, NULL)
            prepared <- reserve_columns(x, 1)
            alias <- prepared
            expect_true(can_add_columns(prepared))
            expect_identical(class(prepared), class(x))
            expect_silent(gen(prepared, z = 1))
            expect_physical_table(alias, c(names(x), "z"))
            expect_identical(serialize(original, NULL), before)
        }
    }
    original <- dibble(x = 1:3)
    copied <- original; attr(copied, "notes") <- "copy"
    pair <- unserialize(serialize(list(original, copied), NULL))
    before <- serialize(pair, NULL)
    fixed <- reserve_columns(pair[[2L]], 1)
    gen(fixed, z = 1)
    repl(fixed, x = 0L)
    expect_true(dtatools:::.reference_state_valid(fixed))
    expect_null(dtatools:::.reference_state(fixed)$object)
    expect_identical(serialize(pair, NULL), before)
})

test_that("legacy overlays require assigned preparation even for no-op helpers", {
    for (structural in c(FALSE, TRUE)) {
        for (op in list(function(x) gen(x, extra = .data$y + 1L),
                        function(x) keep_vars(x, tidyselect::all_of(names(x))),
                        function(x) drop_vars(x, y), function(x) order_vars(x, x),
                        function(x) rename_vars(x, .names = names(x)),
                        function(x) rename_vars(x, y = y),
                        function(x) reorder_dta_rows(x, c(2L, 3L, 1L)),
                        function(x) gen(x, extra = .data$y + 1L, bysort = x),
                        function(x) x[, extra := .data$y + 1L])) {
            x <- legacy_column_table(structural)
            before <- serialize(x, NULL)
            expect_false(can_add_columns(x, 0))
            expect_error(op(x), "Assign.*reserve_columns")
            expect_identical(serialize(x, NULL), before)
            x <- reserve_columns(x, 3)
            expect_silent(op(x))
            expect_physical_table(x)
            expect_false(dtatools:::.has_column_overlay(x))
        }
        for (replace in list(function(x) { x$extra <- 1:3; x },
                             function(x) { x[["extra"]] <- 1:3; x },
                             function(x) { x["extra"] <- list(1:3); x })) {
            x <- legacy_column_table(structural)
            before <- serialize(x, NULL)
            expect_silent(y <- replace(x))
            expect_true(is_dibble(y))
            expect_physical_table(y)
            expect_identical(as.integer(y$extra), 1:3)
            expect_identical(serialize(x, NULL), before)
        }
    }
})

test_that("zero-column tables can reserve and consume their first slot", {
    for (make in list(data.frame, tibble::tibble, dibble)) {
        x <- reserve_columns(make(), 0)
        expect_identical(column_capacity(x), NA_real_)
        expect_true(can_add_columns(x, 0))
        expect_false(can_add_columns(x))
        expect_error(gen(x, y = integer()), "Assign.*reserve_columns")
        x <- reserve_columns(x, 1)
        alias <- x
        expect_silent(gen(x, y = integer()))
        expect_physical_table(alias, "y")
        expect_equal(nrow(alias), 0)
    }
})

test_that("prepared physical columns remain visible to direct consumers", {
    x <- reserve_columns(dibble(x = c(3L, 1L, 2L)), 1)
    gen(x, y = .data$x * 2L)
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

test_that("data.table readiness requires valid self-reference and preserves lookups on failure", {
    .datatable.aware <- TRUE
    skip_if_not_installed("data.table")
    for (damage in list(function(x) unserialize(serialize(x, NULL)),
                         function(x) { data.table::setattr(x, ".internal.selfref", NULL); x })) {
        x <- reserve_columns(data.table::data.table(id = c(2L, 1L), value = 3:4), 2)
        data.table::setkeyv(x, "id")
        data.table::setindexv(x, "value")
        x <- damage(x)
        alias <- x
        before <- serialize(x, NULL)
        expect_identical(column_capacity(x), NA_real_)
        expect_false(can_add_columns(x))
        expect_error(gen(x, extra = stop("RHS ran"), bysort = value), "Assign.*reserve_columns")
        expect_error(drop_vars(x, value), "Assign.*reserve_columns")
        expect_identical(serialize(alias, NULL), before)
        expect_identical(data.table::key(alias), "id")
        expect_identical(data.table::indices(alias), "value")
        expect_identical(alias[data.table::data.table(id = 1L), on = "id"]$value, 4L)
        x <- reserve_columns(x, 1)
        expect_true(can_add_columns(x))
        newer <- x
        gen(x, extra = 1L)
        expect_physical_table(newer, c("id", "value", "extra"))
        expect_physical_table(alias, c("id", "value"))
        expect_identical(x[data.table::data.table(value = 3L), on = "value"]$id, 2L)
    }
    empty <- reserve_columns(data.table::data.table(), 1)
    expect_true(can_add_columns(empty))
    alias <- empty
    gen(empty, x = integer())
    expect_physical_table(alias, "x")
    copied <- copy_data(data.table::data.table(x = 1:2))
    expect_true(can_add_columns(copied))
})

test_that("assigned repair preserves identical column slots without sharing another table", {
    for (make in list(data.frame, tibble::tibble, dibble)) {
        x <- make(a = dta_long(1:3))
        x[["b"]] <- x[["a"]]
        # Explicitly install the same vector in both slots, independent of
        # whether the container's ordinary replacement duplicates it.
        .Call(dtatools:::C_dtatools_set_data_column, x, 2L, x[["a"]])
        y <- reserve_columns(x, 1)
        expect_identical(rlang::obj_address(y$a), rlang::obj_address(y$b))
        alias <- y
        repl(y, a = 0L)
        expect_identical(as.integer(alias$b), rep(0L, 3))
        expect_identical(as.integer(x$a), 1:3)
        expect_identical(as.integer(x$b), 1:3)
    }
})

test_that("data.table structural commits isolate names shared by ordinary copies", {
    .datatable.aware <- TRUE
    skip_if_not_installed("data.table")
    operations <- list(function(x) gen(x, z = 1L),
                       function(x) egen(x, z = dta_mean(y)),
                       function(x) rename_vars(x, renamed = x),
                       function(x) order_vars(x, y),
                       function(x) keep_vars(x, y),
                       function(x) drop_vars(x, y))
    for (operation in operations) {
        for (direction in c("original", "copy")) {
            original <- reserve_columns(data.table::data.table(x = 1:3, y = 4:6), 2)
            data.table::setkeyv(original, "x")
            data.table::setindexv(original, "y")
            copy <- original
            attr(copy, "note") <- "copy"
            target <- if (direction == "original") original else copy
            other <- if (direction == "original") copy else original
            original_names <- names(other)
            alias <- target
            before <- serialize(other, NULL)
            if (direction == "copy") {
                expect_error(operation(target), "Assign.*reserve_columns")
                expect_identical(serialize(other, NULL), before)
                target <- reserve_columns(target, 2)
                alias <- target
            }
            expect_silent(operation(target))
            expect_identical(rlang::obj_address(alias), rlang::obj_address(target))
            expect_physical_table(target)
            expect_physical_table(other, c("x", "y"))
            expect_identical(original_names, c("x", "y"))
            expect_identical(serialize(other, NULL), before)
            expect_identical(other[data.table::data.table(x = 2L), on = "x"]$y, 5L)
            gc()
            expect_silent(data.table::set(target, j = "later", value = rep(9L, 3)))
            expect_identical(alias$later, rep(9L, 3))
            expect_physical_table(other, c("x", "y"))
            data.table::setnames(target, "later", "last")
            expect_identical(alias$last, rep(9L, 3))
        }
    }
})

test_that("rename preflight runs before a computed names selection", {
    skip_if_not_installed("data.table")
    targets <- list(unserialize(serialize(data.table::data.table(x = 1:3), NULL)),
                    legacy_column_table())
    for (target in targets) {
        before <- serialize(target, NULL)
        expect_error(rename_vars(target, .names = stop("selection ran")),
                     "Assign.*reserve_columns")
        expect_identical(serialize(target, NULL), before)
    }
    data <- data.frame(x = 1:3)
    expect_silent(rename_vars(data, .names = toupper(names(data))))
    expect_identical(names(data), "X")
})

test_that("unprepared keep-all is a validated no-op and invalid selectors keep their diagnostics", {
    for (make in list(data.frame, tibble::tibble)) {
        data <- make(a = 1L, b = 2L)
        alias <- data
        before <- serialize(data, NULL)
        expect_silent(keep_vars(data, b, a))
        expect_identical(serialize(alias, NULL), before)
        for (operation in list(keep_vars, drop_vars)) {
            expect_error(operation(data, absent), "does not exist")
            expect_error(operation(data, tidyselect::all_of(character())), "at least one")
            expect_identical(serialize(alias, NULL), before)
        }
    }
})

test_that("an unsupported loaded data.table version is rejected before mutation", {
    skip_if_not_installed("data.table", "1.18.2.1")
    skip_if_not_installed("callr")
    results <- callr::r(function() {
        library(dtatools)
        data <- data.table::data.table(x = 1:3, y = 4:6)
        alias <- data
        before <- serialize(data, NULL)
        effects <- 0L
        effect <- function(value) { effects <<- effects + 1L; value }
        # Simulate an already-loaded unsupported version without replacing
        # native code or touching an installed library. The real old release
        # cannot compile on R 4.6; this tests only the version guard.
        info <- get(".__NAMESPACE__.", envir = asNamespace("data.table"))
        previous <- info$spec
        on.exit(info$spec <- previous, add = TRUE)
        info$spec[["version"]] <- "1.17.8"
        stopifnot(as.character(getNamespaceVersion("data.table")) == "1.17.8")
        calls <- list(
            quote(gen(data, z = effect(1L))),
            quote(egen(data, z = effect(1L))),
            quote(repl(data, x = effect(1L))),
            quote(keep_vars(data, tidyselect::all_of(effect("x")))),
            quote(drop_vars(data, tidyselect::all_of(effect("x")))),
            quote(order_vars(data, tidyselect::all_of(effect("x")))),
            quote(rename_vars(data, .names = effect(c("a", "b")))),
            quote(reorder_dta_rows(data, effect(3:1))),
            quote(reserve_columns(data, n = effect(1L))),
            quote(copy_data(data)),
            quote(column_capacity(data)),
            quote(can_add_columns(data, 0L)),
            quote(set_var_format(data, x, "%9.0g")),
            quote(as_dibble(data))
        )
        messages <- vapply(calls, function(call) {
            tryCatch({ eval(call); "unexpected success" }, error = conditionMessage)
        }, character(1))
        list(messages = messages, effects = effects,
             unchanged = identical(serialize(data, NULL), before) &&
                         identical(serialize(alias, NULL), before))
    }, libpath = .libPaths())
    expect_true(all(grepl("Install or update data.table to version 1.18.2.1", results$messages,
                          fixed = TRUE)), info = paste(results$messages, collapse = "\n"))
    expect_identical(results$effects, 0L)
    expect_true(results$unchanged)
})
