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
    for (index in seq_along(bits)) {
        patch_numeric_fixture_row(modern, index - 1L,
                                  list(x_float = raw_bits(bits[[index]])))
    }
    compare <- function(path, column, count) {
        compact <- read_dta(path, col_select = tidyselect::all_of(column), n_max = count)[[column]]
        plain <- as.double(read_dta(path, col_select = tidyselect::all_of(column), n_max = count,
                                   use_numeric_altrep = FALSE)[[column]])
        for (x in list(compact, .Call(C_dtatools_owned_numeric_freeze, compact, 3L))) {
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
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
        }
    }
    compare(modern, "x_float", length(bits))

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
