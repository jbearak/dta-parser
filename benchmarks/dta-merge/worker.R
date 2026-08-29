# One dta_merge benchmark operation per invocation. Merge timings run warm in
# one process: one untimed warm merge, then timed iterations with a full
# garbage collection between them. The timer covers only the dta_merge()
# call, so path inputs pay their file read inside the timed region and
# in-memory inputs are loaded before it.
library_path <- Sys.getenv("DTATOOLS_BENCH_LIB")
if (nzchar(library_path)) .libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages(library(dtatools))

arguments <- commandArgs(trailingOnly = TRUE)
task <- arguments[[1L]]

emit <- function(...) cat(paste(..., sep = "\t"), "\n", sep = "")

plain_frame <- function(data) {
    tibble::as_tibble(lapply(data, function(value) {
        if (is.numeric(value)) as.double(value) else as.vector(value)
    }))
}

load_input <- function(path) {
    if (identical(tolower(tools::file_ext(path)), "arrow")) {
        read_arrow(path)
    } else {
        read_dta(path)
    }
}

if (task == "prepare") {
    master_dta <- arguments[[2L]]
    master_arrow <- arguments[[3L]]
    using_dta <- arguments[[4L]]
    using_arrow <- arguments[[5L]]
    master <- read_dta(master_dta)
    save_arrow(master, master_arrow)
    rows <- nrow(master)
    matched <- rows %/% 2L
    extra <- rows %/% 25L
    set.seed(20260829L)
    using <- tibble::tibble(
        id = c(seq_len(matched), rows + seq_len(extra)),
        using_score = runif(matched + extra),
        using_group = sample(letters, matched + extra, replace = TRUE)
    )
    save_dta(using, using_dta)
    save_arrow(using, using_arrow)
    emit("prepared", rows, matched + extra)
} else if (task == "merge") {
    x_kind <- arguments[[2L]]
    x_path <- arguments[[3L]]
    y_kind <- arguments[[4L]]
    y_path <- arguments[[5L]]
    iterations <- as.integer(arguments[[6L]])
    x <- if (identical(x_kind, "mem")) load_input(x_path) else x_path
    y <- if (identical(y_kind, "mem")) load_input(y_path) else y_path
    gc(full = TRUE)
    invisible(dta_merge(x, y, by = "id", relationship = "1:1"))
    gc(full = TRUE)
    for (iteration in seq_len(iterations)) {
        started <- proc.time()[["elapsed"]]
        result <- dta_merge(x, y, by = "id", relationship = "1:1")
        elapsed <- proc.time()[["elapsed"]] - started
        emit("iteration", iteration, sprintf("%.6f", elapsed), nrow(result))
        rm(result)
        gc(full = TRUE)
    }
} else if (task == "competitor") {
    engine <- arguments[[2L]]
    x_path <- arguments[[3L]]
    y_path <- arguments[[4L]]
    iterations <- as.integer(arguments[[5L]])
    # Competitors cannot represent Stata missing identity, so they receive
    # plain doubles and characters; the fixture keys hold no missings.
    x <- plain_frame(load_input(x_path))
    y <- plain_frame(load_input(y_path))
    merge_call <- switch(engine,
        base = function() merge(x, y, by = "id", all = TRUE, sort = FALSE),
        dplyr = function() dplyr::full_join(x, y, by = "id"),
        stop("unknown engine")
    )
    gc(full = TRUE)
    invisible(merge_call())
    gc(full = TRUE)
    for (iteration in seq_len(iterations)) {
        started <- proc.time()[["elapsed"]]
        result <- merge_call()
        elapsed <- proc.time()[["elapsed"]] - started
        emit("iteration", iteration, sprintf("%.6f", elapsed), nrow(result))
        rm(result)
        gc(full = TRUE)
    }
} else {
    stop("unknown task")
}
