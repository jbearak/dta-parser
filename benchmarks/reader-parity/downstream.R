args <- commandArgs(TRUE)
job <- jsonlite::fromJSON(args[[1L]])
.libPaths(c(job$library, .libPaths()))
library(dtatools)
reader <- getExportedValue("dtatools", job$reader)
arguments <- list(file = job$path)
if (job$selection_mode != "all") {
    selected <- job$selection[!grepl("^__absent", job$selection)]
    arguments$col_select <- bquote(tidyselect::all_of(.(selected)))
}
started <- proc.time()
value <- do.call(reader, arguments)
loaded <- proc.time() - started
selected <- head(names(value)[vapply(value, is.numeric, logical(1))], 30L)
stopifnot(length(selected) > 0)
info <- function() {
    symbol <- get0("C_dtatools_owned_numeric_info", asNamespace("dtatools"))
    if (is.null(symbol)) return(NULL)
    as.list(.Call(symbol, value[[selected[[1L]]]]))
}
before <- info()
started <- proc.time()
if (job$workload == "sparse") {
    result <- vapply(selected, function(name) as.double(sum(value[[name]], na.rm = TRUE)), numeric(1))
} else if (job$workload == "traverse") {
    result <- datasig(value)
} else if (job$workload == "first_write") {
    saved <- copy_data(value)
    arguments <- c(list(data = value), setNames(list(0), selected[[1L]]), list(where = 1L))
    invisible(do.call(replace_values, arguments))
    result <- as.double(value[[selected[[1L]]]][1L])
    stopifnot(result == 0)
} else if (job$workload == "r_vector") {
    result <- mean(value[[selected[[1L]]]], na.rm = TRUE)
    result <- as.double(result)
} else stop("Unknown downstream workload")
duration <- proc.time() - started
jsonlite::write_json(list(load_seconds = unname(loaded[["elapsed"]]),
    elapsed_seconds = unname(duration[["elapsed"]]),
    cpu_seconds = unname(duration[["user.self"]] + duration[["sys.self"]]),
    result = result, native_before = before, native_after = info()),
    args[[2L]], auto_unbox = TRUE, digits = 12)
