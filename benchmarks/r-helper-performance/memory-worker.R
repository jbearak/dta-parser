arguments <- commandArgs(trailingOnly = TRUE)
operations <- c(
    "factor_from_labels", "haven_as_factor", "tab", "table_haven_factor"
)
if (length(arguments) != 2L || !arguments[[2L]] %in% operations) {
    stop(
        "usage: Rscript memory-worker.R INPUT_DTA OPERATION",
        call. = FALSE
    )
}

benchmark_library <- Sys.getenv("DTATOOLS_BENCH_LIB")
if (!nzchar(benchmark_library)) {
    stop("DTATOOLS_BENCH_LIB is required", call. = FALSE)
}
.libPaths(c(normalizePath(benchmark_library), .libPaths()))

fixture <- normalizePath(arguments[[1L]])
operation <- arguments[[2L]]
source <- dtatools::read_dta(fixture)$x
stopifnot(dtatools:::.is_unmaterialized_numeric_altrep(source))

result <- switch(operation,
    factor_from_labels = dtatools::factor_from_labels(
        source,
        drop_unused = TRUE
    ),
    haven_as_factor = haven::as_factor(source),
    tab = dtatools::tab(source),
    table_haven_factor = table(haven::as_factor(source))
)
stopifnot(length(result) > 0L)
cat(
    "source_materialized ",
    !dtatools:::.is_unmaterialized_numeric_altrep(source),
    "\n",
    sep = ""
)
