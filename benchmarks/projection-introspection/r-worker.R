args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) {
    stop("usage: r-worker.R INPUT PRESENT_NAMES UNION_NAMES REPETITIONS OUTPUT")
}

input <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
present <- scan(args[[2L]], what = character(), quiet = TRUE)
union <- scan(args[[3L]], what = character(), quiet = TRUE)
repetitions <- as.integer(args[[4L]])
output <- args[[5L]]
if (!length(present) || length(union) < length(present) ||
    anyDuplicated(present) || !all(present %in% union) ||
    is.na(repetitions) || repetitions < 1L) {
    stop("invalid projection benchmark arguments")
}

script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument), winslash = "/"))
sys.source(file.path(script_dir, "..", "benchmark-common.R"), envir = environment())
benchmark_activate_library(c("dtatools", "tidyselect"))

read_any <- function() dtatools::read_dta(
    input, col_select = tidyselect::any_of(union)
)
read_all <- function() dtatools::read_dta(
    input, col_select = tidyselect::all_of(present)
)
validate <- function(value) {
    if (!identical(names(value), present) || ncol(value) != length(present)) {
        stop("projected result differs from the requested present columns")
    }
    invisible(value)
}

validate(read_any())
validate(read_all())
rows <- vector("list", repetitions * 2L)
row_index <- 0L
for (iteration in seq_len(repetitions)) {
    gc()
    started <- proc.time()[["elapsed"]]
    value <- read_any()
    elapsed <- proc.time()[["elapsed"]] - started
    validate(value)
    row_index <- row_index + 1L
    rows[[row_index]] <- data.frame(
        method = "dtatools-any-of", iteration = iteration,
        elapsed_seconds = elapsed, rows = nrow(value), columns = ncol(value)
    )

    gc()
    started <- proc.time()[["elapsed"]]
    value <- read_all()
    elapsed <- proc.time()[["elapsed"]] - started
    validate(value)
    row_index <- row_index + 1L
    rows[[row_index]] <- data.frame(
        method = "dtatools-all-of", iteration = iteration,
        elapsed_seconds = elapsed, rows = nrow(value), columns = ncol(value)
    )
}
write.table(
    do.call(rbind, rows), output, sep = "\t", quote = FALSE,
    row.names = FALSE, col.names = FALSE
)
