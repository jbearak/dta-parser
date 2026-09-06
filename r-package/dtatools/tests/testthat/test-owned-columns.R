owned_info <- function(value) .Call(C_dtatools_owned_info, value)
mutation_info <- function(data, location) .Call(C_dtatools_mutation_info, data, as.integer(location))

test_that("bounded generation shape checks retain wide and encoded fallbacks", {
    for (count in c(2047L, 2048L, 2049L)) {
        data <- structure(rep(list(1L), count), names = sprintf("v%04d", seq_len(count)),
                          class = "data.frame", row.names = c(NA_integer_, -1L))
        data <- reserve_columns(data, n = 1L)
        expect_identical(.Call(C_dtatools_mutation_shape, data, 1L), count <= 2048L)
        gen(data, added, 9L)
        expect_identical(names(data)[[count + 1L]], "added")
        expect_identical(as.integer(data$added), 9L)
        expect_identical(data[[count]], 1L)
    }
    latin <- iconv("\u00e9", from = "UTF-8", to = "latin1")
    data <- structure(list(1L, 2L), names = c(latin, "\u00e9"),
                      class = "data.frame", row.names = c(NA_integer_, -1L))
    expect_false(.Call(C_dtatools_mutation_shape, data, 1L))
    expect_error(gen(data, added, 9L), "unique, non-missing column names")
    names(data) <- c(latin, "other")
    data <- reserve_columns(data, n = 1L)
    gen(data, added, 9L)
    expect_identical(as.integer(data$added), 9L)
})

test_that("generation shape checks decline foreign length callbacks", {
    calls <- 0L
    column <- .Call(C_dtatools_callback_integer, c(1L, 2L, 3L), function() calls <<- calls + 1L)
    data <- structure(list(x = column), class = "data.frame", row.names = c(NA_integer_, -3L))
    expect_false(.Call(C_dtatools_mutation_shape, data, 3L))
    expect_identical(calls, 0L)
})

test_that("generation shape validation never invokes foreign class callbacks", {
    calls <- 0L
    classes <- .Call(C_dtatools_callback_character, "Date", function() NULL)
    column <- c(1, 2, 3)
    attr(column, "class") <- classes
    data <- reserve_columns(data.frame(x = c(1, 2, 3)), n = 1L)
    .Call(C_dtatools_set_data_column, data, 1L, column)
    .Call(C_dtatools_arm_callback_character, classes, function() {
        calls <<- calls + 1L
        stop("foreign class callback")
    })
    expect_false(.Call(C_dtatools_mutation_shape, data, 3L))
    expect_identical(calls, 0L)
    expect_error(gen(data, added, 9L), "foreign class callback")
    expect_identical(names(data), "x")
})

test_that("attributed env members retain ordinary evaluation without eligibility callbacks", {
    calls <- 0L
    data <- reserve_columns(data.frame(x = c(1L, 2L, 3L)), n = 1L)
    rhs <- 7L
    member <- structure("rhs", class = "owned_test_member")
    rlang::local_bindings(
        as.character.owned_test_member = function(x, ...) {
            calls <<- calls + 1L
            .Call(C_dtatools_set_attribute, data, "names", "added")
            "rhs"
        },
        length.owned_test_member = function(x) {
            calls <<- calls + 1L
            stop("member eligibility dispatched length")
        }, .env = globalenv())
    gen(data, added, .env[[!!member]])
    expect_identical(calls, 0L)
    expect_identical(names(data), c("x", "added"))
    expect_identical(as.integer(data$added), rep(7L, 3L))
    replace_values(data, x, .env[[!!member]])
    expect_identical(calls, 0L)
    expect_identical(as.integer(data$x), rep(7L, 3L))
})

test_that("journaled append restores shape and metadata after errors and interrupts", {
    withr::defer(.Call(C_dtatools_inject_column_append_failure, 0L, FALSE))
    for (constructor in list(identity, tibble::as_tibble, as_dibble)) {
        for (shared in c(FALSE, TRUE)) for (stage in 1:3) for (interrupt in c(FALSE, TRUE)) {
            fixture <- function() reserve_columns(constructor(data.frame(x = 1:3)), n = 3L)
            control <- fixture()
            expected_order <- names(attributes(control))
            data <- fixture()
            state <- .reference_state(data)
            original <- if (shared) attributes(data) else NULL
            alias <- data
            before_names <- .Call(C_dtatools_column_names_info, data)
            expect_identical(before_names[[2L]], shared)
            .Call(C_dtatools_inject_column_append_failure, stage, interrupt)
            error <- tryCatch({
                if (interrupt) .Call(C_dtatools_append_data_column, data, "added", c(9L, 9L, 9L)) else
                    gen(data, added, 9L)
                NULL
            }, interrupt = identity, error = identity)
            expect_identical(.Call(C_dtatools_column_names_info, data), before_names)
            expect_s3_class(error, if (interrupt) "interrupt" else "error")
            if (!interrupt) expect_match(conditionMessage(error), "injected column append failure")
            expect_identical(names(data), "x")
            expect_identical(length(data), 1L)
            expect_identical(dim(data), c(3L, 1L))
            expect_identical(as.integer(alias$x), 1:3)
            expect_identical(names(attributes(data)), expected_order)
            expect_identical(.reference_state(data), state)
            if (shared) expect_identical(attributes(data), original)
            gen(data, retry, 8L)
            gen(data, second, 7L)
            expect_identical(names(alias), c("x", "retry", "second"))
            expect_identical(as.integer(data$retry), rep(8L, 3L))
        }
    }
})

test_that("classed column names retain R validation dispatch", {
    reject <- FALSE
    calls <- 0L
    rlang::local_bindings(anyNA.owned_test_names = function(x, recursive = FALSE) {
        calls <<- calls + 1L
        if (reject) stop("classed names validation")
        FALSE
    }, .env = globalenv())
    data <- structure(list(1L), names = structure("x", class = "owned_test_names"),
                      class = "data.frame", row.names = c(NA_integer_, -1L))
    data <- reserve_columns(data, n = 1L)
    expect_false(.Call(C_dtatools_mutation_shape, data, 1L))
    calls <- 0L
    reject <- TRUE
    expect_error(gen(data, added, 9L), "classed names validation")
    expect_identical(calls, 1L)
    expect_identical(as.character(names(data)), "x")
})

test_that("private append reuses names without a collection or prior names read", {
    for (constructor in list(identity, tibble::as_tibble, as_dibble)) for (empty in c(FALSE, TRUE)) {
        data <- reserve_columns(constructor(if (empty) data.frame(row.names = 1:3) else
            data.frame(x = 1:3)), n = 10L)
        before <- .Call(C_dtatools_column_names_info, data)
        expect_false(before[[2L]])
        for (i in 1:10) {
            name <- rlang::sym(paste0("added", i))
            gen(data, !!name, i)
            after <- .Call(C_dtatools_column_names_info, data)
            expect_identical(after[[1L]], before[[1L]])
            expect_false(after[[2L]])
            expect_identical(after[[3L]], before[[3L]] + i)
        }
        expect_identical(names(data), c(if (!empty) "x", paste0("added", 1:10)))
    }
})

test_that("generation preserves saved names, attributes and shallow table copies", {
    constructors <- list(identity, tibble::as_tibble, as_dibble)
    for (constructor in constructors) {
        data <- reserve_columns(constructor(data.frame(x = 1:3)), n = 3L)
        saved_names <- names(data)
        saved_attributes <- attributes(data)
        copied <- data
        attr(copied, "source") <- "copy"
        gen(data, added, 9L)
        expect_identical(names(data), c("x", "added"))
        expect_identical(saved_names, "x")
        expect_identical(saved_attributes$names, "x")
        expect_identical(names(copied), "x")
        escaped <- NULL
        makeActiveBinding("capture_names", function() {
            escaped <<- names(data)
            8L
        }, environment())
        gen(data, callback, capture_names)
        rm(capture_names)
        gen(data, last, 7L)
        expect_identical(escaped, c("x", "added"))
        expect_identical(names(data), c("x", "added", "callback", "last"))
        expect_identical(names(copied), "x")
    }
})

test_that("generation protects shallow table names before any public names read", {
    for (copy in list(function(data) { attr(data, "note") <- "copy"; data },
                      function(data) .Call(C_dtatools_metadata_copy, data),
                      function(data) unclass(data))) {
        data <- reserve_columns(data.frame(x = 1L), n = 2L)
        other <- copy(data)
        gen(data, added, 9L)
        gen(data, last, 8L)
        expect_identical(names(other), "x")
        expect_identical(names(data), c("x", "added", "last"))
        expect_identical(other[[1L]], 1L)
    }
})

test_that("generation checks physical rows again after argument capture", {
    data <- reserve_columns(data.frame(x = 1:3), n = 1L)
    expect_error(gen(data, !!{
        .Call(C_dtatools_set_data_column, data, 1L, 1:4)
        rlang::sym("added")
    }, 9L), "inconsistent row counts")
    expect_identical(names(data), "x")
    expect_identical(data$x, 1:4)
})

test_that("captured mutation masks preserve unread columns and lexical lookup", {
    for (constructor in list(dta_double, dta_byte)) {
        for (capture in c("closure", "environment", "helper", "promise", "pronoun")) {
            for (site in c("values", "where", "gen")) {
                for (outcome in c("success", "empty", "error")) {
                    data <- reserve_columns(data.frame(anchor = 1:3))
                    gen(data, x, constructor(c(1, 2, 3)))
                    saved <- NULL
                    delayed <- new.env(parent = emptyenv())
                    offset <- 0
                    helper <- function() { saved <<- parent.frame(); 9 }
                    capture_expression <- switch(capture,
                        closure = quote(saved <<- function() x + offset),
                        environment = quote(saved <<- environment()),
                        helper = quote(helper()),
                        promise = quote(delayedAssign("x", x, eval.env = environment(), assign.env = delayed)),
                        pronoun = quote(saved <<- function() .data$x + offset))
                    tail_expression <- if (outcome == "error") quote(stop("captured mask stopped")) else
                        if (site == "where") if (outcome == "empty") quote(integer()) else quote(2L) else quote(9)
                    expression <- as.call(list(quote(`{`), capture_expression, tail_expression))
                    invocation <- if (site == "gen") {
                        substitute(gen(data, added, VALUE), list(VALUE = expression))
                    } else if (site == "where") {
                        substitute(replace_values(data, x, 9, where = WHERE), list(WHERE = expression))
                    } else {
                        substitute(replace_values(data, x, VALUE, where = ROWS),
                                   list(VALUE = expression, ROWS = if (outcome == "empty") integer() else 2L))
                    }
                    if (outcome == "error") expect_error(eval(invocation), "captured mask stopped") else eval(invocation)
                    read <- function() switch(capture,
                        closure = saved(), environment = evalq(x, saved), helper = evalq(x, saved),
                        promise = delayed$x, pronoun = saved())
                    expect_identical(as.double(read()), c(1, 2, 3))
                    replace_values(data, x, 7, where = 1L)
                    expect_identical(as.double(read()), c(1, 2, 3))
                }
            }
        }
    }
})

test_that("direct reads retain shadow checks and dynamic env subscripts", {
    outside_value <- 9
    data <- dibble(x = dta_double(1), lookup = "outside_value")
    replace_values(data, x, .env[[lookup]])
    expect_identical(as.double(data$x), 9)
    x <- 8
    expect_error(replace_values(data, x, x), "both a column and an object")
})

test_that("plain table staging guards aliases introduced by row callbacks", {
    for (values in list(c(1L, 2L, 3L), c(TRUE, FALSE, TRUE), c("a", "b", "c"))) {
        data <- data.frame(x = values)
        .Call(C_dtatools_patch_slot, data, 1L, 1L, values[1L], TRUE)
        expect_false(mutation_info(data, 1L)$handle_shared)
        escaped <- NULL
        rows <- .Call(C_dtatools_callback_integer, c(2L, 3L), function() {
            escaped <<- data$x
            gc()
        })
        replacement <- values[1L]
        .Call(C_dtatools_patch_slot, data, 1L, rows, replacement, FALSE)
        expect_identical(escaped, values)
        expect_identical(data$x, rep(values[1L], 3L))
    }
})

test_that("ordinary private string writes retain sparse allocation and snapshot isolation", {
    data <- reserve_columns(data.frame(anchor = seq_len(100000L)))
    gen(data, text, "")
    address <- mutation_info(data, 2L)$handle
    for (iteration in 1:3) {
        replace_values(data, text, "x", where = 100000L)
        expect_identical(mutation_info(data, 2L)$handle, address)
    }
    saved <- NULL
    replace_values(data, text, { saved <<- function() text; "y" }, where = 100000L)
    expect_identical(saved()[100000L], "x")
    expect_identical(data$text[100000L], "y")
})

test_that("promotion checks revalidate rows changed by a value callback", {
    rows <- .metadata_copy(c(1, 2))
    values <- .Call(C_dtatools_callback_double, c(1, 1, 999), function() {
        pointer <- .Call(C_dtatools_owned_pointer, rows, TRUE)
        .Call(C_dtatools_owned_pointer_write, pointer, 2L, 4)
    }, TRUE)
    expect_error(.Call(C_dtatools_replacement_fits, values, rows, TRUE, 0L),
                 "invalid reference mutation row")
    expect_identical(as.double(rows), c(1, 4))
})

test_that("generic table transactions reject callback target replacement", {
    data <- data.frame(x = dta_float(c(1, 2, 3)))
    .force_altrep_materialization(data$x)
    values <- .Call(C_dtatools_callback_integer, c(9L, 9L), function() {
        .Call(C_dtatools_set_data_column, data, 1L, c(6, 6, 6))
        gc()
    })
    expect_error(.Call(C_dtatools_patch_slot, data, 1L, c(2L, 3L), values, FALSE),
                 "target changed while preparing replacement")
    expect_identical(data$x, c(6, 6, 6))
})

test_that("native promotion fits preserve ranges, precision and selected values", {
    values <- c(-2147483648, -32768, -128, -127, 0, 100, 101, 32740,
                32741, 2147483620, 2147483621, 0.1, 0.5, 2^24 + 1,
                .dta_float_max, .Machine$double.xmax / 2, Inf, NaN,
                NA_real_, tagged_missing("a"), tagged_missing("z"))
    for (storage in .dta_storage) {
        kind <- match(storage, .dta_storage) - 1L
        for (value in as.list(values)) {
            expected <- .dta_storage_holds(value, storage)
            expect_identical(.Call(C_dtatools_replacement_fits, value, NULL, FALSE, kind), expected)
        }
        expect_identical(.Call(C_dtatools_replacement_fits, values, c(4L, 5L, 6L, 19L, 20L), TRUE, kind), TRUE)
    }
    data <- dibble(x = dta_byte(c(1, 2)))
    replace_values(data, x, c(0.1, 100), where = 2L)
    expect_identical(dta_storage_type(data$x), "byte")
    replace_values(data, x, 0.1, where = 1L)
    expect_identical(dta_storage_type(data$x), "double")
    expect_identical(as.double(data$x), c(0.1, 100))
    expect_null(.Call(C_dtatools_replacement_fits,
                     structure(c(1, 2), class = "unfamiliar_number"), NULL, FALSE, 0L))
})

test_that("grouped proxy callbacks retain isolated Date inputs", {
    data <- data.frame(x = as.Date(c(1, 2, 3, 4), origin = "1970-01-01"),
                       g = c(1L, 1L, 2L, 2L))
    replace_values(data, x, as.Date(1, origin = "1970-01-01"), where = 1L)
    expect_true(mutation_info(data, 1L)$backing_private)
    escaped <- list()
    expected <- list()
    original_proxy <- getS3method("vec_proxy", "Date", envir = asNamespace("vctrs"))
    withr::defer(registerS3method("vec_proxy", "Date", original_proxy,
                                envir = asNamespace("vctrs")))
    registerS3method("vec_proxy", "Date", function(x, ...) {
        copy <- unclass(.deep_copy_value(x))
        if (length(x) == 4L) {
            escaped[[length(escaped) + 1L]] <<- x
            expected[[length(expected) + 1L]] <<-
                unserialize(serialize(as.double(.deep_copy_value(x)), NULL))
        }
        copy
    }, envir = asNamespace("vctrs"))
    replace_values(data, x, as.Date(9, origin = "1970-01-01"),
                   where = x > as.Date(0, origin = "1970-01-01"), by = g)
    expect_gt(length(escaped), 0L)
    expect_identical(lapply(escaped, as.double), expected)
    expect_identical(as.double(data$x), c(9, 9, 9, 9))
})

test_that("owned subsetting roots the payload across foreign index callbacks", {
    source <- .metadata_copy(c(1, 2, 3))
    temporary <- .metadata_copy(source)
    rm(temporary)
    gc()
    invoked <- FALSE
    index <- .Call(C_dtatools_callback_integer, c(1L, 2L, 3L), function() {
        invoked <<- TRUE
        pointer <- .Call(C_dtatools_owned_pointer, source, TRUE)
        .Call(C_dtatools_owned_pointer_write, pointer, 2L, 9)
        gc()
        lapply(seq_len(10000L), function(i) c(11, 12, 13))
        invisible(NULL)
    })
    result <- source[index]
    expect_true(invoked)
    expect_identical(as.double(source), c(1, 9, 3))
    expect_identical(as.double(result), c(1, 2, 3))
})

test_that("compact subsetting retains storage across index materialization callbacks", {
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        for (proxy in c(FALSE, TRUE)) {
            source <- constructor(c(1, 2, 3))
            if (proxy) source <- .metadata_copy(source)
            invoked <- FALSE
            index <- .Call(C_dtatools_callback_integer, c(1L, 2L, 3L), function() {
                invoked <<- TRUE
                .force_altrep_materialization(source)
                gc()
                lapply(seq_len(10000L), function(i) raw(12))
                invisible(NULL)
            })
            result <- source[index]
            expect_true(invoked)
            expect_identical(as.double(result), c(1, 2, 3))
            expect_identical(as.double(source), c(1, 2, 3))
        }
    }
})

test_that("native readers cannot export aliases after the effective write guard", {
    for (mode in c("fused_public", "fused_private", "staged_public", "staged_private")) {
        data <- reserve_columns(data.frame(anchor = 1:3))
        gen(data, x, dta_byte(c(1, 2, 3)))
        expect_false(mutation_info(data, 2L)$handle_shared)
        escaped <- NULL
        staged <- startsWith(mode, "staged")
        values <- .Call(C_dtatools_callback_double, c(9, 9, 9),
            function() escaped <<- data$x, staged)
        if (identical(mode, "fused_public")) {
            replace_values(data, x, .env$values, where = x > 1)
        } else if (identical(mode, "fused_private")) {
            columns <- .Call(C_dtatools_mutation_views, data)
            .Call(C_dtatools_fused_patch_slot, data, 2L, FALSE,
                  4L, columns[[2L]], NULL, c(1, 0), values, NULL, 1L)
        } else if (identical(mode, "staged_public")) {
            replace_values(data, x, .env$values, where = c(2L, 3L))
        } else {
            .Call(C_dtatools_patch_slot, data, 2L, c(2L, 3L), values, FALSE)
        }
        expect_false(is.null(escaped), info = mode)
        expect_identical(as.double(escaped), c(1, 2, 3), info = mode)
        expect_identical(as.double(data$x), c(1, 9, 9), info = mode)
        replace_values(data, x, 7, where = 1L)
        expect_identical(as.double(escaped), c(1, 2, 3), info = mode)
    }
})

test_that("failed fused writes retain sharing introduced by an operand callback", {
    for (mode in c("no_match", "callback_error", "callback_interrupt", "write_interrupt")) {
        data <- reserve_columns(data.frame(anchor = 1:3))
        gen(data, x, dta_byte(c(1, 2, 3)))
        before <- mutation_info(data, 2L)
        expect_false(before$handle_shared)
        expect_true(before$backing_private)
        escaped <- NULL
        values <- .Call(C_dtatools_callback_double, c(9, 9, 9), function() {
            escaped <<- .metadata_copy(data$x)
            if (identical(mode, "callback_error")) stop("operand callback stopped")
            if (identical(mode, "callback_interrupt")) rlang::interrupt()
        }, FALSE)
        columns <- .Call(C_dtatools_mutation_views, data)
        .Call(C_dtatools_native_copy_stats, TRUE)
        .inject_reference_write_interrupt(identical(mode, "write_interrupt"))
        condition <- tryCatch({
            .Call(C_dtatools_fused_patch_slot, data, 2L, FALSE,
                  4L, columns[[2L]], NULL,
                  c(if (identical(mode, "no_match")) 100 else 1, 0),
                  values, NULL, 1L)
            NULL
        }, condition = identity)
        .inject_reference_write_interrupt(FALSE)
        stats <- .Call(C_dtatools_native_copy_stats, FALSE)
        after <- mutation_info(data, 2L)
        if (identical(mode, "no_match")) expect_null(condition)
        if (identical(mode, "callback_error")) expect_match(conditionMessage(condition), "operand callback stopped")
        if (endsWith(mode, "interrupt")) expect_s3_class(condition, "interrupt")
        if (identical(mode, "write_interrupt")) expect_gt(stats[["old_journal"]], 0)
        expect_identical(after$handle, before$handle)
        expect_identical(after$backing, before$backing)
        expect_false(after$backing_private)
        expect_identical(as.double(data$x), c(1, 2, 3))
        expect_identical(as.double(escaped), c(1, 2, 3))
        replace_values(data, x, 7, where = 2L)
        expect_identical(as.double(data$x), c(1, 7, 3))
        expect_identical(as.double(escaped), c(1, 2, 3))
    }
})

test_that("direct owned writes retain callback forks after an interrupt", {
    for (pre_shared in c(FALSE, TRUE)) {
        data <- reserve_columns(data.frame(anchor = 1:3))
        gen(data, x, dta_double(c(1, 2, 3)))
        source <- data$x
        if (pre_shared) historical <- .metadata_copy(source)
        escaped <- NULL
        values <- .Call(C_dtatools_callback_double, c(9, 9, 9), function() {
            escaped <<- .metadata_copy(source)
        }, TRUE)
        .inject_reference_write_interrupt(TRUE)
        condition <- tryCatch(.Call(C_dtatools_patch_vector, source,
                                    c(1L, 2L, 3L), values), condition = identity)
        .inject_reference_write_interrupt(FALSE)
        expect_s3_class(condition, "interrupt")
        # Inspect claims before coercion: coercion itself could mark sharing
        # and conceal a rollback that incorrectly restored a private claim.
        expect_true(owned_info(source)$shared)
        pointer <- .Call(C_dtatools_owned_pointer, source, TRUE)
        .Call(C_dtatools_owned_pointer_write, pointer, 2L, 88)
        expect_identical(as.double(source), c(1, 88, 3))
        expect_identical(as.double(escaped), c(1, 2, 3))
        if (pre_shared) expect_identical(as.double(historical), c(1, 2, 3))
    }
})

test_that("materialized partial writes roll back completed writes and original state", {
    source <- dta_float(c(1, NA_real_, 3, 4))
    .force_altrep_materialization(source)
    data <- data.frame(x = source)
    before <- mutation_info(data, 1L)
    .Call(C_dtatools_native_copy_stats, TRUE)
    .inject_reference_write_interrupt(TRUE)
    # The table helper can discard a detached working column. Call the actual
    # rollback seam here so the interrupt follows writes to a journaled target.
    condition <- tryCatch(.Call(C_dtatools_patch_vector, source, c(2L, 4L), 9), condition = identity)
    .inject_reference_write_interrupt(FALSE)
    stats <- .Call(C_dtatools_native_copy_stats, FALSE)
    after <- mutation_info(data, 1L)
    expect_s3_class(condition, "interrupt")
    expect_gt(stats[["old_journal"]], 0)
    expect_identical(after, before)
    expect_identical(as.double(data$x), c(1, NA_real_, 3, 4))
    expect_identical(as.double(source), c(1, NA_real_, 3, 4))
    .inject_reference_write_interrupt(TRUE)
    condition <- tryCatch(replace_values(data, x, 9, where = c(2L, 4L)), condition = identity)
    .inject_reference_write_interrupt(FALSE)
    expect_s3_class(condition, "interrupt")
    expect_identical(mutation_info(data, 1L), before)
    expect_identical(as.double(data$x), c(1, NA_real_, 3, 4))
    expect_identical(as.double(source), c(1, NA_real_, 3, 4))
    replace_values(data, x, 7, where = 2L)
    expect_identical(as.double(data$x), c(1, 7, 3, 4))
    expect_identical(as.double(source), c(1, NA_real_, 3, 4))
})

test_that("plain doubles capture once and preserve private sparse backing afterwards", {
    source <- rep(1, 1000L)
    data <- data.frame(x = source)
    .Call(C_dtatools_native_copy_stats, TRUE)
    replace_values(data, x, 2, where = 1L)
    capture <- .Call(C_dtatools_native_copy_stats, FALSE)
    expect_identical(capture[["mutation_target_copy"]], 8000)
    expect_identical(source, rep(1, 1000L))
    for (i in 1:3) {
        before <- mutation_info(data, 1L)
        expect_true(before$backing_private)
        expect_false(before$handle_shared)
        .Call(C_dtatools_native_copy_stats, TRUE)
        replace_values(data, x, 3, where = 2L)
        after <- mutation_info(data, 1L)
        stats <- .Call(C_dtatools_native_copy_stats, FALSE)
        expect_identical(stats[["mutation_target_copy"]], 0)
        expect_identical(stats[["old_journal"]], 0)
        expect_identical(after$backing, before$backing)
        expect_identical(after$handle, before$handle)
    }
    expect_null(attr(data$x, "class"))
    expect_identical(as.double(data$x), c(2, 3, rep(1, 998L)))
})

test_that("materialized full replacement copies new values without reading old payloads", {
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        source <- constructor(c(1, 2, NA_real_, 4))
        .force_altrep_materialization(source)
        data <- data.frame(x = source)
        .Call(C_dtatools_native_copy_stats, TRUE)
        replace_values(data, x, c(7, 8, 9, 10))
        stats <- .Call(C_dtatools_native_copy_stats, FALSE)
        expect_identical(stats[["old_journal"]], 0)
        expect_identical(stats[["mutation_target_copy"]], 0)
        expect_identical(as.double(source), c(1, 2, NA_real_, 4))
        expect_true(.is_materialized_numeric_altrep(data$x))
        expect_identical(as.double(data$x), c(7, 8, 9, 10))
    }
})

test_that("native-generated private numeric writes stage new bytes without copying old values", {
    for (constructor in list(dta_double, dta_byte, dta_int, dta_long, dta_float)) {
        data <- reserve_columns(data.frame(anchor = 1:4))
        gen(data, x, constructor(c(1, 2, 3, 4)))
        before <- mutation_info(data, 2L)
        expect_false(before$handle_shared)
        expect_true(before$backing_private)
        .Call(C_dtatools_native_copy_stats, TRUE)
        replace_values(data, x, 9, where = 2L)
        replace_values(data, x, NA_real_, where = 3L)
        replace_values(data, x, 7)
        after <- mutation_info(data, 2L)
        stats <- .Call(C_dtatools_native_copy_stats, FALSE)
        expect_identical(after$handle, before$handle)
        expect_identical(after$backing, before$backing)
        expect_false(after$handle_shared)
        expect_true(after$backing_private)
        expect_identical(unname(stats[c("owned_capture", "compact_copy", "old_journal")]), c(0, 0, 0))
        expect_gt(stats[["staged_new"]], 0)
        expect_identical(as.double(data$x), rep(7, 4))
        expect_false(anyNA(data$x))
    }
})

test_that("full numeric replacement protects borrowed aliases without copying their old payload", {
    for (constructor in list(dta_double, dta_byte, dta_int, dta_long, dta_float)) {
        source <- constructor(c(1, 2, NA_real_, 4))
        data <- data.frame(x = source)
        expect_true(mutation_info(data, 1L)$handle_shared)
        .Call(C_dtatools_native_copy_stats, TRUE)
        replace_values(data, x, 7)
        stats <- .Call(C_dtatools_native_copy_stats, FALSE)
        expect_identical(unname(stats[c("owned_capture", "compact_copy", "old_journal")]), c(0, 0, 0))
        expect_identical(as.double(source), c(1, 2, NA_real_, 4))
        expect_identical(as.double(data$x), rep(7, 4))
    }
})

test_that("validation never exposes an internal read handle to R methods", {
    for (constructor in list(dta_double, dta_byte)) {
        data <- reserve_columns(data.frame(anchor = 1:2))
        gen(data, x, constructor(c(1, 2)))
        expect_false(.Call(C_dtatools_shared_columns, data)[[2L]])
        escaped <- list()
        capture_length <- function(x) {
            escaped[[length(escaped) + 1L]] <<- x
            NextMethod()
        }
        capture_dim <- function(x) {
            escaped[[length(escaped) + 1L]] <<- x
            NULL
        }
        rlang::local_bindings(length.dta_numeric = capture_length,
                             dim.dta_numeric = capture_dim, .env = globalenv())
        replace_values(data, x, 11, where = 1L)
        replace_values(data, x, 12, where = x == 2)
        # Inspect after removing methods, so this test does not itself export
        # a new alias while assessing the captured pre-write handles.
        rm(length.dta_numeric, dim.dta_numeric, envir = globalenv())
        captured <- Filter(function(x) length(x) == 2L, lapply(escaped, as.double))
        expect_length(captured, 0L)
        expect_identical(as.double(data$x), c(11, 12))
    }
})

test_that("custom classes on owned handles use conservative shape validation", {
    data <- reserve_columns(data.frame(anchor = 1:2))
    gen(data, x, dta_double(c(1, 2)))
    class(data$x) <- c("owned_custom", class(data$x))
    escaped <- list()
    expected <- list()
    rlang::local_bindings(length.owned_custom = function(x) {
        escaped[[length(escaped) + 1L]] <<- x
        expected[[length(expected) + 1L]] <<- .Call(C_dtatools_deep_copy_value, x)
        NextMethod()
    }, .env = globalenv())
    replace_values(data, x, 11, where = 1L)
    rm(length.owned_custom, envir = globalenv())
    expect_gt(length(escaped), 0L)
    # Methods also receive one-element replacement prototypes. Preserve the
    # fixed c(1,2) target invariant and check every other captured argument too.
    actual <- lapply(escaped, as.double)
    expected <- lapply(expected, as.double)
    targets <- lengths(expected) == 2L
    expect_true(any(targets))
    expect_true(all(vapply(expected[targets], identical, logical(1), c(1, 2))))
    expect_true(all(vapply(actual[targets], identical, logical(1), c(1, 2))))
    expect_identical(actual, expected)
    expect_identical(as.double(data$x), c(11, 2))
})

test_that("comparison callbacks cannot retain a view changed by the patch", {
    data <- reserve_columns(data.frame(anchor = 1:2))
    gen(data, x, dta_double(c(1, 2)))
    escaped <- list()
    expected <- list()
    rlang::local_bindings(length.dta_numeric = function(x) {
        escaped[[length(escaped) + 1L]] <<- x
        expected[[length(expected) + 1L]] <<- .Call(C_dtatools_deep_copy_value, x)
        NextMethod()
    }, .env = globalenv())
    replace_values(data, x, 12, where = x == 2)
    rm(length.dta_numeric, envir = globalenv())
    # This exact assertion fails on the pre-fix development build: four
    # expected c(1,2) arguments become c(1,12). Native snapshots leave the
    # captured handles' claims unchanged; all arguments are checked after writes.
    expect_identical(lapply(escaped, as.double), lapply(expected, as.double))
    expect_identical(as.double(data$x), c(1, 12))
})

test_that("native comparison decline isolates handles before R fallback errors", {
    data <- reserve_columns(data.frame(anchor = 1:2))
    gen(data, x, dta_double(c(1, 2)))
    pointer <- .Call(C_dtatools_owned_pointer, data$x, TRUE)
    .Call(C_dtatools_owned_pointer_write, pointer, 1L, NaN)
    expect_null(.Call(C_dtatools_dta_compare, 0L, data$x, NULL, c(2, 0), 1L))
    escaped <- list()
    rlang::local_bindings(length.dta_numeric = function(x) {
        escaped[[length(escaped) + 1L]] <<- x
        NextMethod()
    }, .env = globalenv())
    expect_error(replace_values(data, x, 12, where = x == 2), "noncanonical NaN payload")
    rm(length.dta_numeric, envir = globalenv())
    expect_gt(length(escaped), 0L)
    expect_true(all(vapply(lapply(escaped, as.double), identical, logical(1), c(NaN, 2))))
    replace_values(data, x, c(7, 8))
    expect_true(all(vapply(lapply(escaped, as.double), identical, logical(1), c(NaN, 2))))
    expect_identical(as.double(data$x), c(7, 8))
})

test_that("ordinary doubles are captured once and column results fork backing", {
    source <- c(1, 2, NA_real_, tagged_missing("a"))
    column <- dta_double(source)
    expect_type(column, "double")
    expect_s3_class(column, "dta_numeric")
    expect_false(is.null(owned_info(column)))
    data <- dibble(x = column, y = dta_double(c(3, 4, 5, 6)))
    result <- dplyr::rename(data, renamed = x)
    expect_false(identical(rlang::obj_address(data$x), rlang::obj_address(result$renamed)))
    expect_identical(owned_info(data$x)$backing, owned_info(result$renamed)$backing)
    for (i in 1:5) result <- dplyr::relocate(result, y)
    expect_identical(owned_info(result$renamed)$depth, 1L)
    expect_identical(as.double(result$renamed), source)
})

test_that("ordinary dictionary cast prototypes do not decode target values", {
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path))
    save_arrow(data.frame(text = c("first", "second", "third")), path)
    value <- read_arrow(path, output = "tibble")$text
    attr(value, "label") <- "Words"
    expect_true(.is_unmaterialized_dictstring(value))
    cache <- .dictstring_cached_count(value)
    prototype <- .Call(C_dtatools_mutation_prototype, value)
    expect_identical(prototype, structure(character(), label = "Words"))
    expect_identical(.dictstring_cached_count(value), cache)
    expect_true(.is_unmaterialized_dictstring(value))
    class(value) <- "custom_dictionary"
    expect_null(.Call(C_dtatools_mutation_prototype, value))
})

test_that("plain integer and logical cast prototypes need no target payload", {
    for (value in list(seq_len(100L), c(TRUE, NA, FALSE))) {
        attr(value, "label") <- "Values"
        names(value) <- as.character(seq_along(value))
        expected <- structure(vector(typeof(value)), label = "Values",
                              names = character())
        expect_identical(.Call(C_dtatools_mutation_prototype, value), expected)
        class(value) <- "custom_discrete"
        expect_null(.Call(C_dtatools_mutation_prototype, value))
    }
})

test_that("foreign integer prototypes and full replacements skip old payload reads", {
    for (mode in c("prototype", "full", "sparse", "error")) {
        calls <- 0L
        source <- .Call(C_dtatools_callback_integer, c(1L, 2L, 3L), function() {
            calls <<- calls + 1L
            gc()
        })
        attr(source, "label") <- "Values"
        names(source) <- c("a", "b", "c")
        data <- structure(list(x = source), class = "data.frame",
                          row.names = c(NA_integer_, -3L))
        alias <- data
        if (mode == "prototype") {
            expect_identical(.Call(C_dtatools_mutation_prototype, source),
                structure(integer(), label = "Values", names = character()))
            expect_identical(calls, 0L)
            next
        }
        if (mode == "error") {
            expect_error(replace_values(data, x, 0.5), "loss of precision")
            expect_identical(calls, 0L)
            expect_identical(data$x, source)
            next
        }
        if (mode == "full") {
            replace_values(data, x, 9L)
            expect_identical(calls, 0L)
            expected <- c(9L, 9L, 9L)
        } else {
            replace_values(data, x, 9L, where = 2L)
            expect_identical(calls, 1L)
            expected <- c(1L, 9L, 3L)
        }
        expect_identical(unname(as.integer(data$x)), expected)
        expect_identical(attributes(data$x), list(label = "Values", names = c("a", "b", "c")))
        expect_identical(alias$x, data$x)
        expect_false(.is_altrep(data$x))
        expect_identical(unname(as.integer(source)), c(1L, 2L, 3L))
    }
})

test_that("capture preserves identical owned columns within one physical table", {
    for (convert in c(FALSE, TRUE)) {
        column <- dta_double(c(1, 2, 3))
        data <- if (convert) {
            as_dibble(structure(list(x = column, y = column),
                                class = "data.frame", row.names = c(NA_integer_, -3L)))
        } else dibble(x = column, y = column)
        expect_identical(rlang::obj_address(data$x), rlang::obj_address(data$y))
        replace_values(data, x, 9, where = 1L)
        expect_identical(as.double(data$x), c(9, 2, 3))
        expect_identical(as.double(data$y), c(9, 2, 3))
        expect_identical(as.double(column), c(1, 2, 3))
    }
})

test_that("public writable and retained pointers cannot change another fork", {
    source <- dta_double(c(1, 2, 3))
    sibling <- .metadata_copy(source)
    original <- c(1, 2, 3)
    pointer <- .Call(C_dtatools_owned_pointer, source, TRUE)
    expect_true(owned_info(source)$exposed)
    later <- .metadata_copy(source)
    gc()
    .Call(C_dtatools_owned_pointer_write, pointer, 2L, 9)
    expect_identical(as.double(source), c(1, 9, 3))
    expect_identical(as.double(sibling), original)
    expect_identical(as.double(later), original)
    expect_false(identical(owned_info(source)$backing, owned_info(later)$backing))
    expect_error(.Call(C_dtatools_owned_pointer_write,
        .Call(C_dtatools_owned_pointer, later, FALSE), 1L, 0), "writable pointer")
})

test_that("public column exports isolate later ordinary and explicit writes", {
    skip_if_not_installed("data.table")
    exports <- list(
        as_double = function(data) as.double(data$x),
        as_vector = function(data) as.vector(data$x),
        unclass = function(data) unclass(data$x),
        as_data_frame_column = function(data) as.data.frame(data$x)[[1L]],
        as_data_frame_table = function(data) as.data.frame(data)[[2L]],
        as_tibble = function(data) tibble::as_tibble(data)[[2L]],
        as_data_table = function(data) data.table::as.data.table(data)[[2L]]
    )
    for (typed in c(FALSE, TRUE)) for (export in exports) {
        data <- reserve_columns(data.frame(anchor = 1:3))
        gen(data, x, dta_double(c(1, 2, 3)))
        if (!typed) class(data$x) <- NULL
        value <- export(data)
        replace_values(data, x, 9, where = 2L)
        expect_identical(as.double(value), c(1, 2, 3))
        value[1L] <- 8
        expect_identical(as.double(data$x), c(1, 9, 3))
    }
})

test_that("foreign double ingress and data table exports preserve both write directions", {
    skip_if_not_installed("data.table")
    ingress <- list(
        constructor = function(source) dibble(x = source$x),
        conversion = function(source) as_dibble(source),
        mutate = function(source) dplyr::mutate(dibble(anchor = 1:3), x = .env$source$x),
        bind_cols = function(source) dplyr::bind_cols(dibble(anchor = 1:3), source),
        cbind = function(source) cbind(dibble(anchor = 1:3), source),
        callback = function(source) dplyr::group_modify(dibble(anchor = 1:3),
                                                       function(.x, .y) source)
    )
    for (create in ingress) {
        source <- data.table::data.table(x = unserialize(serialize(dta_double(c(1, 2, 3)), NULL)))
        expect_null(owned_info(source$x))
        data <- create(source)
        expect_true(is_dibble(data))
        expect_s3_class(data$x, "dta_double")
        data.table::set(source, i = 2L, j = "x", value = 9)
        expect_identical(as.double(data$x), c(1, 2, 3))
        replace_values(data, x, 8, where = 1L)
        expect_identical(as.double(source$x), c(1, 9, 3))
        output <- data.table::as.data.table(data)
        data.table::set(output, i = 3L, j = "x", value = 7)
        expect_identical(as.double(data$x), c(8, 2, 3))
        replace_values(data, x, 6, where = 2L)
        expect_identical(as.double(output$x), c(8, 2, 7))
    }
})

test_that("read pointers and ordinary aggregates retain safe backing forks", {
    value <- dta_double(c(1, 2, 3))
    pointer <- .Call(C_dtatools_owned_pointer, value, FALSE)
    expect_false(is.null(pointer))
    expect_equal(as.double(sum(value)), 6)
    expect_equal(as.double(min(value)), 1)
    expect_equal(as.double(max(value)), 3)
    expect_false(anyNA(value))
    expect_false(owned_info(value)$exposed)
    copy <- .metadata_copy(value)
    expect_identical(owned_info(copy)$backing, owned_info(value)$backing)
    expect_identical(as.double(value[c(3L, NA_integer_, 1L)]), c(3, NA_real_, 1))
})

test_that("owned doubles preserve metadata and ordinary serialized values", {
    value <- dta_double(c(1, tagged_missing("z"), NA_real_))
    attr(value, "label") <- "Codes"
    restored <- unserialize(serialize(value, NULL))
    expect_identical(as.double(restored), c(1, tagged_missing("z"), NA_real_))
    expect_identical(attributes(restored), attributes(value))
    # Base's initial serialization fallback is allowed to expose/materialize
    # the original. Metadata sharing is checked on a fresh private capture.
    value <- dta_double(c(1, tagged_missing("z"), NA_real_))
    attr(value, "label") <- "Codes"
    data <- dibble(x = value)
    set_var_label(data, x, "Changed")
    expect_identical(attr(value, "label"), "Codes")
    expect_identical(owned_info(data$x)$backing, owned_info(value)$backing)
})
