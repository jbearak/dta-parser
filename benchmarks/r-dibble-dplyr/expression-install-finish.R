# Retained equivalent of the sidecar portion of committed install.R.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) stop("Expected library, source SHA, package tree, archive, helpers")
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
.libPaths(c(library_path, .libPaths()))
if (!identical(as.character(getRversion()), "4.6.1")) stop("Unexpected candidate runtime")
namespace <- loadNamespace("dtatools", lib.loc = library_path)
if (!identical(normalizePath(getNamespaceInfo(namespace, "path")), normalizePath(package_path))) {
  stop("Loaded the wrong dtatools installation")
}
if (length(getNamespaceExports(namespace)) != 106L) stop("Unexpected public export count")
value <- dtatools::dibble(x = 1:2)
if (!inherits(value, "dibble") || !identical(as.double(value$x), c(1, 2))) stop("Tiny baseline load check failed")
validate_benchmark_install(library_path, source_sha)
dll <- getLoadedDLLs()[["dtatools"]][["path"]]
if (!startsWith(normalizePath(dll), paste0(normalizePath(package_path), "/"))) stop("Loaded DLL is outside candidate")
cat("PASS fresh candidate", source_sha, "package tree", source_tree, "exports 106\n")
cat("DLL", dll, "MD5", unname(tools::md5sum(dll)), "\n")
dput(list(R = R.version, libraries = .libPaths(), package_path = package_path,
          exports = length(getNamespaceExports(namespace)), provenance = provenance,
          dll = dll, session = sessionInfo()), file = "installed-identity.R")
namespace_names <- loadedNamespaces()
namespace_paths <- vapply(namespace_names, function(name) {
  if (name == "base") file.path(R.home(), "library/base")
  else getNamespaceInfo(asNamespace(name), "path")
}, character(1))
utils::write.table(data.frame(name = namespace_names, path = namespace_paths),
  "loaded-namespaces.tsv", sep = "\t", row.names = FALSE, quote = FALSE)
writeLines(vapply(getLoadedDLLs(), function(dll) dll[["path"]], character(1)), "loaded-dlls.txt")
