test_that("arithmetic respects a minimum promise replaced by a payload callback", {
    value <- dta_double(c(1, 2))
    invisible(value + 1)
    events <- character()
    original <- .dta_data
    replacement <- function(x) {
        frame <- parent.frame()
        if (exists("minimum", frame, inherits = FALSE)) {
            delayedAssign("minimum", {
                events <<- c(events, "minimum")
                "byte"
            }, eval.env = environment(), assign.env = frame)
        }
        original(x)
    }
    local_mocked_bindings(.dta_data = replacement, .package = "dtatools")
    result <- value + 1
    expect_identical(events, "minimum")
    expect_identical(dta_storage_type(result), "byte")
    expect_identical(as.double(result), c(2, 3))
})

test_that("computed minimum expressions retain callback order and errors", {
    source <- dta_double(c(1, 2))
    events <- character()
    result <- .dta_arith_base("+", source, 1, {
        events <- c(events, "minimum")
        "byte"
    })
    expect_identical(events, "minimum")
    expect_identical(dta_storage_type(result), "byte")
    expect_identical(as.double(result), c(2, 3))
    events <- character()
    result <- .dta_computed(c(1, 2), {
        events <- c(events, "minimum")
        "byte"
    }, { events <- c(events, "temporal"); 0L })
    expect_identical(events, c("temporal", "minimum"))
    expect_identical(dta_storage_type(result), "byte")
    expect_error(.dta_computed(c(1, 2), stop("minimum callback")), "minimum callback")
    expect_error(.dta_arith_base("+", source, 1, stop("minimum callback")), "minimum callback")
})

test_that("compact arithmetic helpers honor a wider minimum storage", {
    invisible(dta_double(rep(1, 4096L)) + 1)
    constructors <- list(byte = dta_byte, int = dta_int,
                         long = dta_long, float = dta_float)
    values <- rep(c(1, 2), length.out = 4096L)
    for (kind in names(constructors)) {
        for (op in c("+", "-")) {
            operation <- get(op, baseenv())
            source <- constructors[[kind]](values)
            right <- .dta_arith_base(op, source, 1, "double")
            source <- constructors[[kind]](values)
            left <- .dta_arith_base(op, 1, source, "double")
            expect_identical(dta_storage_type(right), "double", info = kind)
            expect_identical(dta_storage_type(left), "double", info = kind)
            expect_identical(as.double(right), operation(values, 1), info = kind)
            expect_identical(as.double(left), operation(1, values), info = kind)
        }
        source <- constructors[[kind]](values)
        calls <- 0L
        result <- .dta_arith_base("+", source, 1, {
            calls <- calls + 1L
            "double"
        })
        expect_identical(calls, 1L, info = kind)
        expect_identical(dta_storage_type(result), "double", info = kind)
    }
})

test_that("native minimum admission follows the actual source through promises", {
    source <- dta_byte(c(1, 2))
    hint <- dta_double(c(1, 2))
    attempt <- function(minimum, minimum_source = NULL, temporal = 0L) {
        .Call(C_dtatools_computed_numeric, c(1, 2), environment(),
              .computed_storage_getter, .computed_numeric_dependencies)
    }
    environment(attempt) <- asNamespace("dtatools")
    bridge <- function(minimum) attempt(minimum, minimum_source = hint)
    invisible(source + 1)
    invisible(.dta_computed(c(1, 2), "double"))
    policy <- list2env(list(source = source, bridge = bridge),
                       parent = asNamespace("dtatools"))
    admitted <- evalq(bridge(.declared_dta_storage(source)), policy)
    if (.dtatools_execution_profile_expected()) {
        expect_type(admitted, "list")
        expect_identical(admitted[[2L]], "byte")
    } else expect_null(admitted)
    result <- .dta_computed(c(1, 2), .declared_dta_storage(source))
    expect_identical(dta_storage_type(result), "byte")
    events <- character()
    declined <- attempt({ events <- c(events, "minimum"); "byte" })
    expect_null(declined)
    expect_identical(events, character())
})

test_that("minimum admission respects the promise getter environment", {
    source <- dta_double(c(1, 2))
    events <- character()
    attempt <- function(minimum, minimum_source = NULL, temporal = 0L) {
        .Call(C_dtatools_computed_numeric, c(1, 2), environment(),
              .computed_storage_getter, .computed_numeric_dependencies)
    }
    environment(attempt) <- asNamespace("dtatools")
    foreign <- list2env(list(source = source, attempt = attempt),
                        parent = asNamespace("dtatools"))
    foreign$.declared_dta_storage <- function(x) {
        events <<- c(events, "getter")
        "byte"
    }
    invisible(source + 1)
    invisible(.dta_computed(c(1, 2), "double"))
    expect_null(evalq(attempt(.declared_dta_storage(source),
                              minimum_source = source), foreign))
    expect_identical(events, character())
    result <- evalq(.dta_computed(c(1, 2), .declared_dta_storage(source)), foreign)
    expect_identical(events, "getter")
    expect_identical(dta_storage_type(result), "byte")
})

test_that("native minimum admission leaves active policy and source bindings unread", {
    source <- dta_double(c(1, 2))
    events <- character()
    frame <- list2env(list(temporal = 0L, minimum_source = source),
                      parent = asNamespace("dtatools"))
    makeActiveBinding("minimum", function() {
        events <<- c(events, "minimum")
        "byte"
    }, frame)
    attempt_active <- function(frame) {
        .Call(C_dtatools_computed_numeric, c(1, 2), frame,
              .computed_storage_getter, .computed_numeric_dependencies)
    }
    environment(attempt_active) <- asNamespace("dtatools")
    invisible(source + 1)
    invisible(.dta_computed(c(1, 2), "double"))
    expect_null(attempt_active(frame))
    expect_identical(events, character())
    foreign <- list2env(list(source = source), parent = asNamespace("dtatools"))
    makeActiveBinding("actual", function() {
        events <<- c(events, "source")
        source
    }, foreign)
    attempt <- function(minimum, minimum_source = NULL, temporal = 0L) {
        .Call(C_dtatools_computed_numeric, c(1, 2), environment(),
              .computed_storage_getter, .computed_numeric_dependencies)
    }
    environment(attempt) <- asNamespace("dtatools")
    foreign$attempt <- attempt
    expect_null(evalq(attempt(.declared_dta_storage(actual),
                              minimum_source = source), foreign))
    expect_identical(events, character())
})


test_that("minimum getter bindings stay lazy until the original evaluation", {
    source <- dta_double(c(1, 2))
    attempt <- function(minimum, minimum_source = NULL, temporal = 0L) {
        .Call(C_dtatools_computed_numeric, c(1, 2), environment(),
              .computed_storage_getter, .computed_numeric_dependencies)
    }
    environment(attempt) <- asNamespace("dtatools")
    invisible(source + 1)
    invisible(.dta_computed(c(1, 2), "double"))
    for (active in c(FALSE, TRUE)) {
        events <- character()
        getter <- function() {
            events <<- c(events, "getter binding")
            function(x) "byte"
        }
        foreign <- list2env(list(source = source, attempt = attempt),
                            parent = asNamespace("dtatools"))
        if (active) makeActiveBinding(".declared_dta_storage", getter, foreign) else
            delayedAssign(".declared_dta_storage", getter(),
                          eval.env = environment(), assign.env = foreign)
        expect_null(evalq(attempt(.declared_dta_storage(source),
                                  minimum_source = source), foreign))
        expect_identical(events, character())
        result <- evalq(.dta_computed(c(1, 2), .declared_dta_storage(source)), foreign)
        expect_identical(events, "getter binding")
        expect_identical(dta_storage_type(result), "byte")
    }
})

test_that("arithmetic settles captured operator and minimum promises without changing expressions", {
    source <- dta_double(c(1, 2))
    invisible(source + 1)
    invisible(source + c(1, 1))
    original <- .dta_data
    observe <- function(scalar) {
        captured <- caller <- NULL
        local_mocked_bindings(.dta_data = function(value) {
            captured <<- parent.frame()
            caller <<- parent.frame(2L)
            original(value)
        }, .package = "dtatools")
        result <- if (scalar) source + 1 else source + c(1, 1)
        before <- list(substitute(op, captured), substitute(minimum, captured))
        assign("op", "-", caller)
        local_mocked_bindings(.declared_dta_storage = function(...) {
            stop("late storage getter callback")
        }, .package = "dtatools")
        minimum <- tryCatch(eval(quote(minimum), captured), error = conditionMessage)
        op <- eval(quote(op), captured)
        after <- list(substitute(op, captured), substitute(minimum, captured))
        list(result = result, op = op, minimum = minimum, before = before, after = after)
    }
    expected_expressions <- alist(op, .declared_dta_storage(x))
    for (scalar in c(TRUE, FALSE)) {
        record <- observe(scalar)
        expect_identical(as.double(record$result), c(2, 3))
        expect_identical(dta_storage_type(record$result), "double")
        expect_identical(record$op, "+")
        expect_identical(record$minimum, "double")
        expect_identical(record$before, expected_expressions)
        expect_identical(record$after, expected_expressions)
    }
})

test_that("computed results settle captured temporal and minimum promise chains", {
    invisible(dta_double(c(1, 2)) + 1)
    invisible(.dta_computed(c(1, 2), "double"))
    captured <- NULL
    method <- function(x, ...) {
        captured <<- parent.frame()
        unclass(x)
    }
    key <- "as.double.dtatools_computed_promise_capture"
    table <- get(".__S3MethodsTable__.", baseenv())
    existed <- exists(key, table, inherits = FALSE)
    previous <- if (existed) get(key, table, inherits = FALSE)
    withr::defer({
        if (existed) assign(key, previous, table) else rm(list = key, envir = table)
    })
    registerS3method("as.double", "dtatools_computed_promise_capture", method,
                     envir = baseenv())
    policy <- list2env(list(
        input = structure(c(1, 2), class = "dtatools_computed_promise_capture"),
        minimum = "double", temporal = 0L
    ), parent = environment())
    result <- evalq(.dta_computed(input, minimum, temporal), policy)
    expected_expressions <- alist(temporal, minimum)
    before <- list(substitute(temporal, captured), substitute(minimum, captured))
    policy$minimum <- "byte"
    policy$temporal <- 1L
    expect_identical(as.double(result), c(1, 2))
    expect_identical(dta_storage_type(result), "double")
    # The custom conversion exposed this frame before its original checks.
    # Entry admission must decline and preserve those checks and their locals.
    expect_false(exists("native", captured, inherits = FALSE))
    expect_true(exists("encoded", captured, inherits = FALSE))
    expect_identical(eval(quote(temporal), captured), 0L)
    expect_identical(eval(quote(minimum), captured), "double")
    expect_identical(before, expected_expressions)
    expect_identical(list(substitute(temporal, captured), substitute(minimum, captured)),
                     expected_expressions)
})

test_that("public numeric operations retain the original computed helper call signature", {
    source <- dta_double(c(1, 4))
    invisible(source + 1)
    original <- .dta_computed
    calls <- 0L
    replacement <- function(result, minimum, temporal = .dta_temporal_none) {
        calls <<- calls + 1L
        original(result, minimum, temporal)
    }
    local_mocked_bindings(.dta_computed = replacement, .package = "dtatools")
    operations <- list(
        scalar = function() source + 1,
        vector = function() source + c(1, 2),
        unary = function() -source,
        math = function() sqrt(source),
        mean = function() mean(source),
        median = function() stats::median(source),
        quantile = function() stats::quantile(source, c(0, 1), names = FALSE),
        complex = function() Re(source)
    )
    expected <- list(c(2, 5), c(2, 6), c(-1, -4), c(1, 2),
                     2.5, 2.5, c(1, 4), c(1, 4))
    for (i in seq_along(operations)) {
        calls <- 0L
        record <- tryCatch(list(value = operations[[i]](), error = NULL),
                           error = function(condition) list(error = conditionMessage(condition)))
        expect_null(record$error, info = names(operations)[[i]])
        expect_identical(calls, 1L, info = names(operations)[[i]])
        if (is.null(record$error)) {
            expect_identical(as.double(record$value), expected[[i]], info = names(operations)[[i]])
            expect_identical(dta_storage_type(record$value), "double", info = names(operations)[[i]])
        }
    }
})

test_that("public arithmetic retains the original arithmetic helper call signature", {
    source <- dta_double(c(1, 4))
    invisible(source + 1)
    original <- .dta_arith_base
    calls <- 0L
    replacement <- function(op, x, y, minimum) {
        calls <<- calls + 1L
        original(op, x, y, minimum)
    }
    local_mocked_bindings(.dta_arith_base = replacement, .package = "dtatools")
    operations <- list(
        scalar_right = function() source + 1,
        scalar_left = function() 1 + source,
        vector_right = function() source + c(1, 2),
        typed = function() source + source
    )
    expected <- list(c(2, 5), c(2, 5), c(2, 6), c(2, 8))
    for (i in seq_along(operations)) {
        calls <- 0L
        record <- tryCatch(list(value = operations[[i]](), error = NULL),
                           error = function(condition) list(error = conditionMessage(condition)))
        expect_null(record$error, info = names(operations)[[i]])
        expect_identical(calls, 1L, info = names(operations)[[i]])
        if (is.null(record$error)) {
            expect_identical(as.double(record$value), expected[[i]], info = names(operations)[[i]])
            expect_identical(dta_storage_type(record$value), "double", info = names(operations)[[i]])
        }
    }
})
