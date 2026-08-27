args <- commandArgs(trailingOnly = TRUE)
valid_mode <- length(args) == 4L && (
    identical(args[1:2], c("dtaparser", "stata-storage")) ||
    (args[[1L]] %in% c("dtaparser", "haven") &&
     identical(args[[2L]], "standard-r"))
)
if (!valid_mode) {
    stop(paste(
        "usage: write-worker.R dtaparser stata-storage INPUT_DTA OUTPUT_DTA;",
        "or write-worker.R dtaparser|haven standard-r ROWS OUTPUT_DTA"
    ))
}

writer <- args[[1L]]
workload <- args[[2L]]
input_argument <- args[[3L]]
output <- normalizePath(args[[4L]], winslash = "/", mustWork = FALSE)
script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_path <- normalizePath(sub("^--file=", "", script_argument), winslash = "/")
script_dir <- dirname(script_path)
benchmark_library <- Sys.getenv("DTAPARSER_BENCH_LIB")
if (!nzchar(benchmark_library)) stop("DTAPARSER_BENCH_LIB is required")
.libPaths(c(normalizePath(benchmark_library, winslash = "/", mustWork = TRUE),
            .libPaths()))
if (!requireNamespace("dtaparser", quietly = TRUE)) stop("dtaparser is required")
if (writer == "haven" && !requireNamespace("haven", quietly = TRUE)) {
    stop("haven is required for Haven writes")
}

data <- if (workload == "standard-r") {
    rows <- suppressWarnings(as.integer(input_argument))
    if (length(rows) != 1L || is.na(rows) || rows < 1L ||
        as.character(rows) != input_argument) {
        stop("standard-R row count must be a positive integer")
    }
    sys.source(file.path(script_dir, "standard-r-write-fixture.R"),
               envir = environment())
    make_standard_r_write_fixture(rows)
} else if (writer == "dtaparser") {
    input <- normalizePath(input_argument, winslash = "/", mustWork = TRUE)
    dtaparser::read_dta(input)
} else {
    input <- normalizePath(input_argument, winslash = "/", mustWork = TRUE)
    haven::read_dta(input)
}
if (workload == "stata-storage" && writer == "dtaparser") {
    storage <- vapply(data, function(column) {
        value <- attr(column, "stata.storage", exact = TRUE)
        if (is.null(value)) "string" else value
    }, character(1L))
    expected_storage <- c(
        byte = 4L, int = 4L, long = 9L, float = 4L, double = 9L,
        string = 10L
    )
    observed <- table(factor(storage, levels = names(expected_storage)))
    if (!identical(as.integer(observed), unname(expected_storage))) {
        stop("primary write fixture does not contain the expected Stata storage types")
    }
}
rows <- nrow(data)
columns <- ncol(data)
input_object_bytes <- if (workload == "standard-r") {
    as.numeric(object.size(data))
} else NA_real_
schema <- if (workload == "standard-r") standard_r_write_schema(data) else ""
invisible(gc())
options(warn = 2)
started <- proc.time()[["elapsed"]]
status <- tryCatch({
    if (writer == "dtaparser") {
        dtaparser::write_dta(data, output, version = 19L)
    } else {
        haven::write_dta(data, output, version = 15L)
    }
    "ok"
}, error = function(condition) {
    message(writer, " write worker: ", conditionMessage(condition))
    "error"
})
elapsed <- proc.time()[["elapsed"]] - started
bytes <- if (file.exists(output)) {
    file.info(output, extra_cols = FALSE)$size[[1L]]
} else NA_real_
if (workload == "standard-r") {
    cat(sprintf(
        "STANDARD_R_WRITE\t%s\t%s\t%.9f\t%s\t%s\t%s\t%s\t%s\n",
        writer, status, elapsed, rows, columns, input_object_bytes, bytes,
        schema
    ))
} else {
    cat(sprintf(
        "SYNTHETIC_WRITE\t%s\t%s\t%.9f\t%s\t%s\t%s\n",
        writer, status, elapsed, rows, columns, bytes
    ))
}
if (status != "ok") quit(status = 1L)
