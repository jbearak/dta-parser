args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3L) {
    stop("usage: Rscript summarize.R RAW_TSV SUMMARY_TSV RUNTIME_PROVENANCE_TSV")
}

script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_path <- normalizePath(sub("^--file=", "", script_argument), winslash = "/")
sys.source(file.path(dirname(script_path), "provenance.R"), envir = environment())

runtime <- read.delim(
    args[[3L]], check.names = FALSE, colClasses = "character"
)
if (nrow(runtime) != 1L ||
    !all(c("iterations", "dataset_100mb_sha256", "dataset_1gb_sha256",
          "dataset_100mb_bytes", "dataset_1gb_bytes", "dataset_100mb_rows",
          "dataset_1gb_rows", "full_columns", "projected_columns",
          "build_provenance_id", "provenance_id",
          "created_at_utc") %in% names(runtime))) {
    stop("runtime provenance is missing required fields")
}
stable_runtime_fields <- setdiff(
    names(runtime), c("provenance_id", "created_at_utc")
)
if (!identical(
    runtime$provenance_id[[1L]],
    benchmark_provenance_id(runtime[stable_runtime_fields])
)) {
    stop("runtime provenance ID does not match its stable fields")
}
iterations <- suppressWarnings(as.integer(runtime$iterations[[1L]]))
if (is.na(iterations) || iterations < 1L ||
    !identical(as.character(iterations), runtime$iterations[[1L]])) {
    stop("runtime provenance iterations must be a positive integer")
}

raw <- read.delim(args[[1L]], check.names = FALSE, colClasses = "character")
keys <- c(
    "dataset", "target_bytes", "actual_bytes", "dataset_sha256", "rows",
    "columns", "workload", "provenance_id", "build_provenance_id"
)
implementations <- c("direct-r", "rust-vectors", "haven")
workloads <- c("full", "projected-eight-columns")
datasets <- c("100mb", "1gb")
required <- c(
    keys, "implementation", "iteration", "elapsed_s", "input_gb_per_s"
)
if (!all(required %in% names(raw))) stop("raw timings are missing required fields")

numeric_fields <- c(
    "target_bytes", "actual_bytes", "rows", "columns", "iteration",
    "elapsed_s", "input_gb_per_s"
)
for (field in numeric_fields) {
    raw[[field]] <- suppressWarnings(as.numeric(raw[[field]]))
}
if (any(!is.finite(raw$elapsed_s) | raw$elapsed_s <= 0) ||
    any(!is.finite(raw$input_gb_per_s) | raw$input_gb_per_s <= 0)) {
    stop("raw timings must be positive and finite")
}
for (field in c("target_bytes", "actual_bytes", "rows", "columns", "iteration")) {
    value <- raw[[field]]
    if (any(!is.finite(value) | value <= 0 | value != floor(value))) {
        stop("raw matrix contains invalid integral field: ", field)
    }
}
if (!setequal(unique(raw$dataset), datasets) ||
    !setequal(unique(raw$workload), workloads) ||
    !setequal(unique(raw$implementation), implementations)) {
    stop("raw matrix contains unexpected datasets, workloads, or implementations")
}
if (any(!grepl("^[0-9a-f]{64}$", raw$dataset_sha256))) {
    stop("raw matrix contains an invalid dataset SHA-256")
}
if (!identical(unique(raw$provenance_id), runtime$provenance_id) ||
    !identical(unique(raw$build_provenance_id), runtime$build_provenance_id)) {
    stop("raw matrix provenance IDs do not match runtime provenance")
}

expected <- expand.grid(
    dataset = datasets,
    workload = workloads,
    implementation = implementations,
    iteration = seq_len(iterations),
    stringsAsFactors = FALSE
)
tuple <- function(data) paste(
    data$dataset, data$workload, data$implementation, data$iteration, sep = "\r"
)
raw_tuple <- tuple(raw)
expected_tuple <- tuple(expected)
if (anyDuplicated(raw_tuple) || length(raw_tuple) != length(expected_tuple) ||
    !setequal(raw_tuple, expected_tuple)) {
    stop("raw timings do not form the exact expected Cartesian matrix")
}

expected_targets <- c(`100mb` = 100000000, `1gb` = 1000000000)
expected_hashes <- c(
    `100mb` = runtime$dataset_100mb_sha256[[1L]],
    `1gb` = runtime$dataset_1gb_sha256[[1L]]
)
expected_sizes <- c(
    `100mb` = as.numeric(runtime$dataset_100mb_bytes[[1L]]),
    `1gb` = as.numeric(runtime$dataset_1gb_bytes[[1L]])
)
expected_rows <- c(
    `100mb` = as.numeric(runtime$dataset_100mb_rows[[1L]]),
    `1gb` = as.numeric(runtime$dataset_1gb_rows[[1L]])
)
expected_columns <- c(
    full = as.numeric(runtime$full_columns[[1L]]),
    `projected-eight-columns` = as.numeric(runtime$projected_columns[[1L]])
)
shape_values <- c(expected_sizes, expected_rows, expected_columns)
if (any(!is.finite(shape_values) | shape_values <= 0 |
        shape_values != floor(shape_values)) ||
    expected_columns[["projected-eight-columns"]] != 8) {
    stop("runtime provenance contains invalid dataset shape metadata")
}
for (dataset in datasets) {
    group <- raw[raw$dataset == dataset, ]
    metadata <- unique(group[c(
        "target_bytes", "actual_bytes", "dataset_sha256", "rows"
    )])
    if (nrow(metadata) != 1L ||
        metadata$target_bytes[[1L]] != expected_targets[[dataset]] ||
        metadata$actual_bytes[[1L]] != expected_sizes[[dataset]] ||
        metadata$rows[[1L]] != expected_rows[[dataset]] ||
        !identical(metadata$dataset_sha256[[1L]], expected_hashes[[dataset]])) {
        stop("raw dataset metadata is inconsistent with runtime provenance: ", dataset)
    }
    for (workload in workloads) {
        columns <- unique(group$columns[group$workload == workload])
        if (length(columns) != 1L ||
            columns != expected_columns[[workload]]) {
            stop("raw column metadata is inconsistent for ", dataset, " ", workload)
        }
    }
}
expected_rate <- raw$actual_bytes / 1e9 / raw$elapsed_s
if (any(abs(raw$input_gb_per_s - expected_rate) > 1.1e-6)) {
    stop("raw input throughput is inconsistent with size and elapsed time")
}

groups <- split(raw, interaction(raw[keys], drop = TRUE, lex.order = TRUE))
stats_for <- function(group, implementation) {
    elapsed <- group$elapsed_s[group$implementation == implementation]
    c(
        iterations = length(elapsed),
        median_s = median(elapsed),
        p05_s = unname(quantile(elapsed, 0.05)),
        p95_s = unname(quantile(elapsed, 0.95)),
        median_gb_s = group$actual_bytes[[1L]] / 1e9 / median(elapsed)
    )
}

rows <- lapply(groups, function(group) {
    statistics <- lapply(implementations, function(implementation) {
        stats_for(group, implementation)
    })
    names(statistics) <- implementations
    counts <- vapply(statistics, `[[`, numeric(1), "iterations")
    stopifnot(length(unique(counts)) == 1L, counts[[1L]] == iterations)

    data.frame(
        group[1L, keys, drop = FALSE],
        iterations = counts[[1L]],
        direct_r_median_s = statistics[["direct-r"]][["median_s"]],
        direct_r_p05_s = statistics[["direct-r"]][["p05_s"]],
        direct_r_p95_s = statistics[["direct-r"]][["p95_s"]],
        direct_r_median_gb_s = statistics[["direct-r"]][["median_gb_s"]],
        rust_vectors_median_s = statistics[["rust-vectors"]][["median_s"]],
        rust_vectors_p05_s = statistics[["rust-vectors"]][["p05_s"]],
        rust_vectors_p95_s = statistics[["rust-vectors"]][["p95_s"]],
        rust_vectors_median_gb_s = statistics[["rust-vectors"]][["median_gb_s"]],
        haven_median_s = statistics[["haven"]][["median_s"]],
        haven_p05_s = statistics[["haven"]][["p05_s"]],
        haven_p95_s = statistics[["haven"]][["p95_s"]],
        haven_median_gb_s = statistics[["haven"]][["median_gb_s"]],
        direct_r_to_rust_vectors_time_ratio =
            statistics[["direct-r"]][["median_s"]] /
            statistics[["rust-vectors"]][["median_s"]],
        direct_r_to_haven_time_ratio = statistics[["direct-r"]][["median_s"]] /
            statistics[["haven"]][["median_s"]],
        rust_vectors_to_haven_time_ratio = statistics[["rust-vectors"]][["median_s"]] /
            statistics[["haven"]][["median_s"]],
        check.names = FALSE
    )
})

summary <- do.call(rbind, rows)
summary <- summary[order(summary$actual_bytes, summary$workload), ]
stopifnot(nrow(summary) == 4L)

dir.create(dirname(args[[2L]]), recursive = TRUE, showWarnings = FALSE)
temporary_output <- tempfile(
    pattern = paste0(basename(args[[2L]]), "."), tmpdir = dirname(args[[2L]])
)
on.exit(unlink(temporary_output), add = TRUE)
write.table(summary, temporary_output, sep = "\t", row.names = FALSE, quote = FALSE)
if (!file.rename(temporary_output, args[[2L]])) {
    stop("could not atomically replace ", args[[2L]])
}
print(summary, row.names = FALSE)
