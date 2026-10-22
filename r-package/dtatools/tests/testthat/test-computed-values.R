# `.dta_computed()` without the native calls at its start: the R code that
# results the native calls leave alone still run.
.computed_r_code <- function() {
    computed <- .dta_computed
    code <- as.list(body(computed))
    native <- vapply(code, function(expression) any(all.names(expression) %in% c(
        "C_dtatools_computed_numeric", "C_dtatools_computed_values"
    )), NA)
    body(computed) <- as.call(code[!native])
    computed
}
.computed_facts <- function(x) list(
    value = x, attributes = attributes(x),
    owned = .Call(C_dtatools_is_owned_double, x),
    compact = .is_unmaterialized_numeric_altrep(x)
)
.computed_same <- function(x, y) {
    identical(x, y, num.eq = FALSE, single.NA = FALSE, attrib.as.set = FALSE)
}
.computed_bits <- function(high, low) {
    readBin(writeBin(c(as.integer(low), as.integer(high)), raw(), size = 4L,
                     endian = "little"), "double", endian = "little")
}
# Counts the R code's first helper call, which the native call skips.
.computed_count <- function(env = parent.frame()) {
    calls <- 0L
    suppressMessages(trace(".tab_missing_codes", tracer = function() calls <<- calls + 1L,
                           where = asNamespace("dtatools"), print = FALSE))
    withr::defer(suppressMessages(untrace(".tab_missing_codes",
                                          where = asNamespace("dtatools"))), envir = env)
    list(reset = function() calls <<- 0L, calls = function() calls)
}

test_that("small computed results match the R code", {
    r_code <- .computed_r_code()
    count <- .computed_count()
    cases <- list(
        1990.5, 1990, 0, -0, 1.5, 100, 101, -127, -128, 32740, 32741, -32767,
        2147483620, 2147483621, -2147483647, -2147483648, 5e9, 0.1, 1e30, 3.4e38,
        2^126 * (2 - 2^-23), 3.5e38, 1e300, 1e308, Inf, -Inf, NaN, NA_real_,
        .computed_bits(0x7ff80000L, 1954L), .computed_bits(-0x00100000L, 1954L),
        unclass(tagged_missing("a")), unclass(tagged_missing("z")), numeric(),
        c(1, 2, NA), c(1.5, NaN, 3), c(1, Inf), c(0.5, 1e308), c(NA, NA),
        c(unclass(tagged_missing("b")), 2), c(1, 2, 3, 4) / 3, seq(-200, 200, by = 0.5)
    )
    for (values in cases) {
        for (minimum in .dta_storage) {
            count$reset()
            native <- .computed_facts(.dta_computed(values, minimum))
            expect_identical(count$calls(), 0L)
            expected <- .computed_facts(r_code(values, minimum))
            expect_true(.computed_same(native, expected),
                        info = paste(format(values), minimum, collapse = " "))
        }
    }
})

test_that("computed results the native call does not cover run the R code", {
    r_code <- .computed_r_code()
    count <- .computed_count()
    foreign <- .Call(C_dtatools_callback_double, c(1, 2), function() NULL, FALSE)
    cases <- list(
        list(c(a = 1, b = 2), "byte"),
        list(c(18000, 18001.5, NA), "long", 1L),
        list(c(18000, NA), "double", 2L),
        list(c(1, 2), "byte", asS4(0L)),
        list(asS4(c(1, 2)), "byte"),
        list(1, "strL"),
        list(1, c("int", "int")),
        list(1, structure("int", note = TRUE)),
        list(.computed_bits(0x7ff00041L, 1954L), "double"),
        list(.computed_bits(0x7ff00041L, 1954L), "byte"),
        list(foreign, "double"),
        list(rep(1.5, 2048L), "int"),
        list(TRUE, "byte"),
        list(3L, "byte")
    )
    for (case in cases) {
        count$reset()
        actual <- tryCatch(.computed_facts(do.call(.dta_computed, case)),
                           error = conditionMessage)
        if (is.double(case[[1L]]) && !.is_altrep(case[[1L]])) {
            expect_gt(count$calls(), 0L)
        }
        expected <- tryCatch(.computed_facts(do.call(r_code, case)),
                             error = conditionMessage)
        expect_true(.computed_same(actual, expected), info = paste(format(case), collapse = " "))
    }
})

test_that("small computed results settle their arguments in the R code's order", {
    events <- character()
    result <- .dta_computed(c(1, 2),
        { events <- c(events, "minimum"); "byte" },
        { events <- c(events, "temporal"); 0L })
    expect_identical(events, c("temporal", "minimum"))
    expect_identical(.declared_dta_storage(result), "byte")

    # The R code returns a logical result before it reads the others.
    events <- character()
    expect_identical(.dta_computed(TRUE, { events <- c(events, "minimum"); "byte" }), TRUE)
    expect_identical(events, character())

    # A foreign result is read before either.
    events <- character()
    value <- .Call(C_dtatools_callback_double, c(1, 2), function() {
        events <<- c(events, "read")
    }, FALSE)
    result <- .dta_computed(value,
        { events <- c(events, "minimum"); "double" },
        { events <- c(events, "temporal"); 0L })
    expect_identical(events, c("read", "temporal", "minimum"))

    # A tag byte outside `.a` through `.z` declines before forcing either.
    events <- character()
    suppressMessages(trace(".tab_missing_codes", tracer = function() events <<- c(events, "codes"),
                           where = asNamespace("dtatools"), print = FALSE))
    withr::defer(suppressMessages(untrace(".tab_missing_codes",
                                          where = asNamespace("dtatools"))))
    invisible(.dta_computed(.computed_bits(0x7ff00041L, 1954L),
        { events <- c(events, "minimum"); "double" },
        { events <- c(events, "temporal"); 0L }))
    expect_identical(events[[1L]], "codes")
    expect_identical(events[events != "codes"], c("temporal", "minimum"))
})

test_that("small computed results skip the R code's helpers", {
    count <- .computed_count()
    small <- .dta_computed(c(1.5, 2), "int")
    expect_identical(count$calls(), 0L)
    large <- .dta_computed(rep(c(1.5, 2), 1024L), "int")
    expect_gt(count$calls(), 0L)
    expect_identical(.declared_dta_storage(small), "float")
    expect_identical(.declared_dta_storage(large), "float")
})
