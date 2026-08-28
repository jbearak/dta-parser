args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L || length(args) > 4L) {
    stop(paste(
        "usage: Rscript stata.R INPUT_DTA OUTPUT_TSV [ITERATIONS]",
        "[full|projected-eight-columns]"
    ))
}
if (!requireNamespace("processx", quietly = TRUE)) stop("processx is required")
script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_path <- normalizePath(
    sub("^--file=", "", script_argument), winslash = "/"
)
script_dir <- dirname(script_path)
sys.source(
    file.path(script_dir, "..", "benchmark-common.R"),
    envir = environment()
)

path <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
output <- normalizePath(args[[2L]], winslash = "/", mustWork = FALSE)
iterations <- if (length(args) >= 3L) as.integer(args[[3L]]) else 7L
workload <- if (length(args) == 4L) args[[4L]] else "full"
if (length(iterations) != 1L || is.na(iterations) || iterations < 1L) {
    stop("ITERATIONS must be a positive integer")
}
if (!workload %in% c("full", "projected-eight-columns")) {
    stop("workload must be full or projected-eight-columns")
}
projection <- c(
    "id", "income", "age", "region", "interview_date", "case_code",
    "occupation", "description"
)
worker <- normalizePath(
    file.path(script_dir, "..", "r-corpus-performance", "stata-worker.do"),
    winslash = "/", mustWork = TRUE
)
stata <- find_stata()

rows <- vector("list", iterations)
for (iteration in seq_len(iterations)) {
    work_dir <- tempfile(pattern = "dtaparser-stata-")
    dir.create(work_dir)
    on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)
    if (!file.symlink(path, file.path(work_dir, "input.dta"))) {
        stop("could not create the private Stata input alias")
    }
    file.copy(worker, file.path(work_dir, "stata-worker.do"))
    if (identical(workload, "projected-eight-columns")) {
        writeLines(paste(projection, collapse = " "), file.path(work_dir, "projection.txt"))
    }
    process <- run_timed_process(
        stata,
        c("-q", "-b", "do", "stata-worker.do"),
        work_dir = work_dir
    )
    result_path <- file.path(work_dir, "result.tsv")
    if (!file.exists(result_path)) stop("Stata did not write a benchmark result")
    fields <- trimws(strsplit(readLines(result_path, n = 1L), "\t", fixed = TRUE)[[1L]])
    if (length(fields) != 4L || fields[[1L]] != "ok") stop("Stata could not load the input")
    memory <- parse_memory_metrics(process$stderr)
    rows[[iteration]] <- data.frame(
        iteration = iteration,
        workload = workload,
        elapsed_seconds = as.numeric(fields[[2L]]),
        rows = as.numeric(fields[[3L]]),
        columns = as.numeric(fields[[4L]]),
        rss_bytes = memory$rss_bytes,
        footprint_bytes = memory$footprint_bytes
    )
    unlink(work_dir, recursive = TRUE, force = TRUE)
}

raw <- do.call(rbind, rows)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
atomic_tsv(raw, output)
print(data.frame(
    workload = workload,
    iterations = nrow(raw),
    median_seconds = median(raw$elapsed_seconds),
    median_peak_rss_gb = median(raw$rss_bytes) / 1e9,
    median_peak_footprint_gb = median(raw$footprint_bytes, na.rm = TRUE) / 1e9
), row.names = FALSE)
