# Complete baseline/current value-and-metadata signatures outside all timing.
args <- commandArgs(TRUE)
stopifnot(length(args) == 3L)
.libPaths(c(args[[1L]], .libPaths()))
stopifnot(requireNamespace("dtatools", quietly = TRUE),
    identical(normalizePath(find.package("dtatools")), normalizePath(file.path(args[[1L]], "dtatools"))))
inputs <- jsonlite::fromJSON(args[[2L]], simplifyVector = FALSE)
stream <- file(args[[3L]], "wt")
for (input in inputs) {
    for (output in c("tibble", "dibble")) {
        warnings <- character()
        value <- withCallingHandlers(
            tryCatch(dtatools::read_dta(input$path, output = output, threads = 0L), error = identity),
            warning = function(w) {
                warnings <<- c(warnings, conditionMessage(w))
                invokeRestart("muffleWarning")
            })
        conditions <- list(warnings = warnings,
            error_class = if (inherits(value, "error")) class(value) else character(),
            error_message = if (inherits(value, "error")) conditionMessage(value) else character())
        record <- list(id = input$id, output = output, conditions = conditions,
            conditions_sha256 = unname(tools::sha256sum(bytes = serialize(conditions, NULL, version = 3L))))
        if (inherits(value, "error")) record$status <- "dta_error" else {
            stopifnot(inherits(value, "tbl_df"), identical(inherits(value, "dibble"), output == "dibble"))
            record$status <- "ok"
            record$rows <- nrow(value)
            record$columns <- ncol(value)
            record$signature <- dtatools::datasig(value)
        }
        writeLines(jsonlite::toJSON(record, auto_unbox = TRUE, null = "null"), stream)
        flush(stream)
        rm(value)
        gc()
    }
}
close(stream)
