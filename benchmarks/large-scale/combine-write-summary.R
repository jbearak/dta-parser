args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 7L) {
    stop(paste(
        "usage: combine-write-summary.R CURRENT_RAW CURRENT_SUMMARY CURRENT_PROVENANCE",
        "REFERENCE_RAW REFERENCE_SUMMARY REFERENCE_PROVENANCE OUTPUT"
    ))
}

read_table <- function(path) {
    read.delim(
        normalizePath(path, winslash = "/", mustWork = TRUE),
        check.names = FALSE, stringsAsFactors = FALSE
    )
}
current_raw <- read_table(args[[1L]])
current_summary <- read_table(args[[2L]])
current_provenance <- read_table(args[[3L]])
reference_raw <- read_table(args[[4L]])
reference_summary <- read_table(args[[5L]])
reference_provenance <- read_table(args[[6L]])
output <- normalizePath(args[[7L]], winslash = "/", mustWork = FALSE)

contract_fields <- c("workload", "fixture_storage_schema", "dirty_mutation")
if (nrow(current_provenance) != 1L || nrow(reference_provenance) != 1L ||
    !all(contract_fields %in% names(current_provenance)) ||
    !all(contract_fields %in% names(reference_provenance)) ||
    !identical(current_provenance[contract_fields],
               reference_provenance[contract_fields])) {
    stop("current and reference writes do not share the primary workload contract")
}

if (!identical(unique(current_raw$writer), "dtaparser") ||
    !identical(unique(current_summary$writer), "dtaparser")) {
    stop("current write results must contain only dtaparser")
}
fixed_writers <- "stata"
fixed_raw <- reference_raw[reference_raw$writer %in% fixed_writers, , drop = FALSE]
fixed_summary <- reference_summary[
    reference_summary$writer %in% fixed_writers, , drop = FALSE
]
if (!setequal(unique(fixed_raw$writer), fixed_writers) ||
    !setequal(unique(fixed_summary$writer), fixed_writers)) {
    stop("reference write results must contain Stata")
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

current_summary$measurement <- "current-dtaparser"
fixed_summary$measurement <- "fixed-reference"
combined <- rbind(current_summary, fixed_summary)
writer_order <- c("dtaparser", "stata")
dataset_order <- c("100mb", "1gb")
combined <- combined[
    order(match(combined$dataset, dataset_order),
          match(combined$writer, writer_order)),
]
write.table(combined, output, sep = "\t", row.names = FALSE, quote = FALSE)
print(combined, row.names = FALSE)
