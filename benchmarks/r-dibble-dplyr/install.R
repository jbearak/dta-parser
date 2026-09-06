#!/usr/bin/env Rscript
# Export one git revision, install its source archive, then bind the installation.
args <- commandArgs(TRUE)
if (length(args) != 2L) stop("Usage: install.R LIBRARY REVISION")
source("benchmarks/r-dibble-dplyr/helpers.R")
run <- function(command, arguments, capture = FALSE) {
    value <- system2(command, vapply(arguments, shQuote, character(1)), stdout = if (capture) TRUE else "")
    status <- if (capture) attr(value, "status") else value
    if (!is.null(status) && status != 0L) stop("Benchmark installation command failed: ", command, call. = FALSE)
    if (capture) value else invisible(value)
}
main <- function() {
    source_sha <- run("git", c("rev-parse", "--verify", "--end-of-options", paste0(args[[2L]], "^{commit}")), TRUE)
    if (length(source_sha) != 1L || !grepl("^[0-9a-f]{40}$", source_sha)) stop("Invalid source revision")
    source_tree <- run("git", c("rev-parse", paste0(source_sha, ":r-package/dtatools")), TRUE)
    dir.create(args[[1L]], recursive = TRUE, showWarnings = FALSE)
    library_path <- normalizePath(args[[1L]], mustWork = TRUE)
    package_path <- file.path(library_path, "dtatools")
    if (file.exists(package_path)) stop("Use a fresh library without an existing dtatools installation", call. = FALSE)
    temporary <- tempfile("dibble-benchmark-install-")
    dir.create(temporary)
    on.exit(unlink(temporary, recursive = TRUE), add = TRUE)
    archive <- file.path(temporary, "source.tar")
    run("git", c("archive", "--format=tar", paste0("--output=", archive), source_sha, "r-package/dtatools"))
    utils::untar(archive, exdir = temporary)
    source_path <- file.path(temporary, "r-package", "dtatools")
    version <- read.dcf(file.path(source_path, "DESCRIPTION"), "Version")[[1L]]
    original <- getwd()
    on.exit(setwd(original), add = TRUE, after = FALSE)
    setwd(temporary)
    run(file.path(R.home("bin"), "R"), c("CMD", "build", source_path))
    tarball <- file.path(temporary, paste0("dtatools_", version, ".tar.gz"))
    run(file.path(R.home("bin"), "R"), c("CMD", "INSTALL", paste0("--library=", library_path), tarball))
    provenance <- list(format = 1L, source_sha = source_sha, source_tree = source_tree,
        archive_md5 = unname(tools::md5sum(tarball)), files = benchmark_install_files(package_path))
    saveRDS(provenance, file.path(package_path, "Meta", "benchmark-provenance.rds"))
    validate_benchmark_install(library_path, source_sha)
    cat("Installed benchmark source", source_sha, "in", library_path, "\n")
}
main()
