args <- commandArgs(TRUE)
job <- jsonlite::fromJSON(args[[1L]])
.libPaths(c(job$library, .libPaths()))
if (job$method == "haven") {
    stopifnot(requireNamespace("haven", quietly = TRUE))
    stopifnot(normalizePath(find.package("haven")) == normalizePath(job$haven_path))
    reader <- haven::read_dta
} else {
    stopifnot(requireNamespace("dtatools", quietly = TRUE))
    stopifnot(normalizePath(find.package("dtatools")) ==
              normalizePath(file.path(job$library, "dtatools")))
    reader <- getExportedValue("dtatools", job$method)
}
started <- proc.time()
value <- reader(job$path)
duration <- proc.time() - started
stopifnot(nrow(value) == job$rows, ncol(value) == job$columns)
jsonlite::write_json(list(
    elapsed_seconds = unname(duration[["elapsed"]]),
    read_cpu_seconds = unname(duration[["user.self"]] + duration[["sys.self"]]),
    rows = nrow(value), columns = ncol(value)
), args[[2L]], auto_unbox = TRUE, digits = 12)
