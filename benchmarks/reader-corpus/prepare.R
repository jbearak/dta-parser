# Prepare current-profile Arrow copies before any timed reads.
args <- commandArgs(TRUE)
stopifnot(length(args) == 4L)
.libPaths(c(args[[1L]], .libPaths()))
stopifnot(requireNamespace("dtatools", quietly = TRUE))
stopifnot(normalizePath(find.package("dtatools")) ==
          normalizePath(file.path(args[[1L]], "dtatools")))
inputs <- jsonlite::fromJSON(args[[2L]], simplifyVector = FALSE)
dir.create(args[[3L]], recursive = TRUE, showWarnings = FALSE)
dir.create(args[[4L]], recursive = TRUE, showWarnings = FALSE)
for (index in seq_along(inputs)) {
    input <- inputs[[index]]
    arrow_path <- file.path(args[[3L]], paste0(input$id, ".arrow"))
    output_path <- file.path(args[[4L]], paste0(input$id, ".json"))
    stopifnot(!file.exists(arrow_path), !file.exists(output_path))
    warnings <- character()
    data <- withCallingHandlers(
        tryCatch(dtatools::read_dta(input$path), error = identity),
        warning = function(w) {
            warnings <<- c(warnings, conditionMessage(w))
            invokeRestart("muffleWarning")
        }
    )
    if (inherits(data, "error")) {
        stopifnot(!input$common)
        result <- list(id = input$id, status = "dta_error",
                       message = conditionMessage(data), warnings = warnings)
    } else {
        stopifnot(length(warnings) == 0L)
        if (input$common) {
            stopifnot(nrow(data) == input$rows, ncol(data) == input$columns)
        }
        signature <- dtatools::datasig(data)
        dtatools::save_arrow(data, arrow_path)
        arrow <- dtatools::read_arrow(arrow_path, verify = TRUE)
        stopifnot(identical(signature, dtatools::datasig(arrow)),
                  identical(dim(data), dim(arrow)))
        result <- list(id = input$id, status = "ok", rows = nrow(data),
                       columns = ncol(data), signature = signature,
                       arrow = normalizePath(arrow_path), warnings = warnings)
        rm(arrow)
    }
    jsonlite::write_json(result, output_path, auto_unbox = TRUE, pretty = TRUE)
    rm(data)
    gc()
    if (index %% 25L == 0L) message("prepared: ", index, "/", length(inputs))
}
