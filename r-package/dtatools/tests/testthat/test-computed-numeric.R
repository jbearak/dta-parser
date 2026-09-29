.scalar_native_profile_expected <- function() {
    .dtatools_execution_profile_expected() &&
        identical(as.character(getNamespaceVersion("vctrs")), "0.7.3") &&
        identical(as.character(getNamespaceVersion("rlang")), "1.3.0")
}

test_that("scalar debugger stops follow native admission or public fallback", {
    skip_if_not_installed("callr")
    records <- .dtatools_child_r("scalar-arithmetic-debugonce", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        x <- dta_double(rep(c(1, 2), length.out = 2048L))
        invisible(x + 1)
        functions <- list(vctrs::vec_recycle_common, base::getExportedValue,
                          base::suppressWarnings)
        later <- list(quote(vctrs::vec_recycle_common(1, 1)),
                      quote(getExportedValue("base", "+")),
                      quote(suppressWarnings(1)))
        lapply(seq_along(functions), function(i) {
            lines <- capture.output({
                debugonce(functions[[i]])
                cat("BEFORE_ARITHMETIC\n")
                value <- tryCatch(x + 1, error = identity)
                cat("AFTER_ARITHMETIC\n")
                invisible(tryCatch(eval(later[[i]]), error = identity))
                cat("AFTER_EXPLICIT_CALL\n")
            })
            # The noninteractive debugger consumes debugonce before erroring.
            # A subsequent ordinary public call must still work in either mode.
            public <- x + 1
            list(lines = lines, public = as.double(public),
                 values = if (inherits(value, "error")) NULL else as.double(value),
                 error = if (inherits(value, "error")) conditionMessage(value))
        })
    }, args = list(.libPaths()), timeout = 20)
    for (record in records) {
        entry <- grep("^debugging in:", record$lines)
        before <- match("BEFORE_ARITHMETIC", record$lines)
        expect_length(entry, 1L)
        explicit <- match("AFTER_EXPLICIT_CALL", record$lines)
        # Internal debugonce stops may occur in either the arithmetic call or
        # the next explicit helper call. Both consume the one-shot debugger.
        expect_true(all(entry > before & entry < explicit))
        if (is.null(record$error)) {
            expect_identical(record$values, rep(c(2, 3), length.out = 2048L))
        } else {
            expect_match(record$error, "non-interactive browser", fixed = TRUE)
            expect_null(record$values)
        }
        expect_identical(record$public, rep(c(2, 3), length.out = 2048L))
    }
})

test_that("scalar kernel uses actual settled operands and isolates its result", {
    invisible(dta_double(c(1, 2)) + 1)
    attempt <- function(left, right, x = dta_double(c(1, 2)), y = 1, op = "+") {
        force(x); force(y); force(op)
        minimum <- "double"
        .Call(C_dtatools_scalar_arithmetic, left, right, environment(),
              .computed_storage_getter, .scalar_arith_dependencies)
    }
    # Native lexical inspection must see the installed namespace, not
    # testthat's copy with independent, unforced helper promises.
    environment(attempt) <- asNamespace("dtatools")
    native_expected <- .scalar_native_profile_expected()
    check_result <- function(native, public, expected) {
        expect_identical(as.double(public), expected)
        if (native_expected) {
            expect_identical(as.double(native), expected)
            native
        } else {
            expect_null(native)
            public
        }
    }
    left <- c(10, 20)
    result <- check_result(attempt(left, 3), dta_double(left) + 3, c(13, 23))
    check_result(attempt(left, 3L), dta_double(left) + 3L, c(13, 23))
    check_result(attempt(left, TRUE), dta_double(left) + TRUE, c(11, 21))
    check_result(attempt(7, left, x = 1, y = dta_double(c(1, 2))),
                 7 + dta_double(left), c(17, 27))
    check_result(attempt(7, left, x = 1, y = dta_double(c(1, 2)), op = "-"),
                 7 - dta_double(left), c(-3, -13))
    expect_null(attempt(c(1L, 2L), 3L))
    expect_null(attempt(left, c(3, 4)))
    expect_null(attempt(left, NA_real_))
    expect_null(attempt(left, 3, op = "*"))
    reads <- 0L
    foreign <- .Call(C_dtatools_callback_double, c(3, 4),
                      function() { reads <<- reads + 1L }, TRUE)
    expect_null(attempt(foreign, 3))
    expect_identical(reads, 0L)
    pointer <- .Call(C_dtatools_owned_pointer, result, TRUE)
    .Call(C_dtatools_owned_pointer_write, pointer, 1L, 99)
    expect_identical(as.double(result), c(99, 23))
    expect_identical(left, c(10, 20))
})

test_that("scalar arithmetic keeps operands settled before a source callback", {
    source <- dta_double(c(1, 2))
    original <- .dta_data
    calls <- 0L
    local_mocked_bindings(.dta_data = function(value, ...) {
        calls <<- calls + 1L
        assign("x", 100, envir = parent.frame())
        original(value, ...)
    })
    plus <- .dta_arith_base("+", 2, source, "double")
    minus <- .dta_arith_base("-", 2, source, "double")
    expect_identical(as.double(plus), c(3, 4))
    expect_identical(as.double(minus), c(1, 0))
    expect_identical(calls, 2L)
})

test_that("computed storage is chosen for the complete result", {
    finish <- dtatools:::.dta_computed
    cases <- list(
        list(c(0.1, 1e40), "byte", "double", c(0.1, 1e40)),
        list(c(0.1, 2000000000), "byte", "float",
             as.double(dta_float(c(0.1, 2000000000)))),
        list(c(0.1, 1), "long", "double", c(0.1, 1)),
        list(c(-127, 100), "byte", "byte", c(-127, 100)),
        list(c(-128, 101), "byte", "int", c(-128, 101)),
        list(c(-32768, 32741), "int", "long", c(-32768, 32741))
    )
    for (case in cases) {
        minimum <- case[[2L]]
        value <- finish(case[[1L]], minimum)
        expect_identical(dta_storage_type(value), case[[3L]])
        expect_identical(as.double(value), case[[4L]])
    }
    for (storage in c("byte", "int", "long", "float", "double")) {
        expect_identical(dta_storage_type(finish(double(), storage)), storage)
        value <- finish(c(NA_real_, tagged_missing(letters)), storage)
        expect_identical(dta_storage_type(value), storage)
        expect_identical(missing_tag(value), c(NA_character_, letters))
    }
})

test_that("computed double preserves missing bits and normalizes undefined values", {
    finish <- dtatools:::.dta_computed
    bits <- function(x) writeBin(as.double(x), raw(), size = 8L)
    raw_missing <- c(NA_real_, tagged_missing(letters), -tagged_missing("a"))
    expect_identical(bits(finish(raw_missing, "double")), bits(raw_missing))
    input <- c(-0, .Machine$double.xmin / 2, .Machine$double.xmax / 2,
               NaN, Inf, -Inf, .Machine$double.xmax)
    expect_identical(bits(finish(input, "double")),
                     bits(c(input[1:3], rep(NA_real_, 4L))))
    invalid_tag <- readBin(as.raw(c(0xa2, 0x07, 0, 0, 0x41, 0, 0xf0, 0x7f)),
                           "double", n = 1L, size = 8L, endian = "little")
    expect_identical(bits(finish(invalid_tag, "double")), bits(invalid_tag))
    expect_error(finish(invalid_tag, "int"), "invalid trusted Stata numeric missing code")
})

test_that("computed results retain evaluation order and independent values", {
    finish <- dtatools:::.dta_computed
    log <- character()
    result <- finish(c(a = 1, b = 2),
        { log <- c(log, "minimum"); "double" },
        { log <- c(log, "temporal"); 0L })
    expect_identical(log, c("temporal", "minimum"))
    expect_identical(names(result), c("a", "b"))
    expect_identical(finish(TRUE, stop("unused"), stop("unused")), TRUE)
    expect_identical(finish(1i, stop("unused"), stop("unused")), 1i)
    source <- dta_double(c(1, 2))
    result <- source + 0
    result[1] <- 9
    expect_identical(as.double(source), c(1, 2))
    expect_identical(as.double(result), c(9, 2))
    expect_identical(as.double(dta_double(NA_real_) ^ 0), NA_real_)
    expect_identical(as.double(1 ^ dta_double(NA_real_)), NA_real_)
})

test_that("computed policies retain exact temporal validation and getter callbacks", {
    for (temporal in list(0, FALSE, NA_integer_, structure(0L, names = "t"))) {
        expect_error(.dta_computed(c(1, 2), "double", temporal),
                     "invalid Stata temporal storage type")
    }
    calls <- 0L
    original <- .declared_dta_storage
    local_mocked_bindings(.declared_dta_storage = function(x) {
        calls <<- calls + 1L
        original(x)
    }, .package = "dtatools")
    value <- dta_double(c(1, 2))
    expect_identical(as.double(value + 1), c(2, 3))
    expect_identical(calls, 1L)
})

test_that("native classification declines traced predicates", {
    attempt <- function(minimum = "double", temporal = 0L) {
        .Call(C_dtatools_computed_numeric, c(1, 2), environment(),
              .computed_storage_getter, .computed_numeric_dependencies)
    }
    environment(attempt) <- asNamespace("dtatools")
    invisible(.dta_computed(c(1, 2), "double"))
    if (.dtatools_execution_profile_expected()) {
        expect_type(attempt(), "list")
    } else {
        expect_null(attempt())
    }
    expect_identical(as.double(.dta_computed(c(1, 2), "double")), c(1, 2))
    trace("is.na", quote(invisible(NULL)), where = baseenv(), print = FALSE)
    declined <- tryCatch(attempt(), finally = untrace("is.na", where = baseenv()))
    expect_null(declined)
})

test_that("getter admission does not read foreign literals", {
    reads <- 0L
    literal <- .Call(C_dtatools_callback_character, "stata.storage", function() {
        reads <<- reads + 1L
    })
    getter <- .declared_dta_storage
    expression <- body(getter)
    expression[[2L]][[3L]] <- literal
    body(getter) <- expression
    local_mocked_bindings(.declared_dta_storage = getter, .package = "dtatools")
    source <- dta_double(c(1, 2))
    attempt <- function(minimum = .declared_dta_storage(source),
                        minimum_source = source, temporal = 0L) {
        .Call(C_dtatools_computed_numeric, c(1, 2), environment(),
              .computed_storage_getter, .computed_numeric_dependencies)
    }
    environment(attempt) <- list2env(list(source = source),
                                     parent = asNamespace("dtatools"))
    expect_null(attempt())
    expect_identical(reads, 0L)
    expect_identical(as.double(source + 1), c(2, 3))
    expect_identical(reads, 1L)
})

test_that("foreign result reads precede delayed policy evaluation without replay", {
    events <- character()
    value <- .Call(C_dtatools_callback_double, c(1, 2), function() {
        events <<- c(events, "read")
    }, FALSE)
    result <- .dta_computed(value,
        { events <- c(events, "minimum"); "double" },
        { events <- c(events, "temporal"); 0L })
    expect_identical(as.double(result), c(1, 2))
    expect_identical(events, c("read", "temporal", "minimum"))
})

test_that("computed output owns its values without exposing the source pointer", {
    source <- dta_double(c(1, 2, NA_real_, tagged_missing("z")))
    before <- .Call(C_dtatools_owned_info, source)
    result <- source + 1
    after <- .Call(C_dtatools_owned_info, source)
    expect_identical(after[c("backing", "exposed", "bytes", "depth")],
                     before[c("backing", "exposed", "bytes", "depth")])
    pointer <- .Call(C_dtatools_owned_pointer, result, TRUE)
    .Call(C_dtatools_owned_pointer_write, pointer, 1L, 20)
    expect_identical(as.double(source)[1:2], c(1, 2))
    expect_identical(as.double(result), c(20, 3, NA_real_, NA_real_))
})

test_that("double scalar arithmetic agrees bit for bit with the general path", {
    bits <- function(x) writeBin(as.double(x), raw(), size = 8L)
    values <- c(-0, 0, .Machine$double.xmin / 2, -.Machine$double.xmin / 2,
                1, -1, .Machine$double.xmax / 2, -.Machine$double.xmax / 2,
                NA_real_, tagged_missing(letters))
    for (source in list(dta_double(values),
                        structure(values, stata.storage = "double",
                                  class = .dta_storage_class("double")))) {
        for (scalar in list(-0, 0, .Machine$double.xmin / 2, 1, -1L, TRUE,
                            .Machine$double.xmax / 2)) {
            for (op in c("+", "-")) for (reverse in c(FALSE, TRUE)) {
                x <- if (reverse) scalar else source
                y <- if (reverse) source else scalar
                policy_calls <- 0L
                expected <- .dta_arith_base(op, x, y, {
                    policy_calls <- policy_calls + 1L
                    "double"
                })
                actual <- get(op)(x, y)
                expect_identical(policy_calls, 1L)
                expect_identical(bits(actual), bits(expected))
                expect_identical(attributes(actual), attributes(expected))
            }
        }
    }
})

test_that("scalar admission preserves delayed operator and recycling order", {
    calls <- character()
    expect_error(.dta_arith_base(
        { calls <- c(calls, "operator"); stop("operator evaluated") },
        dta_double(c(1, 2)), c(1, 2, 3), "double"
    ), class = "vctrs_error_incompatible_size")
    expect_identical(calls, character())
    expect_error(.dta_arith_base(
        { calls <- c(calls, "operator"); stop("operator evaluated") },
        dta_double(c(1, 2)), 1, "double"
    ), "operator evaluated")
    expect_identical(calls, "operator")
})

test_that("scalar admission keeps traced recycling and getter calls", {
    calls <- 0L
    trace("vec_recycle_common", tracer = function() { calls <<- calls + 1L },
          where = asNamespace("vctrs"), print = FALSE)
    value <- tryCatch(dta_double(c(1, 2)) + 1,
                      finally = untrace("vec_recycle_common", where = asNamespace("vctrs")))
    expect_identical(as.double(value), c(2, 3))
    expect_identical(calls, 1L)
})

test_that("computed arithmetic retains executable primitive tracers", {
    for (target in c("length", "list")) {
        source <- dta_double(c(1, 2))
        invisible(source + 0)
        calls <- 0L
        trace(target, tracer = function() { calls <<- calls + 1L },
              where = baseenv(), print = FALSE)
        observed <- tryCatch({
            calls <- 0L
            scalar <- source + 0
            scalar_calls <- calls
            calls <- 0L
            vector <- source + c(0, 0)
            vector_calls <- calls
            list(scalar = scalar, vector = vector,
                 calls = c(scalar = scalar_calls, vector = vector_calls))
        }, finally = untrace(target, where = baseenv()))
        expected <- if (target == "length") {
            if (.dtatools_bytecode_execution_expected()) 1L else 4L
        } else 2L
        expect_identical(observed$calls, c(scalar = expected, vector = expected),
                         info = target)
        expect_identical(as.double(observed$scalar), c(1, 2))
        expect_identical(as.double(observed$vector), c(1, 2))
    }
})

test_that("scalar fallback reads classed recycled arguments only once per use", {
    source <- dta_double(c(1, 2))
    invisible(source + 1)
    reads <- integer()
    table <- get(".__S3MethodsTable__.", envir = baseenv())
    registerS3method("[[", "dtatools_scalar_args", function(x, i, ...) {
        reads <<- c(reads, i)
        .subset2(unclass(x), i) + length(reads)
    }, envir = baseenv())
    withr::defer(rm(list = "[[.dtatools_scalar_args", envir = table))
    original <- vctrs::vec_recycle_common
    local_mocked_bindings(vec_recycle_common = function(...) {
        structure(original(...), class = "dtatools_scalar_args")
    }, .package = "vctrs")
    result <- source + 1
    expect_identical(reads, c(1L, 2L, 1L, 2L))
    expect_identical(as.double(result), c(5, 6))
})

test_that("scalar native decline does not touch a foreign operand", {
    calls <- 0L
    foreign <- .Call(C_dtatools_callback_double, c(1, 2), function() {
        calls <<- calls + 1L
    }, FALSE)
    attr(foreign, "stata.storage") <- "double"
    attr(foreign, "class") <- .dta_storage_class("double")
    attempt <- function(x, y = 1, op = "+", minimum = "double") {
        .Call(C_dtatools_scalar_arithmetic, x, y, environment(),
              .computed_storage_getter, .scalar_arith_dependencies)
    }
    environment(attempt) <- asNamespace("dtatools")
    expect_null(attempt(foreign))
    expect_identical(calls, 0L)
})

test_that("scalar arithmetic runs operand names methods before admission", {
    source <- dta_double(c(1, 2))
    events <- character()
    table <- get(".__S3MethodsTable__.", envir = baseenv())
    registerS3method("names", "dta_numeric", function(x) {
        events <<- c(events, "names")
        NULL
    }, envir = baseenv())
    withr::defer(rm(list = "names.dta_numeric", envir = table))
    expected <- .dta_arith_base("+", source, 1, { "double" })
    expected_events <- events
    events <- character()
    actual <- .dta_arith_base("+", source, 1, "double")
    expect_identical(events, expected_events)
    expect_identical(expected_events, "names")
    expect_identical(as.double(actual), as.double(expected))
})

test_that("scalar arithmetic preserves nested recycling and warning callbacks", {
    source <- dta_double(c(1, 2))
    invisible(source + 1)
    for (name in c("withCallingHandlers", "parent.frame", "list2")) {
        where <- if (name == "list2") asNamespace("rlang") else baseenv()
        calls <- 0L
        trace(name, tracer = function() { calls <<- calls + 1L },
              where = where, print = FALSE)
        captured <- tryCatch({
            calls <- 0L
            result <- .dta_arith_base("+", source, 1, "double")
            list(value = result, calls = calls)
        }, finally = untrace(name, where = where))
        expect_identical(captured$calls, 1L, info = name)
        expect_identical(as.double(captured$value), c(2, 3))
    }
})

test_that("scalar arithmetic retains the final classed names assignment", {
    source <- dta_double(c(1, 2))
    invisible(source + 1)
    invisible(source + 1)
    calls <- 0L
    table <- get(".__S3MethodsTable__.", envir = baseenv())
    registerS3method("names<-", "dta_numeric", function(x, value) {
        calls <<- calls + 1L
        attr(x, "setter_was_called") <- TRUE
        x
    }, envir = baseenv())
    withr::defer(rm(list = "names<-.dta_numeric", envir = table))
    result <- source + 1
    expect_identical(calls, 1L)
    expect_true(attr(result, "setter_was_called", exact = TRUE))
    expect_identical(as.double(result), c(2, 3))
})

test_that("computed arithmetic declines replaced primitive predicates", {
    limit <- .Machine$double.xmax / 2
    source <- dta_double(c(1, limit))
    right <- c(0, limit)
    invisible(source + right)
    invisible(source + limit)
    with_primitive <- function(name, replacement, expression) {
        original <- get(name, envir = baseenv(), inherits = FALSE)
        unlockBinding(name, baseenv())
        on.exit({
            unlockBinding(name, baseenv())
            assign(name, original, envir = baseenv())
            lockBinding(name, baseenv())
        }, add = TRUE)
        assign(name, replacement, envir = baseenv())
        lockBinding(name, baseenv())
        force(expression)
    }
    replacements <- list(abs = .Primitive("-"), is.finite = .Primitive("is.na"),
                         any = .Primitive("all"))
    for (name in names(replacements)) {
        result <- with_primitive(name, replacements[[name]], list(
            vector = source + right,
            scalar = source + limit
        ))
        # These are the established R-path results under each replacement.
        missing <- identical(name, "is.finite")
        expect_identical(as.double(result$vector),
                         if (missing) c(NA_real_, NA_real_) else c(1, limit * 2),
                         info = name)
        expect_identical(as.double(result$scalar),
                         if (missing) c(NA_real_, NA_real_) else c(limit, limit * 2),
                         info = name)
    }
})

test_that("computed arithmetic retains machine limit values and methods", {
    source <- dta_double(c(1, 2))
    invisible(source + 0)
    invisible(source + c(0, 0))
    with_machine <- function(machine, expression) {
        local_mocked_bindings(.Machine = machine, .package = "base")
        force(expression)
    }
    calls <- 0L
    table <- get(".__S3MethodsTable__.", envir = baseenv())
    registerS3method("$", "dtatools_machine_limit", function(x, name) {
        calls <<- calls + 1L
        .subset2(x, name)
    }, envir = baseenv())
    withr::defer(rm(list = "$.dtatools_machine_limit", envir = table))
    result <- with_machine(structure(.Machine, class = "dtatools_machine_limit"), {
        values <- list(source + 0, source + c(0, 0))
        list(values = values, calls = calls)
    })
    expect_identical(result$calls, 4L)
    for (value in result$values) expect_identical(as.double(value), c(1, 2))

    machine <- .Machine
    machine$double.xmax <- 2
    result <- with_machine(machine, list(source + 0, source + c(0, 0)))
    for (value in result) expect_identical(as.double(value), c(1, NA_real_))
})

test_that("computed machine limit admission never reads foreign metadata", {
    source <- dta_double(c(1, 2))
    attempt <- function(machine, x = source, y = 1, op = "+",
                        minimum = "double", temporal = 0L) {
        .Machine <- machine
        operation <- .Primitive("+")
        list(
            computed = .Call(C_dtatools_computed_numeric, c(1, 2), environment(),
                .computed_storage_getter, .computed_numeric_dependencies),
            scalar = .Call(C_dtatools_scalar_arithmetic, c(1, 2), 1, environment(),
                .computed_storage_getter, .scalar_arith_dependencies)
        )
    }
    environment(attempt) <- list2env(list(source = source),
                                     parent = asNamespace("dtatools"))
    reads <- 0L
    callback <- function() { reads <<- reads + 1L }
    foreign_limit <- .Call(C_dtatools_callback_double, .Machine$double.xmax,
                           callback, TRUE)
    foreign_names <- list(.Machine$double.xmax)
    attr(foreign_names, "names") <- .Call(C_dtatools_callback_character,
                                          "double.xmax", callback)
    active <- new.env(parent = emptyenv())
    makeActiveBinding("double.xmax", function() {
        callback()
        .Machine$double.xmax
    }, active)
    delayed <- new.env(parent = emptyenv())
    delayedAssign("double.xmax", { callback(); .Machine$double.xmax },
                  assign.env = delayed)
    machines <- list(
        foreign_names, list(double.xmax = foreign_limit),
        list(double.xmax = structure(.Machine$double.xmax, class = "foreign")),
        structure(.Machine, class = "foreign"), active, delayed,
        list(double.xmax = 2), list(double.xmax = .Machine$double.xmax[FALSE]),
        c(.Machine, stats::setNames(rep(list(0), 129L), paste0("extra", 1:129)))
    )
    reads <- 0L
    for (machine in machines) {
        result <- attempt(machine)
        expect_null(result$computed)
        expect_null(result$scalar)
    }
    expect_identical(reads, 0L)
    result <- attempt(list(unrelated = foreign_limit,
                           double.xmax = .Machine$double.xmax))
    if (.dtatools_execution_profile_expected()) {
        expect_type(result$computed, "list")
    } else {
        expect_null(result$computed)
    }
    if (.scalar_native_profile_expected()) {
        expect_type(result$scalar, "double")
    } else {
        expect_null(result$scalar)
    }
    expect_identical(as.double(source + 1), c(2, 3))
    expect_identical(reads, 0L)
})
