args <- commandArgs(trailingOnly = TRUE)
.libPaths(c(args[[1]], .libPaths()))
library(dtatools)
repo <- '<repo>'
reference_file <- file.path(repo, 'r-package/dtatools/tests/testthat/test-native-summary-kernels.R')
eval(parse(reference_file)[[1]])
set.seed(18204)
checks <- 0L
for (iteration in seq_len(300)) {
    n <- sample(c(0:50, 4095:4097), 1)
    scale <- sample(c(1, 1e-100, 1e100), 1)
    x <- sample(c(-9:9, NA_real_), n, TRUE) * scale
    if (n && iteration %% 3L == 0L) x[seq.int(1L, n, 7L)] <- tagged_missing('q')
    w <- sample(c(-3:6, .1, .2, .5, NA_real_), n, TRUE)
    kind <- sample(c('aweight', 'fweight', 'iweight'), 1)
    detail <- sample(c(FALSE, TRUE), 1)
    meanonly <- !detail && sample(c(FALSE, TRUE), 1)
    expected <- .native_summary_reference(x, w, kind, detail, meanonly)
    actual <- dtatools:::.summarize_statistics(dta_double(x), w, kind, detail, meanonly)
    if (!identical(actual, expected)) {
        saveRDS(list(x = x, w = w, kind = kind, detail = detail, meanonly = meanonly,
                     actual = actual, expected = expected),
                '<work>/summary-mismatch.rds')
        stop('summary mismatch in iteration ', iteration, ': ',
             paste(all.equal(actual, expected, tolerance = 0), collapse = '; '))
    }
    for (remove in c(FALSE, TRUE)) {
        actual <- mean(dta_double(x), na.rm = remove)
        expected <- dtatools:::.dta_computed(dtatools:::.collapse_missing(
            mean(x, na.rm = remove)), 'double')
        stopifnot(identical(actual, expected))
        actual <- suppressWarnings(range(dta_double(x), na.rm = remove))
        expected <- suppressWarnings(range(x, na.rm = remove))
        if (n) expected <- dtatools:::.dta_computed(
            dtatools:::.collapse_missing(expected), 'double')
        stopifnot(identical(actual, expected))
    }
    checks <- checks + 5L
}
cat(checks, 'exact randomized summary, mean and range comparisons passed\n')
