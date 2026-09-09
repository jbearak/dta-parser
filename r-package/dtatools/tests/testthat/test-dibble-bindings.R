# Concrete Stage8 regressions derived from the retained predecessor and copied
# controls. Ordinary references below retain typed columns where that affects
# the public contract. No diagnostic recorder or copied implementation is used.

test_that("B01 rows verbs preserve ordering and explicit key policies", {
    x <- dibble(k = 1:3, value = c(10, NA_real_, 30))
    cases <- list(
        insert = list(y = dibble(k = 4:5, value = c(40, 50)),
            k = c(1, 2, 3, 4, 5), value = c(10, NA_real_, 30, 40, 50)),
        append = list(y = dibble(k = 2L, value = 22),
            k = c(1, 2, 3, 2), value = c(10, NA_real_, 30, 22)),
        update = list(y = dibble(k = 2L, value = 99),
            k = c(1, 2, 3), value = c(10, 99, 30)),
        patch = list(y = dibble(k = 2L, value = 99),
            k = c(1, 2, 3), value = c(10, NA_real_, 30)),
        upsert = list(y = dibble(k = c(2L, 4L), value = c(99, 40)),
            k = c(1, 2, 3, 4), value = c(10, 99, 30, 40)),
        delete = list(y = dibble(k = 2L), k = c(1, 3), value = c(10, 30)))
    for (verb in names(cases)) {
        case <- cases[[verb]]
        fn <- getExportedValue("dplyr", paste0("rows_", verb))
        out <- if (verb == "append") fn(x, case$y) else fn(x, case$y, by = "k")
        expect_true(is_dibble(out))
        expect_identical(as.double(out$k), case$k)
        expect_identical(as.double(out$value), case$value)
        expect_identical(attr(out$value, "stata.storage"), "double")
    }
    # A typed system missing follows the existing typed coalesce policy.
    ordinary <- tibble::tibble(k = 1:3, value = c(10, NA_real_, 30))
    expect_identical(dplyr::rows_patch(ordinary, tibble::tibble(k = 2L, value = 99),
        by = "k")$value, c(10, 99, 30))
    expect_error(dplyr::rows_insert(x, dibble(k = 1L, value = 99), by = "k"),
        class = "rlang_error")
    ignored <- dplyr::rows_insert(x, dibble(k = c(1L, 4L), value = c(99, 40)),
        by = "k", conflict = "ignore")
    expect_identical(as.double(ignored$k), c(1, 2, 3, 4))
    expect_identical(as.double(ignored$value), c(10, NA_real_, 30, 40))
    expect_error(dplyr::rows_update(x, dibble(k = 9L, value = 99), by = "k"),
        class = "rlang_error")
    expect_identical(as.double(dplyr::rows_update(x, dibble(k = 9L, value = 99),
        by = "k", unmatched = "ignore")$value), c(10, NA_real_, 30))
    expect_error(dplyr::rows_update(x, dibble(k = c(1L, 1L), value = c(40, 50)),
        by = "k"), class = "rlang_error")
    repeated <- dplyr::rows_update(dibble(k = c(1L, 1L), value = c(10, 20)),
        dibble(k = 1L, value = 99), by = "k")
    expect_identical(as.double(repeated$value), c(99, 99))
    expect_error(dplyr::rows_update(x, dibble(k = 1L, value = 99), by = "k",
        in_place = TRUE), class = "rlang_error")
    expect_identical(as.double(x$k), c(1, 2, 3))
    expect_identical(as.double(x$value), c(10, NA_real_, 30))
})

test_that("B02 rows match common keys without widening destination storage", {
    x <- dibble(k = dta_byte(1:2), value = dta_byte(c(10, 20)))
    expect_error(dplyr::rows_append(x, dibble(k = 3L, value = 200)), "dta_int")
    expect_error(dplyr::rows_update(x, dibble(k = 2L, value = 200), by = "k"), "dta_int")
    expect_error(dplyr::rows_upsert(x, dibble(k = 300, value = 99), by = "k"), "dta_int")
    out <- dplyr::rows_update(x, dibble(k = 2, value = 99), by = "k")
    expect_identical(as.double(out$value), c(10, 99))
    expect_identical(attr(out$k, "stata.storage"), "byte")
    expect_identical(attr(out$value, "stata.storage"), "byte")
    ignored <- dplyr::rows_update(x, dibble(k = 1.5, value = 99),
        by = "k", unmatched = "ignore")
    expect_identical(as.double(ignored$k), c(1, 2))
    expect_identical(as.double(ignored$value), c(10, 20))
    text <- dibble(k = 1:2, value = dta_string(c("a", "b"), "str1"))
    expect_error(dplyr::rows_append(text, dibble(k = 3L, value = "wider")), "str5")
    expect_identical(as.double(x$value), c(10, 20))
    expect_identical(as.character(text$value), c("a", "b"))
})

test_that("B03 column modification preserves grouping and typed replacements", {
    for (shape in c("grouped", "rowwise")) {
        x <- dibble(k = factor(c("a", "a", "b"), levels = c("a", "b", "c")),
            value = c(10, 20, 30))
        x <- if (shape == "grouped") dplyr::group_by(x, k, .drop = FALSE) else dplyr::rowwise(x, k)
        reference <- dtatools:::.reference_snapshot(x)
        for (cols in list(list(value = 7L),
            list(k = factor(c("b", "a", "a"), levels = c("a", "b", "c"))))) {
            actual_events <- expected_events <- character()
            expected <- withCallingHandlers(dplyr::dplyr_col_modify(reference, cols),
                dplyr_regroup = function(cnd) expected_events <<- c(expected_events, class(cnd)[[1L]]))
            out <- withCallingHandlers(dplyr::dplyr_col_modify(x, cols),
                dplyr_regroup = function(cnd) actual_events <<- c(actual_events, class(cnd)[[1L]]))
            expect_true(is_dibble(out))
            expect_identical(class(dtatools:::.reference_snapshot(out)), class(expected))
            expect_identical(as.character(out$k), as.character(expected$k))
            expect_identical(levels(out$k), c("a", "b", "c"))
            expect_identical(as.double(out$value), as.double(expected$value))
            expect_identical(dplyr::group_data(out), dplyr::group_data(expected))
            expect_identical(dplyr::group_vars(out), "k")
            if ("k" %in% names(cols)) {
                expect_identical(actual_events, expected_events)
            } else {
                # The typed replacement is promoted after ordinary assembly;
                # its grouped [[<- produces the retained extra regroup event.
                expect_identical(expected_events, character())
            }
            expect_identical(actual_events, if (shape == "grouped") "dplyr_regroup" else character())
        }
        expect_error(dplyr::dplyr_col_modify(x, list(k = NULL)))
        expect_error(dplyr::dplyr_col_modify(x, list(value = 1:2)),
            class = "vctrs_error_incompatible_size")
        expect_identical(as.double(x$value), c(10, 20, 30))
        expect_identical(as.character(x$k), c("a", "a", "b"))
    }
    x <- dibble(k = 1:2, value = c(10, 20))
    out <- dplyr::dplyr_col_modify(x, list(value = 7L, added = "x"))
    expect_identical(as.double(out$value), c(7, 7))
    expect_identical(attr(out$value, "stata.storage"), "double")
    expect_identical(as.character(out$added), c("x", "x"))
    expect_identical(attr(out$added, "stata.string.storage"), "str1")
    expect_identical(names(dplyr::dplyr_col_modify(x, list(value = NULL))), "k")
})

test_that("B04 rows honor public RHS brackets before assignment", {
    method_name <- "[.dtatools_binding_rhs_probe"
    if (exists(method_name, .GlobalEnv, inherits = FALSE)) stop("Test method already exists")
    events <- character()
    assign(method_name, function(x, i, ..., drop = FALSE) {
        events <<- c(events, paste(i, collapse = ","))
        mode <- attr(x, "probe_mode", exact = TRUE)
        if (mode == "error") stop("RHS bracket sentinel", call. = FALSE)
        if (mode == "warning") warning("RHS bracket warning", call. = FALSE)
        out <- NextMethod("[")
        if ("value" %in% names(out)) out$value <- out$value + 100
        out
    }, envir = .GlobalEnv)
    on.exit(rm(list = method_name, envir = .GlobalEnv), add = TRUE)
    fresh_y <- function(mode = "transform") structure(data.frame(k = 1:2, value = c(30, 40)),
        class = c("dtatools_binding_rhs_probe", "data.frame"), probe_mode = mode)
    for (verb in c("update", "patch", "upsert", "delete")) {
        x <- dibble(k = 1:2, value = c(10, NA_real_))
        fn <- getExportedValue("dplyr", paste0("rows_", verb))
        events <- character()
        expected <- suppressMessages(fn(dtatools:::.reference_snapshot(x), fresh_y(), by = "k"))
        expected_events <- events
        events <- character()
        y <- fresh_y()
        out <- suppressMessages(fn(x, y, by = "k"))
        actual_events <- events
        expect_identical(actual_events, expected_events)
        expect_identical(actual_events, if (verb == "delete") "1" else c("1", "2"))
        expect_identical(as.double(out$value), as.double(expected$value))
        expect_identical(as.double(out$value), switch(verb,
            update = c(130, 140), patch = c(10, NA_real_), upsert = c(130, 140), delete = double()))
        expect_identical(as.double(x$value), c(10, NA_real_))
        expect_identical(y$value, c(30, 40))
    }
    x <- dibble(k = 1:2, value = c(10, 20))
    expect_warning(dplyr::rows_delete(x, fresh_y("warning"), by = "k"), "RHS bracket warning")
    expect_error(dplyr::rows_update(x, fresh_y("error"), by = "k"), "RHS bracket sentinel")
})

test_that("B05 inherited column modification reaches custom reconstruction", {
    method_name <- "dplyr_reconstruct.dtatools_binding_reconstruct_probe"
    if (exists(method_name, .GlobalEnv, inherits = FALSE)) stop("Test method already exists")
    events <- character()
    assign(method_name, function(data, template) {
        events <<- c(events, "reconstruct")
        data$value <- data$value + 100
        attr(data, "label") <- "custom reconstruction"
        data
    }, envir = .GlobalEnv)
    on.exit(rm(list = method_name, envir = .GlobalEnv), add = TRUE)
    # Conversion strips arbitrary subclasses. Establish the supported test
    # boundary on fresh normalized columns and an explicitly valid marker.
    ordinary <- dtatools:::.reference_snapshot(dibble(k = 1:2, value = c(10, 20)))
    class(ordinary) <- c("dtatools_binding_reconstruct_probe", "data.frame")
    x <- dtatools:::.mark_reference_data(ordinary,
        dtatools:::.new_reference_state(ordinary, dibble = TRUE))
    expect_true(dtatools:::.reference_state_valid(x))
    reference <- dtatools:::.reference_snapshot(x)
    expect_identical(class(reference), c("dtatools_binding_reconstruct_probe", "data.frame"))
    events <- character()
    expected <- dplyr::dplyr_col_modify(reference, list(value = 7L))
    expected_events <- events
    events <- character()
    out <- dplyr::dplyr_col_modify(x, list(value = 7L))
    actual_events <- events
    expect_identical(actual_events, expected_events)
    expect_identical(actual_events, "reconstruct")
    expect_identical(as.double(out$value), c(107, 107))
    expect_identical(as.double(out$value), as.double(expected$value))
    expect_identical(attr(out, "label"), "custom reconstruction")
    expect_identical(attr(out, "label"), attr(expected, "label"))
    expect_identical(as.double(x$value), c(10, 20))
})

test_that("B06 base binding retains row alignment recycling and argument order", {
    for (make_factor in list(factor, ordered)) {
        out <- rbind(dibble(k = 1:2, f = make_factor(c("a", "b"), levels = c("a", "b"))),
            data.frame(k = 3L, f = make_factor("c", levels = c("b", "c"))))
        expect_true(is_dibble(out))
        expect_identical(as.character(out$f), c("a", "b", "c"))
        expect_identical(levels(out$f), c("a", "b", "c"))
        expect_identical(is.ordered(out$f), identical(make_factor, ordered))
    }
    x <- dibble(k = 1:2, value = c(10, 20))
    reordered <- rbind(x, data.frame(value = 30, k = 3L))
    matrix_rows <- rbind(x, matrix(c(3, 30), nrow = 1L,
        dimnames = list(NULL, c("k", "value"))))
    expect_identical(as.double(reordered$value), c(10, 20, 30))
    expect_identical(as.double(matrix_rows$value), c(10, 20, 30))
    expect_identical(as.double(reordered$k), c(1, 2, 3))
    expect_error(rbind(x, data.frame(k = 3L, other = 30)), "names")
    expect_identical(as.double(cbind(dibble(k = 1:2), extra = 7L)$extra), c(7, 7))
    expect_identical(as.double(cbind(dibble(k = 1:4), data.frame(extra = c(7L, 8L)))$extra), c(7, 8, 7, 8))
    expect_error(cbind(dibble(k = 1:3), data.frame(extra = c(7L, 8L))))
    expect_error(cbind(dibble(k = 1:2), data.frame(k = 3:4)))
    matrix_cols <- cbind(dibble(k = 1:2), matrix(11:14, nrow = 2L,
        dimnames = list(NULL, c("m1", "m2"))))
    expect_identical(names(matrix_cols), c("k", "m1", "m2"))
    expect_identical(as.double(matrix_cols$m2), c(13, 14))
    expect_identical(names(cbind(left = x, right = data.frame(a = 3:4, b = 5:6))),
        c("left.k", "left.value", "right.a", "right.b"))
    ordinary <- data.frame(k = 3:4, value = c(30, 40))
    ordinary_first <- rbind(ordinary, x)
    reference <- rbind(ordinary, dtatools:::.reference_snapshot(x))
    expect_false(is_dibble(ordinary_first))
    expect_identical(ordinary_first, reference)
    expect_identical(as.double(ordinary_first$value), c(30, 40, 10, 20))
    ordinary_cols <- cbind(data.frame(other = c(30, 40)), x)
    expect_false(is_dibble(ordinary_cols))
    expect_identical(ordinary_cols, cbind(data.frame(other = c(30, 40)),
        dtatools:::.reference_snapshot(x)))
})

test_that("B07 base binding selects the first applicable method", {
    method_names <- paste0(c("rbind", "cbind"), ".dtatools_binding_base_probe")
    if (any(vapply(method_names, exists, logical(1), envir = .GlobalEnv, inherits = FALSE)))
        stop("Test method already exists")
    events <- character()
    on.exit(rm(list = method_names, envir = .GlobalEnv), add = TRUE)
    for (generic in c("rbind", "cbind")) {
        method <- local({
            selected <- generic
            function(..., deparse.level = 1) {
                events <<- c(events, paste(selected, deparse.level, sep = ":"))
                data.frame(dispatched = rep(selected, 2L))
            }
        })
        assign(paste0(generic, ".dtatools_binding_base_probe"), method, .GlobalEnv)
    }
    for (generic in c("rbind", "cbind")) {
        fn <- getExportedValue("base", generic)
        left <- dibble(k = 1:2)
        right <- structure(if (generic == "rbind") data.frame(k = 3:4) else data.frame(other = 3:4),
            class = c("dtatools_binding_base_probe", "data.frame"))
        events <- character()
        out <- fn(left, right, deparse.level = 2L)
        expect_identical(events, character())
        expect_true(is_dibble(out))
        expect_identical(as.double(out$k), if (generic == "rbind") c(1, 2, 3, 4) else c(1, 2))
        events <- character()
        expected <- fn(right, dtatools:::.reference_snapshot(left), deparse.level = 2L)
        expected_events <- events
        events <- character()
        out <- fn(right, left, deparse.level = 2L)
        expect_identical(events, expected_events)
        expect_identical(events, paste0(generic, ":2"))
        expect_identical(out, expected)
        expect_identical(out$dispatched, rep(generic, 2L))
    }
})

test_that("B08 binding rows and column results isolate later payload and label writes", {
    skip_if_not_installed("data.table")
    snapshot <- function(column) {
        out <- numeric(length(column))
        for (i in seq_along(column)) out[[i]] <- as.double(column[[i]])
        out
    }
    for (verb in c("insert", "append", "update", "patch", "upsert", "delete", "rbind", "cbind", "col_modify")) {
        x <- dibble(k = 1:2, value = c(10, 20))
        y <- if (verb == "cbind") dibble(other = c(30, 40)) else
            dibble(k = if (verb %in% c("insert", "append", "rbind")) 3:4 else 1:2, value = c(30, 40))
        set_var_label(x, value, "left source")
        right_column <- if (verb == "cbind") "other" else "value"
        data.table::setattr(y[[right_column]], "label", "right source")
        out <- switch(verb, rbind = rbind(x, y), cbind = cbind(x, y),
            col_modify = dplyr::dplyr_col_modify(x, list(value = y$value)),
            delete = dplyr::rows_delete(x, dibble(k = 2L), by = "k"),
            append = dplyr::rows_append(x, y),
            getExportedValue("dplyr", paste0("rows_", verb))(x, y, by = "k"))
        before <- snapshot(out$value)
        data.table::set(out, i = 1L, j = "value", value = 99)
        data.table::setattr(out$value, "label", "result only")
        expected <- replace(before, 1L, 99)
        expect_identical(snapshot(out$value), expected)
        expect_identical(attr(out$value, "label"), "result only")
        expect_identical(snapshot(x$value), c(10, 20))
        expect_identical(attr(x$value, "label"), "left source")
        expect_identical(snapshot(y[[right_column]]), c(30, 40))
        expect_identical(attr(y[[right_column]], "label"), "right source")
        data.table::set(x, i = 1L, j = "value", value = 77)
        data.table::setattr(x$value, "label", "changed left")
        expect_identical(snapshot(x$value), c(77, 20))
        expect_identical(attr(x$value, "label"), "changed left")
        expect_identical(snapshot(out$value), expected)
        expect_identical(attr(out$value, "label"), "result only")
        expect_identical(snapshot(y[[right_column]]), c(30, 40))
        expect_identical(attr(y[[right_column]], "label"), "right source")
        if (!verb %in% c("delete", "cbind")) {
            data.table::set(y, i = 1L, j = right_column, value = 66)
            data.table::setattr(y[[right_column]], "label", "changed right")
            expect_identical(snapshot(y[[right_column]]), c(66, 40))
            expect_identical(attr(y[[right_column]], "label"), "changed right")
            expect_identical(snapshot(out$value), expected)
            expect_identical(attr(out$value, "label"), "result only")
            expect_identical(snapshot(x$value), c(77, 20))
            expect_identical(attr(x$value, "label"), "changed left")
        }
        if (verb == "cbind") {
            data.table::set(out, i = 1L, j = "other", value = 88)
            data.table::setattr(out$other, "label", "right result only")
            expect_identical(snapshot(out$other), c(88, 40))
            expect_identical(attr(out$other, "label"), "right result only")
            expect_identical(snapshot(y$other), c(30, 40))
            expect_identical(attr(y$other, "label"), "right source")
            data.table::set(y, i = 1L, j = "other", value = 66)
            data.table::setattr(y$other, "label", "changed right")
            expect_identical(snapshot(y$other), c(66, 40))
            expect_identical(attr(y$other, "label"), "changed right")
            expect_identical(snapshot(out$other), c(88, 40))
            expect_identical(attr(out$other, "label"), "right result only")
            expect_identical(snapshot(out$value), expected)
            expect_identical(snapshot(x$value), c(77, 20))
            expect_identical(attr(out$value, "label"), "result only")
            expect_identical(attr(x$value, "label"), "changed left")
        }
    }
})
