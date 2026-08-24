args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L || length(args) > 4L ||
        !args[[2L]] %in% c("dtaparser", "rust-vectors", "haven")) {
    stop(paste(
        "usage: Rscript memory-worker.R INPUT_DTA dtaparser|rust-vectors|haven",
        "[dimensions|object-size] [full|projected-eight-columns]"
    ))
}

path <- normalizePath(args[[1L]])
materialization <- args[[2L]]
workload <- if (length(args) >= 3L) args[[3L]] else "object-size"
selection <- if (length(args) == 4L) args[[4L]] else "full"
if (!workload %in% c("dimensions", "object-size")) {
    stop("workload must be dimensions or object-size")
}
if (!selection %in% c("full", "projected-eight-columns")) {
    stop("selection must be full or projected-eight-columns")
}
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

projection <- c(
    "id", "income", "age", "region", "interview_date", "case_code",
    "occupation", "description"
)
read_arguments <- list(path)
if (identical(selection, "projected-eight-columns")) {
    read_arguments$col_select <- tidyselect::all_of(projection)
}
result <- if (identical(materialization, "dtaparser")) {
    do.call(dtaparser::read_dta, read_arguments)
} else if (identical(materialization, "haven")) {
    do.call(haven::read_dta, read_arguments)
} else {
    do.call(dtaparser:::.read_dta_rust_vectors, read_arguments)
}
if (identical(workload, "object-size")) {
    cat(sprintf(
        "%s/%s/%s: %d rows, %d columns, %.3f MB final R object\n",
        materialization, selection, workload, nrow(result), ncol(result),
        as.numeric(utils::object.size(result)) / 1e6
    ))
} else {
    cat(sprintf(
        "%s/%s/%s: %d rows, %d columns\n",
        materialization, selection, workload, nrow(result), ncol(result)
    ))
}
