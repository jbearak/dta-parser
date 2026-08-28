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
benchmark_library <- benchmark_library_path()

worker_path <- file.path(script_dir, "worker.R")
stata_worker_path <- file.path(script_dir, "stata-worker.do")
rscript <- Sys.which("Rscript")
if (!nzchar(rscript) || !file.exists("/usr/bin/time")) {
    stop("Rscript and /usr/bin/time are required")
}
stata <- find_stata()
installed_package <- benchmark_installed_package_path(benchmark_library)

corpus_names <- c("DHS", "MICS", "NSFG")
inventory <- benchmark_corpus_inventory_files(cache_root, corpus_names)
inventory <- do.call(rbind, lapply(corpus_names, function(corpus) {
    items <- inventory[inventory$corpus == corpus, , drop = FALSE]
    items$id <- sprintf("%s-%04d", corpus, seq_len(nrow(items)))
    items$release <- vapply(items$path, corpus_dta_release, integer(1))
    items
}))

# Largest inputs are visited first. Alternating reader order then distributes
# first-reader cache effects across the files that dominate aggregate time.
inventory <- inventory[order(-inventory$bytes, inventory$relative_path, method = "radix"), ]
inventory <- do.call(rbind, lapply(split(inventory, inventory$corpus), function(items) {
    if (is.finite(max_files)) head(items, max_files) else items
}))
rownames(inventory) <- NULL
if (anyDuplicated(inventory$id)) stop("inventory ID collision")
inventory$modified <- sprintf("%.6f", inventory$mtime)
inventory$sha256 <- benchmark_files_sha256(
    inventory$path, progress = TRUE
)

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
raw_path <- file.path(output_dir, "raw.tsv")
inventory_path <- file.path(output_dir, "inventory.tsv")
inventory_hash <- benchmark_publish_or_verify_tsv(
    inventory[c(
        "corpus", "id", "relative_path", "release", "bytes", "modified",
        "sha256"
    )],
    inventory_path,
    "corpus inventory drifted from this resumable run",
    "could not publish private corpus inventory"
)
binding_path <- file.path(output_dir, "run-binding.tsv")
current_binding <- function() {
    cbind(
        data.frame(
            schema_version = 1L,
            inventory_sha256 = inventory_hash,
            package_sha256 = benchmark_directory_sha256(installed_package),
            harness_sha256 = benchmark_harness_sha256(script_dir),
            stringsAsFactors = FALSE
        ),
        benchmark_runtime_binding(stata)
    )
}
binding <- current_binding()
assert_current_binding <- function() {
    if (!identical(current_binding(), binding)) {
        stop(
            paste(
                "benchmark build, harness, runtime, or comparator",
                "changed during the run"
            )
        )
    }
    invisible(NULL)
}
benchmark_publish_or_verify_binding(
    binding,
    binding_path,
    raw_path,
    paste0(
        "resumable results belong to a different inventory, ",
        "package build, benchmark harness, runtime, or comparator"
    ),
    "existing raw results do not have a resumable run binding"
)

measure_r <- function(item, reader, order_index) {
    process <- run_timed_process(
        rscript,
        c("--vanilla", worker_path, reader, item$path),
        environment = c(
            DTAPARSER_BENCH_LIB = benchmark_library,
            R_ENVIRON_USER = "/dev/null",
            R_PROFILE_USER = "/dev/null"
        )
    )
    fields <- parse_fields(process$stdout, "DTAPARSER_BENCH")
    valid <- length(fields) == 4L
    memory <- parse_memory_metrics(process$stderr)
    data.frame(
        corpus = item$corpus,
        id = item$id,
        reader = reader,
        reader_order = order_index,
        status = if (valid) fields[[1L]] else "worker-error",
        elapsed_seconds = if (valid) as.numeric(fields[[2L]]) else NA_real_,
        rows = if (valid) as.numeric(fields[[3L]]) else NA_real_,
        columns = if (valid) as.numeric(fields[[4L]]) else NA_real_,
        rss_bytes = memory$rss_bytes,
        footprint_bytes = memory$footprint_bytes,
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
    process <- run_timed_process(
        stata,
        c("-q", "-b", "do", "stata-worker.do"),
        work_dir = work_dir
    )
    result_path <- file.path(work_dir, "result.tsv")
    fields <- if (file.exists(result_path)) {
        trimws(strsplit(readLines(result_path, n = 1L, warn = FALSE), "\t", fixed = TRUE)[[1L]])
    } else character()
    valid <- length(fields) == 4L
    stata_number <- function(field) {
        if (!nzchar(field) || field %in% c("NA", ".")) NA_real_ else as.numeric(field)
    }
    memory <- parse_memory_metrics(process$stderr)
    result <- data.frame(
        corpus = item$corpus,
        id = item$id,
        reader = "stata",
        reader_order = order_index,
        status = if (valid) fields[[1L]] else "worker-error",
        elapsed_seconds = if (valid) stata_number(fields[[2L]]) else NA_real_,
        rows = if (valid) stata_number(fields[[3L]]) else NA_real_,
        columns = if (valid) stata_number(fields[[4L]]) else NA_real_,
        rss_bytes = memory$rss_bytes,
        footprint_bytes = memory$footprint_bytes,
        stringsAsFactors = FALSE
    )
    unlink(work_dir, recursive = TRUE, force = TRUE)
    result
}

raw_columns <- c(
    "corpus", "id", "reader", "reader_order", "status", "elapsed_seconds",
    "rows", "columns", "rss_bytes", "footprint_bytes"
)
completed <- if (file.exists(raw_path)) {
    existing <- read.delim(raw_path, check.names = FALSE, stringsAsFactors = FALSE)
    if (!identical(names(existing), raw_columns)) stop("existing raw.tsv has an invalid schema")
    keys <- paste(existing$corpus, existing$id, existing$reader, sep = "\037")
    if (anyDuplicated(keys)) stop("raw results contain duplicate reader measurements")
    successful <- existing[
        !is.na(existing$status) & existing$status == "ok",
        , drop = FALSE
    ]
    if (nrow(successful) != nrow(existing)) {
        atomic_tsv(successful, raw_path, quote = TRUE)
    }
    new_key_set(paste(
        successful$corpus, successful$id, successful$reader, sep = "\037"
    ))
} else {
    new_key_set()
}
reader_orders <- list(
    c("dtaparser", "haven", "stata"),
    c("haven", "stata", "dtaparser"),
    c("stata", "dtaparser", "haven")
)
for (index in seq_len(nrow(inventory))) {
    item <- inventory[index, , drop = FALSE]
    readers <- reader_orders[[((index - 1L) %% length(reader_orders)) + 1L]]
    keys <- paste(item$corpus, item$id, readers, sep = "\037")
    pending <- !vapply(
        keys, function(key) key_set_contains(completed, key), logical(1L)
    )
    if (any(pending)) {
        input_dir <- file.path(output_dir, "input-work", item$id)
        unlink(input_dir, recursive = TRUE, force = TRUE)
        dir.create(input_dir, recursive = TRUE, showWarnings = FALSE)
        item$path <- benchmark_snapshot_file(
            item$path, file.path(input_dir, "input.dta"),
            item$bytes, item$sha256
        )
        for (reader_index in seq_along(readers)) {
            if (!pending[[reader_index]]) next
            reader <- readers[[reader_index]]
            measured <- if (identical(reader, "stata")) {
                measure_stata(item, reader_index)
            } else {
                measure_r(item, reader, reader_index)
            }
            append_tsv(measured, raw_path)
            key_set_add(completed, keys[[reader_index]])
        }
        unlink(input_dir, recursive = TRUE, force = TRUE)
    }
    cat(sprintf("%d/%d: %s\n", index, nrow(inventory), item$id))
}

raw <- read.delim(raw_path, check.names = FALSE, stringsAsFactors = FALSE)
paired <- corpus_pair_results(raw, inventory)
summary <- corpus_performance_summary(inventory, paired, corpus_names)
assert_current_binding()
atomic_tsv(summary, file.path(output_dir, "summary.tsv"))
print(summary, row.names = FALSE)
