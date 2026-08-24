args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L || length(args) > 4L) {
    stop(paste(
        "usage: Rscript stata.R INPUT_DTA OUTPUT_TSV [ITERATIONS]",
        "[full|projected-eight-columns]"
    ))
}
if (!requireNamespace("processx", quietly = TRUE)) stop("processx is required")

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
script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_path <- normalizePath(sub("^--file=", "", script_argument), winslash = "/")
worker <- normalizePath(
    file.path(dirname(script_path), "..", "r-corpus-performance", "stata-worker.do"),
    winslash = "/", mustWork = TRUE
)
stata_candidates <- c(
    Sys.getenv("STATA_BIN"),
    "/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp",
    Sys.which("stata-mp"), Sys.which("stata")
)
stata_candidates <- unique(stata_candidates[nzchar(stata_candidates)])
stata_candidates <- stata_candidates[file.exists(stata_candidates)]
if (!length(stata_candidates)) stop("Stata is required; set STATA_BIN if needed")
stata <- normalizePath(stata_candidates[[1L]], winslash = "/", mustWork = TRUE)

parse_memory <- function(stderr) {
    lines <- strsplit(stderr, "\n", fixed = TRUE)[[1L]]
    if (identical(Sys.info()[["sysname"]], "Darwin")) {
        rss_line <- grep("maximum resident set size", lines, value = TRUE)
        footprint_line <- grep("peak memory footprint", lines, value = TRUE)
        rss <- as.numeric(sub("^ *([0-9]+).*$", "\\1", tail(rss_line, 1L)))
        footprint <- as.numeric(sub("^ *([0-9]+).*$", "\\1", tail(footprint_line, 1L)))
    } else {
        rss_line <- grep("Maximum resident set size [(]kbytes[)]", lines, value = TRUE)
        rss <- 1024 * as.numeric(sub("^.*: *([0-9]+).*$", "\\1", tail(rss_line, 1L)))
        footprint <- NA_real_
    }
    c(rss_bytes = rss, footprint_bytes = footprint)
}

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
    time_arguments <- if (identical(Sys.info()[["sysname"]], "Darwin")) "-l" else "-v"
    process <- processx::run(
        "/usr/bin/time",
        c(time_arguments, stata, "-q", "-b", "do", "stata-worker.do"),
        wd = work_dir, error_on_status = FALSE, echo = FALSE
    )
    result_path <- file.path(work_dir, "result.tsv")
    if (!file.exists(result_path)) stop("Stata did not write a benchmark result")
    fields <- trimws(strsplit(readLines(result_path, n = 1L), "\t", fixed = TRUE)[[1L]])
    if (length(fields) != 4L || fields[[1L]] != "ok") stop("Stata could not load the input")
    memory <- parse_memory(process$stderr)
    rows[[iteration]] <- data.frame(
        iteration = iteration,
        workload = workload,
        elapsed_seconds = as.numeric(fields[[2L]]),
        rows = as.numeric(fields[[3L]]),
        columns = as.numeric(fields[[4L]]),
        rss_bytes = unname(memory[["rss_bytes"]]),
        footprint_bytes = unname(memory[["footprint_bytes"]])
    )
    unlink(work_dir, recursive = TRUE, force = TRUE)
}

raw <- do.call(rbind, rows)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
write.table(raw, output, sep = "\t", row.names = FALSE, quote = FALSE)
print(data.frame(
    workload = workload,
    iterations = nrow(raw),
    median_seconds = median(raw$elapsed_seconds),
    median_peak_rss_gb = median(raw$rss_bytes) / 1e9,
    median_peak_footprint_gb = median(raw$footprint_bytes, na.rm = TRUE) / 1e9
), row.names = FALSE)
