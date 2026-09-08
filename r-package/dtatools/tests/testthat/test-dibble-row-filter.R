# Stage 6 row-operation regression coverage; adapted sources are in inst/NOTICE.
# Adapted policy cases: dplyr 95740975 tests/testthat/test-filter.R;
# package test-dibble-expressions.R; retained Stage 6 caller witnesses.

test_that("S6-F01 filter_out complements the completed TRUE-only conjunction", {
    data <- dibble(id = 1:9,
        a = rep(c(TRUE, FALSE, NA), each = 3),
        b = rep(c(TRUE, FALSE, NA), 3))
    expect_identical(.s6_ids(dplyr::filter(data, a, b)), 1L)
    expect_identical(.s6_ids(dplyr::filter_out(data, a, b)), 2:9)
    expect_identical(.s6_ids(dplyr::filter(data)), 1:9)
    expect_identical(.s6_ids(dplyr::filter_out(data)), integer())
    for (verb in list(dplyr::filter, dplyr::filter_out)) {
        events <- character()
        verb(data, { events <<- c(events, "first"); FALSE },
                   { events <<- c(events, "second"); TRUE })
        expect_identical(events, c("first", "second"))
        expect_error(verb(data, FALSE, stop("second forced")), "second forced")
    }
})

test_that("S6-F02 predicates validate type, size, names and dynamic dots", {
    data <- dibble(id = 1:3, a = c(TRUE, FALSE, NA))
    for (verb in list(dplyr::filter, dplyr::filter_out)) {
        expect_error(verb(data, 1L))
        expect_error(verb(data, c(TRUE, FALSE)), "size")
        expect_error(verb(data, integer()))
        expect_error(verb(data, a = id > 1), "named input")
        expect_error(verb(data, tibble::tibble(a = a)))
        expect_error(verb(data, dplyr::across(a, identity)))
        expect_error(verb(data, matrix(TRUE, 3L, 2L)))
        expect_error(verb(data, array(TRUE, c(3L, 1L, 1L))))
        expected <- if (identical(verb, dplyr::filter)) 1L else 2:3
        expect_identical(.s6_ids(verb(data, !!!list(a = c(TRUE, FALSE, NA)))), expected)
        expect_identical(.s6_ids(verb(data, array(c(TRUE, FALSE, NA)))), expected)
    }
    # The lifecycle option makes warning assertions independent of prior warnings.
    withr::local_options(lifecycle_verbosity = "warning")
    expect_warning(out <- dplyr::filter(data, matrix(c(TRUE, FALSE, NA), 3L)),
                   "one column matrices")
    expect_identical(.s6_ids(out), 1L)
})

test_that("S6-F03 filter and slice dots share a group-local temporary frame", {
    for (grouped in c(FALSE, TRUE)) {
        data <- dibble(id = 1:4, g = c(1, 1, 2, 2), x = 1:4)
        if (grouped) data <- dplyr::group_by(data, g)
        out <- dplyr::filter(data, { .stage6_keep <- x > min(x); TRUE }, .stage6_keep)
        expect_identical(.s6_ids(out), if (grouped) c(2L, 4L) else 2:4)
        out <- dplyr::slice(data, { .stage6_index <- 2L; .stage6_index },
                           .stage6_index - 1L)
        expect_identical(.s6_ids(out), if (grouped) c(2L, 1L, 4L, 3L) else c(2L, 1L))
        expect_false(any(c(".stage6_keep", ".stage6_index") %in% names(data)))
    }
    grouped <- dplyr::group_by(dibble(id = 1:4, g = c(1, 1, 2, 2)), g)
    # A binding made only in group 1 must not become visible in group 2.
    expect_error(dplyr::filter(grouped, {
        if (dplyr::cur_group_id() == 1L) .stage6_first_only <- TRUE
        TRUE
    }, .stage6_first_only), "stage6_first_only")
    expect_error(dplyr::slice(grouped, {
        if (dplyr::cur_group_id() == 1L) .stage6_first_index <- 1L
        1L
    }, .stage6_first_index), "stage6_first_index")
})

test_that("S6-F04 persistent grouping and .by retain distinct row-order policies", {
    data <- dibble(id = 1:4, g = c("b", "a", "b", "a"), x = c(1, 2, 3, 4))
    threshold <- 2
    out <- dplyr::filter(data, .data$x > .env$threshold, .by = g)
    expect_identical(.s6_ids(out), 3:4)
    expect_identical(dplyr::group_vars(out), character())
    grouped <- dplyr::group_by(data, g)
    expect_identical(.s6_ids(dplyr::filter(grouped, x > mean(x))), 3:4)
    expect_identical(.s6_ids(dplyr::slice(grouped, 1L)), c(2L, 1L))
    expect_identical(.s6_ids(dplyr::slice(data, 1L, .by = g)), c(1L, 2L))
    for (verb in list(dplyr::filter, dplyr::filter_out, dplyr::slice)) {
        expect_error(verb(data, .by = g, .preserve = TRUE), "preserve")
        expect_error(verb(grouped, .by = g), "grouped")
        expect_error(verb(dplyr::rowwise(data), .by = g), "rowwise")
        expect_error(verb(data, by = g))
    }
    out <- dplyr::filter(grouped, g == "b", .preserve = TRUE)
    expect_identical(as.character(dplyr::group_keys(out)$g), c("a", "b"))
    expect_identical(as.list(dplyr::group_rows(out)), list(integer(), 1:2))
    out <- dplyr::filter(grouped, g == "b")
    expect_identical(as.character(dplyr::group_keys(out)$g), "b")
})

test_that("S6-F05 empty groups execute the witnessed synthetic and real callbacks", {
    for (shape in c("zero", "drop", "retained", "rowwise", "by")) {
        data <- dibble(id = integer(), g = if (shape == "retained")
            factor(character(), levels = c("a", "b")) else integer())
        if (shape == "drop") data <- dplyr::group_by(data, g, .drop = TRUE)
        if (shape == "retained") data <- dplyr::group_by(data, g, .drop = FALSE)
        if (shape == "rowwise") data <- dplyr::rowwise(data, g)
        for (verb in c("filter", "slice")) {
            events <- list()
            observe <- function() { events[[length(events) + 1L]] <<- .s6_context(); NULL }
            out <- if (verb == "filter") {
                if (shape == "by") dplyr::filter(data, { observe(); logical() }, .by = g) else
                    dplyr::filter(data, { observe(); logical() })
            } else {
                if (shape == "by") dplyr::slice(data, { observe(); integer() }, .by = g) else
                    dplyr::slice(data, { observe(); integer() })
            }
            expect_identical(nrow(out), 0L)
            count <- if (shape == "retained") 2L else 1L
            expect_length(events, count)
            expect_identical(vapply(events, `[[`, integer(1), "id"), seq_len(count))
            expect_identical(vapply(events, `[[`, integer(1), "n"), rep(0L, count))
            expect_identical(lapply(events, `[[`, "rows"), rep(list(integer()), count))
            expect_identical(lapply(events, `[[`, "keys"),
                rep(list(if (shape == "zero") character() else "g"), count))
            expect_identical(lapply(events, `[[`, "g"),
                if (shape == "retained") list("a", "b") else list(character()))
            if (shape %in% c("drop", "rowwise")) expect_identical(nrow(dplyr::group_data(out)), 0L)
            if (shape == "retained") expect_identical(nrow(dplyr::group_data(out)), 2L)
            if (shape %in% c("zero", "by")) expect_identical(dplyr::group_vars(out), character())
        }
    }
})

test_that("S6-F06 top-level if helpers retain factory and predicate context order", {
    # Same fixture as the completed caller witness: ordering, not AND/OR discrimination.
    data <- dplyr::group_by(dibble(id = 1:4, g = c(1, 1, 2, 2),
        x = c(0, 1, 2, 3), y = c(1, 0, 3, 2)), g)
    for (helper in c("any", "all")) {
        events <- character()
        factory <- function() {
            events <<- c(events, paste0("factory:", dplyr::n(), ":", dplyr::cur_group_id()))
            function(x) {
                column <- tryCatch(dplyr::cur_column(), error = function(e) "unavailable")
                events <<- c(events, paste0("predicate:", dplyr::cur_group_id(), ":", column))
                x > 1
            }
        }
        out <- if (helper == "any") dplyr::filter(data, dplyr::if_any(c(x, y), factory())) else
            dplyr::filter(data, dplyr::if_all(c(x, y), factory()))
        expect_identical(.s6_ids(out), 3:4)
        expect_identical(events, c("factory:0:0", "predicate:1:unavailable",
            "predicate:1:unavailable", "predicate:2:unavailable", "predicate:2:unavailable"))
        events <- character()
        if (helper == "any") expect_error(dplyr::slice(data, dplyr::if_any(c(x, y), factory()))) else
            expect_error(dplyr::slice(data, dplyr::if_all(c(x, y), factory())))
        expect_identical(events, c("factory:2:1", "predicate:1:x", "predicate:1:y"))
    }
    # New source-derived discriminating fixture, not claimed as witnessed above.
    data <- dibble(id = 1:4, x = c(0, 1, 1, 0), y = c(1, 0, 1, 0))
    expect_identical(.s6_ids(dplyr::filter(data, dplyr::if_any(c(x, y), ~ .x > 0))), 1:3)
    expect_identical(.s6_ids(dplyr::filter(data, dplyr::if_all(c(x, y), ~ .x > 0))), 3L)
})

test_that("S6-F07 aliases and arbitrary helpers use the active group context", {
    data <- dplyr::group_by(dibble(id = 1:4, g = c("b", "a", "b", "a"),
        x = c(0, 1, 2, 3), y = c(1, 0, 3, 2)), g)
    size <- dplyr::n
    any <- dplyr::if_any
    helper <- function() size() == 2L && dplyr::cur_group_id() > 0L
    out <- dplyr::filter(data, helper(), any(c(x, y), ~ .x > 1))
    expect_identical(.s6_ids(out), 3:4)
    out <- dplyr::slice(data, { helper(); size() })
    expect_identical(.s6_ids(out), c(4L, 3L))
    rowwise <- dplyr::rowwise(dibble(id = 1:3, items = list(1:2, 1L, integer())))
    expect_identical(.s6_ids(dplyr::filter(rowwise, length(items) == 2L)), 1L)
    out <- dplyr::slice(rowwise, if (length(items) == 2L) 1L else integer())
    expect_identical(.s6_ids(out), 1L)
    expect_s3_class(out, "rowwise_df")
})

test_that("S6-F08 filter reduction avoids repeated full-size logical temporaries", {
    skip_if_not(capabilities("profmem"), "R memory profiling is unavailable")
    rows <- 100000L
    data <- dibble(x = rep(TRUE, rows))
    predicate <- rep(c(TRUE, FALSE), length.out = rows)
    expected <- seq.int(1L, rows, by = 2L)
    context <- .begin_dibble_result(data, "filter()", "rows")
    groups <- .dibble_expression_groups(data, rlang::quo(NULL))
    dots <- rlang::quos(.env$predicate)
    invoke <- function() .dibble_filter_locations(context, groups, rows, dots)
    expect_identical(invoke(), expected)
    path <- tempfile()
    on.exit(unlink(path), add = TRUE)
    Rprofmem(path)
    result <- tryCatch(invoke(), finally = Rprofmem(NULL))
    events <- readLines(path, warn = FALSE)
    sizes <- as.numeric(sub(" .*", "", events[grepl("^[0-9]+ :", events)]))
    expect_identical(result, expected)
    # The original R reduction allocated 3.42 MB for this precomputed predicate.
    # Leave room for group indices and runtime bookkeeping, while rejecting
    # the repeated full-length temporary vectors that caused the regression.
    expect_lte(sum(sizes), 12 * rows + 131072)
    expect_identical(as.logical(data$x), rep(TRUE, rows))
})

test_that("S6-F09 native reduction preserves predicate attributes and later evaluation", {
    data <- dibble(id = 1:6, g = c("b", "a", "b", "a", "b", "a"),
                   keep = c(TRUE, FALSE, NA, TRUE, FALSE, NA))
    predicate <- structure(c(TRUE, FALSE, NA, TRUE, FALSE, NA),
                           class = "s6_logical_predicate", note = "preserved")
    before <- attributes(predicate)
    alias <- predicate
    for (verb in list(dplyr::filter, dplyr::filter_out)) {
        expected <- if (identical(verb, dplyr::filter)) c(1L, 4L) else c(2L, 3L, 5L, 6L)
        expect_identical(.s6_ids(verb(data, .env$predicate)), expected)
        expect_identical(.s6_ids(verb(data, keep)), expected)
        events <- new.env(parent = emptyenv())
        events$ids <- integer()
        grouped <- dplyr::group_by(data, g)
        verb(grouped, FALSE, {
            events$ids <- c(events$ids, dplyr::cur_group_id())
            rep(NA, dplyr::n())
        })
        expect_identical(events$ids, 1:2)
        expect_error(verb(grouped, FALSE, stop("later group predicate")),
                     "later group predicate")
        expect_identical(.s6_ids(verb(data, keep)), expected)
    }
    expect_identical(attributes(predicate), before)
    expect_identical(predicate, alias)
    expect_identical(as.logical(data$keep), c(TRUE, FALSE, NA, TRUE, FALSE, NA))
})

test_that("S6-F10 private filter reduction rejects invalid inputs and expires", {
    start <- function(n) .Call(C_dtatools_filter_start, n)
    reduce <- function(state, rows, value) .Call(C_dtatools_filter_reduce, state, rows, value)
    finish <- function(state, inverse = FALSE) .Call(C_dtatools_filter_finish, state, inverse)
    for (n in list(-1L, NA_integer_, Inf, 1.5, integer(), "3")) {
        expect_error(start(n), "filter row count")
    }
    expect_error(reduce(NULL, 1L, TRUE), "filter reduction state")
    for (rows in list(0L, -1L, NA_integer_, 4L)) {
        expect_error(reduce(start(3L), rows, TRUE), "filter group row")
    }
    expect_error(reduce(start(3L), 1, TRUE), "filter reduction input")
    expect_error(reduce(start(3L), 1:3, c(TRUE, FALSE)), "filter reduction input")
    expect_error(reduce(start(3L), 1:3, 1L), "filter reduction input")
    expect_error(finish(start(3L), NA), "filter inversion")
    state <- start(3L)
    reduce(state, c(3L, 1L), c(FALSE, TRUE))
    reduce(state, 2L, NA)
    expect_identical(finish(state), 1L)
    expect_error(finish(state), "expired filter reduction state")
    expect_error(reduce(state, 1L, TRUE), "expired filter reduction state")
    expect_identical(finish(start(0L)), integer())
})

test_that("S6-F11 reduction state and owned predicates survive forced collection", {
    for (rows in list(1:4, NULL)) {
        data <- dibble(keep = c(TRUE, FALSE, NA, TRUE))
        predicate <- data$keep
        state <- .Call(C_dtatools_filter_start, 4L)
        invisible(gc())
        .Call(C_dtatools_filter_reduce, state, rows, predicate)
        rm(data)
        invisible(gc())
        .Call(C_dtatools_filter_reduce, state, c(4L, 1L), c(FALSE, TRUE))
        invisible(gc())
        expect_identical(.Call(C_dtatools_filter_finish, state, FALSE), 1L)
        expect_identical(as.logical(predicate), c(TRUE, FALSE, NA, TRUE))
    }
})

test_that("S6-F12 errors and R interrupts expire active masks before a later filter", {
    data <- dibble(id = 1:3, keep = c(TRUE, FALSE, NA))
    for (kind in c("error", "interrupt")) {
        captured <- new.env(parent = emptyenv())
        trigger <- if (kind == "error") function() stop("filter abort") else
            function() rlang::interrupt()
        # Interrupt after the first native update. This qualifies R unwinding
        # of an active state, not POSIX delivery inside the native loop.
        condition <- tryCatch(dplyr::filter(data, {
            captured$read <- function() keep
            TRUE
        }, trigger()), error = identity, interrupt = identity)
        expect_s3_class(condition, kind)
        expect_error(captured$read(), "Obsolete data mask")
        expect_identical(.s6_ids(dplyr::filter(data, keep)), 1L)
        expect_identical(as.logical(data$keep), c(TRUE, FALSE, NA))
    }
})

test_that("S6-F13 fresh ungrouped filtering avoids materializing group locations", {
    skip_if_not(capabilities("profmem"), "R memory profiling is unavailable")
    rows <- 100000L
    data <- dibble(x = rep(TRUE, rows))
    predicate <- rep(c(TRUE, FALSE), length.out = rows)
    context <- .begin_dibble_result(data, "filter()", "rows")
    dots <- rlang::quos(.env$predicate)
    invoke <- function(invert) .dibble_filter_locations(context,
        .dibble_expression_groups(data, rlang::quo(NULL)), rows, dots, invert)
    path <- tempfile()
    on.exit(unlink(path), add = TRUE)
    for (invert in c(FALSE, TRUE)) {
        expected <- seq.int(if (invert) 2L else 1L, rows, by = 2L)
        expect_identical(invoke(invert), expected)
        Rprofmem(path)
        actual <- tryCatch(invoke(invert), finally = Rprofmem(NULL))
        events <- readLines(path, warn = FALSE)
        sizes <- as.numeric(sub(" .*", "", events[grepl("^[0-9]+ :", events)]))
        expect_identical(actual, expected)
        # One byte per input row and half as many integer result locations.
        # Allow bookkeeping, but reject a fresh full-size integer group vector.
        expect_lte(sum(sizes), 4 * rows + 131072)
    }
    expect_identical(as.logical(data$x), rep(TRUE, rows))
})

test_that("S6-F14 contiguous reduction validates payloads and retains TRUE-only inversion", {
    reduce <- function(state, rows, value) .Call(C_dtatools_filter_reduce, state, rows, value)
    for (value in list(logical(), c(TRUE, FALSE), 1L, NULL,
                       new.env(parent = emptyenv()))) {
        state <- .Call(C_dtatools_filter_start, 3L)
        expect_error(reduce(state, NULL, value), "filter reduction input")
    }
    for (rows in list(TRUE, 1, new.env(parent = emptyenv()))) {
        state <- .Call(C_dtatools_filter_start, 3L)
        expect_error(reduce(state, rows, TRUE), "filter reduction input")
    }
    for (n in c(0L, 1L, 4L)) {
        value <- rep(c(TRUE, FALSE, NA, TRUE), length.out = n)
        for (inverse in c(FALSE, TRUE)) {
            state <- .Call(C_dtatools_filter_start, n)
            reduce(state, NULL, value)
            reduce(state, NULL, TRUE)
            expected <- which(if (inverse) !(value %in% TRUE) else value %in% TRUE)
            expect_identical(.Call(C_dtatools_filter_finish, state, inverse), expected)
            expect_error(reduce(state, NULL, TRUE), "expired filter reduction state")
            state <- .Call(C_dtatools_filter_start, n)
            reduce(state, NULL, FALSE)
            reduce(state, NULL, value)
            expect_identical(.Call(C_dtatools_filter_finish, state, inverse),
                             if (inverse) seq_len(n) else integer())
        }
    }
})
