.decoration_status <- function(route, source, output_names = NULL, explicit = FALSE,
                               local_method = NULL, local_class = "dta_numeric") {
    if (!explicit && is.null(local_method)) {
        # Count publication by the real canonical body. A synthetic .Call
        # wrapper is deliberately ineligible for production entry admission.
        values <- rep(c(1, 2), length.out = length(source))
        names(values) <- output_names
        operation <- switch(route,
            scalar = function() source + 1,
            computed = function() dtatools:::.dta_computed(values, "double"),
            construct = function() dta_double(values))
        return(.dtatools_numeric_entry_observe(operation)$counts[[route]] > 0)
    }
    attempt <- function(route, source, output_names, explicit, local_method, local_class) {
        left <- values <- c(1, 2)
        if (route == "computed") names(values) <- output_names
        value_names <- output_names
        x <- source
        y <- right <- 1
        minimum <- storage <- "double"
        temporal <- 0L
        op <- "+"
        if (!is.null(local_method)) assign(paste0("names<-.", local_class),
                                           local_method, environment())
        frame <- if (explicit) environment() else NULL
        switch(route,
            scalar = .native_admission_call(C_dtatools_scalar_arithmetic,
                left, right, frame, .computed_storage_getter, .scalar_arith_dependencies),
            computed = .native_admission_call(C_dtatools_computed_numeric,
                values, frame, .computed_storage_getter, .computed_numeric_dependencies),
            construct = .native_admission_call(C_dtatools_construct_double,
                values, frame, .strict_double_dependencies))
    }
    environment(attempt) <- asNamespace("dtatools")
    attempt(route, source, output_names, explicit, local_method, local_class)
}

.decoration_with_method <- function(class, method, code, where = NULL) {
    if (is.null(where)) where <- get(".__S3MethodsTable__.", baseenv())
    key <- paste0("names<-.", class)
    had <- exists(key, where, inherits = FALSE)
    old <- if (had) get(key, where, inherits = FALSE)
    on.exit({
        if (had) assign(key, old, where) else rm(list = key, envir = where)
    })
    assign(key, method, where)
    code()
}

.decoration_warm <- function(size = 2L) {
    source <- dta_double(rep(c(1, 2), length.out = size))
    invisible(source + 1)
    invisible(source + rep(1, length(source)))
    source
}

.decoration_observe <- function(operation, records) {
    records$calls <- list()
    result <- operation()
    list(values = as.double(result), names = names(result), calls = records$calls)
}

test_that("numeric decoration preserves registered and lexical names setter callbacks", {
    source <- .decoration_warm(2048L)
    values <- rep(c(1, 2), length.out = 2048L)
    records <- new.env(parent = emptyenv())
    replacement <- function(x, value) {
        frame <- parent.frame()
        records$calls[[length(records$calls) + 1L]] <- list(
            call = sys.call(-1L), encoded = exists("encoded", frame, inherits = FALSE))
        if (identical(.Method, "names<-.default"))
            .Primitive("attr<-")(x, "names", value) else NextMethod()
    }
    operations <- list(
        scalar = function() source + 1,
        computed = function() source + rep(1, length(source)),
        construct = function() dta_double(values))
    for (where in list(get(".__S3MethodsTable__.", baseenv()), .GlobalEnv)) {
        for (class in c("dta_numeric", "dta_double", "vctrs_vctr", "double", "default")) {
            .decoration_with_method(class, replacement, function() {
                for (route in names(operations)) {
                    observed <- .decoration_observe(operations[[route]], records)
                    previous <- .numeric_helper_state$dependencies
                    .numeric_helper_state$dependencies <- NULL
                    reference <- tryCatch(.decoration_observe(operations[[route]], records),
                        finally = { .numeric_helper_state$dependencies <- previous })
                    expect_identical(observed$values, if (route == "construct") values else values + 1)
                    expect_identical(observed, reference, info = paste(route, class))
                    expect_false(.decoration_status(route, source), info = paste(route, class))
                }
            }, where = where)
        }
    }
})

test_that("computed decoration preserves compact storage names setter callbacks", {
    records <- new.env(parent = emptyenv())
    replacement <- function(x, value) {
        records$calls[[length(records$calls) + 1L]] <- list(
            call = sys.call(-1L), encoded = exists("encoded", parent.frame(), inherits = FALSE))
        NextMethod()
    }
    for (storage in c("byte", "int", "long", "float")) {
        source <- get(paste0("dta_", storage))(c(1, 2))
        invisible(source + 1)
        .decoration_with_method(paste0("dta_", storage), replacement, function() {
            observed <- .decoration_observe(function() source + 1, records)
            expect_identical(observed$values, c(2, 3))
            expect_length(observed$calls, 1L)
            expect_true(observed$calls[[1L]]$encoded)
            previous <- .numeric_helper_state$dependencies
            .numeric_helper_state$dependencies <- NULL
            reference <- tryCatch(.decoration_observe(function() source + 1, records),
                finally = { .numeric_helper_state$dependencies <- previous })
            expect_identical(observed, reference)
        })
    }
})

test_that("names repair callbacks retain the original numeric decoration frame", {
    source <- .decoration_warm(2048L)
    values <- rep(c(1, 2), length.out = 2048L)
    records <- new.env(parent = emptyenv())
    original <- get("names_repair_missing", asNamespace("vctrs"))
    local_mocked_bindings(names_repair_missing = function(x) {
        records$calls[[length(records$calls) + 1L]] <- list(
            call = sys.call(-2L), encoded = exists("encoded", parent.frame(2L), inherits = FALSE))
        original(x)
    }, .package = "vctrs")
    for (operation in list(function() source + 1, function() source + rep(1, length(source)),
                           function() dta_double(values))) {
        observed <- .decoration_observe(operation, records)
        expect_length(observed$calls, 1L)
        expect_true(observed$calls[[1L]]$encoded)
    }
})

test_that("numeric decoration guards retain positive unnamed production admission", {
    source <- .decoration_warm(2048L)
    supported <- .dtatools_execution_profile_expected() &&
        identical(as.character(getNamespaceVersion("vctrs")), "0.7.3") &&
        identical(as.character(getNamespaceVersion("rlang")), "1.3.0")
    for (route in c("scalar", "computed", "construct"))
        expect_identical(.decoration_status(route, source), supported, info = route)
    for (route in c("computed", "construct"))
        expect_false(.decoration_status(route, source, rep(c("a", "b"), length.out = 2048L)), info = route)
    expect_identical(names(dta_double(c(a = 1, b = 2))), c("a", "b"))
    expect_identical(names(.dta_computed(c(a = 1, b = 2), "byte")), c("a", "b"))
})

test_that("names decoration guards leave explicit kernel contracts unchanged", {
    source <- .decoration_warm()
    supported <- .dtatools_execution_profile_expected()
    .decoration_with_method("vctrs_vctr", function(x, value) stop("names setter invoked"), function() {
        for (route in c("scalar", "computed", "construct")) {
            result <- .decoration_status(route, source, explicit = TRUE)
            if (supported) expect_type(result, if (route == "computed") "list" else "double") else
                expect_null(result)
        }
    })
})

test_that("names decoration guards leave active and delayed method lookup to the R fallback", {
    source <- .decoration_warm(2048L)
    table <- get(".__S3MethodsTable__.", baseenv())
    key <- "names<-.vctrs_vctr"
    original <- get(key, table, inherits = FALSE)
    on.exit({ rm(list = key, envir = table); assign(key, original, table) })
    records <- new.env(parent = emptyenv())
    replacement <- function(x, value) {
        records$encoded <- exists("encoded", parent.frame(), inherits = FALSE)
        NextMethod()
    }
    for (active in c(TRUE, FALSE)) {
        for (route in c("scalar", "computed", "construct")) {
            rm(list = key, envir = table)
            records$lookups <- 0L
            records$encoded <- FALSE
            if (active) makeActiveBinding(key, function() {
                records$lookups <- records$lookups + 1L
                replacement
            }, table) else delayedAssign(key, {
                records$lookups <- records$lookups + 1L
                replacement
            }, assign.env = table)
            expect_false(.decoration_status(route, source), info = paste(active, route))
            expect_identical(records$lookups, 1L, info = paste(active, route))
            expect_true(records$encoded, info = paste(active, route))
        }
    }
})

test_that("ordinary names wrapper compiler forms retain unnamed native admission", {
    source <- .decoration_warm(2048L)
    supported <- .dtatools_execution_profile_expected() &&
        identical(as.character(getNamespaceVersion("vctrs")), "0.7.3") &&
        identical(as.character(getNamespaceVersion("rlang")), "1.3.0")
    ns <- asNamespace("vctrs")
    setter <- get("names<-.vctrs_vctr", ns)
    repair <- get("names_repair_missing", ns)
    transform <- function(fn, level) {
        body(fn) <- body(fn)
        if (is.na(level)) fn else compiler::cmpfun(fn, options = list(optimize = level))
    }
    observe <- function(level) {
        actual_setter <- transform(setter, level)
        actual_repair <- transform(repair, level)
        local_mocked_bindings(`names<-.vctrs_vctr` = actual_setter,
                              names_repair_missing = actual_repair, .package = "vctrs")
        .decoration_with_method("vctrs_vctr", actual_setter, function() {
            for (route in c("scalar", "computed", "construct"))
                expect_identical(.decoration_status(route, source), supported,
                                 info = paste(level, route))
        })
    }
    for (level in c(NA_integer_, 0L, 2L, 3L)) observe(level)
})

test_that("numeric decoration retains executable NextMethod callbacks", {
    source <- .decoration_warm(2048L)
    values <- rep(c(1, 2), length.out = 2048L)
    seen <- logical()
    trace("NextMethod", tracer = function() {
        frames <- sys.frames()
        naming <- vapply(frames, function(frame) {
            exists(".Generic", frame, inherits = FALSE) &&
                identical(get(".Generic", frame, inherits = FALSE), "names<-")
        }, logical(1))
        if (any(naming)) seen <<- c(seen, any(vapply(frames, function(frame) {
            exists("encoded", frame, inherits = FALSE)
        }, logical(1))))
    }, where = baseenv(), print = FALSE)
    on.exit(untrace("NextMethod", where = baseenv()))
    for (route in c("scalar", "computed", "construct"))
        expect_false(.decoration_status(route, source), info = route)
    for (operation in list(function() source + 1, function() source + rep(1, length(source)),
                           function() dta_double(values))) {
        seen <- logical()
        result <- operation()
        expect_identical(seen, TRUE)
    }
})

test_that("synthetic constructor entries leave unresolved names locals untouched", {
    .decoration_warm()
    attempt <- function(events) {
        storage <- "double"
        temporal <- 0L
        values <- c(1, 2)
        delayedAssign("value_names", {
            events$calls <- events$calls + 1L
            NULL
        }, assign.env = environment())
        .native_admission_call(C_dtatools_construct_double, values, NULL,
                               .strict_double_dependencies)
    }
    environment(attempt) <- asNamespace("dtatools")
    events <- new.env(parent = emptyenv())
    events$calls <- 0L
    expect_false(attempt(events))
    expect_identical(events$calls, 0L)
})


test_that("synthetic numeric entries decline without invoking local names methods", {
    source <- .decoration_warm()
    replacement <- function(x, value) stop("local names setter invoked")
    for (class in c("dta_numeric", "dta_double", "vctrs_vctr", "double", "default")) {
        for (route in c("scalar", "computed", "construct"))
            expect_false(.decoration_status(route, source, local_method = replacement,
                                             local_class = class), info = paste(route, class))
    }
})
