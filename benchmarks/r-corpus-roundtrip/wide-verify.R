args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("usage: wide-verify.R INPUT_DTA")
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
benchmark_activate_library(c("dtatools", "haven"))
expected <- c(1L, 32768L)
stopifnot(
    identical(dim(dtatools::read_dta(args[[1L]])), expected),
    identical(dim(haven::read_dta(args[[1L]])), expected)
)
