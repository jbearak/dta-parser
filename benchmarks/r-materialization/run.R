args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) {
    stop("usage: Rscript run.R INPUT_DTA OUTPUT_TSV [ITERATIONS]")
}

path <- normalizePath(args[[1L]])
output <- normalizePath(args[[2L]], mustWork = FALSE)
iterations <- if (length(args) >= 3L) as.integer(args[[3L]]) else 21L
stopifnot(is.finite(iterations), iterations >= 1L)

script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_path <- normalizePath(sub("^--file=", "", script_argument), winslash = "/")
checkout_root <- normalizePath(file.path(dirname(script_path), "..", ".."), winslash = "/")
benchmark_library <- Sys.getenv("DTATOOLS_BENCH_LIB")
if (!nzchar(benchmark_library)) {
    stop("set DTATOOLS_BENCH_LIB to a library containing dtatools built from this checkout")
}
benchmark_library <- normalizePath(benchmark_library, winslash = "/")
if (!startsWith(benchmark_library, paste0(checkout_root, "/"))) {
    stop("DTATOOLS_BENCH_LIB must point to a library inside this checkout")
}
.libPaths(c(benchmark_library, .libPaths()))
if (!requireNamespace("dtatools", quietly = TRUE)) {
    stop("DTATOOLS_BENCH_LIB does not contain a loadable dtatools installation")
}
loaded_library <- normalizePath(dirname(find.package("dtatools")), winslash = "/")
if (!identical(loaded_library, benchmark_library)) {
    stop("dtatools was not loaded from DTATOOLS_BENCH_LIB")
}

read_one <- function(materialization) {
    if (identical(materialization, "direct-r")) {
        dtatools::read_dta(path)
    } else {
        dtatools:::.read_dta_rust_vectors(path)
    }
}

direct <- read_one("direct-r")
rust_vectors <- read_one("rust-vectors")
stopifnot(identical(direct, rust_vectors))
expected_dim <- dim(direct)
rm(direct, rust_vectors)
invisible(gc())

rows <- vector("list", iterations * 2L)
position <- 1L
for (iteration in seq_len(iterations)) {
    order <- if (iteration %% 2L) {
        c("direct-r", "rust-vectors")
    } else {
        c("rust-vectors", "direct-r")
    }
    for (materialization in order) {
        invisible(gc())
        started <- proc.time()[["elapsed"]]
        result <- read_one(materialization)
        elapsed <- proc.time()[["elapsed"]] - started
        stopifnot(identical(dim(result), expected_dim))
        rows[[position]] <- data.frame(
            materialization = materialization,
            iteration = iteration,
            elapsed_s = elapsed
        )
        position <- position + 1L
        rm(result)
    }
}

raw <- do.call(rbind, rows)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
write.table(raw, output, sep = "\t", row.names = FALSE, quote = FALSE)

summary <- do.call(rbind, lapply(split(raw$elapsed_s, raw$materialization), function(x) {
    data.frame(
        iterations = length(x),
        median_s = median(x),
        p05_s = unname(quantile(x, 0.05)),
        p95_s = unname(quantile(x, 0.95))
    )
}))
summary$materialization <- row.names(summary)
row.names(summary) <- NULL
summary <- summary[c("materialization", "iterations", "median_s", "p05_s", "p95_s")]
print(summary, row.names = FALSE)
