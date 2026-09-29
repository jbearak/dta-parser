.scalar_export_attempt <- local({
    attempt <- function(source) {
        x <- source
        y <- 1
        op <- "+"
        minimum <- "double"
        .Call(C_dtatools_scalar_arithmetic, c(1, 2), 1, environment(),
              .computed_storage_getter, .scalar_arith_dependencies)
    }
    environment(attempt) <- asNamespace("dtatools")
    attempt
})

.with_scalar_export <- function(package, name, value, code, active = TRUE) {
    exports <- getNamespaceInfo(package, "exports")
    previous <- get(name, exports, inherits = FALSE)
    locked <- bindingIsLocked(name, exports)
    if (locked) unlockBinding(name, exports)
    rm(list = name, envir = exports)
    on.exit({
        rm(list = name, envir = exports)
        assign(name, previous, exports)
        if (locked) lockBinding(name, exports)
    })
    if (active) makeActiveBinding(name, value, exports) else
        assign(name, value, exports)
    code()
}

test_that("scalar admission preserves executable recycling export callbacks", {
    source <- dta_double(c(1, 2))
    invisible(source + 1)
    alias <- get("vec_recycle_common", getNamespaceInfo("vctrs", "exports"))
    for (fail in c(FALSE, TRUE)) {
        calls <- 0L
        .with_scalar_export("vctrs", "vec_recycle_common", function() {
            calls <<- calls + 1L
            if (fail) stop("recycling export callback")
            alias
        }, function() {
            expect_null(.scalar_export_attempt(source))
            expect_identical(calls, 0L)
            result <- tryCatch(source + 1, error = conditionMessage)
            expect_identical(calls, 1L)
            if (fail) expect_identical(result, "recycling export callback") else
                expect_identical(as.double(result), c(2, 3))
        })
    }
    expect_identical(as.double(source), c(1, 2))
})

test_that("scalar admission follows a recycling export redirected to a function", {
    source <- dta_double(c(1, 2))
    invisible(source + 1)
    calls <- 0L
    local_mocked_bindings(vec_recycle = function(...) {
        calls <<- calls + 1L
        list(c(10, 20), c(2, 3))
    }, .package = "vctrs")
    .with_scalar_export("vctrs", "vec_recycle_common", "vec_recycle", function() {
        expect_null(.scalar_export_attempt(source))
        expect_identical(calls, 0L)
        result <- source + 1
        expect_identical(calls, 1L)
        expect_identical(as.double(result), c(12, 23))
    }, active = FALSE)
    expect_identical(as.double(source), c(1, 2))
})

test_that("scalar native admission does not inspect the unused list2 export", {
    source <- dta_double(c(1, 2))
    invisible(source + 1)
    supported <- .dtatools_execution_profile_expected() &&
        identical(as.character(getNamespaceVersion("vctrs")), "0.7.3") &&
        identical(as.character(getNamespaceVersion("rlang")), "1.3.0")
    calls <- 0L
    .with_scalar_export("rlang", "list2", function() {
        calls <<- calls + 1L
        stop("unused list2 export callback")
    }, function() {
        native <- .scalar_export_attempt(source)
        if (supported) expect_identical(as.double(native), c(2, 3)) else
            expect_null(native)
        expect_identical(as.double(source + 1), c(2, 3))
        expect_identical(calls, 0L)
    })
})
