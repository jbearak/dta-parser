# Retain selected parent-R runtime information even when the benchmark errors.
record_runtime <- function() {
    output <- Sys.getenv("DTA_ROW_OUTER_OUTPUT")
    namespaces <- sort(loadedNamespaces())
    paths <- vapply(namespaces, function(name) {
        if (name == "base") file.path(.Library, "base") else
            getNamespaceInfo(asNamespace(name), "path")
    }, character(1))
    write.table(data.frame(name = namespaces, path = paths),
        file.path(output, "namespaces.tsv"), sep = "\t", row.names = FALSE,
        quote = FALSE)
    dlls <- getLoadedDLLs()
    write.table(data.frame(name = names(dlls), path = vapply(dlls,
        function(dll) dll[["path"]], character(1))),
        file.path(output, "dlls.tsv"), sep = "\t", row.names = FALSE,
        quote = FALSE)
    writeLines(capture.output(sessionInfo()), file.path(output, "runtime.txt"))
}
tryCatch({
    source(Sys.getenv("DTA_ROW_SCRIPT"), local = .GlobalEnv)
    if (nzchar(Sys.getenv("DTA_ROW_ISOLATION_SCRIPT"))) {
        source(Sys.getenv("DTA_ROW_ISOLATION_SCRIPT"), local = .GlobalEnv)
    }
}, finally = tryCatch(record_runtime(), error = function(condition) {
    # Preserve the original benchmark error if runtime recording also fails.
    # The outer runner rejects this marker even after an otherwise successful R exit.
    writeLines(conditionMessage(condition), file.path(
        Sys.getenv("DTA_ROW_OUTER_OUTPUT"), "runtime-recording-error.txt"))
    message("Runtime recording failed: ", conditionMessage(condition))
}))
