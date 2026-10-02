.numeric_match_reference <- function(x, table, nomatch = NA_integer_,
                                     incomparables = NULL) {
    kind <- dtatools:::.dta_common_identity_kind(x, table, "x", "table")
    x_key <- dtatools:::.dta_identity_key(x, kind, "x")
    table_key <- dtatools:::.dta_identity_key(table, kind, "table")
    incomparable_key <- if (is.null(incomparables)) NULL else {
        incomparable_kind <- dtatools:::.dta_common_identity_kind(
            x, incomparables, "x", "incomparables"
        )
        if (!identical(kind, incomparable_kind)) {
            stop("`incomparables` must have the same kind as `x` and `table`",
                 call. = FALSE)
        }
        dtatools:::.dta_identity_key(incomparables, kind, "incomparables")
    }
    result <- base::match(x_key, table_key, nomatch, incomparable_key)
    names(result) <- names(x)
    result
}

.numeric_match_capture <- function(expr) {
    warnings <- character()
    value <- tryCatch(withCallingHandlers(expr, warning = function(condition) {
        warnings <<- c(warnings, conditionMessage(condition))
        invokeRestart("muffleWarning")
    }), error = function(condition) conditionMessage(condition))
    list(value = value, warnings = warnings)
}

test_that("numeric matching preserves cross-width first matches and missing codes", {
    values <- c(-3, -0, 0, 2, 2, NA_real_, tagged_missing(letters), -3)
    table_values <- rev(c(values, 2, tagged_missing("a")))
    constructors <- list(identity, dta_byte, dta_int, dta_long,
                         dta_float, dta_double)
    for (left in constructors) for (right in constructors) {
        x <- left(values)
        table <- right(table_values)
        names(x) <- paste0("row", seq_along(x))
        for (excluded in list(NULL, c(0, NA_real_, tagged_missing(c("b", "z"))))) {
            expected <- .numeric_match_reference(x, table, -9L, excluded)
            expect_identical(dta_match(x, table, -9L, excluded), expected)
        }
        expect_identical(dta_in(x, table),
                         .numeric_match_reference(x, table, 0L) > 0L)
    }
    expect_identical(dta_match(c(TRUE, FALSE, NA), c(0L, NA, 1L)),
                     c(3L, 1L, 2L))
    expect_identical(dta_match(numeric(), numeric()), integer())
    expect_identical(dta_match(c(1, NA_real_), numeric(), 0L), c(0L, 0L))
    expect_identical(dta_match(NULL, NULL), integer())
})

test_that("numeric matching preserves scalar nomatch conversion and errors", {
    replacements <- list(NA_integer_, 0L, -11L, 3.8, "4", "bad", NULL,
                         integer(), c(2L, 3L), NA_real_, Inf, list(5))
    for (replacement in replacements) {
        expect_identical(
            .numeric_match_capture(dta_match(c(1, 2), 1, replacement)),
            .numeric_match_capture(.numeric_match_reference(c(1, 2), 1, replacement))
        )
    }
    for (bad in list(NaN, c(Inf, NaN), c(NaN, -Inf))) {
        expect_error(dta_match(bad, Inf, incomparables = "wrong"),
                     "`x` contains a noncanonical NaN", fixed = TRUE)
    }
    expect_error(dta_match(1, c(Inf, NaN), incomparables = "wrong"),
                 "`table` contains a noncanonical NaN", fixed = TRUE)
    expect_error(dta_match(1, Inf, incomparables = "wrong"),
                 "`table` contains an infinite value", fixed = TRUE)
    expect_error(dta_match(1, 2, nomatch = stop("nomatch forced"),
                          incomparables = NaN),
                 "`incomparables` contains a noncanonical NaN", fixed = TRUE)
    expect_error(dta_match(NaN, 2, incomparables = stop("incomparables forced")),
                 "`x` contains a noncanonical NaN", fixed = TRUE)
    expect_error(dta_match(1, "1", nomatch = stop("nomatch forced")),
                 "incompatible kinds")
})

test_that("numeric matching preserves temporal identity domains", {
    for (kind in c("date", "datetime")) {
        prototype <- if (kind == "date") {
            structure(as.Date(numeric(), origin = "1970-01-01"),
                      class = c("dta_temporal", "dta_date", "Date"),
                      stata.storage = "int", format.stata = "%td")
        } else {
            structure(as.POSIXct(numeric(), origin = "1970-01-01", tz = "UTC"),
                      class = c("dta_temporal", "dta_datetime", "POSIXct", "POSIXt"),
                      stata.storage = "long", format.stata = "%tc")
        }
        values <- c(-1, 0, 1, NA_real_, tagged_missing(c("a", "z")))
        if (kind == "datetime") values[1:3] <- values[1:3] - 315619200
        x <- dtatools:::.restore_dta_temporal(values, prototype,
                                             if (kind == "date") "int" else "long")
        table <- rev(x)
        expect_identical(dta_match(x, table), .numeric_match_reference(x, table))
        expect_identical(dta_match(x, table, incomparables = x[5]),
                         .numeric_match_reference(x, table, incomparables = x[5]))
    }
})

test_that("numeric matching traverses retained chunks without materializing sources", {
    values <- rep(c(-1, 0, 1, NA_real_, tagged_missing(letters)), 83L)
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        for (chunk_rows in c(1, 7, 1024)) {
            x <- .Call(C_dtatools_owned_numeric_freeze, constructor(values), chunk_rows)
            table <- .Call(C_dtatools_owned_numeric_freeze,
                           constructor(rev(values)), chunk_rows + 1)
            before <- .Call(C_dtatools_owned_numeric_info, x)[["compatibility_bytes"]]
            gc()
            expect_identical(dta_match(x, table),
                             .numeric_match_reference(values, rev(values)))
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(table))
            expect_equal(.Call(C_dtatools_owned_numeric_info, x)[["compatibility_bytes"]],
                         before)
        }
    }
})

test_that("later matching callbacks cannot change prepared earlier identities", {
    x <- .Call(C_dtatools_owned_numeric_freeze, dta_int(c(1, 2, 3)), 1)
    table <- .Call(C_dtatools_callback_double, c(3, 2, 1), function() {
        .Call(C_dtatools_mutate_first_numeric_altrep, x, 9)
        gc()
    }, FALSE)
    expect_identical(dta_match(x, table), c(3L, 2L, 1L))
    expect_identical(as.double(x), c(9, 2, 3))

    x <- dta_int(c(1, 2, 3))
    table <- dta_int(c(3, 2, 1))
    expect_identical(dta_match(x, table, incomparables = {
        .Call(C_dtatools_mutate_first_numeric_altrep, x, 9)
        .Call(C_dtatools_mutate_first_numeric_altrep, table, 9)
        gc()
        2
    }), c(3L, NA_integer_, 1L))
})

test_that("numeric matching retains foreign conversion dispatch", {
    calls <- 0L
    method <- function(x, ...) {
        calls <<- calls + 1L
        unclass(x) + 10
    }
    table <- get(".__S3MethodsTable__.", baseenv())
    key <- "as.double.dtatools_match_foreign"
    existed <- exists(key, table, inherits = FALSE)
    old <- if (existed) get(key, table, inherits = FALSE)
    withr::defer({
        if (existed) assign(key, old, table) else rm(list = key, envir = table)
    })
    registerS3method("as.double", "dtatools_match_foreign", method, baseenv())
    x <- structure(c(1, 2), class = "dtatools_match_foreign")
    expect_identical(dta_match(x, c(12, 11)), c(2L, 1L))
    expect_identical(calls, 1L)
})

test_that("matching rejects invalid numeric conversion results and keeps error calls", {
    for (value in list(NaN, Inf)) {
        error <- tryCatch(dta_match(value, 1), error = identity)
        expect_s3_class(error, "error")
        expect_null(conditionCall(error))
    }
    x <- dta_int(1)
    local_mocked_bindings(
        as.double.dta_numeric = function(x, ...) "n:0x1p+0",
        .package = "dtatools"
    )
    expect_error(dta_match(x, 1), "numeric vector")
})

test_that("numeric matching keeps exact finite double identities", {
    values <- c(-.Machine$double.xmax, -.Machine$double.xmin,
                -.Machine$double.xmin / 2, -0, 0,
                .Machine$double.xmin / 2, .Machine$double.xmin,
                1, 1 + .Machine$double.eps, .Machine$double.xmax)
    table <- c(rev(values), values)
    expect_identical(dta_match(values, table),
                     .numeric_match_reference(values, table))
    expect_identical(dta_match(values, table, incomparables = values[c(1, 5, 8)]),
                     .numeric_match_reference(values, table,
                                              incomparables = values[c(1, 5, 8)]))
})

test_that("numeric identity and sets share matching identity and stable order", {
    values <- c(2, -0, 0, 2, NA_real_, tagged_missing(c("a", "z", "a")))
    x <- dta_byte(values)
    y <- dta_int(c(tagged_missing("z"), 0, 3, NA_real_))
    attr(x, "label") <- "left metadata"
    expect_true(dta_identical(x, values))
    expect_false(dta_identical(x, rev(values)))
    expect_false(dta_identical(x, values[-1]))
    expect_true(dta_setequal(x, rev(x)))
    expect_false(dta_setequal(x, y))
    expect_true(dta_identical(dta_intersect(x, y),
                              c(0, NA_real_, tagged_missing("z"))))
    expect_true(dta_identical(dta_setdiff(x, y), c(2, tagged_missing("a"))))
    expect_true(dta_identical(dta_union(x, y),
                              c(2, 0, NA_real_, tagged_missing(c("a", "z")), 3)))
    expect_identical(attr(dta_intersect(x, y), "label"), "left metadata")
    expect_identical(dta_storage_type(dta_union(x, y)), "int")
})
