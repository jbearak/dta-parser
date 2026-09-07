# Uses the already qualified clean-R native loaded-image probe, without edits.
minimum_runtime_guard <- function(output, phase) {
    study <- "/private/tmp/dta-direct-stage5-minimum-preflight"
    expected_home <- file.path(study, "r460-clean-install/lib/R")
    expected_libraries <- strsplit(Sys.getenv("DTA_MINIMUM_LIBRARIES"), .Platform$path.sep, fixed = TRUE)[[1L]]
    if (!identical(as.character(getRversion()), "4.6.0")) stop("Unexpected R version")
    if (!identical(normalizePath(R.home()), expected_home)) stop("Unexpected R home")
    if (!identical(normalizePath(.libPaths()), normalizePath(expected_libraries))) stop("Unexpected visible libraries")
    if (!is.loaded("preflight_loaded_images")) dyn.load(file.path(study, "runtime-clean-probe/images.so"))
    images <- .Call("preflight_loaded_images")
    writeLines(images, file.path(output, paste0("loaded-images-", phase, ".txt")))
    rlibs <- images[grepl("(^|/)libR[.]dylib$", images)]
    if (length(rlibs) != 1L || !identical(normalizePath(rlibs), file.path(expected_home, "lib/libR.dylib"))) {
        stop("Expected exactly one qualified clean libR")
    }
    names <- loadedNamespaces()
    paths <- vapply(names, function(name) {
        if (name == "base") file.path(R.home(), "library/base")
        else getNamespaceInfo(asNamespace(name), "path")
    }, character(1))
    paths <- normalizePath(paths)
    allowed <- vapply(paths, function(path) any(startsWith(path, paste0(expected_libraries, "/"))), logical(1))
    if (!all(allowed)) stop("Namespace loaded outside clean libraries")
    write.table(data.frame(name = names, path = unname(paths)),
        file.path(output, paste0("guard-namespaces-", phase, ".tsv")),
        sep = "\t", quote = FALSE, row.names = FALSE)
    writeLines(vapply(getLoadedDLLs(), function(dll) dll[["path"]], character(1)),
        file.path(output, paste0("guard-dlls-", phase, ".txt")))
    dput(list(R = R.version, libraries = .libPaths(), libR = rlibs,
              namespaces = paths, image_count = length(images)),
        file = file.path(output, paste0("runtime-guard-", phase, ".R")))
    cat("PASS", phase, "one clean R4.6.0 libR;", length(names), "clean namespaces\n")
}
