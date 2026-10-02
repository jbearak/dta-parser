owned_numeric_info <- function(x) .Call(C_dtatools_owned_numeric_info, x)
freeze_numeric <- function(x, chunk_rows = 2) {
    .Call(C_dtatools_owned_numeric_freeze, x, chunk_rows)
}

with_numeric_gc_stress <- function(code) {
 previous <- gctorture2(1L)
 on.exit(gctorture2(previous), add = TRUE)
 force(code)
}
# Public missing predicates and the guarded native mask producer must agree.
# The native assertion catches a return to generic scalar fallback independently
# of machine speed; the public assertions keep the semantic contract primary.
test_that("compact missing masks cover all tags tails and retained chunk boundaries", {
    constructors <- list(dta_byte, dta_int, dta_long, dta_float)
    pattern <- c(-1, 0, 1, NA_real_, tagged_missing(letters), 5)
    for (constructor in constructors) {
        for (length in c(0:9, 15:17, 31:33, 65)) {
            expected <- rep_len(pattern, length)
            for (chunk_rows in c(0, 1, 7, 32)) {
                value <- constructor(expected)
                if (chunk_rows > 0) value <- freeze_numeric(value, chunk_rows)
                before <- owned_numeric_info(value)[["compatibility_bytes"]]
                expect_identical(is.na(value), is.na(expected))
                expect_identical(is_missing(value), is.na(expected))
                bare <- dtatools:::.dta_data(value)
                expect_identical(.Call(C_dtatools_owned_missing_mask, bare),
                                 is.na(expected))
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(bare))
                expect_equal(owned_numeric_info(value)[["compatibility_bytes"]], before)
            }
        }
    }
})

test_that("compact missing predicates merge columns without changing recycling or names", {
    left_plain <- rep_len(c(1, NA_real_, tagged_missing("a"), 4), 35L)
    right_plain <- rep_len(c(tagged_missing("z"), 2, 3, NA_real_, 5), 35L)
    expected <- is.na(left_plain) | is.na(right_plain)
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        left <- freeze_numeric(constructor(left_plain), 7)
        right <- freeze_numeric(constructor(right_plain), 3)
        expect_identical(is_missing(left, right), expected)
        expect_identical(is_missing(right, left), expected)
        expect_identical(is_missing(left, right, "seen"), expected)
        expect_identical(is_missing(left, right, ""), rep(TRUE, length(expected)))
        names(left) <- paste0("left", seq_along(left))
        names(right) <- paste0("right", seq_along(right))
        expect_identical(is_missing(left, right), setNames(expected, names(left)))
        expect_identical(is_missing(right, left), setNames(expected, names(right)))
        expect_identical(is.na(left), setNames(is.na(left_plain), names(left)))
        expect_identical(.Call(C_dtatools_owned_missing_mask, dtatools:::.dta_data(left)),
                         setNames(is.na(left_plain), names(left)))
        expect_error(is_missing(left, right[-1L]), "size-one recycling")
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(left))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(right))
    }
})

test_that("compact missing masks preserve shape class and materialized fallbacks", {
    plain <- c(1, NA_real_, tagged_missing("b"), 4)
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        value <- freeze_numeric(constructor(plain), 3)
        names(value) <- letters[1:4]
        expect_identical(is.na(value), setNames(is.na(plain), letters[1:4]))
        bare <- as.double(value)
        dim(bare) <- c(2L, 2L)
        dimnames(bare) <- list(c("a", "b"), c("x", "y"))
        ordinary <- matrix(plain, 2L, dimnames = dimnames(bare))
        expect_identical(dtatools:::.dta_read_is_na(bare), is.na(ordinary))
        expect_error(is_missing(bare), "matrix or array")
        class(bare) <- "compact_missing_dispatch"
        rlang::local_bindings(
            is.na.compact_missing_dispatch = function(x) "custom missing dispatch",
            .env = globalenv())
        expect_identical(dtatools:::.dta_read_is_na(bare), "custom missing dispatch")
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))

        materialized <- as.double(value)
        names(materialized) <- letters[1:4]
        .force_altrep_materialization(materialized)
        .Call(C_dtatools_mutate_first_numeric_altrep, materialized, NA_real_)
        expected <- setNames(c(TRUE, TRUE, TRUE, FALSE), letters[1:4])
        expect_identical(dtatools:::.dta_read_is_na(materialized), expected)
        expect_identical(is_missing(materialized), expected)
        expect_identical(is.na(value), setNames(is.na(plain), letters[1:4]))
    }
})

test_that("compact missing masks agree with eager decoding for legacy and modern floats", {
    # Include both IEEE NaN signs, infinities, finite values adjacent to Stata's
    # missing ladder, and entries just outside its modern upper endpoint.
    bits <- c(0, 0x80000000, 0x3f800000, 0xbf800000,
              0x7effffff, 0x7f000000, 0x7f000001, 0x7f0007ff,
              0x7f000800, 0x7f00d000, 0x7f00d001, 0x7f7fffff,
              0x7f800000, 0xff800000, 0x7fc00001, 0xffc00001,
              0x7f800001, 0xff800001, 0xffffffff, 0xff7fffff)
    raw_bits <- function(value) as.raw(floor(value / 256^(0:3)) %% 256)
    paths <- character()
    on.exit(unlink(paths), add = TRUE)
    modern <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    paths <- c(paths, modern)
    for (index in seq_along(bits)) {
        patch_numeric_fixture_row(modern, index - 1L,
                                  list(x_float = raw_bits(bits[[index]])))
    }
    modern_compact <- read_dta(modern, col_select = "x_float", n_max = length(bits))$x_float
    modern_plain <- as.double(read_dta(modern, col_select = "x_float",
                                      n_max = length(bits), use_numeric_altrep = FALSE)$x_float)
    for (value in list(modern_compact, freeze_numeric(modern_compact, 3))) {
        expect_identical(is.na(value), is.na(modern_plain))
        expect_identical(is_missing(value), is.na(modern_plain))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
    }

    # The first row's complete numeric prefix identifies the data block in the
    # redistributable release-111 fixture without assuming header byte offsets.
    original <- readBin(fixture("synthetic_v111.dta"), "raw",
                        n = file.info(fixture("synthetic_v111.dta"))[["size"]])
    prefix <- c(as.raw(1), writeBin(321L, raw(), size = 2L, endian = "little"),
                writeBin(-123456L, raw(), size = 4L, endian = "little"),
                writeBin(1.5, raw(), size = 4L, endian = "little"),
                writeBin(-2.25, raw(), size = 8L, endian = "little"))
    start <- grepRaw(prefix, original, fixed = TRUE, all = TRUE)
    expect_length(start, 1L)
    legacy <- tempfile(fileext = ".dta")
    paths <- c(paths, legacy)
    for (batch in split(bits, ceiling(seq_along(bits) / 4L))) {
        bytes <- original
        for (row in seq_along(batch)) {
            location <- start + (row - 1L) * 25L + 7L
            bytes[location + 0:3] <- raw_bits(batch[[row]])
        }
        writeBin(bytes, legacy)
        compact <- read_dta(legacy, col_select = "f", n_max = length(batch))$f
        plain <- as.double(read_dta(legacy, col_select = "f", n_max = length(batch),
                                    use_numeric_altrep = FALSE)$f)
        for (value in list(compact, freeze_numeric(compact, 1))) {
            expect_identical(is.na(value), is.na(plain))
            expect_identical(is_missing(value), is.na(plain))
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
        }
    }
})

test_that("compact missing masks keep legacy integer missing domains", {
    for (version in c(105L, 108L, 110L, 111L)) {
        path <- fixture(paste0("synthetic_v", version, ".dta"))
        compact <- read_dta(path, output = "tibble")
        eager <- read_dta(path, output = "tibble", use_numeric_altrep = FALSE)
        for (name in names(compact)) {
            source <- compact[[name]]
            if (!dtatools:::.is_unmaterialized_numeric_altrep(source)) next
            expected <- is.na(as.double(eager[[name]]))
            for (value in list(source, freeze_numeric(source, 1))) {
                expect_identical(is.na(value), expected)
                expect_identical(is_missing(value), expected)
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
            }
        }
    }
})

test_that("compact missing predicates preserve foreign callbacks and short circuits", {
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        calls <- 0L
        source <- freeze_numeric(constructor(c(1, NA_real_, 3, 4)), 2)
        later <- .Call(C_dtatools_callback_double, c(NA_real_, 2, NA_real_, 4),
                       function() {
                           calls <<- calls + 1L
                           .force_altrep_materialization(source)
                           gc()
                       }, TRUE)
        expect_identical(is_missing(source, later), c(TRUE, TRUE, TRUE, FALSE))
        expect_gt(calls, 0L)
        calls <- 0L
        all_missing <- freeze_numeric(constructor(rep(NA_real_, 4L)), 3)
        untouched <- .Call(C_dtatools_callback_double, rep(1, 4L),
                           function() calls <<- calls + 1L, TRUE)
        expect_identical(is_missing(all_missing, untouched), rep(TRUE, 4L))
        expect_identical(calls, 0L)
        expect_identical(is_missing(source, untouched, NA_real_), rep(TRUE, 4L))
        expect_identical(calls, 0L)
    }
})

test_that("compact missing masks retain sources and live view facts across GC", {
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        source <- freeze_numeric(constructor(c(1, NA_real_, tagged_missing("z"), 4)), 2)
        expected <- c(FALSE, TRUE, TRUE, FALSE)
        expect_identical(with_numeric_gc_stress(is.na(source)), expected)
        expect_identical(with_numeric_gc_stress(is_missing(source)), expected)
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(source))

        live <- constructor(c(1, 2, 3, 4))
        views <- .Call(C_dtatools_mutation_views, list(x = live))
        proxy <- views[[1L]]
        expect_identical(is.na(proxy), rep(FALSE, 4L))
        .Call(C_dtatools_patch_vector, live, 2L, NA_real_)
        expect_identical(is.na(proxy), c(FALSE, TRUE, FALSE, FALSE))
        expect_identical(is_missing(proxy), c(FALSE, TRUE, FALSE, FALSE))
        .Call(C_dtatools_patch_vector, live, 2L, 8)
        expect_identical(is.na(proxy), rep(FALSE, 4L))
        expect_identical(is_missing(proxy), rep(FALSE, 4L))
    }
})


test_that("compact missing predicates survive reentrant materialization finalizers", {
    arm_finalizer <- function(finalizer) {
        token <- new.env(parent = emptyenv())
        reg.finalizer(token, finalizer, onexit = FALSE)
        invisible(NULL)
    }
    # The finalizer may run before, during, or after the scan. Explicit GC
    # makes collection deterministic without claiming a private allocation window.
    for (predicate in list(is.na, is_missing)) {
        for (retained in c(FALSE, TRUE)) {
            source <- dta_int(c(1, NA_real_, tagged_missing("z"), 4))
            if (retained) source <- freeze_numeric(source, 2)
            fired <- 0L
            prior <- gctorture2(1L)
            tryCatch({
                arm_finalizer(function(key) {
                    fired <<- fired + 1L
                    .force_altrep_materialization(source)
                })
                result <- predicate(source)
                invisible(gc())
            }, finally = gctorture2(prior))
            expect_identical(fired, 1L)
            expect_identical(result, c(FALSE, TRUE, TRUE, FALSE))
            expect_identical(as.double(source), c(1, NA_real_, tagged_missing("z"), 4))
        }
    }
})


test_that("compact temporal missing predicates preserve converted values and all tags", {
    specifications <- list(
        list(kind = 1L, storage = "int", origin = -3653,
             prototype = structure(double(), format.stata = "%td",
                                   class = c("dta_temporal", "dta_date", "Date"))),
        list(kind = 2L, storage = "long", origin = -315619200,
             prototype = structure(double(), format.stata = "%tc", tzone = "UTC",
                                   class = c("dta_temporal", "dta_datetime", "POSIXct", "POSIXt")))
    )
    for (spec in specifications) {
        values <- c(spec$origin + c(-1, 0, 1), NA_real_, tagged_missing(letters))
        source <- dtatools:::.construct_dta_numeric(
            values, NULL, spec$storage, temporal = spec$kind)
        source <- dtatools:::.attach_dta_temporal(source, spec$prototype, spec$storage)
        for (value in list(source, freeze_numeric(source, 2))) {
            names(value) <- paste0("time", seq_along(value))
            before <- attributes(value)
            expect_identical(is.na(value), is.na(values))
            expect_identical(is_missing(value), setNames(is.na(values), names(value)))
            expect_identical(attributes(value), before)
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
            expect_identical(as.double(value), values)
        }
    }
})
