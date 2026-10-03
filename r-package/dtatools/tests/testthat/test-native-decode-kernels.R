.decode_native <- function(name, ...) {
    .Call(get(name, asNamespace("dtatools")), ...)
}

.decode_expect <- function(source, expected, chunks = c(1L, 8191L)) {
    variants <- c(list(source), lapply(chunks, function(chunk)
        .decode_native("C_dtatools_owned_numeric_freeze", source, chunk)))
    expected_bits <- writeBin(expected, raw(), size = 8L, endian = "little")
    for (value in variants) {
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
        invisible(.decode_native("C_dtatools_force_altrep_materialization", value))
        expect_identical(writeBin(as.double(value), raw(), size = 8L, endian = "little"),
                         expected_bits)
        expect_false(dtatools:::.is_unmaterialized_numeric_altrep(value))
    }
}

test_that("compact decode tiles preserve temporal values and every missing payload", {
    count <- 32771L
    missing <- c(NA_real_, tagged_missing(letters))
    for (storage in c("byte", "int", "long", "float")) {
        for (temporal in 0:2) for (layout in c("none", "sparse", "dense")) {
            seed <- if (temporal == 0L) {
                if (storage == "float") c(-1.25, -0, 0, 0.5, 2^60) else c(-100, -1, 0, 1, 100)
            } else if (temporal == 1L) {
                -3653 + c(-1, 0, 1)
            } else if (storage == "byte") {
                -315619200
            } else -315619200 + c(-1, 0, 1)
            expected <- rep_len(seed, count)
            if (layout == "sparse") {
                # Cover both sides of each 16,384-row tile boundary.
                positions <- unique(c(1L, seq.int(16372L, 16398L), 32768L, count))
                expected[positions] <- rep_len(missing, length(positions))
            } else if (layout == "dense") expected <- rep_len(c(seed, missing), count)
            source <- dtatools:::.construct_dta_numeric(
                expected, NULL, storage, temporal = temporal)
            .decode_expect(source, expected, chunks = c(8191L, 32773L))
        }
    }
})

test_that("compact decode keeps modern float gaps infinities and NaN payloads", {
    raw_bits <- function(value) as.raw(floor(value / 256^(0:3)) %% 256)
    reserved <- 0x7f000000 + (0:26) * 0x800
    bits <- unique(c(0, 0x80000000, 0x00000001, 0x80000001,
        0x7effffff, as.vector(outer(reserved, c(-1, 0, 1), "+")),
        0x7f00d800, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000,
        0x7fc00001, 0xffc00001, 0x7f800001, 0xff800001, 0xffffffff))
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    for (batch in split(bits, ceiling(seq_along(bits) / 27L))) {
        for (index in seq_along(batch))
            patch_numeric_fixture_row(path, index - 1L, list(x_float = raw_bits(batch[[index]])))
        source <- read_dta(path, col_select = "x_float", n_max = length(batch))$x_float
        expected <- as.double(read_dta(path, col_select = "x_float", n_max = length(batch),
                                       use_numeric_altrep = FALSE)$x_float)
        .decode_expect(source, expected, chunks = c(1L, 7L))
    }
})

test_that("compact decode retains legacy integer and float missing domains", {
    for (version in c(105L, 108L, 110L, 111L)) {
        path <- fixture(paste0("synthetic_v", version, ".dta"))
        compact <- read_dta(path, output = "tibble")
        eager <- read_dta(path, output = "tibble", use_numeric_altrep = FALSE)
        for (name in names(compact)) {
            if (dtatools:::.is_unmaterialized_numeric_altrep(compact[[name]]))
                .decode_expect(compact[[name]], as.double(eager[[name]]), chunks = 1L)
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
    bits <- c(0, 0x80000000, 0x7effffff, 0x7f000000, 0x7f000001,
              0x7f00d000, 0x7f7fffff, 0x7f800000, 0xff800000,
              0x7fc00001, 0xffc00001, 0x7f800001, 0xff800001)
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    for (batch in split(bits, ceiling(seq_along(bits) / 4L))) {
        bytes <- original
        for (row in seq_along(batch)) {
            location <- start + (row - 1L) * 25L + 7L
            bytes[location + 0:3] <- as.raw(floor(batch[[row]] / 256^(0:3)) %% 256)
        }
        writeBin(bytes, path)
        source <- read_dta(path, col_select = "f", n_max = length(batch))$f
        expected <- as.double(read_dta(path, col_select = "f", n_max = length(batch),
                                       use_numeric_altrep = FALSE)$f)
        .decode_expect(source, expected, chunks = 1L)
    }
})
