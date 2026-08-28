args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L || !args[[1L]] %in% c("dtaparser", "haven")) {
    stop("usage: Rscript worker.R dtaparser|haven INPUT_DTA")
}

reader <- args[[1L]]
path <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_dir <- dirname(normalizePath(
    sub("^--file=", "", script_argument), winslash = "/"
))
sys.source(
    file.path(script_dir, "..", "benchmark-common.R"),
    envir = environment()
)
benchmark_activate_library(
    reader, verify_dtaparser = identical(reader, "dtaparser")
)

started <- proc.time()[["elapsed"]]
result <- tryCatch(
    if (identical(reader, "dtaparser")) {
        dtaparser::read_dta(path)
    } else {
        haven::read_dta(path)
    },
    error = identity
)
elapsed <- proc.time()[["elapsed"]] - started
if (inherits(result, "error")) {
    cat(sprintf("DTAPARSER_BENCH\terror\t%.9f\tNA\tNA\n", elapsed))
} else {
    cat(sprintf(
        "DTAPARSER_BENCH\tok\t%.9f\t%d\t%d\n",
        elapsed, nrow(result), ncol(result)
    ))
}

# A successful result deliberately remains reachable until process exit so the
# external peak-RSS measurement includes the complete returned data frame.
