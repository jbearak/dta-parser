test_that("grouped native mutations preserve S4 grouping key dispatch", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    expected <- c(gen = .dtatools_public_mutation_build_expected(),
        bracket = requireNamespace("dplyr", quietly = TRUE) &&
            .dtatools_ungrouped_dplyr_build_expected())
    observed <- .dtatools_child_r("grouped-native-s4-keys", function(expected) {
        library(dtatools)
        if (requireNamespace("dplyr", quietly = TRUE)) loadNamespace("dplyr")
        options(dtatools.generate_type = "double")
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        calls <- list(gen = quote(gen(d, y = x + 1, by = g)),
            bracket = quote(d[, y := x + 1, by = g]),
            bracket_five = quote(d[, `:=`(a = x + 1, b = x + 1,
                c = x + 1, e = x + 1, f = x + 1), by = g]))
        methods::setOldClass(c("dta_numeric", "numeric"))
        hits <- 0L
        fail <- FALSE
        methods::setMethod("names", "dta_numeric", function(x) {
            hits <<- hits + 1L
            if (fail) stop("S4 grouping names method")
            NULL
        })
        run <- function(route, raw, enabled, type, s4, throwing = FALSE) {
            cc("C_dtatools_probe_grouped_gen_mode", enabled)
            options(dtatools.probe_grouped_bracket = enabled,
                dtatools.probe_grouped_bracket_raw = enabled && raw)
            stat <- if (route == "gen") "C_dtatools_probe_grouped_gen_stats" else
                "C_dtatools_probe_grouped_bracket_stats"
            fail <<- FALSE
            key <- if (type == "long") dta_long(c(1, 1, 2, 2)) else
                dta_double(c(1, 1, 2, 2))
            d <- dibble(x = c(1, 2, 3, 4), g = key)
            if (s4) d$g <- asS4(d$g)
            hits <<- 0L
            fail <<- throwing
            before <- cc(stat, FALSE)
            error <- tryCatch({ eval(calls[[route]]); NULL },
                error = conditionMessage)
            count <- hits
            fail <<- FALSE
            list(error = error, hits = count, columns = names(d),
                values = lapply(d, as.double),
                published = as.integer((cc(stat, FALSE) - before)[[3L]]))
        }
        for (route in names(calls)) for (raw in if (route == "gen") TRUE else c(FALSE, TRUE))
        for (type in c("long", "double")) {
            targets <- if (route == "bracket_five") c("a", "b", "c", "e", "f") else "y"
            for (throwing in c(FALSE, TRUE)) {
                ordinary <- run(route, raw, FALSE, type, TRUE, throwing)
                native <- run(route, raw, TRUE, type, TRUE, throwing)
                stopifnot(identical(native, ordinary), native$hits > 0L,
                    native$published == 0L)
                if (throwing) stopifnot(
                    identical(native$error, "S4 grouping names method"),
                    identical(native$columns, c("x", "g"))) else
                    for (target in targets) stopifnot(identical(native$values[[target]], c(2, 3, 4, 5)))
            }
            positive <- run(route, raw, TRUE, type, FALSE)
            wanted <- expected[[if (route == "gen") "gen" else "bracket"]] * length(targets)
            stopifnot(is.null(positive$error), positive$hits == 0L,
                positive$published == as.integer(wanted))
            for (target in targets) stopifnot(identical(positive$values[[target]], c(2, 3, 4, 5)))
        }
        TRUE
    }, args = list(expected = expected), libpath = .libPaths())
    expect_true(observed)
})

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
    expected <- .dtatools_ungrouped_dplyr_build_expected()
    observed <- .dtatools_child_r("grouped-mutate-column-capacity", function(expected) {
        library(dtatools)
        library(dplyr)
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        run <- function(capacity, enabled, five = FALSE, owned = FALSE) {
            options(dtatools.alloccol = 1024L)
            d <- if (owned) dibble(x = dta_double(c(1, 2, 3, 4)),
                g = dta_long(c(1, 1, 2, 2))) else
                as_dibble(tibble::tibble(x = c(1, 2, 3, 4), g = c(1, 1, 2, 2)))
            options(dtatools.alloccol = capacity)
            cc("C_dtatools_grouped_mode", enabled)
            before <- cc("C_dtatools_grouped_stats", FALSE)
            warnings <- character()
            value <- tryCatch(withCallingHandlers({
                result <- if (five) mutate(d, a = x + 1, b = x + 1,
                    c = x + 1, e = x + 1, f = x + 1, .by = g) else
                    mutate(d, y = x + 1, .by = g)
                list(values = lapply(result, as.double),
                    classes = lapply(result, class), capacity = column_capacity(result))
            }, warning = function(w) {
                warnings <<- c(warnings, conditionMessage(w))
                invokeRestart("muffleWarning")
            }), error = conditionMessage)
            list(value = value, warnings = warnings,
                count = as.integer((cc("C_dtatools_grouped_stats", FALSE) - before)[[2L]]))
        }
        for (capacity in list(NULL, 0L, 0, 1L, 7L, 7, 1024L, 2048L, 4096))
        for (five in c(FALSE, TRUE)) for (owned in c(FALSE, TRUE)) {
            ordinary <- run(capacity, FALSE, five, owned)
            native <- run(capacity, TRUE, five, owned)
            stopifnot(identical(native$value, ordinary$value),
                identical(native$warnings, ordinary$warnings))
            spare <- if (is.null(capacity)) 1024 else capacity
            stopifnot(native$value$capacity == 2 + (if (five) 5 else 1) + spare,
                native$count == as.integer(expected), ordinary$count == 0L)
        }
        altrep_capacity <- dta_long(7)
        attributes(altrep_capacity) <- NULL
        for (capacity in list(-1L, NA_integer_, NA_real_, NaN, Inf, 0.5,
                              TRUE, "invalid", numeric(), c(1, 2),
                              2^52 - 1, setNames(7, "spare"), asS4(7), altrep_capacity)) {
            ordinary <- run(capacity, FALSE)
            native <- run(capacity, TRUE)
            stopifnot(identical(native, ordinary), native$count == 0L)
        }
        hits <- 0L
        fail <- FALSE
        assign("is.na.alloccol_probe", function(x) {
            hits <<- hits + 1L
            warning("column capacity method warning")
            if (fail) stop("column capacity method error")
            NextMethod()
        }, envir = .GlobalEnv)
        for (throwing in c(FALSE, TRUE)) {
            fail <- throwing
            hits <- 0L
            ordinary <- run(structure(7, class = "alloccol_probe"), FALSE)
            ordinary_hits <- hits
            hits <- 0L
            native <- run(structure(7, class = "alloccol_probe"), TRUE)
            stopifnot(identical(native, ordinary), native$count == 0L,
                hits == ordinary_hits, hits > 0L,
                identical(native$warnings, "column capacity method warning"))
            if (throwing) stopifnot(identical(native$value, "column capacity method error"))
        }
        if (expected) {
            fail <- FALSE
            late_option <- function(phase, next_capacity, enabled, five) {
                options(dtatools.alloccol = 1024L)
                d <- dibble(x = c(1, 2, 3, 4), g = dta_long(c(1, 1, 2, 2)))
                options(dtatools.alloccol = 7L)
                cc("C_dtatools_grouped_mode", enabled)
                callbacks <- 0L
                hits <<- 0L
                change <- function() {
                    callbacks <<- callbacks + 1L
                    options(dtatools.alloccol = next_capacity)
                }
                if (enabled) {
                    cc("C_dtatools_probe_grouped_capacity_hook", change, phase)
                    on.exit(cc("C_dtatools_probe_grouped_capacity_hook", NULL, 0L))
                } else {
                    name <- if (phase == 3L) ".mark_fresh_reference" else ".reserve_column_capacity"
                    tracer <- substitute({
                        if (AFTER) force(data)
                        CHANGE()
                    }, list(AFTER = phase == 3L, CHANGE = change))
                    suppressMessages(trace(name, tracer = tracer,
                        where = asNamespace("dtatools"), print = FALSE))
                    on.exit(suppressMessages(untrace(name, where = asNamespace("dtatools"))))
                }
                before <- cc("C_dtatools_grouped_stats", FALSE)
                warnings <- character()
                value <- tryCatch(withCallingHandlers({
                    result <- if (five) mutate(d, a = x + 1, b = x + 1,
                        c = x + 1, e = x + 1, f = x + 1, .by = g) else
                        mutate(d, y = x + 1, .by = g)
                    list(values = lapply(result, as.double), capacity = column_capacity(result))
                }, warning = function(w) {
                    warnings <<- c(warnings, conditionMessage(w))
                    invokeRestart("muffleWarning")
                }), error = conditionMessage)
                list(value = value, warnings = warnings, callbacks = callbacks,
                    hits = hits, option = getOption("dtatools.alloccol"),
                    count = as.integer((cc("C_dtatools_grouped_stats", FALSE) - before)[[2L]]))
            }
            for (phase in 1:3) for (five in c(FALSE, TRUE))
            for (next_capacity in list(0L, 2048L, NULL, -1L,
                                       structure(7, class = "alloccol_probe"))) {
                ordinary <- late_option(phase, next_capacity, FALSE, five)
                native <- late_option(phase, next_capacity, TRUE, five)
                stopifnot(identical(native[names(native) != "count"],
                                    ordinary[names(ordinary) != "count"]),
                    native$callbacks == 1L, ordinary$count == 0L)
                admitted <- phase == 3L || is.null(next_capacity) ||
                    (is.null(attributes(next_capacity)) && next_capacity >= 0)
                stopifnot(native$count == as.integer(admitted))
                if (phase == 3L) stopifnot(native$value$capacity ==
                    2 + (if (five) 5 else 1) + 7)
            }
            options(dtatools.alloccol = 7L)
            d <- dibble(x = c(1, 2, 3, 4), g = dta_long(c(1, 1, 2, 2)))
            cc("C_dtatools_grouped_mode", TRUE)
            on.exit(cc("C_dtatools_probe_grouped_capacity_hook", NULL, 0L), add = TRUE)
            callbacks <- 0L
            local({
                cc("C_dtatools_probe_grouped_capacity_hook", function() {
                    callbacks <<- callbacks + 1L
                    gc()
                    nested <- mutate(d, y = x + 1, .by = g)
                    stopifnot(column_capacity(nested) == 10)
                }, 2L)
            })
            gc()
            before <- cc("C_dtatools_grouped_stats", FALSE)
            result <- mutate(d, y = x + 1, .by = g)
            stopifnot(callbacks == 1L, column_capacity(result) == 10,
                (cc("C_dtatools_grouped_stats", FALSE) - before)[[2L]] == 2L)
            for (phase in 1:3) {
                cc("C_dtatools_probe_grouped_capacity_hook", function()
                    stop("column capacity checkpoint error"), phase)
                error <- tryCatch({ mutate(d, y = x + 1, .by = g); NULL },
                    error = conditionMessage)
                stopifnot(identical(error, "column capacity checkpoint error"))
                before <- cc("C_dtatools_grouped_stats", FALSE)
                result <- mutate(d, y = x + 1, .by = g)
                stopifnot(column_capacity(result) == 10, identical(names(d), c("x", "g")),
                    (cc("C_dtatools_grouped_stats", FALSE) - before)[[2L]] == 1L)
            }
        }
        TRUE
    }, args = list(expected = expected), libpath = .libPaths())
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
