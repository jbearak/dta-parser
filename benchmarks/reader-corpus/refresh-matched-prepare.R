# One untimed file: prepare Arrow, then qualify both explicit containers.
args <- commandArgs(TRUE)
job <- jsonlite::fromJSON(args[[1L]])
.libPaths(c(job$library, .libPaths()))
stopifnot(requireNamespace("dtatools", quietly = TRUE),
          normalizePath(getNamespaceInfo("dtatools", "path")) ==
              normalizePath(file.path(job$library, "dtatools")))
options(warn = 2L)
result <- list(id = job$id, containers = list(), reused_arrow = job$reuse)
for (output in c("tibble", "dibble")) {
    data <- dtatools::read_dta(job$dta, output = output, threads = 0L)
    stopifnot(inherits(data, "tbl_df"),
              identical(inherits(data, "dibble"), output == "dibble"))
    dimensions <- dim(data)
    signature <- dtatools::datasig(data)
    if (output == "tibble" && !job$reuse) {
        stopifnot(!file.exists(job$arrow))
        # Preserve source declarations; dibble reads apply their normal casts.
        dtatools::save_arrow(data, job$arrow)
    }
    rm(data)
    gc()
    restored <- dtatools::read_arrow(job$arrow, verify = TRUE,
                                    output = output, threads = 0L)
    stopifnot(identical(dim(restored), dimensions),
              identical(dtatools::datasig(restored), signature),
              inherits(restored, "tbl_df"),
              identical(inherits(restored, "dibble"), output == "dibble"))
    result$containers[[output]] <- list(rows = dimensions[[1L]],
        columns = dimensions[[2L]], signature = signature, warnings = character())
    rm(restored)
    gc()
}
stopifnot(identical(result$containers$tibble$rows, result$containers$dibble$rows),
          identical(result$containers$tibble$columns, result$containers$dibble$columns))
jsonlite::write_json(result, args[[2L]], auto_unbox = TRUE, pretty = TRUE)
