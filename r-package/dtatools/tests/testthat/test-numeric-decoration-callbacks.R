test_that("numeric decoration preserves replacement helper arguments and frames", {
    source <- dta_double(c(1, 2))
    invisible(source + 1)
    state <- .numeric_helper_state
    saved <- state$dependencies
    withr::defer(state$dependencies <- saved)
    original <- .dta_storage_class
    records <- list()
    replacement <- function(storage) {
        records[[length(records) + 1L]] <<- list(
            expression = substitute(storage),
            encoded = exists("encoded", parent.frame(), inherits = FALSE))
        original(storage)
    }
    local_mocked_bindings(.dta_storage_class = replacement, .package = "dtatools")
    operations <- list(function() source + 1, function() source + c(1, 1),
                       function() dta_double(c(1, 2)))
    for (operation in operations) {
        state$dependencies <- NULL
        records <- list()
        expected <- operation()
        expected_records <- records
        state$dependencies <- saved
        records <- list()
        actual <- operation()
        expect_identical(records, expected_records)
        expect_identical(as.double(actual), as.double(expected))
        expect_identical(attributes(actual), attributes(expected))
    }
})

test_that("numeric decoration retains downstream primitive callback observations", {
    skip_if_not_installed("callr")
    observations <- .dtatools_child_r("numeric-decoration-callbacks", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        ns <- asNamespace("dtatools")
        source <- dta_double(c(1, 2))
        invisible(source + 1)
        state <- get(".numeric_helper_state", ns)
        saved <- state$dependencies
        operations <- list(scalar = function() source + 1,
                           computed = function() source + c(1, 1),
                           construct = function() dta_double(c(1, 2)))
        replace <- function(name, value) {
            unlockBinding(name, baseenv())
            assign(name, value, baseenv())
            lockBinding(name, baseenv())
        }
        results <- list()
        for (name in c("attr<-", "paste0", "names<-", "list")) {
            original <- get(name, baseenv())
            records <- list()
            replacement <- switch(name,
                "attr<-" = function(x, which, value) {
                    if (which %in% c("class", "stata.storage")) {
                        records[[length(records) + 1L]] <<- list(
                            value = substitute(value), which = which,
                            encoded = exists("encoded", parent.frame(), inherits = FALSE))
                    }
                    original(x, which, value)
                },
                paste0 = function(..., collapse = NULL, recycle0 = FALSE) {
                    frame <- parent.frame()
                    if (exists("storage", frame, inherits = FALSE) &&
                        identical(substitute(...), quote("dta_"))) {
                        records[[length(records) + 1L]] <<- substitute(storage, frame)
                    }
                    original(..., collapse = collapse, recycle0 = recycle0)
                },
                list = function(...) {
                    if (identical(sys.call(-1L), quote(paste0("dta_", storage)))) {
                        records[[length(records) + 1L]] <<-
                            exists("encoded", parent.frame(3L), inherits = FALSE)
                    }
                    original(...)
                },
                "names<-" = function(x, value) {
                    records[[length(records) + 1L]] <<- list(
                        value = substitute(value),
                        encoded = exists("encoded", parent.frame(), inherits = FALSE))
                    original(x, value)
                })
            for (route in names(operations)) {
                state$dependencies <- NULL
                records <- list()
                replace(name, replacement)
                expected <- tryCatch(operations[[route]](), error = conditionMessage)
                replace(name, original)
                expected_records <- records
                state$dependencies <- saved
                records <- list()
                replace(name, replacement)
                actual <- tryCatch(operations[[route]](), error = conditionMessage)
                replace(name, original)
                results[[paste(name, route)]] <- list(
                    actual = actual, expected = expected, records = records,
                    expected_records = expected_records)
            }
        }
        results
    }, args = list(.libPaths()))
    for (record in observations) {
        expect_identical(record$records, record$expected_records)
        expect_identical(record$actual, record$expected)
        expect_gt(length(record$expected_records), 0L)
    }
})
