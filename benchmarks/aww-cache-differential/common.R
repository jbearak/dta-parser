aww_schema_version <- 4L
aww_supported_releases <- c(105L, 108L, 110L, 111L, 113L, 114L, 115L, 117L, 118L, 119L)

aww_abort <- function(message, status = 2L) {
    condition <- structure(list(message = message, call = NULL, status = status),
                           class = c("aww_error", "error", "condition"))
    stop(condition)
}

aww_scalar_integer <- function(value, option, minimum = 1L) {
    parsed <- suppressWarnings(as.numeric(value))
    if (length(parsed) != 1L || is.na(parsed) || !is.finite(parsed) ||
        parsed != floor(parsed) || parsed < minimum || parsed > 2^31 - 1) {
        aww_abort(sprintf("%s must be a whole number >= %s", option, minimum))
    }
    as.integer(parsed)
}

aww_parse_arguments <- function(arguments) {
    options <- list(
        root = "/opt/aww_cache",
        state = file.path(getwd(), "target", "aww-cache-differential"),
        stata = Sys.getenv("STATA_BIN", unset = ""),
        rows = 100000L,
        columns = 256L,
        cells = 8000000L,
        memory_mib = 512L,
        timeout = 900L,
        stata_requests = 1000L,
        stata_row_window = 25000L,
        max_files = Inf,
        ids = character(),
        inventory_only = FALSE,
        retry = FALSE
    )
    for (argument in arguments) {
        if (identical(argument, "--inventory-only")) options$inventory_only <- TRUE else
        if (identical(argument, "--retry")) options$retry <- TRUE else
        if (startsWith(argument, "--root=")) options$root <- sub("^[^=]+=", "", argument) else
        if (startsWith(argument, "--state=")) options$state <- sub("^[^=]+=", "", argument) else
        if (startsWith(argument, "--stata=")) options$stata <- sub("^[^=]+=", "", argument) else
        if (startsWith(argument, "--rows=")) options$rows <- aww_scalar_integer(sub("^[^=]+=", "", argument), "--rows") else
        if (startsWith(argument, "--columns=")) options$columns <- aww_scalar_integer(sub("^[^=]+=", "", argument), "--columns") else
        if (startsWith(argument, "--cells=")) options$cells <- aww_scalar_integer(sub("^[^=]+=", "", argument), "--cells") else
        if (startsWith(argument, "--memory-mib=")) options$memory_mib <- aww_scalar_integer(sub("^[^=]+=", "", argument), "--memory-mib", 128L) else
        if (startsWith(argument, "--timeout=")) options$timeout <- aww_scalar_integer(sub("^[^=]+=", "", argument), "--timeout") else
        if (startsWith(argument, "--stata-requests=")) options$stata_requests <- aww_scalar_integer(sub("^[^=]+=", "", argument), "--stata-requests") else
        if (startsWith(argument, "--stata-row-window=")) options$stata_row_window <- aww_scalar_integer(sub("^[^=]+=", "", argument), "--stata-row-window") else
        if (startsWith(argument, "--max-files=")) options$max_files <- aww_scalar_integer(sub("^[^=]+=", "", argument), "--max-files") else
        if (startsWith(argument, "--id=")) options$ids <- unique(c(options$ids, strsplit(sub("^[^=]+=", "", argument), ",", fixed = TRUE)[[1L]])) else
        aww_abort(sprintf("unknown argument: %s", argument))
    }
    if (!startsWith(options$root, "/") || !dir.exists(options$root)) {
        aww_abort("--root must name an existing absolute directory")
    }
    if (nzchar(Sys.readlink(options$root))) aww_abort("--root must not be a symlink")
    options$root <- normalizePath(options$root, winslash = "/", mustWork = TRUE)
    if (!startsWith(options$state, "/")) {
        options$state <- file.path(getwd(), options$state)
    }
    options$state <- normalizePath(options$state, winslash = "/", mustWork = FALSE)
    options
}

aww_sha256_raw <- function(value) unclass(as.character(openssl::sha256(charToRaw(enc2utf8(value)))))

aww_file_sha256 <- function(path) {
    connection <- file(path, open = "rb")
    on.exit(close(connection), add = TRUE)
    unclass(as.character(openssl::sha256(connection)))
}

aww_file_id <- function(relative_path) paste0("D", substr(aww_sha256_raw(relative_path), 1L, 24L))

aww_walk <- function(directory, root) {
    if (file.access(directory, 4L) != 0L) {
        aww_abort(sprintf("cannot enumerate directory: %s", directory), 3L)
    }
    entries <- tryCatch(
        withCallingHandlers(
            list.files(directory, all.files = TRUE, full.names = TRUE,
                       no.. = TRUE, recursive = FALSE),
            warning = function(warning) stop(warning)
        ),
        error = function(error) aww_abort(
            sprintf("cannot enumerate directory %s: %s", directory, conditionMessage(error)), 3L
        )
    )
    result <- character()
    for (path in entries) {
        link <- Sys.readlink(path)
        if (nzchar(link)) next
        info <- file.info(path, extra_cols = FALSE)
        if (is.na(info$isdir)) {
            aww_abort(sprintf("cannot inspect inventory entry: %s", path), 3L)
        }
        if (isTRUE(info$isdir)) {
            result <- c(result, aww_walk(path, root))
        } else if (isTRUE(fs::is_file(path)) &&
                   grepl("\\.dta$", basename(path), ignore.case = TRUE, perl = TRUE)) {
            result <- c(result, path)
        }
    }
    result
}

aww_release <- function(path) {
    connection <- file(path, open = "rb")
    on.exit(close(connection), add = TRUE)
    prefix <- readBin(connection, "raw", n = 256L)
    if (!length(prefix)) return(NA_integer_)
    if (length(prefix) >= 11L && identical(prefix[1:11], charToRaw("<stata_dta>"))) {
        text <- rawToChar(prefix[seq_len(min(64L, length(prefix)))])
        match <- regexec("<release>([0-9]+)</release>", text, perl = TRUE)
        groups <- regmatches(text, match)[[1L]]
        if (length(groups) == 2L) return(as.integer(groups[[2L]]))
        return(NA_integer_)
    }
    as.integer(prefix[[1L]])
}

aww_inventory <- function(root) {
    paths <- aww_walk(root, root)
    relative <- substring(paths, nchar(root, type = "bytes") + 2L)
    order_index <- order(relative, method = "radix")
    paths <- paths[order_index]
    relative <- relative[order_index]
    rows <- lapply(seq_along(paths), function(index) {
        path <- paths[[index]]
        info <- file.info(path, extra_cols = TRUE)
        status <- "ok"
        digest <- tryCatch(aww_file_sha256(path), error = function(error) {
            status <<- "unreadable"
            NA_character_
        })
        data.frame(
            id = aww_file_id(relative[[index]]),
            relative_path = relative[[index]],
            path = path,
            size = as.double(info$size),
            mtime = as.numeric(info$mtime),
            release = tryCatch(aww_release(path), error = function(error) NA_integer_),
            sha256 = digest,
            inventory_status = status,
            stringsAsFactors = FALSE
        )
    })
    result <- if (length(rows)) do.call(rbind, rows) else data.frame(
        id = character(), relative_path = character(), path = character(),
        size = numeric(), mtime = numeric(), release = integer(), sha256 = character(),
        inventory_status = character(), stringsAsFactors = FALSE
    )
    if (anyDuplicated(result$id)) aww_abort("stable file ID collision", 3L)
    rownames(result) <- NULL
    result
}

aww_atomic_save_rds <- function(value, path) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE, mode = "0700")
    temporary <- tempfile(pattern = ".stage-", tmpdir = dirname(path))
    on.exit(unlink(temporary), add = TRUE)
    saveRDS(value, temporary, version = 3L)
    Sys.chmod(temporary, mode = "0600")
    if (!file.rename(temporary, path)) aww_abort(sprintf("cannot publish %s", path), 3L)
    invisible(path)
}

aww_atomic_write <- function(lines, path) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE, mode = "0700")
    temporary <- tempfile(pattern = ".stage-", tmpdir = dirname(path))
    on.exit(unlink(temporary), add = TRUE)
    writeLines(lines, temporary, useBytes = TRUE)
    Sys.chmod(temporary, mode = "0600")
    if (!file.rename(temporary, path)) aww_abort(sprintf("cannot publish %s", path), 3L)
    invisible(path)
}

aww_config_id <- function(options, build_id, haven_version) {
    aww_sha256_raw(paste(
        aww_schema_version, build_id, haven_version, options$root,
        options$rows, options$columns, options$cells, options$memory_mib,
        options$timeout, options$stata_requests, options$stata_row_window,
        sep = "\037"
    ))
}

aww_checkpoint <- function(run_dir, file_id, tile_id) {
    file.path(run_dir, "checkpoints", file_id, paste0(tile_id, ".rds"))
}

aww_tile_id <- function(kind, batch, skip, n_max, column_start = 0L,
                        column_count = 0L) {
    paste(
        kind, sprintf("b%05d", batch), sprintf("c%010d", column_start),
        sprintf("k%010d", column_count), sprintf("s%016.0f", skip),
        sprintf("n%010d", n_max), sep = "-"
    )
}

aww_leaf_reader_rows <- function(leaves, tile, reader) {
    groups <- split(seq_along(leaves), vapply(leaves, function(result) {
        paste(result$tile$column_start, result$tile$column_count, sep = ":")
    }, character(1)))
    counts <- vapply(groups, function(indices) {
        rows <- vapply(leaves[indices], function(result) {
            result$reader_rows[[reader]]
        }, numeric(1))
        if (anyNA(rows)) NA_real_ else sum(rows)
    }, numeric(1))
    list(
        rows = if (length(counts) && !anyNA(counts)) max(counts) else NA_real_,
        partition_rows = counts,
        consistent = length(unique(counts)) <= 1L
    )
}

aww_update_terminations <- function(terminated, reader_totals, requested, skip) {
    newly_terminated <- is.na(terminated) & reader_totals < requested
    terminated[newly_terminated] <- reader_totals[newly_terminated] + skip
    list(counts = terminated, newly_terminated = newly_terminated)
}

aww_beyond_row_ceiling <- function(terminated, skip, ceiling) {
    if (!is.finite(ceiling) || skip < ceiling) return(character())
    names(terminated)[is.na(terminated)]
}

aww_memory_rows <- function(column_count, options) {
    by_cells <- max(1L, floor(options$cells / max(2L, 2L * column_count)))
    min(options$rows, as.integer(by_cells))
}

aww_source_value <- function(value, format) {
    if (inherits(value, "Date")) return(unclass(value) + 3653)
    if (inherits(value, c("POSIXct", "POSIXt"))) return((unclass(value) + 315619200) * 1000)
    unclass(value)
}

aww_source_unchanged <- function(item) {
    if (is.null(item$sha256) || length(item$sha256) != 1L || is.na(item$sha256)) return(FALSE)
    current <- tryCatch(aww_file_sha256(item$path), error = function(error) NA_character_)
    identical(current, item$sha256)
}

aww_select_inventory <- function(inventory, options) {
    selected <- inventory
    if (length(options$ids)) {
        unknown <- setdiff(options$ids, inventory$id)
        if (length(unknown)) {
            aww_abort(sprintf("unknown --id value(s): %s", paste(unknown, collapse = ", ")))
        }
        selected <- selected[selected$id %in% options$ids, , drop = FALSE]
    }
    if (is.finite(options$max_files)) selected <- utils::head(selected, options$max_files)
    selected
}

aww_read_result <- function(path) {
    if (!file.exists(path)) return(NULL)
    tryCatch(readRDS(path), error = function(error) NULL)
}
