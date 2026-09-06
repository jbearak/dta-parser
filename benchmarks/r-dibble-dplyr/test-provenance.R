#!/usr/bin/env Rscript
# Bounded preflight tests; the supplied library must come from install.R.
args <- commandArgs(TRUE)
if (length(args) != 2L) stop("Usage: test-provenance.R LIBRARY SOURCE_SHA")
source("benchmarks/r-dibble-dplyr/helpers.R")
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
source_sha <- args[[2L]]
validate_benchmark_install(library_path, source_sha)
main <- function() {
    prior_locale <- Sys.getlocale("LC_COLLATE")
    on.exit(Sys.setlocale("LC_COLLATE", prior_locale), add = TRUE)
    stopifnot(nzchar(Sys.setlocale("LC_COLLATE", "C")))
    validate_benchmark_install(library_path, source_sha)
    Sys.setlocale("LC_COLLATE", prior_locale)
    temporary <- tempfile("benchmark-provenance-test-")
    dir.create(temporary)
    on.exit(unlink(temporary, recursive = TRUE), add = TRUE)
    copied_library <- file.path(temporary, "copied-library")
    dir.create(copied_library)
    stopifnot(file.copy(file.path(library_path, "dtatools"), copied_library, recursive = TRUE))
    validate_benchmark_install(copied_library, source_sha)
    package_path <- file.path(copied_library, "dtatools")
    sidecar <- file.path(package_path, "Meta", "benchmark-provenance.rds")
    saved_sidecar <- readBin(sidecar, "raw", n = file.info(sidecar)$size)
    description <- file.path(package_path, "DESCRIPTION")
    saved_description <- readBin(description, "raw", n = file.info(description)$size)
    runners <- c("run.R", "columns.R", "run-rows.R", "row-memory.R", "repeat-group-reconstruct.R")
    checks <- 0L
    for (mode in c("mismatch", "missing", "malformed", "changed")) {
        writeBin(saved_sidecar, sidecar)
        writeBin(saved_description, description)
        if (mode == "missing") unlink(sidecar)
        if (mode == "malformed") writeLines("not an RDS file", sidecar)
        if (mode == "changed") cat("\n", file = description, append = TRUE)
        claimed <- if (mode == "mismatch") paste(rep("0", 40L), collapse = "") else source_sha
        for (runner in runners) {
            output <- file.path(temporary, paste(mode, runner, sep = "-"))
            stdout <- tempfile(tmpdir = temporary)
            stderr <- tempfile(tmpdir = temporary)
            second <- if (runner == "row-memory.R") "double" else output
            status <- system2(file.path(R.home("bin"), "Rscript"),
                vapply(c("--vanilla", file.path("benchmarks/r-dibble-dplyr", runner),
                         copied_library, second, claimed), shQuote, character(1)),
                stdout = stdout, stderr = stderr)
            stopifnot(status != 0L, file.info(stdout)$size == 0, !file.exists(output),
                any(grepl("provenance|SOURCE_SHA|installation changed", readLines(stderr))))
            checks <- checks + 1L
        }
    }
    writeBin(saved_sidecar, sidecar)
    writeBin(saved_description, description)
    validate_benchmark_install(copied_library, source_sha)
    # Matching installation: a complete, small grouped run writes real results.
    output <- file.path(temporary, "matching.csv")
    status <- system2(file.path(R.home("bin"), "Rscript"),
        vapply(c("--vanilla", "benchmarks/r-dibble-dplyr/repeat-group-reconstruct.R",
                 copied_library, output, source_sha), shQuote, character(1)),
        stdout = file.path(temporary, "matching.log"), stderr = file.path(temporary, "matching-errors.log"))
    stopifnot(status == 0L, file.exists(output))
    result <- read.csv(output)
    stopifnot(nrow(result) == 3L, all(result$source_sha == source_sha))
    cat(checks, "direct rejection/no-output cases, matching CSV and locale/copy checks passed\n")
}
main()
