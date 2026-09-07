owned_atom_info <- function(value) .Call(C_dtatools_owned_info, value)
owned_atom_scan_stats <- function(reset = FALSE) .Call(C_dtatools_owned_scan_stats, reset)
owned_atom_capture <- function(value) .Call(C_dtatools_capture_column, value)

owned_atom_fixtures <- function() list(
    string = dta_string(c("wide", "", "\u00e9", "z"), "str8"),
    declared = structure(c("wide", "", "\u00e9", "z"), stata.string.storage = "str8"),
    logical = c(TRUE, FALSE, NA, TRUE),
    factor = factor(c("b", "a", NA, "b"), levels = c("a", "b", "unused")),
    ordered = ordered(c("b", "a", NA, "b"), levels = c("a", "b", "unused"))
)

test_that("ordinary atom handles share flat backing with independent attributes", {
    for (value in owned_atom_fixtures()) {
        data <- dibble(x = value, keep = dta_double(1:4))
        source <- owned_atom_info(data$x)
        expect_false(source$exposed)
        renamed <- dplyr::rename(data, y = x)
        selected <- dplyr::select(data, second = x, first = x)
        relocated <- dplyr::relocate(data, keep)
        for (result in list(renamed$y, selected$first, selected$second, relocated$x)) {
            expect_identical(result, data$x)
            expect_identical(owned_atom_info(result)$backing, source$backing)
            expect_identical(owned_atom_info(result)$depth, 1L)
            expect_false(owned_atom_info(result)$exposed)
        }
        attr(renamed$y, "label") <- "changed"
        expect_null(attr(data$x, "label", exact = TRUE))
        expect_identical(attributes(data$x), attributes(value))
        expect_identical(typeof(data$x), typeof(value))
    }
    integers <- owned_atom_capture(c(1L, NA_integer_, 3L))
    sibling <- .metadata_copy(integers)
    expect_identical(typeof(sibling), "integer")
    expect_identical(owned_atom_info(integers)$backing, owned_atom_info(sibling)$backing)
    expect_identical(as.integer(sibling), c(1L, NA_integer_, 3L))
})

test_that("unchanged owned string selectors reuse validation facts", {
    for (value in owned_atom_fixtures()[c("string", "declared")]) {
        data <- dibble(x = value, other = value)
        owned_atom_scan_stats(TRUE)
        for (i in 1:50) {
            data <- dplyr::rename(data, third = x)
            data <- dplyr::select(data, x = third, other)
            data <- dplyr::relocate(data, other)
        }
        expect_identical(owned_atom_scan_stats(), c(0, 0))
        expect_identical(owned_atom_info(data$x)$depth, 1L)
    }
})

test_that("string facts distinguish subset bounds from exact maxima", {
    source <- dta_string(c("long", "x"), "str4")
    expect_identical(.Call(C_dtatools_owned_string_width, source), 4L)
    subset <- as.character(source)[2L]
    owned_atom_scan_stats(TRUE)
    expect_true(.Call(C_dtatools_owned_string_fits, subset, 4))
    expect_identical(owned_atom_scan_stats(), c(0, 0))
    expect_true(.Call(C_dtatools_owned_string_fits, subset, 1))
    expect_identical(owned_atom_scan_stats(), c(1, 1))
    attr(subset, "stata.string.storage") <- "str1"
    expect_true(.string_declaration_holds(subset))
    padded <- as.character(source)[c(2L, NA_integer_, 4L)]
    expect_false(.Call(C_dtatools_owned_string_fits, padded, 4))
    repaired <- dibble(x = structure(padded, stata.string.storage = "str4"))
    expect_identical(as.character(repaired$x), c("x", "", ""))
})

test_that("missingness-only string validation is included in scan counters", {
    source <- owned_atom_capture(c("a", "b"))
    owned_atom_scan_stats(TRUE)
    expect_true(.Call(C_dtatools_owned_no_na, source))
    expect_identical(owned_atom_scan_stats(), c(1, 2))
    expect_true(.Call(C_dtatools_owned_no_na, source))
    expect_identical(owned_atom_scan_stats(), c(1, 2))
    expect_false(anyNA(source))
})

test_that("foreign index callbacks cannot propagate facts from a changed source", {
    source <- owned_atom_capture(c("long", "x"))
    expect_identical(.Call(C_dtatools_owned_string_width, source), 4L)
    calls <- 0L
    index <- .Call(C_dtatools_callback_integer, c(1L, 2L), function() {
        calls <<- calls + 1L
        .Call(C_dtatools_owned_set_string, source, 1L, "x")
        .Call(C_dtatools_owned_string_width, source)
    })
    subset <- .Call(C_dtatools_owned_subset, source, index)
    expect_gt(calls, 0L)
    # Foreign indices force a scan even when the source now has cached facts.
    owned_atom_scan_stats(TRUE)
    expect_true(.Call(C_dtatools_owned_string_fits, subset, 4))
    expect_identical(owned_atom_scan_stats(), c(1, 2))
})

test_that("writable pointers isolate all atom types and remain unsafe to share", {
    for (values in list(c("a", "bb", NA_character_), c(TRUE, FALSE, NA), c(1L, 2L, NA_integer_))) {
        source <- owned_atom_capture(values)
        earlier <- .metadata_copy(source)
        before <- owned_atom_info(source)
        readonly <- .Call(C_dtatools_owned_pointer, source, FALSE)
        expect_identical(owned_atom_info(source), before)
        expect_error(.Call(C_dtatools_owned_pointer_write, readonly, 1L, values[2L]), "writable pointer")
        pointer <- .Call(C_dtatools_owned_pointer, source, TRUE)
        expect_true(owned_atom_info(source)$exposed)
        expect_false(identical(owned_atom_info(source)$backing, before$backing))
        later <- .metadata_copy(source)
        .Call(C_dtatools_owned_pointer_write, pointer, 1L, values[2L])
        expect_identical(earlier, values)
        expect_identical(later, values)
        expect_identical(source[1L], values[2L])
        expect_false(owned_atom_info(later)$exposed)
    }
})

test_that("Set_elt and retained writable strings invalidate missingness and width facts", {
    source <- owned_atom_capture(c("a", "b"))
    expect_true(.Call(C_dtatools_owned_string_fits, source, 1))
    sibling <- .metadata_copy(source)
    .Call(C_dtatools_owned_set_string, source, 1L, "wider")
    expect_false(.Call(C_dtatools_owned_string_fits, source, 1))
    expect_true(.Call(C_dtatools_owned_string_fits, sibling, 1))
    expect_identical(sibling, c("a", "b"))
    .Call(C_dtatools_owned_set_string, source, 2L, NA_character_)
    expect_true(anyNA(source))
    expect_false(.Call(C_dtatools_owned_string_fits, source, 20))
    pointer <- .Call(C_dtatools_owned_pointer, source, TRUE)
    .Call(C_dtatools_owned_pointer_write, pointer, 2L, "b")
    expect_true(.Call(C_dtatools_owned_string_fits, source, 20))
    later <- .metadata_copy(source)
    .Call(C_dtatools_owned_pointer_write, pointer, 1L, "much wider")
    expect_false(.Call(C_dtatools_owned_string_fits, source, 5))
    expect_true(.Call(C_dtatools_owned_string_fits, later, 5))
})

test_that("foreign data.table atoms are captured at constructors and callback ingress", {
    skip_if_not_installed("data.table")
    for (value in owned_atom_fixtures()) {
        foreign <- data.table::data.table(x = value)
        # data.table must supply ordinary foreign storage, never our handle.
        expect_null(owned_atom_info(foreign$x))
        expect_false(.is_altrep(foreign$x))
        original <- .deep_copy_value(foreign$x)
        direct <- as_dibble(foreign)
        source <- dibble(anchor = dta_double(1:4))
        transformed <- dplyr::mutate(source, x = foreign$x)
        callback <- dplyr::group_modify(source, function(.x, .y) tibble::tibble(x = foreign$x))
        bound <- dplyr::bind_cols(source, tibble::tibble(x = foreign$x))
        base_bound <- cbind(source, data.frame(x = foreign$x))
        data.table::set(foreign, i = 1L, j = "x", value = foreign$x[2L])
        for (result in list(direct, transformed, callback, bound, base_bound)) {
            expect_identical(result$x, original)
            expect_false(is.null(owned_atom_info(result$x)))
        }
    }
})

test_that("owned atom serialization restores values without live ownership records", {
    for (value in owned_atom_fixtures()) for (version in c(2L, 3L)) {
        source <- dibble(x = value)
        result <- dplyr::rename(source, y = x)
        restored <- unserialize(serialize(list(source, result), NULL, version = version))
        expect_identical(restored[[1L]]$x, value)
        expect_identical(restored[[2L]]$y, value)
        expect_null(owned_atom_info(restored[[1L]]$x))
        expect_null(owned_atom_info(restored[[2L]]$y))
        # as_dibble(existing_dibble) deliberately remains identity; an ordinary
        # operation recaptures restored plain payload while making its result.
        recaptured <- dplyr::rename(restored[[1L]], x = x)
        expect_false(is.null(owned_atom_info(recaptured$x)))
        recaptured$x[1L] <- recaptured$x[2L]
        expect_identical(restored[[1L]]$x, value)
        expect_identical(restored[[2L]]$y, value)
        expect_identical(source$x, value)
    }
})

test_that("ordinary base copies and explicit atom writes preserve both alias contracts", {
    for (value in owned_atom_fixtures()[c("string", "declared", "logical")]) {
        data <- reserve_columns(dibble(x = value, y = value), n = 2L)
        alias <- data
        isolated <- dplyr::rename(data, z = x)
        standalone <- data$x
        copied <- data
        attr(copied, "copy") <- TRUE
        replacement <- if (is.character(value)) "r" else FALSE
        replace_values(data, x, replacement, where = 1L)
        expect_identical(isolated$z, value)
        expect_identical(standalone, value)
        expect_identical(copied$x, value)
        expect_identical(alias$x[1L], data$x[1L])
        replace_values(isolated, z, replacement, where = 2L)
        expect_identical(data$x[2L], value[2L])
        rebound <- data
        rebound$x[3L] <- replacement
        expect_identical(alias$x, data$x)
        expect_identical(data$x[3L], value[3L])
    }
})

test_that("owned atomic native patches stage fully and keep prior state on interruption", {
    withr::defer(.inject_reference_write_interrupt(FALSE))
    for (value in list(c("a", "b", "c"), c(TRUE, FALSE, NA), c(1L, 2L, 3L))) {
        target <- owned_atom_capture(value)
        sibling <- .metadata_copy(target)
        if (is.character(value)) .Call(C_dtatools_owned_string_width, target)
        before <- owned_atom_info(target)
        .inject_reference_write_interrupt(TRUE)
        condition <- tryCatch(.Call(C_dtatools_patch_vector, target, c(1L, 3L), value[2L]),
                              interrupt = identity, error = identity)
        .inject_reference_write_interrupt(FALSE)
        expect_s3_class(condition, "interrupt")
        expect_identical(owned_atom_info(target), before)
        expect_identical(target, value)
        expect_identical(sibling, value)
        .Call(C_dtatools_patch_vector, target, c(1L, 3L), value[2L])
        expect_identical(target, rep(value[2L], 3L))
        expect_identical(sibling, value)
    }
})

test_that("generation and atomic staging root detached integer row payload", {
    attributes <- structure(list(), names = character())
    for (kind in c("string", "double", "compact", "patch")) {
        rows <- owned_atom_capture(c(1L, 3L))
        .metadata_copy(rows) # Revoke privacy without retaining the old payload.
        callback <- function() {
            .Call(C_dtatools_patch_vector, rows, NULL, c(2L, 2L))
            gc()
        }
        if (kind == "patch") {
            target <- owned_atom_capture(c("a", "b", "c"))
            values <- .Call(C_dtatools_callback_length, c("x", "y"), callback)
            .Call(C_dtatools_patch_vector, target, rows, values)
            expect_identical(target, c("x", "b", "y"))
        } else if (kind == "string") {
            values <- .Call(C_dtatools_callback_length, c("x", "y"), callback)
            output <- .Call(C_dtatools_generate_character, values, rows, 3, NULL, attributes)
            expect_identical(as.vector(output), c("x", "", "y"))
        } else {
            values <- .Call(C_dtatools_callback_length, c(10, 20), callback)
            output <- .Call(C_dtatools_generate_numeric, values, rows, 3,
                            if (kind == "double") 4L else 0L, 0L, attributes)
            expect_identical(as.double(output), c(10, NA_real_, 20))
        }
        expect_identical(rows, c(2L, 2L))
    }
})

test_that("legacy vector patches root detached integer row payloads", {
    path <- tempfile(fileext = ".arrow")
    withr::defer(unlink(path))
    save_arrow(data.frame(x = c("a", "b", "a")), path)
    for (kind in c("plain", "dictionary", "materialized", "compact")) {
        rows <- owned_atom_capture(c(1L, 3L))
        .metadata_copy(rows)
        calls <- 0L
        callback <- function() {
            calls <<- calls + 1L
            .Call(C_dtatools_patch_vector, rows, NULL, c(2L, 2L))
            gc()
        }
        target <- switch(kind, plain = c("a", "b", "a"),
                         dictionary = read_arrow(path, output = "tibble")$x,
                         materialized = dta_byte(1:3), compact = dta_byte(1:3))
        if (kind == "materialized") .force_altrep_materialization(target)
        expect_null(owned_atom_info(target))
        if (kind == "dictionary") expect_true(.is_unmaterialized_dictstring(target))
        if (kind == "compact") expect_true(.is_unmaterialized_numeric_altrep(target))
        if (kind == "materialized") expect_true(.is_materialized_numeric_altrep(target))
        values <- .Call(C_dtatools_callback_length,
                       if (typeof(target) == "character") c("x", "y") else c(10, 20), callback)
        .Call(C_dtatools_patch_vector, target, rows, values)
        expect_identical(calls, 1L)
        expect_identical(rows, c(2L, 2L))
        if (typeof(target) == "character") expect_identical(as.character(target), c("x", "b", "y")) else
            expect_identical(as.double(target), c(10, 2, 20))
    }
})

test_that("legacy foreign rows finish callbacks before numeric readers are retained", {
    for (kind in c("compact", "materialized")) for (after in c(0L, 2L)) {
        target <- dta_byte(1:3)
        if (kind == "materialized") .force_altrep_materialization(target)
        values <- dta_byte(c(10, 20, 30))
        expect_true(.is_unmaterialized_numeric_altrep(values))
        calls <- 0L
        rows <- .Call(C_dtatools_callback_integer_after, c(1L, 3L), function() {
            calls <<- calls + 1L
            .force_altrep_materialization(values)
            gc()
        }, after)
        # Foreign rows are read once into a plain snapshot. Immediate callbacks
        # finish before reader creation; later callbacks cannot reach journaling.
        .Call(C_dtatools_patch_vector, target, rows, values)
        expect_identical(calls, if (after == 0L) 1L else 0L)
        expect_identical(as.double(target), c(10, 2, 30))
        expect_identical(as.double(values), c(10, 20, 30))
        expect_identical(.is_materialized_numeric_altrep(values), after == 0L)
    }
})

test_that("legacy journaling and writes use captured operands without later callbacks", {
    for (operand in c("rows", "values")) {
        target <- dta_byte(1:3)
        calls <- 0L
        delayed <- .Call(C_dtatools_callback_integer_after,
            if (operand == "rows") c(1L, 3L) else c(10L, 20L), function() {
                calls <<- calls + 1L
                .force_altrep_materialization(target)
                gc()
            }, 2L)
        rows <- if (operand == "rows") delayed else c(1L, 3L)
        values <- if (operand == "values") delayed else c(10, 20)
        .Call(C_dtatools_patch_vector, target, rows, values)
        expect_identical(calls, 0L)
        expect_true(.is_unmaterialized_numeric_altrep(target))
        expect_identical(as.double(target), c(10, 2, 20))
    }
})

test_that("legacy dictionary targets validate state after declared-width callbacks", {
    path <- tempfile(fileext = ".arrow")
    withr::defer(unlink(path))
    save_arrow(data.frame(x = c("a", "b", "a")), path)
    target <- read_arrow(path, output = "tibble")$x
    expect_true(.is_unmaterialized_dictstring(target))
    calls <- 0L
    attr(target, "stata.string.storage") <- .Call(C_dtatools_callback_character, "str1", function() {
        calls <<- calls + 1L
        .force_altrep_materialization(target)
        gc()
    })
    expect_error(.Call(C_dtatools_patch_vector, target, 1L, "x"),
                 "target changed while preparing replacement")
    expect_identical(calls, 1L)
    expect_identical(as.vector(target), c("a", "b", "a"))
})

test_that("legacy compact targets reject materialization during operand callbacks", {
    for (boundary in c("length", "row")) {
        target <- dta_byte(1:3)
        expect_true(.is_unmaterialized_numeric_altrep(target))
        calls <- 0L
        callback <- function() {
            calls <<- calls + 1L
            .force_altrep_materialization(target)
            gc()
        }
        values <- if (boundary == "length")
            .Call(C_dtatools_callback_length, c(10, 20), callback) else c(10, 20)
        rows <- if (boundary == "row")
            .Call(C_dtatools_callback_integer, c(1L, 3L), callback) else c(1L, 3L)
        expect_error(.Call(C_dtatools_patch_vector, target, rows, values),
                     "target changed while preparing replacement")
        expect_identical(calls, 1L)
        expect_identical(as.double(target), c(1, 2, 3))
        expect_true(.is_materialized_numeric_altrep(target))
    }
})

test_that("generation rejects live rows moved out of bounds by value callbacks", {
    attributes <- structure(list(), names = character())
    for (kind in c("string", "double", "compact")) {
        rows <- owned_atom_capture(c(1L, 3L))
        pointer <- .Call(C_dtatools_owned_pointer, rows, TRUE)
        callback <- function() .Call(C_dtatools_owned_pointer_write, pointer, 2L, 99L)
        if (kind == "string") {
            values <- .Call(C_dtatools_callback_character, "x", callback)
            expect_error(.Call(C_dtatools_generate_character, values, rows, 3, NULL, attributes),
                         "invalid reference mutation row")
        } else {
            values <- .Call(C_dtatools_callback_double, 10, callback, TRUE)
            expect_error(.Call(C_dtatools_generate_numeric, values, rows, 3,
                               if (kind == "double") 4L else 0L, 0L, attributes),
                         "invalid reference mutation row")
        }
    }
})

test_that("factor ownership preserves existing replacement restrictions and levels", {
    for (value in owned_atom_fixtures()[c("factor", "ordered")]) {
        source <- reserve_columns(dibble(x = value), n = 1L)
        result <- dplyr::rename(source, y = x)
        expect_error(replace_values(source, x, value[1L], where = 2L), "unsupported replacement type")
        source$x[2L] <- source$x[1L]
        expect_identical(result$y, value)
        result$y[1L] <- result$y[2L]
        expect_identical(source$x[1L], value[1L])
        levels(result$y) <- c("first", "second", "unused")
        expect_identical(levels(source$x), levels(value))
        expect_identical(is.ordered(source$x), is.ordered(value))
        expect_identical(is.ordered(result$y), is.ordered(value))
        native <- owned_atom_capture(value)
        sibling <- .metadata_copy(native)
        .Call(C_dtatools_patch_vector, native, 1L, 1L)
        expect_identical(levels(native), levels(value))
        expect_identical(is.ordered(native), is.ordered(value))
        expect_identical(sibling, value)
    }
})

test_that("public atom exports and source mutations remain symmetrically isolated", {
    exports <- list(as.vector, unclass, function(x) data.frame(x = x)$x,
                    function(x) tibble::tibble(x = x)$x)
    if (requireNamespace("data.table", quietly = TRUE)) {
        exports <- c(exports, list(function(x) data.table::as.data.table(list(x = x))$x))
    }
    for (value in owned_atom_fixtures()) for (export in exports) {
        source <- dibble(x = value)
        before <- owned_atom_info(source$x)$backing
        out <- export(source$x)
        expected <- .deep_copy_value(out)
        # Keep each returned alias alive through the next selector and write.
        selected <- dplyr::rename(source, y = x)
        expect_identical(owned_atom_info(source$x)$backing, before)
        if (typeof(value) %in% c("character", "logical")) {
            replace_values(source, x, source$x[2L], where = 1L)
        } else source$x[1L] <- source$x[2L]
        source_after <- .deep_copy_value(source$x)
        expect_identical(out, expected)
        expect_identical(selected$y, value)
        out[2L] <- out[1L]
        expect_identical(source$x, source_after)
        expect_identical(selected$y, value)
    }
    for (value in owned_atom_fixtures()[c("string", "declared")]) {
        source <- dibble(x = value)
        before <- owned_atom_info(source$x)$backing
        out <- as.character(source$x)
        selected <- dplyr::rename(source, y = x)
        expect_identical(owned_atom_info(source$x)$backing, before)
        replace_values(source, x, "r", where = 1L)
        expect_identical(out, as.character(value))
        out[2L] <- "export"
        expect_identical(selected$y, value)
    }
})

test_that("dictionary read pins survive callback materialization in subsets and atom patches", {
    path <- tempfile(fileext = ".arrow")
    withr::defer(unlink(path))
    save_arrow(data.frame(x = c("alpha", "beta", "alpha")), path)
    for (operation in c("subset", "patch", "empty_patch", "error")) {
        value <- read_arrow(path, output = "tibble")$x
        expect_true(.is_unmaterialized_dictstring(value))
        callback <- function() {
            .force_altrep_materialization(value)
            gc()
        }
        if (operation == "subset") {
            index <- .Call(C_dtatools_callback_integer, c(3L, 2L, 1L), callback)
            result <- .Call(C_dtatools_dictstring_subset, value, index)
            expect_identical(as.character(result), c("alpha", "beta", "alpha"))
            expect_true(.is_unmaterialized_dictstring(result))
        } else {
            target <- owned_atom_capture(c("old", "old", "old"))
            declaration <- .Call(C_dtatools_callback_character,
                                 if (operation == "error") "str1" else "str5", callback)
            attr(target, "stata.string.storage") <- declaration
            original <- owned_atom_info(target)
            if (operation == "error") {
                expect_error(.Call(C_dtatools_patch_vector, target, NULL, value), "declared Stata string storage")
                expect_identical(owned_atom_info(target), original)
                expect_identical(as.vector(target), rep("old", 3L))
            } else if (operation == "empty_patch") {
                scalar <- value[1L]
                callback <- function() { .force_altrep_materialization(scalar); gc() }
                declaration <- .Call(C_dtatools_callback_character, "str5", callback)
                attr(target, "stata.string.storage") <- declaration
                .Call(C_dtatools_patch_vector, target, integer(), scalar)
                expect_identical(as.vector(target), rep("old", 3L))
            } else {
                .Call(C_dtatools_patch_vector, target, NULL, value)
                expect_identical(as.vector(target), c("alpha", "beta", "alpha"))
            }
        }
    }
})

test_that("DTA and Arrow writer pointers survive later metadata callbacks", {
    fixture <- tempfile(fileext = ".arrow")
    withr::defer(unlink(fixture))
    save_arrow(data.frame(x = c("alpha", "beta", "alpha")), fixture)
    for (format in c("dta", "arrow")) for (kind in c("dictionary", "integer", "logical", "double")) {
        data <- if (kind == "dictionary") read_arrow(fixture, output = "tibble") else
            tibble::tibble(x = switch(kind, integer = owned_atom_capture(c(1L, 2L, 3L)),
                                    logical = owned_atom_capture(c(TRUE, FALSE, NA)),
                                    double = dta_double(c(1, 2, 3))))
        data$y <- c("a", "b", "c")
        specification <- if (format == "dta") .prepare_dta_write(data, NULL, 2045L, TRUE) else
            .prepare_arrow_write(data, NULL, TRUE)
        value <- specification[[3L]][[1L]]$values
        if (kind == "dictionary") expect_true(.is_unmaterialized_dictstring(value))
        expected <- if (kind == "dictionary") c("alpha", "beta", "alpha") else
            if (kind == "logical") c(1, 0, NA_real_) else c(1, 2, 3)
        if (!is.null(owned_atom_info(value))) .metadata_copy(value)
        callback <- function() {
            if (kind == "dictionary") .force_altrep_materialization(value) else
                if (!is.null(owned_atom_info(value))) .Call(C_dtatools_patch_vector, value, NULL,
                    if (typeof(value) == "logical") FALSE else if (typeof(value) == "integer") 9L else 9)
            gc()
        }
        specification[[3L]][[2L]]$name <- .Call(C_dtatools_callback_character, "y", callback)
        path <- tempfile(fileext = paste0(".", format))
        withr::defer(unlink(path))
        if (format == "dta") .Call(C_dtatools_write, specification, path) else
            .Call(C_dtatools_save_arrow, specification, path, "uncompressed", 1L, TRUE)
        restored <- if (format == "dta") read_dta(path) else read_arrow(path)
        actual <- if (kind == "dictionary") as.character(restored$x) else as.double(restored$x)
        expect_identical(actual, expected)
        expect_identical(as.character(restored$y), c("a", "b", "c"))
    }
})


test_that("table atom exports retain isolation under each explicit write API", {
    exports <- list(data.frame = function(x) data.frame(x = x),
                    tibble = function(x) tibble::tibble(x = x))
    if (requireNamespace("data.table", quietly = TRUE)) {
        exports$data.table <- function(x) data.table::as.data.table(list(x = x))
    }
    for (value in owned_atom_fixtures()[c("string", "declared", "logical")]) for (kind in names(exports)) {
        source <- dibble(x = value)
        exported <- exports[[kind]](source$x)
        selected <- dplyr::rename(source, y = x)
        replace_values(source, x, source$x[2L], where = 1L)
        source_after <- .deep_copy_value(source$x)
        expect_identical(exported$x, value)
        expect_identical(selected$y, value)
        replacement <- if (is.character(value)) "r" else TRUE
        if (kind == "data.table") data.table::set(exported, i = 2L, j = "x", value = replacement) else
            replace_values(exported, x, replacement, where = 2L)
        expect_identical(source$x, source_after)
        expect_identical(selected$y, value)
    }
})
