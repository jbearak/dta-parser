# Turn release assets into a CRAN-style repository. No contributed R packages needed.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L)
assets <- normalizePath(args[[1]], mustWork = TRUE)
output <- args[[2]]
version <- args[[3]]
stopifnot(grepl("^[0-9]+[.][0-9]+[.][0-9]+$", version))
if (dir.exists(output)) stop("Output directory must not already exist: ", output)
dir.create(output, recursive = TRUE)

stage <- function(asset, directory, type = NULL, filename = basename(asset)) {
  destination <- file.path(output, directory)
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  stopifnot(file.copy(asset, file.path(destination, filename)))
  if (!is.null(type)) {
    count <- tools::write_PACKAGES(destination, type = type, addFiles = TRUE)
    stopifnot(count == 1L)
    index <- read.dcf(file.path(destination, "PACKAGES"))
    stopifnot(index[1, "Package"] == "dtatools", index[1, "Version"] == version)
    for (name in c("PACKAGES", "PACKAGES.gz", "PACKAGES.rds")) {
      stopifnot(file.exists(file.path(destination, name)))
    }
  }
  file.path(directory, filename)
}

source <- file.path(assets, paste0("dtatools_", version, ".tar.gz"))
stopifnot(file.exists(source))
links <- stage(source, "src/contrib", "source")
platforms <- c("windows-x86_64", "macos-arm64", "linux-x86_64")
for (platform in platforms) {
  extension <- switch(platform, `windows-x86_64` = "zip", `macos-arm64` = "tgz",
                      `linux-x86_64` = "tar.gz")
  pattern <- paste0("^dtatools_", gsub(".", "[.]", version, fixed = TRUE),
                    "_R-([0-9]+[.][0-9]+)[.][0-9]+_", platform, "[.]",
                    gsub(".", "[.]", extension, fixed = TRUE), "$")
  asset <- list.files(assets, pattern = pattern, full.names = TRUE)
  if (length(asset) != 1L) stop("Expected exactly one binary for ", platform)
  r_minor <- sub(pattern, "\\1", basename(asset))
  directory <- switch(platform,
    `windows-x86_64` = paste0("bin/windows/contrib/", r_minor),
    `macos-arm64` = paste0("bin/macosx/big-sur-arm64/contrib/", r_minor),
    `linux-x86_64` = paste0("bin/linux/x86_64/", r_minor))
  type <- switch(platform, `windows-x86_64` = "win.binary",
                 `macos-arm64` = "mac.binary.big-sur-arm64", `linux-x86_64` = NULL)
  filename <- if (is.null(type)) basename(asset) else paste0("dtatools_", version, ".", extension)
  links <- c(links, stage(asset, directory, type, filename))
  if (platform == "macos-arm64") {
    # R 4.6 CRAN builds use sonoma-arm64; other R builds still use big-sur-arm64.
    links <- c(links, stage(asset, paste0("bin/macosx/sonoma-arm64/contrib/", r_minor),
                            "mac.binary.sonoma-arm64", filename))
  }
}

writeLines(c(
  '<!doctype html><html lang="en"><meta charset="utf-8">',
  '<meta name="viewport" content="width=device-width, initial-scale=1">',
  '<title>dtatools R package repository</title>',
  '<h1>dtatools R package repository</h1>',
  paste0('<p>Latest stable version: ', version, '. Requires R 4.6 or later.</p>'),
  '<pre>install.packages("dtatools", repos = c(',
  '  dtatools = "https://jbearak.github.io/dta-parser",',
  '  CRAN = "https://cloud.r-project.org"',
  '))</pre>',
  '<p>Windows x86_64 and Apple Silicon macOS 14 or later binaries are available for the R minor version shown below. Other systems install from source and need Cargo and Rust 1.98.0 or later.</p>',
  '<p>The Linux archive is an installed package built on the GitHub Actions Ubuntu runner. It needs a compatible R and system libraries; it is a direct download, not a portable Linux repository binary.</p>',
  '<h2>Downloads</h2><ul>',
  paste0('<li><a href="', links, '">', basename(links), '</a></li>'),
  '</ul><p><a href="https://github.com/jbearak/dta-parser/releases">All releases</a> | <a href="https://github.com/jbearak/dta-parser/blob/main/docs/r-package-repository.md">Installation and publishing details</a></p>',
  '</html>'
), file.path(output, "index.html"))
file.create(file.path(output, ".nojekyll"))
cat("Built repository for dtatools", version, "in", output, "\n")
