# Input and output paths stay in the local manifest, never in published reports.
args <- commandArgs(TRUE)
.libPaths(c(args[[1L]], .libPaths()))
inputs <- jsonlite::fromJSON(args[[2L]], simplifyVector = FALSE)
dir.create(args[[3L]], recursive = TRUE, showWarnings = FALSE)
cases <- list()
for (input in inputs) {
    data <- dtatools::read_dta(input$path)
    arrow_path <- file.path(normalizePath(args[[3L]]), paste0(input$id, ".arrow"))
    stopifnot(!file.exists(arrow_path))
    dtatools::save_arrow(data, arrow_path)
    arrow <- dtatools::read_arrow(arrow_path)
    stopifnot(identical(dtatools::datasig(data), dtatools::datasig(arrow)))
    rm(arrow)
    columns <- names(data)
    add <- function(suffix, selection, mode) {
        cases[[length(cases) + 1L]] <<- list(id = paste(input$id, suffix, sep = "-"),
            dataset = input$id, dta = normalizePath(input$path), arrow = arrow_path,
            rows = nrow(data), columns = if (mode == "all") ncol(data) else length(selection),
            selection = if (mode == "any_of") c(selection, "__absent_parity_column") else selection,
            selection_mode = mode, warm_calls = if (file.info(input$path)$size < 1e6) 100L else 1L)
    }
    add("all", character(), "all")
    for (width in c(10L, 30L, 60L)) {
        if (width > length(columns)) next
        for (layout in c("clustered", "scattered")) {
            positions <- if (layout == "clustered") seq_len(width) else
                as.integer(round(seq(1, length(columns), length.out = width)))
            for (mode in c("known", "any_of", "discover"))
                add(paste(width, layout, mode, sep = "-"), columns[positions], mode)
        }
    }
    rm(data)
    gc()
    message("Qualified current-profile Arrow input: ", input$id)
}
jsonlite::write_json(cases, args[[4L]], pretty = TRUE, auto_unbox = TRUE)
