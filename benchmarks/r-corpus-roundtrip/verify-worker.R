args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L) {
    stop("usage: verify-worker.R INPUT DIRECT_DTA ARROW VIA_ARROW_DTA")
}

script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_dir <- dirname(normalizePath(
    sub("^--file=", "", script_argument), winslash = "/"
))
source(file.path(script_dir, "common.R"), local = TRUE)
benchmark_activate_library("dtatools")

input <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
direct <- args[[2L]]
arrow <- args[[3L]]
via_arrow <- args[[4L]]
stage <- "source-read"
rows <- columns <- NA_integer_

unexpected_warning <- function(condition) {
    stop(
        sprintf("%s warning: %s", stage, conditionMessage(condition)),
        call. = FALSE
    )
}

result <- tryCatch({
    data <- dtatools::read_dta(input)
    rows <- nrow(data)
    columns <- ncol(data)

    stage <- "direct-dta-write"
    withCallingHandlers(
        dtatools::save_dta(data, direct, version = 19L),
        warning = unexpected_warning
    )

    stage <- "arrow-write"
    withCallingHandlers(
        dtatools::save_arrow(data, arrow),
        warning = unexpected_warning
    )

    stage <- "arrow-read"
    arrow_data <- withCallingHandlers(
        dtatools::read_arrow(arrow),
        warning = unexpected_warning
    )

    stage <- "arrow-dta-write"
    withCallingHandlers(
        dtatools::save_dta(arrow_data, via_arrow, version = 19L),
        warning = unexpected_warning
    )
    stage <- "r-pass"
    TRUE
}, error = function(condition) {
    message("verification worker: ", conditionMessage(condition))
    FALSE
})

cat(sprintf(
    "DTATOOLS_VERIFY\t%s\t%s\t%s\n", stage, rows, columns
))
if (!result) quit(status = 1L)
