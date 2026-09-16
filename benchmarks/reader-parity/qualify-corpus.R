args <- commandArgs(TRUE)
.libPaths(c(args[[1L]], .libPaths()))
library(dtatools)
inputs <- jsonlite::fromJSON(args[[2L]], simplifyVector = FALSE)
output <- file(args[[3L]], "wt")
for (input in inputs) {
    warnings <- character()
    record <- tryCatch(withCallingHandlers({
        reader <- getExportedValue("dtatools", input$reader)
        value <- reader(input$path)
        result <- list(id = input$id, reader = input$reader, status = "ok",
            rows = nrow(value), columns = ncol(value), signature = datasig(value))
        rm(value)
        result
    }, warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
    }), error = function(e) list(id = input$id, reader = input$reader,
        status = "error", message = conditionMessage(e)))
    record$warnings <- warnings
    writeLines(jsonlite::toJSON(record, auto_unbox = TRUE, null = "null"), output)
    flush(output)
    gc()
}
close(output)
