test_that("double assembly retains the C dispatch stack callbacks", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("combiner-c-stack-callback-counts", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0)
        pieces <- list(dta_double(c(1, 2)), dta_double(c(3, 4)))
        for (i in 1:3) invisible(dtatools:::.mutation_gather_values(pieces))
        inspect <- function(target) {
            original <- get(target, baseenv())
            calls <- 0L
            trace(target, tracer = function() {
                reached <- any(vapply(sys.calls(), function(call) {
                    is.call(call) && identical(call[[1L]], quote(vctrs::list_unchop))
                }, logical(1)))
                if (reached) calls <<- calls + 1L
            }, where = baseenv(), print = FALSE)
            on.exit(untrace(target, where = baseenv()), add = TRUE)
            expected <- vctrs::list_unchop(pieces)
            expected_calls <- calls
            calls <- 0L
            actual <- dtatools:::.mutation_gather_values(pieces)
            actual_calls <- calls
            untrace(target, where = baseenv())
            list(expected_calls = expected_calls, actual_calls = actual_calls,
                 expected = as.double(expected), actual = as.double(actual),
                 attributes = identical(attributes(expected), attributes(actual)),
                 restored = identical(get(target, baseenv()), original))
        }
        lapply(c("sys.frame", "-"), inspect)
    }, args = list(.libPaths()), timeout = 30)
    for (record in observed) {
        expect_gt(record$expected_calls, 0L)
        expect_identical(record$actual_calls, record$expected_calls)
        expect_identical(record$expected, c(1, 2, 3, 4))
        expect_identical(record$actual, record$expected)
        expect_true(record$attributes)
        expect_true(record$restored)
    }
})

test_that("grouped generation preserves errors in C dispatch stack callbacks", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("combiner-c-stack-callback-errors", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0)
        fixture <- function() dibble(x = c(1, 2, 3, 4), g = c(1, 1, 2, 2))
        for (i in 1:3) {
            data <- fixture()
            gen(data, y = x + 1, by = g)
        }
        inspect <- function(target) {
            data <- fixture()
            alias <- data
            original <- get(target, baseenv())
            calls <- 0L
            run <- function() {
                trace(target, tracer = function() {
                    reached <- any(vapply(sys.calls(), function(call) {
                        is.call(call) && identical(call[[1L]], quote(vctrs::list_unchop))
                    }, logical(1)))
                    if (reached) {
                        calls <<- calls + 1L
                        stop("combination stack callback", call. = FALSE)
                    }
                }, where = baseenv(), print = FALSE)
                on.exit(untrace(target, where = baseenv()), add = TRUE)
                tryCatch({ gen(data, y = x + 1, by = g); NULL }, error = conditionMessage)
            }
            error <- run()
            list(error = error, calls = calls, names = names(data),
                 alias_names = names(alias), values = as.double(data$x),
                 groups = as.double(data$g),
                 restored = identical(get(target, baseenv()), original))
        }
        lapply(c("sys.frame", "-"), inspect)
    }, args = list(.libPaths()), timeout = 30)
    for (record in observed) {
        expect_identical(record$error, "combination stack callback")
        expect_identical(record$calls, 1L)
        expect_identical(record$names, c("x", "g"))
        expect_identical(record$alias_names, c("x", "g"))
        expect_identical(record$values, c(1, 2, 3, 4))
        expect_identical(record$groups, c(1, 1, 2, 2))
        expect_true(record$restored)
    }
})

test_that("double assembly settles delayed C dispatch stack dependencies", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("combiner-c-stack-delayed-dependencies", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0)
        pieces <- list(dta_double(c(1, 2)), dta_double(c(3, 4)))
        for (i in 1:3) invisible(dtatools:::.mutation_gather_values(pieces))
        inspect <- function(target) {
            original <- get(target, baseenv(), inherits = FALSE)
            restore <- function() {
                unlockBinding(target, baseenv())
                assign(target, original, baseenv())
                lockBinding(target, baseenv())
            }
            on.exit(restore(), add = TRUE)
            holder <- new.env(parent = baseenv())
            holder$fn <- original
            unlockBinding(target, baseenv())
            delayedAssign(target, fn, eval.env = holder, assign.env = baseenv())
            lockBinding(target, baseenv())
            actual <- dtatools:::.mutation_gather_values(pieces)
            holder$fn <- function(...) stop("delayed stack dependency changed", call. = FALSE)
            settled <- identical(get(target, baseenv(), inherits = FALSE), original)
            restore()
            list(settled = settled, value = as.double(actual),
                 restored = identical(get(target, baseenv(), inherits = FALSE), original))
        }
        lapply(c("sys.frame", "-"), inspect)
    }, args = list(.libPaths()), timeout = 30)
    for (record in observed) {
        expect_true(record$settled)
        expect_identical(record$value, c(1, 2, 3, 4))
        expect_true(record$restored)
    }
})
