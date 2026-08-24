#!/usr/bin/env Rscript

aww_script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
aww_script_path <- normalizePath(sub("^--file=", "", aww_script_argument[[1L]]), winslash = "/", mustWork = TRUE)
aww_script_dir <- dirname(aww_script_path)
source(file.path(aww_script_dir, "common.R"))
source(file.path(aww_script_dir, "compare.R"))
source(file.path(aww_script_dir, "stata.R"))

aww_run_worker <- function(item, tile, options, package_library, package_path) {
    tryCatch(callr::r(
        function(path, tile, worker_script, common_script, compare_script,
                 package_library, package_path) {
            source(worker_script, local = environment())
            aww_worker(path, tile, common_script, compare_script,
                       package_library, package_path)
        },
        args = list(
            path = item$path,
            tile = tile,
            worker_script = file.path(aww_script_dir, "worker.R"),
            common_script = file.path(aww_script_dir, "common.R"),
            compare_script = file.path(aww_script_dir, "compare.R"),
            package_library = package_library,
            package_path = package_path
        ),
        env = c(
            R_ENVIRON_USER = "/dev/null",
            R_PROFILE_USER = "/dev/null",
            R_MAX_VSIZE = sprintf("%dM", options$memory_mib)
        ),
        timeout = options$timeout,
        user_profile = FALSE,
        system_profile = FALSE,
        spinner = FALSE
    ), error = function(error) {
        message <- conditionMessage(error)
        classification <- if (grepl("timed out|timeout", message, ignore.case = TRUE)) "timeout" else
            if (grepl("vector memory exhausted|cannot allocate|memory limit|out of memory|bad_alloc", message, ignore.case = TRUE)) "memory-limit" else
            "worker-crash"
        list(
            schema_version = aww_schema_version, tile = tile,
            elapsed_seconds = NA_real_, reader_errors = list(supervisor = conditionMessage(error)),
            reader_rows = c(dtaparser = NA_integer_, haven = NA_integer_),
            classification = classification, disputes = aww_empty_disputes()
        )
    })
}

aww_execute <- function(item, tile, options, package_library, package_path,
                        run_dir, config_id) {
    path <- aww_checkpoint(run_dir, item$id, tile$id)
    cached <- aww_read_result(path)
    if (!is.null(cached) && identical(cached$schema_version, aww_schema_version) &&
        identical(cached$config_id, config_id) && identical(cached$file_sha256, item$sha256) &&
        identical(cached$tile, tile) && (!options$retry || cached$result$classification %in% c("pass", "dispute"))) {
        cached$result$resumed <- TRUE
        return(cached$result)
    }
    result <- aww_run_worker(item, tile, options, package_library, package_path)
    result$resumed <- FALSE
    aww_atomic_save_rds(list(
        schema_version = aww_schema_version, config_id = config_id,
        file_sha256 = item$sha256, tile = tile, result = result
    ), path)
    result
}

aww_execute_split <- function(item, tile, options, package_library, package_path,
                              run_dir, config_id) {
    result <- aww_execute(item, tile, options, package_library, package_path, run_dir, config_id)
    if (!identical(result$classification, "memory-limit")) return(list(result))
    if (tile$column_count > 1L) {
        left_count <- floor(tile$column_count / 2L)
        right_count <- tile$column_count - left_count
        left <- tile
        left$column_count <- as.integer(left_count)
        if (!is.null(left$storage)) left$storage <- head(left$storage, left_count)
        left$id <- aww_tile_id(
            left$kind, left$batch, left$skip, left$n_max,
            left$column_start, left$column_count
        )
        right <- tile
        right$column_start <- tile$column_start + left_count
        right$column_count <- as.integer(right_count)
        if (!is.null(right$storage)) right$storage <- tail(right$storage, right_count)
        right$id <- aww_tile_id(
            right$kind, right$batch, right$skip, right$n_max,
            right$column_start, right$column_count
        )
        return(c(
            aww_execute_split(item, left, options, package_library, package_path, run_dir, config_id),
            aww_execute_split(item, right, options, package_library, package_path, run_dir, config_id)
        ))
    }
    if (!identical(tile$kind, "value") || tile$n_max <= 1L) return(list(result))
    left_count <- floor(tile$n_max / 2)
    right_count <- tile$n_max - left_count
    left <- tile
    left$n_max <- as.integer(left_count)
    left$id <- aww_tile_id(
        left$kind, left$batch, left$skip, left$n_max,
        left$column_start, left$column_count
    )
    right <- tile
    right$skip <- tile$skip + left_count
    right$n_max <- as.integer(right_count)
    right$id <- aww_tile_id(
        right$kind, right$batch, right$skip, right$n_max,
        right$column_start, right$column_count
    )
    c(
        aww_execute_split(item, left, options, package_library, package_path, run_dir, config_id),
        aww_execute_split(item, right, options, package_library, package_path, run_dir, config_id)
    )
}

aww_file <- function(item, options, package_library, package_path, run_dir, config_id) {
    started <- proc.time()[["elapsed"]]
    base <- list(
        id = item$id, relative_path = item$relative_path, release = item$release,
        rows = NA_real_, columns = NA_integer_, status = "unresolved",
        tiles = 0L, resumed = 0L, disputes = aww_empty_disputes(),
        ownership = character(), adjudication = "not-needed", elapsed_seconds = 0
    )
    finish <- function(result) {
        if (!is.na(item$sha256) && !aww_source_unchanged(item)) {
            result$status <- "input-changed"
            result$adjudication <- "input-changed"
            result$ownership <- rep("unresolved", nrow(result$disputes))
        }
        result$elapsed_seconds <- unname(proc.time()[["elapsed"]] - started)
        result
    }
    if (!identical(item$inventory_status, "ok")) {
        base$status <- "unreadable"
        return(finish(base))
    }
    if (is.na(item$release) || !(item$release %in% aww_supported_releases)) {
        base$status <- if (is.na(item$release)) "empty-or-corrupt" else "unsupported-release"
        return(finish(base))
    }
    shape_tile <- list(
        id = aww_tile_id("shape", 0L, 0, 0L, 1L, 0L),
        kind = "shape", batch = 0L,
        column_start = 1L, column_count = 0L, skip = 0, n_max = 0L
    )
    shape_result <- aww_execute(
        item, shape_tile, options, package_library, package_path, run_dir, config_id
    )
    base$tiles <- 1L
    base$resumed <- as.integer(isTRUE(shape_result$resumed))
    base$disputes <- shape_result$disputes
    if (shape_result$classification %in% c("dtaparser-error", "haven-error", "shared-reader-error")) {
        base$disputes <- aww_dispute(
            "reader_error", "reader-error", attribute = shape_result$classification,
            dtaparser = shape_result$reader_errors$dtaparser,
            haven = shape_result$reader_errors$haven
        )
        probe <- aww_stata_open(item, options, run_dir, aww_script_dir)
        base$adjudication <- probe
        if (identical(probe, "open")) {
            base$ownership <- switch(shape_result$classification,
                "dtaparser-error" = "dtaparser-wrong",
                "haven-error" = "haven-wrong",
                "shared-reader-error" = "both-wrong"
            )
            base$status <- base$ownership
        } else if (identical(probe, "stata-source-error")) {
            base$ownership <- "source-corrupt"
            base$status <- "empty-or-corrupt"
        } else {
            base$ownership <- "unresolved"
            base$status <- "unresolved"
        }
        return(finish(base))
    }
    if (!shape_result$classification %in% c("pass", "dispute")) {
        base$status <- shape_result$classification
        return(finish(base))
    }
    metadata <- shape_result$metadata
    base$rows <- metadata$rows
    base$columns <- metadata$columns
    batch_starts <- if (metadata$columns > 0L) {
        seq.int(1L, metadata$columns, by = options$columns)
    } else integer()
    terminal_failure <- NULL
    failed_result <- NULL
    metadata_results <- list()
    for (batch_index in seq_along(batch_starts)) {
        column_start <- batch_starts[[batch_index]]
        column_count <- min(options$columns, metadata$columns - column_start + 1L)
        tile <- list(
            id = aww_tile_id(
                "metadata", batch_index, 0, 0L, column_start, column_count
            ), kind = "metadata",
            batch = as.integer(batch_index), column_start = as.integer(column_start),
            column_count = as.integer(column_count), skip = 0, n_max = 0L
        )
        leaves <- aww_execute_split(
            item, tile, options, package_library, package_path, run_dir, config_id
        )
        metadata_results <- c(metadata_results, leaves)
        bad <- vapply(leaves, function(result) {
            !result$classification %in% c("pass", "dispute")
        }, logical(1))
        if (any(bad)) {
            failed_result <- leaves[[which(bad)[[1L]]]]
            terminal_failure <- failed_result$classification
            break
        }
        for (leaf in leaves) {
            indices <- seq.int(
                leaf$tile$column_start, length.out = leaf$tile$column_count
            )
            metadata$names[indices] <- leaf$metadata$names
            metadata$formats[indices] <- leaf$metadata$formats
            metadata$storage[indices] <- leaf$metadata$storage
        }
    }
    base$tiles <- base$tiles + length(metadata_results)
    base$resumed <- base$resumed + sum(vapply(
        metadata_results, function(result) isTRUE(result$resumed), logical(1)
    ))
    base$disputes <- aww_bind_disputes(c(
        list(base$disputes), lapply(metadata_results, `[[`, "disputes")
    ))
    observed_rows <- list()
    all_results <- list()
    trusted_rows <- NA_real_
    stata_info <- NULL
    if (is.null(terminal_failure)) for (batch_index in seq_along(batch_starts)) {
        column_start <- batch_starts[[batch_index]]
        column_count <- min(options$columns, metadata$columns - column_start + 1L)
        rows_per_tile <- aww_memory_rows(max(1L, column_count), options)
        skip <- 0
        terminated <- c(dtaparser = NA_real_, haven = NA_real_)
        repeat {
            tile <- list(
                id = aww_tile_id(
                    "value", batch_index, skip, rows_per_tile,
                    column_start, column_count
                ), kind = "value",
                batch = as.integer(batch_index), column_start = as.integer(column_start),
                column_count = as.integer(column_count),
                storage = metadata$storage[seq.int(column_start, length.out = column_count)],
                skip = as.double(skip), n_max = rows_per_tile
            )
            leaves <- aww_execute_split(item, tile, options, package_library, package_path, run_dir, config_id)
            all_results <- c(all_results, leaves)
            bad <- vapply(leaves, function(result) !result$classification %in% c("pass", "dispute"), logical(1))
            if (any(bad)) {
                failed_result <- leaves[[which(bad)[[1L]]]]
                terminal_failure <- failed_result$classification
                break
            }
            reader_coverage <- lapply(c("dtaparser", "haven"), function(reader) {
                aww_leaf_reader_rows(leaves, tile, reader)
            })
            names(reader_coverage) <- c("dtaparser", "haven")
            reader_totals <- vapply(reader_coverage, `[[`, numeric(1), "rows")
            for (reader in names(reader_coverage)) {
                coverage <- reader_coverage[[reader]]
                if (!coverage$consistent) {
                    for (partition_rows in unique(coverage$partition_rows)) {
                        base$disputes <- aww_bind_disputes(list(
                            base$disputes,
                            aww_dispute(
                                "metadata", "dimension", reader = reader,
                                row = skip + 1, skip = skip, n_max = rows_per_tile,
                                attribute = "tile-nrow",
                                dtaparser = if (identical(reader, "dtaparser")) partition_rows else NULL,
                                haven = if (identical(reader, "haven")) partition_rows else NULL
                            )
                        ))
                    }
                }
            }
            termination <- aww_update_terminations(
                terminated, reader_totals, rows_per_tile, skip
            )
            terminated <- termination$counts
            newly_terminated <- termination$newly_terminated
            if (length(unique(reader_totals)) != 1L) {
                base$disputes <- aww_bind_disputes(list(
                    base$disputes,
                    aww_dispute("metadata", "dimension", row = skip + 1,
                                skip = skip, n_max = rows_per_tile,
                                attribute = "tile-nrow",
                                dtaparser = reader_totals[["dtaparser"]],
                                haven = reader_totals[["haven"]])
                ))
            }
            if (all(!is.na(terminated))) {
                observed_rows[[batch_index]] <- terminated
                break
            }
            if (any(newly_terminated) && any(is.na(terminated)) && is.na(trusted_rows)) {
                if (is.null(stata_info)) {
                    stata_info <- aww_stata_info(options, run_dir, aww_script_dir)
                }
                if (identical(stata_info$state, "available")) {
                    row_probe <- aww_stata_row_count(
                        item, metadata, options, run_dir, aww_script_dir,
                        stata_info, batch_index
                    )
                    trusted_rows <- row_probe$rows
                    if (identical(row_probe$state, "input-changed")) {
                        terminal_failure <- "input-changed"
                        break
                    }
                }
            }
            ceiling <- if (is.finite(trusted_rows)) trusted_rows else metadata$rows
            continuing <- aww_beyond_row_ceiling(terminated, skip, ceiling)
            if (length(continuing)) {
                for (reader in continuing) {
                    lower_bound <- skip + reader_totals[[reader]]
                    base$disputes <- aww_bind_disputes(list(
                        base$disputes,
                        aww_dispute(
                            "metadata", "dimension", reader = reader,
                            row = skip + 1, skip = skip, n_max = rows_per_tile,
                            attribute = "row-bound-exceeded",
                            dtaparser = if (identical(reader, "dtaparser")) lower_bound else NULL,
                            haven = if (identical(reader, "haven")) lower_bound else NULL
                        )
                    ))
                }
                observed_rows[[batch_index]] <- terminated
                break
            }
            skip <- skip + rows_per_tile
        }
        if (!is.null(terminal_failure)) break
    }
    if (length(observed_rows)) {
        observed <- do.call(rbind, observed_rows)
        for (reader in c("dtaparser", "haven")) {
            mismatches <- which(
                !is.na(observed[, reader]) & observed[, reader] != metadata$rows
            )
            if (length(mismatches)) for (batch_index in mismatches) {
                observed_value <- observed[batch_index, reader]
                base$disputes <- aww_bind_disputes(list(
                    base$disputes,
                    aww_dispute(
                        "metadata", "dimension", reader = reader,
                        attribute = "observed-row-count",
                        dtaparser = if (identical(reader, "dtaparser")) observed_value else NULL,
                        haven = if (identical(reader, "haven")) observed_value else NULL
                    )
                ))
                if (identical(reader, "dtaparser")) {
                    base$disputes <- aww_bind_disputes(list(
                        base$disputes,
                        aww_dispute(
                            "metadata", "dimension", reader = "dtaparser",
                            attribute = "declared-row-count",
                            dtaparser = metadata$rows
                        )
                    ))
                }
            }
        }
    }
    base$tiles <- base$tiles + length(all_results)
    base$resumed <- base$resumed + sum(vapply(all_results, function(result) isTRUE(result$resumed), logical(1)))
    base$disputes <- aww_bind_disputes(c(list(base$disputes), lapply(all_results, `[[`, "disputes")))
    if (!is.null(terminal_failure)) {
        if (terminal_failure %in% c("dtaparser-error", "haven-error", "shared-reader-error")) {
            base$disputes <- aww_bind_disputes(list(
                base$disputes,
                aww_dispute("reader_error", "reader-error",
                            row = failed_result$tile$skip + 1,
                            attribute = terminal_failure,
                            dtaparser = failed_result$reader_errors$dtaparser,
                            haven = failed_result$reader_errors$haven)
            ))
            probe <- aww_stata_open(item, options, run_dir, aww_script_dir)
            base$adjudication <- probe
            if (identical(probe, "open")) {
                base$ownership <- switch(terminal_failure,
                    "dtaparser-error" = "dtaparser-wrong",
                    "haven-error" = "haven-wrong",
                    "shared-reader-error" = "both-wrong"
                )
                base$status <- base$ownership
            } else if (identical(probe, "stata-source-error")) {
                base$ownership <- "source-corrupt"
                base$status <- "empty-or-corrupt"
            } else {
                base$ownership <- "unresolved"
                base$status <- "unresolved"
            }
        } else {
            base$status <- terminal_failure
        }
        return(finish(base))
    }
    current_hash <- tryCatch(aww_file_sha256(item$path), error = function(error) NA_character_)
    if (!identical(current_hash, item$sha256)) {
        base$status <- "input-changed"
        return(finish(base))
    }
    if (!nrow(base$disputes)) {
        base$status <- "match"
        return(finish(base))
    }
    if (is.null(stata_info)) {
        stata_info <- aww_stata_info(options, run_dir, aww_script_dir)
    }
    dispute_id <- aww_dispute_id(item$sha256, base$disputes)
    adjudication_path <- file.path(run_dir, "checkpoints", item$id, paste0("stata-", dispute_id, ".rds"))
    cached <- aww_read_result(adjudication_path)
    valid_cache <- !is.null(cached) && identical(cached$schema_version, aww_schema_version) &&
        identical(cached$file_sha256, item$sha256) && identical(cached$dispute_id, dispute_id) &&
        identical(cached$stata_id, stata_info$id) &&
        (!options$retry || identical(cached$result$state, "complete"))
    if (valid_cache) {
        adjudication <- cached$result
    } else {
        adjudication <- aww_adjudicate(
            base$disputes, metadata, item, options, run_dir, aww_script_dir, stata_info
        )
        aww_atomic_save_rds(list(
            schema_version = aww_schema_version, file_sha256 = item$sha256,
            dispute_id = dispute_id, stata_id = stata_info$id, result = adjudication
        ), adjudication_path)
    }
    base$adjudication <- adjudication$state
    base$ownership <- adjudication$ownership
    resolved <- unique(base$ownership[base$ownership != "unresolved"])
    base$status <- if (any(base$ownership == "unresolved")) "unresolved" else
        if (length(resolved) == 1L) resolved[[1L]] else "mixed"
    finish(base)
}

aww_write_results <- function(results, path) {
    frame <- if (length(results)) do.call(rbind, lapply(results, function(result) data.frame(
        id = result$id,
        relative_path = result$relative_path,
        release = result$release,
        rows = result$rows,
        columns = result$columns,
        status = result$status,
        tiles = result$tiles,
        resumed = result$resumed,
        disputes = nrow(result$disputes),
        dtaparser_wrong = sum(result$ownership == "dtaparser-wrong"),
        haven_wrong = sum(result$ownership == "haven-wrong"),
        both_wrong = sum(result$ownership == "both-wrong"),
        representation_only = sum(result$ownership == "representation-only"),
        unresolved = sum(result$ownership == "unresolved"),
        elapsed_seconds = result$elapsed_seconds,
        stringsAsFactors = FALSE
    ))) else data.frame(
        id = character(), relative_path = character(), release = integer(),
        rows = numeric(), columns = integer(), status = character(), tiles = integer(),
        resumed = integer(), disputes = integer(), dtaparser_wrong = integer(),
        haven_wrong = integer(), both_wrong = integer(), representation_only = integer(),
        unresolved = integer(), elapsed_seconds = numeric(), stringsAsFactors = FALSE
    )
    temporary <- tempfile(pattern = ".stage-", tmpdir = dirname(path))
    on.exit(unlink(temporary), add = TRUE)
    write.table(frame, temporary, sep = "\t", quote = TRUE, row.names = FALSE, na = "")
    Sys.chmod(temporary, "0600")
    if (!file.rename(temporary, path)) aww_abort("cannot publish results.tsv", 3L)
    frame
}

aww_report <- function(frame, inventory, options, config_id, build_id, haven_version, run_dir) {
    statuses <- sort(table(frame$status), decreasing = TRUE)
    lines <- c(
        "DTA corpus comparison",
        sprintf("Run: %s", config_id),
        sprintf("Root: %s", options$root),
        sprintf("Inventory: %s files; %.0f bytes", format(nrow(inventory), big.mark = ","), sum(inventory$size)),
        sprintf("Readers: dtaparser build %s; haven %s", substr(build_id, 1L, 12L), haven_version),
        sprintf("Coverage: %s files completed; %s tiles (%s resumed)", nrow(frame), sum(frame$tiles), sum(frame$resumed)),
        "",
        "File outcomes:"
    )
    for (name in names(statuses)) lines <- c(lines, sprintf("  %-24s %d", name, statuses[[name]]))
    lines <- c(lines,
        "",
        sprintf("Disputes: %d", sum(frame$disputes)),
        sprintf("  dtaparser wrong: %d", sum(frame$dtaparser_wrong)),
        sprintf("  haven wrong: %d", sum(frame$haven_wrong)),
        sprintf("  both wrong: %d", sum(frame$both_wrong)),
        sprintf("  representation only: %d", sum(frame$representation_only)),
        sprintf("  unresolved: %d", sum(frame$unresolved))
    )
    exceptional <- frame[frame$status != "match", , drop = FALSE]
    if (nrow(exceptional)) {
        shown <- utils::head(exceptional, 20L)
        lines <- c(lines, "", sprintf(
            "Non-matching files (showing %d of %d):", nrow(shown), nrow(exceptional)
        ))
        lines <- c(lines, vapply(seq_len(nrow(shown)), function(index) sprintf(
            "  %s — %s (%d disputes)", shown$relative_path[[index]],
            shown$status[[index]], shown$disputes[[index]]
        ), character(1)))
        if (nrow(exceptional) > nrow(shown)) {
            lines <- c(lines, sprintf(
                "  … %d additional files are listed only in results.tsv",
                nrow(exceptional) - nrow(shown)
            ))
        }
    }
    c(lines, "", sprintf("Details: %s", file.path(run_dir, "results.tsv")))
}

main <- function() {
    options <- aww_parse_arguments(commandArgs(TRUE))
    required <- c("callr", "fs", "haven", "openssl", "processx", "tidyselect")
    missing <- required[!vapply(required, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
    if (length(missing)) aww_abort(sprintf("missing R packages: %s", paste(missing, collapse = ", ")))
    package_library <- normalizePath(Sys.getenv("AWW_PACKAGE_LIBRARY"), winslash = "/", mustWork = TRUE)
    package_path <- normalizePath(Sys.getenv("AWW_PACKAGE_PATH"), winslash = "/", mustWork = TRUE)
    build_id <- Sys.getenv("AWW_BUILD_ID")
    haven_version <- as.character(utils::packageVersion("haven"))
    config_id <- aww_config_id(options, build_id, haven_version)
    run_dir <- file.path(options$state, "runs", config_id)
    dir.create(run_dir, recursive = TRUE, showWarnings = FALSE, mode = "0700")
    aww_atomic_save_rds(list(
        schema_version = aww_schema_version, config_id = config_id,
        options = options, build_id = build_id, haven_version = haven_version
    ), file.path(run_dir, "config.rds"))
    inventory <- aww_inventory(options$root)
    aww_atomic_save_rds(inventory, file.path(run_dir, "inventory.rds"))
    if (options$inventory_only) {
        report <- c(
            "DTA corpus inventory",
            sprintf("Root: %s", options$root),
            sprintf("Files: %s", format(nrow(inventory), big.mark = ",")),
            sprintf("Bytes: %.0f", sum(inventory$size)),
            sprintf("Inventory: %s", file.path(run_dir, "inventory.rds"))
        )
        aww_atomic_write(report, file.path(run_dir, "report.txt"))
        writeLines(report)
        return(invisible(0L))
    }
    selected <- aww_select_inventory(inventory, options)
    results <- vector("list", nrow(selected))
    for (index in seq_len(nrow(selected))) {
        item <- as.list(selected[index, , drop = FALSE])
        message(sprintf("[%d/%d] %s", index, nrow(selected), item$relative_path))
        results[[index]] <- aww_file(item, options, package_library, package_path, run_dir, config_id)
        aww_atomic_save_rds(list(
            schema_version = aww_schema_version, config_id = config_id,
            file_sha256 = item$sha256, result = results[[index]]
        ), file.path(run_dir, "checkpoints", item$id, "file-result.rds"))
    }
    frame <- aww_write_results(results, file.path(run_dir, "results.tsv"))
    report <- aww_report(frame, inventory, options, config_id, build_id, haven_version, run_dir)
    aww_atomic_write(report, file.path(run_dir, "report.txt"))
    writeLines(report)
    incomplete <- any(frame$status %in% c(
        "unresolved", "unreadable", "empty-or-corrupt", "unsupported-release",
        "dtaparser-error", "haven-error", "shared-reader-error", "timeout",
        "worker-crash", "memory-limit", "input-changed", "row-termination-mismatch"
    ))
    invisible(if (incomplete) 1L else 0L)
}

if (!identical(Sys.getenv("AWW_SOURCE_ONLY", unset = ""), "1")) {
    status <- tryCatch(main(), aww_error = function(error) {
        message(error$message)
        error$status
    }, error = function(error) {
        message(conditionMessage(error))
        3L
    })
    quit(status = status)
}
