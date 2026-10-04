test_that("strict float constructors establish an allocation domain proof", {
    x <- dta_float(c(-2^-149, -0, 0, 2^-149, -3, 3, NA_real_, tagged_missing(letters)))
    before <- writeBin(as.double(x), raw(), size = 8L)
    expect_true(.Call(C_dtatools_numeric_domain_info, x))
    expect_identical(writeBin(as.double(x), raw(), size = 8L), before)
    expect_false(.Call(C_dtatools_numeric_domain_info, dta_long(c(1, NA_real_))))
    # Removing the R class can retain the same compact bytes and their proof.
    expect_true(.Call(C_dtatools_numeric_domain_info, as.double(x)))
    expect_false(.Call(C_dtatools_numeric_domain_info, c(1, 2)))
    restored <- unserialize(serialize(x, NULL))
    expect_false(.Call(C_dtatools_numeric_domain_info, restored))
    expect_identical(writeBin(as.double(restored), raw(), size = 8L), before)
})

.domain_bytes <- function(x) writeBin(as.double(x), raw(), size = 8L, endian = "little")
.domain_strict <- function(x) .Call(C_dtatools_numeric_domain_info, x)
.domain_facts <- function(x) .Call(C_dtatools_numeric_facts_info, x)
.domain_expected_facts <- function(flags, maximum = 0, minimum = 0, zeros = 0) {
    c(flags = flags, max_magnitude_bound = maximum,
      min_nonzero_magnitude_bound = minimum, zero_count = zeros)
}

test_that("compact facts describe final encoded values and independent counts", {
    x <- dta_float(c(-0, 0, -2^-150, 2^-150, -2^-149, 2^-149,
                     -3, 3, NA_real_, tagged_missing(letters)))
    expect_identical(.domain_facts(x), .domain_expected_facts(7, 0x40400000, 1, 4))
    expect_identical(.domain_facts(as.double(x)), .domain_facts(x))
    expect_identical(.domain_facts(dta_float(numeric())),
                     .domain_expected_facts(7, 0, 0xffffffff, 0))
    expect_identical(.domain_facts(dta_float(c(NA_real_, tagged_missing(letters)))),
                     .domain_expected_facts(7, 0, 0xffffffff, 0))
    expect_identical(.domain_facts(dta_float(c(-0, 0, NA_real_))),
                     .domain_expected_facts(7, 0, 0xffffffff, 2))
    largest <- readBin(as.raw(c(255, 255, 255, 126)), "numeric", size = 4L,
                       endian = "little")
    expect_identical(.domain_facts(dta_float(c(-largest, largest))),
                     .domain_expected_facts(7, 0x7effffff, 0x7effffff, 0))
    for (constructor in list(dta_byte, dta_int, dta_long)) {
        expect_identical(.domain_facts(constructor(c(-1, -0, 0, 1, NA_real_,
                                                    tagged_missing(letters)))),
                         .domain_expected_facts(4, 0, 0, 2))
    }
    expect_identical(.domain_facts(c(0, 1)), .domain_expected_facts(0))
})

test_that("facts are retained only by descriptors for unchanged immutable bytes", {
    values <- c(-0, 0, 2^-149, -3, 3, NA_real_, tagged_missing(letters))
    x <- dta_float(values)
    expected <- .domain_facts(x)
    frozen <- .Call(C_dtatools_owned_numeric_freeze, x, 7L)
    alias <- .Call(C_dtatools_metadata_copy, frozen)
    expect_identical(.domain_facts(frozen), expected)
    expect_identical(.domain_facts(alias), expected)
    .Call(C_dtatools_patch_vector, frozen, 1L, 7)
    expect_identical(.domain_facts(frozen)[["flags"]], 0)
    expect_identical(.domain_facts(alias), expected)
    expect_identical(.domain_facts(x), expected)
    .Call(C_dtatools_patch_vector, x, 1L, 7)
    expect_identical(.domain_facts(x)[["flags"]], 0)
    .force_altrep_materialization(alias)
    expect_identical(.domain_facts(alias), .domain_expected_facts(0))

    x <- dta_float(values)
    for (copy in list(x[c(2L, 3L, 6L)],
                     .Call(C_dtatools_gather_numeric, x, NULL, c(2L, 3L, 6L), NULL),
                     unserialize(serialize(x, NULL)))) {
        expect_identical(.domain_facts(copy)[["flags"]], 0)
    }
})

test_that("compact domain proofs follow retained bytes and writable invalidation", {
    values <- rep(c(-2^-149, -0, 0, 2^-149, -3, 3, NA_real_, tagged_missing(letters)), 4L)
    x <- dta_float(values)
    frozen <- .Call(C_dtatools_owned_numeric_freeze, x, 7L)
    alias <- .Call(C_dtatools_metadata_copy, frozen)
    expect_true(.domain_strict(frozen))
    expect_true(.domain_strict(alias))
    expect_identical(.domain_bytes(frozen), .domain_bytes(x))
    .Call(C_dtatools_patch_vector, frozen, 1L, 7)
    expect_false(.domain_strict(frozen))
    expect_true(.domain_strict(alias))
    expect_identical(as.double(frozen)[[1L]], 7)
    expect_identical(.domain_bytes(alias), .domain_bytes(x))
    .Call(C_dtatools_patch_vector, x, 1L, 7)
    expect_false(.domain_strict(x))
    expect_identical(as.double(x)[[1L]], 7)
    x <- dta_float(values)
    .force_altrep_materialization(x)
    expect_false(.domain_strict(x))
    expect_identical(.domain_bytes(x), writeBin(values, raw(), size = 8L, endian = "little"))
})

test_that("reader and freeze validation grant only strict compact domains", {
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    withr::defer(unlink(path))
    raw_bits <- function(x) as.raw(floor(x / 256^(0:3)) %% 256)
    bits <- c(0, 0x80000000, 1, 0x80000001, 0x7effffff, 0xfeffffff,
        0x7f000000 + (0:26) * 2048, 0x7f000001, 0xff000001,
        0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00001, 0xff800001)
    for (index in seq_along(bits)) {
        patch_numeric_fixture_row(path, 0L, list(x_float = raw_bits(bits[[index]])))
        x <- read_dta(path, col_select = "x_float", n_max = 2L)$x_float
        expect_identical(.domain_strict(x), index <= 33L)
        expected <- .domain_bytes(x)
        frozen <- .Call(C_dtatools_owned_numeric_freeze, x, 1L)
        # Both validators prove the same bytes; imports do not normalize them.
        expect_identical(.domain_strict(frozen), index <= 33L)
        expect_identical(.domain_facts(frozen)[["flags"]], if (index <= 33L) 7 else 0)
        expect_identical(.domain_facts(x), .domain_facts(frozen))
        expect_identical(.domain_bytes(frozen), expected)
        restored <- unserialize(serialize(frozen, NULL))
        expect_false(.domain_strict(restored))
        expect_identical(.domain_facts(restored)[["flags"]], 0)
        expect_identical(.domain_bytes(restored), expected)
    }
    legacy <- read_dta(fixture("synthetic_v111.dta"), col_select = "f")$f
    expect_false(.domain_strict(legacy))
    expect_identical(.domain_facts(legacy)[["flags"]], 0)
    expect_false(.domain_strict(.Call(C_dtatools_owned_numeric_freeze, legacy, 1L)))
})

test_that("freeze validates captured bytes across reentry and releases failed claims", {
    withr::defer(.Call(C_dtatools_test_numeric_freeze_checkpoint, 0L, NULL))
    n <- 16385L
    values <- rep(c(1, NA_real_, tagged_missing("z")), length.out = n)
    for (retained in c(FALSE, TRUE)) for (action in c("patch", "materialize")) {
        x <- dta_float(values)
        if (retained) x <- .Call(C_dtatools_owned_numeric_freeze, x, 7L)
        original <- .domain_bytes(x)
        original_facts <- .domain_facts(x)
        fired <- 0L
        local({
            token <- new.env(parent = emptyenv())
            reg.finalizer(token, function(key) {
                fired <<- fired + 1L
                if (action == "patch") .Call(C_dtatools_patch_vector, x, n, 7)
                else .force_altrep_materialization(x)
            }, onexit = FALSE)
            .Call(C_dtatools_test_numeric_freeze_checkpoint, 1L, token)
        })
        result <- .Call(C_dtatools_owned_numeric_freeze, x, 11L)
        expect_identical(fired, 1L)
        expect_true(.domain_strict(result))
        expect_identical(.domain_facts(result), original_facts)
        expect_identical(.domain_bytes(result), original)
        expect_true(anyNA(result))
        if (action == "patch") expect_identical(as.double(x)[[n]], 7)
        else expect_false(.domain_strict(x))
    }
    x <- dta_float(values)
    .Call(C_dtatools_test_numeric_freeze_checkpoint, 2L, NULL)
    expect_error(.Call(C_dtatools_owned_numeric_freeze, x, 7L), "injected numeric freeze checkpoint failure")
    expect_true(.domain_strict(x))
    expect_identical(.domain_facts(x), .domain_expected_facts(7, 0x3f800000, 0x3f800000, 0))
    before <- .Call(C_dtatools_native_copy_stats, FALSE)[["compact_copy"]]
    .Call(C_dtatools_patch_vector, x, 1L, 7)
    after <- .Call(C_dtatools_native_copy_stats, FALSE)[["compact_copy"]]
    expect_identical(after - before, 0)
    expect_false(.domain_strict(x))
    expect_identical(.domain_facts(x)[["flags"]], 0)
    expect_identical(as.double(x)[[1L]], 7)
})
