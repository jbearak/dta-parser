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

test_that("owned generation preserves custom source arithmetic dispatch", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    expected <- .dtatools_public_mutation_build_expected()
    observed <- .dtatools_child_r("owned-generation-custom-arithmetic", function(expected) {
        library(dtatools)
        options(dtatools.generate_type = "double")
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        assign("Ops.review_custom", function(e1, e2) rep(123, length(e1)),
               envir = globalenv())
        on.exit(rm("Ops.review_custom", envir = globalenv()), add = TRUE)
        run <- function(enabled, late = FALSE, custom = TRUE) {
            cc("C_dtatools_probe_direct_final_mode", enabled)
            d <- as_dibble(tibble::tibble(x = rep(1, 41L)))
            subclass <- function() {
                column <- .subset2(d, 1L)
                class(column) <- c("review_custom", class(column))
                cc("C_dtatools_set_data_column", d, 1L, column)
            }
            if (late && enabled) cc("C_dtatools_probe_gen_after_stage", subclass)
            else if (custom) subclass()
            on.exit(cc("C_dtatools_probe_gen_after_stage", NULL), add = TRUE)
            before <- cc("C_dtatools_probe_direct_final_stats", FALSE)
            gen(d, y = x + 1)
            after <- cc("C_dtatools_probe_direct_final_stats", FALSE)
            list(value = as.double(d$y), published = (after - before)[[3L]])
        }
        canonical <- run(TRUE, custom = FALSE)
        stopifnot(identical(canonical$value, rep(2, 41L)),
                  canonical$published == as.integer(expected))
        ordinary <- run(FALSE)
        native <- run(TRUE)
        stopifnot(identical(native, ordinary),
                  identical(native$value, rep(123, 41L)), native$published == 0L)
        if (expected) {
            late <- run(TRUE, TRUE)
            stopifnot(identical(late, ordinary))
        }
        TRUE
    }, args = list(expected = expected), libpath = .libPaths())
    expect_true(observed)
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
                set_dta_values(d, "x", 92.0, rows = 1L)
                stopifnot(identical(as.double(value$x), source_before))
                input_before <- as.double(d$spare)
                set_dta_values(value, "spare", 93.0, rows = 1L)
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
    if (.dtatools_public_mutation_build_expected()) expect_identical(result, d) else {
        expect_null(result)
        dtatools::replace_values(d, x = 3.0)
    }
    expect_identical(as.double(d$x), rep(3, 41L))
    expect_identical(as.double(alias), rep(2, 41L))
    expect_identical(attributes(d$x), old_attributes)
})

test_that("plain native admission preserves traced public arithmetic", {
    skip_if_not_installed("dplyr")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("plain-native-public-traces", function() {
        library(dtatools)
        library(dplyr)
        options(dtatools.generate_type = "double")
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        events <- new.env(parent = emptyenv())
        events$hits <- 0L
        run <- function(enabled, expression) {
            cc("C_dtatools_probe_direct_final_mode", enabled)
            cc("C_dtatools_probe_unique_repl_mode", as.integer(enabled))
            cc("C_dtatools_probe_mutate_mode", enabled)
            profile <- dtatools:::.probe_bracket_public_state
            saved <- profile$snapshots
            if (!enabled) profile$snapshots <- NULL
            on.exit(profile$snapshots <- saved)
            d <- as_dibble(tibble::tibble(x = rep(2, 41L), spare = rep(7, 41L)))
            for (i in seq_along(d)) cc("C_dtatools_set_data_column", d, as.integer(i),
                cc("C_dtatools_owned_plain_snapshot", .subset2(d, i)))
            events$hits <- 0L
            value <- eval(expression)
            hits <- events$hits
            list(hits = hits, columns = lapply(value, function(column)
                list(values = as.double(column), attributes = attributes(column))))
        }
        check_trace <- function(package, name) {
            trace(name, where = asNamespace(package), print = FALSE,
                tracer = function() events$hits <- events$hits + 1L)
            on.exit(untrace(name, where = asNamespace(package)))
            total <- 0L
            for (expression in list(quote(gen(d, y = x + 2.5)),
                quote(dtatools::replace_values(d, x = x + 2.5)),
                quote(dtatools::replace_values(d, x = abs(-3))),
                quote(dtatools::replace_values(d, x = 3)),
                quote(d[, x := x + 2.5]), quote(d[, y := x + 2.5]),
                quote(mutate(d, y = x + 2.5)))) {
                native <- run(TRUE, expression)
                ordinary <- run(FALSE, expression)
                if (!identical(native, ordinary)) stop(paste(name, deparse1(expression),
                    "native hits", native$hits, "ordinary hits", ordinary$hits,
                    paste(all.equal(native, ordinary), collapse = "; ")))
                total <- total + native$hits
            }
            stopifnot(total > 0L)
        }
        for (name in c("vec_arith", "vec_cast", "vec_math")) check_trace("vctrs", name)
        check_trace("rlang", "as_label")
        TRUE
    }, libpath = .libPaths())
    expect_true(observed)
})

test_that("plain bracket generation retains the RHS across source writes", {
    skip_if_not_installed("data.table")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("plain-native-pending-rhs", function() {
        library(dtatools)
        options(dtatools.generate_type = "double")
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        run <- function(enabled, step) {
            d <- as_dibble(tibble::tibble(x = rep(2, 41L), spare = rep(7, 41L)))
            for (i in seq_along(d)) cc("C_dtatools_set_data_column", d, as.integer(i),
                cc("C_dtatools_owned_plain_snapshot", .subset2(d, i)))
            profile <- dtatools:::.probe_bracket_public_state
            saved <- profile$snapshots
            if (!enabled) profile$snapshots <- NULL
            on.exit(profile$snapshots <- saved)
            hits <- 0L
            options(dtatools.probe_bracket_generation_hook = function() {
                hits <<- hits + 1L
                if (hits == step) data.table::set(d, i = 1L, j = "x", value = 42.0)
            })
            on.exit(options(dtatools.probe_bracket_generation_hook = NULL), add = TRUE)
            d[, `:=`(one = x + 2.5, two = x + 2.5, three = x + 2.5,
                     four = x + 2.5, five = x + 2.5)]
            list(values = lapply(d, as.double), hits = hits)
        }
        for (step in c(1L, 2L, 5L)) {
            native <- run(TRUE, step)
            ordinary <- run(FALSE, step)
            stopifnot(identical(native, ordinary), native$hits == 5L,
                native$values$one[[1L]] == 4.5)
        }
        TRUE
    }, libpath = .libPaths())
    expect_true(observed)
})

test_that("plain bracket generation honors numeric limits changed between assignments", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    expected <- .dtatools_public_mutation_build_expected()
    observed <- .dtatools_child_r("plain-native-late-double-limit", function() {
        library(dtatools)
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        original_machine <- get(".Machine", baseenv())
        original_lock <- bindingIsLocked(".Machine", baseenv())
        run <- function(enabled, step = 0L) {
            profile <- dtatools:::.probe_bracket_public_state
            saved <- profile$snapshots
            old_options <- options(dtatools.generate_type = "double",
                dtatools.probe_bracket_generation_hook = NULL)
            set_machine <- function(value) {
                if (bindingIsLocked(".Machine", baseenv()))
                    unlockBinding(".Machine", baseenv())
                assign(".Machine", value, baseenv())
                if (original_lock) lockBinding(".Machine", baseenv())
            }
            on.exit({
                set_machine(original_machine)
                options(old_options)
                profile$snapshots <- saved
            }, add = TRUE)
            d <- as_dibble(tibble::tibble(x = c(1, 2, 3, 4), spare = rep(7, 4L)))
            for (i in seq_along(d)) cc("C_dtatools_set_data_column", d, as.integer(i),
                cc("C_dtatools_owned_plain_snapshot", .subset2(d, i)))
            stopifnot(!cc("C_dtatools_is_owned_double", .subset2(d, 1L)))
            if (!enabled) profile$snapshots <- NULL
            changed_machine <- original_machine
            changed_machine$double.xmax <- 6
            hits <- 0L
            # Deliberately adversarial: the limit changes after this RHS has
            # been computed. Only later RHS values above 3 become missing.
            # An entry-only public guard misses this change and publishes
            # numbers instead. The already computed RHS must remain intact.
            options(dtatools.probe_bracket_generation_hook = function() {
                hits <<- hits + 1L
                if (hits == step) set_machine(changed_machine)
            })
            before <- cc("C_dtatools_probe_bracket_step_stats", FALSE)
            d[, `:=`(one = x + 1, two = x + 1, three = x + 1,
                     four = x + 1, five = x + 1)]
            after <- cc("C_dtatools_probe_bracket_step_stats", FALSE)
            set_machine(original_machine)
            list(result = list(values = lapply(d, as.double),
                attributes = lapply(d, attributes), hits = hits),
                published = (after - before)[[3L]])
        }
        control <- run(TRUE)
        cases <- lapply(seq_len(5L), function(step) {
            ordinary <- run(FALSE, step)
            native <- run(TRUE, step)
            list(ordinary = ordinary$result, native = native$result)
        })
        stopifnot(identical(get(".Machine", baseenv()), original_machine),
            identical(bindingIsLocked(".Machine", baseenv()), original_lock))
        list(control = control, cases = cases)
    }, libpath = .libPaths())
    # A clean control establishes that the supported build exercises the native
    # route. Changed-limit cases assert results, not how many checks it uses.
    expect_identical(observed$control$published, if (expected) 5L else 0L)
    targets <- c("one", "two", "three", "four", "five")
    for (step in seq_len(5L)) {
        case <- observed$cases[[step]]
        info <- paste("limit changed after RHS", step)
        expect_identical(case$native, case$ordinary, info = info)
        expected_values <- rep(list(c(2, 3, NA_real_, NA_real_)), 5L)
        expected_values[seq_len(step)] <- rep(list(c(2, 3, 4, 5)), step)
        names(expected_values) <- targets
        expect_identical(case$native$values,
            c(list(x = c(1, 2, 3, 4), spare = rep(7, 4L)), expected_values), info = info)
        expect_identical(case$native$hits, 5L, info = info)
    }
})

test_that("native mutate retains ordinary isolation and explicit foreign-write copies", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("data.table")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    expected <- .dtatools_ungrouped_dplyr_build_expected()
    observed <- .dtatools_child_r("plain-native-result-contract", function(expected) {
        library(dtatools)
        library(dplyr)
        if (!expected) return(TRUE)
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        fixture <- function(plain, n = 41L) {
            columns <- setNames(lapply(seq_len(100L), function(j)
                rep(as.double(j), n)), c("x", paste0("spare", 2:100)))
            d <- as_dibble(tibble::as_tibble(columns))
            if (plain) for (i in seq_along(d))
                cc("C_dtatools_set_data_column", d, as.integer(i),
                    cc("C_dtatools_owned_plain_snapshot", .subset2(d, i)))
            d
        }
        expressions <- list(quote(mutate(d, x = 3)),
            quote(mutate(d, x = abs(-3))), quote(mutate(d, x = x + 1)),
            quote(mutate(d, y = x + 1)),
            quote(mutate(d, a = x + 1, b = x + 1, c = x + 1,
                         e = x + 1, f = x + 1)))
        for (plain in c(TRUE, FALSE)) for (expression in expressions) {
            d <- fixture(plain)
            input_alias <- d
            input_column <- d$spare2
            before <- cc("C_dtatools_probe_dplyr_early_stats", FALSE)
            result <- eval(expression)
            after <- cc("C_dtatools_probe_dplyr_early_stats", FALSE)
            stopifnot((after - before)[[3L]] == 1L)
            result_alias <- result
            set_dta_values(result, "spare2", 91, rows = 1L)
            stopifnot(as.double(result_alias$spare2)[[1L]] == 91,
                identical(as.double(d$spare2), rep(2, 41L)),
                identical(as.double(input_column), rep(2, 41L)))
            set_dta_values(d, "spare3", 92, rows = 1L)
            stopifnot(as.double(input_alias$spare3)[[1L]] == 92,
                identical(as.double(result$spare3), rep(3, 41L)))
            ordinary <- result
            ordinary$spare4[1L] <- 93
            attr(ordinary$spare5, "label") <- "Changed locally"
            stopifnot(identical(as.double(result$spare4), rep(4, 41L)),
                is.null(attr(result$spare5, "label")),
                is.null(attr(d$spare5, "label")))
            set_var_label(result, spare6, "Changed explicitly")
            stopifnot(is.null(attr(d$spare6, "label")))
            copied <- copy_data(result)
            data.table::set(result, i = 1L, j = "spare7", value = 94.0)
            stopifnot(identical(as.double(copied$spare7), rep(7, 41L)))
            data.table::set(copied, i = 1L, j = "spare8", value = 95.0)
            stopifnot(identical(as.double(result$spare8), rep(8, 41L)),
                identical(as.double(d$spare8), rep(8, 41L)))
        }
        if (capabilities("profmem")) {
            d <- fixture(TRUE, 100000L)
            warm <- mutate(d, y = x + 1)
            rm(warm)
            invisible(gc())
            log <- tempfile()
            on.exit(unlink(log), add = TRUE)
            before <- cc("C_dtatools_probe_dplyr_early_stats", FALSE)
            utils::Rprofmem(log)
            result <- tryCatch(mutate(d, y = x + 1),
                               finally = utils::Rprofmem(NULL))
            after <- cc("C_dtatools_probe_dplyr_early_stats", FALSE)
            records <- readLines(log, warn = FALSE)
            sizes <- as.double(sub(" .*", "", records[grepl("^[0-9]+ ", records)]))
            stopifnot((after - before)[[3L]] == 1L,
                sum(sizes) < 16 * 1024^2,
                identical(as.double(result$y), rep(2, 100000L)),
                identical(as.double(d$x), rep(1, 100000L)))
        }
        TRUE
    }, args = list(expected = expected), libpath = .libPaths())
    expect_true(observed)
})
