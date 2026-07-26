args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L || !args[[2L]] %in% c("direct-r", "rust-vectors")) {
    stop("usage: Rscript memory-worker.R INPUT_DTA direct-r|rust-vectors")
}

path <- normalizePath(args[[1L]])
materialization <- args[[2L]]
script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_path <- normalizePath(sub("^--file=", "", script_argument), winslash = "/")
checkout_root <- normalizePath(file.path(dirname(script_path), "..", ".."), winslash = "/")
benchmark_library <- Sys.getenv("DTAPARSER_BENCH_LIB")
if (!nzchar(benchmark_library)) {
    stop("set DTAPARSER_BENCH_LIB to a library containing dtaparser built from this checkout")
}
benchmark_library <- normalizePath(benchmark_library, winslash = "/")
if (!startsWith(benchmark_library, paste0(checkout_root, "/"))) {
    stop("DTAPARSER_BENCH_LIB must point to a library inside this checkout")
}
.libPaths(c(benchmark_library, .libPaths()))
if (!requireNamespace("dtaparser", quietly = TRUE)) {
    stop("DTAPARSER_BENCH_LIB does not contain a loadable dtaparser installation")
}
loaded_library <- normalizePath(dirname(find.package("dtaparser")), winslash = "/")
if (!identical(loaded_library, benchmark_library)) {
    stop("dtaparser was not loaded from DTAPARSER_BENCH_LIB")
}

result <- if (identical(materialization, "direct-r")) {
    dtaparser::read_dta(path)
} else {
    dtaparser:::.read_dta_rust_vectors(path)
}
cat(sprintf(
    "%s: %d rows, %d columns, %.3f MB final R object\n",
    materialization, nrow(result), ncol(result),
    as.numeric(utils::object.size(result)) / 1e6
))
