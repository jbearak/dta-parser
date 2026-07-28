fertility_git_lines <- function(checkout_root, arguments) {
    output <- system2("git", c("-C", shQuote(checkout_root), arguments),
                      stdout = TRUE, stderr = TRUE)
    status <- attr(output, "status", exact = TRUE)
    if (!is.null(status) && status != 0L) stop("git command failed")
    output
}

fertility_tree_digest <- function(checkout_root, scope) {
    paths <- fertility_git_lines(
        checkout_root,
        c("ls-files", "--cached", "--others", "--exclude-standard", "--", scope)
    )
    paths <- sort(unique(paths[nzchar(paths)]))
    if (!length(paths)) stop("no provenance inputs found")
    hashes <- unname(tools::sha256sum(file.path(checkout_root, paths)))
    temporary <- tempfile("fertility-tree-")
    on.exit(unlink(temporary), add = TRUE)
    writeLines(paste(paths, hashes, sep = "\t"), temporary, useBytes = TRUE)
    unname(tools::sha256sum(temporary))
}

fertility_directory_digest <- function(directory) {
    directory <- normalizePath(directory, winslash = "/", mustWork = TRUE)
    paths <- sort(list.files(directory, recursive = TRUE, all.files = TRUE,
                             full.names = FALSE, include.dirs = FALSE, no.. = TRUE))
    if (!length(paths)) stop("installed package is empty")
    temporary <- tempfile("fertility-installed-")
    on.exit(unlink(temporary), add = TRUE)
    writeLines(paste(paths, unname(tools::sha256sum(file.path(directory, paths))),
                     sep = "\t"), temporary, useBytes = TRUE)
    unname(tools::sha256sum(temporary))
}

fertility_package_path <- function(library) {
    library <- normalizePath(library, winslash = "/", mustWork = TRUE)
    lexical <- file.path(library, "dtaparser")
    if (nzchar(Sys.readlink(lexical))) stop("installed package must not be a symlink")
    resolved <- normalizePath(lexical, winslash = "/", mustWork = TRUE)
    if (!identical(dirname(resolved), library)) stop("installed package escaped library")
    resolved
}

fertility_dependency_provenance <- function(packages) {
    record <- list()
    for (package in packages) {
        if (!requireNamespace(package, quietly = TRUE)) stop(package, " is required")
        installed <- normalizePath(find.package(package), winslash = "/",
                                   mustWork = TRUE)
        namespace <- normalizePath(
            getNamespaceInfo(asNamespace(package), "path"),
            winslash = "/", mustWork = TRUE
        )
        if (!identical(installed, namespace)) {
            stop(package, " installed and loaded namespace paths disagree")
        }
        record[[paste0(package, "_version")]] <-
            as.character(utils::packageVersion(package))
        record[[paste0(package, "_path")]] <- installed
        record[[paste0(package, "_namespace_path")]] <- namespace
        record[[paste0(package, "_installed_sha256")]] <-
            fertility_directory_digest(installed)
    }
    as.data.frame(record, stringsAsFactors = FALSE, check.names = FALSE)
}

fertility_current_provenance <- function(checkout_root, library) {
    description <- read.dcf(file.path(checkout_root, "r-package", "dtaparser",
                                      "DESCRIPTION"))
    status <- fertility_git_lines(
        checkout_root,
        c("status", "--porcelain", "--untracked-files=all", "--",
          "r-package/dtaparser", "benchmarks/fertility-surveys")
    )
    provenance <- data.frame(
        schema_version = fertility_schema_version,
        git_commit = fertility_git_lines(checkout_root, c("rev-parse", "HEAD"))[[1L]],
        git_dirty = length(status) > 0L,
        package_version = unname(description[[1L, "Version"]]),
        package_source_sha256 = fertility_tree_digest(checkout_root, "r-package/dtaparser"),
        framework_source_sha256 = fertility_tree_digest(
            checkout_root, "benchmarks/fertility-surveys"
        ),
        installed_package_sha256 = fertility_directory_digest(
            fertility_package_path(library)
        ),
        r_version = R.version.string,
        stringsAsFactors = FALSE, check.names = FALSE
    )
    runtime_packages <- c(
        "haven", "openssl", "callr", "ps", "readr", "rlang", "tibble", "tidyselect"
    )
    cbind(provenance, fertility_dependency_provenance(runtime_packages))
}

fertility_write_provenance <- function(checkout_root, library, path,
                                       source_tarball_sha256) {
    provenance <- fertility_current_provenance(checkout_root, library)
    provenance$source_tarball_sha256 <- tolower(source_tarball_sha256)
    provenance$provenance_id <- fertility_stable_id(provenance)
    provenance$created_at_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    fertility_atomic_write_table(provenance, path)
    invisible(provenance)
}

fertility_provenance_mismatches <- function(current, recorded) {
    missing <- setdiff(names(current), names(recorded))
    if (length(missing)) return(missing)
    names(current)[!vapply(names(current), function(field) {
        identical(as.character(current[[field]]), as.character(recorded[[field]]))
    }, logical(1))]
}

fertility_verify_provenance <- function(checkout_root, library, path) {
    recorded <- read.delim(path, colClasses = "character", check.names = FALSE)
    if (nrow(recorded) != 1L) stop("build provenance must contain exactly one row")
    current <- fertility_current_provenance(checkout_root, library)
    mismatched <- fertility_provenance_mismatches(current, recorded)
    if (length(mismatched)) stop("stale or foreign corpus package installation")
    stable <- recorded[setdiff(names(recorded), c("provenance_id", "created_at_utc"))]
    if (!identical(recorded$provenance_id[[1L]], fertility_stable_id(stable))) {
        stop("invalid corpus build provenance ID")
    }
    recorded
}

fertility_commit_tree <- function(checkout_root, commit, scope,
                                  preserve = FALSE) {
    archive <- tempfile("fertility-commit-", fileext = ".tar")
    extracted <- tempfile("fertility-commit-tree-")
    dir.create(extracted, mode = "0700")
    on.exit(unlink(archive), add = TRUE)
    if (!preserve) on.exit(unlink(extracted, recursive = TRUE), add = TRUE)
    status <- system2("git", c(
        "-C", shQuote(checkout_root), "archive", "--format=tar",
        paste0("--output=", shQuote(archive)), shQuote(commit), shQuote(scope)
    ))
    if (!identical(status, 0L)) stop("could not materialize recorded git tree")
    utils::untar(archive, exdir = extracted)
    paths <- sort(list.files(
        file.path(extracted, scope), recursive = TRUE, all.files = TRUE,
        full.names = FALSE, include.dirs = FALSE, no.. = TRUE
    ))
    if (!length(paths)) stop("recorded git tree scope is empty")
    relative <- file.path(scope, paths)
    temporary <- tempfile("fertility-commit-digest-")
    on.exit(unlink(temporary), add = TRUE)
    writeLines(paste(
        relative, unname(tools::sha256sum(file.path(extracted, relative))), sep = "\t"
    ), temporary, useBytes = TRUE)
    list(digest = unname(tools::sha256sum(temporary)), root = extracted)
}

fertility_verify_recorded_provenance <- function(checkout_root, library, path) {
    recorded <- read.delim(path, colClasses = "character", check.names = FALSE)
    if (nrow(recorded) != 1L ||
        !identical(recorded$schema_version[[1L]],
                   as.character(fertility_legacy_corpus_schema_version)) ||
        !identical(recorded$git_dirty[[1L]], "FALSE")) {
        stop("recorded corpus generation is not migration-safe")
    }
    stable <- recorded[setdiff(names(recorded), c("provenance_id", "created_at_utc"))]
    if (!identical(recorded$provenance_id[[1L]], fertility_stable_id(stable))) {
        stop("invalid recorded corpus provenance ID")
    }
    commit <- recorded$git_commit[[1L]]
    exists <- system2(
        "git", c("-C", shQuote(checkout_root), "cat-file", "-e",
                 shQuote(paste0(commit, "^{commit}"))),
        stdout = FALSE, stderr = FALSE
    )
    if (!identical(exists, 0L)) stop("recorded corpus commit is unavailable")
    package_tree <- fertility_commit_tree(checkout_root, commit, "r-package/dtaparser")
    framework_tree <- fertility_commit_tree(
        checkout_root, commit, "benchmarks/fertility-surveys"
    )
    if (!identical(package_tree$digest, recorded$package_source_sha256[[1L]]) ||
        !identical(framework_tree$digest, recorded$framework_source_sha256[[1L]]) ||
        !identical(fertility_directory_digest(fertility_package_path(library)),
                   recorded$installed_package_sha256[[1L]]) ||
        !identical(R.version.string, recorded$r_version[[1L]])) {
        stop("recorded corpus generation no longer matches its attestation")
    }
    packages <- c(
        "haven", "openssl", "callr", "ps", "readr", "rlang", "tibble", "tidyselect"
    )
    dependencies <- fertility_dependency_provenance(packages)
    fields <- names(dependencies)
    if (length(setdiff(fields, names(recorded))) || any(vapply(fields, function(field) {
        !identical(as.character(dependencies[[field]]), recorded[[field]])
    }, logical(1)))) stop("recorded corpus dependency provenance changed")
    recorded
}

fertility_verify_recorded_framework_snapshot <- function(checkout_root, snapshot_root,
                                                         recorded) {
    tree <- fertility_commit_tree(
        checkout_root, recorded$git_commit[[1L]], "benchmarks/fertility-surveys",
        preserve = TRUE
    )
    extracted <- tree$root
    on.exit(unlink(extracted, recursive = TRUE), add = TRUE)
    for (name in c("common.R", "worker.R", "compare.R", "runtime.R")) {
        expected <- file.path(extracted, "benchmarks", "fertility-surveys", name)
        actual <- file.path(snapshot_root, name)
        if (!file.exists(actual) ||
            !identical(unname(tools::sha256sum(expected)),
                       unname(tools::sha256sum(actual)))) {
            stop("recorded framework snapshot is not migration-safe")
        }
    }
    invisible(TRUE)
}
