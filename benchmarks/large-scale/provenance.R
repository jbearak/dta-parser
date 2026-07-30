benchmark_assert_plain_text <- function(values, label) {
    values <- as.character(values)
    if (anyNA(values) || any(grepl("[\t\r\n]", values, perl = TRUE))) {
        stop(label, " must not contain tabs, newlines, or missing values")
    }
    invisible(values)
}

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

benchmark_tree_digest <- function(checkout_root, scope) {
    paths <- benchmark_git_lines(
        checkout_root,
        c("ls-files", "--cached", "--others", "--exclude-standard", "--", scope)
    )
    paths <- sort(unique(paths[nzchar(paths)]))
    if (!length(paths)) stop("no provenance inputs found under ", scope)
    benchmark_assert_plain_text(paths, "benchmark source path")

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
    benchmark_assert_plain_text(benchmark_library, "benchmark library path")
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
    benchmark_assert_plain_text(directory, "installed package path")
    entries <- list.files(
        directory, recursive = TRUE, all.files = TRUE,
        full.names = FALSE, include.dirs = TRUE, no.. = TRUE
    )
    entries <- sort(entries)
    if (!length(entries)) {
        stop("no installed provenance inputs found under ", directory)
    }
    benchmark_assert_plain_text(entries, "installed package entry")
    absolute <- file.path(directory, entries)
    if (any(nzchar(Sys.readlink(absolute)))) {
        stop("installed dtaparser package tree must not contain symbolic links")
    }
    resolved <- normalizePath(absolute, winslash = "/", mustWork = TRUE)
    prefix <- paste0(directory, "/")
    if (any(!startsWith(resolved, prefix))) {
        stop("installed dtaparser package entry resolves outside its package tree")
    }
    info <- file.info(absolute)
    if (anyNA(info$isdir)) {
        stop("installed dtaparser package tree contains an unreadable entry")
    }
    files <- !info$isdir
    if (!any(files) || any(!file_test("-f", absolute[files]))) {
        stop("installed dtaparser package tree contains a non-regular file")
    }
    paths <- entries[files]
    hashes <- unname(tools::md5sum(absolute[files]))
    if (anyNA(hashes)) stop("installed dtaparser package file could not be hashed")
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
    benchmark_assert_plain_text(
        c(checkout_root, benchmark_library), "benchmark provenance root"
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
    provenance <- data.frame(
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
    benchmark_assert_provenance_fields(provenance)
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
