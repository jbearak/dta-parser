owned_atom_info <- function(value) .Call(C_dtatools_owned_info, value)
owned_atom_scan_stats <- function(reset = FALSE) .Call(C_dtatools_owned_scan_stats, reset)
owned_atom_capture <- function(value) .Call(C_dtatools_capture_column, value)

test_that("validated discrete batches retain vctrs and base gather behavior", {
    values <- list(l = rep(c(TRUE, FALSE, NA), length.out = 1000L),
                   f = factor(rep(c("b", "a", NA), length.out = 1000L),
                              levels = c("a", "b", "unused")),
                   o = ordered(rep(c("b", "a", NA), length.out = 1000L),
                               levels = c("a", "b", "unused")))
    values <- lapply(values, function(x) {
        # Populate a fresh ordinary vector. Repeated attribute edits to a
        # borrowed large vector can instead create R's foreign metadata wrapper.
        out <- if (is.factor(x)) as.integer(x)[seq_along(x)] else x[seq_along(x)]
        if (is.factor(x)) {
            attr(out, "levels") <- levels(x)
            attr(out, "class") <- class(x)
        }
        attr(out, "label") <- "label"
        attr(out, "notes") <- c("one", "two")
        out
    })
    frame <- vctrs::new_data_frame(values, n = 1000L)
    expect_false(any(vapply(values, .is_altrep, TRUE)))
    columns <- lapply(values, owned_atom_capture)
    before <- lapply(columns, owned_atom_info)
    expect_true(all(vapply(before, function(x) !is.null(x), TRUE)))
    for (locations in list(integer(), c(1L, 1000L, 1L), c(NA_integer_, 3L, 1L))) {
        result <- .Call(C_dtatools_gather_owned_discrete, columns, locations)
        expect_identical(result, stats::setNames(
            .plain_data_columns(vctrs::vec_slice(frame, locations)), names(values)))
        expect_identical(lapply(result, attributes), lapply(values, attributes))
        expect_true(all(vapply(result, function(x) !is.null(owned_atom_info(x)), TRUE)))
        expect_identical(.gather_dta_columns(columns, locations), result)
        expect_identical(.gather_dta_columns(columns, locations, "base"),
                         stats::setNames(.plain_data_columns(frame[locations, , drop = FALSE]),
                                         names(values)))
    }
    result <- .Call(C_dtatools_gather_owned_discrete, columns, c(1L, 3L))
    .Call(C_dtatools_patch_vector, columns$l, 1L, FALSE)
    expect_identical(as.logical(result$l), c(TRUE, NA))
    .Call(C_dtatools_patch_vector, result$f, 1L, 1L)
    expect_identical(as.integer(columns$f), as.integer(values$f))
    expect_identical(lapply(columns[-1L], function(x) owned_atom_info(x)$backing),
                     lapply(before[-1L], `[[`, "backing"))
})

test_that("discrete gather declines whole callback or metadata fallback batches", {
    calls <- 0L
    callback <- function() calls <<- calls + 1L
    eligible <- owned_atom_capture(c(TRUE, FALSE, NA))
    foreign <- .Call(C_dtatools_callback_integer, c(1L, 2L, 3L), callback)
    expect_null(.Call(C_dtatools_gather_owned_discrete,
                     list(first = eligible, second = foreign), c(1L, 3L)))
    expect_identical(calls, 0L)
    for (attribute in list(list(names = c("a", "b", "c")), list(dim = c(3L, 1L)),
                           list(custom = TRUE), list(class = "unknown"))) {
        value <- .metadata_copy(eligible)
        attributes(value) <- attribute
        expect_null(.Call(C_dtatools_gather_owned_discrete,
                         list(first = eligible, second = value), c(1L, 3L)))
    }
    foreign_locations <- .Call(C_dtatools_callback_integer, c(1L, 3L), callback)
    expect_null(.Call(C_dtatools_gather_owned_discrete, list(eligible), foreign_locations))
    expect_identical(calls, 0L)
    expect_null(.Call(C_dtatools_gather_owned_discrete, list(eligible), c(a = 1L)))
})

test_that("mixed gather fallbacks retain cross-column callback order", {
    run <- function(direct, foreign_first) {
        target <- owned_atom_capture(c(TRUE, FALSE, NA))
        calls <- 0L
        foreign <- .Call(C_dtatools_callback_integer, c(1L, 2L, 3L), function() {
            calls <<- calls + 1L
            .Call(C_dtatools_patch_vector, target, 1L, FALSE)
        })
        columns <- if (foreign_first) list(foreign = foreign, target = target) else
            list(target = target, foreign = foreign)
        result <- if (direct) .gather_dta_columns(columns, c(1L, 3L)) else
            stats::setNames(.plain_data_columns(vctrs::vec_slice(
                vctrs::new_data_frame(columns, n = 3L), c(1L, 3L))), names(columns))
        list(result = result, source = as.logical(target), calls = calls)
    }
    for (foreign_first in c(FALSE, TRUE)) {
        actual <- run(TRUE, foreign_first)
        expect_identical(actual, run(FALSE, foreign_first))
        expect_identical(as.logical(actual$result$target), c(!foreign_first, NA))
        expect_identical(actual$source, c(FALSE, FALSE, NA))
        expect_identical(actual$calls, 1L)
    }
})

owned_atom_fixtures <- function() list(
    string = dta_string(c("wide", "", "\u00e9", "z"), "str8"),
    declared = structure(c("wide", "", "\u00e9", "z"), stata.string.storage = "str8"),
    logical = c(TRUE, FALSE, NA, TRUE),
    factor = factor(c("b", "a", NA, "b"), levels = c("a", "b", "unused")),
    ordered = ordered(c("b", "a", NA, "b"), levels = c("a", "b", "unused"))
)

test_that("owned record reads follow each replacement allocation through GC", {
    for (value in c(owned_atom_fixtures(), list(real = dta_double(c(1, 2, NA, 4))))) {
        original <- paste0(value)
        target <- owned_atom_capture(value)
        sibling <- .metadata_copy(target)
        .Call(C_dtatools_patch_vector, target, 1L, value[2L])
        expected <- original
        expected[1L] <- original[2L]
        gc()
        expect_identical(paste0(target), expected)
        expect_identical(paste0(sibling), original)
        .Call(C_dtatools_patch_vector, target, 2L, value[4L])
        expected[2L] <- original[4L]
        gc()
        expect_identical(paste0(target), expected)
        previous <- .metadata_copy(target)
        .Call(C_dtatools_patch_vector, target, NULL, rep(value[2L], length(value)))
        gc()
        expect_identical(paste0(target), rep(original[2L], length(value)))
        expect_identical(paste0(previous), expected)
        expect_identical(paste0(sibling), original)
    }
})

test_that("factor integer exports use an isolated ordinary deep copy", {
    for (ordered in c(FALSE, TRUE)) {
        value <- factor(rep(c("b", "a", NA), length.out = 1000L),
                        levels = c("a", "b", "unused"), ordered = ordered)
        source <- owned_atom_capture(value)
        expect_false(is.null(owned_atom_info(source)))
        before <- owned_atom_info(source)$backing
        expected <- as.integer(value)
        exported <- as.integer(source)
        expect_identical(exported, expected)
        expect_false(.is_altrep(exported))
        expect_null(attributes(exported))
        expect_identical(owned_atom_info(source)$backing, before)
        metadata_copy <- .metadata_copy(source)
        expect_identical(owned_atom_info(metadata_copy)$backing, before)
        if (ordered) expect_identical(range(source, na.rm = TRUE), range(value, na.rm = TRUE))
        .Call(C_dtatools_patch_vector, source, 1L, 1L)
        expect_identical(exported, expected)
        expect_identical(metadata_copy, value)
        exported[2L] <- 2L
        expect_identical(as.integer(source)[1:3], c(1L, 1L, NA_integer_))
        expect_identical(as.integer(metadata_copy), expected)
    }
})

test_that("public logical subsets are fresh ordinary values and batch results stay owned", {
    for (named in c(FALSE, TRUE)) {
        value <- rep(c(TRUE, FALSE, NA), length.out = 1000L)
        if (named) names(value) <- paste0("r", seq_along(value))
        source <- owned_atom_capture(value)
        before <- owned_atom_info(source)$backing
        for (locations in list(integer(), c(1L, 3L, 1L), c(NA_integer_, 1000L, 2L))) {
            result <- source[locations]
            expect_identical(result, value[locations])
            expect_false(.is_altrep(result))
            native <- .Call(C_dtatools_owned_subset, source, locations)
            expect_false(is.null(owned_atom_info(native)))
            expect_identical(unname(as.logical(native)), unname(as.logical(value[locations])))
        }
        result <- source[c(1L, 2L, 3L)]
        .Call(C_dtatools_patch_vector, source, 1L, FALSE)
        expect_identical(result, value[c(1L, 2L, 3L)])
        result[2L] <- TRUE
        expect_identical(unname(as.logical(source[1:3])), c(FALSE, FALSE, NA))
        expect_identical(owned_atom_info(source)$backing, before)
    }
})

.check_optional_split_owned_atoms_173 <- function(include_dplyr) {
    for (value in owned_atom_fixtures()) {
        data <- dibble(x = value, keep = dta_double(1:4))
        source <- owned_atom_info(data$x)
        expect_false(source$exposed)
        if (include_dplyr) {
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
        }
        expect_null(attr(data$x, "label", exact = TRUE))
        expect_identical(attributes(data$x), attributes(value))
        expect_identical(typeof(data$x), typeof(value))
    }
    integers <- owned_atom_capture(c(1L, NA_integer_, 3L))
    sibling <- .metadata_copy(integers)
    expect_identical(typeof(sibling), "integer")
    expect_identical(owned_atom_info(integers)$backing, owned_atom_info(sibling)$backing)
    expect_identical(as.integer(sibling), c(1L, NA_integer_, 3L))
}

test_that("ordinary atom handles share flat backing with independent attributes", {
    .check_optional_split_owned_atoms_173(FALSE)
})

test_that("ordinary atom backing through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_owned_atoms_173(TRUE)
})
test_that("native owned string copies and renaming reuse validation facts", {
    for (value in owned_atom_fixtures()[c("string", "declared")]) {
        expected <- as.character(value)
        data <- dibble(x = value, other = value)
        original <- data
        owned_atom_scan_stats(TRUE)
        for (i in 1:50) {
            data <- copy_data(data)
            data <- reserve_columns(data, 8L)
            names(data) <- c("third", "other")
            names(data) <- c("x", "other")
        }
        expect_true(.Call(C_dtatools_owned_string_fits, data$x, 8))
        expect_identical(owned_atom_scan_stats(), c(0, 0))
        expect_identical(owned_atom_info(data$x)$depth, 1L)
        expect_identical(as.character(data$x), expected)
        expect_identical(as.character(original$x), expected)
        .Call(C_dtatools_owned_set_string, data$x, 1L, "new")
        expect_identical(as.character(data$x), c("new", expected[-1L]))
        expect_identical(as.character(original$x), expected)
        expect_identical(as.character(data$other), expected)
    }
})

test_that("unchanged owned string selectors reuse validation facts", {
    skip_if_not_installed("dplyr", "1.2.1")
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

.check_optional_split_owned_atoms_297 <- function(include_dplyr) {
    skip_if_not_installed("data.table")
    for (value in owned_atom_fixtures()) {
        foreign <- data.table::data.table(x = value)
        # data.table must supply ordinary foreign storage, never our handle.
        expect_null(owned_atom_info(foreign$x))
        expect_false(.is_altrep(foreign$x))
        original <- .deep_copy_value(foreign$x)
        direct <- as_dibble(foreign)
        source <- dibble(anchor = dta_double(1:4))
        if (include_dplyr) {
            transformed <- dplyr::mutate(source, x = foreign$x)
            callback <- dplyr::group_modify(source, function(.x, .y) tibble::tibble(x = foreign$x))
            bound <- dplyr::bind_cols(source, tibble::tibble(x = foreign$x))
        }
        base_bound <- cbind(source, data.frame(x = foreign$x))
        data.table::set(foreign, i = 1L, j = "x", value = foreign$x[2L])
        results <- if (include_dplyr) list(direct, transformed, callback, bound, base_bound) else
            list(direct, base_bound)
        for (result in results) {
            expect_identical(result$x, original)
            expect_false(is.null(owned_atom_info(result$x)))
        }
    }
}

test_that("foreign data.table atoms are captured at constructors and callback ingress", {
    .check_optional_split_owned_atoms_297(FALSE)
})

test_that("foreign atom ingress through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_owned_atoms_297(TRUE)
})
.check_optional_split_owned_atoms_319 <- function(include_dplyr) {
    for (value in owned_atom_fixtures()) for (version in c(2L, 3L)) {
        source <- dibble(x = value)
        result <- if (include_dplyr) dplyr::rename(source, y = x) else {
            copied <- copy_data(source)
            names(copied) <- "y"
            copied
        }
        restored <- unserialize(serialize(list(source, result), NULL, version = version))
        expect_identical(restored[[1L]]$x, value)
        expect_identical(restored[[2L]]$y, value)
        expect_null(owned_atom_info(restored[[1L]]$x))
        expect_null(owned_atom_info(restored[[2L]]$y))
        # as_dibble(existing_dibble) deliberately remains identity; an ordinary
        # operation recaptures restored plain payload while making its result.
        recaptured <- if (include_dplyr) dplyr::rename(restored[[1L]], x = x) else
            reserve_columns(restored[[1L]])
        expect_false(is.null(owned_atom_info(recaptured$x)))
        recaptured$x[1L] <- recaptured$x[2L]
        expect_identical(restored[[1L]]$x, value)
        expect_identical(restored[[2L]]$y, value)
        expect_identical(source$x, value)
    }
}

test_that("owned atom serialization restores values without live ownership records", {
    .check_optional_split_owned_atoms_319(FALSE)
})

test_that("serialized atom recapture through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_owned_atoms_319(TRUE)
})
.check_optional_split_owned_atoms_339 <- function(include_dplyr) {
    for (value in owned_atom_fixtures()[c("string", "declared", "logical")]) {
        data <- reserve_columns(dibble(x = value, y = value), n = 2L)
        alias <- data
        isolated <- if (include_dplyr) dplyr::rename(data, z = x) else {
            copied_result <- copy_data(data)
            names(copied_result)[1L] <- "z"
            copied_result
        }
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
}

test_that("ordinary base copies and explicit atom writes preserve both alias contracts", {
    .check_optional_split_owned_atoms_339(FALSE)
})

test_that("ordinary and explicit atom aliases through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_owned_atoms_339(TRUE)
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

.check_optional_split_owned_atoms_542 <- function(include_dplyr) {
    for (value in owned_atom_fixtures()[c("factor", "ordered")]) {
        source <- reserve_columns(dibble(x = value), n = 1L)
        result <- if (include_dplyr) dplyr::rename(source, y = x) else {
            copied <- copy_data(source)
            names(copied) <- "y"
            copied
        }
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
}

test_that("factor ownership preserves existing replacement restrictions and levels", {
    .check_optional_split_owned_atoms_542(FALSE)
})

test_that("factor replacement and levels through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_owned_atoms_542(TRUE)
})
.check_optional_split_owned_atoms_564 <- function(include_dplyr) {
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
        if (include_dplyr) selected <- dplyr::rename(source, y = x)
        expect_identical(owned_atom_info(source$x)$backing, before)
        if (typeof(value) %in% c("character", "logical")) {
            replace_values(source, x, source$x[2L], where = 1L)
        } else source$x[1L] <- source$x[2L]
        source_after <- .deep_copy_value(source$x)
        expect_identical(out, expected)
        if (include_dplyr) expect_identical(selected$y, value)
        out[2L] <- out[1L]
        expect_identical(source$x, source_after)
        if (include_dplyr) expect_identical(selected$y, value)
    }
    for (value in owned_atom_fixtures()[c("string", "declared")]) {
        source <- dibble(x = value)
        before <- owned_atom_info(source$x)$backing
        out <- as.character(source$x)
        if (include_dplyr) selected <- dplyr::rename(source, y = x)
        expect_identical(owned_atom_info(source$x)$backing, before)
        replace_values(source, x, "r", where = 1L)
        expect_identical(out, as.character(value))
        out[2L] <- "export"
        if (include_dplyr) expect_identical(selected$y, value)
    }
}

test_that("public atom exports and source mutations remain symmetrically isolated", {
    .check_optional_split_owned_atoms_564(FALSE)
})

test_that("public atom export isolation through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_owned_atoms_564(TRUE)
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
    for (format in c("dta", "arrow")) for (kind in c("dictionary", "string", "integer", "logical", "double")) {
        data <- if (kind == "dictionary") read_arrow(fixture, output = "tibble") else
            tibble::tibble(x = switch(kind, string = owned_atom_capture(c("alpha", "beta", "alpha")),
                                    integer = owned_atom_capture(c(1L, 2L, 3L)),
                                    logical = owned_atom_capture(c(TRUE, FALSE, NA)),
                                    double = dta_double(c(1, 2, 3))))
        data$y <- c("a", "b", "c")
        specification <- if (format == "dta") .prepare_dta_write(data, NULL, 2045L, TRUE) else
            .prepare_arrow_write(data, NULL, TRUE)
        value <- specification[[3L]][[1L]]$values
        if (kind == "dictionary") expect_true(.is_unmaterialized_dictstring(value))
        expected <- if (kind %in% c("dictionary", "string")) c("alpha", "beta", "alpha") else
            if (kind == "logical") c(1, 0, NA_real_) else c(1, 2, 3)
        if (!is.null(owned_atom_info(value))) .metadata_copy(value)
        callback <- function() {
            if (kind == "dictionary") .force_altrep_materialization(value) else
                if (!is.null(owned_atom_info(value))) .Call(C_dtatools_patch_vector, value, NULL,
                    if (typeof(value) == "character") "changed" else if (typeof(value) == "logical") FALSE else
                        if (typeof(value) == "integer") 9L else 9)
            gc()
        }
        specification[[3L]][[2L]]$name <- .Call(C_dtatools_callback_character, "y", callback)
        path <- tempfile(fileext = paste0(".", format))
        withr::defer(unlink(path))
        if (format == "dta") .Call(C_dtatools_write, specification, path) else
            .Call(C_dtatools_save_arrow, specification, path, "uncompressed", 1L, TRUE)
        restored <- if (format == "dta") read_dta(path) else read_arrow(path)
        actual <- if (kind %in% c("dictionary", "string")) as.character(restored$x) else as.double(restored$x)
        expect_identical(actual, expected)
        expect_identical(as.character(restored$y), c("a", "b", "c"))
    }
})

test_that("DTA planning retains already UTF-8 owned strings without a payload copy", {
    for (raw in list(c("a", "\u00e9", ""), c("a", NA_character_, ""))) {
        value <- owned_atom_capture(raw)
        before <- owned_atom_info(value)
        plan <- .Call(C_dtatools_write_string_plan, value)
        expect_identical(plan[1:2], list(if (anyNA(raw)) 1 else 2, as.double(sum(is.na(raw)))))
        expect_identical(as.vector(plan[[3L]]), raw)
        expect_identical(owned_atom_info(plan[[3L]])$backing, before$backing)
        expect_identical(owned_atom_info(value), before)
    }
})

test_that("writer specifications isolate initially private strings from public callback writes", {
    for (format in c("dta", "arrow")) {
        data <- dibble(x = dta_string(rep("old", 3L), "str12"), y = c("a", "b", "c"))
        replace_values(data, x, c("alpha", "beta", "alpha"))
        expect_true(.Call(C_dtatools_mutation_info, data, 1L)$backing_private)
        specification <- if (format == "dta") .prepare_dta_write(data, NULL, 2045L, TRUE) else
            .prepare_arrow_write(data, NULL, TRUE)
        calls <- 0L
        callback <- function() {
            calls <<- calls + 1L
            replace_values(data, x, "changed")
            gc()
        }
        specification[[3L]][[2L]]$name <- .Call(C_dtatools_callback_character, "y", callback)
        path <- tempfile(fileext = paste0(".", format))
        withr::defer(unlink(path))
        if (format == "dta") .Call(C_dtatools_write, specification, path) else
            .Call(C_dtatools_save_arrow, specification, path, "uncompressed", 1L, TRUE)
        restored <- if (format == "dta") read_dta(path) else read_arrow(path)
        expect_identical(calls, 1L)
        expect_identical(as.character(data$x), rep("changed", 3L))
        expect_identical(as.character(restored$x), c("alpha", "beta", "alpha"))
    }
})

test_that("Arrow readers adopt fresh logical and factor allocations", {
    for (value in list(c(TRUE, FALSE, NA), factor(c("a", "b", NA)),
                       ordered(c("a", "b", NA), levels = c("b", "a", "unused")))) {
        path <- tempfile(fileext = ".arrow")
        withr::defer(unlink(path))
        save_arrow(tibble::tibble(x = value), path)
        .Call(C_dtatools_native_copy_stats, TRUE)
        result <- read_arrow(path)
        stats <- .Call(C_dtatools_native_copy_stats, FALSE)
        expect_identical(as.vector(result$x), as.vector(value))
        expect_identical(attributes(result$x), attributes(value))
        expect_false(is.null(owned_atom_info(result$x)))
        expect_equal(stats[["owned_capture"]], 0)
    }
})

test_that("fresh unnamed string construction keeps its first write private", {
    for (rows in c(1L, 64L, 1000L)) for (collect in c(FALSE, TRUE)) {
        raw <- rep("aa", rows)
        value <- dta_string(raw, "str4")
        if (collect) gc()
        before <- owned_atom_info(value)
        expect_false(before$shared)
        .Call(C_dtatools_native_copy_stats, TRUE)
        .Call(C_dtatools_owned_set_string, value, 1L, "zz")
        copies <- .Call(C_dtatools_native_copy_stats, FALSE)
        expect_identical(copies[["owned_capture"]], 0)
        expect_identical(owned_atom_info(value)$backing, before$backing)
        expect_identical(as.character(value), c("zz", rep("aa", rows - 1L)))
        expect_identical(raw, rep("aa", rows))
        expect_identical(attributes(value), list(stata.string.storage = "str4",
            class = c("dta_string", "vctrs_vctr", "character")))
    }
})

test_that("constructing from an owned string preserves real aliases in both directions", {
    source <- dta_string(rep("aa", 64L), "str4")
    result <- dta_string(source, "str8")
    expect_identical(owned_atom_info(result)$backing, owned_atom_info(source)$backing)
    expect_true(owned_atom_info(result)$shared)
    .Call(C_dtatools_owned_set_string, result, 1L, "longer")
    expect_identical(as.character(source), rep("aa", 64L))
    .Call(C_dtatools_owned_set_string, source, 2L, "bb")
    expect_identical(as.character(result), c("longer", rep("aa", 63L)))
    expect_identical(attr(source, "stata.string.storage"), "str4")
    expect_identical(attr(result, "stata.string.storage"), "str8")
})

test_that("internal string construction captures before forcing metadata promises", {
    skip_if_not_installed("data.table")
    for (argument in c("storage", "prototype")) {
        foreign <- data.table::data.table(x = rep("aa", 64L))
        change <- function(result) {
            data.table::set(foreign, i = 1L, j = "x", value = "bb")
            gc()
            result
        }
        value <- if (argument == "storage") .new_dta_string(foreign$x, change("str4")) else
            .new_dta_string(foreign$x, "str4", prototype = change(NULL))
        expect_identical(as.character(value), rep("aa", 64L))
        expect_identical(foreign$x, c("bb", rep("aa", 63L)))
        .Call(C_dtatools_owned_set_string, value, 2L, "cc")
        expect_identical(foreign$x, c("bb", rep("aa", 63L)))
    }
})

test_that("named string construction preserves replacement dispatch and escaped aliases", {
    escaped <- NULL
    calls <- 0L
    method <- function(x, value) {
        calls <<- calls + 1L
        if (is.null(escaped)) escaped <<- x
        attr(x, "names") <- paste0("custom-", value)
        x
    }
    table <- get(".__S3MethodsTable__.", envir = baseenv())
    registerS3method("names<-", "dta_string", method, envir = baseenv())
    withr::defer(rm(list = "names<-.dta_string", envir = table))
    raw <- stats::setNames(rep("aa", 64L), as.character(seq_len(64L)))
    value <- dta_string(raw, "str4")
    expect_identical(calls, 1L)
    expect_identical(names(value), paste0("custom-", names(raw)))
    # Generic names assignment can return R's foreign metadata wrapper, whose
    # established mutation API is ordinary R replacement.
    value[1L] <- "bb"
    expect_identical(unname(as.character(escaped)), rep("aa", 64L))
    escaped[2L] <- "cc"
    expect_identical(unname(as.character(value)), c("bb", rep("aa", 63L)))
    expect_identical(unname(raw), rep("aa", 64L))
})

test_that("owned width scans preserve encoded bytes and missingness", {
    latin <- iconv("\u00e9\u00f1", to = "latin1")
    Encoding(latin) <- "latin1"
    bytes <- latin
    Encoding(bytes) <- "bytes"
    for (text in list("ascii", enc2utf8(latin), latin, bytes)) {
        raw <- rep(text, 1000L)
        value <- owned_atom_capture(raw)
        expected <- max(nchar(enc2utf8(raw), type = "bytes"))
        expect_identical(.Call(C_dtatools_owned_string_width, value), expected)
        expect_identical(value, raw)
        .Call(C_dtatools_owned_set_string, value, 1L, NA_character_)
        expect_true(is.na(.Call(C_dtatools_owned_string_width, value)))
    }
})

test_that("large string constructors and restoration retain owned facts", {
    for (rows in c(63L, 64L, 1000L)) {
        raw <- rep(c("alpha", "", "\u00e9"), length.out = rows)
        value <- dta_string(raw, "str8")
        expect_false(is.null(owned_atom_info(value)))
        source <- owned_atom_info(value)$backing
        for (result in list(value[seq_len(rows)], vctrs::vec_slice(value, seq_len(rows)))) {
            expect_false(is.null(owned_atom_info(result)))
            expect_identical(as.character(result), raw)
            expect_identical(attributes(result), attributes(value))
            owned_atom_scan_stats(TRUE)
            expect_true(.string_declaration_holds(result))
            expect_identical(owned_atom_scan_stats(), c(0, 0))
        }
        expect_identical(owned_atom_info(value)$backing, source)
        annotated <- .set_dta_string_attribute(value, "label", "restored")
        expect_identical(owned_atom_info(annotated)$backing, source)
        expect_null(attr(value, "label", exact = TRUE))
        .Call(C_dtatools_owned_set_string, annotated, 1L, "new")
        expect_identical(as.character(value), raw)
        expect_identical(as.character(annotated), c("new", raw[-1L]))
        .Call(C_dtatools_owned_set_string, value, 2L, "source")
        expect_identical(as.character(annotated), c("new", raw[-1L]))
    }
})

test_that("owned string metadata leaves names replacement dispatch to R", {
    calls <- 0L
    method <- function(x, value) {
        calls <<- calls + 1L
        attr(x, "names") <- paste0("custom-", value)
        x
    }
    table <- get(".__S3MethodsTable__.", envir = baseenv())
    registerS3method("names<-", "stage4_owned_names", method, envir = baseenv())
    withr::defer(rm(list = "names<-.stage4_owned_names", envir = table))
    value <- .set_dta_string_attribute(owned_atom_capture(c("a", "b")), "class", "stage4_owned_names")
    expect_null(.set_dta_string_attribute(value, "names", c("first", "second")))
    expect_identical(calls, 0L)
    result <- .restore_dta_variable_metadata(value, character(), names = c("first", "second"))
    expect_identical(calls, 1L)
    expect_identical(names(result), c("custom-first", "custom-second"))
    expect_null(names(value))
    expect_identical(class(value), "stage4_owned_names")
})

test_that("string metadata declines compact storage without changing its source", {
    path <- tempfile(fileext = ".arrow")
    withr::defer(unlink(path))
    raw <- rep(sprintf("text-%03d", seq_len(128L)), 4L)
    save_arrow(data.frame(x = raw), path)
    value <- read_arrow(path)$x
    expect_true(.is_unmaterialized_dictstring(value))
    cache <- .dictstring_cached_count(value)
    expect_null(.set_dta_string_attribute(value, "label", "later"))
    expect_null(attr(value, "label", exact = TRUE))
    expect_identical(.dictstring_cached_count(value), cache)
    prototype <- set_var_labels(value, "source label")
    result <- .new_dta_string(value[integer()], "str8", prototype)
    ordinary <- .new_dta_string(character(), "str8", prototype)
    expect_identical(result, ordinary)
    # Compact restoration keeps the existing class position before the label.
    expect_identical(attributes(result), list(stata.string.storage = "str8",
        class = c("dta_string", "vctrs_vctr", "character"), label = "source label"))
    expect_true(.is_unmaterialized_dictstring(value))
    expect_identical(.dictstring_cached_count(value), cache)
    expect_identical(as.character(value), raw)
})

test_that("large string construction captures borrowed values before removing metadata", {
    skip_if_not_installed("data.table")
    for (rows in c(64L, 1000L, 1000000L)) for (unknown in c(FALSE, TRUE)) {
        raw <- rep(c("a", "b"), length.out = rows)
        foreign <- data.table::data.table(x = rep(c("a", "b"), length.out = rows))
        if (unknown) data.table::setattr(foreign$x, "class", "stage4_removed_string_class")
        key <- iconv("caf\u00e9", to = "latin1")
        Encoding(key) <- "latin1"
        data.table::setattr(foreign$x, key, "remove")
        data.table::setattr(foreign$x, enc2utf8("ol\u00e9"), "also remove")
        value <- dta_string(foreign$x, "str8")
        expect_false(is.null(owned_atom_info(value)))
        expect_identical(attributes(value), list(stata.string.storage = "str8",
            class = c("dta_string", "vctrs_vctr", "character")))
        data.table::set(foreign, i = 1L, j = "x", value = "changed")
        expect_identical(as.character(value), raw)
        .Call(C_dtatools_owned_set_string, value, 2L, "new")
        expect_identical(as.character(value), c("a", "new", raw[-(1:2)]))
        expect_identical(as.character(foreign$x), c("changed", raw[-1L]))
    }
})

test_that("string construction validates values captured after declaration callbacks", {
    skip_if_not_installed("data.table")
    for (replacement in list(NA_character_, "wide", "bb")) {
        foreign <- data.table::data.table(x = rep("a", 64L))
        calls <- 0L
        callback <- function() {
            calls <<- calls + 1L
            data.table::set(foreign, i = 1L, j = "x", value = replacement)
            gc()
        }
        storage <- .Call(C_dtatools_callback_character, "str3", callback)
        if (is.na(replacement)) expect_error(dta_string(foreign$x, storage), "NA_character_") else
            if (replacement == "wide") expect_error(dta_string(foreign$x, storage), "str3 storage cannot represent") else {
                result <- dta_string(foreign$x, storage)
                expect_identical(as.character(result), c("bb", rep("a", 63L)))
                expect_true(.string_declaration_holds(result))
                data.table::set(foreign, i = 1L, j = "x", value = "late")
                expect_identical(as.character(result), c("bb", rep("a", 63L)))
            }
        expect_identical(calls, 1L)
    }
})

test_that("Arrow UTF-8 readiness reads current owned strings and retains conversion fallbacks", {
    value <- owned_atom_capture(c("ascii", "\u00e9", NA_character_))
    before <- owned_atom_info(value)
    result <- .arrow_utf8(value, "test column")
    expect_identical(result, value)
    expect_identical(owned_atom_info(result), before)
    latin1 <- iconv("\u00e9", to = "latin1")
    Encoding(latin1) <- "latin1"
    .Call(C_dtatools_owned_set_string, value, 1L, latin1)
    converted <- .arrow_utf8(value, "test column")
    expect_identical(as.vector(converted), c("\u00e9", "\u00e9", NA_character_))
    expect_identical(Encoding(converted)[1L], "UTF-8")
    expect_identical(Encoding(value)[1L], "latin1")
    bytes <- "caf\u00e9"
    Encoding(bytes) <- "bytes"
    expect_identical(Encoding(bytes), "bytes")
    .Call(C_dtatools_owned_set_string, value, 1L, bytes)
    expect_error(.arrow_utf8(value, "test column"), "test column cannot contain strings with `bytes` encoding")
})

test_that("Arrow UTF-8 preflight retains its original fallback when base conversion is traced", {
    value <- owned_atom_capture(c("a", "\u00e9"))
    calls <- fallback_calls <- 0L
    # Match the original compiled fallback. R may compile enc2utf8 as a direct
    # builtin call, so tracing that name alone need not run its tracer.
    reference <- function(value, what) {
        .arrow_reject_bytes(value, what)
        enc2utf8(value)
    }
    environment(reference) <- asNamespace("dtatools")
    reference <- compiler::cmpfun(reference)
    trace("enc2utf8", tracer = function() calls <<- calls + 1L, where = baseenv(), print = FALSE)
    withr::defer(untrace("enc2utf8", where = baseenv()))
    trace(".arrow_reject_bytes", tracer = function() fallback_calls <<- fallback_calls + 1L,
          where = asNamespace("dtatools"), print = FALSE)
    withr::defer(untrace(".arrow_reject_bytes", where = asNamespace("dtatools")))
    expected <- reference(value, "test column")
    expected_calls <- calls
    expect_identical(fallback_calls, 1L)
    calls <- fallback_calls <- 0L
    result <- .arrow_utf8(value, "test column")
    expect_identical(calls, expected_calls)
    expect_identical(fallback_calls, 1L)
    expect_identical(result, expected)
})


.check_optional_split_owned_atoms_984 <- function(include_dplyr) {
    exports <- list(data.frame = function(x) data.frame(x = x),
                    tibble = function(x) tibble::tibble(x = x))
    if (requireNamespace("data.table", quietly = TRUE)) {
        exports$data.table <- function(x) data.table::as.data.table(list(x = x))
    }
    for (value in owned_atom_fixtures()[c("string", "declared", "logical")]) for (kind in names(exports)) {
        source <- dibble(x = value)
        exported <- exports[[kind]](source$x)
        if (include_dplyr) selected <- dplyr::rename(source, y = x)
        replace_values(source, x, source$x[2L], where = 1L)
        source_after <- .deep_copy_value(source$x)
        expect_identical(exported$x, value)
        if (include_dplyr) expect_identical(selected$y, value)
        replacement <- if (is.character(value)) "r" else TRUE
        if (kind == "data.table") data.table::set(exported, i = 2L, j = "x", value = replacement) else
            replace_values(exported, x, replacement, where = 2L)
        expect_identical(source$x, source_after)
        if (include_dplyr) expect_identical(selected$y, value)
    }
}

test_that("table atom exports retain isolation under each explicit write API", {
    .check_optional_split_owned_atoms_984(FALSE)
})

test_that("table atom export isolation through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_owned_atoms_984(TRUE)
})