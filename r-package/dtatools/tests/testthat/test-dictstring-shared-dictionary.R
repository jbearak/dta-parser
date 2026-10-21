test_that("compact subsets and copies keep the dictionary they share", {
    path <- tempfile(fileext = ".dta")
    withr::defer(unlink(path))
    values <- sprintf("value %03d", rep(1:200, 2))
    save_dta(dibble(s = values), path)
    source <- read_dta(path)$s
    expect_true(dtatools:::.is_unmaterialized_dictstring(source))
    subset <- .subset(source, 400:1)
    copy <- .Call(dtatools:::C_dtatools_deep_copy_value, source)
    for (value in list(subset, copy)) {
        expect_true(dtatools:::.is_unmaterialized_dictstring(value))
    }
    # Materializing the source releases its payload. The others still read
    # the dictionary through theirs.
    dtatools:::.force_altrep_materialization(source)
    rm(source)
    gc()
    expect_identical(as.character(subset), rev(values))
    expect_identical(as.character(unclass(copy)), values)
    # A subset of a subset shares the dictionary too.
    nested <- .subset(subset, 1:300)
    rm(subset)
    gc()
    expect_true(dtatools:::.is_unmaterialized_dictstring(nested))
    expect_identical(as.character(nested), rev(values)[1:300])
})
