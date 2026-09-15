args <- commandArgs(TRUE)
job <- jsonlite::fromJSON(args[[1L]])
.libPaths(c(job$library, .libPaths()))
stopifnot(requireNamespace("dtatools"), requireNamespace("tidyselect"))
stopifnot(normalizePath(find.package("dtatools")) ==
          normalizePath(file.path(job$library, "dtatools")))
reader <- getExportedValue("dtatools", job$reader)
read_one <- function() {
    selected <- job$selection
    if (job$selection_mode == "discover") {
        available <- names(reader(job$path, n_max = 0))
        selected <- selected[selected %in% available]
    }
    arguments <- list(file = job$path)
    if (job$selection_mode != "all") {
        selector <- if (job$selection_mode == "any_of") "any_of" else "all_of"
        arguments$col_select <- substitute(tidyselect::SELECTOR(NAMES),
            list(SELECTOR = as.name(selector), NAMES = selected))
    }
    do.call(reader, arguments)
}
if (job$mode == "qualify") {
    value <- read_one()
    jsonlite::write_json(list(signature = dtatools::datasig(value),
        rows = nrow(value), columns = ncol(value)), args[[2L]], auto_unbox = TRUE)
    quit(status = 0)
}
if (job$mode == "warm") {
    invisible(read_one())
    gc(full = TRUE)
}
started <- proc.time()
for (i in seq_len(job$calls)) value <- read_one()
duration <- proc.time() - started
stopifnot(nrow(value) == job$rows, ncol(value) == job$columns)
jsonlite::write_json(list(elapsed_seconds = unname(duration[["elapsed"]]) / job$calls,
    cpu_seconds = unname(duration[["user.self"]] + duration[["sys.self"]]) / job$calls,
    rows = nrow(value), columns = ncol(value)), args[[2L]], auto_unbox = TRUE, digits = 12)
