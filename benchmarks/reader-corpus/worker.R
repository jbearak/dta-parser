# One fresh-process full read; result stays live until process exit.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
job <- jsonlite::fromJSON(args[[1L]])
.libPaths(c(job$library, .libPaths()))
stopifnot(requireNamespace("dtatools", quietly = TRUE))
stopifnot(normalizePath(find.package("dtatools")) ==
          normalizePath(file.path(job$library, "dtatools")))
stopifnot(job$method %in% c("read_dta", "read_arrow"))
reader <- getExportedValue("dtatools", job$method)
started <- proc.time()
value <- tryCatch(
    if (job$method == "read_arrow") reader(job$path, verify = TRUE) else reader(job$path),
    error = identity
)
duration <- proc.time() - started
if (inherits(value, "error")) {
    stopifnot(job$expected_status == "dta_error", job$method == "read_dta")
    result <- list(status = "dta_error", message = conditionMessage(value))
} else {
    stopifnot(job$expected_status == "ok", nrow(value) == job$rows,
              ncol(value) == job$columns)
    result <- list(status = "ok", rows = nrow(value), columns = ncol(value))
}
result$elapsed_seconds <- unname(duration[["elapsed"]])
result$read_cpu_seconds <- unname(duration[["user.self"]] + duration[["sys.self"]])
jsonlite::write_json(result, args[[2L]], auto_unbox = TRUE, digits = 12)
