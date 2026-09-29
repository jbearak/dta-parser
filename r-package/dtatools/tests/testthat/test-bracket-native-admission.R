test_that("native brackets publish unfamiliar columns and preserve ordinary fallback", {
    skip_if_not_installed("dplyr")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    expected <- c(.dtatools_public_mutation_build_expected(),
                  .dtatools_ungrouped_dplyr_build_expected())
    observed <- .dtatools_child_r("bracket-native-admission", function(expected) {
        library(dtatools)
        library(dplyr)
        options(dtatools.generate_type = "double")
        ns <- asNamespace("dtatools")
        cc <- function(name, ...) .Call(get(name, ns), ...)
        make <- function() as_dibble(tibble::tibble(
            other = rep(9.0, 41L), source_value = rep(c(2, 7, -3), length.out = 41L),
            group_key = dta_long(rep(c(91, 3, 8), length.out = 41L))))
        run <- function(grouped, enabled) {
            env <- new.env(parent = globalenv())
            env$d <- make()
            profile <- get(".probe_bracket_public_state", ns)
            saved <- profile$snapshots
            if (!enabled) profile$snapshots <- NULL
            on.exit(profile$snapshots <- saved)
            options(dtatools.probe_grouped_bracket = enabled,
                    dtatools.probe_grouped_bracket_raw = enabled)
            stat <- if (grouped) "C_dtatools_probe_grouped_bracket_stats" else
                "C_dtatools_probe_bracket_step_stats"
            cc(stat, TRUE)
            expression <- if (grouped) quote(d[, `:=`(alpha = source_value + 1,
                beta = source_value + 1, gamma = source_value + 1,
                delta = source_value + 1, epsilon = source_value + 1), by = group_key]) else
                quote(d[, `:=`(alpha = source_value + 2.5, beta = source_value + 2.5,
                gamma = source_value + 2.5, delta = source_value + 2.5,
                epsilon = source_value + 2.5)])
            value <- eval(expression, env)
            list(columns = lapply(value, function(column)
                list(values = as.double(column), attributes = attributes(column))),
                counts = cc(stat, FALSE))
        }
        publications <- integer(2L)
        for (grouped in c(FALSE, TRUE)) {
            ordinary <- run(grouped, FALSE)
            native <- run(grouped, TRUE)
            stopifnot(identical(native$columns, ordinary$columns))
            index <- if (grouped) 2L else 1L
            publications[[index]] <- native$counts[[3L]]
            stopifnot(publications[[index]] == if (expected[[index]]) 5L else 0L)
        }
        publications
    }, args = list(expected = expected), libpath = .libPaths())
    expect_identical(observed, ifelse(expected, 5L, 0L))
})

test_that("bracket fallback retains a completed RHS after a source write", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("bracket-pending-rhs", function() {
        library(dtatools)
        options(dtatools.generate_type = "double")
        run <- function(enabled, step) {
            env <- new.env(parent = globalenv())
            env$d <- as_dibble(tibble::tibble(other = rep(1.0, 41L),
                source_value = as.double(seq_len(41L))))
            source <- env$d$source_value
            profile <- dtatools:::.probe_bracket_public_state
            saved <- profile$snapshots
            if (!enabled) profile$snapshots <- NULL
            on.exit(profile$snapshots <- saved)
            hits <- 0L
            options(dtatools.probe_bracket_generation_hook = function() {
                hits <<- hits + 1L
                if (hits == step)
                    .Call(dtatools:::C_dtatools_probe_owned_write_first, source, 42.0)
            })
            on.exit(options(dtatools.probe_bracket_generation_hook = NULL), add = TRUE)
            eval(quote(d[, `:=`(alpha = source_value + 1, beta = source_value + 1,
                gamma = source_value + 1, delta = source_value + 1,
                epsilon = source_value + 1)]), env)
            list(values = lapply(env$d, as.double), hits = hits)
        }
        for (step in c(1L, 2L, 5L)) {
            native <- run(TRUE, step)
            ordinary <- run(FALSE, step)
            stopifnot(identical(native, ordinary), native$hits == 5L,
                native$values$alpha[[1L]] == 2)
        }
        TRUE
    }, libpath = .libPaths())
    expect_true(observed)
})

test_that("grouped bracket late shaping traces preserve the uncommitted prefix", {
    skip_if_not_installed("dplyr")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("grouped-bracket-pending-rhs", function() {
        library(dtatools)
        library(dplyr)
        options(dtatools.generate_type = "double")
        run <- function(enabled, step) {
            env <- new.env(parent = globalenv())
            env$d <- as_dibble(tibble::tibble(source_value = as.double(seq_len(41L)),
                group_key = dta_long(rep(c(8, 3), length.out = 41L))))
            hits <- 0L
            installed <- FALSE
            options(dtatools.probe_grouped_bracket = enabled,
                dtatools.probe_grouped_bracket_raw = enabled,
                dtatools.probe_grouped_pre_generation_hook = function(resolved = NULL) {
                    hits <<- hits + 1L
                    if (hits == step) {
                        trace("vec_data", where = asNamespace("vctrs"), print = FALSE,
                            tracer = quote(stop("late shaping callback", call. = FALSE)))
                        installed <<- TRUE
                    }
                })
            on.exit({
                options(dtatools.probe_grouped_pre_generation_hook = NULL)
                if (installed) untrace("vec_data", where = asNamespace("vctrs"))
            })
            result <- tryCatch(eval(quote(d[, `:=`(alpha = source_value + 1,
                beta = source_value + 1, gamma = source_value + 1,
                delta = source_value + 1, epsilon = source_value + 1), by = group_key]), env),
                error = identity)
            stopifnot(inherits(result, "error"))
            list(message = conditionMessage(result), names = names(env$d), hits = hits)
        }
        for (step in c(1L, 2L, 5L)) {
            native <- run(TRUE, step)
            ordinary <- run(FALSE, step)
            stopifnot(identical(native, ordinary), native$hits == step,
                length(native$names) == 2L + step - 1L,
                identical(native$message, "late shaping callback"))
        }
        TRUE
    }, libpath = .libPaths())
    expect_true(observed)
})

test_that("generated native siblings have independent mutable metadata", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("data.table")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("native-generated-metadata-isolation", function() {
        library(dtatools)
        library(dplyr)
        options(dtatools.generate_type = "double")
        checks <- 0L
        for (engine in c("bracket", "grouped_bracket", "mutate", "grouped_mutate"))
            for (attribute in c("class", "stata.storage")) {
                d <- as_dibble(tibble::tibble(source_value = as.double(seq_len(41L)),
                    group_key = dta_long(rep(c(8, 3), length.out = 41L))))
                out <- switch(engine,
                    bracket = d[, `:=`(a = source_value + 1, b = source_value + 1,
                        c = source_value + 1, e = source_value + 1, f = source_value + 1)],
                    grouped_bracket = d[, `:=`(a = source_value + 1, b = source_value + 1,
                        c = source_value + 1, e = source_value + 1, f = source_value + 1), by = group_key],
                    mutate = mutate(d, a = source_value + 1, b = source_value + 1,
                        c = source_value + 1, e = source_value + 1, f = source_value + 1),
                    grouped_mutate = mutate(d, a = source_value + 1, b = source_value + 1,
                        c = source_value + 1, e = source_value + 1, f = source_value + 1, .by = group_key))
                holder <- attr(out$a, attribute)
                data.table::setattr(holder, "test_marker", "first-output-only")
                stopifnot(identical(attr(attr(out$a, attribute), "test_marker"), "first-output-only"))
                for (name in c("source_value", "b", "c", "e", "f"))
                    stopifnot(is.null(attr(attr(out[[name]], attribute), "test_marker")))
                checks <- checks + 1L
            }
        checks
    }, libpath = .libPaths())
    expect_identical(observed, 8L)
})

test_that("pending bracket generation does not repeat reference marker callbacks", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    observed <- .dtatools_child_r("bracket-pending-marker", function() {
        library(dtatools)
        options(dtatools.generate_type = "double")
        run<-function(native,step) {
         env<-new.env(parent=globalenv());env$d<-as_dibble(tibble::tibble(source_value=as.double(1:41)))
         profile<-dtatools:::.probe_bracket_public_state;saved<-profile$snapshots
         if(!native)profile$snapshots<-NULL
         on.exit(profile$snapshots<-saved)
         events<-new.env();events$hits<-0L;stage<-0L
         options(dtatools.probe_bracket_generation_hook=function(){stage<<-stage+1L;if(stage==step)trace('obj_address',where=asNamespace('rlang'),tracer=function()events$hits<-events$hits+1L,print=FALSE)})
         on.exit({options(dtatools.probe_bracket_generation_hook=NULL);untrace('obj_address',where=asNamespace('rlang'))},add=TRUE)
         eval(quote(d[,`:=`(a=source_value+1,b=source_value+1,c=source_value+1,e=source_value+1,f=source_value+1)]),env)
         list(hits=events$hits,stage=stage,values=lapply(env$d,as.double))
        }
        for(step in c(1L,2L,5L)) {
         ordinary<-run(FALSE,step);native<-run(TRUE,step)
         stopifnot(identical(native,ordinary))
        }
        TRUE
    }, libpath = .libPaths())
    expect_true(observed)
})
