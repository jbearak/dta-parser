fertility_memory_error <- function(error) {
    grepl("vector memory exhausted|cannot allocate|memory limit|out of memory",
          conditionMessage(error), ignore.case = TRUE)
}

fertility_worker_base <- function(item, framework_id, timeout_seconds) {
    list(
        schema_version = fertility_schema_version, framework_id = framework_id,
        id = item$id, program = item$program, level = item$level,
        release = as.integer(item$release), expected_sha512 = item$expected_sha512,
        timeout_seconds = timeout_seconds
    )
}

fertility_load_readers <- function(package_library, expected_package_path) {
    .libPaths(c(package_library, .libPaths()))
    if (!requireNamespace("dtaparser", quietly = TRUE)) stop("dtaparser-load-error")
    loaded <- normalizePath(getNamespaceInfo(asNamespace("dtaparser"), "path"),
                            winslash = "/", mustWork = TRUE)
    if (!identical(loaded, expected_package_path)) stop("foreign-dtaparser-installation")
    if (!requireNamespace("haven", quietly = TRUE)) stop("haven-load-error")
    invisible(NULL)
}

fertility_worker_encoding <- function(item) {
    encoding <- item$encoding_override
    if (is.null(encoding)) return(NULL)
    allowed <- c("UTF-8", "Windows-1252", "ISO-8859-1")
    if (!is.character(encoding) || length(encoding) != 1L ||
        is.na(encoding) || !encoding %in% allowed) {
        stop("invalid-encoding-override")
    }
    encoding
}

fertility_tile_read <- function(reader, path, tile, encoding = NULL) {
    if (!is.finite(tile$n_max) || tile$n_max < 0L) stop("tile row bound is invalid")
    if (identical(tile$type, "metadata")) {
        frame <- if (identical(reader, "direct")) {
            dtaparser::read_dta(
                path, encoding = encoding, n_max = 0L, .name_repair = "minimal"
            )
        } else if (identical(reader, "rust")) {
            dtaparser:::.read_dta_rust_vectors(
                path, encoding = encoding, n_max = 0L, .name_repair = "minimal"
            )
        } else {
            haven::read_dta(
                path, encoding = encoding, n_max = 0L, .name_repair = "minimal"
            )
        }
        shape <- if (identical(reader, "direct")) {
            dtaparser::read_dta(
                path, encoding = encoding, col_select = character(),
                .name_repair = "minimal"
            )
        } else if (identical(reader, "rust")) {
            dtaparser:::.read_dta_rust_vectors(
                path, encoding = encoding, col_select = character(),
                .name_repair = "minimal"
            )
        } else {
            NULL
        }
        return(list(
            frame = frame,
            shape_rows = if (is.null(shape)) NA_integer_ else nrow(shape),
            shape_columns = if (is.null(shape)) 0L else ncol(shape)
        ))
    }
    columns <- tile$column_names
    if (!length(columns)) {
        if (identical(reader, "direct")) {
            return(dtaparser::read_dta(
                path, encoding = encoding, skip = tile$skip, n_max = tile$n_max,
                .name_repair = "minimal"
            ))
        }
        if (identical(reader, "rust")) {
            return(dtaparser:::.read_dta_rust_vectors(
                path, encoding = encoding, skip = tile$skip, n_max = tile$n_max,
                .name_repair = "minimal"
            ))
        }
        return(haven::read_dta(
            path, encoding = encoding, skip = tile$skip, n_max = tile$n_max,
            .name_repair = "minimal"
        ))
    }
    if (identical(reader, "direct")) {
        dtaparser::read_dta(
            path, encoding = encoding, col_select = tidyselect::all_of(columns),
            skip = tile$skip, n_max = tile$n_max, .name_repair = "minimal"
        )
    } else if (identical(reader, "rust")) {
        dtaparser:::.read_dta_rust_vectors(
            path, encoding = encoding, col_select = tidyselect::all_of(columns),
            skip = tile$skip, n_max = tile$n_max, .name_repair = "minimal"
        )
    } else {
        haven::read_dta(
            path, encoding = encoding, col_select = tidyselect::all_of(columns),
            skip = tile$skip, n_max = tile$n_max, .name_repair = "minimal"
        )
    }
}

fertility_compare_available_pairs <- function(frames, errors) {
    mismatches <- fertility_bind_mismatches(list())
    secondary <- character()
    pairs <- list(
        list(left = "direct", right = "rust", id = "direct-rust", internal = TRUE),
        list(left = "direct", right = "haven", id = "direct-haven", internal = FALSE),
        list(left = "rust", right = "haven", id = "rust-haven", internal = FALSE)
    )
    for (pair in pairs) {
        if (errors[[pair$left]] || errors[[pair$right]]) next
        compared <- if (pair$internal) {
            fertility_compare_internal(frames[[pair$left]], frames[[pair$right]])
        } else {
            fertility_compare_haven(frames[[pair$left]], frames[[pair$right]])
        }
        current <- compared$mismatches
        if (!nrow(current)) next
        current$pair <- pair$id
        mismatches <- fertility_bind_mismatches(list(mismatches, current))
        if (pair$internal) secondary <- c(secondary, "direct-vs-rust-mismatch")
        secondary <- c(secondary, current$category)
    }
    list(mismatches = mismatches, secondary = sort(unique(secondary)))
}

fertility_projection_hash <- function(column_names, framework_id) {
    fertility_stable_id(list(
        framework_id = framework_id,
        ordered_names = paste(column_names, collapse = "\037")
    ))
}

fertility_projection_attestation <- function(frames, errors, expected_names,
                                             framework_id) {
    readers <- names(errors)
    expected_count <- length(expected_names)
    expected_hash <- fertility_projection_hash(expected_names, framework_id)
    counts <- setNames(rep(NA_integer_, length(readers)), readers)
    hashes <- setNames(rep(NA_character_, length(readers)), readers)
    ok <- setNames(rep(FALSE, length(readers)), readers)
    for (reader in readers[!errors]) {
        returned <- names(frames[[reader]])
        counts[[reader]] <- length(returned)
        hashes[[reader]] <- fertility_projection_hash(returned, framework_id)
        ok[[reader]] <- identical(returned, expected_names)
    }
    list(expected_count = expected_count, expected_hash = expected_hash,
         counts = counts, hashes = hashes, ok = ok)
}

fertility_row_termination_mismatch <- function(reader_rows) {
    any(reader_rows > 0L, na.rm = TRUE)
}

fertility_structural_shape_mismatch <- function(shape_rows, expected_rows,
                                                actual_columns, expected_columns) {
    known <- shape_rows[!is.na(shape_rows)]
    (length(known) > 1L && length(unique(known)) != 1L) ||
        (length(known) && is.finite(expected_rows) && any(known != expected_rows)) ||
        (is.finite(expected_columns) && !is.na(actual_columns) &&
         actual_columns != expected_columns)
}

fertility_reader_error_classification <- function(errors) {
    dta_error <- errors[["direct"]] || errors[["rust"]]
    haven_error <- errors[["haven"]]
    if (dta_error && haven_error) "shared-reader-error" else
        if (dta_error) "dtaparser-only-error" else
        if (haven_error) "haven-only-error" else NA_character_
}

fertility_reader_error_categories <- function(errors) {
    readers <- names(errors)
    if (is.null(readers) || !identical(readers, c("direct", "rust", "haven"))) {
        stop("reader error flags are not canonical")
    }
    if (!any(errors)) return(character())
    paste0(readers[errors], "-reader-error")
}

fertility_string_payload_bytes <- function(frame) {
    values <- vapply(frame, function(column) {
        if (!is.character(column)) return(0)
        sum(nchar(column, type = "bytes", allowNA = TRUE), na.rm = TRUE)
    }, numeric(1))
    sum(values)
}

fertility_worker_sizing_tile <- function(item, tile, framework_id,
                                         timeout_seconds, encoding = NULL) {
    readers <- c("direct", "rust", "haven")
    maximum <- 0
    completed <- 0L
    errors <- setNames(rep(FALSE, length(readers)), readers)
    memory_errors <- errors
    for (offset in tile$sample_offsets) {
        payload <- 0
        complete <- TRUE
        for (reader in readers) {
            sample_tile <- tile
            sample_tile$type <- "value"
            sample_tile$skip <- as.double(offset)
            sample_tile$n_max <- 1L
            value <- tryCatch({
                frame <- fertility_tile_read(
                    reader, item$path, sample_tile, encoding = encoding
                )
                fertility_string_payload_bytes(frame)
            }, error = identity)
            if (inherits(value, "error")) {
                errors[[reader]] <- TRUE
                memory_errors[[reader]] <- memory_errors[[reader]] ||
                    fertility_memory_error(value)
                complete <- FALSE
            } else {
                payload <- payload + value
            }
            rm(value)
            gc(FALSE)
        }
        if (complete) {
            maximum <- max(maximum, payload)
            completed <- completed + 1L
        }
    }
    classification <- if (any(memory_errors)) "memory-limit" else
        if (any(errors)) fertility_reader_error_classification(errors) else "pass"
    c(fertility_worker_base(item, framework_id, timeout_seconds), list(
        tile_id = tile$tile_id, tile_type = tile$type, batch = tile$batch,
        skip = tile$skip, n_max = tile$n_max, classification = classification,
        secondary = fertility_reader_error_categories(errors),
        mismatches = fertility_bind_mismatches(list()), rows = completed,
        reader_rows = setNames(rep(NA_integer_, length(readers)), readers),
        columns = length(tile$column_names), column_names = character(),
        storage = character(), structural_rows = NA_real_, column_bytes = numeric(),
        strl = logical(), payload_bytes_per_row = if (completed) maximum else NA_real_,
        samples_requested = length(tile$sample_offsets),
        samples_completed = completed,
        projection_expected_count = NA_integer_,
        projection_expected_hash = NA_character_,
        projection_counts = setNames(rep(NA_integer_, length(readers)), readers),
        projection_hashes = setNames(rep(NA_character_, length(readers)), readers),
        projection_ok = setNames(rep(NA, length(readers)), readers),
        elapsed_seconds = 0
    ))
}

fertility_worker_tile <- function(item, tile, compare_script, package_library,
                                  expected_package_path, framework_id,
                                  timeout_seconds) {
    source(compare_script, local = environment(fertility_worker_tile))
    fertility_load_readers(package_library, expected_package_path)
    encoding <- fertility_worker_encoding(item)
    started <- proc.time()[["elapsed"]]
    if (identical(tile$type, "sizing")) {
        result <- fertility_worker_sizing_tile(
            item, tile, framework_id, timeout_seconds, encoding = encoding
        )
        result$elapsed_seconds <- unname(proc.time()[["elapsed"]] - started)
        return(result)
    }
    readers <- c("direct", "rust", "haven")
    values <- setNames(lapply(readers, function(reader) {
        tryCatch(
            fertility_tile_read(reader, item$path, tile, encoding = encoding),
            error = identity
        )
    }), readers)
    errors <- vapply(values, inherits, logical(1), what = "error")
    memory_errors <- vapply(values, function(value) {
        inherits(value, "error") && fertility_memory_error(value)
    }, logical(1))
    reader_rows <- setNames(rep(NA_integer_, length(readers)), readers)
    for (reader in readers[!errors]) {
        reader_rows[[reader]] <- if (identical(tile$type, "metadata"))
            values[[reader]]$shape_rows else nrow(values[[reader]])
    }
    secondary <- fertility_reader_error_categories(errors)
    frames <- values
    if (identical(tile$type, "metadata")) {
        frames[!errors] <- lapply(values[!errors], `[[`, "frame")
    }
    projection <- if (tile$type %in% c("value", "terminal")) {
        fertility_projection_attestation(
            frames, errors, tile$column_names, framework_id
        )
    } else list(
        expected_count = NA_integer_, expected_hash = NA_character_,
        counts = setNames(rep(NA_integer_, length(readers)), readers),
        hashes = setNames(rep(NA_character_, length(readers)), readers),
        ok = setNames(rep(NA, length(readers)), readers)
    )
    pair_comparison <- fertility_compare_available_pairs(frames, errors)
    mismatches <- pair_comparison$mismatches
    secondary <- c(secondary, pair_comparison$secondary)
    if (tile$type %in% c("value", "terminal") &&
        any(!projection$ok[!errors])) {
        mismatches <- fertility_bind_mismatches(list(
            mismatches, fertility_mismatch_record(
                "metadata-mismatch", "projection-name-mismatch"
            )
        ))
        secondary <- c(secondary, "metadata-mismatch")
    }
    structural <- if (identical(tile$type, "metadata")) tryCatch(
        dtaparser:::.dta_metadata(item$path, encoding = encoding), error = identity
    ) else NULL
    source_structure <- if (identical(tile$type, "metadata")) tryCatch(
        fertility_structural_metadata(item$path), error = identity
    ) else NULL
    if (inherits(structural, "error") || inherits(source_structure, "error")) {
        secondary <- c(secondary, "metadata-reader-error")
    }
    if (identical(tile$type, "metadata") && !inherits(structural, "error")) {
        if (anyNA(structural) || anyDuplicated(structural)) {
            mismatches <- fertility_bind_mismatches(list(
                mismatches, fertility_mismatch_record(
                    "metadata-mismatch", "source-name-mismatch"
                )
            ))
        }
        for (reader in readers[!errors]) {
            if (!identical(names(frames[[reader]]), as.character(structural))) {
                mismatches <- fertility_bind_mismatches(list(
                    mismatches, fertility_mismatch_record(
                        "metadata-mismatch", "source-name-mismatch"
                    )
                ))
            }
        }
    }
    if (identical(tile$type, "metadata")) {
        successful_shapes <- values[!errors]
        shape_rows <- vapply(successful_shapes, `[[`, integer(1), "shape_rows")
        shape_columns <- vapply(successful_shapes, `[[`, integer(1), "shape_columns")
        if (length(shape_columns) && any(shape_columns != 0L)) {
            mismatches <- fertility_bind_mismatches(list(
                mismatches, fertility_mismatch_record(
                    "metadata-mismatch", "zero-column-shape-mismatch"
                )
            ))
        }
        known_shape_rows <- shape_rows[!is.na(shape_rows)]
        expected_rows <- if (inherits(source_structure, "error")) NA_real_ else
            source_structure$rows
        expected_columns <- if (inherits(source_structure, "error")) NA_integer_ else
            source_structure$columns
        if (fertility_structural_shape_mismatch(
                known_shape_rows, expected_rows,
                if (inherits(structural, "error")) NA_integer_ else length(structural),
                expected_columns
            )) {
            mismatches <- fertility_bind_mismatches(list(
                mismatches, fertility_mismatch_record(
                    "metadata-mismatch", "row-count-mismatch"
                )
            ))
        }
    }
    if (identical(tile$type, "terminal") &&
        fertility_row_termination_mismatch(reader_rows)) {
        mismatches <- fertility_bind_mismatches(list(
            mismatches, fertility_mismatch_record(
                "unresolved", "row-termination-mismatch"
            )
        ))
        secondary <- c(secondary, "row-termination-mismatch")
    }
    error_classification <- fertility_reader_error_classification(errors)
    classification <- if (any(memory_errors)) "memory-limit" else if ("metadata-reader-error" %in% secondary)
        "dtaparser-only-error" else if (!is.na(error_classification))
        error_classification else if ("row-termination-mismatch" %in% secondary)
        "row-termination-mismatch" else if ("direct-vs-rust-mismatch" %in% secondary)
        "direct-vs-rust-mismatch" else if (nrow(mismatches))
        mismatches$category[[1L]] else "pass"
    successful <- frames[!errors]
    shape_source <- if (length(successful)) successful[[1L]] else NULL
    column_names <- if (identical(tile$type, "metadata")) {
        if (!inherits(structural, "error")) as.character(structural) else
            if (!is.null(shape_source)) names(shape_source) else character()
    } else character()
    storage <- if (identical(tile$type, "metadata") &&
                   !inherits(structural, "error"))
        attr(structural, "dta_storage", exact = TRUE) else character()
    column_bytes <- if (identical(tile$type, "metadata") &&
                        !inherits(source_structure, "error"))
        source_structure$column_bytes else numeric()
    strl <- if (identical(tile$type, "metadata") &&
                !inherits(source_structure, "error"))
        source_structure$strl else logical()
    structural_rows <- if (identical(tile$type, "metadata") &&
                           !inherits(source_structure, "error"))
        source_structure$rows else NA_real_
    rows <- if (identical(tile$type, "metadata")) {
        if (length(successful_shapes)) successful_shapes[[1L]]$shape_rows else NA_integer_
    } else if (is.null(shape_source)) NA_integer_ else nrow(shape_source)
    columns <- if (identical(tile$type, "metadata")) length(column_names) else
        if (is.null(shape_source)) NA_integer_ else ncol(shape_source)
    rm(values)
    invisible(gc())
    list(
        schema_version = fertility_schema_version, framework_id = framework_id,
        id = item$id, tile_id = tile$tile_id, tile_type = tile$type,
        batch = tile$batch, skip = tile$skip, n_max = tile$n_max,
        classification = classification, secondary = sort(unique(secondary)),
        mismatches = mismatches, rows = rows, reader_rows = reader_rows,
        columns = columns, column_names = column_names, storage = storage,
        structural_rows = structural_rows, column_bytes = column_bytes, strl = strl,
        projection_expected_count = projection$expected_count,
        projection_expected_hash = projection$expected_hash,
        projection_counts = projection$counts,
        projection_hashes = projection$hashes,
        projection_ok = projection$ok,
        elapsed_seconds = unname(proc.time()[["elapsed"]] - started)
    )
}

# Compatibility entry point for preflight classifications. Supported files must
# use bounded fertility_worker_tile() calls and can never take a whole-file path.
fertility_worker <- function(item, compare_script, package_library,
                             expected_package_path, framework_id,
                             timeout_seconds, parent_sha512) {
    started <- proc.time()[["elapsed"]]
    base <- fertility_worker_base(item, framework_id, timeout_seconds)
    finish <- function(classification, actual_sha512 = NA_character_) c(base, list(
        classification = classification, component = NA_integer_, rows = NA_real_,
        columns = NA_integer_, actual_sha512 = actual_sha512,
        elapsed_seconds = unname(proc.time()[["elapsed"]] - started)
    ))
    actual_sha512 <- tryCatch(
        fertility_file_sha512(item$path), error = function(error) NA_character_
    )
    if (is.na(actual_sha512)) return(finish("input-hash-error"))
    if (!identical(actual_sha512, parent_sha512)) {
        return(finish("input-changed-before-read", actual_sha512))
    }
    if (nzchar(item$expected_sha512) &&
        !identical(actual_sha512, tolower(item$expected_sha512))) {
        return(finish("input-signature-mismatch", actual_sha512))
    }
    if (!(item$release %in% fertility_supported_releases)) {
        return(finish("expected-unsupported-111", actual_sha512))
    }
    stop("supported corpus files require bounded tile execution")
}
