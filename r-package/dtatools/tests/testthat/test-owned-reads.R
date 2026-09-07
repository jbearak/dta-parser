test_that("owned integer and logical exports preserve base values and argument evaluation", {
    fixtures <- list(numeric(), c(-1.75, -0, 0, 0.25, 1.9),
                     c(-2147483648, -2147483647.5, 2147483647, 2147483647.5, 2147483648),
                     c(1, NA_real_, tagged_missing("a"), tagged_missing("z")),
                     c(a = 0, b = 1, c = NA_real_))
    for (convert in list(as.integer, as.logical)) {
        for (values in fixtures) {
            source <- dta_double(values)
            expect_identical(suppressWarnings(convert(source)), suppressWarnings(convert(values)))
            expect_identical(as.double(source), unname(values))
        }
        source <- dta_double(c(1, 2))
        calls <- 0L
        expect_identical(convert(source, { calls <- calls + 1L; 7 }), convert(c(1, 2)))
        expect_identical(calls, 1L)
        expect_error(convert(source, stop("forced extra argument")), "forced extra argument")
        expect_error(convert(source, ), "argument.*empty|argument.*missing")
    }
})

test_that("integer warnings can rewrite and collect the original source safely", {
    data <- dibble(x = dta_double(c(1, 1e20, 3)))
    seen <- character()
    calls <- list()
    result <- withCallingHandlers(as.integer(data$x), warning = function(w) {
        seen <<- c(seen, conditionMessage(w))
        calls[[length(calls) + 1L]] <<- conditionCall(w)
        replace_values(data, x, 9, where = 1L)
        gc()
        invokeRestart("muffleWarning")
    })
    expect_identical(seen, "NAs introduced by coercion to integer range")
    expect_identical(calls, list(quote(as.integer.dta_numeric(data$x))))
    expect_identical(result, c(1L, NA_integer_, 3L))
    expect_identical(as.double(data$x), c(9, 1e20, 3))
})

test_that("owned public read helpers retain traced base callbacks", {
    rlang::local_bindings(.owned_read_trace_calls = 0L, .env = globalenv())
    for (target in c("as.integer", "as.logical", "is.na")) {
        value <- dta_double(c(1, NA_real_))
        trace(target, quote(.owned_read_trace_calls <<- .owned_read_trace_calls + 1L),
              where = baseenv(), print = FALSE)
        tryCatch({
            assign(".owned_read_trace_calls", 0L, globalenv())
            getExportedValue("base", target)(value)
            calls <- get(".owned_read_trace_calls", globalenv())
        }, finally = untrace(target, where = baseenv()))
        if (target == "is.na") expect_gte(calls, 1L) else expect_identical(calls, 2L)
    }
})

test_that("owned coercions and range snapshots stay separate from writable pointers", {
    for (exposed in c(FALSE, TRUE)) {
        data <- dibble(x = dta_double(c(0, 1.5, 2, NA_real_)))
        value <- data$x
        pointer <- if (exposed) .Call(C_dtatools_owned_pointer, value, TRUE) else NULL
        before <- .Call(C_dtatools_owned_info, value)
        ordinary <- .dta_data(value, ordinary = TRUE)
        after <- .Call(C_dtatools_owned_info, value)
        expect_identical(after, before)
        expect_null(.Call(C_dtatools_owned_info, ordinary))
        integer <- as.integer(value)
        logical <- as.logical(value)
        if (exposed) .Call(C_dtatools_owned_pointer_write, pointer, 1L, 9)
        else replace_values(data, x, 9, where = 1L)
        expect_identical(ordinary, c(0, 1.5, 2, NA_real_))
        expect_identical(integer, c(0L, 1L, 2L, NA_integer_))
        expect_identical(logical, c(FALSE, TRUE, TRUE, NA))
        ordinary[[2L]] <- 8
        expect_identical(as.double(value)[[2L]], 1.5)
        expect_identical(as.double(data$x)[[1L]], 9)
    }
})

test_that("owned range keeps ordinary summary behavior across missing and empty inputs", {
    capture <- function(expr) {
        warnings <- character()
        value <- withCallingHandlers(expr, warning = function(w) {
            warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
        })
        list(value = value, warnings = warnings)
    }
    for (values in list(numeric(), c(-0, 0), c(3, 1, 2), c(NA_real_, tagged_missing("z")),
                        c(1, NA_real_, tagged_missing("a")), c(a = 2, b = 1))) {
        owned <- dta_double(values)
        ordinary <- unserialize(serialize(owned, NULL))
        for (operation in list(range, min, max)) for (remove in c(FALSE, TRUE)) {
            expect_identical(capture(operation(owned, na.rm = remove)),
                             capture(operation(ordinary, na.rm = remove)))
        }
        expect_identical(capture(range(owned, 4, finite = TRUE, na.rm = TRUE)),
                         capture(range(ordinary, 4, finite = TRUE, na.rm = TRUE)))
    }
})

test_that("owned constructor validation agrees with ordinary detailed validation", {
    invalid_tag <- readBin(as.raw(c(0xa2, 0x07, 0, 0, 0x41, 0, 0xf0, 0x7f)),
                           "double", n = 1L, endian = "little")
    values <- c(-.Machine$double.xmax, -.Machine$double.xmax / 2, -1, -0, 0, 0.25,
                .Machine$double.xmax / 2, .Machine$double.xmax, -Inf, Inf, NaN,
                NA_real_, tagged_missing("a"), tagged_missing("z"), invalid_tag)
    capture <- function(x) tryCatch(dta_double(x), error = function(e) conditionMessage(e))
    for (plain in c(list(numeric(), c(1, NA_real_, 0.25)), as.list(values))) {
        owned <- .Call(C_dtatools_capture_column, plain)
        expect_identical(capture(owned), capture(plain))
    }
    returned <- .Call(C_dtatools_capture_column,
                      structure(c(1, 2), class = "Date"))
    rlang::local_bindings(
        as.double.owned_read_class = function(x, ...) returned,
        is.finite.Date = function(x) stop("classed finite dispatch"),
        .env = globalenv())
    expect_error(dta_double(structure(c(1, 2), class = "owned_read_class")),
                 "classed finite dispatch")
})

test_that("owned missing masks keep names dimensions classes and foreign callbacks", {
    plain <- c(0, NA_real_, NaN, tagged_missing("a"), Inf)
    value <- .Call(C_dtatools_capture_column, plain)
    expect_identical(.dta_read_is_na(value), is.na(plain))
    names(value) <- letters[seq_along(value)]
    expect_identical(.dta_read_is_na(value), setNames(is.na(plain), names(value)))
    dim(value) <- c(1L, 5L)
    expect_identical(.dta_read_is_na(value), is.na(matrix(plain, 1L)))
    class(value) <- "owned_read_missing"
    rlang::local_bindings(is.na.owned_read_missing = function(x) "class dispatch",
                         .env = globalenv())
    expect_identical(.dta_read_is_na(value), "class dispatch")
    calls <- 0L
    foreign <- .Call(C_dtatools_callback_double, plain, function() calls <<- calls + 1L, TRUE)
    expect_identical(.dta_read_is_na(foreign), is.na(plain))
    expect_gt(calls, 0L)
})
