test_that("plain double generation uses the guarded native route", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    expected <- .dtatools_public_mutation_build_expected()
    observed <- .dtatools_child_r("plain-native-generation", function(expected) {
        library(dtatools)
        options(dtatools.generate_type = "double")
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        make <- function(values = rep(c(-3, 2, 9), length.out = 41L)) {
            d <- as_dibble(tibble::tibble(source_value = values, spare = rep(7, length(values))))
            for (i in seq_along(d)) cc("C_dtatools_set_data_column", d, as.integer(i),
                cc("C_dtatools_owned_plain_snapshot", .subset2(d, i)))
            stopifnot(!cc("C_dtatools_is_owned_double", .subset2(d, 1L)))
            d
        }
        run <- function(enabled, values = rep(c(-3, 2, 9), length.out = 41L)) {
            d <- make(values)
            cc("C_dtatools_probe_direct_final_mode", enabled)
            before <- cc("C_dtatools_probe_direct_final_stats", FALSE)
            gen(d, new_value = source_value + 2.5)
            after <- cc("C_dtatools_probe_direct_final_stats", FALSE)
            list(columns = lapply(d, function(column)
                list(values = as.double(column), attributes = attributes(column))),
                published = as.integer((after - before)[[3L]]))
        }
        ordinary <- run(FALSE)
        native <- run(TRUE)
        stopifnot(identical(native$columns, ordinary$columns),
            native$published == as.integer(expected))
        for (values in list(c(1, NA_real_, 3), c(1, .a, 3))) {
            ordinary <- run(FALSE, values)
            native <- run(TRUE, values)
            stopifnot(identical(native$columns, ordinary$columns), native$published == 0L)
        }
        native <- run(TRUE)
        native$published
    }, args = list(expected = expected), libpath = .libPaths())
    expect_identical(observed, as.integer(expected))
})

test_that("plain double mutate preserves frozen columns on its native route", {
    skip_if_not_installed("dplyr")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    expected <- .dtatools_ungrouped_dplyr_build_expected()
    observed <- .dtatools_child_r("plain-native-mutate", function(expected) {
        library(dtatools)
        library(dplyr)
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        make <- function() {
            d <- as_dibble(tibble::tibble(spare = rep(7, 41L),
                source_value = rep(c(-3, 2, 9), length.out = 41L)))
            for (i in seq_along(d)) cc("C_dtatools_set_data_column", d, as.integer(i),
                cc("C_dtatools_owned_plain_snapshot", .subset2(d, i)))
            d
        }
        run <- function(enabled) {
            cc("C_dtatools_probe_mutate_mode", enabled)
            d <- make()
            before <- cc("C_dtatools_probe_dplyr_early_stats", FALSE)
            value <- mutate(d, one = source_value + 2.5, two = source_value + 2.5,
                three = source_value + 2.5, four = source_value + 2.5,
                five = source_value + 2.5)
            after <- cc("C_dtatools_probe_dplyr_early_stats", FALSE)
            stopifnot(identical(names(d), c("spare", "source_value")))
            list(values = lapply(value, function(column)
                list(values = as.double(column), attributes = attributes(column))),
                published = as.integer((after - before)[[3L]]))
        }
        ordinary <- run(FALSE)
        native <- run(TRUE)
        stopifnot(identical(native$values, ordinary$values),
            native$published == as.integer(expected))
        native$published
    }, args = list(expected = expected), libpath = .libPaths())
    expect_identical(observed, as.integer(expected))
})

test_that("plain replacement and bracket operations use native admission", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    expected <- .dtatools_public_mutation_build_expected()
    observed <- .dtatools_child_r("plain-native-reference-operations", function(expected) {
        library(dtatools)
        options(dtatools.generate_type = "double")
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        make <- function() {
            d <- as_dibble(tibble::tibble(source_value = rep(c(-3, 2, 9), length.out = 41L),
                spare = rep(7, 41L)))
            for (i in seq_along(d)) cc("C_dtatools_set_data_column", d, as.integer(i),
                cc("C_dtatools_owned_plain_snapshot", .subset2(d, i)))
            d
        }
        expressions <- list(
            quote(dtatools::replace_values(d, source_value = source_value + 2.5)),
            quote(dtatools::replace_values(d, source_value = abs(-3))),
            quote(d[, source_value := source_value + 2.5]),
            quote(d[, source_value := abs(-3)]),
            quote(d[, new_value := source_value + 2.5]),
            quote(d[, `:=`(one = source_value + 2.5, two = source_value + 2.5,
                three = source_value + 2.5, four = source_value + 2.5,
                five = source_value + 2.5)]))
        for (i in seq_along(expressions)) {
            d <- make()
            source_alias <- d$source_value
            stat <- if (i <= 2L) "C_dtatools_probe_unique_repl_stats" else
                "C_dtatools_probe_bracket_step_stats"
            before <- cc(stat, FALSE)
            eval(expressions[[i]])
            after <- cc(stat, FALSE)
            stopifnot((after - before)[[if (i <= 2L) 6L else 3L]] == if (expected) if (i == 6L) 5L else 1L else 0L,
                identical(as.double(source_alias), rep(c(-3, 2, 9), length.out = 41L)))
            targets <- if (i <= 4L) "source_value" else if (i == 5L) "new_value" else
                c("one", "two", "three", "four", "five")
            values <- if (i %in% c(2L, 4L)) rep(3, 41L) else
                rep(c(-3, 2, 9), length.out = 41L) + 2.5
            for (target in targets) stopifnot(identical(as.double(d[[target]]), values),
                identical(dta_storage_type(d[[target]]), "double"))
        }
        TRUE
    }, args = list(expected = expected), libpath = .libPaths())
    expect_true(observed)
})

test_that("plain native operations retain ordinary values metadata and aliases", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("data.table")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("plain-native-semantics", function() {
        library(dtatools)
        library(dplyr)
        options(dtatools.generate_type = "double")
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        expressions <- list(quote(gen(d, y = x + 2.5)),
            quote(dtatools::replace_values(d, x = x + 2.5)),
            quote(d[, x := x + 2.5]), quote(d[, y := x + 2.5]),
            quote(mutate(d, y = x + 2.5)),
            quote(mutate(d, x = x + 2.5)),
            quote(gen(d, y = x + 1e308)),
            quote(dtatools::replace_values(d, x = x + 1e308)),
            quote(d[, y := x + 1e308]), quote(mutate(d, y = x + 1e308)))
        run <- function(enabled, expression, values, rich, mixed) {
            cc("C_dtatools_probe_direct_final_mode", enabled)
            cc("C_dtatools_probe_unique_repl_mode", as.integer(enabled))
            cc("C_dtatools_probe_mutate_mode", enabled)
            profile <- dtatools:::.probe_bracket_public_state
            saved <- profile$snapshots
            if (!enabled) profile$snapshots <- NULL
            on.exit(profile$snapshots <- saved)
            d <- as_dibble(tibble::tibble(x = values, spare = rep(7, length(values))))
            for (i in if (mixed) 1L else seq_along(d))
                cc("C_dtatools_set_data_column", d, as.integer(i),
                    cc("C_dtatools_owned_plain_snapshot", .subset2(d, i)))
            if (rich) {
                source <- d$x
                attr(source, "label") <- "Measured input"
                cc("C_dtatools_set_data_column", d, 1L, source)
            }
            alias <- d$x
            alias_before <- as.double(alias)
            alias_attrs <- attributes(alias)
            value <- tryCatch(eval(expression), error = identity)
            stopifnot(identical(as.double(alias), alias_before),
                identical(attributes(alias), alias_attrs))
            if (inherits(value, "error")) return(list(error = conditionMessage(value),
                class = class(value), columns = lapply(d, function(column)
                    list(values = as.double(column), attributes = attributes(column)))))
            result <- list(columns = lapply(value, function(column)
                list(values = as.double(column), attributes = attributes(column))),
                names = names(value), class = class(value), rows = attr(value, "row.names"))
            if (identical(expression[[1L]], as.name("mutate")) && length(values)) {
                source_before <- as.double(value$x)
                data.table::set(d, i = 1L, j = "x", value = 92.0)
                stopifnot(identical(as.double(value$x), source_before))
                input_before <- as.double(d$spare)
                data.table::set(value, i = 1L, j = "spare", value = 93.0)
                stopifnot(identical(as.double(d$spare), input_before))
            }
            result
        }
        for (values in list(rep(c(-3, 2, 9), length.out = 41L),
                            c(1, NA_real_, 3), c(.a, .z, NA_real_),
                            c(1e307, -1e307, 0), double()))
            for (rich in c(FALSE, TRUE)) for (mixed in c(FALSE, TRUE))
                for (expression in expressions) {
                    native <- run(TRUE, expression, values, rich, mixed)
                    ordinary <- run(FALSE, expression, values, rich, mixed)
                    if (!identical(native, ordinary)) stop(paste(
                        deparse1(expression), "rich", rich, "mixed", mixed,
                        "input", paste(values, collapse = ","),
                        paste(all.equal(native, ordinary), collapse = "; ")))
                }
        TRUE
    }, libpath = .libPaths())
    expect_true(observed)
})

test_that("plain native mutate freezes each source at its ordered copy", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("data.table")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    expected <- .dtatools_ungrouped_dplyr_build_expected()
    observed <- .dtatools_child_r("plain-native-fork-writes", function(expected) {
        library(dtatools)
        library(dplyr)
        if (!expected) return(TRUE)
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        for (index in c(1L, 2L, -1L)) {
            d <- as_dibble(tibble::tibble(spare = rep(7, 41L), x = rep(2, 41L)))
            for (i in seq_along(d)) cc("C_dtatools_set_data_column", d, as.integer(i),
                cc("C_dtatools_owned_plain_snapshot", .subset2(d, i)))
            hits <- 0L
            local({
                victim <- new.env(parent = emptyenv())
                reg.finalizer(victim, function(e) {
                    hits <<- hits + 1L
                    data.table::set(d, i = 1L, j = "x", value = 42.0)
                })
                stopifnot(cc("C_dtatools_probe_arm_publication_gc", victim))
            })
            cc("C_dtatools_probe_fork_gc_index", index)
            before <- cc("C_dtatools_probe_dplyr_early_stats", FALSE)
            value <- mutate(d, y = x + 2.5)
            after <- cc("C_dtatools_probe_dplyr_early_stats", FALSE)
            stopifnot(hits == 1L, (after - before)[[3L]] == 1L,
                as.double(d$x)[[1L]] == 42,
                as.double(value$x)[[1L]] == if (index == 1L) 42 else 2,
                as.double(value$y)[[1L]] == if (index == 1L) 44.5 else 4.5)
        }
        cc("C_dtatools_probe_fork_gc_index", -1L)
        TRUE
    }, args = list(expected = expected), libpath = .libPaths())
    expect_true(observed)
})

test_that("plain whole-column scalar replacement avoids general resolution", {
    d <- as_dibble(tibble::tibble(x = rep(2, 41L), spare = rep(3, 41L)))
    plain <- .Call(C_dtatools_owned_plain_snapshot, d$x)
    .Call(C_dtatools_set_data_column, d, 1L, plain)
    alias <- d$x
    old_attributes <- attributes(alias)
    result <- .Call(C_dtatools_patch_scalar, d, "x", NULL, 3.0, TRUE)
    expect_identical(result, d)
    expect_identical(as.double(d$x), rep(3, 41L))
    expect_identical(as.double(alias), rep(2, 41L))
    expect_identical(attributes(d$x), old_attributes)
})
