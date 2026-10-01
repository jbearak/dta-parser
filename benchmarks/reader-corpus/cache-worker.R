# One current read_dta call; base R setup/reporting matches the historical corpus worker.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L, args[[2L]] %in% c("tibble", "dibble"))
path <- normalizePath(args[[1L]], mustWork = TRUE)
output <- args[[2L]]
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]])
source(file.path(dirname(normalizePath(script)), "../reader-refresh/workers/benchmark-common.R"))
benchmark_activate_library("dtatools", verify_dtatools = TRUE)
stopifnot(!"jsonlite" %in% loadedNamespaces())
warnings <- character()
started <- proc.time()
value <- withCallingHandlers(
    tryCatch(dtatools::read_dta(path, output = output, threads = 0L), error = identity),
    warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
    })
duration <- proc.time() - started
if (inherits(value, "error")) {
    cat(sprintf("DTATOOLS_BENCH\terror\t%.9f\tNA\tNA\n", duration[["elapsed"]]))
    message(conditionMessage(value))
} else {
    stopifnot(inherits(value, "tbl_df"), identical(inherits(value, "dibble"), output == "dibble"))
    cat(sprintf("DTATOOLS_BENCH\tok\t%.9f\t%d\t%d\n",
        duration[["elapsed"]], nrow(value), ncol(value)))
}
cat(sprintf("DTATOOLS_CPU\t%.9f\t%.9f\n", duration[["user.self"]], duration[["sys.self"]]))
# Error/warning identities are checked after the read interval without loading jsonlite.
conditions <- list(warnings = warnings,
    error_class = if (inherits(value, "error")) class(value) else character(),
    error_message = if (inherits(value, "error")) conditionMessage(value) else character())
cat("DTATOOLS_CONDITIONS\t", unname(tools::sha256sum(bytes = serialize(conditions, NULL, version = 3L))), "\n", sep = "")
stopifnot(!"jsonlite" %in% loadedNamespaces())
