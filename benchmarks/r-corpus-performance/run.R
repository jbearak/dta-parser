args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L || length(args) > 3L) {
    stop("usage: Rscript run.R CACHE_ROOT OUTPUT_DIR [MAX_FILES_PER_CORPUS]")
}
if (!requireNamespace("processx", quietly = TRUE)) {
    stop("the processx package is required")
}

script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_path <- normalizePath(sub("^--file=", "", script_argument), winslash = "/")
script_dir <- dirname(script_path)
source(file.path(script_dir, "common.R"), local = TRUE)

cache_root <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
output_dir <- normalizePath(args[[2L]], winslash = "/", mustWork = FALSE)
max_files <- if (length(args) == 3L) as.integer(args[[3L]]) else Inf
if (length(max_files) != 1L || is.na(max_files) || max_files < 1L) {
    stop("MAX_FILES_PER_CORPUS must be a positive integer")
}
benchmark_library <- Sys.getenv("DTAPARSER_BENCH_LIB")
if (!nzchar(benchmark_library)) stop("DTAPARSER_BENCH_LIB is required")
benchmark_library <- normalizePath(benchmark_library, winslash = "/", mustWork = TRUE)

worker_path <- file.path(script_dir, "worker.R")
stata_worker_path <- file.path(script_dir, "stata-worker.do")
rscript <- Sys.which("Rscript")
time_command <- "/usr/bin/time"
if (!nzchar(rscript) || !file.exists(time_command)) {
    stop("Rscript and /usr/bin/time are required")
}
stata_candidates <- c(
    Sys.getenv("STATA_BIN"),
    "/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp",
    Sys.which("stata-mp"), Sys.which("stata")
)
stata_candidates <- unique(stata_candidates[nzchar(stata_candidates)])
stata_candidates <- stata_candidates[file.exists(stata_candidates)]
if (!length(stata_candidates)) stop("Stata is required; set STATA_BIN if needed")
stata <- normalizePath(stata_candidates[[1L]], winslash = "/", mustWork = TRUE)

walk_dta <- function(directory) {
    entries <- list.files(
        directory, all.files = TRUE, full.names = TRUE,
        no.. = TRUE, recursive = FALSE
    )
    result <- character()
    for (path in entries) {
        if (nzchar(Sys.readlink(path))) next
        info <- file.info(path, extra_cols = FALSE)
        if (is.na(info$isdir)) stop(sprintf("cannot inspect %s", path))
        if (isTRUE(info$isdir)) {
            result <- c(result, walk_dta(path))
        } else if (grepl("[.]dta$", basename(path), ignore.case = TRUE)) {
            result <- c(result, normalizePath(path, winslash = "/"))
        }
    }
    result
}

corpus_names <- c("DHS", "MICS", "NSFG")
corpus_roots <- setNames(file.path(cache_root, corpus_names), corpus_names)
if (!all(dir.exists(corpus_roots))) {
    stop("CACHE_ROOT must contain DHS, MICS, and NSFG directories")
}
inventory_rows <- lapply(names(corpus_roots), function(corpus) {
    paths <- walk_dta(corpus_roots[[corpus]])
    relative_paths <- substring(paths, nchar(cache_root, type = "chars") + 2L)
    info <- file.info(paths, extra_cols = TRUE)
    order_index <- order(relative_paths, method = "radix")
    paths <- paths[order_index]
    relative_paths <- relative_paths[order_index]
    info <- info[order_index, , drop = FALSE]
    data.frame(
        corpus = corpus,
        id = sprintf("%s-%04d", corpus, seq_along(paths)),
        relative_path = relative_paths,
        path = paths,
        release = vapply(paths, corpus_dta_release, integer(1)),
        bytes = as.double(info$size),
        mtime = as.numeric(info$mtime),
        stringsAsFactors = FALSE
    )
})
inventory <- do.call(rbind, inventory_rows)

# Largest inputs are visited first. Alternating reader order then distributes
# first-reader cache effects across the files that dominate aggregate time.
inventory <- inventory[order(-inventory$bytes, inventory$relative_path, method = "radix"), ]
inventory <- do.call(rbind, lapply(split(inventory, inventory$corpus), function(items) {
    if (is.finite(max_files)) head(items, max_files) else items
}))
rownames(inventory) <- NULL
if (anyDuplicated(inventory$id)) stop("inventory ID collision")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
raw_path <- file.path(output_dir, "raw.tsv")
inventory_path <- file.path(output_dir, "inventory.tsv")
write.table(
    inventory[c("corpus", "id", "relative_path", "release", "bytes", "mtime")],
    inventory_path, sep = "\t", row.names = FALSE, quote = TRUE
)

parse_memory <- function(stderr) {
    lines <- strsplit(stderr, "\n", fixed = TRUE)[[1L]]
    if (identical(Sys.info()[["sysname"]], "Darwin")) {
        rss_line <- grep("maximum resident set size", lines, value = TRUE)
        footprint_line <- grep("peak memory footprint", lines, value = TRUE)
        rss <- if (length(rss_line)) {
            as.numeric(sub("^ *([0-9]+).*$", "\\1", tail(rss_line, 1L)))
        } else NA_real_
        footprint <- if (length(footprint_line)) {
            as.numeric(sub("^ *([0-9]+).*$", "\\1", tail(footprint_line, 1L)))
        } else NA_real_
    } else {
        rss_line <- grep("Maximum resident set size [(]kbytes[)]", lines, value = TRUE)
        rss <- if (length(rss_line)) {
            1024 * as.numeric(sub("^.*: *([0-9]+).*$", "\\1", tail(rss_line, 1L)))
        } else NA_real_
        footprint <- NA_real_
    }
    c(rss_bytes = rss, footprint_bytes = footprint)
}

measure_r <- function(item, reader, order_index) {
    time_arguments <- if (identical(Sys.info()[["sysname"]], "Darwin")) "-l" else "-v"
    process <- processx::run(
        time_command,
        c(time_arguments, rscript, "--vanilla", worker_path, reader, item$path),
        env = c(
            DTAPARSER_BENCH_LIB = benchmark_library,
            R_ENVIRON_USER = "/dev/null",
            R_PROFILE_USER = "/dev/null"
        ),
        error_on_status = FALSE,
        echo = FALSE
    )
    marker <- grep("^DTAPARSER_BENCH\\t", strsplit(process$stdout, "\n")[[1L]], value = TRUE)
    fields <- if (length(marker)) strsplit(tail(marker, 1L), "\t", fixed = TRUE)[[1L]] else character()
    memory <- parse_memory(process$stderr)
    valid <- length(fields) == 5L && fields[[1L]] == "DTAPARSER_BENCH"
    data.frame(
        corpus = item$corpus,
        id = item$id,
        reader = reader,
        reader_order = order_index,
        status = if (valid) fields[[2L]] else "worker-error",
        elapsed_seconds = if (valid) as.numeric(fields[[3L]]) else NA_real_,
        rows = if (valid) as.numeric(fields[[4L]]) else NA_real_,
        columns = if (valid) as.numeric(fields[[5L]]) else NA_real_,
        rss_bytes = unname(memory[["rss_bytes"]]),
        footprint_bytes = unname(memory[["footprint_bytes"]]),
        stringsAsFactors = FALSE
    )
}

measure_stata <- function(item, order_index) {
    work_dir <- file.path(output_dir, "stata-work", item$id)
    unlink(work_dir, recursive = TRUE, force = TRUE)
    dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
    input_link <- file.path(work_dir, "input.dta")
    if (file.exists(input_link) || nzchar(Sys.readlink(input_link))) unlink(input_link)
    if (!file.symlink(item$path, input_link)) {
        return(data.frame(
            corpus = item$corpus, id = item$id, reader = "stata",
            reader_order = order_index, status = "input-alias-error",
            elapsed_seconds = NA_real_, rows = NA_real_, columns = NA_real_,
            rss_bytes = NA_real_, footprint_bytes = NA_real_,
            stringsAsFactors = FALSE
        ))
    }
    file.copy(stata_worker_path, file.path(work_dir, "stata-worker.do"), overwrite = TRUE)
    time_arguments <- if (identical(Sys.info()[["sysname"]], "Darwin")) "-l" else "-v"
    process <- processx::run(
        time_command,
        c(time_arguments, stata, "-q", "-b", "do", "stata-worker.do"),
        wd = work_dir, error_on_status = FALSE, echo = FALSE
    )
    result_path <- file.path(work_dir, "result.tsv")
    fields <- if (file.exists(result_path)) {
        trimws(strsplit(readLines(result_path, n = 1L, warn = FALSE), "\t", fixed = TRUE)[[1L]])
    } else character()
    memory <- parse_memory(process$stderr)
    valid <- length(fields) == 4L
    stata_number <- function(field) {
        if (!nzchar(field) || field %in% c("NA", ".")) NA_real_ else as.numeric(field)
    }
    result <- data.frame(
        corpus = item$corpus,
        id = item$id,
        reader = "stata",
        reader_order = order_index,
        status = if (valid) fields[[1L]] else "worker-error",
        elapsed_seconds = if (valid) stata_number(fields[[2L]]) else NA_real_,
        rows = if (valid) stata_number(fields[[3L]]) else NA_real_,
        columns = if (valid) stata_number(fields[[4L]]) else NA_real_,
        rss_bytes = unname(memory[["rss_bytes"]]),
        footprint_bytes = unname(memory[["footprint_bytes"]]),
        stringsAsFactors = FALSE
    )
    unlink(work_dir, recursive = TRUE, force = TRUE)
    result
}

raw_columns <- c(
    "corpus", "id", "reader", "reader_order", "status", "elapsed_seconds",
    "rows", "columns", "rss_bytes", "footprint_bytes"
)
if (file.exists(raw_path)) {
    existing <- read.delim(raw_path, check.names = FALSE, stringsAsFactors = FALSE)
    if (!identical(names(existing), raw_columns)) stop("existing raw.tsv has an invalid schema")
    completed <- paste(existing$corpus, existing$id, existing$reader, sep = "\037")
} else {
    completed <- character()
}
for (index in seq_len(nrow(inventory))) {
    item <- inventory[index, , drop = FALSE]
    orders <- list(
        c("dtaparser", "haven", "stata"),
        c("haven", "stata", "dtaparser"),
        c("stata", "dtaparser", "haven")
    )
    readers <- orders[[((index - 1L) %% length(orders)) + 1L]]
    for (reader_index in seq_along(readers)) {
        reader <- readers[[reader_index]]
        key <- paste(item$corpus, item$id, reader, sep = "\037")
        if (key %in% completed) next
        measured <- if (identical(reader, "stata")) {
            measure_stata(item, reader_index)
        } else {
            measure_r(item, reader, reader_index)
        }
        write.table(
            measured, raw_path, sep = "\t", row.names = FALSE, quote = TRUE,
            append = file.exists(raw_path), col.names = !file.exists(raw_path)
        )
        completed <- c(completed, key)
    }
    cat(sprintf("%d/%d: %s\n", index, nrow(inventory), item$id))
}

raw <- read.delim(raw_path, check.names = FALSE, stringsAsFactors = FALSE)
paired <- corpus_pair_results(raw, inventory)
summary <- corpus_performance_summary(inventory, paired, names(corpus_roots))
write.table(
    summary, file.path(output_dir, "summary.tsv"),
    sep = "\t", row.names = FALSE, quote = FALSE
)
print(summary, row.names = FALSE)
