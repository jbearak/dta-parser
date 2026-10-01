# Namespace startup only. Resolve the isolated library before the clock.
library_path <- normalizePath(Sys.getenv("DTATOOLS_BENCH_LIB"), mustWork = TRUE)
.libPaths(c(library_path, .libPaths()))
stopifnot(!"dtatools" %in% loadedNamespaces(), !"jsonlite" %in% loadedNamespaces())
started <- proc.time()
value <- loadNamespace("dtatools")
elapsed <- proc.time() - started
stopifnot(identical(normalizePath(getNamespaceInfo(value, "path")),
                    normalizePath(file.path(library_path, "dtatools"))))
cat(paste("RESULT", "loadNamespace", "default", elapsed[["elapsed"]],
    elapsed[["user.self"]], elapsed[["sys.self"]], 0, 0, NA, sep = "\t"), "\n", sep = "")
