args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) stop("Expected library, source SHA, package tree, archive, helpers")
source(Sys.getenv("DTA_MINIMUM_GUARD"))
minimum_runtime_guard(getwd(), "before")
tryCatch({
    library_path <- normalizePath(args[[1L]], mustWork = TRUE)
    source_sha <- args[[2L]]
    source_tree <- args[[3L]]
    archive <- normalizePath(args[[4L]], mustWork = TRUE)
    source(args[[5L]])
    package_path <- file.path(library_path, "dtatools")
    sidecar <- file.path(package_path, "Meta/benchmark-provenance.rds")
    if (file.exists(sidecar)) stop("Refusing existing benchmark provenance")
    provenance <- list(format = 1L, source_sha = source_sha, source_tree = source_tree,
        archive_md5 = unname(tools::md5sum(archive)), files = benchmark_install_files(package_path))
    saveRDS(provenance, sidecar)
    validate_benchmark_install(library_path, source_sha)
    namespace <- loadNamespace("dtatools", lib.loc = library_path)
    if (!identical(normalizePath(getNamespaceInfo(namespace, "path")), normalizePath(package_path))) stop("Wrong dtatools namespace")
    if (length(getNamespaceExports(namespace)) != 106L) stop("Unexpected public export count")
    value <- dtatools::dibble(x = 1:2)
    if (!inherits(value, "dibble") || !identical(as.double(value$x), c(1, 2))) stop("Constructor failed")
    value <- dplyr::mutate(value, y = c(NA_real_, 1), z = y > 0)
    if (!identical(value$z, c(TRUE, TRUE))) stop("Sequential typing failed")
    if (!identical(as.character(utils::packageVersion("dplyr")), "1.2.1")) stop("Wrong dplyr version")
    validate_benchmark_install(library_path, source_sha)
    dll <- getLoadedDLLs()[["dtatools"]][["path"]]
    if (!startsWith(normalizePath(dll), paste0(normalizePath(package_path), "/"))) stop("DLL outside installation")
    dput(list(source = source_sha, tree = source_tree, provenance = provenance,
              dll = dll, dll_md5 = unname(tools::md5sum(dll)), session = sessionInfo()),
         file = "installed-identity.R")
    names <- loadedNamespaces()
    paths <- vapply(names, function(name) {
        if (name == "base") file.path(R.home(), "library/base")
        else getNamespaceInfo(asNamespace(name), "path")
    }, character(1))
    write.table(data.frame(name = names, path = unname(paths)),
        "loaded-namespaces.tsv", sep = "\t", quote = FALSE, row.names = FALSE)
    cat("PASS clean-R minimum candidate", source_sha, "exports106 and sequential Stata typing\n")
}, finally = minimum_runtime_guard(getwd(), "after"))
