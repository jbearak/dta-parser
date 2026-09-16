# One fresh-process full read; result stays live until process exit.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L, args[[1L]] %in% c("read_dta", "read_arrow"))
method <- args[[1L]]
path <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument)))
# Match the earlier corpus worker's setup without loading reporting packages.
sys.source(
    file.path(script_dir, "../reader-refresh/workers/benchmark-common.R"),
    envir = environment()
)
benchmark_activate_library("dtatools", verify_dtatools = TRUE)
stopifnot(!"jsonlite" %in% loadedNamespaces())
started <- proc.time()
value <- tryCatch(
    if (method == "read_arrow") dtatools::read_arrow(path, verify = TRUE)
    else dtatools::read_dta(path),
    error = identity
)
duration <- proc.time() - started
if (inherits(value, "error")) {
    cat(sprintf("DTATOOLS_BENCH\terror\t%.9f\tNA\tNA\n", duration[["elapsed"]]))
    message(conditionMessage(value))
} else {
    cat(sprintf("DTATOOLS_BENCH\tok\t%.9f\t%d\t%d\n",
                duration[["elapsed"]], nrow(value), ncol(value)))
}
cat(sprintf("DTATOOLS_CPU\t%.9f\t%.9f\n",
            duration[["user.self"]], duration[["sys.self"]]))
stopifnot(!"jsonlite" %in% loadedNamespaces())
