# Execute the unchanged standalone cases under the already qualified clean R.
# The loaded-image guard follows runtime-clean-probe/check.R from the prior
# minimum-version study, using its existing native probe without recompilation.
local({
  guard_args <- commandArgs(trailingOnly = TRUE)
  if (length(guard_args) != 2L) stop("Expected frozen adapter and fresh output")
  guard_output <- normalizePath(guard_args[[2L]], mustWork = TRUE)
  study_root <- "/private/tmp/dta-direct-stage5-minimum-preflight"
  expected_rhome <- file.path(study_root, "r460-clean-install/lib/R")
  expected_libraries <- c(file.path(study_root, "r460-clean-dplyr-libraries/1.2.1"),
                          file.path(study_root, "r460-clean-dependencies"),
                          file.path(expected_rhome, "library"))
  frozen_cases <- "/private/tmp/dta-direct-stage5-helper-proof/cases-v4.R"
  expected_adapter <- "/private/tmp/dta-direct-stage5-helper-proof/adapter-v2.R"
  if (!identical(as.character(getRversion()), "4.6.0")) stop("Unexpected R version")
  if (!identical(normalizePath(R.home()), expected_rhome)) stop("Unexpected R home")
  if (!identical(normalizePath(guard_args[[1L]]), expected_adapter)) stop("Unexpected adapter path")
  if (!identical(normalizePath(.libPaths()), expected_libraries)) stop("Unexpected visible libraries")
  dyn.load(file.path(study_root, "runtime-clean-probe/images.so"))
  check_images <- function(phase) {
    images <- .Call("preflight_loaded_images")
    writeLines(images, file.path(guard_output, paste0("loaded-images-", phase, ".txt")))
    rlibs <- images[grepl("(^|/)libR[.]dylib$", images)]
    if (length(rlibs) != 1L) stop("Expected exactly one loaded libR")
    if (!identical(normalizePath(rlibs), file.path(expected_rhome, "lib/libR.dylib"))) {
      stop("Loaded libR is not the qualified clean R4.6.0 library")
    }
    namespace_names <- loadedNamespaces()
    paths <- vapply(namespace_names, function(name) {
      if (name == "base") file.path(R.home(), "library/base")
      else getNamespaceInfo(asNamespace(name), "path")
    }, character(1))
    normalized <- normalizePath(paths)
    allowed <- vapply(normalized, function(path) any(startsWith(path, paste0(expected_libraries, "/"))), logical(1))
    if (!all(allowed)) stop("A namespace came from outside the three clean libraries")
    utils::write.table(data.frame(name = namespace_names, path = normalized),
      file.path(guard_output, paste0("guard-namespaces-", phase, ".tsv")),
      sep = "\t", row.names = FALSE, quote = FALSE)
    dput(list(phase = phase, libR = rlibs, R = R.version, library_paths = .libPaths(),
               image_count = length(images), namespace_count = length(paths)),
      file = file.path(guard_output, paste0("image-guard-", phase, ".R")))
    cat("IMAGE_GUARD", phase, "PASS one clean libR;", length(paths), "clean namespaces\n")
  }
  check_images("before")
  tryCatch({
    source(frozen_cases, local = globalenv(), chdir = FALSE)
    if (!identical(as.character(utils::packageVersion("dplyr")), "1.2.1")) stop("Unexpected dplyr version")
    if (!identical(normalizePath(find.package("dplyr")), file.path(expected_libraries[[1L]], "dplyr"))) {
      stop("Unexpected dplyr library")
    }
  }, finally = check_images("after"))
})
