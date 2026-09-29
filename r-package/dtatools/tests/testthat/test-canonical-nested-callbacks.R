test_that("metadata filtering retains nested environment tracer errors before generation", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("metadata-nested-environment-callbacks", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        fixture <- function() dibble(x = c(1, 2, 3, 4), g = c(1, 1, 2, 2))
        for (i in 1:3) {
            data <- fixture()
            gen(data, y = x + 1, by = g)
        }
        original <- get("environment", baseenv())
        inspect <- function(target) {
            data <- fixture()
            alias <- data
            calls <- 0L
            trace("environment", tracer = function() {
                stack <- sys.calls()
                reached <- any(vapply(stack, function(call) {
                    is.call(call) && identical(call[[1L]], as.name(target))
                }, logical(1)))
                if (reached) {
                    calls <<- calls + 1L
                    stop("metadata environment callback", call. = FALSE)
                }
            }, where = baseenv(), print = FALSE)
            on.exit(untrace("environment", where = baseenv()), add = TRUE)
            error <- tryCatch({ gen(data, y = x + 1, by = g); NULL },
                              error = conditionMessage)
            list(error = error, calls = calls, names = names(data),
                 alias_names = names(alias), values = as.double(data$x),
                 groups = as.double(data$g))
        }
        targets <- c(".dta_attribute_plan", ".generate_attributes")
        records <- lapply(targets, inspect)
        names(records) <- targets
        list(records = records, restored = identical(get("environment", baseenv()), original))
    }, args = list(.libPaths()), timeout = 30)
    for (target in names(observed$records)) {
        record <- observed$records[[target]]
        expect_identical(record$error, "metadata environment callback", info = target)
        expect_identical(record$calls, 1L, info = target)
        expect_identical(record$names, c("x", "g"), info = target)
        expect_identical(record$alias_names, c("x", "g"), info = target)
        expect_identical(record$values, c(1, 2, 3, 4), info = target)
        expect_identical(record$groups, c(1, 1, 2, 2), info = target)
    }
    expect_true(observed$restored)
})

test_that("grouped assembly retains snapshot attribute tracer errors before publication", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("combination-snapshot-attribute-callbacks", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        fixture <- function() dibble(x = c(1, 2, 3, 4), g = c(1, 1, 2, 2))
        for (i in 1:3) {
            data <- fixture()
            gen(data, y = x + 1, by = g)
        }
        data <- fixture()
        alias <- data
        original <- get("attributes<-", baseenv())
        calls <- 0L
        run <- function() {
            trace("attributes<-", tracer = function() {
                stack <- sys.calls()
                if (any(vapply(stack, identical, logical(1), quote(.dta_snapshot(x)))) &&
                    any(vapply(stack, identical, logical(1), quote(vctrs::list_unchop(pieces))))) {
                    calls <<- calls + 1L
                    stop("snapshot attributes callback", call. = FALSE)
                }
            }, where = baseenv(), print = FALSE)
            on.exit(untrace("attributes<-", where = baseenv()), add = TRUE)
            tryCatch({ gen(data, y = x + 1, by = g); NULL }, error = conditionMessage)
        }
        error <- run()
        list(error = error, calls = calls, names = names(data), alias_names = names(alias),
             values = as.double(data$x), groups = as.double(data$g),
             restored = identical(get("attributes<-", baseenv()), original))
    }, args = list(.libPaths()), timeout = 30)
    expect_identical(observed$error, "snapshot attributes callback")
    expect_identical(observed$calls, 1L)
    expect_identical(observed$names, c("x", "g"))
    expect_identical(observed$alias_names, c("x", "g"))
    expect_identical(observed$values, c(1, 2, 3, 4))
    expect_identical(observed$groups, c(1, 1, 2, 2))
    expect_true(observed$restored)
})
