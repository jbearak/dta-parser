fertility_usage <- function() {
    paste(
        "usage: run.R [--inventory-only] [--program=a,b] [--release=113,118]",
        "[--id=F0001,F0002] [--shard-index=N --shard-count=N] [--max-files=N]",
        "[--timeout-seconds=N] [--chunk-rows=N] [--column-batch=N]",
        "[--memory-mib=N] [--cell-budget=N] [--max-tiles-per-batch=N]",
        "[--beyond-end-windows=N] [--retry]"
    )
}

fertility_parse_positive_integer <- function(value, option) {
    if (!grepl("^[1-9][0-9]*$", value)) stop(option, " must be a positive integer")
    number <- as.double(value)
    if (!is.finite(number) || number > .Machine$integer.max) stop(option, " is too large")
    as.integer(number)
}

fertility_parse_arguments <- function(arguments) {
    options <- list(
        inventory_only = FALSE, programs = character(), releases = integer(),
        ids = character(), shard_index = 1L, shard_count = 1L,
        max_files = Inf, timeout_seconds = 600L, chunk_rows = 10000L,
        column_batch = 16L, memory_mib = 256L, cell_budget = 1000000L,
        max_tiles_per_batch = 100000L, beyond_end_windows = 1L,
        retry = FALSE
    )
    seen_shard_index <- seen_shard_count <- FALSE
    for (argument in arguments) {
        if (identical(argument, "--inventory-only")) options$inventory_only <- TRUE
        else if (identical(argument, "--retry")) options$retry <- TRUE
        else if (startsWith(argument, "--program=")) {
            options$programs <- unique(strsplit(tolower(sub("^[^=]+=", "", argument)),
                                                ",", fixed = TRUE)[[1L]])
        } else if (startsWith(argument, "--release=")) {
            values <- strsplit(sub("^[^=]+=", "", argument), ",", fixed = TRUE)[[1L]]
            if (any(!grepl("^[0-9]+$", values))) stop("--release values must be integers")
            options$releases <- unique(as.integer(values))
        } else if (startsWith(argument, "--id=")) {
            options$ids <- unique(strsplit(sub("^[^=]+=", "", argument),
                                           ",", fixed = TRUE)[[1L]])
            if (any(!grepl("^F[0-9]{4}$", options$ids))) stop("invalid --id value")
        } else if (startsWith(argument, "--shard-index=")) {
            options$shard_index <- fertility_parse_positive_integer(
                sub("^[^=]+=", "", argument), "--shard-index"
            )
            seen_shard_index <- TRUE
        } else if (startsWith(argument, "--shard-count=")) {
            options$shard_count <- fertility_parse_positive_integer(
                sub("^[^=]+=", "", argument), "--shard-count"
            )
            seen_shard_count <- TRUE
        } else if (startsWith(argument, "--max-files=")) {
            options$max_files <- fertility_parse_positive_integer(
                sub("^[^=]+=", "", argument), "--max-files"
            )
        } else if (startsWith(argument, "--timeout-seconds=")) {
            options$timeout_seconds <- fertility_parse_positive_integer(
                sub("^[^=]+=", "", argument), "--timeout-seconds"
            )
        } else if (startsWith(argument, "--chunk-rows=")) {
            options$chunk_rows <- fertility_parse_positive_integer(
                sub("^[^=]+=", "", argument), "--chunk-rows"
            )
        } else if (startsWith(argument, "--column-batch=")) {
            options$column_batch <- fertility_parse_positive_integer(
                sub("^[^=]+=", "", argument), "--column-batch"
            )
        } else if (startsWith(argument, "--memory-mib=")) {
            options$memory_mib <- fertility_parse_positive_integer(
                sub("^[^=]+=", "", argument), "--memory-mib"
            )
        } else if (startsWith(argument, "--cell-budget=")) {
            options$cell_budget <- fertility_parse_positive_integer(
                sub("^[^=]+=", "", argument), "--cell-budget"
            )
        } else if (startsWith(argument, "--max-tiles-per-batch=")) {
            options$max_tiles_per_batch <- fertility_parse_positive_integer(
                sub("^[^=]+=", "", argument), "--max-tiles-per-batch"
            )
        } else if (startsWith(argument, "--beyond-end-windows=")) {
            options$beyond_end_windows <- fertility_parse_positive_integer(
                sub("^[^=]+=", "", argument), "--beyond-end-windows"
            )
        } else stop(fertility_usage())
    }
    if (xor(seen_shard_index, seen_shard_count)) {
        stop("--shard-index and --shard-count must be supplied together")
    }
    if (options$shard_index > options$shard_count) {
        stop("--shard-index must not exceed --shard-count")
    }
    if (options$memory_mib < 128L) {
        stop("--memory-mib must be at least 128 for an enforceable R vector limit")
    }
    if (options$beyond_end_windows > 8L) {
        stop("--beyond-end-windows must not exceed 8")
    }
    options
}

fertility_filter_inventory <- function(inventory, options) {
    selected <- inventory
    if (length(options$programs)) {
        if (length(setdiff(options$programs, unique(inventory$program)))) {
            stop("unknown --program value")
        }
        selected <- selected[selected$program %in% options$programs, , drop = FALSE]
    }
    if (length(options$releases)) {
        if (length(setdiff(options$releases, unique(inventory$release)))) {
            stop("unknown --release value")
        }
        selected <- selected[selected$release %in% options$releases, , drop = FALSE]
    }
    if (length(options$ids)) {
        if (length(setdiff(options$ids, inventory$id))) stop("unknown --id value")
        selected <- selected[selected$id %in% options$ids, , drop = FALSE]
    }
    positions <- match(selected$id, inventory$id)
    selected <- selected[((positions - 1L) %% options$shard_count) + 1L ==
                             options$shard_index, , drop = FALSE]
    if (is.finite(options$max_files) && nrow(selected) > options$max_files) {
        selected <- selected[seq_len(options$max_files), , drop = FALSE]
    }
    selected
}

fertility_capture_input <- function(item) {
    info <- file.info(item$path)
    if (!nrow(info) || is.na(info$size[[1L]])) {
        size <- NA_character_
        modified <- NA_character_
    } else {
        size <- as.character(info$size[[1L]])
        modified <- format(info$mtime[[1L]], "%Y-%m-%dT%H:%M:%OS6Z", tz = "UTC")
    }
    actual <- tryCatch(suppressWarnings(fertility_file_sha512(item$path)),
                       error = function(error) NA_character_)
    hash_status <- if (is.na(actual)) "error" else "ok"
    identity <- fertility_stable_id(list(
        id = item$id, release = as.integer(item$release),
        expected_sha512 = item$expected_sha512, hash_status = hash_status,
        actual_sha512 = if (is.na(actual)) "" else actual,
        size = size, modified = modified
    ))
    list(input_id = identity, hash_status = hash_status,
         actual_sha512 = actual, size = size, modified = modified)
}

fertility_inventory_preflight <- function(item, input) {
    if (identical(input$hash_status, "error")) {
        return(list(classification = "inventory-hash-error",
                    reason = "hash-read-error"))
    }
    if (nzchar(item$expected_sha512) &&
        !identical(input$actual_sha512, tolower(item$expected_sha512))) {
        return(list(classification = "inventory-hash-error",
                    reason = "signature-mismatch"))
    }
    NULL
}

fertility_file_stat <- function(path) {
    info <- file.info(path)
    if (!nrow(info) || is.na(info$size[[1L]]) || is.na(info$mtime[[1L]])) return(NULL)
    list(size = as.character(info$size[[1L]]),
         modified = format(info$mtime[[1L]], "%Y-%m-%dT%H:%M:%OS6Z", tz = "UTC"))
}

fertility_checkpoint_valid <- function(checkpoint, item, framework_id,
                                       input = NULL, timeout_seconds = NULL) {
    valid <- is.list(checkpoint) &&
        identical(checkpoint$schema_version, fertility_schema_version) &&
        identical(checkpoint$framework_id, framework_id) &&
        identical(checkpoint$id, item$id) &&
        identical(checkpoint$expected_sha512, item$expected_sha512) &&
        identical(as.integer(checkpoint$release), as.integer(item$release)) &&
        !is.null(checkpoint$input_id) && !is.null(checkpoint$timeout_seconds)
    if (valid && !is.null(timeout_seconds)) {
        valid <- identical(as.integer(checkpoint$timeout_seconds),
                           as.integer(timeout_seconds))
    }
    if (!valid || is.null(input)) return(valid)
    identical(checkpoint$input_id, input$input_id)
}

fertility_checkpoint_input_current <- function(checkpoint, item) {
    fertility_checkpoint_valid(
        checkpoint, item, checkpoint$framework_id, fertility_capture_input(item),
        checkpoint$timeout_seconds
    )
}

fertility_base_result <- function(item, framework_id, timeout_seconds, input,
                                  classification, elapsed_seconds = NA_real_) {
    list(
        schema_version = fertility_schema_version,
        framework_id = framework_id, input_id = input$input_id,
        id = item$id, program = item$program, level = item$level,
        release = as.integer(item$release), expected_sha512 = item$expected_sha512,
        timeout_seconds = timeout_seconds, classification = classification,
        component = NA_integer_, rows = NA_real_, columns = NA_integer_,
        actual_sha512 = input$actual_sha512, elapsed_seconds = elapsed_seconds
    )
}

fertility_process_item <- function(item, checkpoint_path, framework_id,
                                   timeout_seconds, retry, execute) {
    input_before <- fertility_capture_input(item)
    checkpoint <- if (file.exists(checkpoint_path)) tryCatch(
        readRDS(checkpoint_path), error = function(error) NULL
    ) else NULL
    if (!is.null(checkpoint) &&
        fertility_checkpoint_valid(
            checkpoint, item, framework_id, input_before, timeout_seconds
        ) &&
        (!retry || !fertility_should_retry(checkpoint))) {
        return(list(result = checkpoint, resumed = TRUE))
    }
    if (identical(input_before$hash_status, "error")) {
        result <- fertility_base_result(
            item, framework_id, timeout_seconds, input_before, "input-hash-error"
        )
    } else if (nzchar(item$expected_sha512) &&
               !identical(input_before$actual_sha512,
                          tolower(item$expected_sha512))) {
        result <- fertility_base_result(
            item, framework_id, timeout_seconds, input_before,
            "input-signature-mismatch"
        )
    } else {
        result <- execute(item, input_before)
        input_after <- fertility_capture_input(item)
        if (!identical(input_after$input_id, input_before$input_id)) {
            result <- fertility_base_result(
                item, framework_id, timeout_seconds, input_after,
                "input-changed-during-subprocess"
            )
        } else {
            result$input_id <- input_before$input_id
            result$actual_sha512 <- input_before$actual_sha512
        }
    }
    fertility_atomic_save_rds(result, checkpoint_path)
    list(result = result, resumed = FALSE)
}

fertility_should_retry <- function(checkpoint) {
    !(checkpoint$classification %in% c("match", "unsupported-release"))
}

fertility_result_frame <- function(checkpoints) {
    fields <- c(
        "framework_id", "id", "program", "level", "release", "classification",
        "secondary_categories", "mismatch_count", "mismatch_categories",
        "mismatch_signatures", "rows", "columns", "tiles_expected",
        "tiles_completed", "complete", "elapsed_seconds"
    )
    rows <- lapply(checkpoints, function(value) {
        row <- setNames(lapply(fields, function(field) {
            if (is.null(value[[field]])) NA else value[[field]]
        }), fields)
        as.data.frame(row, stringsAsFactors = FALSE, optional = TRUE)
    })
    result <- do.call(rbind, rows)
    rownames(result) <- NULL
    result
}

fertility_publish_results <- function(checkpoints, build_provenance_id, path) {
    results <- fertility_result_frame(checkpoints)
    results$build_provenance_id <- build_provenance_id
    fertility_atomic_write_table(results, path)
    results
}

fertility_tile_configuration <- function(options) {
    fields <- list(
        chunk_rows = options$chunk_rows, column_batch = options$column_batch,
        memory_mib = options$memory_mib, cell_budget = options$cell_budget,
        max_tiles_per_batch = options$max_tiles_per_batch,
        beyond_end_windows = options$beyond_end_windows,
        timeout_seconds = options$timeout_seconds, object_overhead_bytes = 64L,
        readers_per_tile = 3L
    )
    c(fields, list(config_id = fertility_stable_id(fields)))
}

fertility_adaptive_rows <- function(column_bytes, configuration) {
    column_bytes <- as.double(column_bytes)
    if (!length(column_bytes)) column_bytes <- 8
    if (any(!is.finite(column_bytes))) return(1L)
    per_row <- sum(pmax(column_bytes, 1) + configuration$object_overhead_bytes)
    readers <- as.double(configuration$readers_per_tile)
    memory_bytes <- as.double(configuration$memory_mib) * 1024^2
    by_memory <- floor(memory_bytes / (readers * per_row))
    by_cells <- floor(as.double(configuration$cell_budget) /
                      (readers * length(column_bytes)))
    as.integer(max(1, min(configuration$chunk_rows, by_memory, by_cells)))
}

fertility_metadata_tile <- function() {
    list(tile_id = "metadata", type = "metadata", batch = 0L, skip = 0L,
         n_max = 0L, column_names = character(), column_hash = "all")
}

fertility_value_tile <- function(batch, skip, n_max, column_names,
                                 type = "value", probe = 0L) {
    list(
        tile_id = sprintf("b%05d-%s%02d-r%015.0f", as.integer(batch),
                          if (identical(type, "value")) "v" else "p",
                          as.integer(probe), as.double(skip)),
        type = type, batch = as.integer(batch), skip = as.double(skip),
        n_max = as.integer(n_max), column_names = column_names,
        column_hash = fertility_stable_id(list(
            batch = as.integer(batch), type = type, probe = as.integer(probe),
            names = paste(column_names, collapse = "\037")
        ))
    )
}

fertility_column_batches <- function(column_names, batch_size, column_bytes = NULL) {
    if (!length(column_names)) return(list())
    if (is.null(column_bytes) || length(column_bytes) != length(column_names)) {
        column_bytes <- rep(8, length(column_names))
    }
    batches <- list()
    current <- character()
    for (i in seq_along(column_names)) {
        strl <- !is.finite(column_bytes[[i]])
        if (length(current) && (length(current) >= batch_size || strl)) {
            batches[[length(batches) + 1L]] <- current
            current <- character()
        }
        current <- c(current, column_names[[i]])
        if (strl) {
            batches[[length(batches) + 1L]] <- current
            current <- character()
        }
    }
    if (length(current)) batches[[length(batches) + 1L]] <- current
    batches
}

fertility_structural_batches <- function(column_names, batch_size, column_bytes,
                                         declared_columns) {
    if (identical(as.integer(declared_columns), 0L) && !length(column_names)) {
        return(list(character()))
    }
    fertility_column_batches(column_names, batch_size, column_bytes)
}

fertility_batch_bytes <- function(column_names, all_names, column_bytes) {
    column_bytes[match(column_names, all_names)]
}

fertility_projection_hash <- function(column_names, framework_id) {
    fertility_stable_id(list(
        framework_id = framework_id,
        ordered_names = paste(column_names, collapse = "\037")
    ))
}

fertility_plan_offsets <- function(total_rows, rows_per_tile, max_tiles) {
    if (!is.finite(total_rows) || total_rows < 0) {
        return(list(offsets = numeric(), ceiling = TRUE))
    }
    needed <- if (total_rows == 0) 1 else ceiling(total_rows / rows_per_tile)
    if (needed > max_tiles) return(list(offsets = numeric(), ceiling = TRUE))
    list(offsets = if (total_rows == 0) 0 else
             seq(0, total_rows - 1, by = rows_per_tile), ceiling = FALSE)
}

fertility_memory_error <- function(error) {
    grepl("vector memory exhausted|cannot allocate|memory limit|out of memory",
          conditionMessage(error), ignore.case = TRUE)
}

fertility_tile_checkpoint_valid <- function(checkpoint, item, tile, framework_id,
                                              config_id, input_id,
                                              timeout_seconds) {
    is.list(checkpoint) &&
        identical(checkpoint$schema_version, fertility_schema_version) &&
        identical(checkpoint$framework_id, framework_id) &&
        identical(checkpoint$config_id, config_id) &&
        identical(checkpoint$input_id, input_id) &&
        identical(checkpoint$id, item$id) &&
        identical(checkpoint$tile_id, tile$tile_id) &&
        identical(checkpoint$tile_type, tile$type) &&
        identical(as.integer(checkpoint$batch), as.integer(tile$batch)) &&
        identical(as.double(checkpoint$skip), as.double(tile$skip)) &&
        identical(as.integer(checkpoint$n_max), as.integer(tile$n_max)) &&
        identical(checkpoint$column_hash, tile$column_hash) &&
        identical(as.integer(checkpoint$timeout_seconds), as.integer(timeout_seconds))
}

fertility_tile_should_retry <- function(checkpoint) {
    checkpoint$classification %in% c(
        "timeout", "crash", "dtaparser-only-error", "haven-only-error",
        "shared-reader-error", "memory-limit", "unresolved"
    )
}

fertility_process_tile <- function(item, tile, checkpoint_path, framework_id,
                                   configuration, input, retry, execute) {
    checkpoint <- if (file.exists(checkpoint_path)) tryCatch(
        readRDS(checkpoint_path), error = function(error) NULL
    ) else NULL
    valid <- !is.null(checkpoint) && fertility_tile_checkpoint_valid(
        checkpoint, item, tile, framework_id, configuration$config_id,
        input$input_id, configuration$timeout_seconds
    )
    if (valid && (!retry || !fertility_tile_should_retry(checkpoint))) {
        return(list(result = checkpoint, resumed = TRUE))
    }
    result <- execute(item, tile, input)
    result$config_id <- configuration$config_id
    result$input_id <- input$input_id
    result$column_hash <- tile$column_hash
    result$timeout_seconds <- configuration$timeout_seconds
    fertility_atomic_save_rds(result, checkpoint_path)
    list(result = result, resumed = FALSE)
}

fertility_mismatch_summary <- function(tiles) {
    mismatches <- lapply(tiles, function(tile) tile$mismatches)
    mismatches <- mismatches[vapply(
        mismatches, function(value) is.data.frame(value) && nrow(value) > 0L,
        logical(1)
    )]
    if (!length(mismatches)) return(list(count = 0L, categories = "", signatures = ""))
    mismatches <- do.call(rbind, mismatches)
    if (!nrow(mismatches)) return(list(count = 0L, categories = "", signatures = ""))
    keys <- paste(mismatches$category, mismatches$detail,
                  ifelse(is.na(mismatches$component), "", mismatches$component),
                  if ("pair" %in% names(mismatches)) mismatches$pair else "",
                  sep = ":")
    counts <- sort(table(keys), decreasing = TRUE)
    categories <- sort(table(mismatches$category), decreasing = TRUE)
    list(
        count = as.integer(sum(counts)),
        categories = paste(names(categories), as.integer(categories), sep = "=",
                           collapse = ","),
        signatures = paste(vapply(names(counts), function(key) {
            fertility_stable_id(list(signature = key))
        }, character(1)), as.integer(counts), sep = "=", collapse = ",")
    )
}

fertility_aggregate_classification <- function(tiles, complete) {
    classes <- vapply(tiles, `[[`, character(1), "classification")
    secondary <- unique(unlist(lapply(tiles, `[[`, "secondary"), use.names = FALSE))
    if (any(classes == "input-changed")) return("inventory-hash-error")
    if (any(classes == "timeout")) return("timeout")
    if (any(classes == "memory-limit")) return("memory-limit")
    if (any(classes == "crash")) return("crash")
    for (classification in c("shared-reader-error", "dtaparser-only-error",
                             "haven-only-error")) {
        if (classification %in% classes) return(classification)
    }
    if (any(classes == "unresolved")) return("unresolved")
    if ("row-termination-mismatch" %in% c(classes, secondary)) {
        return("row-termination-mismatch")
    }
    if ("direct-vs-rust-mismatch" %in% c(classes, secondary)) {
        return("direct-vs-rust-mismatch")
    }
    for (classification in c("metadata-mismatch", "tag-mismatch", "date-mismatch",
                             "encoding-mismatch", "value-mismatch",
                             "known-intentional-divergence")) {
        if (classification %in% c(classes, secondary)) return(classification)
    }
    if (!complete) "unresolved" else "pass"
}

fertility_validate_tile_completeness <- function(tiles, batches, total_rows,
                                                 configuration) {
    if (!length(tiles) || !identical(tiles[[1L]]$tile_type, "metadata")) return(FALSE)
    if (is.na(total_rows) || !length(batches) ||
        is.null(configuration$beyond_end_windows)) return(FALSE)
    terminal_tiles <- tiles[vapply(
        tiles, function(tile) identical(tile$tile_type, "terminal"), logical(1)
    )]
    expected_probes <- as.integer(configuration$beyond_end_windows)
    if (length(terminal_tiles) != expected_probes) return(FALSE)
    terminal_tiles <- terminal_tiles[order(vapply(
        terminal_tiles, `[[`, numeric(1), "skip"
    ))]
    expected_terminal_skips <- as.double(total_rows) + seq.int(0, expected_probes - 1L)
    expected_count <- length(batches[[1L]])
    readers <- c("direct", "rust", "haven")
    for (probe in seq_len(expected_probes)) {
        tile <- terminal_tiles[[probe]]
        expected_hash <- if (!is.null(tile$framework_id))
            fertility_projection_hash(batches[[1L]], tile$framework_id) else
            NA_character_
        attested <- identical(as.integer(tile$batch), 1L) &&
            identical(as.double(tile$skip), expected_terminal_skips[[probe]]) &&
            identical(as.integer(tile$n_max), 1L) &&
            identical(as.integer(tile$rows), 0L) &&
            identical(names(tile$reader_rows), readers) &&
            all(tile$reader_rows == 0L) &&
            identical(as.integer(tile$projection_expected_count),
                      as.integer(expected_count)) &&
            identical(tile$projection_expected_hash, expected_hash) &&
            identical(names(tile$projection_counts), readers) &&
            identical(names(tile$projection_hashes), readers) &&
            identical(names(tile$projection_ok), readers) &&
            all(tile$projection_ok) &&
            all(tile$projection_counts == expected_count) &&
            all(tile$projection_hashes == expected_hash)
        if (!isTRUE(attested)) return(FALSE)
    }
    value_tiles <- tiles[vapply(tiles, function(tile) identical(tile$tile_type, "value"),
                                logical(1))]
    if (length(batches) != length(unique(vapply(value_tiles, `[[`, integer(1), "batch")))) {
        return(FALSE)
    }
    for (batch in seq_along(batches)) {
        current <- value_tiles[vapply(value_tiles, function(tile) tile$batch == batch,
                                      logical(1))]
        current <- current[order(vapply(current, `[[`, numeric(1), "skip"))]
        expected_skip <- 0
        expected_count <- length(batches[[batch]])
        for (tile in current) {
            expected_hash <- if (!is.null(tile$framework_id))
                fertility_projection_hash(batches[[batch]], tile$framework_id) else
                NA_character_
            readers <- c("direct", "rust", "haven")
            attested <- identical(as.integer(tile$projection_expected_count),
                                  as.integer(expected_count)) &&
                is.character(tile$projection_expected_hash) &&
                length(tile$projection_expected_hash) == 1L &&
                !is.na(expected_hash) &&
                identical(tile$projection_expected_hash, expected_hash) &&
                identical(names(tile$projection_counts), readers) &&
                identical(names(tile$projection_hashes), readers) &&
                identical(names(tile$projection_ok), readers) &&
                all(tile$projection_ok) &&
                all(tile$projection_counts == expected_count) &&
                all(tile$projection_hashes == expected_hash)
            if (!isTRUE(attested) ||
                !identical(as.double(tile$skip), as.double(expected_skip)) ||
                is.na(tile$rows)) return(FALSE)
            expected_rows <- min(tile$n_max, total_rows - expected_skip)
            if (!identical(as.integer(tile$rows), as.integer(expected_rows))) return(FALSE)
            expected_skip <- expected_skip + tile$rows
        }
        if (!identical(as.double(expected_skip), as.double(total_rows))) return(FALSE)
    }
    TRUE
}

fertility_file_result_valid <- function(result, item, framework_id,
                                         configuration, input) {
    is.list(result) &&
        identical(result$schema_version, fertility_schema_version) &&
        identical(result$framework_id, framework_id) &&
        identical(result$config_id, configuration$config_id) &&
        identical(result$input_id, input$input_id) &&
        identical(result$id, item$id) &&
        identical(as.integer(result$release), as.integer(item$release)) &&
        identical(as.integer(result$timeout_seconds),
                  as.integer(configuration$timeout_seconds))
}

fertility_tiled_result <- function(item, framework_id, configuration, input, tiles,
                                    batches, total_rows) {
    complete <- fertility_validate_tile_completeness(
        tiles, batches, total_rows, configuration
    )
    mismatch <- fertility_mismatch_summary(tiles)
    secondary <- sort(unique(c(
        unlist(lapply(tiles, `[[`, "secondary"), use.names = FALSE),
        unlist(lapply(tiles, function(tile) {
            if (is.data.frame(tile$mismatches)) tile$mismatches$category else character()
        }), use.names = FALSE)
    )))
    list(
        schema_version = fertility_schema_version, framework_id = framework_id,
        config_id = configuration$config_id, input_id = input$input_id,
        id = item$id, program = item$program, level = item$level,
        release = as.integer(item$release), expected_sha512 = item$expected_sha512,
        timeout_seconds = configuration$timeout_seconds,
        classification = fertility_aggregate_classification(tiles, complete),
        secondary_categories = paste(secondary, collapse = ","),
        mismatch_count = mismatch$count, mismatch_categories = mismatch$categories,
        mismatch_signatures = mismatch$signatures,
        rows = as.double(total_rows), columns = length(unlist(batches)),
        tiles_expected = length(tiles), tiles_completed = length(tiles),
        complete = complete, actual_sha512 = input$actual_sha512,
        elapsed_seconds = sum(vapply(tiles, function(tile) tile$elapsed_seconds,
                                     numeric(1)), na.rm = TRUE)
    )
}
