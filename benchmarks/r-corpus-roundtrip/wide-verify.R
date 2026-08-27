args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("usage: wide-verify.R INPUT_DTA")
benchmark_library <- Sys.getenv("DTAPARSER_BENCH_LIB")
if (!nzchar(benchmark_library)) stop("DTAPARSER_BENCH_LIB is required")
.libPaths(c(normalizePath(benchmark_library, mustWork = TRUE), .libPaths()))
if (!requireNamespace("dtaparser", quietly = TRUE) ||
    !requireNamespace("haven", quietly = TRUE)) {
    stop("dtaparser and haven are required")
}
expected <- c(1L, 32768L)
stopifnot(
    identical(dim(dtaparser::read_dta(args[[1L]])), expected),
    identical(dim(haven::read_dta(args[[1L]])), expected)
)
