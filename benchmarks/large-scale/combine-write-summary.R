args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 9L) {
    stop(paste(
        "usage: combine-write-summary.R CURRENT_RAW CURRENT_SUMMARY",
        "CURRENT_PROVENANCE CURRENT_VALIDATION REFERENCE_RAW",
        "REFERENCE_SUMMARY REFERENCE_PROVENANCE REFERENCE_VALIDATION OUTPUT"
    ))
}

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
sys.source(file.path(script_dir, "provenance.R"), envir = environment())
sys.source(file.path(script_dir, "write-run-common.R"), envir = environment())

read_table <- function(path) {
    read.delim(
        normalizePath(path, winslash = "/", mustWork = TRUE),
        check.names = FALSE, stringsAsFactors = FALSE
    )
}
read_provenance <- function(path) {
    read.delim(
        normalizePath(path, winslash = "/", mustWork = TRUE),
        check.names = FALSE, stringsAsFactors = FALSE,
        colClasses = "character", na.strings = character()
    )
}
current_raw <- read_table(args[[1L]])
current_summary <- read_table(args[[2L]])
current_provenance <- read_provenance(args[[3L]])
current_validation <- read_table(args[[4L]])
reference_raw <- read_table(args[[5L]])
reference_summary <- read_table(args[[6L]])
reference_provenance <- read_provenance(args[[7L]])
reference_validation <- read_table(args[[8L]])
output <- normalizePath(args[[9L]], winslash = "/", mustWork = FALSE)

validate_provenance <- function(provenance, description) {
    required <- c("provenance_id", "created_at_utc", "build_provenance_id")
    if (nrow(provenance) != 1L || anyDuplicated(names(provenance)) ||
        !all(required %in% names(provenance))) {
        stop(description, " provenance is not a single complete record")
    }
    benchmark_assert_provenance_fields(provenance)
    stable_fields <- setdiff(
        names(provenance), c("provenance_id", "created_at_utc")
    )
    expected_id <- benchmark_provenance_id(provenance[stable_fields])
    if (!identical(as.character(provenance$provenance_id[[1L]]), expected_id)) {
        stop(description, " provenance ID does not match its stable fields")
    }
    if (!grepl(
        "^[0-9a-f]{64}$", as.character(provenance$build_provenance_id[[1L]])
    )) {
        stop(description, " build provenance ID is invalid")
    }
}
validate_provenance(current_provenance, "current write")
validate_provenance(reference_provenance, "reference write")

contract_fields <- c(
    "workload", "fixture_storage_schema", "fixture_creator",
    "fixture_generator_sha256", "stata_save_state", "r_writer_input",
    "full_scale_validation"
)
if (nrow(current_provenance) != 1L || nrow(reference_provenance) != 1L ||
    !all(contract_fields %in% names(current_provenance)) ||
    !all(contract_fields %in% names(reference_provenance)) ||
    !identical(current_provenance[contract_fields],
               reference_provenance[contract_fields])) {
    stop("current and reference writes do not share the primary workload contract")
}

datasets <- c("100mb", "1gb")
parse_iterations <- function(provenance, description) {
    text <- as.character(provenance$iterations)
    value <- suppressWarnings(as.integer(text))
    if (length(text) != 1L || is.na(value) || value < 1L ||
        !identical(as.character(value), text)) {
        stop(description, " provenance has invalid iterations")
    }
    value
}
summary_key <- function(data) paste(data$dataset, data$writer, sep = "\r")
validate_summary_matrix <- function(data, writers, iterations, description) {
    required <- c(
        "dataset", "writer", "iterations", "input_bytes",
        "median_seconds", "p05_seconds", "p95_seconds",
        "median_peak_rss_bytes", "median_output_bytes",
        "provenance_id", "build_provenance_id"
    )
    expected <- expand.grid(
        dataset = datasets, writer = writers, stringsAsFactors = FALSE
    )
    if (!all(required %in% names(data)) || anyDuplicated(summary_key(data)) ||
        !setequal(summary_key(data), summary_key(expected)) ||
        any(data$iterations != iterations)) {
        stop(description, " summary is not the exact expected matrix")
    }
}
validate_binding <- function(data, provenance, description) {
    required <- c("provenance_id", "build_provenance_id")
    if (!all(required %in% names(data)) ||
        !identical(unique(data$provenance_id), provenance$provenance_id) ||
        !identical(
            unique(data$build_provenance_id),
            provenance$build_provenance_id
        )) {
        stop(description, " is not bound to its provenance")
    }
}
validate_validation_matrix <- function(
    data, raw, writers, provenance, description
) {
    required <- c(
        "dataset", "dataset_sha256", "writer", "rows", "columns",
        "output_bytes", "parity_status", "storage_status",
        "input_storage_class_counts", "output_storage_class_counts",
        "provenance_id", "build_provenance_id"
    )
    expected <- expand.grid(
        dataset = datasets, writer = writers, stringsAsFactors = FALSE
    )
    if (!all(required %in% names(data)) ||
        anyDuplicated(summary_key(data)) ||
        !setequal(summary_key(data), summary_key(expected))) {
        stop(description, " validation is not the exact expected matrix")
    }
    validate_binding(data, provenance, paste(description, "validation"))
    fixture_schema <- provenance$fixture_storage_schema[[1L]]
    widened_schema <- "byte=0,int=0,long=0,float=0,double=30,string=10"
    for (index in seq_len(nrow(data))) {
        row <- data[index, , drop = FALSE]
        matching <- raw[
            raw$dataset == row$dataset & raw$writer == row$writer,
            , drop = FALSE
        ]
        if (!nrow(matching) ||
            !identical(unique(matching$dataset_sha256), row$dataset_sha256) ||
            !identical(unique(matching$rows), row$rows) ||
            !identical(unique(matching$columns), row$columns) ||
            !identical(unique(matching$output_bytes), row$output_bytes) ||
            row$input_storage_class_counts != fixture_schema) {
            stop(description, " validation does not match its timed rows")
        }
        if (row$writer == "dtatools") {
            valid <- row$parity_status == "dtatools-model-identical" &&
                row$storage_status == "declared-numeric-storage-preserved" &&
                row$output_storage_class_counts == fixture_schema
        } else {
            valid <- row$parity_status == "haven-model-identical" &&
                row$storage_status == "numeric-storage-widened-to-double" &&
                row$output_storage_class_counts == widened_schema
        }
        if (!valid) stop(description, " validation status is invalid")
    }
}
validate_bundle <- function(
    raw, summary, validation, provenance, writers, validation_writers,
    description
) {
    iterations <- parse_iterations(provenance, description)
    if (!identical(provenance$writers, paste(writers, collapse = ","))) {
        stop(description, " provenance has unexpected writers")
    }
    validate_write_result_matrix(raw, datasets, writers, iterations, description)
    validate_summary_matrix(summary, writers, iterations, description)
    expected_summary <- summarize_write_results(
        raw, datasets, writers, "input_bytes"
    )
    rownames(summary) <- NULL
    rownames(expected_summary) <- NULL
    time_fields <- c("median_seconds", "p05_seconds", "p95_seconds")
    exact_fields <- setdiff(names(expected_summary), time_fields)
    times_match <- all(vapply(time_fields, function(field) {
        all(abs(summary[[field]] - expected_summary[[field]]) <= 1e-12)
    }, logical(1L)))
    if (!identical(summary[exact_fields], expected_summary[exact_fields]) ||
        !times_match) {
        stop(description, " summary does not match its raw results")
    }
    validate_binding(raw, provenance, paste(description, "raw results"))
    validate_binding(summary, provenance, paste(description, "summary"))
    validate_validation_matrix(
        validation, raw, validation_writers, provenance, description
    )
}
validate_bundle(
    current_raw, current_summary, current_validation, current_provenance,
    "dtatools", "dtatools", "current write"
)
reference_writers <- c("dtatools", "haven", "stata")
validate_bundle(
    reference_raw, reference_summary, reference_validation,
    reference_provenance, reference_writers, c("dtatools", "haven"),
    "reference write"
)

fixed_writers <- c("haven", "stata")
fixed_raw <- reference_raw[reference_raw$writer %in% fixed_writers, , drop = FALSE]
fixed_summary <- reference_summary[
    reference_summary$writer %in% fixed_writers, , drop = FALSE
]
if (!setequal(unique(fixed_raw$writer), fixed_writers) ||
    !setequal(unique(fixed_summary$writer), fixed_writers)) {
    stop("reference write results must contain Haven and Stata")
}

dataset_key <- function(data) paste(data$dataset, data$dataset_sha256, sep = "\r")
if (!setequal(unique(dataset_key(current_raw)), unique(dataset_key(fixed_raw)))) {
    stop("current and reference writes use different synthetic datasets")
}
current_shape <- unique(current_raw[c("dataset", "input_bytes", "rows", "columns")])
reference_shape <- unique(fixed_raw[c("dataset", "input_bytes", "rows", "columns")])
current_shape <- current_shape[order(current_shape$dataset), , drop = FALSE]
reference_shape <- reference_shape[order(reference_shape$dataset), , drop = FALSE]
rownames(current_shape) <- rownames(reference_shape) <- NULL
if (!identical(current_shape, reference_shape)) {
    stop("current and reference write inputs have different shapes")
}

current_summary$measurement <- "current-dtatools"
fixed_summary$measurement <- "fixed-reference"
combined <- rbind(current_summary, fixed_summary)
writer_order <- c("dtatools", "haven", "stata")
dataset_order <- c("100mb", "1gb")
combined <- combined[
    order(match(combined$dataset, dataset_order),
          match(combined$writer, writer_order)),
]
atomic_tsv(combined, output)
print(combined, row.names = FALSE)
