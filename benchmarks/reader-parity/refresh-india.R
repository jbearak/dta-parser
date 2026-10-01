# Keep the historical india.R setup and timer boundaries for fresh reads.
args <- commandArgs(TRUE)
job <- jsonlite::fromJSON(args[[1L]])
.libPaths(c(job$library, .libPaths()))
stopifnot(job$mode %in% c("qualify", "read"),
          job$method %in% c("read_dta", "read_arrow"),
          job$output %in% c("tibble", "dibble"),
          requireNamespace("dtatools", quietly = TRUE),
          normalizePath(find.package("dtatools")) ==
              normalizePath(file.path(job$library, "dtatools")))
reader <- getExportedValue("dtatools", job$method)
if (job$method == "read_arrow") {
    stopifnot(identical(formals(reader)$verify, TRUE),
              identical(formals(reader)$profile, TRUE))
}

if (job$mode == "qualify") {
    warnings <- character()
    value <- withCallingHandlers(
        reader(job$path, output = job$output, threads = 0L,
               use_numeric_altrep = TRUE),
        warning = function(w) {
            warnings <<- c(warnings, conditionMessage(w))
            invokeRestart("muffleWarning")
        }
    )
    result <- list(signature = dtatools::datasig(value), warnings = warnings)
} else {
    # Qualification requires no warnings; a new warning must fail the run.
    options(warn = 2L)
    started <- proc.time()
    value <- reader(job$path, output = job$output, threads = 0L,
                    use_numeric_altrep = TRUE)
    duration <- proc.time() - started
    result <- list(
        elapsed_seconds = unname(duration[["elapsed"]]),
        read_cpu_seconds = unname(duration[["user.self"]] + duration[["sys.self"]])
    )
}
stopifnot(nrow(value) == job$rows, ncol(value) == job$columns,
          inherits(value, "tbl_df"),
          identical(inherits(value, "dibble"), job$output == "dibble"))
result$rows <- nrow(value)
result$columns <- ncol(value)
result$output <- job$output
jsonlite::write_json(result, args[[2L]], auto_unbox = TRUE, digits = 12)
# The result stays live through process exit. Signature traversal is confined
# to separate qualification children and never enters timed process resources.
