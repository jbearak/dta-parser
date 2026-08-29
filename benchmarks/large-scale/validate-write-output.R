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

if (writer == "dtatools") {
    before <- dtatools::read_dta(input, use_numeric_altrep = FALSE)
    after <- dtatools::read_dta(output, use_numeric_altrep = FALSE)
} else {
    before <- haven::read_dta(input)
    after <- haven::read_dta(output)
}
if (!identical(before, after)) {
    stop(writer, " full-scale semantic round-trip mismatch")
}
cat(sprintf(
    "WRITE_VALIDATION\t%s\tok\t%s\t%s\n",
    writer, nrow(after), ncol(after)
))
