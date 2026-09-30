test_that("grouped native mutate honors local double arithmetic methods", {
    skip_if_not_installed("dplyr")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("native-mutate-local-double-methods", function() {
        library(dtatools)
        library(dplyr)
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        for (method in c("+.dta_double", "Ops.dta_double")) {
            for (inherited in c(FALSE, TRUE)) for (five in c(FALSE, TRUE)) {
                run <- function(enabled) {
                    cc("C_dtatools_grouped_mode", enabled)
                    d <- as_dibble(tibble::tibble(x = c(1, 2, 3, 4),
                                                g = c(1, 1, 2, 2)))
                    hits <- 0L
                    replacement <- function(e1, e2) {
                        hits <<- hits + 1L
                        rep(99, length(e1))
                    }
                    call <- if (five) quote(mutate(d, a = x + 1, b = x + 1,
                        c = x + 1, e = x + 1, f = x + 1, .by = g)) else
                        quote(mutate(d, y = x + 1, .by = g))
                    caller <- new.env(parent = environment())
                    assign(method, replacement, if (inherited) environment() else caller)
                    before <- cc("C_dtatools_grouped_stats", FALSE)
                    result <- eval(call, caller)
                    count <- as.integer((cc("C_dtatools_grouped_stats", FALSE) - before)[[2L]])
                    list(values = lapply(result, as.double), hits = hits, count = count)
                }
                ordinary <- run(FALSE)
                native <- run(TRUE)
                stopifnot(identical(native, ordinary),
                    native$hits == if (five) 10L else 2L,
                    native$count == 0L)
            }
        }
        TRUE
    }, libpath = .libPaths())
    expect_true(observed)
})

test_that("native mutate preserves reserved evaluation symbols with colliding columns", {
    skip_if_not_installed("dplyr")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("native-mutate-mask-pronouns", function() {
        library(dtatools)
        library(dplyr)
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        reserved <- c(".data", ".env", "...", "..0", "..1", "..01",
                      "..+1", "..-1", "..9999999999999999999999")
        for (name in reserved) for (grouped in c(FALSE, TRUE)) {
            key_cases <- if (grouped && name %in% c(".data", ".env", tail(reserved, 1L)))
                c(FALSE, TRUE) else FALSE
            for (five in c(FALSE, TRUE)) for (key in key_cases) {
                run <- function(enabled) {
                    cc("C_dtatools_probe_mutate_mode", enabled)
                    cc("C_dtatools_grouped_mode", enabled)
                    d <- as_dibble(setNames(tibble::tibble(x = c(11, 22, 33, 44),
                        g = c(1, 1, 2, 2)), if (key) c("x", name) else c(name, "g")))
                    source <- if (key) quote(x) else as.name(name)
                    call <- if (five) substitute(mutate(d, a = SOURCE + 1,
                        b = SOURCE + 1, c = SOURCE + 1, e = SOURCE + 1,
                        f = SOURCE + 1), list(SOURCE = source)) else
                        substitute(mutate(d, y = SOURCE + 1), list(SOURCE = source))
                    if (grouped) call$.by <- if (key) as.name(name) else quote(g)
                    stat <- if (grouped) "C_dtatools_grouped_stats" else
                        "C_dtatools_probe_dplyr_early_stats"
                    before <- cc(stat, FALSE)
                    error <- tryCatch({ eval(call); NULL }, error = conditionMessage)
                    count <- tail(as.integer(cc(stat, FALSE) - before), 1L)
                    list(error = error, count = count)
                }
                ordinary <- run(FALSE)
                native <- run(TRUE)
                stopifnot(is.character(ordinary$error),
                    identical(native, ordinary), native$count == 0L)
            }
        }
        TRUE
    }, libpath = .libPaths())
    expect_true(observed)
})

test_that("grouped native mutate honors configured column capacity", {
    skip_if_not_installed("dplyr")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("grouped-mutate-column-capacity", function() {
        library(dtatools)
        library(dplyr)
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        for (capacity in list(0L, 7L, -1L, NA_integer_, "invalid")) {
            run <- function(enabled) {
                options(dtatools.alloccol = 1024L)
                d <- as_dibble(tibble::tibble(x = c(1, 2, 3, 4),
                                            g = c(1, 1, 2, 2)))
                options(dtatools.alloccol = capacity)
                cc("C_dtatools_grouped_mode", enabled)
                before <- cc("C_dtatools_grouped_stats", FALSE)
                value <- tryCatch({
                    result <- mutate(d, y = x + 1, .by = g)
                    list(values = as.double(result$y), capacity = column_capacity(result))
                }, error = conditionMessage)
                list(value = value,
                    count = as.integer((cc("C_dtatools_grouped_stats", FALSE) - before)[[2L]]))
            }
            ordinary <- run(FALSE)
            native <- run(TRUE)
            stopifnot(identical(native, ordinary), native$count == 0L)
        }
        TRUE
    }, libpath = .libPaths())
    expect_true(observed)
})

test_that("native brackets preserve reserved source symbol evaluation", {
    skip_if_not_installed("dplyr")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("bracket-reserved-source-symbols", function() {
        library(dtatools)
        library(dplyr)
        options(dtatools.generate_type = "double")
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        profile <- dtatools:::.probe_bracket_public_state
        saved <- profile$snapshots
        for (name in c(".data", ".env", ".n", ".N", "...", "..1", "..0", "..+1")) {
            operations <- c("create", "five", "replace", if (name == "...") "scalar")
            for (grouped in c(FALSE, TRUE)) for (operation in operations) {
                run <- function(enabled) {
                    profile$snapshots <- if (enabled) saved else NULL
                    options(dtatools.probe_grouped_bracket = enabled,
                            dtatools.probe_grouped_bracket_raw = enabled)
                    d <- as_dibble(setNames(tibble::tibble(x = c(11, 22, 33, 44),
                        g = c(1, 1, 2, 2)), c(name, "g")))
                    call <- if (operation == "scalar")
                        substitute(d[, TARGET := 1], list(TARGET = as.name(name))) else
                        if (operation == "five") substitute(d[, `:=`(
                        a = SOURCE + 1, b = SOURCE + 1, c = SOURCE + 1,
                        e = SOURCE + 1, f = SOURCE + 1)], list(SOURCE = as.name(name))) else
                        substitute(d[, TARGET := SOURCE + 1], list(SOURCE = as.name(name),
                            TARGET = as.name(if (operation == "replace") name else "y")))
                    if (grouped) call$by <- quote(g)
                    stat <- if (grouped) "C_dtatools_probe_grouped_bracket_stats" else
                        "C_dtatools_probe_bracket_step_stats"
                    before <- cc(stat, FALSE)
                    error <- tryCatch({ eval(call); NULL }, error = conditionMessage)
                    list(error = error, columns = lapply(d, function(column)
                        list(values = as.double(column), attributes = attributes(column))),
                        published = as.integer((cc(stat, FALSE) - before)[[3L]]))
                }
                ordinary <- run(FALSE)
                native <- run(TRUE)
                if (!identical(native, ordinary)) stop(sprintf(
                    "%s grouped=%s operation=%s: %s", name, grouped, operation,
                    paste(all.equal(native, ordinary), collapse = "; ")))
                stopifnot(native$published == 0L)
                if (operation == "create" && name %in% c(".n", ".N")) {
                    expected <- if (name == ".n") if (grouped) c(2, 3, 2, 3) else 2:5 else
                        rep(if (grouped) 3 else 5, 4L)
                    stopifnot(identical(native$columns$y$values, as.double(expected)))
                }
            }
        }
        TRUE
    }, libpath = .libPaths())
    expect_true(observed)
})

test_that("plain and owned double keys admit grouped reference creation", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    expected <- c(.dtatools_public_mutation_build_expected(),
        requireNamespace("dplyr", quietly = TRUE) && .dtatools_ungrouped_dplyr_build_expected())
    observed <- .dtatools_child_r("grouped-double-reference", function(expected) {
        library(dtatools)
        if (requireNamespace("dplyr", quietly = TRUE)) loadNamespace("dplyr")
        options(dtatools.generate_type = "double")
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        make <- function(plain, keys = rep(c(3, 1, 2), length.out = 37L)) {
            d <- as_dibble(tibble::tibble(x = rep(c(-3, 2, 9), length.out = length(keys)), g = keys))
            for (i in seq_along(d)) {
                column <- cc("C_dtatools_capture_column", dta_double(as.double(.subset2(d, i))))
                if (plain) column <- cc("C_dtatools_owned_plain_snapshot", column)
                cc("C_dtatools_set_data_column", d, as.integer(i), column)
            }
            d
        }
        shape <- function(d) lapply(d, function(x) list(as.double(x), attributes(x)))
        operations <- list(quote(gen(d, y = x + 1, by = g)),
            quote(d[, y := x + 1, by = g]),
            quote(d[, `:=`(y1 = x + 1, y2 = x + 1, y3 = x + 1,
                          y4 = x + 1, y5 = x + 1), by = g]))
        for (plain in c(FALSE, TRUE)) for (i in seq_along(operations)) {
            run <- function(enabled, keys = rep(c(3, 1, 2), length.out = 37L)) {
                cc("C_dtatools_probe_grouped_gen_mode", enabled)
                options(dtatools.probe_grouped_bracket = enabled,
                    dtatools.probe_grouped_bracket_raw = enabled)
                d <- make(plain, keys)
                alias <- d$x
                stat <- if (i == 1L) "C_dtatools_probe_grouped_gen_stats" else "C_dtatools_probe_grouped_bracket_stats"
                before <- cc(stat, FALSE)
                eval(operations[[i]])
                count <- as.integer((cc(stat, FALSE) - before)[[3L]])
                stopifnot(identical(as.double(alias), rep(c(-3, 2, 9), length.out = length(keys))))
                list(value = shape(d), count = count)
            }
            ordinary <- run(FALSE)
            native <- run(TRUE)
            stopifnot(identical(native$value, ordinary$value))
            wanted <- if (expected[[if (i == 1L) 1L else 2L]]) if (i == 3L) 5L else 1L else 0L
            if (native$count != wanted) stop(sprintf("plain=%s operation=%d: published %d, expected %d", plain, i, native$count, wanted))
            for (keys in list(c(1, NA_real_, 2), c(1, .a, 2), c(1, 1.5, 2))) {
                ordinary <- run(FALSE, keys)
                native <- run(TRUE, keys)
                stopifnot(identical(native$value, ordinary$value), native$count == 0L)
            }
        }
        TRUE
    }, args = list(expected = expected), libpath = .libPaths())
    expect_true(observed)
})

test_that("grouped double mutate preserves complete values metadata and aliases", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("data.table")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    expected <- .dtatools_ungrouped_dplyr_build_expected()
    observed <- .dtatools_child_r("grouped-double-mutate", function(expected) {
        library(dtatools)
        library(dplyr)
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        for (plain in c(FALSE, TRUE)) for (wide in c(FALSE, TRUE)) for (five in c(FALSE, TRUE)) {
            run <- function(enabled) {
                cc("C_dtatools_grouped_mode", enabled)
                values <- list(x = rep(c(-3, 2, 9), length.out = 37L), g = rep(c(3, 1, 2), length.out = 37L))
                if (wide) for (i in 3:20) values[[paste0("v", i)]] <- rep(as.double(i), 37L)
                d <- as_dibble(tibble::as_tibble(values))
                for (i in seq_along(d)) {
                    column <- cc("C_dtatools_capture_column", dta_double(values[[i]]))
                    if (plain) column <- cc("C_dtatools_owned_plain_snapshot", column)
                    cc("C_dtatools_set_data_column", d, as.integer(i), column)
                }
                before <- cc("C_dtatools_grouped_stats", FALSE)
                result <- if (five) mutate(d, y1 = x + 1, y2 = x + 1, y3 = x + 1,
                    y4 = x + 1, y5 = x + 1, .by = g) else mutate(d, y = x + 1, .by = g)
                count <- as.integer((cc("C_dtatools_grouped_stats", FALSE) - before)[[2L]])
                snapshot <- lapply(result, function(x) list(as.double(x), attributes(x)))
                input <- lapply(d, as.double)
                set_dta_values(d, "x", 99, rows = 1L)
                stopifnot(identical(lapply(result, function(x) list(as.double(x), attributes(x))), snapshot))
                set_dta_values(result, "g", 77, rows = 2L)
                stopifnot(identical(as.double(d$g), input$g))
                if (wide) {
                    result_alias <- result
                    input_column <- d$v3
                    set_dta_values(result, "v3", 93, rows = 1L)
                    stopifnot(as.double(result_alias$v3)[[1L]] == 93,
                        identical(as.double(d$v3), rep(3, 37L)),
                        identical(as.double(input_column), rep(3, 37L)))
                    set_dta_values(d, "v4", 94, rows = 1L)
                    stopifnot(identical(as.double(result$v4), rep(4, 37L)))
                    ordinary <- result
                    ordinary$v5[1L] <- 95
                    attr(ordinary$v6, "label") <- "Local change"
                    stopifnot(identical(as.double(result$v5), rep(5, 37L)),
                        is.null(attr(result$v6, "label")))
                    copied <- copy_data(result)
                    data.table::set(result, i = 1L, j = "v7", value = 96)
                    stopifnot(identical(as.double(copied$v7), rep(7, 37L)))
                    data.table::set(copied, i = 1L, j = "v8", value = 97)
                    stopifnot(identical(as.double(result$v8), rep(8, 37L)),
                        identical(as.double(d$v8), rep(8, 37L)))
                }
                list(value = snapshot, count = count)
            }
            ordinary <- run(FALSE)
            native <- run(TRUE)
            stopifnot(identical(native$value, ordinary$value), native$count == as.integer(expected))
        }
        TRUE
    }, args = list(expected = expected), libpath = .libPaths())
    expect_true(observed)
})

test_that("double key plans preserve first appearance metadata and late writes", {
    skip_if_not_installed("data.table")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    expected <- .dtatools_public_mutation_build_expected()
    observed <- .dtatools_child_r("grouped-double-key-plan", function(expected) {
        library(dtatools)
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        make <- function(plain) {
            x <- cc("C_dtatools_capture_column", dta_double(c(3, 1, 3, 2, 1)))
            if (plain) cc("C_dtatools_owned_plain_snapshot", x) else x
        }
        for (plain in c(FALSE, TRUE)) {
            key <- make(plain)
            actual <- cc("C_dtatools_probe_grouped_bracket_selection", key, "g")
            if (!expected) { stopifnot(is.null(actual)); next }
            ordinary <- vctrs::vec_group_loc(data.frame(g = key))
            stopifnot(identical(actual$groups$rows, ordinary$loc),
                identical(as.double(actual$groups$keys$g), as.double(ordinary$key$g)),
                identical(attributes(actual$groups$keys$g), attributes(ordinary$key$g)))
            for (phase in c("snapshot", "validation")) {
                key <- make(plain)
                holder <- structure(list(g = key), class = "data.frame", row.names = .set_row_names(5L))
                hits <- 0L
                hook <- function() {
                    hits <<- hits + 1L
                    data.table::set(holder, i = 1L, j = "g", value = 9)
                }
                name <- paste0("dtatools.probe_grouped_plan_", phase, "_hook")
                options(setNames(list(hook), name))
                result <- cc("C_dtatools_probe_grouped_bracket_selection", key, "g")
                options(setNames(list(NULL), name))
                stopifnot(hits == 1L, is.null(result), as.double(key)[[1L]] == 9)
            }
        }
        TRUE
    }, args = list(expected = expected), libpath = .libPaths())
    expect_true(observed)
})

test_that("grouped double operations preserve public equality and arithmetic traces", {
    skip_if_not_installed("dplyr")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("grouped-double-public-traces", function() {
        library(dtatools)
        library(dplyr)
        options(dtatools.generate_type = "double")
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        for (plain in c(FALSE, TRUE)) for (operation in 1:3) for (name in c("vec_proxy_equal", "vec_arith", "vec_cast")) {
            run <- function(enabled) {
                cc("C_dtatools_probe_grouped_gen_mode", enabled)
                cc("C_dtatools_grouped_mode", enabled)
                options(dtatools.probe_grouped_bracket = enabled,
                    dtatools.probe_grouped_bracket_raw = enabled)
                d <- as_dibble(tibble::tibble(x = rep(c(1, 2), 4L), g = rep(c(3, 1), 4L)))
                for (i in seq_along(d)) {
                    column <- cc("C_dtatools_capture_column", dta_double(as.double(.subset2(d, i))))
                    if (plain) column <- cc("C_dtatools_owned_plain_snapshot", column)
                    cc("C_dtatools_set_data_column", d, as.integer(i), column)
                }
                hits <- new.env(parent = emptyenv()); hits$n <- 0L
                tracer <- substitute(assign("n", get("n", envir = E) + 1L, envir = E), list(E = hits))
                suppressMessages(trace(name, tracer = tracer, where = asNamespace("vctrs"), print = FALSE))
                on.exit(suppressMessages(untrace(name, where = asNamespace("vctrs"))))
                result <- switch(operation, gen(d, y = x + 1, by = g),
                    d[, y := x + 1, by = g], mutate(d, y = x + 1, .by = g))
                list(value = lapply(result, function(x) list(as.double(x), attributes(x))), hits = hits$n)
            }
            stopifnot(identical(run(TRUE), run(FALSE)))
        }
        TRUE
    }, libpath = .libPaths())
    expect_true(observed)
})

test_that("grouped double brackets retain completed values across foreign writes", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("data.table")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("grouped-double-pending-rhs", function() {
        library(dtatools)
        library(dplyr)
        options(dtatools.generate_type = "double")
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        run <- function(enabled, plain, step) {
            options(dtatools.probe_grouped_bracket = enabled,
                dtatools.probe_grouped_bracket_raw = enabled)
            d <- as_dibble(tibble::tibble(x = rep(2, 41L), g = rep(c(3, 1), length.out = 41L)))
            for (i in seq_along(d)) {
                column <- cc("C_dtatools_capture_column", dta_double(as.double(.subset2(d, i))))
                if (plain) column <- cc("C_dtatools_owned_plain_snapshot", column)
                cc("C_dtatools_set_data_column", d, as.integer(i), column)
            }
            hits <- 0L
            cc("C_dtatools_probe_grouped_output_hook", function() {
                hits <<- hits + 1L
                if (hits == step) data.table::set(d, i = 1L, j = "x", value = 42)
            })
            on.exit(cc("C_dtatools_probe_grouped_output_hook", NULL))
            d[, `:=`(one = x + 1, two = x + 1, three = x + 1,
                four = x + 1, five = x + 1), by = g]
            list(value = lapply(d, function(x) list(as.double(x), attributes(x))), hits = hits)
        }
        for (plain in c(FALSE, TRUE)) for (step in c(1L, 2L, 5L)) {
            native <- run(TRUE, plain, step)
            ordinary <- run(FALSE, plain, step)
            stopifnot(identical(native, ordinary), native$hits == 5L,
                native$value$one[[1L]][[1L]] == 3)
        }
        TRUE
    }, libpath = .libPaths())
    expect_true(observed)
})

test_that("grouped double brackets normalize values outside Stata storage range", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("data.table")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("grouped-double-storage-range", function() {
        library(dtatools)
        library(dplyr)
        options(dtatools.generate_type = "double")
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        for (plain in c(FALSE, TRUE)) for (sign in c(-1, 1)) {
            run <- function(enabled) {
                options(dtatools.probe_grouped_bracket = enabled,
                    dtatools.probe_grouped_bracket_raw = enabled)
                d <- as_dibble(tibble::tibble(x = rep(1, 4L), g = c(1, 2, 1, 2)))
                for (i in seq_along(d)) {
                    column <- cc("C_dtatools_capture_column", dta_double(as.double(.subset2(d, i))))
                    if (plain) column <- cc("C_dtatools_owned_plain_snapshot", column)
                    cc("C_dtatools_set_data_column", d, as.integer(i), column)
                }
                if (plain) data.table::set(d, i = 1L, j = "x", value = sign * 1e308) else
                    cc("C_dtatools_probe_grouped_owned_write_first", .subset2(d, 1L), sign * 1e308)
                d[, y := x + 1, by = g]
                list(values = as.double(d$y), attributes = attributes(d$y))
            }
            native <- run(TRUE)
            stopifnot(identical(native, run(FALSE)), is.na(native$values[[1L]]))
        }
        TRUE
    }, libpath = .libPaths())
    expect_true(observed)
})
