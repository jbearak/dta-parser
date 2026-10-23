.descriptor_managed <- function(value) .Call(C_dtatools_numeric_descriptor_managed, value)

test_that("compact numerics built from R bytes keep their descriptor on R's heap", {
    x <- dta_int(c(1, 2, 3, NA))
    large <- dta_int(seq_len(3000L))
    values <- list(
        constructed = x, byte = dta_byte(c(1, tagged_missing("a"))), long = dta_long(c(5, 6)),
        float = dta_float(c(0.5, 1.5)), computed = mean(x, na.rm = TRUE),
        copied = .metadata_copy(mean(x, na.rm = TRUE)), subset = x[2:3],
        arithmetic = large + 1L, unserialized = unserialize(serialize(x, NULL)),
        gathered = .gather_dta_columns(list(value = x), 2:3)[[1L]],
        split = .split_dta_column(x, list(c(1L, 2L), 3L))[[1L]],
        appended = dta_append(list(dibble(v = x), dibble(v = x)))$v
    )
    for (name in names(values)) expect_true(.descriptor_managed(values[[name]]), info = name)
    expect_identical(.descriptor_managed(1:3), NA)
    expect_identical(.descriptor_managed(dta_double(c(1.5, 2))), NA)
})

test_that("reader columns keep the native owner their finalizer releases", {
    auto <- read_dta(system.file("extdata", "auto_v118.dta", package = "dtatools"))
    managed <- vapply(as.list(auto), .descriptor_managed, NA)
    managed <- managed[!is.na(managed)]
    expect_gt(length(managed), 0L)
    expect_false(any(managed))
    # A subset copies the bytes, so its descriptor is R's.
    subset <- .subset2(auto, names(managed)[[1L]])[1:3]
    expect_true(.descriptor_managed(subset))
})

test_that("compact numerics with R-owned descriptors keep their values", {
    make <- function() {
        x <- dta_int(c(1, 2, NA, 4))
        y <- dta_float(c(0.5, tagged_missing("b"), 2.25))
        list(subset = x[c(1L, 3L)], copy = .metadata_copy(x), computed = mean(x, na.rm = TRUE),
             float = y[2:3], serialized = serialize(y, NULL))
    }
    kept <- make()
    for (i in 1:3) gc(full = TRUE)
    expect_identical(as.double(kept$subset), c(1, NA))
    expect_identical(as.double(kept$copy), c(1, 2, NA, 4))
    # The mean of an int is a float.
    expect_identical(as.double(kept$computed), as.double(dta_float(7 / 3)))
    expect_identical(missing_tag(kept$float), c("b", NA))
    restored <- unserialize(kept$serialized)
    expect_true(.descriptor_managed(restored))
    expect_identical(missing_tag(restored), c(NA, "b", NA))
    expect_identical(as.double(restored), c(0.5, NA, 2.25))
})
