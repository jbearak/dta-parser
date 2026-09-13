# Qualification and a separate single-read Arrow RSS observation.
args <- commandArgs(trailingOnly = TRUE)
.libPaths(c(Sys.getenv("DTATOOLS_BENCH_LIB"), .libPaths()))
library(dtatools)
if (identical(args[[1L]], "memory")) {
    start <- proc.time()
    value <- read_arrow(args[[2L]])
    duration <- proc.time() - start
    elapsed <- duration[["elapsed"]]
    cat(sprintf("DTATOOLS_BENCH\tok\t%.9f\t%d\t%d\n",
                elapsed, nrow(value), ncol(value)))
    cat(sprintf("DTATOOLS_CPU\t%.9f\t%.9f\n",
                duration[["user.self"]], duration[["sys.self"]]))
} else {
    dta <- read_dta(args[[1L]])
    arrow <- read_arrow(args[[2L]])
    stopifnot(is_dibble(dta), is_dibble(arrow),
              identical(dim(dta), dim(arrow)), identical(names(dta), names(arrow)))
    # The retained August Arrow files predate preservation of value-label names
    # declared fixed-string widths and variable notes. Compare current values and other
    # metadata without requiring those old files to acquire newer metadata.
    missing_notes <- vapply(seq_along(dta), function(i) {
        !is.null(attr(dta[[i]], "notes", exact = TRUE)) &&
            is.null(attr(arrow[[i]], "notes", exact = TRUE))
    }, logical(1))
    cat("Columns with notes absent from retained Arrow file:", sum(missing_notes), "\n")
    normalize <- function(x) {
        x <- dtatools:::.reference_snapshot(x)
        for (i in seq_along(x)) {
            attr(x[[i]], "value.label.name") <- NULL
            attr(x[[i]], "stata.string.storage") <- NULL
            if (missing_notes[[i]]) attr(x[[i]], "notes") <- NULL
        }
        x
    }
    stopifnot(identical(datasig(normalize(dta)), datasig(normalize(arrow))))
    cat("Equal dimensions, names and normalized data signatures:",
        nrow(dta), ncol(dta), "\n")
}
