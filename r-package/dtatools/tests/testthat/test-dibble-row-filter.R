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
