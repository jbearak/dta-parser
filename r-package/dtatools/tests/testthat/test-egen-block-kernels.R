egen_block_freeze <- function(x, rows) {
    .Call(C_dtatools_owned_numeric_freeze, x, rows)
}

egen_block_ordinary <- function(x) {
    readBin(writeBin(as.double(x), raw(), size = 8L), "double", n = length(x))
}

test_that("egen block summaries agree with ordinary values across compact chunks", {
    pattern <- c(-3, 0, 5, NA_real_, tagged_missing(letters), 2)
    operations <- list(dta_mean, dta_min, dta_max, dta_total,
                       function(x) dta_min(x, missing = TRUE),
                       function(x) dta_max(x, missing = TRUE),
                       function(x) dta_total(x, missing = TRUE))
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        for (size in c(0L, 1L, 31L, 1023L, 1024L, 1025L, 4097L)) {
            values <- rep_len(pattern, size)
            source <- constructor(values)
            for (value in list(source, egen_block_freeze(source, 3),
                               egen_block_freeze(source, 1021))) {
                for (operation in operations) {
                    expect_identical(operation(value), operation(values))
                }
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
            }
        }
    }
})

test_that("egen row blocks preserve column order and all-missing policy", {
    pattern <- c(-3, 0, 5, NA_real_, tagged_missing(letters), 2)
    for (size in c(0L, 1L, 31L, 1023L, 1024L, 1025L, 4097L)) {
        values <- list(rep_len(pattern, size), rep_len(rev(pattern), size),
                       rep_len(c(NA_real_, 1, 2), size))
        compact <- list(egen_block_freeze(dta_byte(values[[1L]]), 7),
                        egen_block_freeze(dta_int(values[[2L]]), 1021),
                        egen_block_freeze(dta_float(values[[3L]]), 1025))
        expect_identical(dta_row_max(compact), dta_row_max(values))
        expect_identical(dta_row_total(compact), dta_row_total(values))
        expect_identical(dta_row_total(compact, missing = TRUE),
                         dta_row_total(values, missing = TRUE))
        expect_true(all(vapply(compact, dtatools:::.is_unmaterialized_numeric_altrep,
                               logical(1))))
    }
    missing <- list(egen_block_freeze(dta_byte(rep(NA_real_, 1025)), 3),
                    egen_block_freeze(dta_long(rep(tagged_missing("z"), 1025)), 7))
    expect_identical(dta_row_max(missing), rep(NA_real_, 1025))
    expect_identical(dta_row_total(missing), rep(0, 1025))
    expect_identical(dta_row_total(missing, missing = TRUE), rep(NA_real_, 1025))
})

test_that("egen blocks keep one ordered double accumulator across boundaries", {
    values <- c(rep(0, 4095L), 2^55, 1, -2^55, 1)
    for (chunk_rows in c(1, 1021, 4096, 4097)) {
        compact <- egen_block_freeze(dta_float(values), chunk_rows)
        expect_identical(dta_total(compact), 1)
        expect_identical(dta_mean(compact), 1 / length(values))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact))
    }
    columns <- lapply(c(2^55, 1, -2^55, 1), function(value) {
        egen_block_freeze(dta_float(rep(value, 4097)), 1021)
    })
    expect_identical(dta_row_total(columns), rep(1, 4097))
    expect_identical(dta_row_total(columns[c(1, 3, 2, 4)]), rep(2, 4097))
})

test_that("egen block extrema preserve all missing ranks and signed-zero ties", {
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        missing <- egen_block_freeze(constructor(c(tagged_missing(letters), NA_real_)), 7)
        expect_identical(dta_min(missing), NA_real_)
        expect_identical(dta_max(missing), NA_real_)
        expect_identical(dta_min(missing, missing = TRUE), NA_real_)
        expect_identical(dta_max(missing, missing = TRUE), tagged_missing("z"))
        expect_identical(dta_total(missing, missing = TRUE), NA_real_)
        expect_identical(dta_total(missing), 0)
    }
    bytes <- function(x) writeBin(x, raw(), size = 8L, endian = "little")
    for (values in list(c(-0, 0), c(0, -0))) {
        compact <- egen_block_freeze(dta_float(values), 1)
        expect_identical(bytes(dta_min(compact)), bytes(dta_min(values)))
        expect_identical(bytes(dta_max(compact)), bytes(dta_max(values)))
    }
})

test_that("egen block calculations keep legacy numeric missing domains", {
    for (version in c(105L, 108L, 110L, 111L)) {
        data <- read_dta(fixture(paste0("synthetic_v", version, ".dta")), output = "tibble")
        for (source in data) {
            if (!dtatools:::.is_unmaterialized_numeric_altrep(source)) next
            value <- egen_block_freeze(source, 1)
            plain <- egen_block_ordinary(source)
            for (operation in list(dta_mean, dta_min, dta_max, dta_total)) {
                expect_identical(operation(value), operation(plain))
            }
            expect_identical(dta_min(value, missing = TRUE), dta_min(plain, missing = TRUE))
            expect_identical(dta_max(value, missing = TRUE), dta_max(plain, missing = TRUE))
            expect_identical(dta_row_total(value, value), dta_row_total(plain, plain))
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
        }
    }
})

test_that("egen blocks preserve Stata temporal conversion order and strip metadata", {
    specs <- list(
        list(kind = 1L, storage = "int", origin = -3653,
             prototype = structure(double(), format.stata = "%td",
                                   class = c("dta_temporal", "dta_date", "Date"))),
        list(kind = 2L, storage = "long", origin = -315619200,
             prototype = structure(double(), format.stata = "%tc", tzone = "UTC",
                                   class = c("dta_temporal", "dta_datetime", "POSIXct", "POSIXt")))
    )
    for (spec in specs) {
        values <- rep_len(c(spec$origin + c(-1, 0, 1), NA_real_, tagged_missing("b")), 1025)
        source <- dtatools:::.construct_dta_numeric(values, NULL, spec$storage, temporal = spec$kind)
        source <- dtatools:::.attach_dta_temporal(source, spec$prototype, spec$storage)
        compact <- egen_block_freeze(source, 1021)
        plain <- structure(egen_block_ordinary(source),
                           class = if (spec$kind == 1L) "Date" else c("POSIXct", "POSIXt"))
        for (operation in list(dta_mean, dta_min, dta_max, dta_total)) {
            expect_identical(operation(compact), operation(plain))
        }
        expect_identical(dta_row_total(compact, compact), dta_row_total(plain, plain))
        expect_identical(dta_row_max(compact, compact), dta_row_max(plain, plain))
        expect_null(attributes(dta_row_total(compact)))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact))
    }
})

test_that("egen block admission preserves foreign row-major callback order", {
    events <- character()
    first <- .Call(C_dtatools_callback_integer_after, c(1L, 2L, 3L),
                   function() events <<- c(events, "first-row-two"), 1L)
    second <- .Call(C_dtatools_callback_double, c(4, 5, 6),
                    function() events <<- c(events, "second-row-one"), TRUE)
    compact <- egen_block_freeze(dta_int(c(7, 8, 9)), 1)
    expect_identical(dta_row_total(first, compact, second), c(12, 15, 18))
    expect_identical(events, c("second-row-one", "first-row-two"))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact))
})

test_that("egen block validation retains NaN policy and unsupported-tag rejection", {
    scope <- dtatools:::.dta_egen_evaluation
    previous <- scope$allow_nan
    on.exit(scope$allow_nan <- previous, add = TRUE)
    invalid_tag <- tagged_nan_for_test("A")
    for (allow in c(FALSE, TRUE)) {
        scope$allow_nan <- allow
        for (value in list(Inf, -Inf, invalid_tag)) {
            expect_error(dta_total(c(1, value)), "NaN|infinities")
            expect_error(dta_row_total(c(1, value), c(2, 3)), "NaN|infinities")
        }
        if (allow) {
            expect_identical(dta_total(c(1, NaN, 2)), 3)
            expect_identical(dta_row_total(c(1, NaN, 2)), c(1, 0, 2))
        } else {
            expect_error(dta_total(c(1, NaN, 2)), "NaN")
            expect_error(dta_row_total(c(1, NaN, 2)), "NaN")
        }
    }
    scope$allow_nan <- FALSE
    # Validation visits row one column two before row two column one.
    expect_error(dta_row_total(c(1, NaN), c(1e308, 0)), "Stata double storage")
    expect_error(dta_row_total(c(1, 1e308), c(NaN, 0)), "NaN|infinities")
})

test_that("egen blocks normalize compact IEEE NaNs only in calculation scope", {
    scope <- dtatools:::.dta_egen_evaluation
    previous <- scope$allow_nan
    on.exit(scope$allow_nan <- previous, add = TRUE)
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    patch_numeric_fixture_row(path, 0L, list(x_float = as.raw(c(1, 0, 192, 127))))
    patch_numeric_fixture_row(path, 1L, list(x_float = as.raw(c(1, 0, 192, 255))))
    patch_numeric_fixture_row(path, 2L, list(x_float = as.raw(c(0, 0, 128, 63))))
    source <- read_dta(path, col_select = "x_float", n_max = 3L)$x_float
    for (value in list(source, egen_block_freeze(source, 1))) {
        scope$allow_nan <- FALSE
        expect_error(dta_total(value), "NaN")
        expect_error(dta_row_total(value), "NaN")
        scope$allow_nan <- TRUE
        expect_identical(dta_mean(value), 1)
        expect_identical(dta_row_total(value), c(0, 0, 1))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
    }
})

test_that("egen scalar fallback retains foreign class callbacks and captured storage", {
    source <- egen_block_freeze(dta_int(c(1, 2, 3)), 1)
    calls <- 0L
    classes <- .Call(C_dtatools_callback_character, class(source), function() NULL)
    attr(source, "class") <- classes
    .Call(C_dtatools_arm_callback_character, classes, function() {
        calls <<- calls + 1L
        .force_altrep_materialization(source)
        gc()
    })
    expect_identical(.Call(C_dtatools_egen_summary, source, 3L, FALSE, FALSE), 6)
    expect_identical(calls, 1L)
    expect_identical(as.double(source), c(1, 2, 3))
})
