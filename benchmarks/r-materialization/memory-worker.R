args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L || !args[[2L]] %in% c("direct-r", "rust-vectors")) {
    stop("usage: Rscript memory-worker.R INPUT_DTA direct-r|rust-vectors")
}

path <- normalizePath(args[[1L]])
materialization <- args[[2L]]
if (!requireNamespace("dtaparser", quietly = TRUE)) {
    stop("dtaparser is required")
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
