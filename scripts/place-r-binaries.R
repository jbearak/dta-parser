# Rscript scripts/place-r-binaries.R <built> <out>
#
# Put the binary packages `R CMD INSTALL --build` left in <built> where
# install.packages() looks for them under <out>/repo, the root of a
# CRAN-like repository, and index them there. Copy them also to
# <out>/assets under names that say the platform and R version, for the
# GitHub release.
#
# macOS and Windows have a binary layout of their own, found with
# contrib.url(). Linux has none: its binaries are served per
# distribution and R version, each directory a repository whose
# src/contrib holds them, as r-universe and Posit's package manager do.

args <- commandArgs(TRUE)
built <- args[1]
repo <- file.path(args[2], "repo")
assets <- file.path(args[2], "assets")
r_version <- paste(R.version$major, sub("\\..*", "", R.version$minor), sep = ".")

if (Sys.info()[["sysname"]] == "Linux") {
  release <- readLines("/etc/os-release")
  codename <- sub("^VERSION_CODENAME=", "", grep("^VERSION_CODENAME=", release, value = TRUE))
  platform <- paste0(codename, "-", R.version$arch)
  dir <- file.path(repo, "bin", "linux", platform, r_version, "src", "contrib")
  files <- list.files(built, "_R_.*\\.tar\\.gz$", full.names = TRUE)
  names <- sub("_R_.*\\.tar\\.gz$", ".tar.gz", basename(files))
  type <- "source"
} else {
  # CRAN's builds of R install binaries; Homebrew's, for one, do not.
  if (.Platform$pkgType == "source") stop("this R does not install binary packages; use CRAN's build")
  mac <- startsWith(.Platform$pkgType, "mac")
  platform <- if (mac) paste0("macos-", sub("aarch64", "arm64", R.version$arch)) else "windows-x86_64"
  dir <- contrib.url(repo, type = .Platform$pkgType)
  files <- list.files(built, "\\.(tgz|zip)$", full.names = TRUE)
  names <- basename(files)
  type <- if (mac) "mac.binary" else "win.binary"
}
stopifnot(length(files) == 3)

dir.create(dir, recursive = TRUE, showWarnings = FALSE)
dir.create(assets, recursive = TRUE, showWarnings = FALSE)
stopifnot(file.copy(files, file.path(dir, names)))
tools::write_PACKAGES(dir, type = type)

# dtaparser_1.0.0.tgz becomes dtaparser_1.0.0_macos-arm64_R4.6.tgz.
ext <- regmatches(names, regexpr("\\.(tar\\.gz|tgz|zip)$", names))
stem <- substr(names, 1, nchar(names) - nchar(ext))
stopifnot(file.copy(files, file.path(assets, paste0(stem, "_", platform, "_R", r_version, ext))))
cat(dir, "\n")
