benchmark_assert_plain_text <- function(values, label) {
    values <- as.character(values)
    if (anyNA(values) || any(grepl("[\t\r\n]", values, perl = TRUE))) {
        stop(label, " must not contain tabs, newlines, or missing values")
    }
    invisible(values)
}

benchmark_library_path <- function() {
    benchmark_library <- Sys.getenv("DTAPARSER_BENCH_LIB")
    if (!nzchar(benchmark_library)) stop("DTAPARSER_BENCH_LIB is required")
    normalizePath(benchmark_library, winslash = "/", mustWork = TRUE)
}

benchmark_installed_package_path <- function(benchmark_library) {
    benchmark_library <- normalizePath(
        benchmark_library, winslash = "/", mustWork = TRUE
    )
    benchmark_assert_plain_text(benchmark_library, "benchmark library path")
    lexical_path <- file.path(benchmark_library, "dtaparser")
    if (nzchar(Sys.readlink(lexical_path))) {
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

benchmark_activate_library <- function(
    required_packages,
    verify_dtaparser = TRUE,
    benchmark_library = benchmark_library_path()
) {
    .libPaths(c(benchmark_library, .libPaths()))
    available <- vapply(
        required_packages, requireNamespace, logical(1L), quietly = TRUE
    )
    if (any(!available)) {
        stop(
            "benchmark package is unavailable: ",
            paste(required_packages[!available], collapse = ", ")
        )
    }
    if (verify_dtaparser) {
        expected_package <- benchmark_installed_package_path(
            benchmark_library
        )
        loaded_package <- normalizePath(
            getNamespaceInfo(asNamespace("dtaparser"), "path"),
            winslash = "/", mustWork = TRUE
        )
        if (!identical(loaded_package, expected_package)) {
            stop("dtaparser was not loaded from DTAPARSER_BENCH_LIB")
        }
    }
    invisible(benchmark_library)
}

benchmark_legacy_releases <- c(
    104L, 105L, 108L, 110L, 111L, 113L, 114L, 115L
)
benchmark_modern_release_prefix <- charToRaw("<stata_dta><header><release>")

corpus_dta_release <- function(path) {
    tryCatch({
        if (!file.exists(path) || dir.exists(path)) return(NA_integer_)
        connection <- suppressWarnings(file(path, open = "rb"))
        on.exit(close(connection), add = TRUE)
        needed <- length(benchmark_modern_release_prefix) + 3L
        header <- readBin(connection, what = "raw", n = needed)
        if (!length(header)) return(NA_integer_)

        first <- as.integer(header[[1L]])
        if (first %in% benchmark_legacy_releases) return(first)
        if (length(header) < needed || !identical(
            header[seq_along(benchmark_modern_release_prefix)],
            benchmark_modern_release_prefix
        )) return(NA_integer_)

        digits <- rawToChar(header[seq.int(
            length(benchmark_modern_release_prefix) + 1L, needed
        )])
        if (!grepl("^[0-9]{3}$", digits)) return(NA_integer_)
        as.integer(digits)
    }, error = function(error) NA_integer_)
}

corpus_walk_dta <- function(directory) {
    entries <- list.files(
        directory, all.files = TRUE, full.names = TRUE,
        no.. = TRUE, recursive = FALSE
    )
    result <- lapply(entries, function(path) {
        link <- Sys.readlink(path)
        if (!is.na(link) && nzchar(link)) return(character())
        info <- file.info(path, extra_cols = FALSE)
        if (is.na(info$isdir[[1L]])) stop("cannot inspect corpus entry")
        if (isTRUE(info$isdir[[1L]])) return(corpus_walk_dta(path))
        if (grepl("[.]dta$", basename(path), ignore.case = TRUE)) {
            return(normalizePath(path, winslash = "/", mustWork = TRUE))
        }
        character()
    })
    unlist(result, use.names = FALSE)
}

benchmark_corpus_inventory_files <- function(cache_root, corpora) {
    cache_root <- normalizePath(cache_root, winslash = "/", mustWork = TRUE)
    roots <- setNames(file.path(cache_root, corpora), corpora)
    if (!all(dir.exists(roots))) {
        stop("cache root must contain ", paste(corpora, collapse = ", "),
             " directories")
    }
    rows <- lapply(names(roots), function(corpus) {
        paths <- corpus_walk_dta(roots[[corpus]])
        relative <- substring(paths, nchar(cache_root, type = "chars") + 2L)
        order_index <- order(relative, method = "radix")
        paths <- paths[order_index]
        relative <- relative[order_index]
        info <- file.info(paths, extra_cols = FALSE)
        data.frame(
            corpus = rep(corpus, length(paths)),
            relative_path = relative,
            path = paths,
            bytes = as.double(info$size),
            mtime = as.numeric(info$mtime),
            stringsAsFactors = FALSE
        )
    })
    result <- do.call(rbind, rows)
    rownames(result) <- NULL
    result
}

benchmark_directory_files <- function(directory) {
    directory <- normalizePath(directory, winslash = "/", mustWork = TRUE)
    prefix <- paste0(directory, "/")
    walk <- function(current, relative) {
        if (file.access(current, 4L) != 0L ||
            (.Platform$OS.type == "unix" && file.access(current, 1L) != 0L)) {
            stop("installed dtaparser package tree contains an unreadable directory")
        }
        entries <- tryCatch(
            list.files(
                current, recursive = FALSE, all.files = TRUE,
                full.names = FALSE, no.. = TRUE
            ),
            warning = function(condition) stop(condition),
            error = function(condition) stop(condition)
        )
        entries <- sort(entries)
        if (anyNA(entries) || any(grepl("[\t\r\n]", entries, perl = TRUE))) {
            stop("installed package entry must not contain tabs, newlines, or missing values")
        }
        lapply(entries, function(entry) {
            entry_relative <- if (nzchar(relative)) {
                file.path(relative, entry)
            } else entry
            absolute <- file.path(current, entry)
            if (nzchar(Sys.readlink(absolute))) {
                stop("installed dtaparser package tree must not contain symbolic links")
            }
            info <- file.info(absolute)
            if (is.na(info$isdir[[1L]])) {
                stop("installed dtaparser package tree contains an unreadable entry")
            }
            resolved <- normalizePath(
                absolute, winslash = "/", mustWork = TRUE
            )
            if (!startsWith(resolved, prefix)) {
                stop("installed dtaparser package entry resolves outside its package tree")
            }
            if (isTRUE(info$isdir[[1L]])) {
                walk(absolute, entry_relative)
            } else {
                if (!file_test("-f", absolute)) {
                    stop("installed dtaparser package tree contains a non-regular file")
                }
                entry_relative
            }
        })
    }
    files <- unlist(walk(directory, ""), use.names = FALSE)
    sort(as.character(files))
}

benchmark_validate_sha256 <- function(values, expected_length, label) {
    values <- tolower(as.character(values))
    if (length(values) != expected_length || anyNA(values) ||
        any(!grepl("^[0-9a-f]{64}$", values))) {
        stop(label, " could not be hashed")
    }
    unname(values)
}

benchmark_file_sha256 <- function(path) {
    benchmark_validate_sha256(
        tools::sha256sum(path), length(path), "benchmark file"
    )
}

benchmark_hash_workers <- function(cores) {
    if (length(cores) == 1L && isTRUE(is.finite(cores)) && cores >= 1) {
        min(4L, as.integer(cores))
    } else 1L
}

benchmark_files_sha256 <- function(paths, progress = FALSE) {
    workers <- benchmark_hash_workers(
        suppressWarnings(parallel::detectCores(logical = FALSE))
    )
    if (.Platform$OS.type != "windows" && workers > 1L &&
        length(paths) >= 50L) {
        if (progress) {
            message(
                "hashing ", length(paths), " benchmark files with ",
                workers, " workers"
            )
        }
        hashes <- parallel::mclapply(
            paths, benchmark_file_sha256, mc.cores = workers
        )
        return(benchmark_validate_sha256(
            unlist(hashes, use.names = FALSE),
            length(paths),
            "benchmark file"
        ))
    }

    hashes <- character(length(paths))
    for (index in seq_along(paths)) {
        hashes[[index]] <- benchmark_file_sha256(paths[[index]])
        if (progress && index %% 50L == 0L) {
            message("hashed ", index, " benchmark files")
        }
    }
    benchmark_validate_sha256(
        hashes, length(paths), "benchmark file"
    )
}

benchmark_snapshot_file <- function(
    source, destination, expected_bytes, expected_sha256
) {
    expected_sha256 <- benchmark_validate_sha256(
        expected_sha256, 1L, "expected benchmark input"
    )
    temporary <- tempfile(
        pattern = paste0(basename(destination), "."),
        tmpdir = dirname(destination)
    )
    on.exit(unlink(temporary), add = TRUE)
    if (!file.copy(
        source, temporary, overwrite = FALSE,
        copy.mode = FALSE, copy.date = FALSE
    )) {
        stop("could not snapshot benchmark input")
    }
    info <- file.info(temporary, extra_cols = FALSE)
    if (nzchar(Sys.readlink(temporary)) || !file_test("-f", temporary) ||
        is.na(info$size[[1L]]) ||
        as.double(info$size[[1L]]) != as.double(expected_bytes) ||
        !identical(benchmark_file_sha256(temporary), expected_sha256)) {
        stop("benchmark input differs from its inventory identity")
    }
    if ((file.exists(destination) || nzchar(Sys.readlink(destination))) &&
        unlink(destination) != 0L) {
        stop("could not replace benchmark input snapshot")
    }
    if (!file.rename(temporary, destination)) {
        stop("could not publish benchmark input snapshot")
    }
    normalizePath(destination, winslash = "/", mustWork = TRUE)
}

benchmark_directory_sha256 <- function(directory) {
    directory <- normalizePath(directory, winslash = "/", mustWork = TRUE)
    relative <- benchmark_directory_files(directory)
    hashes <- benchmark_file_sha256(file.path(directory, relative))
    unname(tools::sha256sum(bytes = charToRaw(paste(
        paste(relative, hashes, sep = "\t"), collapse = "\n"
    ))))
}

benchmark_harness_sha256 <- function(script_dir) {
    script_dir <- normalizePath(script_dir, winslash = "/", mustWork = TRUE)
    relative <- benchmark_directory_files(script_dir)
    relative <- relative[grepl("[.](R|sh|do)$", relative)]
    shared <- file.path(dirname(script_dir), "benchmark-common.R")
    if (!file_test("-f", shared) || nzchar(Sys.readlink(shared))) {
        stop("shared benchmark helper must be a regular nonsymlink file")
    }
    labels <- c(relative, "../benchmark-common.R")
    paths <- c(file.path(script_dir, relative), shared)
    hashes <- benchmark_file_sha256(paths)
    unname(tools::sha256sum(bytes = charToRaw(paste(
        paste(labels, hashes, sep = "\t"), collapse = "\n"
    ))))
}

benchmark_runtime_binding <- function(
    stata,
    r_executable = file.path(R.home("bin"), "R"),
    rscript_executable = Sys.which("Rscript"),
    time_executable = "/usr/bin/time",
    haven_package = system.file(package = "haven", mustWork = TRUE),
    processx_package = system.file(package = "processx", mustWork = TRUE)
) {
    r_executable <- normalizePath(
        r_executable, winslash = "/", mustWork = TRUE
    )
    rscript_executable <- normalizePath(
        rscript_executable, winslash = "/", mustWork = TRUE
    )
    time_executable <- normalizePath(
        time_executable, winslash = "/", mustWork = TRUE
    )
    stata <- normalizePath(stata, winslash = "/", mustWork = TRUE)
    data.frame(
        r_version = R.version.string,
        r_platform = R.version$platform,
        r_executable_sha256 = benchmark_file_sha256(r_executable),
        rscript_executable_sha256 = benchmark_file_sha256(rscript_executable),
        time_executable_sha256 = benchmark_file_sha256(time_executable),
        haven_sha256 = benchmark_directory_sha256(haven_package),
        processx_sha256 = benchmark_directory_sha256(processx_package),
        stata_sha256 = benchmark_file_sha256(stata),
        stringsAsFactors = FALSE
    )
}

benchmark_publish_or_verify_tsv <- function(
    value, path, drift_message, publish_message, quote = TRUE
) {
    candidate <- tempfile(
        pattern = paste0(basename(path), "."), tmpdir = dirname(path)
    )
    on.exit(unlink(candidate), add = TRUE)
    write.table(
        value, candidate, sep = "\t", row.names = FALSE, quote = quote
    )
    candidate_hash <- benchmark_file_sha256(candidate)
    if (file.exists(path)) {
        if (!identical(benchmark_file_sha256(path), candidate_hash)) {
            stop(drift_message)
        }
    } else if (!file.rename(candidate, path)) {
        stop(publish_message)
    }
    candidate_hash
}

benchmark_publish_or_verify_binding <- function(
    binding, binding_path, resumable_paths, mismatch_message,
    unbound_message
) {
    if (file.exists(binding_path)) {
        existing <- read.delim(
            binding_path, check.names = FALSE, stringsAsFactors = FALSE
        )
        if (!identical(existing, binding)) stop(mismatch_message)
    } else {
        if (any(file.exists(resumable_paths))) stop(unbound_message)
        atomic_tsv(binding, binding_path)
    }
    invisible(NULL)
}

parse_fields <- function(output, prefix) {
    lines <- strsplit(output, "\n", fixed = TRUE)[[1L]]
    marker <- grep(paste0("^", prefix, "\t"), lines, value = TRUE)
    if (!length(marker)) return(character())
    strsplit(tail(marker, 1L), "\t", fixed = TRUE)[[1L]][-1L]
}

parse_memory_metrics <- function(stderr) {
    lines <- strsplit(stderr, "\n", fixed = TRUE)[[1L]]
    darwin <- identical(Sys.info()[["sysname"]], "Darwin")
    rss_line <- grep(
        if (darwin) "maximum resident set size" else
            "Maximum resident set size [(]kbytes[)]",
        lines, value = TRUE
    )
    rss_bytes <- if (!length(rss_line)) {
        NA_real_
    } else if (darwin) {
        as.numeric(sub("^ *([0-9]+).*$", "\\1", tail(rss_line, 1L)))
    } else {
        1024 * as.numeric(sub(
            "^.*: *([0-9]+).*$", "\\1", tail(rss_line, 1L)
        ))
    }
    footprint_line <- if (darwin) {
        grep("peak memory footprint", lines, value = TRUE)
    } else character()
    footprint_bytes <- if (length(footprint_line)) {
        as.numeric(sub(
            "^ *([0-9]+).*$", "\\1", tail(footprint_line, 1L)
        ))
    } else NA_real_
    list(
        rss_bytes = rss_bytes,
        footprint_bytes = footprint_bytes
    )
}

parse_memory <- function(stderr) {
    parse_memory_metrics(stderr)$rss_bytes
}

run_timed_process <- function(command, arguments, work_dir = NULL,
                              environment = character()) {
    time_flag <- if (identical(Sys.info()[["sysname"]], "Darwin")) "-l" else "-v"
    processx::run(
        "/usr/bin/time", c(time_flag, command, arguments), wd = work_dir,
        env = environment, error_on_status = FALSE, echo = FALSE
    )
}

find_stata <- function() {
    candidates <- unique(c(
        Sys.getenv("STATA_BIN"),
        "/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp",
        Sys.which("stata-mp"), Sys.which("stata")
    ))
    candidates <- candidates[nzchar(candidates)]
    candidates <- candidates[file.exists(candidates)]
    if (!length(candidates)) stop("Stata is required; set STATA_BIN")
    normalizePath(candidates[[1L]], winslash = "/", mustWork = TRUE)
}

atomic_tsv <- function(value, path, quote = FALSE) {
    temporary <- tempfile(
        pattern = paste0(basename(path), "."), tmpdir = dirname(path)
    )
    on.exit(unlink(temporary), add = TRUE)
    write.table(value, temporary, sep = "\t", row.names = FALSE, quote = quote)
    if (!file.rename(temporary, path)) stop("could not publish ", path)
}

append_tsv <- function(row, path) {
    present <- file.exists(path)
    temporary <- tempfile(
        pattern = paste0(basename(path), "."), tmpdir = dirname(path)
    )
    on.exit(unlink(temporary), add = TRUE)
    if (present && !file.copy(path, temporary, overwrite = TRUE)) {
        stop("could not stage ", path)
    }
    write.table(
        row, temporary, sep = "\t", row.names = FALSE, quote = TRUE,
        append = present, col.names = !present
    )
    if (!file.rename(temporary, path)) stop("could not publish ", path)
}

new_key_set <- function(keys = character()) {
    result <- new.env(hash = TRUE, parent = emptyenv())
    for (key in keys) assign(key, TRUE, envir = result)
    result
}

key_set_contains <- function(set, key) {
    exists(key, envir = set, inherits = FALSE)
}

key_set_add <- function(set, key) {
    assign(key, TRUE, envir = set)
    invisible(NULL)
}
