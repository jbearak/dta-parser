# Public behavior plus the native decline contract: an ineligible call has
# neither evaluated caller code nor changed data when the general path starts.
fast_values_probe <- function(data, variable, value, rows = NULL, create = FALSE) {
    .Call(C_dtatools_set_values_fast, data, environment())
}

test_that("native scalar inspection accepts literals and settled bindings only", {
    data <- dibble(x = c(1, 2, 3))
    expect_identical(fast_values_probe(data, "x", 7, rows = 2L), data)
    column <- "x"
    value <- 8L
    rows <- c(3L, 1L, 3L)
    expect_identical(fast_values_probe(data, column, value, rows), data)
    expect_identical(as.double(data$x), c(8, 7, 8))
    touched <- 0L
    expect_null(fast_values_probe(data, "x", { touched <- touched + 1L; 0 }))
    expect_identical(touched, 0L)
    delayedAssign("lazy", { touched <- touched + 1L; 4 })
    expect_null(fast_values_probe(data, "x", lazy))
    expect_identical(touched, 0L)
    makeActiveBinding("active", function() { touched <<- touched + 1L; 5 }, environment())
    expect_null(fast_values_probe(data, "x", active))
    expect_identical(touched, 0L)
    expect_identical(as.double(data$x), c(8, 7, 8))
    set_dta_values(data, "x", lazy)
    expect_identical(touched, 1L)
    expect_identical(as.double(data$x), rep(4, 3))
    set_dta_values(data, "x", active)
    expect_identical(touched, 2L)
    expect_identical(as.double(data$x), rep(5, 3))
    # A previously forced promise is readable without re-running its body.
    forced <- function(value) { force(value); fast_values_probe(data, "x", value) }
    expect_identical(forced({ touched <- touched + 1L; 6 }), data)
    expect_identical(touched, 3L)
    expect_identical(as.double(data$x), rep(6, 3))
})

test_that("native scalar declines preserve diagnostics and unsupported inputs", {
    data <- dibble(x = c(1, 2, 3))
    for (rows in list(0, -1, 4, NA_real_, 1.5, c(TRUE, FALSE, TRUE))) {
        expect_null(fast_values_probe(data, "x", 9, rows))
    }
    expect_null(fast_values_probe(data, "x", c(1, 2, 3)))
    expect_null(fast_values_probe(data, "x", structure(2, class = "special")))
    expect_null(fast_values_probe(data, "x", 2, create = TRUE))
    expect_null(fast_values_probe(data, "missing", 2))
    expect_null(fast_values_probe(data, , 2))
    expect_identical(as.double(data$x), c(1, 2, 3))
    expect_error(set_dta_values(data, "x", 9, rows = 0), "`rows` row positions")
    expect_error(repl(data, , 0), "unquoted")
    expect_error(set_dta_values(data, "x", Inf), "NaN.*infinities")
    expect_identical(as.double(data$x), c(1, 2, 3))
    temporal <- dibble(x = as.Date("2020-01-01") + 0:2)
    expect_null(fast_values_probe(temporal, "x", 2))
    callbacks <- 0L
    foreign <- .Call(C_dtatools_callback_double, 7,
                     function() callbacks <<- callbacks + 1L, 1L)
    expect_null(fast_values_probe(data, "x", foreign))
    expect_identical(callbacks, 0L)
    set_dta_values(data, "x", foreign)
    expect_identical(callbacks, 1L)
    expect_identical(as.double(data$x), rep(7, 3))
})

test_that("scalar writes reuse private storage and isolate shared results", {
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float, dta_double)) {
        data <- dibble(anchor = 1:4)
        gen(data, x = constructor(c(1, 2, 3, 4)))
        alias <- data
        .Call(C_dtatools_native_copy_stats, TRUE)
        set_dta_values(data, "x", 9, rows = 2L)
        repl(data, x = 8, where = 3L)
        data[4L, x := 7]
        stats <- .Call(C_dtatools_native_copy_stats, FALSE)
        expect_identical(stats[["native_scratch_allocated"]], 0)
        expect_identical(stats[["mutation_target_copy"]], 0)
        expect_identical(as.double(alias$x), c(1, 9, 8, 7))
        other <- tibble::as_tibble(data)
        set_dta_values(data, "x", 6, rows = 1L)
        expect_identical(as.double(other$x), c(1, 9, 8, 7))
        expect_identical(as.double(alias$x), c(6, 9, 8, 7))
        .Call(C_dtatools_native_copy_stats, TRUE)
        set_dta_values(data, "x", 5)
        stats <- .Call(C_dtatools_native_copy_stats, FALSE)
        expect_identical(stats[["native_scratch_allocated"]], 0)
        expect_identical(stats[["mutation_target_copy"]], 0)
        expect_identical(as.double(other$x), c(1, 9, 8, 7))
        expect_identical(as.double(alias$x), rep(5, 4))
    }
})

test_that("scalar storage policy distinguishes fixed rounding and promotion", {
    data <- dibble(x = dta_float(c(1, 2, 3)))
    set_dta_values(data, "x", 16777217, rows = 1L)
    expect_identical(as.double(data$x), c(16777216, 2, 3))
    expect_identical(dta_storage_type(data$x), "float")
    expect_message(repl(data, x = 16777217, where = 2L), "float now double")
    expect_identical(as.double(data$x), c(16777216, 16777217, 3))
    expect_identical(dta_storage_type(data$x), "double")
    data <- dibble(x = dta_byte(c(1, 2, 3)))
    data[1L, x := 1000]
    expect_identical(dta_storage_type(data$x), "int")
    expect_identical(as.double(data$x), c(1000, 2, 3))
    empty <- integer()
    repl(data, x = NaN, where = !!empty)
    data[integer(), x := Inf]
    expect_error(set_dta_values(data, "x", NaN, rows = empty), "NaN")
    expect_identical(as.double(data$x), c(1000, 2, 3))
    tag <- tagged_missing("z")
    set_dta_values(data, "x", tag, rows = 3L)
    expect_identical(.stata_missing_text(.tab_missing_codes(data$x))[[3L]], ".z")
})

test_that("speculative scalar replacement leaves retained backing intact", {
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        data <- dibble(x = .Call(C_dtatools_owned_numeric_freeze,
                                constructor(c(1, 2, 3, 4)), 2))
        before <- .Call(C_dtatools_owned_numeric_info, data$x)
        expect_identical(before[["owned"]], 1)
        # A promoted assignment to no rows is a no-op even for invalid values.
        data[integer(), x := Inf]
        data[x > 10, x := 1000]
        after <- .Call(C_dtatools_owned_numeric_info, data$x)
        expect_identical(after[["owned"]], 1)
        expect_identical(after[["compatibility_bytes"]], before[["compatibility_bytes"]])
        # A failed speculative fit leaves conversion to the general path.
        expect_null(.Call(C_dtatools_patch_scalar, data, "x", 1L, Inf, TRUE))
        after <- .Call(C_dtatools_owned_numeric_info, data$x)
        expect_identical(after[["owned"]], 1)
        expect_identical(after[["compatibility_bytes"]], before[["compatibility_bytes"]])
        expect_identical(as.double(data$x), c(1, 2, 3, 4))
    }
})

test_that("direct generation retains storage defaults and one bracket selection", {
    for (storage in c("float", "double")) {
        withr::local_options(dtatools.generate_type = storage)
        data <- dibble(x = c(1, 2, 3))
        gen(data, y = 2, where = 2L)
        expect_identical(as.double(data$y), c(NA_real_, 2, NA_real_))
        expect_identical(dta_storage_type(data$y), storage)
        gen(data, z = 2L)
        expect_identical(dta_storage_type(data$z), "long")
        gen(data, flag = TRUE)
        expect_type(data$flag, "logical")
        counter <- new.env()
        counter$selected <- 0L
        data[{ counter$selected <- counter$selected + 1L; x < 3 }, `:=`(x = 9, a = 4, b = x + 1)]
        expect_identical(counter$selected, 1L)
        expect_identical(as.double(data$x), c(9, 9, 3))
        expect_identical(as.double(data$a), c(4, 4, NA_real_))
        expect_identical(dta_storage_type(data$a), storage)
        expect_identical(as.double(data$b), c(10, 10, NA_real_))
    }
})

test_that("fast shape preserves wide and malformed table checks", {
    data <- as_dibble(tibble::as_tibble(setNames(rep(list(c(1, 2, 3)), 100L), paste0("x", 1:100))))
    expect_identical(fast_values_probe(data, "x100", 7, rows = 2L), data)
    expect_identical(as.double(data$x100), c(1, 7, 3))
    bad <- data
    attr(bad, "names") <- rep("x", 100L)
    touched <- FALSE
    expect_error(set_dta_values(bad, "x", { touched <- TRUE; 2 }), "unique")
    expect_false(touched)
    large <- as_dibble(tibble::as_tibble(setNames(rep(list(c(1, 2)), 2050L), paste0("x", 1:2050))))
    expect_null(fast_values_probe(large, "x2050", 7))
    set_dta_values(large, "x2050", 7)
    expect_identical(as.double(large$x2050), c(7, 7))
})

test_that("native generation declines accepted attributed storage options safely", {
    for (storage in c("float", "double")) {
        withr::local_options(dtatools.generate_type = c(storage = storage))
        data <- dibble(x = c(1, 2, 3))
        gen(data, y = 2)
        data[2L, z := 4]
        set_dta_values(data, "w", 6, create = TRUE)
        expect_identical(as.double(data$y), rep(2, 3))
        expect_identical(as.double(data$z), c(NA_real_, 4, NA_real_))
        expect_identical(as.double(data$w), rep(6, 3))
        expect_identical(unname(dta_storage_type(data$y)), storage)
        expect_identical(unname(dta_storage_type(data$z)), storage)
        expect_identical(unname(dta_storage_type(data$w)), storage)
        expect_identical(.set_values_preflight(data), 3L)
    }
})

test_that("growth warning handlers run before direct generation reads bindings", {
    withr::local_options(dtatools.alloccol = 0L)
    for (selected in c(FALSE, TRUE)) {
        data <- dibble(x = c(1, 2, 3))
        row <- 1L
        value <- 2
        warnings <- 0L
        result <- withCallingHandlers(
            if (selected) gen(data, y = value, where = row) else gen(data, y = value),
            warning = function(w) {
                warnings <<- warnings + 1L
                row <<- 3L
                value <<- 8
                invokeRestart("muffleWarning")
            }
        )
        expect_identical(warnings, 1L)
        expect_identical(as.double(result$y), if (selected) c(NA_real_, NA_real_, 8) else rep(8, 3))
    }
})

test_that("invalid generation defaults still fail before appending a scalar", {
    for (storage in list("long", "int", NA_character_, 3, c("float", "double"))) {
        withr::local_options(dtatools.generate_type = storage)
        data <- dibble(x = c(1, 2, 3))
        expect_error(gen(data, y = 2), "dtatools.generate_type")
        expect_identical(names(data), "x")
        gen(data, y = 2L)
        expect_identical(dta_storage_type(data$y), "long")
    }
})

test_that("promote callbacks cannot change a declined scalar assignment", {
    for (promoting in c(FALSE, TRUE)) {
        data <- dibble(x = dta_byte(c(1, 2, 3)))
        value <- if (promoting) 1000 else 9
        row <- 1L
        calls <- 0L
        expect_message(repl(data, x = value, where = row, promote = {
            calls <- calls + 1L
            value <- 7
            row <- 3L
            TRUE
        }), if (promoting) "byte now int" else NA)
        expect_identical(calls, 1L)
        expect_identical(as.double(data$x), c(if (promoting) 1000 else 9, 2, 3))
        expect_identical(dta_storage_type(data$x), if (promoting) "int" else "byte")
    }
    data <- dibble(x = dta_byte(c(1, 2, 3)))
    value <- 1000
    row <- 1L
    delayedAssign("policy", { value <- 7; row <- 3L; TRUE })
    expect_message(repl(data, x = value, where = row, promote = policy), "byte now int")
    expect_identical(as.double(data$x), c(1000, 2, 3))
})

test_that("native promote inspection declines active and attributed flags", {
    peek <- function(promote = TRUE) .Call(C_dtatools_peek_promote, environment())
    expect_identical(peek(), TRUE)
    expect_identical(peek(FALSE), FALSE)
    expect_null(peek(structure(TRUE, label = "policy")))
    labelled <- structure(TRUE, label = "policy")
    expect_null(peek(labelled))
    touched <- 0L
    makeActiveBinding("active_policy", function() { touched <<- touched + 1L; TRUE }, environment())
    expect_null(peek(active_policy))
    expect_identical(touched, 0L)
    expect_null(peek({ touched <- touched + 1L; TRUE }))
    expect_identical(touched, 0L)
})
