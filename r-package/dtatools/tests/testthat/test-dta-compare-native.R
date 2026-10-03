compact_constructors <- list(
    byte = dta_byte,
    int = dta_int,
    long = dta_long,
    float = dta_float
)

mixed_values <- function(constructor) {
    constructor(c(
        -5, 0, 5, NA_real_, tagged_missing("a"), tagged_missing("z")
    ))
}

test_that("native scalar comparisons match Stata total order", {
    for (storage in names(compact_constructors)) {
        value <- mixed_values(compact_constructors[[storage]])

        expect_identical(
            value == 5, c(FALSE, FALSE, TRUE, FALSE, FALSE, FALSE),
            info = storage
        )
        expect_identical(
            value != 5, c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE),
            info = storage
        )
        expect_identical(
            value < 5, c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE),
            info = storage
        )
        expect_identical(
            value <= 5, c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE),
            info = storage
        )
        expect_identical(
            value > 5, c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE),
            info = storage
        )
        expect_identical(
            value >= 5, c(FALSE, FALSE, TRUE, TRUE, TRUE, TRUE),
            info = storage
        )
    }
})

test_that("native comparisons keep every missing code distinct and ordered", {
    for (storage in names(compact_constructors)) {
        value <- mixed_values(compact_constructors[[storage]])

        expect_identical(
            value == NA_real_,
            c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE),
            info = storage
        )
        expect_identical(
            value < NA_real_,
            c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE),
            info = storage
        )
        expect_identical(
            value == tagged_missing("a"),
            c(FALSE, FALSE, FALSE, FALSE, TRUE, FALSE),
            info = storage
        )
        expect_identical(
            value >= tagged_missing("a"),
            c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE),
            info = storage
        )
        expect_identical(
            value <= tagged_missing("z"),
            rep(TRUE, 6),
            info = storage
        )
        expect_identical(
            value > tagged_missing("z"),
            rep(FALSE, 6),
            info = storage
        )
    }
})

test_that("narrow storage understands constants it cannot represent", {
    value <- dta_byte(c(-5, 0, 5, NA_real_, tagged_missing("a")))

    # 5.5 and 200 are not representable as Stata bytes, yet comparisons
    # must still work on the byte's decoded value.
    expect_identical(value == 5.5, rep(FALSE, 5))
    expect_identical(value < 5.5, c(TRUE, TRUE, TRUE, FALSE, FALSE))
    expect_identical(value < 200, c(TRUE, TRUE, TRUE, FALSE, FALSE))
    expect_identical(value > -200, c(TRUE, TRUE, TRUE, TRUE, TRUE))
    expect_identical(value < Inf, c(TRUE, TRUE, TRUE, FALSE, FALSE))
    expect_identical(value > -Inf, rep(TRUE, 5))
})

test_that("scalar-on-the-left comparisons flip correctly", {
    value <- mixed_values(dta_int)

    expect_identical(5 == value, value == 5)
    expect_identical(5 != value, value != 5)
    expect_identical(5 < value, value > 5)
    expect_identical(5 <= value, value >= 5)
    expect_identical(5 > value, value < 5)
    expect_identical(5 >= value, value <= 5)
})

test_that("compact-versus-compact comparisons agree elementwise", {
    x <- dta_byte(c(1, 2, NA_real_, tagged_missing("a"), 5))
    y <- dta_long(c(1, 3, NA_real_, tagged_missing("b"), 4))

    expect_identical(x == y, c(TRUE, FALSE, TRUE, FALSE, FALSE))
    expect_identical(x < y, c(FALSE, TRUE, FALSE, TRUE, FALSE))
    expect_identical(x >= y, c(TRUE, FALSE, TRUE, FALSE, TRUE))
})

test_that("comparisons never materialize compact operands", {
    value <- mixed_values(dta_byte)
    other <- mixed_values(dta_long)

    invisible(value == 5)
    invisible(5 < value)
    invisible(value >= tagged_missing("a"))
    invisible(value == other)

    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(other))
})

test_that("the native kernel is engaged for compact storage", {
    for (storage in names(compact_constructors)) {
        value <- mixed_values(compact_constructors[[storage]])
        native <- dtatools:::.dta_compare_native("==", value, 5)

        expect_identical(
            native, c(FALSE, FALSE, TRUE, FALSE, FALSE, FALSE),
            info = storage
        )
    }

    # Eager doubles compare natively too, classifying NA_real_ and
    # tagged NaNs from the decoded payload bits.
    expect_identical(
        dtatools:::.dta_compare_native("==", dta_double(c(1, 2)), 1),
        c(TRUE, FALSE)
    )
})

test_that("decoded double vectors compare natively with full semantics", {
    value <- dta_double(c(
        -5, 0, 5, NA_real_, tagged_missing("a"), tagged_missing("z")
    ))

    expect_identical(value == 5, c(FALSE, FALSE, TRUE, FALSE, FALSE, FALSE))
    expect_identical(value < 5, c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE))
    expect_identical(value > 5, c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE))
    expect_identical(
        value == NA_real_, c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE)
    )
    expect_identical(
        value == tagged_missing("a"),
        c(FALSE, FALSE, FALSE, FALSE, TRUE, FALSE)
    )
    expect_identical(
        value >= tagged_missing("a"),
        c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE)
    )

    # Mixed compact-vs-double pairs of equal length also stay native.
    compact <- dta_byte(c(
        -5, NA_real_, 5, 3, tagged_missing("a"), tagged_missing("z")
    ))
    expect_identical(
        dtatools:::.dta_compare_native("==", compact, value),
        c(TRUE, FALSE, TRUE, FALSE, TRUE, TRUE)
    )
    expect_identical(
        compact == value, c(TRUE, FALSE, TRUE, FALSE, TRUE, TRUE)
    )
    # Element 2 is `.` versus 0: missing sorts above every finite value.
    expect_identical(
        compact < value, c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE)
    )

    # Noncanonical NaN payloads still surface the fallback's error.
    expect_error(value == NaN, "noncanonical NaN")
})

test_that("multi-threaded comparisons match single-threaded results", {
    length_over_threshold <- 600000L
    value <- dta_long(seq_len(length_over_threshold))
    expected <- seq_len(length_over_threshold) <= 300000L

    previous <- options(dtatools.threads = 2L)
    on.exit(options(previous), add = TRUE)
    threaded <- value <= 300000

    options(dtatools.threads = 1L)
    serial <- value <= 300000

    expect_identical(threaded, expected)
    expect_identical(serial, expected)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
})

test_that("fallback-owned errors survive the native fast path", {
    value <- mixed_values(dta_byte)

    expect_error(value == NaN, "noncanonical NaN")
    expect_error(value == dta_byte(c(1, 2)), class = "vctrs_error")
})

.float_comparison_reference <- function(op, x, y) {
    # Ordinary decoded doubles give an independent lexicographic oracle. The
    # missing inspector here reads R's double payloads, never compact floats.
    parts <- function(value) {
        rank <- integer(length(value))
        rank[is.na(value)] <- 1L
        tags <- missing_tag(value)
        tagged <- !is.na(tags)
        rank[tagged] <- match(tags[tagged], letters) + 1L
        value[rank > 0L] <- 0
        list(rank = rank, value = value)
    }
    a <- parts(x)
    b <- parts(y)
    equal <- a$rank == b$rank & a$value == b$value
    less <- a$rank < b$rank | (a$rank == b$rank & a$value < b$value)
    greater <- a$rank > b$rank | (a$rank == b$rank & a$value > b$value)
    switch(op, "==" = equal, "!=" = !equal, "<" = less,
           "<=" = less | equal, ">" = greater, ">=" = greater | equal)
}

.float_comparison_expect <- function(x, y, plain_x, plain_y) {
    for (op in c("==", "!=", "<", "<=", ">", ">=")) {
        expected <- .float_comparison_reference(op, plain_x, plain_y)
        expect_identical(dtatools:::.dta_compare_native(op, x, y), expected, info = op)
        expect_identical(getExportedValue("base", op)(x, y), expected, info = op)
    }
}

.float_comparison_freeze <- function(value, rows) {
    .Call(C_dtatools_owned_numeric_freeze, value, rows)
}

test_that("double pair kernels preserve every missing rank and IEEE comparisons", {
    values <- c(-Inf, -.Machine$double.xmax, -1, -0, 0,
                .Machine$double.xmin, 1, .Machine$double.xmax, Inf,
                NA_real_, tagged_missing(letters))
    plain <- rep(values, each = length(values))
    other <- rep(values, times = length(values))
    # Permissive imported doubles may contain infinities and high finite values
    # that the public storage constructor does not create.
    x <- plain
    y <- other
    attributes(x) <- attributes(dta_double())
    attributes(y) <- attributes(dta_double())
    .float_comparison_expect(x, y, plain, other)
    .float_comparison_expect(y, x, other, plain)
    expect_identical(as.double(x), plain)
    expect_identical(as.double(y), other)
})

test_that("double pair kernels retain native decline and public NaN errors", {
    other <- dta_double(c(1, 2, tagged_missing("z")))
    for (invalid in list(NaN, tagged_nan_for_test("?"), tagged_nan_for_test("A"))) {
        x <- c(1, invalid, NA_real_)
        attributes(x) <- attributes(dta_double())
        for (op in c("==", "!=", "<", "<=", ">", ">=")) {
            operation <- getExportedValue("base", op)
            expect_null(dtatools:::.dta_compare_native(op, x, other))
            expect_null(dtatools:::.dta_compare_native(op, other, x))
            expect_error(operation(x, other), "noncanonical NaN")
            expect_error(operation(other, x), "noncanonical NaN")
        }
    }
})

test_that("double temporal pairs compare their already decoded values", {
    path <- fixture_with_temporal_storage("price")
    on.exit(unlink(path), add = TRUE)
    prototype <- read_dta(path)$price
    plain <- c(-0, 0, 1, 1 + 2^-52, NA_real_, tagged_missing(letters))
    other <- rev(plain)
    x <- dtatools:::.restore_dta_temporal(plain, prototype, "double")
    y <- dtatools:::.restore_dta_temporal(other, prototype, "double")
    .float_comparison_expect(x, y, plain, other)
    .float_comparison_expect(y, x, other, plain)
})

.float_comparison_fixture <- function(bits, display_format = NULL) {
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    for (index in seq_along(bits)) {
        raw <- as.raw(floor(bits[[index]] / 256^(0:3)) %% 256)
        patch_numeric_fixture_row(path, index - 1L, list(x_float = raw))
    }
    if (!is.null(display_format)) {
        bytes <- readBin(path, "raw", n = file.info(path)[["size"]])
        start <- grepRaw(charToRaw("<formats>"), bytes, fixed = TRUE, all = TRUE)
        end <- grepRaw(charToRaw("</formats>"), bytes, fixed = TRUE, all = TRUE)
        stopifnot(length(start) == 1L, length(end) == 1L)
        start <- start + nchar("<formats>")
        width <- (end - start) / length(.numeric_missing_fixture_widths)
        stopifnot(width == trunc(width), nchar(display_format) < width)
        # x_float is the fifth column in the shared missing-value fixture.
        location <- start + 4L * width
        bytes[location + seq_len(width) - 1L] <-
            c(charToRaw(display_format), raw(width - nchar(display_format)))
        writeBin(bytes, path)
    }
    path
}

.float_comparison_read <- function(path, count, compact = TRUE, column = "x_float") {
    result <- read_dta(path, col_select = tidyselect::all_of(column), n_max = count,
                       use_numeric_altrep = compact)[[column]]
    if (compact) result else as.double(result)
}

test_that("float comparisons preserve all missing ranks and signed-zero ties", {
    plain <- c(-5, -0, 0, 5, NA_real_, tagged_missing(letters))
    other <- rev(plain)
    for (retained in c(FALSE, TRUE)) {
        x <- dta_float(plain)
        y <- dta_float(other)
        if (retained) {
            x <- .float_comparison_freeze(x, 3L)
            y <- .float_comparison_freeze(y, 7L)
        }
        .float_comparison_expect(x, y, plain, other)
        .float_comparison_expect(y, x, other, plain)
        for (scalar in c(-0, 0, NA_real_, tagged_missing(letters))) {
            .float_comparison_expect(x, scalar, plain, scalar)
            .float_comparison_expect(scalar, x, scalar, plain)
        }
        expect_identical(as.double(x), plain)
        expect_identical(as.double(y), other)
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(y))
    }
})

test_that("float scalar comparisons preserve double precision at float boundaries", {
    plain <- c(1, 1 + 2^-23, -1, -1 - 2^-23, 2^24, 2^24 + 2,
               2^-149, -2^-149, -0, 0, NA_real_, tagged_missing("z"))
    scalars <- c(1 + 2^-24, 1 + 2^-25, -1 - 2^-24, 2^24 + 1,
                 2^-150, -2^-150, -Inf, Inf)
    for (x in list(dta_float(plain), .float_comparison_freeze(dta_float(plain), 5L))) {
        for (scalar in scalars) {
            .float_comparison_expect(x, scalar, plain, scalar)
            .float_comparison_expect(scalar, x, scalar, plain)
        }
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
        expect_identical(as.double(x), plain)
    }
})

test_that("float comparison spans cross unequal retained chunks in serial and auto modes", {
    size <- 600007L
    plain <- rep_len(c(-5, -0, 0, 5, NA_real_, tagged_missing(letters)), size)
    other <- rep_len(c(tagged_missing(rev(letters)), NA_real_, 5, 0, -0, -5), size)
    x <- .float_comparison_freeze(dta_float(plain), 8191L)
    y <- .float_comparison_freeze(dta_float(other), 16385L)
    before <- .Call(C_dtatools_owned_numeric_info, x)[["compatibility_bytes"]]
    previous <- options(dtatools.threads = 1L)
    on.exit(options(previous), add = TRUE)
    for (threads in c(1L, 0L)) {
        options(dtatools.threads = threads)
        .float_comparison_expect(x, y, plain, other)
        .float_comparison_expect(x, 0.5, plain, 0.5)
    }
    expect_identical(.Call(C_dtatools_owned_numeric_info, x)[["compatibility_bytes"]], before)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(y))
    expect_identical(as.double(x), plain)
    expect_identical(as.double(y), other)
})

test_that("modern float imports retain tag gaps high values and infinity ordering", {
    bits <- c(0, 0x80000000, 1, 0x80000001, 0x7effffff,
              0x7f000000, 0x7f000001, 0x7f0007ff, 0x7f000800,
              0x7f00d000, 0x7f00d001, 0x7f00d800,
              0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000)
    left_path <- .float_comparison_fixture(bits)
    right_path <- .float_comparison_fixture(rev(bits))
    on.exit(unlink(c(left_path, right_path)), add = TRUE)
    source <- .float_comparison_read(left_path, length(bits))
    partner <- .float_comparison_read(right_path, length(bits))
    plain <- .float_comparison_read(left_path, length(bits), FALSE)
    other <- .float_comparison_read(right_path, length(bits), FALSE)
    for (retained in c(FALSE, TRUE)) {
        x <- if (retained) .float_comparison_freeze(source, 3L) else source
        y <- if (retained) .float_comparison_freeze(partner, 5L) else partner
        .float_comparison_expect(x, y, plain, other)
        for (scalar in c(0, Inf, -Inf, NA_real_, tagged_missing("a"), tagged_missing("z")))
            .float_comparison_expect(x, scalar, plain, scalar)
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(y))
        expect_identical(as.double(x), plain)
        expect_identical(as.double(y), other)
    }
})

test_that("invalid float NaNs decline pair and scalar comparisons before fallback errors", {
    for (bits in c(0x7fc00001, 0xffc00001, 0x7f800001, 0xff800001)) {
        path <- .float_comparison_fixture(c(0x3f800000, bits, 0x7f000800))
        source <- .float_comparison_read(path, 3L)
        unlink(path)
        other <- dta_float(c(1, 2, tagged_missing("a")))
        for (x in list(source, .float_comparison_freeze(source, 1L))) {
            for (op in c("==", "!=", "<", "<=", ">", ">=")) {
                operation <- getExportedValue("base", op)
                expect_null(dtatools:::.dta_compare_native(op, x, other))
                expect_null(dtatools:::.dta_compare_native(op, other, x))
                expect_null(dtatools:::.dta_compare_native(op, x, 1))
                expect_error(operation(x, other), "noncanonical NaN")
                expect_error(operation(other, x), "noncanonical NaN")
                expect_error(operation(x, 1), "noncanonical NaN")
            }
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(other))
        }
    }
})

test_that("temporal float comparisons use decoded equality after rounding collapse", {
    bits <- c(0, 1, 0x80000001, 0x3f800000, 0x3f800001,
              0x7f000000, 0x7f000800, 0x7f00d000)
    permutation <- c(2L, 3L, 1L, 5L, 4L, 8L, 6L, 7L)
    for (format in c("%td", "%tc")) {
        left_path <- .float_comparison_fixture(bits, format)
        right_path <- .float_comparison_fixture(bits[permutation], format)
        source <- .float_comparison_read(left_path, length(bits))
        partner <- .float_comparison_read(right_path, length(bits))
        plain <- .float_comparison_read(left_path, length(bits), FALSE)
        other <- .float_comparison_read(right_path, length(bits), FALSE)
        unlink(c(left_path, right_path))
        expect_true(inherits(source, "dta_temporal"))
        # Three different physical floats become the same R date/datetime.
        expect_identical(plain[1:3], rep(plain[[1L]], 3L))
        for (retained in c(FALSE, TRUE)) {
            x <- if (retained) .float_comparison_freeze(source, 3L) else source
            y <- if (retained) .float_comparison_freeze(partner, 5L) else partner
            .float_comparison_expect(x, y, plain, other)
            .float_comparison_expect(x, plain[[1L]], plain, plain[[1L]])
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(y))
        }
    }
})

test_that("legacy float comparisons retain version-specific missing domains", {
    for (version in c(105L, 108L, 110L, 111L)) {
        path <- fixture(paste0("synthetic_v", version, ".dta"))
        source <- .float_comparison_read(path, 4L, column = "f")
        plain <- .float_comparison_read(path, 4L, FALSE, "f")
        other <- rev(plain)
        modern <- dta_float(other)
        for (x in list(source, .float_comparison_freeze(source, 1L))) {
            .float_comparison_expect(x, modern, plain, other)
            .float_comparison_expect(modern, x, other, plain)
            .float_comparison_expect(x, tagged_missing("a"), plain, tagged_missing("a"))
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
        }
    }

    original <- readBin(fixture("synthetic_v111.dta"), "raw",
                        n = file.info(fixture("synthetic_v111.dta"))[["size"]])
    prefix <- c(as.raw(1), writeBin(321L, raw(), size = 2L, endian = "little"),
                writeBin(-123456L, raw(), size = 4L, endian = "little"),
                writeBin(1.5, raw(), size = 4L, endian = "little"),
                writeBin(-2.25, raw(), size = 8L, endian = "little"))
    start <- grepRaw(prefix, original, fixed = TRUE, all = TRUE)
    expect_length(start, 1L)
    # Identical raw bits have different meanings under legacy and modern rules.
    bits <- c(0x7f000001, 0x7f000800, 0x7f00d001, 0x7f800000)
    legacy_path <- tempfile(fileext = ".dta")
    modern_path <- .float_comparison_fixture(bits)
    on.exit(unlink(c(legacy_path, modern_path)), add = TRUE)
    for (row in seq_along(bits)) {
        location <- start + (row - 1L) * 25L + 7L
        original[location + 0:3] <- as.raw(floor(bits[[row]] / 256^(0:3)) %% 256)
    }
    writeBin(original, legacy_path)
    legacy <- .float_comparison_read(legacy_path, 4L, column = "f")
    modern <- .float_comparison_read(modern_path, 4L)
    old_plain <- .float_comparison_read(legacy_path, 4L, FALSE, "f")
    new_plain <- .float_comparison_read(modern_path, 4L, FALSE)
    expect_identical(old_plain, rep(NA_real_, 4L))
    for (retained in c(FALSE, TRUE)) {
        x <- if (retained) .float_comparison_freeze(legacy, 1L) else legacy
        y <- if (retained) .float_comparison_freeze(modern, 3L) else modern
        .float_comparison_expect(x, y, old_plain, new_plain)
        .float_comparison_expect(y, x, new_plain, old_plain)
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(y))
    }
})
