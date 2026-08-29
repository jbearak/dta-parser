args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L || !args[[1L]] %in% c("dtatools", "haven")) {
    stop("usage: validate-write-output.R dtatools|haven INPUT_DTA OUTPUT_DTA")
}

writer <- args[[1L]]
input <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
output <- normalizePath(args[[3L]], winslash = "/", mustWork = TRUE)
script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_path <- normalizePath(sub("^--file=", "", script_argument), winslash = "/")
script_dir <- dirname(script_path)
sys.source(
    file.path(script_dir, "..", "benchmark-common.R"),
    envir = environment()
)
benchmark_activate_library(c("dtatools", if (writer == "haven") "haven"))

storage_schema <- function(path) {
    data <- dtatools::read_dta(path, n_max = 0)
    levels <- c("byte", "int", "long", "float", "double", "string")
    storage <- vapply(data, function(column) {
        value <- attr(column, "stata.storage", exact = TRUE)
        if (is.null(value)) "string" else value
    }, character(1L))
    counts <- as.integer(table(factor(storage, levels = levels)))
    names(counts) <- levels
    list(
        counts = counts,
        text = paste(paste(levels, counts, sep = "="), collapse = ",")
    )
}

input_storage <- storage_schema(input)
output_storage <- storage_schema(output)
if (writer == "dtatools") {
    before <- dtatools::read_dta(input, use_numeric_altrep = FALSE)
    after <- dtatools::read_dta(output, use_numeric_altrep = FALSE)
    parity_status <- "dtatools-model-identical"
    storage_status <- "declared-numeric-storage-preserved"
    storage_valid <- identical(input_storage$counts, output_storage$counts)
} else {
    before <- haven::read_dta(input)
    after <- haven::read_dta(output)
    parity_status <- "haven-model-identical"
    storage_status <- "numeric-storage-widened-to-double"
    expected_storage <- input_storage$counts
    expected_storage[["double"]] <- sum(expected_storage[1:5])
    expected_storage[1:4] <- 0L
    storage_valid <- identical(expected_storage, output_storage$counts)
}
if (!identical(before, after) || !storage_valid) {
    stop(writer, " full-scale parity or storage validation failed")
}
cat(sprintf(
    "WRITE_VALIDATION\t%s\tok\t%s\t%s\t%s\t%s\t%s\t%s\n",
    writer, nrow(after), ncol(after), parity_status, storage_status,
    input_storage$text, output_storage$text
))
