benchmark_git_lines <- function(checkout_root, arguments) {
    output <- system2(
        "git",
        c("-C", shQuote(checkout_root), arguments),
        stdout = TRUE, stderr = TRUE
    )
    status <- attr(output, "status", exact = TRUE)
    if (!is.null(status) && status != 0L) {
        stop("git command failed: ", paste(output, collapse = "\n"))
    }
    output
}

benchmark_tree_digest <- function(checkout_root, scope) {
    paths <- benchmark_git_lines(
        checkout_root,
        c("ls-files", "--cached", "--others", "--exclude-standard", "--", scope)
    )
    paths <- sort(unique(paths[nzchar(paths)]))
    if (!length(paths)) stop("no provenance inputs found under ", scope)

    absolute <- file.path(checkout_root, paths)
    hashes <- rep.int("<missing>", length(paths))
    present <- file.exists(absolute)
    hashes[present] <- unname(tools::md5sum(absolute[present]))
    manifest <- paste(paths, hashes, sep = "\t")
    temporary <- tempfile("dtaparser-provenance-")
    on.exit(unlink(temporary), add = TRUE)
    writeLines(manifest, temporary, useBytes = TRUE)
    unname(tools::md5sum(temporary))
}

benchmark_installed_package_path <- function(benchmark_library) {
    benchmark_library <- normalizePath(
        benchmark_library, winslash = "/", mustWork = TRUE
    )
    lexical_path <- file.path(benchmark_library, "dtaparser")
    link_target <- Sys.readlink(lexical_path)
    if (nzchar(link_target)) {
        stop("installed dtaparser package root must not be a symbolic link")
    }
    resolved_path <- normalizePath(
        lexical_path, winslash = "/", mustWork = TRUE
    )
    if (!identical(dirname(resolved_path), benchmark_library)) {
        stop("installed dtaparser package must resolve directly inside DTAPARSER_BENCH_LIB")
    }
    resolved_path
}

benchmark_directory_digest <- function(directory) {
    directory <- normalizePath(directory, winslash = "/", mustWork = TRUE)
    paths <- list.files(
        directory, recursive = TRUE, all.files = TRUE,
        full.names = FALSE, include.dirs = FALSE, no.. = TRUE
    )
    paths <- sort(paths)
    if (!length(paths)) stop("no installed provenance inputs found under ", directory)
    hashes <- unname(tools::md5sum(file.path(directory, paths)))
    manifest <- paste(paths, hashes, sep = "\t")
    temporary <- tempfile("dtaparser-installed-provenance-")
    on.exit(unlink(temporary), add = TRUE)
    writeLines(manifest, temporary, useBytes = TRUE)
    unname(tools::md5sum(temporary))
}

benchmark_current_provenance <- function(checkout_root, benchmark_library) {
    checkout_root <- normalizePath(checkout_root, winslash = "/", mustWork = TRUE)
    benchmark_library <- normalizePath(
        benchmark_library, winslash = "/", mustWork = TRUE
    )
    commit <- benchmark_git_lines(checkout_root, c("rev-parse", "HEAD"))
    stopifnot(length(commit) == 1L)
    status <- benchmark_git_lines(
        checkout_root,
        c("status", "--porcelain", "--untracked-files=all", "--",
          "r-package/dtaparser", "benchmarks/large-scale")
    )
    description <- read.dcf(
        file.path(checkout_root, "r-package", "dtaparser", "DESCRIPTION")
    )
    data.frame(
        schema_version = 1L,
        checkout_root = checkout_root,
        git_commit = commit,
        git_dirty = length(status) > 0L,
        package_source_md5 = benchmark_tree_digest(
            checkout_root, "r-package/dtaparser"
        ),
        benchmark_source_md5 = benchmark_tree_digest(
            checkout_root, "benchmarks/large-scale"
        ),
        installed_package_md5 = benchmark_directory_digest(
            benchmark_installed_package_path(benchmark_library)
        ),
        package_version = unname(description[[1L, "Version"]]),
        benchmark_library = benchmark_library,
        stringsAsFactors = FALSE,
        check.names = FALSE
    )
}

benchmark_provenance_id <- function(provenance) {
    stopifnot(is.data.frame(provenance), nrow(provenance) == 1L)
    fields <- sort(names(provenance))
    values <- vapply(fields, function(field) {
        paste0(field, "=", as.character(provenance[[field]][[1L]]))
    }, character(1))
    unname(tools::sha256sum(bytes = charToRaw(paste(values, collapse = "\n"))))
}

write_benchmark_provenance <- function(checkout_root, benchmark_library, path,
                                       expected_package_source_md5,
                                       source_tarball_sha256) {
    provenance <- benchmark_current_provenance(checkout_root, benchmark_library)
    if (!identical(
        as.character(provenance$package_source_md5[[1L]]),
        as.character(expected_package_source_md5)
    )) {
        stop("package source changed while building the benchmark installation")
    }
    source_tarball_sha256 <- tolower(as.character(source_tarball_sha256))
    if (length(source_tarball_sha256) != 1L ||
        !grepl("^[0-9a-f]{64}$", source_tarball_sha256)) {
        stop("source tarball SHA-256 is invalid")
    }
    provenance$source_tarball_sha256 <- source_tarball_sha256
    provenance$provenance_id <- benchmark_provenance_id(provenance)
    provenance$created_at_utc <- format(
        Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
    )
    temporary <- tempfile(
        pattern = paste0(basename(path), "."), tmpdir = dirname(path)
    )
    on.exit(unlink(temporary), add = TRUE)
    write.table(
        provenance, temporary, sep = "\t", row.names = FALSE, quote = FALSE
    )
    if (!file.rename(temporary, path)) {
        stop("could not atomically replace ", path)
    }
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
