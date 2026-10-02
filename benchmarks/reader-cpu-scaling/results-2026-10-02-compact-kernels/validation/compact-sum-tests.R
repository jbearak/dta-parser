owned_numeric_info <- function(x) .Call(C_dtatools_owned_numeric_info, x)
freeze_numeric <- function(x, chunk_rows = 2) {
    .Call(C_dtatools_owned_numeric_freeze, x, chunk_rows)
}

test_that("compact sums match ordered ordinary sums across types and missing permutations", {
    sum_bytes <- function(x, remove) {
        writeBin(sum(as.double(x), na.rm = remove), raw(), size = 8L, endian = "little")
    }
    fixtures <- list(numeric(), -0, c(-0, 0), c(0, -0), c(-1, 0, 1),
                     c(NA_real_, tagged_missing("a"), tagged_missing("z")),
                     c(tagged_missing("a"), NA_real_, tagged_missing("z")),
                     c(tagged_missing("z"), tagged_missing("a"), NA_real_),
                     c(1, tagged_missing("a"), -1, NA_real_, tagged_missing("z")),
                     rep_len(c(7, -3, 1, 0, -1), 65L))
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        for (values in fixtures) {
            source <- constructor(values)
            for (chunk_rows in c(0, 1, 3, 16)) {
                value <- if (chunk_rows == 0) source else freeze_numeric(source, chunk_rows)
                before <- owned_numeric_info(value)[["compatibility_bytes"]]
                for (remove in c(FALSE, TRUE)) {
                    expect_identical(sum_bytes(value, remove), sum_bytes(values, remove))
                }
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
                expect_equal(owned_numeric_info(value)[["compatibility_bytes"]], before)
            }
        }
    }
})

test_that("compact sums retain legacy integer domains and non-Stata float payloads", {
    sum_bytes <- function(x, remove) {
        writeBin(sum(as.double(x), na.rm = remove), raw(), size = 8L, endian = "little")
    }
    ordinary <- function(x) {
        readBin(writeBin(as.double(x), raw(), size = 8L), "double", n = length(x))
    }
    for (version in c(105L, 108L, 110L, 111L)) {
        columns <- read_dta(fixture(paste0("synthetic_v", version, ".dta")), output = "tibble")
        for (source in columns) {
            if (!dtatools:::.is_unmaterialized_numeric_altrep(source)) next
            plain <- ordinary(source)
            for (value in list(source, freeze_numeric(source, 1), freeze_numeric(source, 3))) {
                for (remove in c(FALSE, TRUE)) {
                    expect_identical(sum_bytes(value, remove), sum_bytes(plain, remove))
                }
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
            }
        }
    }

    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    bits <- c(0x7fc00001, 0xffc00001, 0x3f800000, 0x7f000000,
              0x7f000800, 0x7f00d000, 0x7f800000, 0xff800000, 0x80000000)
    for (index in seq_along(bits)) {
        raw <- as.raw(floor(bits[[index]] / 256^(0:3)) %% 256)
        patch_numeric_fixture_row(path, index - 1L, list(x_float = raw))
    }
    source <- read_dta(path, col_select = "x_float", n_max = length(bits))$x_float
    for (rows in list(1:9, 9:1, c(4L, 1L, 5L, 2L, 6L),
                      c(5L, 1L, 4L, 2L, 6L), c(6L, 2L, 1L, 5L, 4L),
                      c(7L, 8L, 3L), c(8L, 7L, 3L), c(9L, 3L))) {
        selected <- source[rows]
        plain <- ordinary(selected)
        for (value in list(selected, freeze_numeric(selected, 1), freeze_numeric(selected, 4))) {
            for (remove in c(FALSE, TRUE)) {
                expect_identical(sum_bytes(value, remove), sum_bytes(plain, remove))
            }
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
        }
    }
})

test_that("compact sums apply date and datetime conversion before ordered accumulation", {
    sum_bytes <- function(x, remove) {
        writeBin(sum(as.double(x), na.rm = remove), raw(), size = 8L, endian = "little")
    }
    specifications <- list(
        list(kind = 1L, origin = -3653, storages = c("byte", "int", "long", "float")),
        list(kind = 2L, origin = -315619200, storages = c("int", "long", "float"))
    )
    for (spec in specifications) {
        fixtures <- list(numeric(), spec$origin + c(-1, 0, 1),
                         c(NA_real_, tagged_missing("a"), tagged_missing("z")),
                         c(spec$origin - 1, tagged_missing("z"), spec$origin + 1, NA_real_))
        for (storage in spec$storages) {
            for (values in fixtures) {
                source <- dtatools:::.construct_dta_numeric(values, NULL, storage, temporal = spec$kind)
                for (value in list(source, freeze_numeric(source, 1), freeze_numeric(source, 3))) {
                    for (remove in c(FALSE, TRUE)) {
                        expect_identical(sum_bytes(value, remove), sum_bytes(values, remove))
                    }
                    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
                }
            }
        }
    }
})
