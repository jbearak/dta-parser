args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("usage: wide-generate.R OUTPUT_DTA")
benchmark_library <- Sys.getenv("DTAPARSER_BENCH_LIB")
if (!nzchar(benchmark_library)) stop("DTAPARSER_BENCH_LIB is required")
.libPaths(c(normalizePath(benchmark_library, mustWork = TRUE), .libPaths()))
data <- setNames(
    as.data.frame(rep(list(1L), 32768L), optional = TRUE),
    paste0("x", seq_len(32768L))
)
dtaparser::write_dta(data, args[[1L]], version = 19L)
