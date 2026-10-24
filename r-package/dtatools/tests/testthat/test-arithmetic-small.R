# ADR 0059: `.dta_arith_base()` computes operands under the size gate in one
# native call. These tests call it from a frame like the helper's and compare
# it with the R code that follows it in the helper.
.small_arithmetic_native <- function(op, x, y, minimum) {
    if (.Call(C_dtatools_arithmetic_small)) native else NULL
}
environment(.small_arithmetic_native) <- asNamespace("dtatools")

.small_arithmetic_r <- local({
    helper <- dtatools:::.dta_arith_base
    statements <- as.list(body(helper))
    skipped <- vapply(statements[2:3], function(statement)
        paste(deparse(statement), collapse = " "), character(1))
    stopifnot(grepl("C_dtatools_arithmetic_small", skipped[[1L]], fixed = TRUE),
              grepl("C_dtatools_scalar_arithmetic", skipped[[2L]], fixed = TRUE))
    body(helper) <- as.call(statements[-(2:3)])
    helper
})

.small_arithmetic_same <- function(actual, expected) {
    same <- identical(actual, expected, num.eq = FALSE, single.NA = FALSE) &&
        identical(attributes(actual), attributes(expected))
    if (!same || !is.numeric(actual)) return(same)
    identical(is_tagged_missing(actual), is_tagged_missing(expected))
}

.small_arithmetic_outcome <- function(operation) {
    tryCatch(operation(), error = function(error) conditionMessage(error))
}

.small_arithmetic_stata <- function() list(
    byte = dta_byte(c(1, -3, NA, tagged_missing("a"), 100)),
    int = dta_int(c(30000, -2, 7, NA, tagged_missing("z"))),
    long = dta_long(c(2e9, -1, 0, NA, 5)),
    float = dta_float(c(0.5, 1.25, -3, NA, tagged_missing("b"))),
    double = dta_double(c(0.1, 1e300, -2.5, NA, tagged_missing("c"))),
    labelled = set_val_labels(dta_byte(c(1, 2, NA, tagged_missing("d"), 2)),
                              c(male = 1, female = 2)),
    described = set_var_label(dta_float(c(1.5, -2, 4, 8, NA)), "a label"),
    one = dta_int(7)
)

.small_arithmetic_bare <- function() list(
    double = c(2, 0, Inf, NaN, -0),
    zero = 0,
    huge = 1e308,
    not_a_number = NaN,
    integer = c(1L, NA, -2L, 3L, 0L),
    three = 3L,
    logical = c(TRUE, NA, FALSE, TRUE, FALSE),
    true = TRUE
)

.small_arithmetic_pairs <- function() {
    stata <- .small_arithmetic_stata()
    others <- c(stata, .small_arithmetic_bare())
    pairs <- list()
    for (left in names(stata)) for (right in names(others)) {
        pairs[[paste(left, right)]] <- list(stata[[left]], others[[right]])
        pairs[[paste(right, left)]] <- list(others[[right]], stata[[left]])
    }
    pairs
}

test_that("one native call gives what the R code gives for small operands", {
    invisible(dta_double(c(1, 2)) + 1)
    pairs <- .small_arithmetic_pairs()
    failures <- character()
    admitted <- 0L
    for (name in names(pairs)) for (op in c("+", "-", "*", "/")) {
        for (minimum in c("byte", "int", "long", "float", "double")) {
            x <- pairs[[name]][[1L]]
            y <- pairs[[name]][[2L]]
            actual <- .small_arithmetic_native(op, x, y, minimum)
            expected <- .small_arithmetic_r(op, x, y, minimum)
            if (is.null(actual)) {
                failures <- c(failures, paste(name, op, minimum, "declined"))
            } else {
                admitted <- admitted + 1L
                if (!.small_arithmetic_same(actual, expected))
                    failures <- c(failures, paste(name, op, minimum))
            }
        }
    }
    expect_identical(failures, character())
    expect_identical(admitted, length(pairs) * 20L)
})

test_that("operators give the same results with and without the native call", {
    invisible(dta_double(c(1, 2)) + 1)
    pairs <- .small_arithmetic_pairs()
    results <- list()
    for (mode in c("native", "r")) {
        if (mode == "r") {
            prior <- .Call(C_dtatools_test_numeric_size_minimum, 0L)
            withr::defer(.Call(C_dtatools_test_numeric_size_minimum, prior))
        }
        results[[mode]] <- lapply(pairs, function(pair) lapply(
            c("+", "-", "*", "/"), function(op) .small_arithmetic_outcome(
                function() getExportedValue("base", op)(pair[[1L]], pair[[2L]])
            )
        ))
    }
    for (name in names(pairs)) for (index in 1:4) {
        expect_true(.small_arithmetic_same(results$native[[name]][[index]],
                                           results$r[[name]][[index]]),
                    info = paste(name, c("+", "-", "*", "/")[[index]]))
    }
})

test_that("small Stata arithmetic skips the R code", {
    invisible(dta_double(c(1, 2)) + 1)
    hits <- 0L
    suppressMessages(trace(".collapse_missing", tracer = function() hits <<- hits + 1L,
                           where = asNamespace("dtatools"), print = FALSE))
    withr::defer(suppressMessages(untrace(".collapse_missing",
                                          where = asNamespace("dtatools"))))
    x <- dta_byte(c(1, 2, NA))
    small <- x * 2
    small_hits <- hits
    hits <- 0L
    power <- x^2
    power_hits <- hits
    expect_identical(small_hits, 0L)
    expect_identical(as.double(small), c(2, 4, NA))
    expect_identical(dta_storage_type(small), "byte")
    expect_identical(as.double(power), c(1, 4, NA))
    expect_gt(power_hits, 0L)
})

test_that("other operators, operands and sizes leave the call to the R code", {
    invisible(dta_double(c(1, 2)) + 1)
    native <- .small_arithmetic_native
    x <- dta_int(c(1, 2, 3))
    for (op in list("^", "%%", "%/%", "++", "", NA_character_, c("+", "-"),
                    as.name("+"), structure("+", class = "operator")))
        expect_null(native(op, x, 2, "double"), info = deparse(op))
    bare <- c(1, 2, 3)
    integer <- 1L
    logical <- TRUE
    expect_null(native("+", bare, 2, "double"))
    expect_null(native("+", integer, logical, "double"))
    shorter <- dta_int(c(1, 2))
    expect_null(native("+", x, shorter, "double"))
    expect_error(.small_arithmetic_r("+", x, shorter, "double"))
    empty <- dta_int(numeric())
    none <- numeric()
    expect_null(native("+", empty, 2, "double"))
    expect_null(native("+", x, none, "double"))
    others <- list(named = c(a = 1, b = 2, c = 3), factor = factor(c("a", "b", "c")),
                   character = "2", complex = 2i, list = list(2), matrix = matrix(1:3),
                   date = as.Date("2020-01-01"))
    for (name in names(others)) {
        other <- others[[name]]
        expect_null(native("+", x, other, "double"), info = name)
        expect_null(native("+", other, x, "double"), info = name)
    }
    named <- x
    names(named) <- c("a", "b", "c")
    expect_null(native("+", named, 2, "double"))
    subclass <- x
    class(subclass) <- c("probe_subclass", class(subclass))
    expect_true(.is_unmaterialized_numeric_altrep(subclass))
    expect_null(native("+", subclass, 2, "double"))
    expect_null(native("+", 2, subclass, "double"))
    large <- dta_int(seq_len(2048L))
    one <- dta_int(1)
    expect_null(native("+", large, 2, "double"))
    expect_null(native("+", 2, large, "double"))
    expect_null(native("+", one, large, "double"))
    below <- dta_int(seq_len(2047L))
    expect_identical(as.double(native("+", below, 2, "double")), seq_len(2047L) + 2)
    # An operand or operator still to be computed stays unevaluated.
    expect_null(native("+", x, stop("forced"), "double"))
    expect_null(native("+", stop("forced"), x, "double"))
    expect_null(native(stop("forced"), x, 2, "double"))
    # As in the R code, `minimum` is forced after the values are computed.
    expect_error(native("+", x, 2, stop("minimum forced")), "minimum forced")
    # A storage the call cannot build goes to `.dta_computed()`, as in the R code.
    expect_identical(tryCatch(native("+", x, 2, "short"), error = conditionMessage),
                     tryCatch(.small_arithmetic_r("+", x, 2, "short"),
                              error = conditionMessage))
    prior <- .Call(C_dtatools_test_numeric_size_minimum, 0L)
    withr::defer(.Call(C_dtatools_test_numeric_size_minimum, prior))
    expect_null(native("+", x, 2, "double"))
})

test_that("a minimum that changes an operand keeps the values computed before it", {
    invisible(dta_double(c(1, 2)) + 1)
    # The call reads `x` before it forces `minimum`, as the R code does. A
    # named storage leaves the result to `.dta_computed()`, which gets those
    # values instead of a rerun on the changed `x`.
    run <- function(helper) {
        x <- dta_int(1)
        helper("+", x, 1, { x <- dta_int(100); c(storage = "int") })
    }
    expected <- run(.small_arithmetic_r)
    expect_identical(as.double(expected), 2)
    expect_true(.small_arithmetic_same(run(.small_arithmetic_native), expected))
    expect_true(.small_arithmetic_same(run(dtatools:::.dta_arith_base), expected))
})

test_that("the call checks base's operators and its own frame", {
    invisible(dta_double(c(1, 2)) + 1)
    x <- dta_int(c(1, 2, 3))
    # The call compares base's binding of the operator with the primitive in
    # `.numeric_binary_dependencies` as the frame finds it.
    swapped <- .small_arithmetic_native
    environment(swapped) <- list2env(list(.numeric_binary_dependencies = list(
        .Primitive("*"), .Primitive("/"), .Primitive("-"), .Primitive("+")
    )), parent = asNamespace("dtatools"))
    expect_null(swapped("+", x, 2, "double"))
    expect_null(swapped("-", x, 2, "double"))
    expect_false(is.null(swapped("*", x, 2, "double")))
    # The call never replaces a binding of `native` in its frame.
    bound <- function(op, x, y, minimum) {
        native <- "kept"
        list(.Call(C_dtatools_arithmetic_small), native)
    }
    environment(bound) <- asNamespace("dtatools")
    expect_identical(bound("+", x, 2, "double"), list(FALSE, "kept"))
})
