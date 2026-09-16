expect_physical_table <- function(x, expected = names(x)) {
    expect_identical(length(unclass(x)), length(expected))
    expect_identical(ncol(x), length(expected))
    expect_identical(names(x), expected)
    expect_identical(names(.subset(x)), expected)
    expect_identical(attributes(x)$names, expected)
    for (i in seq_along(expected)) expect_identical(.subset2(x, i), x[[i]])
}

test_that("public capacity separates type, preparation, and spare slots", {
    withr::local_options(dtatools.alloccol = NULL)
    expect_equal(column_capacity(dibble(x = 1:2)), 1025)
    for (n in c(0, 1, 13)) {
        withr::local_options(dtatools.alloccol = n)
        for (x in list(dibble(x = 1:2), reserve_columns(dibble(x = 1:2)))) {
            expect_equal(column_capacity(x), n + 1)
            expect_true(can_add_columns(x, n))
            expect_false(can_add_columns(x, n + 1))
        }
    }
    x <- unserialize(serialize(dibble(x = 1:2), NULL))
    expect_identical(column_capacity(x), NA_real_)
    expect_true(can_add_columns(x, 0))
    expect_false(can_add_columns(x))
    expect_true(is_dibble(x))
    expect_false(dtatools:::.reference_state_valid(x))
    expect_false(can_add_columns(x))
    for (n in list(-1, Inf, NA_real_, NaN, .5, "5", TRUE, numeric(), c(1, 2), 2^52)) {
        expect_error(reserve_columns(dibble(x = 1), n), "whole number")
        expect_error(can_add_columns(dibble(x = 1), n), "whole number")
        withr::local_options(dtatools.alloccol = n)
        expect_error(dibble(x = 1), "whole number")
    }
    expect_error(column_capacity(list(x = 1)), "must be a dibble")
    expect_error(can_add_columns(list(x = 1)), "must be a dibble")
})

test_that("preparation preserves the dibble and isolates column values", {
    x <- dibble(x = 1:100)
    y <- reserve_columns(x, 5)
    expect_identical(class(y), class(x))
    expect_true(is_dibble(y))
    expect_false(identical(rlang::obj_address(y$x), rlang::obj_address(x$x)))
    expect_identical(as.integer(y$x), as.integer(x$x))
    expect_false(identical(rlang::obj_address(y), rlang::obj_address(x)))
    expect_gte(column_capacity(y), 6)
    expect_true(can_add_columns(y, 5))
    gen(y, z = .data$x + 1L)
    expect_physical_table(y, c("x", "z"))
    expect_physical_table(x, "x")
})

test_that("explicit helpers reject plain containers before evaluating their arguments", {
    containers <- list(data.frame(x = 1:3), tibble::tibble(x = 1:3))
    if (requireNamespace("data.table", quietly = TRUE)) {
        containers <- c(containers, list(data.table::data.table(x = 1:3)))
    }
    for (data in containers) {
        before <- serialize(data, NULL)
        expect_error(reserve_columns(data, 1), "must be a dibble")
        expect_error(column_capacity(data), "must be a dibble")
        expect_error(can_add_columns(data, 0), "must be a dibble")
        expect_error(copy_data(data), "must be a dibble")
        expect_error(gen(data, y = stop("RHS ran")), "must be a dibble")
        expect_error(repl(data, x = stop("RHS ran")), "must be a dibble")
        expect_error(rename_vars(data, .names = stop("selection ran")), "must be a dibble")
        expect_error(keep_vars(data, x), "must be a dibble")
        expect_error(drop_vars(data, x), "must be a dibble")
        expect_identical(serialize(data, NULL), before)
        expect_false(inherits(data, "dtatools_ref_data"))
    }
})

test_that("capacity exhaustion fails before writes and assigned repair isolates aliases", {
    withr::local_options(dtatools.auto_grow = FALSE)
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
    withr::local_options(dtatools.auto_grow = FALSE)
    for (prepared in c(FALSE, TRUE)) {
        make <- function() {
            x <- unserialize(serialize(dibble(x = 1:2), NULL))
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
        a <- reserve_columns(dibble(x = 1:2), 1)
        b <- data.frame(z = 3:4)
        calls <- 0L
        name <- function() { calls <<- calls + 1L; c("a", "b")[[calls]] }
        call <- substitute(gen(FUN(name()), y = 1), list(FUN = as.name(getter)))
        expect_silent(eval(call))
        expect_identical(calls, 1L)
        expect_physical_table(a, c("x", "y"))
        expect_physical_table(b, "z")
    }
    box <- list(a = reserve_columns(dibble(x = 1:2), 1), b = data.frame(z = 3:4))
    index <- "a"
    values <- function() { index <<- "b"; 1L }
    expect_silent(gen(box[[index]], y = values()))
    expect_physical_table(box$a, c("x", "y"))
    expect_physical_table(box$b, "z")
    expect_identical(index, "b")
    for (replacement in list(42L, list(data = data.frame(z = 3:4)))) {
        box <- list(data = reserve_columns(dibble(x = 1:2), 1))
        original <- box$data
        values <- function() { box <<- replacement; 1L }
        result <- gen(box$data, y = values())
        expect_identical(box, replacement)
        expect_identical(rlang::obj_address(result), rlang::obj_address(original))
        expect_physical_table(original, c("x", "y"))
    }
})

test_that("growth rejects row selection and sorting before they run", {
    withr::local_options(dtatools.auto_grow = FALSE)
    for (make in list(dibble)) {
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
    withr::local_options(dtatools.auto_grow = FALSE)
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
    for (make in list(dibble)) {
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
    for (make in list(dibble)) {
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

test_that("zero-column tables can reserve and consume their first slot", {
    withr::local_options(dtatools.auto_grow = FALSE)
    for (make in list(dibble)) {
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

.check_optional_split_reserve_columns_313 <- function(include_dplyr) {
    x <- reserve_columns(dibble(x = c(3L, 1L, 2L)), 1)
    gen(x, y = .data$x * 2L)
    reorder_dta_rows(x, c(2L, 3L, 1L))
    expect_physical_table(x, c("x", "y"))
    if (include_dplyr) {
        expect_identical(names(dplyr::bind_rows(x, x)), c("x", "y"))
        expect_identical(names(dplyr::bind_cols(x, tibble::tibble(z = 1:3))), c("x", "y", "z"))
    }
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
}

test_that("prepared physical columns remain visible to direct consumers", {
    .check_optional_split_reserve_columns_313(FALSE)
})

test_that("prepared physical column consumers through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_reserve_columns_313(TRUE)
})
test_that("assigned repair preserves identical column slots without sharing another table", {
    for (make in list(dibble)) {
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

test_that("rename of an unprepared dibble accepts a computed names selection", {
    data <- unserialize(serialize(dibble(x = 1:3), NULL))
    expect_silent(rename_vars(data, .names = toupper(names(data))))
    expect_identical(names(data), "X")
})

test_that("unprepared keep-all is a validated no-op and invalid selectors keep their diagnostics", {
    for (make in list(dibble)) {
        data <- unserialize(serialize(make(a = 1L, b = 2L), NULL))
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
    results <- .dtatools_child_r("data-table-version", function() {
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
            quote(set_var_format(data, .(effect("x")), effect("%9.0g"))),
            quote(set_var_formats(data, x, effect("%9.0g"))),
            quote(set_var_formats(data, x = effect("%9.0g"))),
            quote(set_var_label(data, .(effect("x")), effect("Label"))),
            quote(set_var_labels(data, x = effect("Label"))),
            quote(set_val_labels(data, x = effect(c(One = 1L)))),
            quote(set_dta_metadata(data, variable = effect("x"), source = effect("survey"))),
            quote(set_dta_note(data, effect(1L), "Note", variable = "x")),
            quote(add_dta_note(data, effect("Note"), variable = "x")),
            quote(drop_dta_notes(data, effect(1L), variable = "x")),
            quote(renumber_dta_notes(data, effect(2L), variable = "x")),
            quote(set_dta_characteristic(data, effect("source"), "survey", variable = "x")),
            quote(drop_dta_characteristics(data, effect("source"), variable = "x")),
            quote(as_dibble(data))
        )
        messages <- vapply(calls, function(call) {
            tryCatch({ eval(call); "unexpected success" }, error = conditionMessage)
        }, character(1))
        # Mutation helpers reject the data.table as a target before the version
        # guard; only the conversion reaches it.
        conversion <- vapply(calls, function(call) identical(call[[1L]], quote(as_dibble)), logical(1))
        list(messages = messages, conversion = conversion, effects = effects,
             unchanged = identical(serialize(data, NULL), before) &&
                         identical(serialize(alias, NULL), before))
    }, libpath = .libPaths())
    expect_true(all(grepl("Install or update data.table to version 1.18.2.1",
                          results$messages[results$conversion], fixed = TRUE)),
                info = paste(results$messages, collapse = "\n"))
    expect_true(all(grepl("must be a dibble", results$messages[!results$conversion], fixed = TRUE)),
                info = paste(results$messages, collapse = "\n"))
    expect_identical(results$effects, 0L)
    expect_true(results$unchanged)
})
