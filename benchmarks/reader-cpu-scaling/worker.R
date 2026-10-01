# Exactly one full read in a fresh R process. Do not load reporting packages.
args <- commandArgs(TRUE)
stopifnot(length(args) == 5L, args[[1L]] %in% c("dta", "arrow", "empty", "qualify-dta", "qualify-arrow"))
qualification <- startsWith(args[[1L]], "qualify-")
method <- sub("^qualify-", "", args[[1L]])
threads <- as.integer(args[[3L]])
stopifnot(!is.na(threads), threads >= 0L)
library_path <- normalizePath(Sys.getenv("DTATOOLS_BENCH_LIB"), mustWork = TRUE)
.libPaths(c(library_path, .libPaths()))
stopifnot(requireNamespace("dtatools", quietly = TRUE),
    identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
              normalizePath(file.path(library_path, "dtatools"))),
    !"jsonlite" %in% loadedNamespaces())
cat("RUNTIME\t", R.version.string, "\t", R.version$platform, "\t",
    as.character(packageVersion("dtatools")), "\n", sep = "")
if (method == "empty") {
    for (index in seq_len(100L)) {
        started <- proc.time()
        duration <- proc.time() - started
        cat(sprintf("EMPTY\t%d\t%.9f\t%.9f\t%.9f\n", index,
            duration[["elapsed"]], duration[["user.self"]], duration[["sys.self"]]))
    }
} else {
    path <- normalizePath(args[[2L]], mustWork = TRUE)
    reader <- if (method == "dta") dtatools::read_dta else dtatools::read_arrow
    if (qualification) {
        value <- withCallingHandlers(
            if (method == "arrow") reader(path, threads = threads, verify = TRUE) else
                reader(path, threads = threads),
            warning = function(w) stop("Unexpected thread-qualification warning: ", conditionMessage(w)))
        stopifnot(nrow(value) == as.integer(args[[4L]]), ncol(value) == as.integer(args[[5L]]))
        cat(sprintf("QUALIFIED\t%d\t%d\t%d\t%s\n", threads, nrow(value), ncol(value),
            dtatools::datasig(value)))
        quit(status = 0L)
    }
    started <- proc.time()
    value <- if (method == "arrow") reader(path, threads = threads, verify = TRUE) else
        reader(path, threads = threads)
    duration <- proc.time() - started
    stopifnot(nrow(value) == as.integer(args[[4L]]), ncol(value) == as.integer(args[[5L]]))
    cat(sprintf("READ\t%.9f\t%.9f\t%.9f\t%d\t%d\n",
        duration[["elapsed"]], duration[["user.self"]], duration[["sys.self"]],
        nrow(value), ncol(value)))
}
stopifnot(!"jsonlite" %in% loadedNamespaces())
