# A Stata file with one string variable of 400 rows over 200 distinct
# values, so subsets of up to 12 rows are at most a sixteenth as long as the
# dictionary.
.dictstring_fixture <- function(envir = parent.frame()) {
    path <- tempfile(fileext = ".dta")
    withr::defer(unlink(path), envir = envir)
    save_dta(dibble(s = sprintf("value %03d", rep(1:200, 2))), path)
    path
}

test_that("empty subsets of compact strings leave the dictionary alone", {
    data <- read_dta(fixture("all_types_v118.dta"))
    compact <- data$v_str20
    expect_true(dtatools:::.is_unmaterialized_dictstring(compact))
    # Serialization writes the values, so the copy holds ordinary strings.
    twin <- unserialize(serialize(compact, NULL))
    expect_false(dtatools:::.is_unmaterialized_dictstring(twin))
    cached <- dtatools:::.dictstring_cached_count(compact)
    for (index in list(integer(), double(), FALSE)) {
        empty <- .subset(compact, index)
        expect_identical(empty, character())
        expect_false(dtatools:::.is_unmaterialized_dictstring(empty))
        expect_identical(compact[index], twin[index])
        expect_identical(vctrs::vec_slice(compact, index),
                         vctrs::vec_slice(twin, index))
    }
    expect_identical(vctrs::vec_ptype(compact), vctrs::vec_ptype(twin))
    expect_identical(vctrs::vec_ptype2(compact, ""), vctrs::vec_ptype2(twin, ""))
    expect_identical(dtatools:::.dictstring_cached_count(compact), cached)
    expect_true(dtatools:::.is_unmaterialized_dictstring(compact))
    # A subset with values still gathers them over the dictionary.
    expect_true(dtatools:::.is_unmaterialized_dictstring(compact[2:1]))
})

test_that("short subsets of compact strings are ordinary strings", {
    path <- .dictstring_fixture()
    twin <- unserialize(serialize(read_dta(path)$s, NULL))
    compact <- read_dta(path)$s
    expect_true(dtatools:::.is_unmaterialized_dictstring(compact))
    # One value comes from the cache, the others from the dictionary.
    expect_identical(.subset2(compact, 7L), "value 007")
    cached <- dtatools:::.dictstring_cached_count(compact)
    expect_identical(cached, 1)
    for (index in list(c(7L, 207L, 7L, 3L), 12:1, c(400, 1), 1:13, 400:1)) {
        result <- .subset(compact, index)
        expect_identical(result, .subset(twin, index))
        expect_identical(dtatools:::.is_unmaterialized_dictstring(result),
                         length(index) > 12L)
        expect_identical(compact[index], twin[index])
        expect_identical(vctrs::vec_slice(compact, index),
                         vctrs::vec_slice(twin, index))
    }
    expect_identical(dtatools:::.dictstring_cached_count(compact), cached)
    # The rows of each group, as a grouped verb slices them. Grouping reads
    # every value, so it fills the cache.
    groups <- rep(1:40, length.out = 400L)
    expect_identical(vctrs::vec_split(compact, groups),
                     vctrs::vec_split(twin, groups))
    expect_true(dtatools:::.is_unmaterialized_dictstring(compact))
})

test_that("casts into strL storage do not measure the values", {
    data <- read_dta(fixture("all_types_v118.dta"))
    compact <- data$v_str20
    first <- as.character(compact)[[1L]]
    expected <- as.character(compact) == first
    prototype <- dta_string("a", storage = "strL")
    long <- strrep("x", 3000L)
    local_mocked_bindings(
        .dta_string_required_width = function(x) stop("measured"),
        .package = "dtatools"
    )
    expect_identical(compact == first, expected)
    expect_identical(compact != first, !expected)
    cast <- vctrs::vec_cast(c(long, NA), prototype)
    expect_identical(as.character(cast), c(long, ""))
    expect_identical(attr(cast, "stata.string.storage"), "strL")
})

test_that("an index that materializes the source while it is read still subsets", {
    path <- tempfile(fileext = ".arrow")
    withr::defer(unlink(path))
    save_arrow(data.frame(x = c("alpha", "beta", "alpha")), path)
    long <- .dictstring_fixture()
    # The probe, its rows, the file, and whether the subset stays compact.
    probes <- list(
        list(C_dtatools_callback_length, c(3L, 2L), "arrow", TRUE),
        list(C_dtatools_callback_length, integer(), "arrow", FALSE),
        list(C_dtatools_callback_length, c(3L, 2L), "dta", FALSE),
        list(C_dtatools_callback_integer, c(3L, 2L), "dta", FALSE)
    )
    for (probe in probes) {
        value <- if (probe[[3L]] == "arrow") {
            read_arrow(path, output = "tibble")$x
        } else {
            read_dta(long)$s
        }
        expected <- as.character(unserialize(serialize(value, NULL)))[probe[[2L]]]
        expect_true(dtatools:::.is_unmaterialized_dictstring(value))
        index <- .Call(probe[[1L]], probe[[2L]], function() {
            dtatools:::.force_altrep_materialization(value)
            gc()
        })
        result <- .Call(dtatools:::C_dtatools_dictstring_subset, value, index)
        expect_identical(as.character(result), expected)
        expect_identical(dtatools:::.is_unmaterialized_dictstring(result),
                         probe[[4L]])
        expect_false(dtatools:::.is_unmaterialized_dictstring(value))
    }
})
