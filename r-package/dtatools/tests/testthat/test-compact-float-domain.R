test_that("strict float constructors establish an allocation domain proof", {
    x <- dta_float(c(-2^-149, -0, 0, 2^-149, -3, 3, NA_real_, tagged_missing(letters)))
    before <- writeBin(as.double(x), raw(), size = 8L)
    expect_true(.Call(C_dtatools_numeric_domain_info, x))
    expect_identical(writeBin(as.double(x), raw(), size = 8L), before)
    expect_false(.Call(C_dtatools_numeric_domain_info, dta_long(c(1, NA_real_))))
    expect_false(.Call(C_dtatools_numeric_domain_info, as.double(x)))
    restored <- unserialize(serialize(x, NULL))
    expect_false(.Call(C_dtatools_numeric_domain_info, restored))
    expect_identical(writeBin(as.double(restored), raw(), size = 8L), before)
})

.domain_bytes <- function(x) writeBin(as.double(x), raw(), size = 8L, endian = "little")
.domain_strict <- function(x) .Call(C_dtatools_numeric_domain_info, x)

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

test_that("imports and restored compact payloads do not assert strict domains", {
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    withr::defer(unlink(path))
    raw_bits <- function(x) as.raw(floor(x / 256^(0:3)) %% 256)
    bits <- c(0, 0x80000000, 1, 0x80000001, 0x7effffff, 0xfeffffff,
        0x7f000000 + (0:26) * 2048, 0x7f000001, 0xff000001,
        0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00001, 0xff800001)
    for (index in seq_along(bits)) {
        patch_numeric_fixture_row(path, 0L, list(x_float = raw_bits(bits[[index]])))
        x <- read_dta(path, col_select = "x_float", n_max = 2L)$x_float
        expect_false(.domain_strict(x))
        expected <- .domain_bytes(x)
        frozen <- .Call(C_dtatools_owned_numeric_freeze, x, 1L)
        # Only the test adapter's new independent validation can grant a fact.
        expect_identical(.domain_strict(frozen), index <= 33L)
        expect_identical(.domain_bytes(frozen), expected)
        restored <- unserialize(serialize(frozen, NULL))
        expect_false(.domain_strict(restored))
        expect_identical(.domain_bytes(restored), expected)
    }
    legacy <- read_dta(fixture("synthetic_v111.dta"), col_select = "f")$f
    expect_false(.domain_strict(legacy))
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
        expect_identical(.domain_bytes(result), original)
        expect_true(anyNA(result))
        if (action == "patch") expect_identical(as.double(x)[[n]], 7)
        else expect_false(.domain_strict(x))
    }
    x <- dta_float(values)
    .Call(C_dtatools_test_numeric_freeze_checkpoint, 2L, NULL)
    expect_error(.Call(C_dtatools_owned_numeric_freeze, x, 7L), "injected numeric freeze checkpoint failure")
    expect_true(.domain_strict(x))
    before <- .Call(C_dtatools_native_copy_stats, FALSE)[["compact_copy"]]
    .Call(C_dtatools_patch_vector, x, 1L, 7)
    after <- .Call(C_dtatools_native_copy_stats, FALSE)[["compact_copy"]]
    expect_identical(after - before, 0)
    expect_false(.domain_strict(x))
    expect_identical(as.double(x)[[1L]], 7)
})
