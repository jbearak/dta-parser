# Every qualification phase starts in a fresh process with this source/library
# binding; phase-specific checks keep their own process and endpoint guards.
args <- commandArgs(TRUE)
if (length(args) != 4L) stop("Expected library, source revision, source root and output")
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
source(file.path(args[[3L]], "benchmarks/r-dibble-dplyr/helpers.R"))
provenance <- validate_benchmark_install(library_path, args[[2L]])
.libPaths(c(library_path, .libPaths()))
namespace <- loadNamespace("dtatools", lib.loc = library_path)
package_path <- normalizePath(file.path(library_path, "dtatools"))
stopifnot(identical(normalizePath(getNamespaceInfo(namespace, "path")), package_path),
          length(getNamespaceExports(namespace)) == 106L)
dll <- normalizePath(getLoadedDLLs()[["dtatools"]][["path"]])
stopifnot(startsWith(dll, paste0(package_path, "/")))
validate_benchmark_install(library_path, args[[2L]])
dput(list(source_sha = args[[2L]], provenance = provenance,
    package_path = package_path, dll = dll, dll_md5 = tools::md5sum(dll),
    runtime = R.version, libraries = .libPaths()),
    file.path(args[[4L]], "preflight-identity.R"))
cat("PASS exact installed source, namespace, DLL and 106 exports\n")
