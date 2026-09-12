# Supplemental reader coverage. No comparator or writer is invoked.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
job <- jsonlite::fromJSON(args[[1L]], simplifyVector = TRUE)
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]))
source(file.path(dirname(script), "benchmark-common.R"))
benchmark_activate_library(c("dtatools", "tidyselect"))
selected <- if (is.null(job$selection)) NULL else as.character(job$selection)
if (isTRUE(job$select_first_two)) {
    selected <- head(names(dtatools::read_dta(job$path, n_max = 0)), 2L)
}
read_one <- function() {
    arguments <- list(file = job$path)
    if (!is.null(job$threads)) arguments$threads <- as.integer(job$threads)
    if (!is.null(selected)) arguments$col_select <- bquote(tidyselect::all_of(.(selected)))
    if (identical(job$format, "arrow")) {
        arguments$verify <- !identical(job$verify, FALSE)
        do.call(dtatools::read_arrow, arguments)
    } else {
        if (!is.null(job$skip)) arguments$skip <- job$skip
        if (!is.null(job$n_max)) arguments$n_max <- job$n_max
        do.call(dtatools::read_dta, arguments)
    }
}
validate <- function(value) {
    if (!is.null(job$rows)) stopifnot(nrow(value) == job$rows)
    if (!is.null(job$columns)) stopifnot(ncol(value) == job$columns)
    if (!is.null(selected)) stopifnot(identical(names(value), selected))
}
if (identical(job$mode, "qualify")) {
    value <- read_one()
    validate(value)
    jsonlite::write_json(list(signature = dtatools::datasig(value),
        rows = nrow(value), columns = ncol(value), names = names(value)),
        args[[2L]], auto_unbox = TRUE, pretty = TRUE)
    quit(status = 0L)
}
if (identical(job$mode, "warm")) {
    invisible(read_one())
    gc(full = TRUE)
}
rows <- list()
for (iteration in seq_len(job$iterations)) {
    if (!identical(job$mode, "fresh")) gc()
    started <- proc.time()
    if (identical(job$mode, "micro")) {
        for (i in seq_len(job$batch)) value <- read_one()
    } else value <- read_one()
    duration <- proc.time() - started
    validate(value)
    count <- if (identical(job$mode, "micro")) job$batch else 1L
    rows[[iteration]] <- data.frame(iteration = iteration, calls = count,
        elapsed_seconds = duration[["elapsed"]] / count,
        user_cpu_seconds = duration[["user.self"]] / count,
        system_cpu_seconds = duration[["sys.self"]] / count,
        cpu_seconds = (duration[["user.self"]] + duration[["sys.self"]]) / count,
        rows = nrow(value), columns = ncol(value))
    # Fresh results remain live through process exit. Repeated cases retain the
    # previous result through the next read, matching the projected-read worker.
}
write.csv(do.call(rbind, rows), args[[2L]], row.names = FALSE)
