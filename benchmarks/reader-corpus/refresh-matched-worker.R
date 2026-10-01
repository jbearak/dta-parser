# Historical worker.R timer and base-R reporting, with an explicit container.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L, args[[1L]] %in% c("read_dta", "read_arrow"),
          args[[3L]] %in% c("tibble", "dibble"))
method <- args[[1L]]
path <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
output <- args[[3L]]
script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument)))
sys.source(file.path(script_dir, "../reader-refresh/workers/benchmark-common.R"),
           envir = environment())
benchmark_activate_library("dtatools", verify_dtatools = TRUE)
stopifnot(!"jsonlite" %in% loadedNamespaces())
options(warn = 2L)
started <- proc.time()
value <- tryCatch(
    if (method == "read_arrow") dtatools::read_arrow(path, verify = TRUE, output = output)
    else dtatools::read_dta(path, output = output),
    error = identity
)
duration <- proc.time() - started
if (inherits(value, "error")) {
    cat(sprintf("DTATOOLS_BENCH\terror\t%.9f\tNA\tNA\n", duration[["elapsed"]]))
    message(conditionMessage(value))
} else {
    stopifnot(inherits(value, "tbl_df"),
              identical(inherits(value, "dibble"), output == "dibble"))
    cat(sprintf("DTATOOLS_BENCH\tok\t%.9f\t%d\t%d\n",
                duration[["elapsed"]], nrow(value), ncol(value)))
}
cat(sprintf("DTATOOLS_CPU\t%.9f\t%.9f\n",
            duration[["user.self"]], duration[["sys.self"]]))
stopifnot(!"jsonlite" %in% loadedNamespaces())
# Keep the returned object alive through process exit.
