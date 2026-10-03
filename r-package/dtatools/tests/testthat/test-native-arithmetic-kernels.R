.native_arithmetic_reference <- function(op, x, y, minimum) {
    args <- vctrs::vec_recycle_common(as.double(x), as.double(y))
    values <- suppressWarnings(getExportedValue("base", op)(args[[1]], args[[2]]))
    values[is.na(args[[1]]) | is.na(args[[2]])] <- NA_real_
    dtatools:::.dta_computed(values, minimum)
}

.native_arithmetic_expect <- function(actual, expected) {
    expect_identical(dta_storage_type(actual), dta_storage_type(expected))
    expect_identical(names(actual), names(expected))
    expect_identical(writeBin(as.double(actual), raw(), size = 8L),
                     writeBin(as.double(expected), raw(), size = 8L))
}

.native_arithmetic_enable <- function(env = parent.frame()) {
    prior <- .Call(C_dtatools_test_numeric_size_minimum, 0L)
    withr::defer(.Call(C_dtatools_test_numeric_size_minimum, prior), envir = env)
}

.native_arithmetic_expect_entry <- function() {
    count <- .Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
    if (.dtatools_numeric_entry_expected()) expect_gt(count, 0)
    else expect_equal(count, 0)
}

test_that("compact arithmetic agrees with the ordinary public calculation", {
    .native_arithmetic_enable()
    constructors <- list(byte = dta_byte, int = dta_int, long = dta_long,
                         float = dta_float, double = dta_double)
    values <- c(-5, -1, -0, 0, 1, 3, 5, NA_real_, tagged_missing(c("a", "z")))
    for (kind in names(constructors)) {
        x <- constructors[[kind]](values)
        for (op in c("+", "-", "*", "/")) {
            operation <- getExportedValue("base", op)
            for (scalar in list(-2, -0, 0, 0.5, 3L, TRUE, NA_real_,
                                tagged_missing("b"), NaN, Inf)) {
                .native_arithmetic_expect(operation(x, scalar),
                    .native_arithmetic_reference(op, x, scalar, kind))
                .native_arithmetic_expect(operation(scalar, x),
                    .native_arithmetic_reference(op, scalar, x, kind))
            }
            for (other_kind in names(constructors)) {
                y <- constructors[[other_kind]](rev(values))
                minimum <- dtatools:::.dta_promote(kind, other_kind)
                .native_arithmetic_expect(operation(x, y),
                    .native_arithmetic_reference(op, x, y, minimum))
            }
        }
    }
})

test_that("compact arithmetic promotes the complete result and collapses invalid values", {
    .native_arithmetic_enable()
    cases <- list(
        list("*", dta_byte(c(50, 100)), 3, "int"),
        list("*", dta_int(c(100, 32740)), 2, "long"),
        list("/", dta_byte(c(1, 3)), 3, "float"),
        list("/", dta_long(c(1, 3)), 3, "double"),
        list("*", dta_float(c(1e20, 1)), 1e20, "double"),
        list("+", dta_long(2147483620), dta_float(1), "double"),
        list("+", dta_float(16777216), dta_float(1), "float")
    )
    for (case in cases) {
        actual <- getExportedValue("base", case[[1]])(case[[2]], case[[3]])
        expect_identical(dta_storage_type(actual), case[[4]])
        minimum <- dta_storage_type(case[[2]])
        if (inherits(case[[3]], "dta_numeric")) {
            minimum <- dtatools:::.dta_promote(minimum, dta_storage_type(case[[3]]))
        }
        .native_arithmetic_expect(actual,
            .native_arithmetic_reference(case[[1]], case[[2]], case[[3]], minimum))
    }
    x <- dta_double(c(0, 1, -1, .Machine$double.xmax / 2,
                      NA_real_, tagged_missing("z")))
    expect_identical(dtatools:::.tab_missing_codes(as.double(x / 0)),
                     rep(0L, length(x)))
    expect_identical(as.double(x * 4)[4], NA_real_)
    expect_identical(as.double(x / Inf), c(0, 0, 0, 0, NA_real_, NA_real_))
})

test_that("arithmetic keeps recycling names and unsupported input behavior", {
    x <- dta_int(c(first = 2, second = 3))
    for (op in c("+", "-", "*", "/")) {
        operation <- getExportedValue("base", op)
        expected <- .native_arithmetic_reference(op, unname(x), 2, "int")
        names(expected) <- names(x)
        .native_arithmetic_expect(operation(x, 2), expected)
        expect_error(operation(x, c(1, 2, 3)), class = "vctrs_error_incompatible_size")
        expect_length(operation(dta_byte(numeric()), 2), 0)
        expect_length(operation(2, dta_byte(numeric())), 0)
        scalar <- dta_byte(2)
        vector <- dta_int(c(3, 4))
        .native_arithmetic_expect(operation(scalar, vector),
            .native_arithmetic_reference(op, scalar, vector, "int"))
    }
    calls <- character()
    expect_error(dtatools:::.dta_arith_base(
        { calls <- c(calls, "operator"); stop("operator forced") },
        dta_byte(c(1, 2)), dta_int(c(1, 2, 3)), "int"
    ), class = "vctrs_error_incompatible_size")
    expect_identical(calls, character())
})

test_that("arithmetic crosses retained chunks without changing source storage", {
    values <- rep(c(-3, -1, 0, 2, 4, NA_real_, tagged_missing(letters)), 67L)
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        for (chunk_rows in c(1, 7, 1024)) {
            x <- .Call(C_dtatools_owned_numeric_freeze, constructor(values), chunk_rows)
            y <- .Call(C_dtatools_owned_numeric_freeze, constructor(rev(values)), chunk_rows + 2)
            before <- .Call(C_dtatools_owned_numeric_info, x)[["compatibility_bytes"]]
            gc()
            for (op in c("+", "-", "*", "/")) {
                result <- getExportedValue("base", op)(x, y)
                .native_arithmetic_expect(result,
                    .native_arithmetic_reference(op, values, rev(values), dta_storage_type(x)))
            }
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(y))
            expect_equal(.Call(C_dtatools_owned_numeric_info, x)[["compatibility_bytes"]],
                         before)
        }
    }
})

test_that("extended arithmetic keeps primitive and recycling callbacks", {
    .native_arithmetic_enable()
    source <- dta_byte(c(1, 2))
    for (op in c("*", "/")) {
        calls <- 0L
        trace(op, tracer = function() { calls <<- calls + 1L },
              where = baseenv(), print = FALSE)
        actual <- tryCatch(dtatools:::.dta_arith_base(op, source, 2, "byte"),
                           finally = untrace(op, where = baseenv()))
        expect_gt(calls, 0L)
        .native_arithmetic_expect(actual,
            .native_arithmetic_reference(op, source, 2, "byte"))
    }
    calls <- 0L
    trace("vec_recycle_common", tracer = function() { calls <<- calls + 1L },
          where = asNamespace("vctrs"), print = FALSE)
    actual <- tryCatch(source * source,
                       finally = untrace("vec_recycle_common", where = asNamespace("vctrs")))
    expect_identical(calls, 1L)
    expect_identical(as.double(actual), c(1, 4))
})

test_that("public scalar and column arithmetic enter the native producer", {
    skip_if_not(.dtatools_numeric_entry_expected())
    x <- dta_int(rep(c(1, 2, 3, NA_real_, tagged_missing("a")), length.out = 4096L))
    y <- dta_float(rep(c(2, 3, 4, 5, 6), length.out = 4096L))
    cases <- list(function() x * 2, function() 2 * x,
                  function() x / 2, function() 2 / x,
                  function() x + y, function() x - y,
                  function() x * y, function() x / y)
    for (operation in cases) {
        .Call(C_dtatools_numeric_entry_stats, TRUE)
        result <- operation()
        expect_s3_class(result, "dta_numeric")
        expect_gt(.Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]], 0)
    }
})

test_that("imported DTA and Arrow columns enter native arithmetic with display metadata", {
    values <- rep(c(-3, -1, 0, 2, 4), length.out = 4096L)
    source <- dibble(x = dta_int(values))
    attr(source$x, "format.stata") <- "%8.0g"
    attr(source$x, "label") <- "Arithmetic source"
    dta_path <- tempfile(fileext = ".dta")
    arrow_path <- tempfile(fileext = ".arrow")
    withr::defer(unlink(c(dta_path, arrow_path)))
    save_dta(source, dta_path)
    save_arrow(source, arrow_path)
    imported <- list(read_dta(dta_path)$x, read_arrow(arrow_path)$x)
    for (x in imported) {
        expect_identical(attr(x, "format.stata"), "%8.0g")
        expect_identical(attr(x, "label"), "Arithmetic source")
        for (operation in list(function() x * 2, function() x / 2,
                               function() x + x, function() x - x,
                               function() x * x, function() x / x)) {
            .Call(C_dtatools_numeric_entry_stats, TRUE)
            actual <- operation()
            if (.dtatools_numeric_entry_expected()) {
                expect_gt(.Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]], 0)
            } else {
                expect_equal(.Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]], 0)
            }
            expect_null(attr(actual, "format.stata"))
            expect_null(attr(actual, "label"))
        }
        .native_arithmetic_expect(x * 2,
            .native_arithmetic_reference("*", values, 2, "int"))
        .native_arithmetic_expect(x / 2,
            .native_arithmetic_reference("/", values, 2, "int"))
        for (op in c("+", "-", "*", "/")) {
            .native_arithmetic_expect(getExportedValue("base", op)(x, x),
                .native_arithmetic_reference(op, values, values, "int"))
        }
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
    }
})

test_that("extended arithmetic retains storage-specific names methods", {
    .native_arithmetic_enable()
    x <- dta_int(c(1, 2))
    calls <- 0L
    table <- get(".__S3MethodsTable__.", baseenv())
    key <- "names.dta_int"
    existed <- exists(key, table, inherits = FALSE)
    old <- if (existed) get(key, table, inherits = FALSE)
    withr::defer({
        if (existed) assign(key, old, table) else rm(list = key, envir = table)
    })
    registerS3method("names", "dta_int", function(x) {
        calls <<- calls + 1L
        c("first", "second")
    }, baseenv())
    for (op in c("+", "-", "*", "/")) {
        calls <- 0L
        actual <- getExportedValue("base", op)(x, 2)
        expect_gt(calls, 0L)
        expect_identical(names(actual), c("first", "second"))
        expect_identical(unname(as.double(actual)),
                         getExportedValue("base", op)(c(1, 2), 2))
    }
})

test_that("observed compact span arithmetic crosses distinct chunk boundaries", {
    .native_arithmetic_enable()
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        x_values <- rep(c(-5, -1, 0, 1, 3, 5), 97L)
        y_values <- rev(x_values)
        x <- .Call(C_dtatools_owned_numeric_freeze, constructor(x_values), 7L)
        y <- .Call(C_dtatools_owned_numeric_freeze, constructor(y_values), 11L)
        minimum <- dta_storage_type(x)
        for (op in c("+", "-", "*", "/")) {
            .native_arithmetic_expect(getExportedValue("base", op)(x, y),
                .native_arithmetic_reference(op, x_values, y_values, minimum))
        }
        .native_arithmetic_expect(x * 0.1,
            .native_arithmetic_reference("*", x_values, 0.1, minimum))
        .native_arithmetic_expect(3 / x,
            .native_arithmetic_reference("/", 3, x_values, minimum))
    }
})

test_that("legacy observed integer codes promote into modern arithmetic storage", {
    .native_arithmetic_enable()
    legacy <- read_dta(fixture("synthetic_v111.dta"), output = "tibble")
    for (column in c("b", "i")) {
        source <- legacy[[column]]
        values <- as.double(source)
        source <- source[!is.na(values)]
        values <- values[!is.na(values)]
        kind <- if (column == "b") "byte" else "int"
        expect_true(any(values > if (kind == "byte") 100 else 32740))
        attributes(source) <- list(
            class = dtatools:::.dta_storage_class(kind), stata.storage = kind
        )
        for (x in list(source, .Call(C_dtatools_owned_numeric_freeze, source, 1L))) {
            result <- x * 1
            expect_identical(as.double(result), values)
            expect_identical(dta_storage_type(result),
                             if (kind == "byte") "int" else "long")
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
        }
    }
})

test_that("specialized arithmetic keeps aliased inputs scalar directions and promotion", {
    constructors <- list(byte = dta_byte, int = dta_int, long = dta_long,
                         float = dta_float, double = dta_double)
    boundaries <- list(byte = c(-127, -1, 0, 1, 100),
                       int = c(-32767, -1, 0, 1, 32740),
                       long = c(-2147483647, -1, 0, 1, 2147483620),
                       float = c(-1e20, -0, 0, 1, 1e20),
                       double = c(-1e200, -0, 0, 1, 1e200))
    for (kind in names(constructors)) {
        constructor <- constructors[[kind]]
        x <- constructor(rep(boundaries[[kind]], length.out = 4096L))
        scalar <- constructor(2)
        for (op in c("+", "-", "*", "/")) {
            operation <- getExportedValue("base", op)
            for (pair in list(list(x, x), list(x, scalar), list(scalar, x))) {
                .Call(C_dtatools_numeric_entry_stats, TRUE)
                actual <- operation(pair[[1]], pair[[2]])
                if (.dtatools_numeric_entry_expected()) {
                    expect_gt(.Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]], 0)
                } else {
                    expect_equal(.Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]], 0)
                }
                .native_arithmetic_expect(actual,
                    .native_arithmetic_reference(op, pair[[1]], pair[[2]], kind))
            }
        }
        for (scalar in c(2, 0.5)) {
            .native_arithmetic_expect(x * scalar,
                .native_arithmetic_reference("*", x, scalar, kind))
            .native_arithmetic_expect(scalar * x,
                .native_arithmetic_reference("*", scalar, x, kind))
        }
    }
})

test_that("missing span arithmetic keeps all codes across scalar and column shapes", {
    .native_arithmetic_enable()
    values <- c(-3, -1, -0, 0, 1, 5, NA_real_, tagged_missing(letters))
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        x <- .Call(C_dtatools_owned_numeric_freeze, constructor(rep(values, 3)), 7L)
        y <- .Call(C_dtatools_owned_numeric_freeze, constructor(rep(rev(values), 3)), 11L)
        minimum <- dta_storage_type(x)
        gc()
        for (op in c("+", "-", "*", "/")) {
            operation <- getExportedValue("base", op)
            for (pair in list(list(x, y), list(y, x), list(x, x),
                              list(x, constructor(2)), list(constructor(2), x))) {
                .Call(C_dtatools_numeric_entry_stats, TRUE)
                actual <- operation(pair[[1]], pair[[2]])
                .native_arithmetic_expect_entry()
                .native_arithmetic_expect(actual,
                    .native_arithmetic_reference(op, pair[[1]], pair[[2]], minimum))
            }
        }
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(y))
    }
})

test_that("missing span arithmetic keeps each operand's legacy missing encoding", {
    .native_arithmetic_enable()
    legacy <- read_dta(fixture("synthetic_v111.dta"), output = "tibble")
    constructors <- list(b = dta_byte, i = dta_int, l = dta_long, f = dta_float)
    for (column in names(constructors)) {
        source <- legacy[[column]]
        kind <- dta_storage_type(source)
        attributes(source) <- list(class = dtatools:::.dta_storage_class(kind),
                                   stata.storage = kind)
        modern <- constructors[[column]](c(2, NA_real_, tagged_missing("z"), 3))
        for (retained in c(FALSE, TRUE)) {
            x <- if (retained) .Call(C_dtatools_owned_numeric_freeze, source, 1L) else source
            y <- if (retained) .Call(C_dtatools_owned_numeric_freeze, modern, 3L) else modern
            for (op in c("+", "-", "*", "/")) {
                for (pair in list(list(x, y), list(y, x))) {
                    .Call(C_dtatools_numeric_entry_stats, TRUE)
                    actual <- getExportedValue("base", op)(pair[[1]], pair[[2]])
                    .native_arithmetic_expect_entry()
                    .native_arithmetic_expect(actual,
                        .native_arithmetic_reference(op, pair[[1]], pair[[2]],
                                                     dta_storage_type(x)))
                }
            }
        }
    }
})

test_that("float span arithmetic matches eager IEEE and reserved-code decoding", {
    .native_arithmetic_enable()
    bits <- c(0, 0x80000000, 0x3f800000, 0xbf800000,
              0x7effffff, 0x7f000000, 0x7f000001, 0x7f0007ff,
              0x7f000800, 0x7f00d000, 0x7f00d001, 0x7f7fffff,
              0x7f800000, 0xff800000, 0x7fc00001, 0xffc00001,
              0x7f800001, 0xff800001, 0xffffffff, 0xff7fffff)
    raw_bits <- function(value) as.raw(floor(value / 256^(0:3)) %% 256)
    modern <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    legacy <- tempfile(fileext = ".dta")
    withr::defer(unlink(c(modern, legacy)))
    compare <- function(path, column, count) {
        compact <- read_dta(path, col_select = tidyselect::all_of(column), n_max = count)[[column]]
        plain <- as.double(read_dta(path, col_select = tidyselect::all_of(column), n_max = count,
                                   use_numeric_altrep = FALSE)[[column]])
        for (x in list(compact, .Call(C_dtatools_owned_numeric_freeze, compact, 3L))) {
            before <- writeBin(as.double(x), raw(), size = 8L)
            one <- dta_float(rep(1, count))
            for (op in c("+", "-", "*", "/")) {
                operation <- getExportedValue("base", op)
                .Call(C_dtatools_numeric_entry_stats, TRUE)
                actual <- operation(one, x)
                .native_arithmetic_expect_entry()
                .native_arithmetic_expect(actual,
                    .native_arithmetic_reference(op, rep(1, count), plain, "float"))
                .native_arithmetic_expect(operation(x, one),
                    .native_arithmetic_reference(op, plain, rep(1, count), "float"))
            }
            # A vector of ones declines the scalar scaling route. Exercise
            # that route explicitly, including provisional float overflow
            # that must be recomputed in double after whole-column promotion.
            expect_scaled <- function(op, left, right, left_values, right_values,
                                      minimum = "float") {
                .Call(C_dtatools_numeric_entry_stats, TRUE)
                actual <- getExportedValue("base", op)(left, right)
                .native_arithmetic_expect_entry()
                expected <- .native_arithmetic_reference(op, left_values, right_values, minimum)
                .native_arithmetic_expect(actual, expected)
                expected_missing <- is.na(as.double(expected))
                expect_identical(is.na(actual), expected_missing)
                expect_identical(anyNA(actual), any(expected_missing))
                if (any(expected_missing)) {
                    # Clearing the actual missing rows must also clear its
                    # cached count. An overcount can survive correct bytes.
                    data <- dibble(x = actual)
                    replace_values(data, x = 0, where = which(expected_missing))
                    cleared <- as.double(expected)
                    cleared[expected_missing] <- 0
                    expect_false(anyNA(data$x))
                    expect_identical(as.double(data$x), cleared)
                }
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
                expect_false(.Call(C_dtatools_is_materialized_numeric_altrep, x))
            }
            for (scalar in c(-2, 2, -2^30, 2^30, 1.01, -3.25, 1 / 3)) {
                expect_scaled("*", x, scalar, plain, scalar)
                expect_scaled("*", scalar, x, scalar, plain)
                expect_scaled("/", x, scalar, plain, scalar)
                expect_scaled("/", scalar, x, scalar, plain)
            }
            for (scalar in c(0, -0, 0.1, -1e38, 1e39)) {
                for (op in c("+", "-", "*")) {
                    expect_scaled(op, x, scalar, plain, scalar)
                    expect_scaled(op, scalar, x, scalar, plain)
                }
            }
            for (op in c("+", "-", "*", "/")) {
                expect_scaled(op, x, x, plain, plain)
            }
            # Raw imported maxima remain available here, unlike a constructor
            # that normalizes values outside Stata's observed float range.
            # Their products and quotients by the smallest subnormal exercise
            # the full physical bounds used to prove binary64 results safe.
            tiny <- dta_float(rep(2^-149, count))
            expect_scaled("/", x, tiny, plain, rep(2^-149, count))
            expect_scaled("/", tiny, x, rep(2^-149, count), plain)
            half <- dta_float(rep(0.5, count))
            expect_scaled("*", x, half, plain, rep(0.5, count))
            expect_scaled("*", half, x, rep(0.5, count), plain)
            # Distinct physical widths use the compact pair producer. Keep
            # the full binary64 byte comparison: negative and zero numerators
            # divided by observed +/-Inf must retain the zero sign, whereas
            # legacy +Inf, NaNs and reserved codes propagate system missing.
            for (kind in c("int", "long")) {
                constructor <- get(paste0("dta_", kind))
                minimum <- dtatools:::.dta_promote("float", kind)
                for (values in list(rep(-1, count), rep(0, count),
                    rep(c(-2, 0, 2, NA_real_, tagged_missing(c("a", "z"))),
                        length.out = count))) {
                    y <- .Call(C_dtatools_owned_numeric_freeze, constructor(values), 5L)
                    y_before <- writeBin(as.double(y), raw(), size = 8L)
                    for (op in c("+", "-", "*", "/")) {
                        expect_scaled(op, x, y, plain, values, minimum)
                        expect_scaled(op, y, x, values, plain, minimum)
                    }
                    expect_identical(writeBin(as.double(y), raw(), size = 8L), y_before)
                    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(y))
                }
            }
            expect_identical(writeBin(as.double(x), raw(), size = 8L), before)
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
        }
    }
    # Every modern reserved code is missing, but its immediate bit neighbors
    # are observed. The next aligned code after .z is also observed.
    reserved <- 0x7f000000 + (0:26) * 0x800
    modern_bits <- unique(c(bits, as.vector(outer(reserved, c(-1, 0, 1), "+")),
                            0x7f00d800))
    # Keep each patch within the fixture's 27 known rows, and qualify its
    # partial final batch independently so no stale patched row is inspected.
    for (batch in split(modern_bits, ceiling(seq_along(modern_bits) / 27L))) {
        for (index in seq_along(batch)) {
            patch_numeric_fixture_row(modern, index - 1L,
                                      list(x_float = raw_bits(batch[[index]])))
        }
        compare(modern, "x_float", length(batch))
    }

    original <- readBin(fixture("synthetic_v111.dta"), "raw",
                        n = file.info(fixture("synthetic_v111.dta"))[["size"]])
    prefix <- c(as.raw(1), writeBin(321L, raw(), size = 2L, endian = "little"),
                writeBin(-123456L, raw(), size = 4L, endian = "little"),
                writeBin(1.5, raw(), size = 4L, endian = "little"),
                writeBin(-2.25, raw(), size = 8L, endian = "little"))
    start <- grepRaw(prefix, original, fixed = TRUE, all = TRUE)
    expect_length(start, 1L)
    for (batch in split(bits, ceiling(seq_along(bits) / 4L))) {
        bytes <- original
        for (row in seq_along(batch)) {
            location <- start + (row - 1L) * 25L + 7L
            bytes[location + 0:3] <- raw_bits(batch[[row]])
        }
        writeBin(bytes, legacy)
        compare(legacy, "f", length(batch))
    }
})

test_that("compact pair promotion recomputes earlier chunks and counts missing unions", {
    .native_arithmetic_enable()
    values <- rep(c(1 + 2^-23, -0, 0, 2, NA_real_, tagged_missing(letters)),
                  length.out = 131L)
    values[[131L]] <- 1e38
    x <- .Call(C_dtatools_owned_numeric_freeze, dta_float(values), 7L)
    y_values <- rep(c(3, 2, -2, NA_real_, tagged_missing(rev(letters))),
                    length.out = length(values))
    y_values[[131L]] <- 2
    y <- .Call(C_dtatools_owned_numeric_freeze, dta_int(y_values), 11L)
    before <- lapply(list(x, y), function(value) writeBin(as.double(value), raw(), size = 8L))
    .Call(C_dtatools_numeric_entry_stats, TRUE)
    actual <- x * y
    .native_arithmetic_expect_entry()
    expected <- .native_arithmetic_reference("*", x, y, "float")
    expect_identical(dta_storage_type(actual), "double")
    .native_arithmetic_expect(actual, expected)
    # The first exact product differs from its once-rounded float value.
    # Late promotion must discard that provisional rounding in every chunk.
    expect_identical(as.double(actual)[[1L]], (1 + 2^-23) * 3)
    expect_false(identical(as.double(actual)[[1L]], as.double(dta_float((1 + 2^-23) * 3))))
    missing <- is.na(as.double(expected))
    expect_identical(is.na(actual), missing)
    result <- dibble(x = actual)
    replace_values(result, x = 0, where = which(missing))
    expect_false(anyNA(result$x))
    expect_identical(lapply(list(x, y), function(value) writeBin(as.double(value), raw(), size = 8L)), before)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(y))
})

test_that("rounded float multiplication limits retain exact binary64 storage decisions", {
    .native_arithmetic_enable()
    from_bits <- function(bits) readBin(as.raw(floor(bits / 256^(0:3)) %% 256),
                                       "double", n = 1L, size = 4L, endian = "little")
    # Both products round to the largest observed float. The exact first
    # product is above that limit, while the second is below it. A rounded
    # equality alone must therefore never choose the storage type.
    witnesses <- list(
        list(value = from_bits(0x7d3a2e8b), multiplier = 11, storage = "double"),
        list(value = from_bits(0x7cd79435), multiplier = 19, storage = "float")
    )
    limit <- from_bits(0x7effffff)
    expect_gt(witnesses[[1L]]$value * 11, limit)
    expect_lt(witnesses[[2L]]$value * 19, limit)
    for (witness in witnesses) {
        expect_identical(readBin(writeBin(witness$value * witness$multiplier,
            raw(), size = 4L), "double", n = 1L, size = 4L), limit)
        for (kind in c("byte", "int", "float")) {
            for (sign in c(-1, 1)) {
                for (retained in c(FALSE, TRUE)) {
                    values <- rep(c(1 + 2^-23, -0, 0, NA_real_, tagged_missing(letters)),
                                  length.out = 131L)
                    values[[131L]] <- sign * witness$value
                    multipliers <- rep(c(3, -2, 0, NA_real_, tagged_missing("z")),
                                       length.out = 131L)
                    multipliers[[131L]] <- witness$multiplier
                    x <- dta_float(values)
                    y <- get(paste0("dta_", kind))(multipliers)
                    if (retained) {
                        x <- .Call(C_dtatools_owned_numeric_freeze, x, 7L)
                        y <- .Call(C_dtatools_owned_numeric_freeze, y, 11L)
                    }
                    before <- lapply(list(x, y), function(value)
                        writeBin(as.double(value), raw(), size = 8L))
                    expected <- .native_arithmetic_reference("*", x, y, "float")
                    expect_identical(dta_storage_type(expected), witness$storage)
                    for (reverse in c(FALSE, TRUE)) {
                        .Call(C_dtatools_numeric_entry_stats, TRUE)
                        actual <- if (reverse) y * x else x * y
                        .native_arithmetic_expect_entry()
                        .native_arithmetic_expect(actual, expected)
                        missing <- is.na(as.double(expected))
                        expect_identical(is.na(actual), missing)
                        result <- dibble(x = actual)
                        replace_values(result, x = 0, where = which(missing))
                        expect_false(anyNA(result$x))
                        if (witness$storage == "double") {
                            expect_identical(as.double(actual)[[1L]], (1 + 2^-23) * 3)
                        }
                    }
                    expect_identical(lapply(list(x, y), function(value)
                        writeBin(as.double(value), raw(), size = 8L)), before)
                    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
                    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(y))
                }
            }
        }
    }
})

test_that("compact float sums preserve rounded binary64 fit and late promotion", {
    .native_arithmetic_enable()
    limit <- readBin(as.raw(c(255, 255, 255, 126)), "double", n = 1L,
                     size = 4L, endian = "little")
    # The storage contract uses the rounded binary64 expression. L + 1 is
    # above L as a rational number, but binary64 rounds it back to L. A
    # quarter float step remains above L in double while also rounding to L
    # in float. The first must retain float and the second must promote.
    expect_identical(limit + 1, limit)
    expect_gt(limit + 2^101, limit)
    expect_identical(readBin(writeBin(limit + 2^101, raw(), size = 4L),
                            "double", n = 1L, size = 4L), limit)
    witnesses <- list(
        list(delta = 1, storage = "float", kinds = c("byte", "int", "float")),
        list(delta = -1, storage = "float", kinds = c("byte", "int", "float")),
        list(delta = 2^101, storage = "double", kinds = "float"),
        list(delta = -2^101, storage = "float", kinds = "float"),
        list(delta = 2^103, storage = "double", kinds = "float")
    )
    for (witness in witnesses) for (kind in witness$kinds) {
        for (op in c("+", "-")) for (sign in c(-1, 1)) {
            operation <- getExportedValue("base", op)
            for (retained in c(FALSE, TRUE)) {
                values <- rep(c(1 + 2^-23, -0, 0, NA_real_, tagged_missing(letters)),
                              length.out = 131L)
                values[[131L]] <- sign * limit
                other <- rep(c(7, -2, 0, NA_real_, tagged_missing("z")),
                             length.out = 131L)
                other[[131L]] <- sign * witness$delta * if (op == "+") 1 else -1
                x <- dta_float(values)
                y <- get(paste0("dta_", kind))(other)
                if (retained) {
                    x <- .Call(C_dtatools_owned_numeric_freeze, x, 7L)
                    y <- .Call(C_dtatools_owned_numeric_freeze, y, 11L)
                }
                before <- lapply(list(x, y), function(value)
                    writeBin(as.double(value), raw(), size = 8L))
                for (reverse in c(FALSE, TRUE)) {
                    pair <- if (reverse) list(y, x) else list(x, y)
                    expected <- .native_arithmetic_reference(op, pair[[1L]], pair[[2L]], "float")
                    expect_identical(dta_storage_type(expected), witness$storage)
                    .Call(C_dtatools_numeric_entry_stats, TRUE)
                    actual <- operation(pair[[1L]], pair[[2L]])
                    .native_arithmetic_expect_entry()
                    .native_arithmetic_expect(actual, expected)
                    missing <- is.na(as.double(expected))
                    expect_identical(is.na(actual), missing)
                    result <- dibble(x = actual)
                    replace_values(result, x = 0, where = which(missing))
                    expect_false(anyNA(result$x))
                    if (witness$storage == "double") {
                        original <- if (reverse) operation(7, 1 + 2^-23) else
                            operation(1 + 2^-23, 7)
                        expect_identical(as.double(actual)[[1L]], original)
                        expect_false(identical(original, as.double(dta_float(original))))
                    }
                }
                expect_identical(lapply(list(x, y), function(value)
                    writeBin(as.double(value), raw(), size = 8L)), before)
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(y))
            }
        }
    }
})

test_that("compact float sums keep exponent-gap cancellation and zero bits", {
    .native_arithmetic_enable()
    pairs <- list()
    for (exponent in c(-119, -1, 0, 126)) for (gap in c(28, 29, 30, 31, 52, 53, 54)) {
        if (exponent - gap < -149) next
        for (neighbor in c(1 - 2^-24, 1, 1 + 2^-23)) {
            for (left_sign in c(-1, 1)) for (right_sign in c(-1, 1)) {
                pairs[[length(pairs) + 1L]] <- c(left_sign * 2^exponent * neighbor,
                                              right_sign * 2^(exponent - gap))
            }
        }
    }
    # Include exact cancellation, both zero signs, and adjacent subnormals.
    for (value in c(0, -0, 2^-149, 2^-126 - 2^-149, 2^-126, 1)) {
        pairs[[length(pairs) + 1L]] <- c(value, value)
        pairs[[length(pairs) + 1L]] <- c(value, -value)
    }
    values <- do.call(rbind, pairs)
    for (retained in c(FALSE, TRUE)) {
        x <- dta_float(values[, 1L])
        y <- dta_float(values[, 2L])
        if (retained) {
            x <- .Call(C_dtatools_owned_numeric_freeze, x, 7L)
            y <- .Call(C_dtatools_owned_numeric_freeze, y, 11L)
        }
        before <- lapply(list(x, y), function(value) writeBin(as.double(value), raw(), size = 8L))
        for (op in c("+", "-")) for (reverse in c(FALSE, TRUE)) {
            pair <- if (reverse) list(y, x) else list(x, y)
            .Call(C_dtatools_numeric_entry_stats, TRUE)
            actual <- getExportedValue("base", op)(pair[[1L]], pair[[2L]])
            .native_arithmetic_expect_entry()
            .native_arithmetic_expect(actual,
                .native_arithmetic_reference(op, pair[[1L]], pair[[2L]], "float"))
        }
        expect_identical(lapply(list(x, y), function(value)
            writeBin(as.double(value), raw(), size = 8L)), before)
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(y))
    }
})

test_that("integer reciprocal bounds preserve storage zero signs and missing caches", {
    .native_arithmetic_enable()
    float_limit <- (2^24 - 1) * 2^103
    double_limit <- .Machine$double.xmax / 2
    for (kind in c("byte", "int", "long")) {
        constructor <- get(paste0("dta_", kind))
        endpoints <- switch(kind, byte = c(-127, 100), int = c(-32767, 32740),
                            long = c(-2147483647, 2147483620))
        values <- rep(c(endpoints, -1, 0, 1, 3, NA_real_, tagged_missing(letters)),
                      length.out = 257L)
        scalars <- as.list(c(0, -0, 1.01, -1.01, float_limit, -float_limit,
                            2^127, -2^127, double_limit, -double_limit,
                            .Machine$double.xmax, NA_real_, NaN, Inf, -Inf))
        # A typed scalar forces double output even when every quotient is an
        # integer. This exercises signed zero in the new floating writer.
        scalars <- c(scalars, lapply(c(0, -0, 1.01, -1.01, double_limit), dta_double),
                     list(tagged_missing("z")))
        for (retained in c(FALSE, TRUE)) {
            x <- constructor(values)
            if (retained) x <- .Call(C_dtatools_owned_numeric_freeze, x, 7L)
            before <- writeBin(as.double(x), raw(), size = 8L)
            for (scalar in scalars) {
                minimum <- if (inherits(scalar, "dta_numeric")) "double" else kind
                expected <- .native_arithmetic_reference("/", scalar, x, minimum)
                .Call(C_dtatools_numeric_entry_stats, TRUE)
                actual <- scalar / x
                .native_arithmetic_expect_entry()
                .native_arithmetic_expect(actual, expected)
                missing <- is.na(as.double(expected))
                expect_identical(is.na(actual), missing)
                result <- dibble(x = actual)
                replace_values(result, x = 0, where = which(missing))
                expect_false(anyNA(result$x))
            }
            expect_identical(writeBin(as.double(x), raw(), size = 8L), before)
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
        }
        for (n in c(16383L, 16384L, 16385L)) {
            values <- rep(1, n)
            values[[n]] <- 3
            x <- constructor(values)
            .native_arithmetic_expect(1 / x, .native_arithmetic_reference("/", 1, x, kind))
            expect_identical(dta_storage_type(1 / x), if (kind == "long") "double" else "float")
        }
    }
})
