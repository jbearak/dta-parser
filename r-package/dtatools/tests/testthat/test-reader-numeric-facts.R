.reader_facts <- function(x) .Call(C_dtatools_numeric_facts_info, x)
.reader_facts_bytes <- function(x) writeBin(as.double(x), raw(), size = 8L, endian = "little")
.reader_facts_expected <- function(values, storage) {
    observed <- values[!is.na(values)]
    zeros <- sum(observed == 0)
    if (storage != "float") return(c(flags = 4, max_magnitude_bound = 0,
        min_nonzero_magnitude_bound = 0, zero_count = as.double(zeros)))
    bits <- readBin(writeBin(abs(observed), raw(), size = 4L, endian = "little"),
                    "integer", length(observed), size = 4L, endian = "little")
    c(flags = 7, max_magnitude_bound = if (length(bits)) as.double(max(bits)) else 0,
      min_nonzero_magnitude_bound = if (any(bits != 0L)) as.double(min(bits[bits != 0L])) else 0xffffffff,
      zero_count = as.double(zeros))
}

.reader_facts_native <- function(env = parent.frame()) {
    prior <- .Call(C_dtatools_test_numeric_size_minimum, 0L)
    withr::defer(.Call(C_dtatools_test_numeric_size_minimum, prior), envir = env)
    invisible(dta_double(c(1, 2)) + 1)
}

.reader_facts_reciprocal <- function(source, storage) {
    before <- .reader_facts_bytes(source)
    facts <- .reader_facts(source)
    values <- as.double(source)
    expected <- 1.01 / values
    expected[!is.finite(expected) | abs(expected) > (2^53 - 1) * 2^970] <- NA_real_
    if (storage == "float") {
        observed <- !is.na(expected)
        expected[observed] <- readBin(writeBin(expected[observed], raw(), size = 4L,
                                             endian = "little"), "numeric", sum(observed),
                                      size = 4L, endian = "little")
    }
    entries <- .Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
    result <- 1.01 / source
    expect_identical(.Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]] - entries,
                     if (.dtatools_numeric_entry_expected("scalar")) 1 else 0)
    expect_identical(dta_storage_type(result), storage)
    expect_identical(.reader_facts_bytes(result), .reader_facts_bytes(expected))
    expect_identical(is.na(result), is.na(expected))
    expect_identical(anyNA(result), anyNA(expected))
    expect_identical(.reader_facts_bytes(source), before)
    expect_identical(.reader_facts(source), facts)
    original <- .reader_facts_bytes(result)
    mutable <- dibble(x = result)
    replace_values(mutable, x = 0, where = which(is.na(expected)))
    expected[is.na(expected)] <- 0
    expect_identical(.reader_facts_bytes(mutable$x), .reader_facts_bytes(expected))
    expect_false(anyNA(mutable$x))
    expect_identical(.reader_facts_bytes(result), original)
}

test_that("DTA and Arrow readers publish facts for the returned compact extent", {
    .reader_facts_native()
    n <- 65539L
    integer_values <- rep(c(-3, -1, 0, 1, 3, NA_real_, tagged_missing("z")), length.out = n)
    float_values <- rep(c(0, -0, 0.125, -3, 3, NA_real_, tagged_missing("z")), length.out = n)
    when <- dtatools:::.construct_dta_numeric(
        rep(c(0, 1, NA_real_), length.out = n), NULL, "float", temporal = 1L)
    when <- dtatools:::.attach_dta_temporal(when,
        structure(double(), format.stata = "%td",
                  class = c("dta_temporal", "dta_date", "Date")), "float")
    data <- dibble(b = dta_byte(integer_values), i = dta_int(integer_values),
                   l = dta_long(integer_values), f = dta_float(float_values), when = when)
    dta_path <- tempfile(fileext = ".dta")
    arrow_path <- tempfile(fileext = ".arrow")
    withr::defer(unlink(c(dta_path, arrow_path)))
    save_dta(data, dta_path)
    save_arrow(data, arrow_path)
    windows <- list(c(0L, n), c(3L, 65536L), c(n - 3L, 3L), c(n, 0L))
    for (source in list(list(read = read_dta, path = dta_path),
                        list(read = read_arrow, path = arrow_path))) {
        for (threads in c(1L, 2L)) for (window in windows) {
            result <- source$read(source$path, skip = window[[1L]], n_max = window[[2L]],
                                  threads = threads, use_numeric_altrep = TRUE)
            positions <- if (window[[2L]]) seq.int(window[[1L]] + 1L, length.out = window[[2L]]) else integer()
            expect_identical(names(result), names(data))
            for (name in c("b", "i", "l", "f")) {
                values <- as.double(data[[name]])[positions]
                storage <- dta_storage_type(data[[name]])
                expect_identical(length(result[[name]]), length(values))
                expect_identical(dta_storage_type(result[[name]]), storage)
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(result[[name]]))
                expect_identical(.reader_facts(result[[name]]), .reader_facts_expected(values, storage))
                expect_identical(.reader_facts_bytes(result[[name]]), .reader_facts_bytes(values))
                expect_identical(is.na(result[[name]]), is.na(values))
                expect_identical(anyNA(result[[name]]), anyNA(values))
                if (length(values)) .reader_facts_reciprocal(result[[name]],
                    if (storage == "long") "double" else "float")
            }
            expect_identical(.reader_facts(result$when)[["flags"]], 0)
        }
    }
})

test_that("reader FLOAT facts decline invalid tails and legacy values without normalization", {
    raw_bits <- function(bits) as.raw(floor(bits / 256^(0:3)) %% 256)
    invalid <- c(0x7f000001, 0xff000000, 0x7f7fffff, 0xff7fffff,
                 0x7f800000, 0xff800000, 0x7f800001, 0xffc00001)
    dta_path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    arrow_path <- tempfile(fileext = ".arrow")
    withr::defer(unlink(c(dta_path, arrow_path)))
    patch_numeric_fixture_row(dta_path, 0L, list(x_float = raw_bits(0)))
    patch_numeric_fixture_row(dta_path, 1L, list(x_float = raw_bits(0x80000000)))
    patch_numeric_fixture_row(dta_path, 2L, list(x_float = raw_bits(1)))
    for (bits in invalid) {
        patch_numeric_fixture_row(dta_path, 26L, list(x_float = raw_bits(bits)))
        for (threads in c(1L, 2L)) {
            full <- read_dta(dta_path, col_select = "x_float", n_max = 27L, threads = threads)$x_float
            eager <- read_dta(dta_path, col_select = "x_float", n_max = 27L,
                              threads = threads, use_numeric_altrep = FALSE)$x_float
            selected <- read_dta(dta_path, col_select = "x_float", n_max = 26L, threads = threads)$x_float
            expect_identical(.reader_facts(full)[["flags"]], 0)
            expect_identical(.reader_facts_bytes(full), .reader_facts_bytes(eager))
            expect_identical(.reader_facts(selected), c(flags = 7, max_magnitude_bound = 1,
                min_nonzero_magnitude_bound = 1, zero_count = 2))
            expect_true(anyNA(full))
        }
    }
    sentinel <- raw_bits(0x3fc12345)
    values <- rep(c(0, -0, 1), length.out = 257L)
    values[[257L]] <- readBin(sentinel, "numeric", size = 4L, endian = "little")
    save_arrow(dibble(x = dta_float(values)), arrow_path)
    original <- readBin(arrow_path, "raw", n = file.info(arrow_path)[["size"]])
    location <- grepRaw(sentinel, original, fixed = TRUE, all = TRUE)
    expect_length(location, 1L)
    for (bits in invalid) {
        bytes <- original
        bytes[location + 0:3] <- raw_bits(bits)
        writeBin(bytes, arrow_path)
        for (threads in c(1L, 2L)) {
            # Deliberately altered payload: disable verification to exercise
            # the permissive reader's raw numeric semantics, not checksums.
            full <- read_arrow(arrow_path, verify = FALSE, threads = threads)$x
            eager <- read_arrow(arrow_path, verify = FALSE, threads = threads,
                                use_numeric_altrep = FALSE)$x
            selected <- read_arrow(arrow_path, verify = FALSE, threads = threads, n_max = 256L)$x
            expect_identical(.reader_facts(full)[["flags"]], 0)
            expect_identical(.reader_facts_bytes(full), .reader_facts_bytes(eager))
            expect_identical(.reader_facts(selected), .reader_facts_expected(values[1:256], "float"))
            expect_identical(anyNA(full), anyNA(eager))
        }
    }
    legacy <- read_dta(fixture("synthetic_v111.dta"), col_select = "f")$f
    expect_identical(.reader_facts(legacy)[["flags"]], 0)
})

test_that("reader facts retain immutable owners and writable access invalidates them", {
    .reader_facts_native()
    values <- rep(c(0, -0, 0.125, -3, 3, NA_real_, tagged_missing("z")), length.out = 257L)
    dta_path <- tempfile(fileext = ".dta")
    arrow_path <- tempfile(fileext = ".arrow")
    withr::defer(unlink(c(dta_path, arrow_path)))
    save_dta(dibble(x = dta_float(values)), dta_path)
    save_arrow(dibble(x = dta_float(values)), arrow_path)
    for (source in list(read_dta(dta_path)$x, read_arrow(arrow_path)$x)) {
        expected <- .reader_facts_expected(values, "float")
        expect_identical(.reader_facts(source), expected)
        .reader_facts_reciprocal(source, "float")
        info <- .Call(C_dtatools_owned_numeric_info, source)
        retained <- !is.null(info) && isTRUE(info[["owned"]] == 1)
        alias <- .Call(C_dtatools_metadata_copy, source)
        expect_identical(.reader_facts(alias)[["flags"]], if (retained) 7 else 0)
        .Call(C_dtatools_patch_vector, source, 3L, 2^-149)
        expect_identical(.reader_facts(source)[["flags"]], 0)
        expect_identical(.reader_facts_bytes(alias), .reader_facts_bytes(values))
        expect_identical(.reader_facts(alias)[["flags"]], if (retained) 7 else 0)
        .reader_facts_reciprocal(source, "double")
        .reader_facts_reciprocal(alias, "float")
        expect_identical(.reader_facts(unserialize(serialize(alias, NULL)))[["flags"]], 0)
        expect_identical(.reader_facts(alias[c(1L, 2L, 3L)])[["flags"]], 0)
        .force_altrep_materialization(alias)
        expect_identical(.reader_facts(alias)[["flags"]], 0)
    }
})
