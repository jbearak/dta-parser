test_that("native replacement admits an unfamiliar column and preserves public fallback", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    native_expected <- .dtatools_public_mutation_build_expected()
    observed <- .dtatools_child_r("repl-native-clean-session", function(native_expected) {
        library(dtatools)
        probe <- function(name, ...) {
            .Primitive(".Call")(get(name, asNamespace("dtatools")), ...)
        }
        make <- function() {
            values <- setNames(lapply(seq_len(9L), function(i)
                rep(as.double(i), 41L)), paste0("field_", seq_len(9L)))
            values[[6L]] <- rep(c(-3, 1, 7), length.out = 41L)
            data <- as_dibble(tibble::as_tibble(values))
            probe("C_dtatools_patch_slot", data, 6L, NULL,
                  values[[6L]], TRUE)
            data
        }
        run <- function(enabled, events = NULL) {
            probe("C_dtatools_probe_unique_repl_mode", as.integer(enabled))
            probe("C_dtatools_probe_unique_repl_stats", TRUE)
            data <- make()
            if (!is.null(events)) events$hits <- 0L
            repl(data, field_6 = field_6 + 1.75)
            list(data = data,
                 counts = as.integer(probe("C_dtatools_probe_unique_repl_stats", FALSE)),
                 hits = if (is.null(events)) NULL else events$hits)
        }
        same <- function(actual, expected) {
            stopifnot(identical(names(actual), names(expected)),
                      identical(class(actual), class(expected)),
                      identical(attr(actual, "row.names"),
                                attr(expected, "row.names")))
            for (name in names(actual))
                stopifnot(identical(as.double(actual[[name]]),
                                    as.double(expected[[name]])),
                          identical(attributes(actual[[name]]),
                                    attributes(expected[[name]])))
        }

        ordinary <- run(FALSE)
        native <- run(TRUE)
        same(native$data, ordinary$data)
        stopifnot(identical(native$counts[[1L]], as.integer(native_expected)),
                  identical(native$counts[[6L]], as.integer(native_expected)),
                  identical(as.double(native$data$field_6[1:3]),
                            c(-1.25, 2.75, 8.75)),
                  identical(as.double(native$data$field_5[[1L]]), 5))
        if (!native_expected)
            stopifnot(identical(native$counts, integer(6L)))

        events <- new.env(parent = emptyenv())
        events$hits <- 0L
        trace("vec_arith", where = asNamespace("vctrs"),
              tracer = function() events$hits <- events$hits + 1L,
              print = FALSE)
        traced_ordinary <- run(FALSE, events)
        traced_native <- run(TRUE, events)
        untrace("vec_arith", where = asNamespace("vctrs"))
        same(traced_native$data, traced_ordinary$data)
        stopifnot(traced_native$hits > 0L,
                  identical(traced_native$hits, traced_ordinary$hits),
                  identical(traced_native$counts[[6L]], 0L))
        probe("C_dtatools_probe_unique_repl_mode", 1L)
        list(native = native$counts, traced = traced_native$counts,
             callbacks = traced_native$hits)
    }, args = list(native_expected = native_expected), libpath = .libPaths())
    expect_identical(observed$native[[1L]], as.integer(native_expected))
    expect_identical(observed$native[[6L]], as.integer(native_expected))
    expect_identical(observed$traced[[6L]], 0L)
    expect_gt(observed$callbacks, 0L)
})

test_that("native constant replacement stages a buffer for shared owned targets", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    native_expected <- .dtatools_public_mutation_build_expected()
    observed <- .dtatools_child_r("repl-native-shared-constant", function(native_expected) {
        library(dtatools)
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        d <- as_dibble(tibble::tibble(x = rep(2, 41L), spare = rep(7, 41L)))
        table_alias <- d
        column_alias <- d$x
        attrs <- attributes(column_alias)
        before <- cc("C_dtatools_probe_unique_repl_stats", FALSE)
        replace_values(d, x = abs(-3))
        counts <- cc("C_dtatools_probe_unique_repl_stats", FALSE) - before
        stopifnot(counts[[6L]] == as.integer(native_expected),
            identical(as.double(d$x), rep(3, 41L)),
            identical(as.double(table_alias$x), rep(3, 41L)),
            identical(as.double(column_alias), rep(2, 41L)),
            identical(attributes(d$x), attrs),
            identical(attributes(column_alias), attrs),
            identical(as.double(d$spare), rep(7, 41L)))
        TRUE
    }, args = list(native_expected = native_expected), libpath = .libPaths())
    expect_true(observed)
})

test_that("native replacement preserves R dots evaluation errors", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("repl-native-dots-sources", function() {
        library(dtatools)
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        for (name in c("...", "..1")) {
            run <- function(enabled) {
                cc("C_dtatools_probe_unique_repl_mode", as.integer(enabled))
                data <- as_dibble(setNames(tibble::tibble(x = rep(1, 41L)), name))
                expression <- as.call(c(list(quote(repl), quote(data)),
                    setNames(list(call("+", as.name(name), 1)), name)))
                error <- tryCatch({ eval(expression); NULL }, error = conditionMessage)
                list(error = error, values = as.double(.subset2(data, 1L)))
            }
            ordinary <- run(FALSE)
            native <- run(TRUE)
            stopifnot(is.character(ordinary$error), identical(native, ordinary),
                identical(native$values, rep(1, 41L)))
        }
        TRUE
    }, libpath = .libPaths())
    expect_true(observed)
})

test_that("native generation honors public methods on canonical double sources", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    expected <- .dtatools_public_mutation_build_expected()
    observed <- .dtatools_child_r("gen-native-source-methods", function(expected) {
        library(dtatools)
        options(dtatools.generate_type = "double")
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        methods <- c(outer(c("dim", "names"),
            c("dta_numeric", "dta_double", "vctrs_vctr", "double", "default"),
            paste, sep = "."), paste0("names<-.",
            c("dta_numeric", "dta_double", "double", "default")),
            "vec_proxy.dta_numeric", "vec_arith.dta_numeric.double")
        run <- function(native, method, late = FALSE,
                        registered = FALSE, grouped = FALSE) {
            cc("C_dtatools_probe_direct_final_mode", native)
            cc("C_dtatools_probe_grouped_gen_mode", native)
            env <- new.env(parent = globalenv())
            env$d <- as_dibble(tibble::tibble(x = dta_double(rep(1, 41L)),
                g = dta_long(rep(c(1, 2), length.out = 41L))))
            where <- if (registered) get(".__S3MethodsTable__.", baseenv()) else
                globalenv()
            previous <- get0(method, where, inherits = FALSE)
            install <- function() {
                callback <- function(...) stop("source method callback", call. = FALSE)
                if (registered) registerS3method(sub("\\..*$", "", method),
                    sub("^[^.]*\\.", "", method), callback, envir = baseenv())
                else assign(method, callback, envir = where)
            }
            if (late) cc("C_dtatools_probe_gen_after_stage", install)
            else install()
            on.exit({
                cc("C_dtatools_probe_gen_after_stage", NULL)
                if (!is.null(previous)) assign(method, previous, envir = where)
                else if (exists(method, where, inherits = FALSE))
                    rm(list = method, envir = where)
            })
            stat <- if (grouped) "C_dtatools_probe_grouped_gen_stats" else
                "C_dtatools_probe_direct_final_stats"
            before <- cc(stat, FALSE)
            expression <- if (grouped) quote(gen(d, y = x + 1, by = g)) else
                quote(gen(d, y = x + 1))
            error <- tryCatch({ eval(expression, env); NULL }, error = conditionMessage)
            if (!is.null(previous)) assign(method, previous, envir = where)
            else if (exists(method, where, inherits = FALSE))
                rm(list = method, envir = where)
            after <- cc(stat, FALSE)
            list(error = error, names = names(env$d),
                published = (after - before)[[3L]])
        }
        for (method in methods) {
            ordinary <- run(FALSE, method)
            native <- run(TRUE, method)
            stopifnot(identical(ordinary$error, "source method callback"),
                identical(native, ordinary), native$published == 0L)
            if (expected) stopifnot(identical(run(TRUE, method, TRUE), ordinary))
        }
        for (method in c("dim.dta_numeric", "names.dta_numeric"))
            for (registered in c(FALSE, TRUE)) for (grouped in c(FALSE, TRUE)) {
                ordinary <- run(FALSE, method, registered = registered, grouped = grouped)
                native <- run(TRUE, method, registered = registered, grouped = grouped)
                stopifnot(identical(ordinary$error, "source method callback"),
                    identical(native, ordinary), native$published == 0L)
            }
        for (name in c("...", "..1")) for (grouped in c(FALSE, TRUE)) {
            run_dots <- function(native) {
                cc("C_dtatools_probe_direct_final_mode", native)
                cc("C_dtatools_probe_grouped_gen_mode", native)
                env <- new.env(parent = globalenv())
                env$d <- as_dibble(setNames(tibble::tibble(
                    x = dta_double(rep(1, 41L)),
                    g = dta_long(rep(c(1, 2), length.out = 41L))), c(name, "g")))
                expression <- substitute(gen(d, y = SOURCE + 1),
                    list(SOURCE = as.name(name)))
                if (grouped) expression$by <- quote(g)
                error <- tryCatch({ eval(expression, env); NULL }, error = conditionMessage)
                list(error = error, names = names(env$d))
            }
            ordinary <- run_dots(FALSE)
            stopifnot(is.character(ordinary$error), identical(run_dots(TRUE), ordinary))
        }
        TRUE
    }, args = list(expected = expected), libpath = .libPaths())
    expect_true(observed)
})
