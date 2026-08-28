benchmark_assert_provenance_fields <- function(provenance) {
    stopifnot(is.data.frame(provenance), nrow(provenance) == 1L)
    for (field in names(provenance)) {
        benchmark_assert_plain_text(provenance[[field]], paste0(
            "benchmark provenance field ", field
        ))
    }
    invisible(provenance)
}

benchmark_git_lines <- function(checkout_root, arguments) {
    diagnostics_path <- tempfile("benchmark-git-stderr-")
    on.exit(unlink(diagnostics_path), add = TRUE)
    output <- system2(
        "git",
        c("-C", shQuote(checkout_root), arguments),
        stdout = TRUE, stderr = diagnostics_path
    )
    status <- attr(output, "status", exact = TRUE)
    if (!is.null(status) && status != 0L) {
        diagnostics <- if (file.exists(diagnostics_path)) {
            readLines(diagnostics_path, warn = FALSE)
        } else character()
        stop("git command failed: ", paste(c(output, diagnostics), collapse = "\n"))
    }
    output
}

benchmark_git_paths <- function(checkout_root, scope) {
    output_path <- tempfile("benchmark-git-paths-")
    diagnostics_path <- tempfile("benchmark-git-stderr-")
    on.exit(unlink(c(output_path, diagnostics_path)), add = TRUE)
    status <- system2(
        "git",
        c("-C", shQuote(checkout_root), "ls-files", "-z", "--cached",
          "--others", "--exclude-standard", "--", scope),
        stdout = output_path, stderr = diagnostics_path
    )
    if (!identical(status, 0L)) {
        diagnostics <- if (file.exists(diagnostics_path)) {
            readLines(diagnostics_path, warn = FALSE)
        } else character()
        stop("git command failed: ", paste(diagnostics, collapse = "\n"))
    }
    size <- file.info(output_path)$size[[1L]]
    bytes <- readBin(output_path, "raw", n = size)
    if (!length(bytes)) return(character())
    nul <- which(bytes == as.raw(0L))
    if (!length(nul) || tail(nul, 1L) != length(bytes)) {
        stop("git path output is not NUL terminated")
    }
    starts <- c(1L, head(nul, -1L) + 1L)
    ends <- nul - 1L
    vapply(seq_along(starts), function(index) {
        if (ends[[index]] < starts[[index]]) return("")
        rawToChar(bytes[starts[[index]]:ends[[index]]])
    }, character(1L))
}

benchmark_tree_digest <- function(checkout_root, scope) {
    paths <- benchmark_git_paths(checkout_root, scope)
    paths <- sort(unique(paths[nzchar(paths)]))
    if (!length(paths)) stop("no provenance inputs found under ", scope)
    benchmark_assert_plain_text(paths, "benchmark source path")

    absolute <- file.path(checkout_root, paths)
    hashes <- rep.int("<missing>", length(paths))
    present <- file.exists(absolute)
    if (any(nzchar(Sys.readlink(absolute[present])))) {
        stop("benchmark source provenance input must be a regular nonsymlink file")
    }
    present_paths <- absolute[present]
    if (length(present_paths) && any(!file_test("-f", present_paths))) {
        stop("benchmark source provenance input must be a regular nonsymlink file")
    }
    observed_hashes <- unname(tools::md5sum(present_paths))
    if (anyNA(observed_hashes)) {
        stop("benchmark source provenance input could not be hashed")
    }
    hashes[present] <- observed_hashes
    manifest <- paste(paths, hashes, sep = "\t")
    temporary <- tempfile("dtaparser-provenance-")
    on.exit(unlink(temporary), add = TRUE)
    writeLines(manifest, temporary, useBytes = TRUE)
    unname(tools::md5sum(temporary))
}

benchmark_directory_digest <- function(directory) {
    directory <- normalizePath(directory, winslash = "/", mustWork = TRUE)
    benchmark_assert_plain_text(directory, "installed package path")
    paths <- benchmark_directory_files(directory)
    if (!length(paths)) {
        stop("no installed provenance inputs found under ", directory)
    }
    hashes <- unname(tools::md5sum(file.path(directory, paths)))
    if (anyNA(hashes)) stop("installed dtaparser package file could not be hashed")
    manifest <- paste(paths, hashes, sep = "\t")
    temporary <- tempfile("dtaparser-installed-provenance-")
    on.exit(unlink(temporary), add = TRUE)
    writeLines(manifest, temporary, useBytes = TRUE)
    unname(tools::md5sum(temporary))
}

benchmark_current_provenance <- function(checkout_root, benchmark_library,
                                         package_source_md5 = NULL) {
    checkout_root <- normalizePath(checkout_root, winslash = "/", mustWork = TRUE)
    benchmark_library <- normalizePath(
        benchmark_library, winslash = "/", mustWork = TRUE
    )
    benchmark_assert_plain_text(
        c(checkout_root, benchmark_library), "benchmark provenance root"
    )
    commit <- benchmark_git_lines(checkout_root, c("rev-parse", "HEAD"))
    stopifnot(length(commit) == 1L)
    benchmark_scope <- c(
        "benchmarks/benchmark-common.R",
        "benchmarks/large-scale"
    )
    status <- benchmark_git_lines(
        checkout_root,
        c("status", "--porcelain", "--untracked-files=all", "--",
          "r-package/dtaparser", benchmark_scope)
    )
    description <- read.dcf(
        file.path(checkout_root, "r-package", "dtaparser", "DESCRIPTION")
    )
    if (is.null(package_source_md5)) {
        package_source_md5 <- benchmark_tree_digest(
            checkout_root, "r-package/dtaparser"
        )
    } else {
        package_source_md5 <- tolower(as.character(package_source_md5))
        if (length(package_source_md5) != 1L ||
            is.na(package_source_md5) ||
            !grepl("^[0-9a-f]{32}$", package_source_md5)) {
            stop("package source digest is invalid")
        }
    }
    provenance <- data.frame(
        schema_version = 1L,
        checkout_root = checkout_root,
        git_commit = commit,
        git_dirty = length(status) > 0L,
        package_source_md5 = package_source_md5,
        benchmark_source_md5 = benchmark_tree_digest(
            checkout_root, benchmark_scope
        ),
        installed_package_md5 = benchmark_directory_digest(
            benchmark_installed_package_path(benchmark_library)
        ),
        package_version = unname(description[[1L, "Version"]]),
        benchmark_library = benchmark_library,
        stringsAsFactors = FALSE,
        check.names = FALSE
    )
    benchmark_assert_provenance_fields(provenance)
    provenance
}

benchmark_provenance_id <- function(provenance) {
    benchmark_assert_provenance_fields(provenance)
    fields <- sort(names(provenance))
    values <- vapply(fields, function(field) {
        paste0(field, "=", as.character(provenance[[field]][[1L]]))
    }, character(1))
    unname(tools::sha256sum(bytes = charToRaw(paste(values, collapse = "\n"))))
}

write_benchmark_provenance <- function(checkout_root, benchmark_library, path,
                                       expected_package_source_md5,
                                       source_tarball_sha256) {
    provenance <- benchmark_current_provenance(
        checkout_root, benchmark_library, expected_package_source_md5
    )
    source_tarball_sha256 <- tolower(as.character(source_tarball_sha256))
    if (length(source_tarball_sha256) != 1L ||
        is.na(source_tarball_sha256) ||
        !grepl("^[0-9a-f]{64}$", source_tarball_sha256)) {
        stop("source tarball SHA-256 is invalid")
    }
    provenance$source_tarball_sha256 <- source_tarball_sha256
    provenance$provenance_id <- benchmark_provenance_id(provenance)
    provenance$created_at_utc <- format(
        Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
    )
    benchmark_assert_provenance_fields(provenance)
    atomic_tsv(provenance, path)
    invisible(provenance)
}

verify_benchmark_provenance <- function(checkout_root, benchmark_library, path) {
    if (!file.exists(path)) {
        stop("benchmark provenance record is missing: ", path)
    }
    recorded <- read.delim(
        path, check.names = FALSE, stringsAsFactors = FALSE,
        colClasses = "character"
    )
    if (nrow(recorded) != 1L) stop("benchmark provenance record must have one row")
    benchmark_assert_provenance_fields(recorded)
    current <- benchmark_current_provenance(checkout_root, benchmark_library)
    fields <- names(current)
    if (!all(c(fields, "source_tarball_sha256", "provenance_id",
               "created_at_utc") %in% names(recorded))) {
        stop("benchmark provenance record is missing required fields")
    }
    mismatched <- fields[!vapply(fields, function(field) {
        identical(as.character(recorded[[field]]), as.character(current[[field]]))
    }, logical(1))]
    if (length(mismatched)) {
        stop(
            "stale or foreign benchmark installation; provenance mismatch: ",
            paste(mismatched, collapse = ", ")
        )
    }
    if (!grepl("^[0-9a-f]{64}$", recorded$source_tarball_sha256[[1L]])) {
        stop("benchmark provenance source tarball SHA-256 is invalid")
    }
    stable_fields <- setdiff(names(recorded), c("provenance_id", "created_at_utc"))
    expected_id <- benchmark_provenance_id(recorded[stable_fields])
    if (!identical(as.character(recorded$provenance_id[[1L]]), expected_id)) {
        stop("benchmark provenance ID does not match its stable fields")
    }
    invisible(recorded)
}
