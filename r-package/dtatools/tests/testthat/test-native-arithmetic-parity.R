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
