args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("usage: wide-generate.R OUTPUT_DTA")
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
benchmark_activate_library("dtaparser")
data <- setNames(
    as.data.frame(rep(list(1L), 32768L), optional = TRUE),
    paste0("x", seq_len(32768L))
)
dtaparser::write_dta(data, args[[1L]], version = 19L)
