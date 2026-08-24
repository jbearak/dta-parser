args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) {
    stop("usage: Rscript string-workloads.R INPUT_DTA OUTPUT_TSV [ITERATIONS]")
}

path <- normalizePath(args[[1L]])
output <- normalizePath(args[[2L]], mustWork = FALSE)
iterations <- if (length(args) >= 3L) as.integer(args[[3L]]) else 21L
stopifnot(is.finite(iterations), iterations >= 1L)

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

reference <- dtaparser:::.read_dta_rust_vectors(path)
character_columns <- names(reference)[vapply(reference, is.character, logical(1))]
numeric_columns <- names(reference)[vapply(reference, is.numeric, logical(1))]
subset_rows <- if (nrow(reference) == 0L) {
    integer()
} else {
    unique(as.integer(round(seq(1, nrow(reference), length.out = 1024L))))
}
expected_dim <- dim(reference)

consume <- function(result, workload) {
    if (identical(workload, "dimensions")) {
        return(sum(dim(result)))
    }
    if (identical(workload, "string-subset")) {
        return(sum(vapply(result[character_columns], function(column) {
            sum(nchar(column[subset_rows], type = "bytes"))
        }, numeric(1))))
    }
    if (identical(workload, "numeric-scan")) {
        return(sum(vapply(result[numeric_columns], sum, numeric(1), na.rm = TRUE)))
    }
    if (identical(workload, "all-string-scan")) {
        return(sum(vapply(result[character_columns], function(column) {
            sum(nchar(column, type = "bytes"))
        }, numeric(1))))
    }
    if (identical(workload, "object-size")) {
        return(as.numeric(utils::object.size(result)))
    }
    stop("unknown workload")
}

workloads <- c(
    "dimensions", "string-subset", "numeric-scan",
    "all-string-scan", "object-size"
)
expected_checksums <- vapply(workloads, function(workload) {
    consume(reference, workload)
}, numeric(1))
rm(reference)
invisible(gc())

rows <- vector("list", iterations * length(workloads))
position <- 1L
for (iteration in seq_len(iterations)) {
    order <- if (iteration %% 2L) workloads else rev(workloads)
    for (workload in order) {
        invisible(gc())
        started <- proc.time()[["elapsed"]]
        result <- dtaparser::read_dta(path)
        checksum <- consume(result, workload)
        elapsed <- proc.time()[["elapsed"]] - started
        stopifnot(
            identical(dim(result), expected_dim),
            is.finite(checksum),
            identical(workload, "object-size") || isTRUE(all.equal(
                checksum, expected_checksums[[workload]],
                tolerance = 0, check.attributes = FALSE
            ))
        )
        rows[[position]] <- data.frame(
            workload = workload,
            iteration = iteration,
            elapsed_s = elapsed,
            checksum = checksum
        )
        position <- position + 1L
        rm(result)
    }
}

raw <- do.call(rbind, rows)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
write.table(raw, output, sep = "\t", row.names = FALSE, quote = FALSE)

summary <- do.call(rbind, lapply(split(raw$elapsed_s, raw$workload), function(x) {
    data.frame(
        iterations = length(x),
        median_s = median(x),
        p05_s = unname(quantile(x, 0.05)),
        p95_s = unname(quantile(x, 0.95))
    )
}))
summary$workload <- row.names(summary)
row.names(summary) <- NULL
summary <- summary[c("workload", "iterations", "median_s", "p05_s", "p95_s")]
print(summary, row.names = FALSE)
