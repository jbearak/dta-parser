# Stage 6 row-operation regression coverage; adapted sources are in inst/NOTICE.

test_that("S6-L06 row conditions preserve warning timing and error families", {
    data <- dibble(id = 1:2)
    flag <- new.env(parent = emptyenv())
    flag$value <- FALSE
    out <- withCallingHandlers(dplyr::slice(data,
        { warning("slice mark"); 1L }, if (flag$value) 2L else integer()),
        warning = function(condition) { flag$value <- TRUE; invokeRestart("muffleWarning") })
    expect_identical(.s6_ids(out), 1:2)
    flag$value <- FALSE
    out <- withCallingHandlers(dplyr::arrange(data,
        { warning("arrange mark"); 0L }, if (flag$value) -id else id),
        warning = function(condition) { flag$value <- TRUE; invokeRestart("muffleWarning") })
    expect_identical(.s6_ids(out), 2:1)
    flag$value <- FALSE
    out <- withCallingHandlers(dplyr::filter(data,
        { rlang::warn("user lifecycle", class = "lifecycle_warning_deprecated"); TRUE },
        !flag$value), warning = function(condition) {
            flag$value <- TRUE
            invokeRestart("muffleWarning")
        })
    expect_identical(.s6_ids(out), 1:2)
    expect_true(flag$value)
    for (operation in list(function(x) dplyr::filter(x, stop("filter failure")),
                           function(x) dplyr::slice(x, stop("slice failure")))) {
        condition <- tryCatch(operation(data), error = identity)
        expect_s3_class(condition, "error")
        expect_false(inherits(condition, "dplyr:::mutate_error"))
    }
    condition <- tryCatch(dplyr::mutate(data, x = stop("mutate failure")), error = identity)
    expect_s3_class(condition, "dplyr:::mutate_error")
})
# Based on test-dibble-rows.R/test-dibble-expressions.R; see inst/NOTICE.

.s6_row_operations <- function() list(
    filter = function(d) dplyr::filter(d, x >= 2),
    filter_out = function(d) dplyr::filter_out(d, x < 2),
    arrange = function(d) dplyr::arrange(d, x),
    distinct = function(d) dplyr::distinct(d, x, .keep_all = TRUE),
    slice = function(d) dplyr::slice(d, c(3L, 1L, 1L)),
    head = function(d) dplyr::slice_head(d, n = 2L),
    tail = function(d) dplyr::slice_tail(d, n = 2L),
    min = function(d) dplyr::slice_min(d, x, n = 2L),
    max = function(d) dplyr::slice_max(d, x, n = 2L),
    sample = function(d) dplyr::slice_sample(d, n = 3L, replace = TRUE,
        weight_by = c(1, 0, 0, 0)))

test_that("S6-L01 every row verb preserves metadata and symmetric later-write isolation", {
    withr::local_seed(5)
    for (operation in .s6_row_operations()) for (roundtrip in c(FALSE, TRUE)) {
        source <- dibble(id = 1:4, x = dta_double(c(4, 1, 3, 2)),
            flag = c(TRUE, FALSE, NA, TRUE),
            f = factor(c("a", "b", "a", "b"), levels = c("b", "a", "unused")))
        attr(source$x, "label") <- "Measured x"
        attr(source, "label") <- "Dataset label"
        add_dta_note(source, "dataset note")
        alias <- source
        standalone <- source$x
        result <- operation(source)
        expect_true(is_dibble(result))
        expect_identical(attr(result$x, "label"), "Measured x")
        expect_identical(attr(result, "label"), "Dataset label")
        expect_identical(dta_notes(result), dta_notes(source))
        expect_identical(levels(result$f), levels(source$f))
        expect_identical(class(result$x), class(source$x))
        expect_identical(result$flag, source$flag[.s6_ids(result)])
        pair <- list(source, result)
        if (roundtrip) pair <- unserialize(serialize(pair, NULL))
        source <- pair[[1L]]; result <- pair[[2L]]
        old_source <- as.double(source$x); old_result <- as.double(result$x)
        repl(source, x = 80, where = 1L)
        expect_identical(as.double(result$x), old_result)
        repl(result, x = 90, where = 1L)
        expect_identical(as.double(source$x), c(80, old_source[-1L]))
        # A live alias names the same explicitly mutable table. Serialization
        # creates a separate source; only that branch leaves the old alias alone.
        expect_identical(as.double(alias$x), if (roundtrip) c(4, 1, 3, 2) else c(80, 1, 3, 2))
        expect_identical(as.double(standalone), c(4, 1, 3, 2))
        result <- reserve_columns(result)
        gen(result, copied = x)
        expect_false("copied" %in% names(source))
    }
})

test_that("S6-L02 forced captures survive while late column resolution expires", {
    for (verb in c("filter", "filter_out", "slice", "arrange", "distinct")) {
        data <- dibble(id = 1:4, x = dta_double(c(4, 1, 3, 2)))
        captured <- NULL; closure <- NULL; pronoun <- NULL; quo <- NULL
        late <- new.env(parent = emptyenv())
        save_late <- function(value) delayedAssign("x", value,
            eval.env = environment(), assign.env = late)
        expression <- rlang::quo({
            captured <<- x
            closure <<- function() x
            pronoun <<- .data
            quo <<- rlang::quo(x)
            save_late(x)
            x
        })
        result <- switch(verb,
            filter = dplyr::filter(data, (!!expression) > 0),
            filter_out = dplyr::filter_out(data, (!!expression) < 0),
            slice = dplyr::slice(data, { !!expression; 1:4 }),
            arrange = dplyr::arrange(data, !!expression),
            distinct = dplyr::distinct(data, key = !!expression, .keep_all = TRUE))
        expect_identical(as.double(captured), c(4, 1, 3, 2))
        for (read in list(function() closure(), function() pronoun$x,
                         function() rlang::eval_tidy(quo), function() late$x)) {
            expect_error(suppressWarnings(read()), "Obsolete data mask")
        }
        repl(data, x = 80, where = 1L)
        repl(result, x = 90, where = 1L)
        expect_identical(as.double(captured), c(4, 1, 3, 2))
    }
    for (verb in c("filter", "slice")) {
        data <- dplyr::group_by(dibble(id = 1:3, g = c("b", "a", "b"),
                                     x = dta_double(c(10, 20, 30))), g)
        captured <- list(); closures <- list()
        expression <- rlang::quo({
            i <- dplyr::cur_group_id()
            captured[[i]] <<- x
            closures[[i]] <<- function() x
            if (i > 1L) expect_identical(as.double(captured[[1L]]), 20)
            if (verb == "filter") TRUE else seq_len(dplyr::n())
        })
        out <- if (verb == "filter") dplyr::filter(data, !!expression) else
            dplyr::slice(data, !!expression)
        expect_identical(.s6_ids(out), if (verb == "filter") 1:3 else c(2L, 1L, 3L))
        expect_identical(lapply(captured, as.double), list(20, c(10, 30)))
        for (closure in closures) expect_error(suppressWarnings(closure()), "Obsolete data mask")
        repl(data, x = 80, where = 1L)
        repl(out, x = 90, where = 1L)
        expect_identical(lapply(captured, as.double), list(20, c(10, 30)))
    }
})

test_that("S6-L03 nested row verbs restore outer context after success and error", {
    data <- dplyr::group_by(dibble(id = 1:4, g = c("b", "a", "b", "a")), g)
    seen <- list()
    out <- dplyr::filter(data, {
        before <- .s6_context()
        inner <- dplyr::slice(dibble(id = 1:3), 1L)
        expect_identical(.s6_ids(inner), 1L)
        expect_error(dplyr::filter(dibble(id = 1:2), stop("inner failed")), "inner failed")
        expect_identical(.s6_context(), before)
        seen[[length(seen) + 1L]] <<- before
        TRUE
    })
    expect_identical(.s6_ids(out), 1:4)
    expect_identical(lapply(seen, `[[`, "rows"), list(c(2L, 4L), c(1L, 3L)))
    expect_error(dplyr::n(), "Must only be used")
    expect_error(dplyr::filter(data, stop("outer failed")), "outer failed")
    expect_error(dplyr::n(), "Must only be used")
    expect_identical(.s6_ids(dplyr::filter(data, TRUE)), 1:4)
})

test_that("S6-L04 plain reference-marked frame fallback preserves its container policy", {
    withr::local_seed(7)
    for (tibble in c(FALSE, TRUE)) for (operation in .s6_row_operations()) {
        source <- data.frame(id = 1:4, x = c(4, 1, 3, 2))
        if (tibble) source <- tibble::as_tibble(source)
        source <- reserve_columns(source)
        gen(source, staged = x)
        expect_s3_class(source, "dtatools_ref_data")
        expect_false(is_dibble(source))
        plain <- dtatools:::.reference_snapshot(source)
        set.seed(7)
        expected <- operation(plain)
        set.seed(7)
        actual <- operation(source)
        expect_identical(.s6_plain(actual), expected)
        expect_false(is_dibble(actual))
    }
})

test_that("S6-L05 foreign data.table input cannot mutate a gathered dibble result", {
    skip_if_not_installed("data.table", minimum_version = "1.18.2.1")
    for (operation in list(function(d) dplyr::filter(d, x > 1),
                          function(d) dplyr::arrange(d, x),
                          function(d) dplyr::slice(d, c(3L, 1L, 1L)))) {
        foreign <- data.table::data.table(id = 1:3, x = dta_double(c(3, 1, 2)))
        source <- as_dibble(foreign)
        result <- operation(source)
        before <- as.double(result$x)
        data.table::set(foreign, i = 1L, j = "x", value = 70)
        expect_identical(as.double(foreign$x), c(70, 1, 2))
        expect_identical(as.double(result$x), before)
        expect_identical(as.double(source$x), c(3, 1, 2))
        repl(result, x = 99, where = 1L)
        expect_identical(as.double(foreign$x), c(70, 1, 2))
    }
})
