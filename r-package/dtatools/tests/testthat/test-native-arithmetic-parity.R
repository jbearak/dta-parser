.arithmetic_parity_enable <- function(env = parent.frame()) {
    prior <- .Call(C_dtatools_test_numeric_size_minimum, 0L)
    withr::defer(.Call(C_dtatools_test_numeric_size_minimum, prior), envir = env)
    # Settle the one-time helper profile before checking producer counters.
    invisible(dta_double(c(1, 2)) + 1)
}

.arithmetic_parity_bytes <- function(x) {
    writeBin(as.double(x), raw(), size = 8L, endian = "little")
}

.arithmetic_parity_source <- function(kind, values, chunk_rows = NULL) {
    source <- getExportedValue("dtatools", paste0("dta_", kind))(values)
    if (!is.null(chunk_rows)) {
        source <- .Call(C_dtatools_owned_numeric_freeze, source, chunk_rows)
    }
    source
}

.arithmetic_parity_expect <- function(op, x, y, minimum, storage, info) {
    # Match the existing ordinary arithmetic oracle. In particular, let the
    # established computed-result policy choose float rounding after the whole
    # result is known; do not reproduce the new kernel's fit calculation here.
    arguments <- vctrs::vec_recycle_common(as.double(x), as.double(y))
    operation <- getExportedValue("base", op)
    values <- suppressWarnings(operation(arguments[[1L]], arguments[[2L]]))
    values[is.na(arguments[[1L]]) | is.na(arguments[[2L]])] <- NA_real_
    expected <- dtatools:::.dta_computed(values, minimum)
    if (is.null(storage)) storage <- dta_storage_type(expected)
    expect_identical(dta_storage_type(expected), storage, info = info)

    sources <- Filter(function(value) inherits(value, "dta_numeric"), list(x, y))
    before <- lapply(sources, .arithmetic_parity_bytes)
    for (source in sources) {
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(source), info = info)
        expect_false(.Call(C_dtatools_is_materialized_numeric_altrep, source), info = info)
    }
    .Call(C_dtatools_numeric_entry_stats, TRUE)
    actual <- operation(x, y)
    count <- .Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
    expect_identical(count, if (.dtatools_numeric_entry_expected("scalar")) 1 else 0,
                     info = info)
    expect_identical(dta_storage_type(actual), storage, info = info)
    expect_identical(names(actual), names(expected), info = info)
    expect_identical(.arithmetic_parity_bytes(actual), .arithmetic_parity_bytes(expected),
                     info = info)
    for (index in seq_along(sources)) {
        expect_identical(.arithmetic_parity_bytes(sources[[index]]), before[[index]], info = info)
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(sources[[index]]), info = info)
        expect_false(.Call(C_dtatools_is_materialized_numeric_altrep, sources[[index]]),
                     info = info)
    }
    invisible(actual)
}

test_that("a final or boundary value promotes every earlier scalar result", {
    .arithmetic_parity_enable()
    triggers <- c(byte = 51, int = 16371, long = 1073741811, float = 1e38)
    destinations <- c(byte = "int", int = "long", long = "double", float = "double")
    layouts <- list(
        list(rows = 33L, chunk = NULL, trigger = 33L),
        list(rows = 33L, chunk = 7L, trigger = 7L),
        list(rows = 33L, chunk = 7L, trigger = 8L),
        list(rows = 33L, chunk = 7L, trigger = 33L),
        list(rows = 1025L, chunk = 1024L, trigger = 1024L),
        list(rows = 1025L, chunk = 1024L, trigger = 1025L),
        list(rows = 16385L, chunk = 16384L, trigger = 16384L),
        list(rows = 16385L, chunk = 16384L, trigger = 16385L)
    )
    for (kind in names(triggers)) {
        for (layout in layouts) {
            values <- rep(c(-3, -1, -0, 0, 1, 3), length.out = layout$rows)
            values[[layout$trigger]] <- triggers[[kind]]
            x <- .arithmetic_parity_source(kind, values, layout$chunk)
            info <- paste(kind, "rows", layout$rows, "trigger", layout$trigger,
                          "chunk", layout$chunk)
            .arithmetic_parity_expect("*", x, 2, kind, destinations[[kind]], info)
            .arithmetic_parity_expect("*", 2, x, kind, destinations[[kind]], info)
        }
    }
})

test_that("column promotion crosses independently chunked operands", {
    .arithmetic_parity_enable()
    triggers <- c(byte = 51, int = 16371, long = 1073741811, float = 1e38)
    destinations <- c(byte = "int", int = "long", long = "double", float = "double")
    for (kind in names(triggers)) {
        for (position in c(7L, 8L, 11L, 12L, 1025L)) {
            left <- rep(c(-1, 0, 1), length.out = 1025L)
            right <- -left
            left[[position]] <- right[[position]] <- triggers[[kind]]
            x <- .arithmetic_parity_source(kind, left, 7L)
            y <- .arithmetic_parity_source(kind, right, 11L)
            info <- paste(kind, "independent chunks, trigger", position)
            .arithmetic_parity_expect("+", x, y, kind, destinations[[kind]], info)
        }
        .arithmetic_parity_expect("+", x, x, kind, destinations[[kind]],
                                 paste(kind, "aliased operands, final trigger"))
    }
})

test_that("missing codes and negative limits do not hide the final promotion", {
    .arithmetic_parity_enable()
    negative_triggers <- c(byte = -64, int = -16384, long = -1073741824, float = -1e38)
    destinations <- c(byte = "int", int = "long", long = "double", float = "double")
    prefix <- c(-3, -1, -0, 0, 1, 3, NA_real_, tagged_missing(letters))
    for (kind in names(negative_triggers)) {
        for (chunk in list(NULL, 7L)) {
            info <- paste(kind, "all missing codes, chunk", chunk)
            x <- .arithmetic_parity_source(kind, c(prefix, negative_triggers[[kind]]), chunk)
            .arithmetic_parity_expect("*", x, 2, kind, destinations[[kind]], info)
            # A missing tail has no observed value that should force widening.
            missing_tail <- .arithmetic_parity_source(kind, c(prefix, tagged_missing("z")), chunk)
            actual <- .arithmetic_parity_expect("*", missing_tail, 1, kind, kind, info)
            expect_identical(dtatools:::.tab_missing_codes(as.double(actual)),
                             c(rep(NA_integer_, 6L), rep(0L, 28L)), info = info)
            reciprocal_storage <- if (kind == "long") "double" else "float"
            .arithmetic_parity_expect("/", 2, missing_tail, kind, reciprocal_storage, info)
        }
    }
})

test_that("fractional and large results choose storage for the complete column", {
    .arithmetic_parity_enable()
    maxima <- c(byte = 100, int = 32739, long = 2147483619)
    for (kind in names(maxima)) {
        for (reverse in c(FALSE, TRUE)) {
            values <- c(1, -1, maxima[[kind]], -0, 0, NA_real_, tagged_missing("z"))
            if (reverse) values <- rev(values)
            for (chunk in list(NULL, 3L)) {
                x <- .arithmetic_parity_source(kind, values, chunk)
                storage <- if (kind == "long") "double" else "float"
                .arithmetic_parity_expect("/", x, 2, kind, storage,
                                         paste(kind, "fraction and large integer", reverse, chunk))
            }
        }
    }

    # The early fractional result must not keep float rounding when a later
    # result forces double storage, and the reverse ordering must agree.
    for (position in c(1L, 1024L, 1025L)) {
        values <- rep(c(0.1, -0.3, 1, -0, 0), length.out = 1025L)
        values[[position]] <- 1e38
        for (chunk in list(NULL, 1024L)) {
            x <- .arithmetic_parity_source("float", values, chunk)
            .arithmetic_parity_expect("*", x, 1.9, "float", "double",
                                     paste("float fractional product, trigger", position, chunk))
        }
        multipliers <- rep(c(0.3, -0.1, 1, 2, 3), length.out = 1025L)
        multipliers[[position]] <- 2
        x <- .arithmetic_parity_source("float", values, 7L)
        y <- .arithmetic_parity_source("float", multipliers, 11L)
        .arithmetic_parity_expect("*", x, y, "float", "double",
                                 paste("float fractional column product, trigger", position))
    }
})

test_that("integer division by powers of two inspects the complete column", {
    .arithmetic_parity_enable()
    for (kind in c("byte", "int", "long")) {
        for (odd_tail in c(FALSE, TRUE)) {
            values <- rep(c(-12, -4, 0, 4, 12, NA_real_, tagged_missing("a")),
                          length.out = 33L)
            values[[33L]] <- if (odd_tail) 3 else 12
            # Pair ordinary compact storage with retained storage; the sole odd
            # tail can appear after the final complete retained chunk.
            for (chunk in list(NULL, 7L)) {
                x <- .arithmetic_parity_source(kind, values, chunk)
                for (divisor in c(-2, 2, -4, 4, -2^30, 2^30)) {
                    .arithmetic_parity_expect("/", x, divisor, kind, NULL,
                        paste(kind, "power-of-two division", divisor, "odd tail", odd_tail, chunk))
                }
            }
        }
    }
    divisible <- .arithmetic_parity_source("long", c(-2^30, 0, 2^30, NA_real_), 3L)
    .arithmetic_parity_expect("/", divisible, 2^30, "long", "long", "large exact divisor")
    .arithmetic_parity_expect("/", divisible, -2^30, "long", "long", "large negative exact divisor")
})

test_that("float power-of-two scaling preserves subnormals and zero signs", {
    .arithmetic_parity_enable()
    values <- c(-0, 0, -2^-149, 2^-149, -2^-126, 2^-126,
                -0.1, 0.1, -1e38, 1e38, NA_real_, tagged_missing(c("a", "z")))
    for (chunk in list(NULL, 7L)) {
        x <- .arithmetic_parity_source("float", values, chunk)
        for (scalar in c(-2^-30, 2^-30, -2^30, 2^30)) {
            info <- paste("float power-of-two scale", scalar, chunk)
            .arithmetic_parity_expect("*", x, scalar, "float", NULL, info)
            .arithmetic_parity_expect("*", scalar, x, "float", NULL, info)
            .arithmetic_parity_expect("/", x, scalar, "float", NULL, info)
        }
        # Without the large values forcing double storage, tiny results round
        # into signed float zero. The byte comparison includes its sign bit.
        tiny <- .arithmetic_parity_source("float", values[seq_len(8L)], chunk)
        .arithmetic_parity_expect("*", tiny, 2^-30, "float", "float", "float underflow")
        .arithmetic_parity_expect("/", tiny, -2^30, "float", "float", "negative float underflow")
    }
})

test_that("integer preflight preserves missing-only storage and bounded scalars", {
    .arithmetic_parity_enable()
    missing <- c(NA_real_, tagged_missing(letters))
    for (kind in c("byte", "int", "long")) {
        x <- .arithmetic_parity_source(kind, missing, 7L)
        y <- .arithmetic_parity_source(kind, rev(missing), 11L)
        for (op in c("+", "-", "*")) {
            .arithmetic_parity_expect(op, x, y, kind, kind, paste(kind, "missing-only", op))
        }
        .arithmetic_parity_expect("*", x, -2147483648, kind, kind,
                                 paste(kind, "missing-only bounded scalar"))
        observed <- .arithmetic_parity_source(kind, c(-1, 0, 1, 100, missing), 7L)
        for (scalar in c(-2147483648, -2147483647, 2147483647, 2147483648)) {
            info <- paste(kind, "scalar at or adjacent to int32 bound", scalar)
            .arithmetic_parity_expect("*", observed, scalar, kind, NULL, info)
            .arithmetic_parity_expect("*", scalar, observed, kind, NULL, info)
        }
    }
})

test_that("integer products choose long or float without losing signed zero", {
    .arithmetic_parity_enable()
    for (kind in c("byte", "int")) {
        x <- .arithmetic_parity_source(kind, c(-1, 0, 1, 100), 3L)
        .arithmetic_parity_expect("*", x, 21474836, kind, "long",
                                 paste(kind, "last product fits long"))
        .arithmetic_parity_expect("*", x, 21474837, kind, "float",
                                 paste(kind, "last product exceeds long"))
        .arithmetic_parity_expect("*", x, -21474837, kind, "float",
                                 paste(kind, "negative widened zero"))
    }
    x <- .arithmetic_parity_source("long", c(2147483619, 2147483620, -2147483647, 0), 3L)
    y <- .arithmetic_parity_source("long", c(2147483619, -2147483647, -2147483647, -2147483647), 2L)
    .arithmetic_parity_expect("*", x, y, "long", "double", "long products beyond exact doubles")
})

test_that("power-of-two arithmetic preserves legacy storage decoding", {
    .arithmetic_parity_enable()
    legacy <- read_dta(fixture("synthetic_v111.dta"), output = "tibble")
    for (column in c("b", "i", "l", "f")) {
        source <- legacy[[column]]
        kind <- dta_storage_type(source)
        attributes(source) <- list(class = dtatools:::.dta_storage_class(kind),
                                   stata.storage = kind)
        for (x in list(source, .Call(C_dtatools_owned_numeric_freeze, source, 3L))) {
            for (scalar in c(2, -4, 2^30)) {
                info <- paste("legacy", kind, scalar)
                .arithmetic_parity_expect("*", x, scalar, kind, NULL, info)
                .arithmetic_parity_expect("/", x, scalar, kind, NULL, info)
            }
        }
    }
})

test_that("float scaling promotes just beyond the binary32 cutoff", {
    .arithmetic_parity_enable()
    float_maximum <- 2^126 * (2 - 2^-23)
    for (factor in c(-2, 2, -2^30, 2^30)) {
        cutoff <- float_maximum / abs(factor)
        cutoff_bits <- readBin(writeBin(cutoff, raw(), size = 4L, endian = "little"),
                               integer(), n = 1L, size = 4L, endian = "little")
        # Adjacent positive binary32 encodings give one ULP below and above
        # the exact mathematical cutoff, including the exponent transition.
        adjacent <- readBin(writeBin(cutoff_bits + c(-1L, 0L, 1L), raw(),
                                     size = 4L, endian = "little"),
                            numeric(), n = 3L, size = 4L, endian = "little")
        expect_identical(adjacent[[2L]], cutoff)
        for (position in seq_along(adjacent)) {
            values <- rep(c(2^-149, -2^-149, -0, 0, 0.1, NA_real_), length.out = 16385L)
            values[[16385L]] <- adjacent[[position]]
            storage <- if (position == 3L) "double" else "float"
            for (chunk in list(NULL, 16384L)) {
                x <- .arithmetic_parity_source("float", values, chunk)
                info <- paste("float cutoff", position - 2L, "ULP, factor", factor, chunk)
                .arithmetic_parity_expect("*", x, factor, "float", storage, info)
                # Division by the reciprocal selects the same scaling result.
                .arithmetic_parity_expect("/", x, 1 / factor, "float", storage, info)
            }
        }
    }
})

test_that("early long promotion still counts missing rows in later chunks", {
    .arithmetic_parity_enable()
    values <- rep(1, 32769L)
    values[[1L]] <- 1073741811
    missing_rows <- c(16385L, 32768L, 32769L)
    values[missing_rows] <- c(NA_real_, tagged_missing(c("a", "z")))
    missing_mask <- rep(FALSE, length(values))
    missing_mask[missing_rows] <- TRUE
    for (chunk in list(NULL, 16384L)) {
        x <- .arithmetic_parity_source("long", values, chunk)
        for (op in c("*", "+")) {
            y <- if (op == "*") 2 else x
            actual <- .arithmetic_parity_expect(op, x, y, "long", "double",
                paste("early long promotion with later missing codes", op, chunk))
            # These public predicates also exercise cached result facts, which
            # a partial promotion scan must not mistake for complete counts.
            expect_true(anyNA(actual))
            expect_identical(is.na(actual), missing_mask)
        }
    }
})

test_that("general arithmetic keeps mixed physical sources and scalar directions exact", {
    .arithmetic_parity_enable()
    check <- function(op, x, y, minimum, info) {
        operation <- getExportedValue("base", op)
        arguments <- vctrs::vec_recycle_common(as.double(x), as.double(y))
        values <- suppressWarnings(operation(arguments[[1L]], arguments[[2L]]))
        values[is.na(arguments[[1L]]) | is.na(arguments[[2L]])] <- NA_real_
        expected <- dtatools:::.dta_computed(values, minimum)
        before <- lapply(list(x, y), .arithmetic_parity_bytes)
        .Call(C_dtatools_numeric_entry_stats, TRUE)
        actual <- operation(x, y)
        expect_identical(.Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]],
            if (.dtatools_numeric_entry_expected("scalar")) 1 else 0, info = info)
        expect_identical(dta_storage_type(actual), dta_storage_type(expected), info = info)
        expect_identical(.arithmetic_parity_bytes(actual), .arithmetic_parity_bytes(expected), info = info)
        expect_identical(is.na(actual), is.na(as.double(expected)), info = info)
        expect_identical(anyNA(actual), anyNA(as.double(expected)), info = info)
        for (i in 1:2) {
            source <- list(x, y)[[i]]
            expect_identical(.arithmetic_parity_bytes(source), before[[i]], info = info)
            if (isTRUE(dta_storage_type(source) %in% c("byte", "int", "long", "float"))) {
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(source), info = info)
                expect_false(.Call(C_dtatools_is_materialized_numeric_altrep, source), info = info)
            }
        }
    }
    values <- rep(c(-3, -1, -0, 0, 1, 7, NA_real_, tagged_missing(c("a", "z"))), length.out = 35L)
    for (kind in c("byte", "int", "long", "float")) {
        for (chunk in list(NULL, 7L)) {
            x <- .arithmetic_parity_source(kind, values, chunk)
            for (other in c("byte", "int", "long", "float", "double", "bare", "integer", "logical")) {
                y <- switch(other,
                    bare = rev(values) / 3,
                    integer = rep(c(NA_integer_, -2L, 0L, 1L, 3L), length.out = length(values)),
                    logical = rep(c(NA, FALSE, TRUE), length.out = length(values)),
                    double = dta_double(rev(values) / 3),
                    .arithmetic_parity_source(other, rev(values), 11L))
                minimum <- if (other %in% c("bare", "integer", "logical")) kind else
                    dta_storage_type(vctrs::vec_ptype2(x, y))
                for (op in c("+", "-", "*", "/")) {
                    info <- paste(kind, other, op, "chunk", chunk)
                    check(op, x, y, minimum, info)
                    check(op, y, x, minimum, paste(info, "reverse"))
                }
            }
            for (scalar in c(1.01, -3.25, 1 / 3, 1e30, -0, Inf, -Inf, NA_real_, tagged_missing("z"))) {
                for (op in c("+", "-", "*", "/")) {
                    info <- paste(kind, "general scalar", scalar, op, chunk)
                    check(op, x, scalar, kind, info)
                    check(op, scalar, x, kind, paste(info, "reverse"))
                }
            }
        }
    }
})

test_that("general preflight and float promotion retain later missing rows and earlier precision", {
    .arithmetic_parity_enable()
    for (kind in c("byte", "int", "long", "float")) {
        values <- rep(c(-3, -1, -0, 0, 1, 3), length.out = 32769L)
        values[c(16384L, 16385L, 32769L)] <- c(NA_real_, tagged_missing(c("a", "z")))
        x <- .arithmetic_parity_source(kind, values, 16384L)
        for (scalar in c(1.01, -3.25, 1 / 3)) {
            actual <- .arithmetic_parity_expect("*", x, scalar, kind, NULL,
                paste("general preflight missing tail", kind, scalar))
            expect_identical(is.na(actual), is.na(values))
            expect_true(anyNA(actual))
        }
    }
    for (position in c(1L, 16384L, 16385L, 32769L)) {
        values <- rep(c(0.1, -0.3, 1, -0, 0), length.out = 32769L)
        values[[position]] <- 1e38
        x <- .arithmetic_parity_source("float", values, 16384L)
        .arithmetic_parity_expect("*", x, 1.9, "float", "double",
            paste("general float promotion discards rounded prefix", position))
    }
})

test_that("general integer scalar bounds preserve floating storage and missing counts", {
    .arithmetic_parity_enable()
    low <- c(byte = -127, int = -32767, long = -2147483647)
    high <- c(byte = 100, int = 32740, long = 2147483620)
    physical_magnitude <- c(byte = 128, int = 32768, long = 2147483648)
    float_limit <- (2^24 - 1) * 2^103
    double_limit <- (2^53 - 1) * 2^970
    missing <- c(NA_real_, tagged_missing(letters))
    for (kind in names(low)) {
        observed <- c(low[[kind]], -1, 0, 1, high[[kind]])
        cutoff <- float_limit / physical_magnitude[[kind]]
        cases <- list(list("+", 0.1), list("-", -0.1), list("*", 1.01),
            list("*", -0), list("*", 0), list("/", -3.25),
            list("/", .Machine$double.xmin * .Machine$double.eps),
            list("/", .Machine$double.xmax),
            list("*", cutoff * (1 - 2^-50)), list("*", cutoff * (1 + 2^-50)),
            list("*", -double_limit / physical_magnitude[[kind]]),
            list("*", double_limit / physical_magnitude[[kind]] * (1 + 2^-50)))
        for (values in list(observed, c(observed, missing), missing)) {
            for (chunk in list(NULL, 7L)) {
                x <- .arithmetic_parity_source(kind, values, chunk)
                for (case in cases) {
                    op <- case[[1L]]; scalar <- case[[2L]]
                    for (reverse in c(FALSE, TRUE)) {
                        info <- paste(kind, op, scalar, "reverse", reverse, "chunk", chunk)
                        actual <- if (reverse)
                            .arithmetic_parity_expect(op, scalar, x, kind, NULL, info)
                        else .arithmetic_parity_expect(op, x, scalar, kind, NULL, info)
                        expected_missing <- is.na(as.double(actual))
                        expect_identical(is.na(actual), expected_missing, info = info)
                        expect_identical(anyNA(actual), any(expected_missing), info = info)
                        if (any(expected_missing)) {
                            # Correct values alone cannot expose an excessive
                            # cached count. Clear every actual missing lane.
                            result <- dibble(x = actual)
                            replace_values(result, x = 0, where = which(expected_missing))
                            expect_false(anyNA(result$x), info = info)
                        }
                    }
                }
            }
        }
    }
})

test_that("general arithmetic includes imported physical signed minima and legacy reserved observations", {
    .arithmetic_parity_enable()
    modern <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    legacy <- tempfile(fileext = ".dta")
    withr::defer(unlink(c(modern, legacy)))
    minimum_bits <- list(x_byte = as.raw(0x80), x_int = as.raw(c(0, 0x80)),
                         x_long = as.raw(c(0, 0, 0, 0x80)))
    patch_numeric_fixture_row(modern, 0L, minimum_bits)
    bytes <- readBin(fixture("synthetic_v111.dta"), "raw",
                     n = file.info(fixture("synthetic_v111.dta"))[["size"]])
    prefix <- c(as.raw(1), writeBin(321L, raw(), size = 2L, endian = "little"),
                writeBin(-123456L, raw(), size = 4L, endian = "little"),
                writeBin(1.5, raw(), size = 4L, endian = "little"),
                writeBin(-2.25, raw(), size = 8L, endian = "little"))
    start <- grepRaw(prefix, bytes, fixed = TRUE, all = TRUE)
    expect_length(start, 1L)
    bytes[start + 0:6] <- unlist(minimum_bits, use.names = FALSE)
    # Legacy integer storage reserves only its maximum signed value. These
    # modern extended-missing codes remain observed in this input layout.
    bytes[start + 25L + 0:6] <- c(as.raw(126),
        writeBin(32766L, raw(), size = 2L, endian = "little"),
        writeBin(2147483646L, raw(), size = 4L, endian = "little"))
    writeBin(bytes, legacy)
    for (version in c("modern", "legacy")) {
        path <- if (version == "modern") modern else legacy
        names <- if (version == "modern") c("x_byte", "x_int", "x_long") else c("b", "i", "l")
        imported <- read_dta(path, col_select = tidyselect::all_of(names))
        eager <- read_dta(path, col_select = tidyselect::all_of(names), use_numeric_altrep = FALSE)
        for (index in seq_along(names)) {
            source <- imported[[names[[index]]]]
            kind <- dta_storage_type(source)
            expect_identical(as.double(source), as.double(eager[[names[[index]]]]))
            expect_identical(as.double(source)[[1L]], -c(128, 32768, 2147483648)[[index]])
            if (version == "legacy") {
                expect_identical(as.double(source)[[2L]], c(126, 32766, 2147483646)[[index]])
            }
            # The legacy byte fixture has value-label metadata, which correctly
            # declines this admission route. Preserve its bytes and encoding
            # while selecting the ordinary compact arithmetic contract.
            attributes(source) <- list(class = dtatools:::.dta_storage_class(kind),
                                       stata.storage = kind)
            for (x in list(source, .Call(C_dtatools_owned_numeric_freeze, source, 3L))) {
                for (scalar in c(1.01, -3.25)) {
                    for (op in c("+", "-", "*", "/")) {
                        info <- paste(version, kind, "signed physical minimum", op, scalar)
                        .arithmetic_parity_expect(op, x, scalar, kind, NULL, info)
                        .arithmetic_parity_expect(op, scalar, x, kind, NULL, info)
                    }
                }
                partner <- .Call(C_dtatools_owned_numeric_freeze,
                    dta_float(rep(c(1.5, -0, 0, 2^-149, NA_real_, tagged_missing("z")),
                                  length.out = length(x))), 5L)
                minimum <- dtatools:::.dta_promote(kind, "float")
                for (op in c("+", "-", "*", "/")) {
                    info <- paste(version, kind, "physical compact pair", op)
                    .arithmetic_parity_expect(op, x, partner, minimum, NULL, info)
                    .arithmetic_parity_expect(op, partner, x, minimum, NULL, info)
                }
            }
        }
    }
})

test_that("floating scalar results reject unsafe endpoint proofs", {
    .arithmetic_parity_enable()
    for (kind in c("byte", "int", "long", "float")) {
        x <- .arithmetic_parity_source(kind, c(-100, -1, 0, 1, 100, NA_real_, tagged_missing("z")), 3L)
        source <- .arithmetic_parity_bytes(x)
        for (scalar in c(1.01, 1e307, -1e307,
                         .Machine$double.xmin * .Machine$double.eps,
                         -.Machine$double.xmin * .Machine$double.eps)) {
            # Declared double storage exercises the proof even when every
            # nonzero result overflows and the bare-scalar result could stay
            # in integer storage. New invalid results must increase its count.
            y <- dta_double(scalar)
            for (op in c("*", "/")) {
                operation <- getExportedValue("base", op)
                values <- operation(as.double(x), scalar)
                values[is.na(as.double(x))] <- NA_real_
                expected <- dtatools:::.dta_computed(values, "double")
                .Call(C_dtatools_numeric_entry_stats, TRUE)
                actual <- operation(x, y)
                expect_identical(.Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]],
                    if (.dtatools_numeric_entry_expected("scalar")) 1 else 0)
                expect_identical(dta_storage_type(actual), "double")
                expect_identical(.arithmetic_parity_bytes(actual), .arithmetic_parity_bytes(expected))
                missing <- is.na(as.double(expected))
                expect_identical(is.na(actual), missing)
                expect_identical(anyNA(actual), any(missing))
                result <- dibble(x = actual)
                replace_values(result, x = 0, where = which(missing))
                expect_false(anyNA(result$x))
                expect_identical(.arithmetic_parity_bytes(x), source)
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
            }
        }
    }
})

test_that("float scalar interval proofs retain zero signs and exact missing counts", {
    .arithmetic_parity_enable()
    missing <- c(NA_real_, tagged_missing(letters))
    observed <- c(-0, 0, -2^-149, 2^-149, -1, 1, -1e38, 1e38)
    cases <- list(list("+", 0.1), list("-", -0.1), list("*", 1.01),
        list("*", -3.25), list("*", -0), list("*", 0), list("/", -3.25),
        list("/", .Machine$double.xmin * .Machine$double.eps),
        list("/", .Machine$double.xmax), list("+", 1e39), list("-", -1e39),
        list("+", 2e38), list("-", -2e38),
        list("*", 1e307), list("+", 1e307))
    for (values in list(observed, c(observed, missing), missing)) {
        for (chunk in list(NULL, 7L)) {
            x <- .arithmetic_parity_source("float", values, chunk)
            for (case in cases) {
                for (reverse in c(FALSE, TRUE)) {
                    op <- case[[1L]]; scalar <- case[[2L]]
                    info <- paste("float interval", op, scalar, reverse, chunk)
                    actual <- if (reverse)
                        .arithmetic_parity_expect(op, scalar, x, "float", NULL, info)
                    else .arithmetic_parity_expect(op, x, scalar, "float", NULL, info)
                    expected_missing <- is.na(as.double(actual))
                    expect_identical(is.na(actual), expected_missing, info = info)
                    expect_identical(anyNA(actual), any(expected_missing), info = info)
                    if (any(expected_missing)) {
                        result <- dibble(x = actual)
                        replace_values(result, x = 0, where = which(expected_missing))
                        expect_false(anyNA(result$x), info = info)
                    }
                }
            }
        }
    }
})

test_that("float scalar fit intervals include exactly their binary32 boundary neighbors", {
    .arithmetic_parity_enable()
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    withr::defer(unlink(path))
    float_limit <- (2^24 - 1) * 2^103
    physical_limit <- (2^24 - 1) * 2^104
    raw_bits <- function(value) as.raw(floor(value / 256^(0:3)) %% 256)
    # The oracle uses ordinary binary64 arithmetic and the established result
    # policy. Generate neighbors from algebraic estimates, independently of
    # the native search over ordered encodings; the estimates need not be exact.
    neighbor_bits <- function(value) {
        if (!is.finite(value) || abs(value) > physical_limit) return(numeric())
        encoded <- readBin(writeBin(abs(value), raw(), size = 4L, endian = "little"),
                           integer(), n = 1L, size = 4L, endian = "little")
        nearby <- encoded + (-2:2)
        nearby <- nearby[nearby >= 0 & nearby <= 0x7f7fffff]
        unique(c(nearby, nearby + 0x80000000))
    }
    for (scalar in c(1.01, -3.25, 0.1, -1e38, 1e38, -2e38, 2e38, -1e39, 1e39, 1e-30)) {
        for (op in c("+", "-", "*", "/")) {
            for (reverse in c(FALSE, TRUE)) {
                estimates <- switch(op,
                    "+" = c(-float_limit - scalar, float_limit - scalar),
                    "-" = if (reverse) c(scalar - float_limit, scalar + float_limit)
                          else c(-float_limit + scalar, float_limit + scalar),
                    "*" = c(-float_limit / scalar, float_limit / scalar),
                    "/" = if (reverse) c(-scalar / float_limit, scalar / float_limit)
                          else c(-float_limit * scalar, float_limit * scalar))
                bits <- unique(c(0, 0x80000000, 1, 0x80000001, 0x3ecccccd,
                    0x7effffff, 0x7f000001, 0x7f7fffff, 0xff7fffff,
                    unlist(lapply(estimates, neighbor_bits), use.names = FALSE)))
                for (batch in split(bits, ceiling(seq_along(bits) / 27L))) {
                    for (index in seq_along(batch))
                        patch_numeric_fixture_row(path, index - 1L,
                            list(x_float = raw_bits(batch[[index]])))
                    compact <- read_dta(path, col_select = "x_float", n_max = length(batch))$x_float
                    eager <- read_dta(path, col_select = "x_float", n_max = length(batch),
                                      use_numeric_altrep = FALSE)$x_float
                    expect_identical(as.double(compact), as.double(eager))
                    for (x in list(compact, .Call(C_dtatools_owned_numeric_freeze, compact, 7L))) {
                        info <- paste("imported float boundary", op, scalar, reverse)
                        if (reverse)
                            .arithmetic_parity_expect(op, scalar, x, "float", NULL, info)
                        else .arithmetic_parity_expect(op, x, scalar, "float", NULL, info)
                    }
                }
            }
        }
    }
})

test_that("scalar block proofs preserve ordinary tails and late whole-column promotion", {
    .arithmetic_parity_enable()
    n <- 32769L
    cases <- list(list("+", 0.1), list("-", -0.1), list("*", 1.01),
        list("*", -3.25), list("*", -0), list("*", 0), list("/", -3.25),
        list("+", 2e38), list("-", -2e38))
    for (late in c(FALSE, TRUE)) {
        values <- rep(c(1.5, -0, 0, 2^-149, -2^-149, -1.5), length.out = n)
        values[seq_len(256L)] <- rep(c(NA_real_, tagged_missing(letters)), length.out = 256L)
        if (late) values[[n]] <- (2^24 - 1) * 2^103
        for (chunk in list(NULL, 63L, 16385L)) {
            x <- .arithmetic_parity_source("float", values, chunk)
            for (case in cases) {
                op <- case[[1L]]; scalar <- case[[2L]]
                info <- paste("scalar block", op, scalar, late, chunk)
                for (reverse in c(FALSE, TRUE)) {
                    actual <- if (reverse)
                        .arithmetic_parity_expect(op, scalar, x, "float", NULL, info)
                    else .arithmetic_parity_expect(op, x, scalar, "float", NULL, info)
                    missing <- is.na(as.double(actual))
                    expect_identical(is.na(actual), missing, info = info)
                    expect_identical(anyNA(actual), any(missing), info = info)
                }
                # Declared double output bypasses float-fit/narrowing checks.
                operation <- getExportedValue("base", op)
                reference <- operation(as.double(x), scalar)
                reference[is.na(as.double(x))] <- NA_real_
                expected <- dtatools:::.dta_computed(reference, "double")
                actual <- operation(x, dta_double(scalar))
                expect_identical(dta_storage_type(actual), "double", info = info)
                expect_identical(.arithmetic_parity_bytes(actual), .arithmetic_parity_bytes(expected), info = info)
                expect_identical(is.na(actual), is.na(as.double(expected)), info = info)
            }
        }
    }
})

test_that("scalar block proofs preserve imported exceptions after ordinary spans", {
    .arithmetic_parity_enable()
    modern <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    legacy <- tempfile(fileext = ".dta")
    withr::defer(unlink(c(modern, legacy)))
    original <- readBin(fixture("synthetic_v111.dta"), "raw",
        n = file.info(fixture("synthetic_v111.dta"))[["size"]])
    prefix <- c(as.raw(1), writeBin(321L, raw(), size = 2L, endian = "little"),
        writeBin(-123456L, raw(), size = 4L, endian = "little"),
        writeBin(1.5, raw(), size = 4L, endian = "little"),
        writeBin(-2.25, raw(), size = 8L, endian = "little"))
    start <- grepRaw(prefix, original, fixed = TRUE, all = TRUE)
    expect_length(start, 1L)
    bits <- c(0, 0x80000000, 1, 0x80000001, 0x7effffff, 0x7f000000,
        0x7f000001, 0x7f000800, 0x7f00d000, 0x7f7fffff, 0xff7fffff,
        0x7f800000, 0xff800000, 0x7fc00000, 0xffc00000)
    raw_bits <- function(value) as.raw(floor(value / 256^(0:3)) %% 256)
    for (batch in split(bits, ceiling(seq_along(bits) / 3L))) {
        batch <- c(0x3fc00000, batch) # Ordinary fractional prefix for promotion.
        bytes <- original
        for (index in seq_along(batch)) {
            patch_numeric_fixture_row(modern, index - 1L,
                list(x_float = raw_bits(batch[[index]])))
            location <- start + (index - 1L) * 25L + 7L
            bytes[location + 0:3] <- raw_bits(batch[[index]])
        }
        writeBin(bytes, legacy)
        for (version in c("modern", "legacy")) {
            path <- if (version == "modern") modern else legacy
            column <- if (version == "modern") "x_float" else "f"
            small <- read_dta(path, col_select = tidyselect::all_of(column), n_max = length(batch))[[column]]
            rows <- c(rep(1L, 32769L), seq.int(2L, length(batch)))
            gathered <- .Call(C_dtatools_gather_numeric, small, NULL, rows, NULL)
            source <- dtatools:::.dta_merge_restore_gathered(gathered, small)
            expect_identical(.arithmetic_parity_bytes(source),
                writeBin(as.double(small)[rows], raw(), size = 8L, endian = "little"))
            for (chunk in list(NULL, 8191L)) {
                x <- if (is.null(chunk)) source else .Call(C_dtatools_owned_numeric_freeze, source, chunk)
                for (case in list(list("+", 0.1), list("-", 1e38), list("*", 1.01), list("/", -3.25))) {
                    op <- case[[1L]]; scalar <- case[[2L]]
                    info <- paste("scalar imported block", version, op, scalar, chunk)
                    for (reverse in c(FALSE, TRUE)) {
                        actual <- if (reverse)
                            .arithmetic_parity_expect(op, scalar, x, "float", NULL, info)
                        else .arithmetic_parity_expect(op, x, scalar, "float", NULL, info)
                        expect_identical(is.na(actual), is.na(as.double(actual)), info = info)
                        expect_identical(anyNA(actual), any(is.na(as.double(actual))), info = info)
                    }
                }
            }
        }
    }
})

test_that("long float block addition preserves bits and exact missing unions", {
    .arithmetic_parity_enable()
    n <- 32769L
    grid_x <- as.double((seq_len(n) * 13) %% 10001L - 5000L)
    grid_y <- as.double((seq_len(n) * 19) %% 1001L - 500L) / 8
    tags <- c(NA_real_, tagged_missing(letters))
    for (pattern in c("ordinary", "sparse", "prefix", "suffix", "alternating", "all")) {
        values_x <- grid_x
        values_y <- grid_y
        missing_x <- missing_y <- integer()
        if (pattern == "sparse") {
            missing_x <- seq.int(13L, n, by = 997L)
            missing_y <- seq.int(19L, n, by = 991L)
        } else if (pattern == "prefix") missing_y <- seq_len(256L)
        else if (pattern == "suffix") missing_y <- seq.int(n - 255L, n)
        else if (pattern == "alternating")
            missing_x <- missing_y <- which(((seq_len(n) - 1L) %/% 64L) %% 2L == 0L)
        else if (pattern == "all") missing_x <- missing_y <- seq_len(n)
        values_x[missing_x] <- rep(tags, length.out = length(missing_x))
        values_y[missing_y] <- rep(rev(tags), length.out = length(missing_y))
        # Ordinary lanes include int32 values that cannot round through float,
        # zero signs, and the least positive and negative binary32 subnormal.
        ordinary <- setdiff(seq_len(n), union(missing_x, missing_y))
        if (length(ordinary) >= 5L) {
            values_x[ordinary[1:5]] <- c(16777217, -16777217, 0, 0, 0)
            values_y[ordinary[1:5]] <- c(0.5, -0.5, -0, 2^-149, -2^-149)
        }
        for (chunks in list(c(0L, 0L), c(7L, 11L), c(8191L, 16385L))) {
            x <- .arithmetic_parity_source("long", values_x, if (chunks[[1L]]) chunks[[1L]] else NULL)
            y <- .arithmetic_parity_source("float", values_y, if (chunks[[2L]]) chunks[[2L]] else NULL)
            before <- lapply(list(x, y), .arithmetic_parity_bytes)
            values <- as.double(x) + as.double(y)
            values[is.na(as.double(x)) | is.na(as.double(y))] <- NA_real_
            expected <- dtatools:::.dta_computed(values, "double")
            missing <- is.na(expected)
            for (reverse in c(FALSE, TRUE)) {
                info <- paste("long float blocks", pattern, chunks, reverse)
                actual <- if (reverse)
                    .arithmetic_parity_expect("+", y, x, "double", "double", info)
                else .arithmetic_parity_expect("+", x, y, "double", "double", info)
                expect_identical(is.na(actual), missing, info = info)
                expect_identical(anyNA(actual), any(missing), info = info)
                result <- dibble(x = actual)
                if (any(missing)) replace_values(result, x = 0, where = which(missing))
                cleared <- as.double(expected)
                cleared[missing] <- 0
                expect_identical(.arithmetic_parity_bytes(result$x), writeBin(cleared, raw(), 8L, endian = "little"), info = info)
                expect_false(anyNA(result$x), info = info)
                expect_identical(.arithmetic_parity_bytes(actual), .arithmetic_parity_bytes(expected), info = info)
            }
            expect_identical(lapply(list(x, y), .arithmetic_parity_bytes), before)
        }
    }
})

test_that("long float block addition retains imported exceptions after ordinary spans", {
    .arithmetic_parity_enable()
    modern <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    legacy <- tempfile(fileext = ".dta")
    withr::defer(unlink(c(modern, legacy)))
    original <- readBin(fixture("synthetic_v111.dta"), "raw",
        n = file.info(fixture("synthetic_v111.dta"))[["size"]])
    prefix <- c(as.raw(1), writeBin(321L, raw(), 2L, endian = "little"), writeBin(-123456L, raw(), 4L, endian = "little"),
                writeBin(1.5, raw(), 4L, endian = "little"), writeBin(-2.25, raw(), 8L, endian = "little"))
    start <- grepRaw(prefix, original, fixed = TRUE, all = TRUE)
    expect_length(start, 1L)
    raw_bits <- function(value) as.raw(floor(value / 256^(0:3)) %% 256)
    long_bits <- c(0x80000000, 0x01000001, 0x7fffffe4, 0x7fffffe5, 0x7ffffffe, 0x7fffffff)
    float_bits <- c(0, 0x80000000, 1, 0x80000001, 0x7effffff, 0xfeffffff,
        0x7f000000, 0x7f000001, 0x7f000800, 0x7f00d000, 0x7f7fffff, 0xff7fffff,
        0x7f800000, 0xff800000, 0x7fc00001, 0xffc00001)
    for (batch in split(seq_along(float_bits), ceiling(seq_along(float_bits) / 3L))) {
        xs <- c(0x01000001, long_bits[(batch - 1L) %% length(long_bits) + 1L])
        ys <- c(0x3f000000, float_bits[batch])
        bytes <- original
        for (index in seq_along(xs)) {
            patch_numeric_fixture_row(modern, index - 1L,
                list(x_long = raw_bits(xs[[index]]), x_float = raw_bits(ys[[index]])))
            location <- start + (index - 1L) * 25L
            bytes[location + 3:6] <- raw_bits(xs[[index]])
            bytes[location + 7:10] <- raw_bits(ys[[index]])
        }
        writeBin(bytes, legacy)
        for (version in c("modern", "legacy")) {
            path <- if (version == "modern") modern else legacy
            columns <- if (version == "modern") c("x_long", "x_float") else c("l", "f")
            source <- read_dta(path, col_select = tidyselect::all_of(columns), n_max = length(xs))
            eager <- read_dta(path, col_select = tidyselect::all_of(columns), n_max = length(xs), use_numeric_altrep = FALSE)
            for (index in seq_along(columns))
                expect_identical(.arithmetic_parity_bytes(source[[columns[[index]]]]),
                    .arithmetic_parity_bytes(eager[[columns[[index]]]]))
            rows <- c(rep(1L, 32769L), seq.int(2L, length(xs)))
            extended <- lapply(columns, function(column) {
                small <- source[[column]]
                kind <- dta_storage_type(small)
                attributes(small) <- list(class = dtatools:::.dta_storage_class(kind), stata.storage = kind)
                gathered <- .Call(C_dtatools_gather_numeric, small, NULL, rows, NULL)
                dtatools:::.dta_merge_restore_gathered(gathered, small)
            })
            for (retained in c(FALSE, TRUE)) {
                x <- if (retained) .Call(C_dtatools_owned_numeric_freeze, extended[[1L]], 8191L) else extended[[1L]]
                y <- if (retained) .Call(C_dtatools_owned_numeric_freeze, extended[[2L]], 16385L) else extended[[2L]]
                for (reverse in c(FALSE, TRUE)) {
                    info <- paste("imported long float blocks", version, retained, reverse)
                    actual <- if (reverse)
                        .arithmetic_parity_expect("+", y, x, "double", "double", info)
                    else .arithmetic_parity_expect("+", x, y, "double", "double", info)
                    missing <- is.na(as.double(actual))
                    result <- dibble(x = actual)
                    if (any(missing)) replace_values(result, x = 0, where = which(missing))
                    cleared <- as.double(actual)
                    cleared[missing] <- 0
                    expect_identical(.arithmetic_parity_bytes(result$x), writeBin(cleared, raw(), 8L, endian = "little"), info = info)
                    expect_false(anyNA(result$x), info = info)
                }
            }
        }
    }
})
