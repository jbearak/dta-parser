args <- commandArgs(trailingOnly = TRUE)
iterations <- if (length(args)) as.integer(args[[1]]) else 25L
stopifnot(is.finite(iterations), iterations >= 1L, iterations <= 10000L)

if (!requireNamespace("dtatools", quietly = TRUE)) {
    stop("dtatools must be installed; this benchmark never reports a skipped PASS")
}

fixture_dir <- file.path(getwd(), "tests", "fixtures", "dta")
cases <- c(
    modern_all_types = "all_types_v118.dta",
    wide = "wide_v118.dta",
    strl = "strl_test_v118.dta",
    legacy = "all_types_v115.dta"
)

measure <- function(operation) {
    gc()
    elapsed <- system.time(for (index in seq_len(iterations)) operation())[["elapsed"]]
    elapsed * 1000 / iterations
}

cat("case\tphase\tinput_bytes\titerations\tmean_ms\n")
for (case_name in names(cases)) {
    path <- file.path(fixture_dir, cases[[case_name]])
    size <- file.info(path)$size
    projection_names <- utils::head(names(dtatools::read_dta(path, n_max = 0)), 2L)
    native <- measure(function() dtatools::read_dta(path))
    cat(case_name, "native-wrapper-allocation-population", size, iterations,
        sprintf("%.6f", native), sep = "\t")
    cat("\n")
    projected <- measure(function() dtatools::read_dta(
        path, col_select = tidyselect::all_of(projection_names), skip = 1, n_max = 16
    ))
    cat(case_name, "native-projected-two-columns", size, iterations,
        sprintf("%.6f", projected), sep = "\t")
    cat("\n")
    if (requireNamespace("haven", quietly = TRUE)) {
        haven <- measure(function() haven::read_dta(
            path, col_select = tidyselect::all_of(projection_names),
            skip = 1, n_max = 16
        ))
        cat(case_name, "haven-projected-two-columns", size, iterations,
            sprintf("%.6f", haven), sep = "\t")
        cat("\n")
    } else {
        message("SKIP haven benchmark for ", case_name, ": package not installed")
    }
}
