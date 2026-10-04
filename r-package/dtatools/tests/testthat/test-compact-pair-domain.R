.pair_domain_enable <- function(env = parent.frame()) {
    prior <- .Call(C_dtatools_test_numeric_size_minimum, 0L)
    withr::defer(.Call(C_dtatools_test_numeric_size_minimum, prior), envir = env)
    invisible(dta_double(c(1, 2)) + 1)
}

.pair_domain_proved <- function(x) .Call(C_dtatools_numeric_domain_info, x)
.pair_domain_bytes <- function(x) writeBin(as.double(x), raw(), size = 8L, endian = "little")
.pair_domain_reference <- function(op, x, y) {
    a <- as.double(x)
    b <- as.double(y)
    values <- suppressWarnings(getExportedValue("base", op)(a, b))
    values[is.na(a) | is.na(b)] <- NA_real_
    dtatools:::.dta_computed(values, "float")
}

.pair_domain_check <- function(op, x, y, info = "") {
    expected <- .pair_domain_reference(op, x, y)
    before <- lapply(list(x, y), .pair_domain_bytes)
    proof <- lapply(list(x, y), .pair_domain_proved)
    .Call(C_dtatools_numeric_entry_stats, TRUE)
    actual <- getExportedValue("base", op)(x, y)
    expect_identical(.Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]],
        if (.dtatools_numeric_entry_expected("scalar")) 1 else 0, info = info)
    expect_identical(dta_storage_type(actual), dta_storage_type(expected), info = info)
    expect_identical(.pair_domain_bytes(actual), .pair_domain_bytes(expected), info = info)
    missing <- is.na(as.double(expected))
    expect_identical(is.na(actual), missing, info = info)
    expect_identical(anyNA(actual), any(missing), info = info)
    if (any(missing)) {
        data <- dibble(value = actual)
        replace_values(data, value = 0, where = which(missing))
        cleared <- as.double(expected)
        cleared[missing] <- 0
        expect_identical(.pair_domain_bytes(data$value), writeBin(cleared, raw(), size = 8L,
            endian = "little"), info = info)
        expect_false(anyNA(data$value), info = info)
        expect_identical(.pair_domain_bytes(actual), .pair_domain_bytes(expected), info = info)
    }
    expect_identical(lapply(list(x, y), .pair_domain_bytes), before, info = info)
    expect_identical(lapply(list(x, y), .pair_domain_proved), proof, info = info)
    invisible(actual)
}

test_that("mixed compact pairs preserve strict and unknown domain results", {
    .pair_domain_enable()
    n <- 131L
    xv <- rep(c(-2, 0, 1, NA_real_, tagged_missing(letters)), length.out = n)
    yv <- rep(c(2^-149, -2^-149, -0, 0, 0.25, -0.25, NA_real_,
        tagged_missing(rev(letters))), length.out = n)
    for (kind in c("byte", "int")) for (retained in c(FALSE, TRUE))
        for (unknown in c(FALSE, TRUE)) {
            x <- get(paste0("dta_", kind))(xv)
            y <- dta_float(yv)
            if (retained) {
                x <- .Call(C_dtatools_owned_numeric_freeze, x, 7L)
                y <- .Call(C_dtatools_owned_numeric_freeze, y, 11L)
            }
            if (unknown) {
                # A same-value write preserves bytes but invalidates the fact.
                .Call(C_dtatools_patch_vector, y, 1L, yv[[1L]])
            }
            expect_identical(.pair_domain_proved(y), !unknown)
            for (op in c("+", "-", "*")) {
                info <- paste(kind, retained, unknown, op)
                .pair_domain_check(op, x, y, info)
                .pair_domain_check(op, y, x, paste(info, "reverse"))
            }
        }
})

test_that("mixed domain pairs retain ambiguous limits and original promotion inputs", {
    .pair_domain_enable()
    from_bits <- function(bits) readBin(as.raw(floor(bits / 256^(0:3)) %% 256),
        "double", n = 1L, size = 4L, endian = "little")
    witnesses <- list(list(bits = 0x7d3a2e8b, multiplier = 11, storage = "double"),
        list(bits = 0x7cd79435, multiplier = 19, storage = "float"))
    for (witness in witnesses) for (retained in c(FALSE, TRUE)) {
        xv <- rep(c(3, -2, 0, NA_real_, tagged_missing("z")), length.out = 131L)
        yv <- rep(c(1 + 2^-23, -0, 0, NA_real_, tagged_missing(letters)), length.out = 131L)
        xv[[131L]] <- witness$multiplier
        yv[[131L]] <- from_bits(witness$bits)
        x <- dta_int(xv)
        y <- dta_float(yv)
        if (retained) {
            x <- .Call(C_dtatools_owned_numeric_freeze, x, 7L)
            y <- .Call(C_dtatools_owned_numeric_freeze, y, 11L)
        }
        for (reverse in c(FALSE, TRUE)) {
            actual <- if (reverse) .pair_domain_check("*", y, x) else
                .pair_domain_check("*", x, y)
            expect_identical(dta_storage_type(actual), witness$storage)
            if (witness$storage == "double")
                expect_identical(as.double(actual)[[1L]], 3 * (1 + 2^-23))
        }
    }
})

test_that("mixed domain read claims retain strict bytes through allocation callbacks", {
    .pair_domain_enable()
    if (!.dtatools_numeric_entry_expected("scalar"))
        skip("arithmetic checkpoint requires an admitted native execution profile")
    withr::defer(.Call(C_dtatools_test_arithmetic_checkpoint, 0L, NULL))
    for (retained in c(FALSE, TRUE)) for (op in c("+", "-", "*")) {
        x <- dta_int(rep(c(1, 3), length.out = 131L))
        y <- dta_float(rep(c(0.25, NA_real_, tagged_missing("z")), length.out = 131L))
        if (retained) y <- .Call(C_dtatools_owned_numeric_freeze, y, 11L)
        alias <- .Call(C_dtatools_metadata_copy, y)
        alias_proof <- .pair_domain_proved(alias)
        # The metadata alias initially shares the strict descriptor. A later
        # plain backing copy starts UNKNOWN; retained clones retain the owner fact.
        expect_true(alias_proof)
        expected <- .pair_domain_reference(op, x, y)
        original <- .pair_domain_bytes(y)
        fired <- 0L
        local({
            token <- new.env(parent = emptyenv())
            reg.finalizer(token, function(key) {
                fired <<- fired + 1L
                .Call(C_dtatools_patch_vector, y, 1L, tagged_missing("a"))
            }, onexit = FALSE)
            .Call(C_dtatools_test_arithmetic_checkpoint, 1L, token)
        })
        .Call(C_dtatools_numeric_entry_stats, TRUE)
        result <- getExportedValue("base", op)(x, y)
        expect_identical(.Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]], 1)
        expect_identical(fired, 1L)
        expect_identical(.pair_domain_bytes(result), .pair_domain_bytes(expected))
        expect_identical(is.na(result), is.na(as.double(expected)))
        expect_false(.pair_domain_proved(y))
        expect_identical(.pair_domain_proved(alias), if (retained) alias_proof else FALSE)
        expect_identical(.pair_domain_bytes(alias), original)
        expect_identical(missing_tag(as.double(y)[[1L]]), "a")
        # The detached current source must use its new missing value on the next call.
        .pair_domain_check(op, x, y)
    }
})

test_that("cached pair bounds preserve FLOAT pairs and observed endpoint storage", {
    .pair_domain_enable()
    from_bits <- function(bits) readBin(as.raw(floor(bits / 256^(0:3)) %% 256),
        "double", n = 1L, size = 4L, endian = "little")
    witnesses <- list(
        list(op = "+", x = 0x7efffffe, y = 0x72800000, storage = "float"),
        list(op = "*", x = 0x5f7ffffe, y = 0x5f000000, storage = "float"),
        list(op = "*", x = 0x5f7fffff, y = 0x5f000000, storage = "float"),
        list(op = "*", x = 0x5f800000, y = 0x5f000000, storage = "double"))
    for (retained in c(FALSE, TRUE)) {
        xv <- rep(c(3, -2, 0, NA_real_, tagged_missing("z")), length.out = 131L)
        yv <- rep(c(1 + 2^-23, -0, 0, NA_real_, tagged_missing("a")), length.out = 131L)
        x <- dta_float(xv)
        y <- dta_float(yv)
        if (retained) {
            x <- .Call(C_dtatools_owned_numeric_freeze, x, 7L)
            y <- .Call(C_dtatools_owned_numeric_freeze, y, 11L)
        }
        expect_identical(.Call(C_dtatools_numeric_facts_info, x)[["flags"]], 7)
        expect_identical(.Call(C_dtatools_numeric_facts_info, y)[["flags"]], 7)
        for (op in c("+", "-", "*")) {
            .pair_domain_check(op, x, y)
            .pair_domain_check(op, y, x)
        }
        .Call(C_dtatools_patch_vector, x, 1L, xv[[1L]])
        expect_identical(.Call(C_dtatools_numeric_facts_info, x)[["flags"]], 0)
        for (op in c("+", "-", "*")) .pair_domain_check(op, x, y)
        for (witness in witnesses) {
            xv[[131L]] <- from_bits(witness$x)
            yv[[131L]] <- from_bits(witness$y)
            x <- dta_float(xv)
            y <- dta_float(yv)
            if (retained) {
                x <- .Call(C_dtatools_owned_numeric_freeze, x, 7L)
                y <- .Call(C_dtatools_owned_numeric_freeze, y, 11L)
            }
            for (reverse in c(FALSE, TRUE)) {
                result <- if (reverse) .pair_domain_check(witness$op, y, x) else
                    .pair_domain_check(witness$op, x, y)
                expect_identical(dta_storage_type(result), witness$storage)
            }
        }
    }
})
