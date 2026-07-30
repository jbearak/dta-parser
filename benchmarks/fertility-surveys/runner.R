fertility_report_schema_version <- 2L
fertility_legacy_report_schema_version <- 1L
fertility_legacy_corpus_schema_version <- 10L

fertility_usage <- function() {
    paste(
        "usage: run.R [--inventory-only]",
        "(--cache-root=/absolute/path --manifest=/absolute/path |",
        " --output-root=/absolute/path)",
        "[--program=a,b] [--release=113,118] [--id=F0001,F0002]",
        "[--encoding-override=F0001:ENCODING]",
        "[--shard-index=N --shard-count=N] [--max-files=N]",
        "[--timeout-seconds=N] [--chunk-rows=N] [--column-batch=N]",
        "[--memory-mib=N] [--cell-budget=N] [--max-tiles-per-batch=N]",
        "[--beyond-end-windows=N] [--accepted-current-hashes=ID] [--retry]"
    )
}

fertility_parse_positive_integer <- function(value, option) {
    if (!grepl("^[1-9][0-9]*$", value)) stop(option, " must be a positive integer")
    number <- as.double(value)
    if (!is.finite(number) || number > .Machine$integer.max) stop(option, " is too large")
    as.integer(number)
}

fertility_canonical_encoding <- function(value) {
    if (!is.character(value) || length(value) != 1L || is.na(value) ||
        !nzchar(value)) {
        stop("encoding override must contain one non-empty encoding")
    }
    key <- tolower(gsub("[-_ ]", "", value))
    canonical <- switch(
        key,
        utf8 = "UTF-8",
        windows1252 = "Windows-1252",
        cp1252 = "Windows-1252",
        iso88591 = "ISO-8859-1",
        latin1 = "ISO-8859-1",
        NULL
    )
    if (is.null(canonical)) {
        stop(paste(
            "unsupported encoding override; use UTF-8, Windows-1252,",
            "or ISO-8859-1"
        ))
    }
    canonical
}

fertility_parse_encoding_overrides <- function(values) {
    if (!length(values)) return(setNames(character(), character()))
    if (!is.character(values) || anyNA(values)) {
        stop("encoding overrides must be character values")
    }
    entries <- unlist(strsplit(values, ",", fixed = TRUE), use.names = FALSE)
    if (!length(entries) || any(!nzchar(entries))) {
        stop("--encoding-override contains an empty entry")
    }
    pieces <- strsplit(entries, ":", fixed = TRUE)
    if (any(lengths(pieces) != 2L)) {
        stop("--encoding-override entries must have the form F0001:ENCODING")
    }
    ids <- vapply(pieces, `[[`, character(1), 1L)
    encodings <- vapply(pieces, `[[`, character(1), 2L)
    if (any(!grepl("^F[0-9]{4}$", ids))) {
        stop("invalid --encoding-override ID")
    }
    if (anyDuplicated(ids)) stop("duplicate --encoding-override ID")
    encodings <- vapply(encodings, fertility_canonical_encoding, character(1))
    ordering <- order(ids)
    setNames(encodings[ordering], ids[ordering])
}

fertility_encoding_overrides_text <- function(overrides) {
    if (!length(overrides)) return("")
    paste(names(overrides), overrides, sep = ":", collapse = ",")
}

fertility_validate_encoding_overrides <- function(overrides, family) {
    canonical <- if (length(overrides)) fertility_parse_encoding_overrides(
        fertility_encoding_overrides_text(overrides)
    ) else setNames(character(), character())
    if (!identical(overrides, canonical)) stop("encoding overrides are not canonical")
    if (length(setdiff(names(overrides), family$id))) {
        stop("encoding override IDs are outside the complete selected family")
    }
    invisible(overrides)
}

fertility_parse_arguments <- function(arguments) {
    options <- list(
        inventory_only = FALSE, programs = character(), releases = integer(),
        ids = character(), shard_index = 1L, shard_count = 1L,
        max_files = Inf, timeout_seconds = 600L, chunk_rows = 10000L,
        column_batch = 16L, memory_mib = 256L, cell_budget = 1000000L,
        max_tiles_per_batch = 100000L, beyond_end_windows = 1L,
        encoding_overrides = setNames(character(), character()),
        accepted_current_hashes = "", cache_root = "", manifest = "",
        output_root = "", retry = FALSE
    )
    seen_shard_index <- seen_shard_count <- FALSE
    seen_program <- FALSE
    seen_cache_root <- seen_manifest <- FALSE
    encoding_override_values <- character()
    for (argument in arguments) {
        if (identical(argument, "--inventory-only")) options$inventory_only <- TRUE
        else if (identical(argument, "--retry")) options$retry <- TRUE
        else if (startsWith(argument, "--cache-root=")) {
            if (seen_cache_root) stop("--cache-root may be supplied only once")
            options$cache_root <- sub("^[^=]+=", "", argument)
            seen_cache_root <- TRUE
            if (!startsWith(options$cache_root, "/")) {
                stop("--cache-root must be absolute")
            }
        } else if (startsWith(argument, "--manifest=")) {
            if (seen_manifest) stop("--manifest may be supplied only once")
            options$manifest <- sub("^[^=]+=", "", argument)
            seen_manifest <- TRUE
            if (!startsWith(options$manifest, "/")) {
                stop("--manifest must be absolute")
            }
        } else if (startsWith(argument, "--output-root=")) {
            if (nzchar(options$output_root)) stop("--output-root may be supplied only once")
            options$output_root <- sub("^[^=]+=", "", argument)
            if (!startsWith(options$output_root, "/")) {
                stop("--output-root must be absolute")
            }
        } else if (startsWith(argument, "--program=")) {
            seen_program <- TRUE
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
        } else if (startsWith(argument, "--encoding-override=")) {
            encoding_override_values <- c(
                encoding_override_values, sub("^[^=]+=", "", argument)
            )
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
        } else if (startsWith(argument, "--accepted-current-hashes=")) {
            if (nzchar(options$accepted_current_hashes)) {
                stop("--accepted-current-hashes may be supplied only once")
            }
            options$accepted_current_hashes <- sub("^[^=]+=", "", argument)
            if (!grepl("^[0-9a-f]{64}$", options$accepted_current_hashes)) {
                stop("--accepted-current-hashes requires an exact commitment ID")
            }
        } else stop(fertility_usage())
    }
    options$encoding_overrides <- fertility_parse_encoding_overrides(
        encoding_override_values
    )
    if (nzchar(options$output_root)) {
        fertility_assert_output_root(options$output_root)
        if (seen_program) stop("--program cannot be combined with --output-root")
        if (nzchar(options$accepted_current_hashes)) {
            stop("accepted-current-hash evidence cannot be combined with --output-root")
        }
        options$programs <- "output"
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

fertility_validate_source_arguments <- function(options) {
    raw_arguments <- c(cache_root = options$cache_root, manifest = options$manifest)
    supplied_raw <- nzchar(raw_arguments)
    if (fertility_output_requested(options)) {
        if (any(supplied_raw)) {
            stop("--cache-root and --manifest are invalid with --output-root")
        }
        return(options)
    }
    if (!all(supplied_raw)) {
        stop("raw fertility mode requires explicit --cache-root and --manifest")
    }
    cache_root <- fertility_assert_canonical_components(
        options$cache_root, "fertility cache root"
    )
    if (!dir.exists(cache_root) || fertility_path_is_symlink(cache_root)) {
        stop("fertility cache root must be a canonical non-symlink directory")
    }
    manifest <- fertility_assert_canonical_components(
        options$manifest, "fertility manifest"
    )
    if (!file.exists(manifest) || dir.exists(manifest) ||
        fertility_path_is_symlink(manifest) || !isTRUE(file_test("-f", manifest))) {
        stop("fertility manifest must be a canonical non-symlink regular file")
    }
    options$cache_root <- cache_root
    options$manifest <- manifest
    options
}

fertility_filter_inventory_base <- function(inventory, options) {
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
    selected
}

fertility_shard_index <- function(ids, inventory_ids, shard_count) {
    positions <- match(ids, inventory_ids)
    if (anyNA(positions)) stop("selection contains an unknown inventory ID")
    ((positions - 1L) %% as.integer(shard_count)) + 1L
}

fertility_filter_inventory <- function(inventory, options) {
    selected <- fertility_filter_inventory_base(inventory, options)
    owners <- fertility_shard_index(selected$id, inventory$id, options$shard_count)
    selected <- selected[owners == options$shard_index, , drop = FALSE]
    if (is.finite(options$max_files) && nrow(selected) > options$max_files) {
        selected <- selected[seq_len(options$max_files), , drop = FALSE]
    }
    selected
}

fertility_family_selection <- function(inventory, options) {
    eligible <- fertility_filter_inventory_base(inventory, options)
    pieces <- lapply(seq_len(options$shard_count), function(index) {
        current <- eligible[fertility_shard_index(
            eligible$id, inventory$id, options$shard_count
        ) == index, , drop = FALSE]
        if (is.finite(options$max_files) && nrow(current) > options$max_files) {
            current <- current[seq_len(options$max_files), , drop = FALSE]
        }
        current
    })
    if (!length(pieces)) return(eligible[FALSE, , drop = FALSE])
    result <- do.call(rbind, pieces)
    result[order(match(result$id, inventory$id)), , drop = FALSE]
}

fertility_inventory_id <- function(inventory) {
    fertility_stable_id(list(
        ids = paste(inventory$id, collapse = ","),
        programs = paste(inventory$program, collapse = ","),
        levels = paste(inventory$level, collapse = ","),
        releases = paste(inventory$release, collapse = ","),
        signatures = paste(inventory$expected_sha512, collapse = ",")
    ))
}

fertility_manifest_id <- function(
    manifest, fields = names(manifest), schema_version = fertility_schema_version
) {
    if (!identical(names(manifest), fields)) stop("manifest schema is not canonical")
    text <- lapply(manifest, as.character)
    rows <- if (!nrow(manifest)) character() else vapply(
        seq_len(nrow(manifest)), function(index) {
            paste(vapply(text, function(column) column[[index]], character(1L)),
                  collapse = "\037")
        }, character(1L)
    )
    fertility_stable_id(list(
        schema_version = as.integer(schema_version),
        fields = paste(fields, collapse = ","),
        rows = paste(rows, collapse = "\036")
    ))
}

fertility_inventory_manifest <- function(inventory) {
    manifest <- fertility_public_inventory(inventory)
    manifest$release <- as.integer(manifest$release)
    rownames(manifest) <- NULL
    manifest
}

fertility_family_manifest <- function(inventory, options) {
    family <- fertility_family_selection(inventory, options)
    manifest <- fertility_public_inventory(family)
    manifest$release <- as.integer(manifest$release)
    manifest$shard_index <- fertility_shard_index(
        manifest$id, inventory$id, options$shard_count
    )
    rownames(manifest) <- NULL
    manifest
}

fertility_filter_spec <- function(options) {
    list(
        program_filter = paste(sort(options$programs), collapse = ","),
        release_filter = paste(sort(options$releases), collapse = ","),
        id_filter = paste(sort(options$ids), collapse = ","),
        max_files = as.character(options$max_files)
    )
}

fertility_options_from_filter_spec <- function(provenance) {
    split_filter <- function(value, mode = "character") {
        if (!nzchar(value)) return(if (mode == "integer") integer() else character())
        pieces <- strsplit(value, ",", fixed = TRUE)[[1L]]
        if (mode == "integer") {
            if (any(!grepl("^[0-9]+$", pieces))) stop("invalid release filter provenance")
            return(as.integer(pieces))
        }
        pieces
    }
    max_value <- provenance$max_files[[1L]]
    max_files <- if (identical(max_value, "Inf")) Inf else {
        if (!grepl("^[1-9][0-9]*$", max_value)) stop("invalid max-files provenance")
        as.integer(max_value)
    }
    programs <- split_filter(provenance$program_filter[[1L]])
    releases <- split_filter(provenance$release_filter[[1L]], "integer")
    ids <- split_filter(provenance$id_filter[[1L]])
    if (any(!programs %in% fertility_programs) ||
        any(!grepl("^F[0-9]{4}$", ids)) || anyDuplicated(programs) ||
        anyDuplicated(releases) || anyDuplicated(ids) ||
        !identical(programs, sort(programs)) ||
        !identical(releases, sort(releases)) || !identical(ids, sort(ids))) {
        stop("filter provenance is not canonical")
    }
    shard_value <- provenance$shard_count[[1L]]
    if (!grepl("^[1-9][0-9]*$", shard_value)) stop("invalid shard-count provenance")
    shard_count <- suppressWarnings(as.integer(shard_value))
    if (is.na(shard_count)) stop("invalid shard-count provenance")
    encoding_text <- provenance$encoding_overrides[[1L]]
    encoding_overrides <- if (nzchar(encoding_text)) {
        fertility_parse_encoding_overrides(encoding_text)
    } else setNames(character(), character())
    if (!identical(fertility_encoding_overrides_text(encoding_overrides),
                   encoding_text)) {
        stop("encoding override provenance is not canonical")
    }
    list(
        programs = programs, releases = releases, ids = ids,
        shard_index = 1L, shard_count = shard_count, max_files = max_files,
        encoding_overrides = encoding_overrides
    )
}

fertility_family_id_from_manifest <- function(
    manifest, framework_id, config_id, build_provenance_id, inventory_id,
    shard_count, max_files, report_schema_id = fertility_report_schema_id(),
    evidence_origin = "fresh-execution",
    source_corpus_schema_version = fertility_schema_version
) {
    fertility_stable_id(list(
        framework_id = framework_id, config_id = config_id,
        build_provenance_id = build_provenance_id,
        inventory_id = inventory_id, report_schema_id = report_schema_id,
        evidence_origin = evidence_origin,
        source_corpus_schema_version = as.integer(source_corpus_schema_version),
        family_manifest_id = fertility_manifest_id(manifest),
        shard_count = as.integer(shard_count), max_files = as.character(max_files)
    ))
}

fertility_selection_family_id <- function(
    inventory, options, framework_id, config_id, build_provenance_id,
    report_schema_id = fertility_report_schema_id(),
    evidence_origin = "fresh-execution",
    source_corpus_schema_version = fertility_schema_version
) {
    fertility_family_id_from_manifest(
        fertility_family_manifest(inventory, options), framework_id, config_id,
        build_provenance_id, fertility_inventory_id(inventory),
        options$shard_count, options$max_files, report_schema_id,
        evidence_origin, source_corpus_schema_version
    )
}

fertility_full_output_family <- function(options) {
    identical(options$programs, "output") && !length(options$releases) &&
        !length(options$ids) && !is.finite(options$max_files)
}

fertility_full_default_family <- function(options) {
    (!length(options$programs) || fertility_full_output_family(options)) &&
        !length(options$releases) && !length(options$ids) &&
        !is.finite(options$max_files)
}

fertility_output_expected_releases <- c(
    `111` = 130L, `113` = 486L, `114` = 24L, `115` = 5L, `118` = 581L
)
fertility_output_expected_levels <- c(survey = 1218L, aggregate = 8L)

fertility_output_terminal_classifications <- function() c(
    "pass", "direct-vs-rust-mismatch", "dtaparser-only-error",
    "haven-only-error", "shared-reader-error", "metadata-mismatch",
    "value-mismatch", "tag-mismatch", "date-mismatch", "encoding-mismatch",
    "row-termination-mismatch", "known-intentional-divergence"
)

fertility_validate_full_output_results <- function(results) {
    values <- fertility_manifest_character(results, fertility_result_fields())
    releases <- suppressWarnings(as.integer(values$release))
    release_counts <- table(factor(
        releases, levels = as.integer(names(fertility_output_expected_releases))
    ))
    level_counts <- table(factor(
        values$level, levels = names(fertility_output_expected_levels)
    ))
    unsupported <- !(releases %in% fertility_supported_releases)
    supported <- !unsupported
    if (nrow(values) != fertility_output_expected_files ||
        !identical(values$id,
                   sprintf("F%04d", seq_len(fertility_output_expected_files))) ||
        any(values$program != "output")) {
        stop("full output family membership is invalid")
    }
    if (anyNA(releases) ||
        any(!(releases %in% as.integer(names(fertility_output_expected_releases)))) ||
        !identical(as.integer(release_counts),
                   as.integer(fertility_output_expected_releases))) {
        stop("full output family release counts are invalid")
    }
    if (any(!(values$level %in% names(fertility_output_expected_levels))) ||
        !identical(as.integer(level_counts),
                   as.integer(fertility_output_expected_levels))) {
        stop("full output family level counts are invalid")
    }
    if (!all(values$classification[unsupported] == "expected-unsupported-111") ||
        any(values$classification[supported] == "expected-unsupported-111")) {
        stop("full output family unsupported-release classifications are invalid")
    }
    tiles_expected <- suppressWarnings(as.integer(values$tiles_expected))
    tiles_completed <- suppressWarnings(as.integer(values$tiles_completed))
    supported_terminal <- values$classification[supported] %in%
        fertility_output_terminal_classifications()
    supported_tiles_complete <- !is.na(tiles_expected[supported]) &
        tiles_expected[supported] > 0L &
        !is.na(tiles_completed[supported]) &
        tiles_completed[supported] == tiles_expected[supported]
    supported_pass_complete <- values$classification[supported] != "pass" |
        values$complete[supported] == "TRUE"
    unsupported_tiles_zero <- !is.na(tiles_expected[unsupported]) &
        tiles_expected[unsupported] == 0L & !is.na(tiles_completed[unsupported]) &
        tiles_completed[unsupported] == 0L
    if (any(values$complete[unsupported] != "TRUE") ||
        any(!unsupported_tiles_zero) ||
        any(!supported_terminal) || any(!supported_tiles_complete) ||
        any(!supported_pass_complete)) {
        stop("full output family executable accounting is invalid")
    }
    invisible(TRUE)
}

fertility_capture_input <- function(item, acceptance = NULL) {
    captured <- tryCatch(
        suppressWarnings(fertility_nofollow_file_capture(item$path)),
        error = function(error) NULL
    )
    if (is.null(captured)) {
        device <- inode <- mode <- modified_ns <- changed_ns <- ""
        size <- NA_character_
        modified <- NA_character_
        actual <- NA_character_
    } else {
        device <- captured$device
        inode <- captured$inode
        mode <- captured$mode
        modified_ns <- captured$modified_ns
        changed_ns <- captured$changed_ns
        size <- captured$size
        modified <- fertility_descriptor_timestamp(captured$modified_seconds)
        actual <- captured$sha512
    }
    hash_status <- if (is.na(actual)) "error" else "ok"
    identity_fields <- list(
        id = item$id, release = as.integer(item$release),
        expected_sha512 = item$expected_sha512, hash_status = hash_status,
        actual_sha512 = if (is.na(actual)) "" else actual,
        device = device, inode = inode, mode = mode, modified_ns = modified_ns,
        changed_ns = changed_ns, size = size, modified = modified
    )
    accepted_sha512 <- ""
    manifest_hash_status <- if (identical(hash_status, "error")) "hash-read-error" else
        if (nzchar(item$expected_sha512) &&
            !identical(actual, tolower(item$expected_sha512))) "signature-mismatch" else
        if (nzchar(item$expected_sha512)) "signature-match" else "empty-manifest-signature"
    local_evidence_status <- "not-requested"
    if (!is.null(acceptance)) {
        position <- match(item$id, acceptance$entries$id)
        if (is.na(position)) stop("accepted-current-hash case is outside the commitment")
        accepted_sha512 <- acceptance$entries$accepted_sha512[[position]]
        local_evidence_status <- if (identical(hash_status, "ok") &&
            identical(actual, accepted_sha512)) "accepted-current-sha512-match" else
            "accepted-current-sha512-mismatch"
        identity_fields$acceptance_authority <- acceptance$authority
        identity_fields$acceptance_commitment_id <- acceptance$commitment_id
        identity_fields$acceptance_artifact_sha256 <- acceptance$artifact_sha256
        identity_fields$accepted_sha512 <- accepted_sha512
        identity_fields$manifest_hash_status <- manifest_hash_status
        identity_fields$local_evidence_status <- local_evidence_status
    }
    identity <- fertility_stable_id(identity_fields)
    list(
        input_id = identity, hash_status = hash_status, actual_sha512 = actual,
        device = device, inode = inode, mode = mode, size = size,
        modified_ns = modified_ns, changed_ns = changed_ns, modified = modified,
        accepted_sha512 = accepted_sha512,
        manifest_hash_status = manifest_hash_status,
        local_evidence_status = local_evidence_status,
        acceptance_authority = if (is.null(acceptance)) "" else acceptance$authority,
        acceptance_commitment_id = if (is.null(acceptance)) "" else
            acceptance$commitment_id,
        acceptance_artifact_sha256 = if (is.null(acceptance)) "" else
            acceptance$artifact_sha256
    )
}

fertility_inventory_preflight <- function(item, input) {
    if (identical(input$hash_status, "error")) {
        return(list(classification = "inventory-hash-error",
                    reason = "hash-read-error"))
    }
    if (!is.null(input$acceptance_commitment_id) &&
        nzchar(input$acceptance_commitment_id)) {
        if (!identical(input$manifest_hash_status, "signature-mismatch") ||
            !identical(input$local_evidence_status,
                       "accepted-current-sha512-match")) {
            return(list(classification = "inventory-hash-error",
                        reason = "signature-mismatch"))
        }
        return(NULL)
    }
    if (nzchar(item$expected_sha512) &&
        !identical(input$actual_sha512, tolower(item$expected_sha512))) {
        return(list(classification = "inventory-hash-error",
                    reason = "signature-mismatch"))
    }
    NULL
}

fertility_changed_input_reason <- function(input) {
    input_id_valid <- is.character(input$input_id) && length(input$input_id) == 1L &&
        grepl("^[0-9a-f]{64}$", input$input_id)
    hash_missing <- length(input$actual_sha512) != 1L ||
        is.na(input$actual_sha512)
    if (!input_id_valid) stop("changed input identity is invalid")
    if (identical(input$hash_status, "error") && hash_missing) {
        return("hash-read-error")
    }
    if (identical(input$hash_status, "ok") && !hash_missing &&
        is.character(input$actual_sha512) &&
        grepl("^[0-9a-f]{128}$", input$actual_sha512)) {
        return("input-changed")
    }
    stop("changed input capture is inconsistent")
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

fertility_result_acceptance_fields <- function(input) {
    if (is.null(input$acceptance_commitment_id) ||
        !nzchar(input$acceptance_commitment_id)) return(list())
    list(
        acceptance_authority = input$acceptance_authority,
        acceptance_commitment_id = input$acceptance_commitment_id,
        acceptance_artifact_sha256 = input$acceptance_artifact_sha256,
        accepted_sha512 = input$accepted_sha512,
        manifest_hash_status = input$manifest_hash_status,
        local_evidence_status = input$local_evidence_status
    )
}

fertility_base_result <- function(item, framework_id, timeout_seconds, input,
                                  classification, elapsed_seconds = NA_real_,
                                  secondary_categories = "") {
    c(list(
        schema_version = fertility_schema_version,
        framework_id = framework_id, input_id = input$input_id,
        id = item$id, program = item$program, level = item$level,
        release = as.integer(item$release), expected_sha512 = item$expected_sha512,
        timeout_seconds = timeout_seconds, classification = classification,
        component = NA_integer_, secondary_categories = secondary_categories,
        mismatch_count = 0L,
        mismatch_categories = "", mismatch_signatures = "", rows = NA_real_,
        columns = NA_integer_, tiles_expected = 0L, tiles_completed = 0L,
        complete = FALSE, actual_sha512 = input$actual_sha512,
        elapsed_seconds = elapsed_seconds
    ), fertility_result_acceptance_fields(input))
}

fertility_process_item <- function(item, checkpoint_path, framework_id,
                                   timeout_seconds, retry, execute) {
    input_before <- fertility_capture_input(item)
    checkpoint_path <- fertility_assert_checkpoint_file(
        checkpoint_path, "file checkpoint"
    )
    checkpoint <- if (file.exists(checkpoint_path)) tryCatch(
        readRDS(fertility_assert_checkpoint_file(
            checkpoint_path, "file checkpoint", must_exist = TRUE
        )), error = function(error) NULL
    ) else NULL
    if (!is.null(checkpoint) &&
        fertility_checkpoint_valid(
            checkpoint, item, framework_id, input_before, timeout_seconds
        ) &&
        (!retry || !fertility_should_retry(checkpoint))) {
        return(list(result = checkpoint, resumed = TRUE))
    }
    preflight <- fertility_inventory_preflight(item, input_before)
    if (!is.null(preflight)) {
        result <- fertility_base_result(
            item, framework_id, timeout_seconds, input_before,
            preflight$classification,
            secondary_categories = preflight$reason
        )
    } else {
        result <- execute(item, input_before)
        input_after <- fertility_capture_input(item)
        if (!identical(input_after$input_id, input_before$input_id)) {
            result <- fertility_base_result(
                item, framework_id, timeout_seconds, input_after,
                "inventory-hash-error",
                secondary_categories = fertility_changed_input_reason(input_after)
            )
        } else {
            result$input_id <- input_before$input_id
            result$actual_sha512 <- input_before$actual_sha512
        }
    }
    fertility_assert_checkpoint_file(checkpoint_path, "file checkpoint")
    fertility_atomic_save_rds(result, checkpoint_path)
    list(result = result, resumed = FALSE)
}

fertility_should_retry <- function(checkpoint) {
    checkpoint$classification %in% c(
        "timeout", "crash", "dtaparser-only-error", "haven-only-error",
        "shared-reader-error", "memory-limit", "unresolved"
    )
}

fertility_run_provenance_fields <- function() c(
    "schema_version", "report_schema_version", "evidence_origin",
    "source_corpus_schema_version", "replayed_at_utc", "acceptance_authority",
    "acceptance_commitment_id", "acceptance_artifact_sha256", "selection_id",
    "evidence_selection_id", "input_attestation_id", "family_id",
    "family_manifest_id", "framework_id", "config_id", "build_provenance_id",
    "inventory_id", "report_schema_id", "selected_files", "expected_family_files",
    "full_default_family", "program_filter", "release_filter", "id_filter",
    "encoding_overrides", "max_files", "shard_index", "shard_count", "timeout_seconds",
    "chunk_rows", "column_batch", "memory_mib", "cell_budget",
    "max_tiles_per_batch", "beyond_end_windows", "retry", "created_at_utc"
)

fertility_snapshot_report_schema_version <- function(provenance) {
    if (!is.data.frame(provenance) || !all(c(
        "evidence_origin", "source_corpus_schema_version"
    ) %in% names(provenance))) stop("shard evidence origin is unavailable")
    origins <- unique(provenance$evidence_origin)
    source_schemas <- unique(provenance$source_corpus_schema_version)
    if (length(origins) != 1L || length(source_schemas) != 1L) {
        stop("shard reports have mixed evidence origins")
    }
    if (identical(origins, "historical-schema-10-replay") &&
        identical(source_schemas,
                  as.character(fertility_legacy_corpus_schema_version))) {
        return(fertility_legacy_report_schema_version)
    }
    fertility_report_schema_version
}

fertility_result_fields <- function(include_build = TRUE) {
    fields <- c(
        "framework_id", "id", "program", "level", "release", "classification",
        "secondary_categories", "mismatch_count", "mismatch_categories",
        "mismatch_signatures", "rows", "columns", "tiles_expected",
        "tiles_completed", "complete", "elapsed_seconds"
    )
    if (include_build) c(fields, "build_provenance_id") else fields
}

fertility_report_schema_id <- function(
    report_schema_version = fertility_report_schema_version
) {
    report_schema_version <- as.integer(report_schema_version)
    contract <- paste(
        "hash,id,enum,manifest-release,enum,fixed-categories,count,",
        "fixed-counts,fixed-category-pair-hashed-counts-v2,",
        "optional-number,optional-count,count,",
        "count,boolean,optional-number,hash", sep = ""
    )
    if (identical(report_schema_version, fertility_legacy_report_schema_version)) {
        return(fertility_stable_id(list(
            schema_version = fertility_legacy_corpus_schema_version,
            fields = paste(fertility_result_fields(), collapse = ","),
            contract = contract
        )))
    }
    if (!identical(report_schema_version, fertility_report_schema_version)) {
        stop("unsupported public report schema version")
    }
    fertility_stable_id(list(
        report_schema_version = report_schema_version,
        fields = paste(fertility_result_fields(), collapse = ","),
        contract = contract
    ))
}

fertility_result_frame <- function(checkpoints) {
    fields <- fertility_result_fields(include_build = FALSE)
    character_fields <- c(
        "framework_id", "id", "program", "level", "classification",
        "secondary_categories", "mismatch_categories", "mismatch_signatures"
    )
    integer_fields <- c(
        "release", "mismatch_count", "columns", "tiles_expected", "tiles_completed"
    )
    numeric_fields <- c("rows", "elapsed_seconds")
    coerce_field <- function(value, field) {
        if (is.null(value) || length(value) != 1L) value <- NA
        if (field %in% character_fields) return(as.character(value))
        if (field %in% integer_fields) return(as.integer(value))
        if (field %in% numeric_fields) return(as.double(value))
        if (identical(field, "complete")) return(as.logical(value))
        stop("unknown public result field")
    }
    columns <- setNames(lapply(fields, function(field) {
        if (!length(checkpoints)) return(coerce_field(NULL, field)[FALSE])
        vapply(checkpoints, function(value) coerce_field(value[[field]], field),
               coerce_field(NULL, field))
    }), fields)
    result <- as.data.frame(columns, stringsAsFactors = FALSE, optional = TRUE)
    rownames(result) <- NULL
    result
}

fertility_classifications <- function() c(
    "pass", "expected-unsupported-111", "inventory-hash-error",
    "direct-vs-rust-mismatch", "dtaparser-only-error", "haven-only-error",
    "shared-reader-error", "metadata-mismatch", "value-mismatch", "tag-mismatch",
    "date-mismatch", "encoding-mismatch", "row-termination-mismatch",
    "known-intentional-divergence", "timeout", "memory-limit", "crash", "unresolved"
)

fertility_mismatch_categories <- function() c(
    "metadata-mismatch", "value-mismatch", "tag-mismatch", "date-mismatch",
    "encoding-mismatch", "row-termination-mismatch", "direct-vs-rust-mismatch",
    "known-intentional-divergence", "unresolved"
)

fertility_validate_public_results <- function(results) {
    if (!is.data.frame(results) ||
        !identical(names(results), fertility_result_fields())) {
        stop("result report schema is not the exact public schema")
    }
    if (any(vapply(results, function(value) {
        is.factor(value) || is.list(value) || !is.atomic(value) || !is.null(dim(value))
    }, logical(1)))) stop("result report contains an invalid column type")
    character_fields <- c(
        "framework_id", "id", "program", "level", "classification",
        "secondary_categories", "mismatch_categories", "mismatch_signatures",
        "build_provenance_id"
    )
    numeric_fields <- c(
        "release", "mismatch_count", "rows", "columns", "tiles_expected",
        "tiles_completed", "elapsed_seconds"
    )
    if (any(vapply(character_fields, function(field) {
        !is.character(results[[field]])
    }, logical(1))) || any(vapply(numeric_fields, function(field) {
        !(is.character(results[[field]]) || is.integer(results[[field]]) ||
          is.double(results[[field]]))
    }, logical(1))) || !(is.character(results$complete) || is.logical(results$complete))) {
        stop("result report contains an invalid column type")
    }
    if (!nrow(results)) return(invisible(TRUE))
    values <- lapply(results, function(value) {
        value <- as.character(value)
        value[is.na(value)] <- ""
        value
    })
    if (any(!grepl("^[0-9a-f]{64}$", values$framework_id)) ||
        any(!grepl("^[0-9a-f]{64}$", values$build_provenance_id)) ||
        any(!grepl("^F[0-9]{4}$", values$id)) ||
        any(!values$program %in% fertility_programs) ||
        any(!values$level %in% fertility_levels) ||
        any(!grepl("^[1-9][0-9]*$", values$release)) ||
        any(!values$classification %in% fertility_classifications()) ||
        any(!values$complete %in% c("TRUE", "FALSE"))) {
        stop("result report contains an invalid scalar")
    }
    integer_required <- c("mismatch_count", "tiles_expected", "tiles_completed")
    integer_optional <- "columns"
    number_optional <- c("rows", "elapsed_seconds")
    if (any(vapply(integer_required, function(field) {
        any(!grepl("^(0|[1-9][0-9]*)$", values[[field]]))
    }, logical(1))) || any(vapply(integer_optional, function(field) {
        any(nzchar(values[[field]]) &
            !grepl("^(0|[1-9][0-9]*)$", values[[field]]))
    }, logical(1))) || any(vapply(number_optional, function(field) {
        any(nzchar(values[[field]]) &
            !grepl("^[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$", values[[field]]))
    }, logical(1)))) stop("result report contains an invalid numeric scalar")
    if (any(as.double(values$tiles_completed) > as.double(values$tiles_expected))) {
        stop("result report contains inconsistent tile accounting")
    }
    allowed_secondary <- unique(c(
        fertility_classifications(), fertility_mismatch_categories(),
        "direct-reader-error", "rust-reader-error", "haven-reader-error",
        "metadata-reader-error", "hash-read-error", "signature-mismatch",
        "input-changed", "tile-ceiling-reached",
        "structural-metadata-unavailable"
    ))
    secondary_ok <- vapply(values$secondary_categories, function(value) {
        if (!nzchar(value)) return(TRUE)
        pieces <- strsplit(value, ",", fixed = TRUE)[[1L]]
        all(pieces %in% allowed_secondary) && !anyDuplicated(pieces) &&
            identical(pieces, sort(pieces))
    }, logical(1))
    parse_count_map <- function(value, key_pattern, allowed_keys = NULL) {
        if (!nzchar(value)) return(list(keys = character(), counts = integer()))
        pieces <- strsplit(value, ",", fixed = TRUE)[[1L]]
        if (any(!grepl(paste0("^", key_pattern, "=[1-9][0-9]*$"), pieces))) {
            return(NULL)
        }
        keys <- sub("=[0-9]+$", "", pieces)
        counts <- suppressWarnings(as.integer(sub("^.*=", "", pieces)))
        if (anyNA(counts) || anyDuplicated(keys) ||
            (!is.null(allowed_keys) && any(!keys %in% allowed_keys)) ||
            !identical(order(-counts, keys), seq_along(keys))) return(NULL)
        list(keys = keys, counts = counts)
    }
    categories <- lapply(values$mismatch_categories, parse_count_map,
                         key_pattern = "[a-z0-9-]+",
                         allowed_keys = fertility_mismatch_categories())
    signatures <- lapply(values$mismatch_signatures, parse_count_map,
                         key_pattern = "[0-9a-f]{64}")
    aggregate_ok <- vapply(seq_len(nrow(results)), function(index) {
        if (is.null(categories[[index]]) || is.null(signatures[[index]])) return(FALSE)
        expected <- as.integer(values$mismatch_count[[index]])
        category_total <- sum(categories[[index]]$counts)
        signature_total <- sum(signatures[[index]]$counts)
        identical(category_total, expected) && identical(signature_total, expected) &&
            identical(expected == 0L,
                      !nzchar(values$mismatch_categories[[index]])) &&
            identical(expected == 0L,
                      !nzchar(values$mismatch_signatures[[index]]))
    }, logical(1))
    if (!all(secondary_ok) || !all(aggregate_ok)) {
        stop("result report contains non-public mismatch detail or inconsistent counts")
    }
    invisible(TRUE)
}

fertility_classification_summary <- function(results) {
    if (!nrow(results)) {
        return(data.frame(classification = character(), files = integer(),
                          stringsAsFactors = FALSE))
    }
    summary <- as.data.frame(table(classification = results$classification),
                             stringsAsFactors = FALSE)
    names(summary)[[2L]] <- "files"
    summary
}

fertility_publication_frame <- function(value) {
    result <- fertility_character_frame(value)
    for (field in names(result)) result[[field]][is.na(result[[field]])] <- ""
    result
}

fertility_publish_results <- function(checkpoints, build_provenance_id, path) {
    results <- fertility_result_frame(checkpoints)
    results$build_provenance_id <- rep(build_provenance_id, nrow(results))
    fertility_validate_public_results(results)
    results <- fertility_publication_frame(results)
    fertility_validate_public_results(results)
    fertility_atomic_write_table(results, path)
    results
}

fertility_merged_results_id <- function(results) {
    fertility_manifest_id(
        fertility_manifest_character(results, fertility_result_fields()),
        fertility_result_fields(), fertility_report_schema_version
    )
}

fertility_merge_identity <- function(provenance) {
    fields <- c(
        "schema_version", "report_schema_version", "evidence_origin",
        "source_corpus_schema_version", "replayed_at_utc",
        "acceptance_authority", "acceptance_commitment_id",
        "acceptance_artifact_sha256", "family_id", "evidence_family_id",
        "family_input_attestation_id", "framework_id", "config_id",
        "build_provenance_id", "inventory_id", "family_manifest_id",
        "report_schema_id", "results_id", "shard_count", "files",
        "full_default_family"
    )
    if (!is.data.frame(provenance) || nrow(provenance) != 1L ||
        !all(fields %in% names(provenance))) {
        stop("merge identity provenance is invalid")
    }
    fertility_stable_id(as.list(provenance[1L, fields, drop = FALSE]))
}

fertility_merge_provenance_fields <- function() c(
    "schema_version", "report_schema_version", "evidence_origin",
    "source_corpus_schema_version", "replayed_at_utc",
    "acceptance_authority", "acceptance_commitment_id",
    "acceptance_artifact_sha256", "family_id", "evidence_family_id",
    "family_input_attestation_id", "framework_id", "config_id",
    "build_provenance_id", "inventory_id", "family_manifest_id",
    "report_schema_id", "results_id", "merge_id", "shard_count", "files",
    "full_default_family", "created_at_utc"
)

fertility_assessment_legacy_provenance_fields <- function() c(
    "schema_version", "report_schema_version", "evidence_origin",
    "source_corpus_schema_version", "replayed_at_utc", "family_id",
    "evidence_family_id", "family_input_attestation_id", "framework_id",
    "config_id", "build_provenance_id", "inventory_id", "family_manifest_id",
    "report_schema_id", "shard_count", "files", "full_default_family",
    "created_at_utc"
)

fertility_assessment_bundle_files <- function(format = c("current", "legacy-original")) {
    format <- match.arg(format)
    files <- c(
        provenance = "merge-provenance.tsv", results = "results.tsv",
        summary = "summary.tsv", family_manifest = "family-manifest.tsv"
    )
    if (identical(format, "current")) {
        files <- c(files, input_attestation = "input-attestation.tsv")
    }
    files
}

fertility_assessment_bundle_format <- function(entries, role = c("original", "accepted")) {
    role <- match.arg(role)
    if (!is.character(entries) || anyNA(entries) || anyDuplicated(entries)) {
        stop("assessment merged-family bundle shape is invalid")
    }
    entries <- sort(entries)
    current <- sort(unname(fertility_assessment_bundle_files("current")))
    legacy <- sort(unname(fertility_assessment_bundle_files("legacy-original")))
    if (identical(entries, current)) return("current-merged-report-v2")
    if (identical(role, "original") && identical(entries, legacy)) {
        return("legacy-original-merged-report-v2")
    }
    stop("assessment merged-family bundle has an unsupported exact file set")
}

fertility_validate_merged_bundle <- function(bundle, family_id,
                                              canonical_inventory) {
    required <- c(
        "provenance", "results", "summary", "family_manifest", "input_attestation"
    )
    if (!is.list(bundle) || !identical(sort(names(bundle)), sort(required)) ||
        !all(vapply(bundle, is.data.frame, logical(1)))) {
        stop("merged report bundle schema is invalid")
    }
    provenance <- fertility_manifest_character(
        bundle$provenance, fertility_merge_provenance_fields()
    )
    if (nrow(provenance) != 1L || !identical(provenance$family_id[[1L]], family_id)) {
        stop("merged report family provenance is invalid")
    }
    hash_fields <- c(
        "family_id", "evidence_family_id", "family_input_attestation_id",
        "framework_id", "config_id", "build_provenance_id", "inventory_id",
        "family_manifest_id", "report_schema_id", "results_id", "merge_id"
    )
    accepted <- nzchar(provenance$acceptance_commitment_id[[1L]])
    acceptance_valid <- if (accepted) {
        identical(provenance$acceptance_authority[[1L]],
                  fertility_acceptance_authority()) &&
            grepl("^[0-9a-f]{64}$", provenance$acceptance_commitment_id[[1L]]) &&
            grepl("^[0-9a-f]{64}$", provenance$acceptance_artifact_sha256[[1L]])
    } else {
        !nzchar(provenance$acceptance_authority[[1L]]) &&
            !nzchar(provenance$acceptance_artifact_sha256[[1L]])
    }
    fresh <- identical(provenance$evidence_origin[[1L]], "fresh-execution")
    historical <- identical(
        provenance$evidence_origin[[1L]], "historical-schema-10-replay"
    )
    origin_valid <- (fresh &&
        identical(provenance$source_corpus_schema_version[[1L]],
                  as.character(fertility_schema_version)) &&
        !nzchar(provenance$replayed_at_utc[[1L]])) ||
        (historical &&
         identical(provenance$source_corpus_schema_version[[1L]],
                   as.character(fertility_legacy_corpus_schema_version)) &&
         grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$",
               provenance$replayed_at_utc[[1L]]))
    if (any(vapply(hash_fields, function(field) {
            !grepl("^[0-9a-f]{64}$", provenance[[field]][[1L]])
        }, logical(1))) || !acceptance_valid || !origin_valid ||
        (accepted && !fresh) ||
        !identical(provenance$schema_version[[1L]],
                   as.character(fertility_schema_version)) ||
        !identical(provenance$report_schema_version[[1L]],
                   as.character(fertility_report_schema_version)) ||
        !identical(provenance$report_schema_id[[1L]], fertility_report_schema_id()) ||
        !grepl("^[1-9][0-9]*$", provenance$shard_count[[1L]]) ||
        !grepl("^(0|[1-9][0-9]*)$", provenance$files[[1L]]) ||
        !provenance$full_default_family[[1L]] %in% c("TRUE", "FALSE") ||
        !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$",
               provenance$created_at_utc[[1L]])) {
        stop("merged report provenance contains an invalid scalar")
    }
    live_inventory_id <- fertility_inventory_id(canonical_inventory)
    canonical <- fertility_validate_canonical_inventory(
        fertility_inventory_manifest(canonical_inventory)
    )
    if (!identical(provenance$inventory_id[[1L]], live_inventory_id)) {
        stop("merged report does not match canonical inventory authority")
    }
    shard_count <- as.integer(provenance$shard_count[[1L]])
    manifest <- fertility_manifest_character(
        bundle$family_manifest,
        c("id", "program", "level", "release", "shard_index")
    )
    manifest_shards <- suppressWarnings(as.integer(manifest$shard_index))
    expected_members <- canonical[
        match(manifest$id, canonical$id),
        c("id", "program", "level", "release"), drop = FALSE
    ]
    rownames(expected_members) <- NULL
    if (anyDuplicated(manifest$id) || anyNA(manifest_shards) ||
        any(!grepl("^[1-9][0-9]*$", manifest$shard_index)) ||
        any(manifest_shards > shard_count) ||
        !identical(manifest[c("id", "program", "level", "release")],
                   expected_members) ||
        !identical(fertility_manifest_id(manifest),
                   provenance$family_manifest_id[[1L]])) {
        stop("merged family manifest is not canonical")
    }
    results <- fertility_manifest_character(bundle$results, fertility_result_fields())
    fertility_validate_public_results(results)
    if (nrow(results) != as.integer(provenance$files[[1L]]) ||
        !identical(results[c("id", "program", "level", "release")],
                   manifest[c("id", "program", "level", "release")]) ||
        any(results$framework_id != provenance$framework_id[[1L]]) ||
        any(results$build_provenance_id != provenance$build_provenance_id[[1L]]) ||
        !identical(fertility_merged_results_id(results), provenance$results_id[[1L]])) {
        stop("merged results are not bound to family provenance")
    }
    input_attestation <- fertility_manifest_character(
        bundle$input_attestation,
        c("shard_index", "input_attestation_id", "evidence_selection_id")
    )
    if (nrow(input_attestation) != shard_count || !identical(
        fertility_family_input_attestation_id(input_attestation),
        provenance$family_input_attestation_id[[1L]]
    )) stop("merged family input attestation identity is invalid")
    summary <- fertility_manifest_character(
        bundle$summary, c("classification", "files")
    )
    expected_summary <- fertility_manifest_character(
        fertility_classification_summary(results), c("classification", "files")
    )
    if (!identical(summary, expected_summary)) {
        stop("merged classification summary is invalid")
    }
    expected_evidence <- fertility_evidence_family_id(
        family_id, provenance$family_input_attestation_id[[1L]],
        provenance$evidence_origin[[1L]],
        as.integer(provenance$source_corpus_schema_version[[1L]]),
        provenance$report_schema_id[[1L]],
        provenance$acceptance_authority[[1L]],
        provenance$acceptance_commitment_id[[1L]]
    )
    if (!identical(provenance$evidence_family_id[[1L]], expected_evidence) ||
        !identical(provenance$merge_id[[1L]],
                   fertility_merge_identity(provenance))) {
        stop("merged evidence family identity is invalid")
    }
    full_default <- identical(provenance$full_default_family[[1L]], "TRUE")
    full_output <- full_default && nrow(results) > 0L &&
        all(results$program == "output")
    if (full_output) {
        fertility_validate_full_output_results(results)
    } else if (full_default && !identical(
        results$id, sprintf("F%04d", seq_len(fertility_expected_rows))
    )) {
        stop("merged full family membership is invalid")
    }
    if (accepted && (full_default || provenance$shard_count[[1L]] != "1" ||
        !identical(results$id, fertility_accepted_ids()))) {
        stop("merged accepted family membership is invalid")
    }
    list(
        results = results, summary = summary, family_manifest = manifest,
        input_attestation = input_attestation,
        provenance = provenance, full_default = full_default,
        evidence_family_id = provenance$evidence_family_id[[1L]],
        family_input_attestation_id = provenance$family_input_attestation_id[[1L]],
        merge_id = provenance$merge_id[[1L]],
        source_format = "current-merged-report-v2",
        source_id = provenance$merge_id[[1L]]
    )
}

fertility_manifest_character <- function(manifest, fields) {
    if (!is.data.frame(manifest) || !identical(names(manifest), fields)) {
        stop("manifest schema is not canonical")
    }
    result <- as.data.frame(lapply(manifest, as.character), stringsAsFactors = FALSE,
                            optional = TRUE)
    names(result) <- fields
    rownames(result) <- NULL
    result
}

fertility_validate_original_assessment_results <- function(results) {
    unsupported <- results$release == "111"
    supported_hash_errors <- results[
        !unsupported & results$classification == "inventory-hash-error",
        c("id", "secondary_categories"), drop = FALSE
    ]
    if (nrow(results) != fertility_expected_rows ||
        !all(results$classification[unsupported] == "expected-unsupported-111") ||
        any(results$classification[!unsupported] == "expected-unsupported-111") ||
        any(unsupported & results$classification == "inventory-hash-error") ||
        nrow(supported_hash_errors) != length(fertility_accepted_ids()) ||
        !identical(supported_hash_errors$id, fertility_accepted_ids()) ||
        !identical(supported_hash_errors$secondary_categories,
                   rep("signature-mismatch", length(fertility_accepted_ids())))) {
        stop("assessment original full family is not the preserved manifest-gated family")
    }
    invisible(TRUE)
}

fertility_assessment_legacy_source_identity <- function(
    provenance, results, summary, family_manifest
) {
    provenance_fields <- fertility_assessment_legacy_provenance_fields()
    provenance <- fertility_manifest_character(provenance, provenance_fields)
    results <- fertility_manifest_character(results, fertility_result_fields())
    summary <- fertility_manifest_character(summary, c("classification", "files"))
    family_manifest <- fertility_manifest_character(
        family_manifest, c("id", "program", "level", "release", "shard_index")
    )
    provenance_id <- fertility_manifest_id(
        provenance, provenance_fields, fertility_schema_version
    )
    results_id <- fertility_merged_results_id(results)
    summary_id <- fertility_manifest_id(
        summary, c("classification", "files"), fertility_report_schema_version
    )
    family_manifest_id <- fertility_manifest_id(family_manifest)
    source_id <- fertility_stable_id(list(
        source_contract = "assessment-legacy-original-schema10-report2-four-file-v1",
        provenance_id = provenance_id, results_id = results_id,
        summary_id = summary_id, family_manifest_id = family_manifest_id
    ))
    list(
        source_id = source_id, provenance_id = provenance_id,
        results_id = results_id, summary_id = summary_id,
        family_manifest_id = family_manifest_id
    )
}

fertility_validate_assessment_legacy_original_bundle <- function(
    bundle, family_id, canonical_inventory
) {
    required <- c("provenance", "results", "summary", "family_manifest")
    if (!is.list(bundle) || !identical(sort(names(bundle)), sort(required)) ||
        !all(vapply(bundle, is.data.frame, logical(1)))) {
        stop("legacy assessment original bundle schema is invalid")
    }
    provenance <- fertility_manifest_character(
        bundle$provenance, fertility_assessment_legacy_provenance_fields()
    )
    hash_fields <- c(
        "family_id", "evidence_family_id", "family_input_attestation_id",
        "framework_id", "config_id", "build_provenance_id", "inventory_id",
        "family_manifest_id", "report_schema_id"
    )
    if (nrow(provenance) != 1L ||
        !identical(provenance$family_id[[1L]], family_id) ||
        any(vapply(hash_fields, function(field) {
            !grepl("^[0-9a-f]{64}$", provenance[[field]][[1L]])
        }, logical(1))) ||
        !identical(provenance$schema_version[[1L]],
                   as.character(fertility_schema_version)) ||
        !identical(provenance$report_schema_version[[1L]],
                   as.character(fertility_report_schema_version)) ||
        !identical(provenance$evidence_origin[[1L]], "fresh-execution") ||
        !identical(provenance$source_corpus_schema_version[[1L]],
                   as.character(fertility_schema_version)) ||
        nzchar(provenance$replayed_at_utc[[1L]]) ||
        !identical(provenance$report_schema_id[[1L]], fertility_report_schema_id()) ||
        !identical(provenance$shard_count[[1L]], "8") ||
        !identical(provenance$files[[1L]],
                   as.character(fertility_expected_rows)) ||
        !identical(provenance$full_default_family[[1L]], "TRUE") ||
        !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$",
               provenance$created_at_utc[[1L]])) {
        stop("legacy assessment original provenance is invalid")
    }
    live_inventory_id <- fertility_inventory_id(canonical_inventory)
    canonical <- fertility_validate_canonical_inventory(
        fertility_inventory_manifest(canonical_inventory), exact = TRUE
    )
    if (!identical(provenance$inventory_id[[1L]], live_inventory_id)) {
        stop("legacy assessment original does not match canonical inventory authority")
    }
    expected_manifest <- canonical
    expected_manifest$shard_index <- fertility_shard_index(
        expected_manifest$id, canonical$id, 8L
    )
    manifest <- fertility_manifest_character(
        bundle$family_manifest,
        c("id", "program", "level", "release", "shard_index")
    )
    expected_manifest <- fertility_manifest_character(expected_manifest, names(manifest))
    if (!identical(manifest, expected_manifest) ||
        !identical(fertility_manifest_id(manifest),
                   provenance$family_manifest_id[[1L]])) {
        stop("legacy assessment original family manifest is not canonical")
    }
    expected_family_id <- fertility_family_id_from_manifest(
        manifest, provenance$framework_id[[1L]], provenance$config_id[[1L]],
        provenance$build_provenance_id[[1L]], provenance$inventory_id[[1L]],
        8L, Inf, provenance$report_schema_id[[1L]], "fresh-execution",
        fertility_schema_version
    )
    if (!identical(family_id, expected_family_id)) {
        stop("legacy assessment original family identity is invalid")
    }
    results <- fertility_manifest_character(bundle$results, fertility_result_fields())
    fertility_validate_public_results(results)
    if (nrow(results) != fertility_expected_rows ||
        !identical(results[c("id", "program", "level", "release")],
                   manifest[c("id", "program", "level", "release")]) ||
        any(results$framework_id != provenance$framework_id[[1L]]) ||
        any(results$build_provenance_id != provenance$build_provenance_id[[1L]])) {
        stop("legacy assessment original results are not bound to family provenance")
    }
    fertility_validate_original_assessment_results(results)
    summary <- fertility_manifest_character(
        bundle$summary, c("classification", "files")
    )
    expected_summary <- fertility_manifest_character(
        fertility_classification_summary(results), c("classification", "files")
    )
    if (!identical(summary, expected_summary)) {
        stop("legacy assessment original classification summary is invalid")
    }
    expected_evidence <- fertility_evidence_family_id(
        family_id, provenance$family_input_attestation_id[[1L]],
        "fresh-execution", fertility_schema_version,
        provenance$report_schema_id[[1L]]
    )
    if (!identical(provenance$evidence_family_id[[1L]], expected_evidence)) {
        stop("legacy assessment original evidence family identity is invalid")
    }
    identity <- fertility_assessment_legacy_source_identity(
        provenance, results, summary, manifest
    )
    list(
        results = results, summary = summary, family_manifest = manifest,
        input_attestation = NULL, provenance = provenance, full_default = TRUE,
        evidence_family_id = provenance$evidence_family_id[[1L]],
        family_input_attestation_id = provenance$family_input_attestation_id[[1L]],
        merge_id = "", source_format = "legacy-original-merged-report-v2",
        source_id = identity$source_id, source_content_ids = identity
    )
}

fertility_validate_shard_bundles <- function(bundles, family_id,
                                               canonical_inventory) {
    if (!length(bundles)) stop("no current shard reports found for family ID")
    required <- fertility_run_provenance_fields()
    acceptance_fields <- c(
        "acceptance_authority", "acceptance_commitment_id",
        "acceptance_artifact_sha256"
    )
    legacy_required <- setdiff(required, acceptance_fields)
    bundles <- lapply(bundles, function(bundle) {
        if (is.list(bundle) && is.data.frame(bundle$provenance) &&
            identical(names(bundle$provenance), legacy_required)) {
            for (field in acceptance_fields) bundle$provenance[[field]] <- ""
            bundle$provenance <- bundle$provenance[required]
        }
        bundle
    })
    if (any(vapply(bundles, function(bundle) {
        !is.list(bundle) || !is.data.frame(bundle$provenance) ||
            nrow(bundle$provenance) != 1L ||
            !identical(names(bundle$provenance), required) ||
            !is.data.frame(bundle$results) || !is.data.frame(bundle$family_manifest)
    }, logical(1)))) stop("shard report provenance schema is invalid")
    provenance <- do.call(rbind, lapply(bundles, `[[`, "provenance"))
    hash_fields <- c(
        "selection_id", "evidence_selection_id", "input_attestation_id",
        "family_id", "family_manifest_id", "framework_id", "config_id",
        "build_provenance_id", "inventory_id", "report_schema_id"
    )
    if (any(provenance$schema_version != as.character(fertility_schema_version)) ||
        any(provenance$report_schema_version !=
            as.character(fertility_report_schema_version)) ||
        any(vapply(hash_fields, function(field) {
            any(!grepl("^[0-9a-f]{64}$", provenance[[field]]))
        }, logical(1))) ||
        any(nzchar(provenance$acceptance_commitment_id) &
            !grepl("^[0-9a-f]{64}$", provenance$acceptance_commitment_id)) ||
        any(nzchar(provenance$acceptance_artifact_sha256) &
            !grepl("^[0-9a-f]{64}$", provenance$acceptance_artifact_sha256)) ||
        any(!provenance$retry %in% c("TRUE", "FALSE")) ||
        any(!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$",
                   provenance$created_at_utc))) {
        stop("shard report provenance contains an invalid scalar")
    }
    origins <- provenance$evidence_origin
    source_schemas <- provenance$source_corpus_schema_version
    replayed <- provenance$replayed_at_utc
    fresh <- origins == "fresh-execution"
    historical <- origins == "historical-schema-10-replay"
    timestamp <- "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
    accepted <- nzchar(provenance$acceptance_commitment_id)
    acceptance_valid <- (!accepted & !nzchar(provenance$acceptance_authority) &
                         !nzchar(provenance$acceptance_artifact_sha256)) |
        (accepted &
         provenance$acceptance_authority == fertility_acceptance_authority() &
         grepl("^[0-9a-f]{64}$", provenance$acceptance_artifact_sha256))
    if (!all(acceptance_valid) || length(unique(accepted)) != 1L) {
        stop("shard acceptance provenance is invalid")
    }
    if (any(!(fresh | historical)) ||
        any(fresh & (source_schemas != as.character(fertility_schema_version) |
                     nzchar(replayed))) ||
        any(historical & (
            source_schemas != as.character(fertility_legacy_corpus_schema_version) |
            !grepl(timestamp, replayed)
        ))) stop("shard evidence-origin provenance contains a false claim")
    if (any(provenance$family_id != family_id)) stop("shard report family ID disagrees")
    stable_fields <- c(
        "schema_version", "report_schema_version", "evidence_origin",
        "source_corpus_schema_version", "replayed_at_utc",
        "acceptance_authority", "acceptance_commitment_id",
        "acceptance_artifact_sha256", "family_id",
        "family_manifest_id", "framework_id",
        "config_id", "build_provenance_id", "inventory_id", "report_schema_id",
        "expected_family_files", "full_default_family", "program_filter",
        "release_filter", "id_filter", "encoding_overrides", "max_files",
        "shard_count", "timeout_seconds", "chunk_rows", "column_batch", "memory_mib",
        "cell_budget", "max_tiles_per_batch", "beyond_end_windows"
    )
    for (field in stable_fields) {
        if (length(unique(provenance[[field]])) != 1L) {
            stop("shard reports do not share identical framework/config/build/inventory")
        }
    }
    if (!identical(provenance$report_schema_id[[1L]], fertility_report_schema_id())) {
        stop("shard report schema identity is invalid")
    }
    boolean <- provenance$full_default_family[[1L]]
    if (!boolean %in% c("TRUE", "FALSE")) stop("invalid full-default provenance")
    full_default <- identical(boolean, "TRUE")
    integer_field <- function(field, positive = FALSE) {
        text <- provenance[[field]]
        pattern <- if (positive) "^[1-9][0-9]*$" else "^(0|[1-9][0-9]*)$"
        values <- suppressWarnings(as.integer(text))
        if (any(!grepl(pattern, text)) || anyNA(values)) {
            stop("invalid shard report accounting")
        }
        values
    }
    shard_count <- integer_field("shard_count", positive = TRUE)[[1L]]
    shard_indexes <- integer_field("shard_index", positive = TRUE)
    for (field in c("selected_files", "expected_family_files")) integer_field(field)
    for (field in c(
        "timeout_seconds", "chunk_rows", "column_batch", "memory_mib",
        "cell_budget", "max_tiles_per_batch", "beyond_end_windows"
    )) integer_field(field, positive = TRUE)
    if (shard_count < 1L || length(shard_indexes) != shard_count ||
        !identical(sort(shard_indexes), seq_len(shard_count))) {
        stop("shard reports do not contain every shard index exactly once")
    }
    ordering <- order(shard_indexes)
    bundles <- bundles[ordering]
    provenance <- provenance[ordering, , drop = FALSE]
    shard_indexes <- shard_indexes[ordering]
    canonical <- fertility_validate_canonical_inventory(canonical_inventory)
    options <- fertility_options_from_filter_spec(provenance[1L, , drop = FALSE])
    family_selection <- fertility_family_selection(canonical, options)
    fertility_validate_encoding_overrides(options$encoding_overrides, family_selection)
    for (field in c(
        "timeout_seconds", "chunk_rows", "column_batch", "memory_mib",
        "cell_budget", "max_tiles_per_batch", "beyond_end_windows"
    )) options[[field]] <- integer_field(field, positive = TRUE)[[1L]]
    acceptance <- if (accepted[[1L]]) list(
        authority = provenance$acceptance_authority[[1L]],
        commitment_id = provenance$acceptance_commitment_id[[1L]],
        artifact_sha256 = provenance$acceptance_artifact_sha256[[1L]]
    ) else NULL
    if (!identical(provenance$config_id[[1L]],
                   fertility_tile_configuration(options, acceptance)$config_id)) {
        stop("configuration provenance identity is invalid")
    }
    if (!identical(full_default, fertility_full_default_family(options))) {
        stop("full-default provenance disagrees with filter provenance")
    }
    if (accepted[[1L]] && identical(provenance$evidence_origin[[1L]],
                                    "historical-schema-10-replay")) {
        stop("historical replay cannot claim accepted-current-hash evidence")
    }
    if (identical(provenance$evidence_origin[[1L]],
                  "historical-schema-10-replay")) {
        replay_options <- fertility_parse_arguments(c(
            "--shard-index=1", "--shard-count=8", "--timeout-seconds=600",
            "--chunk-rows=50000", "--column-batch=32", "--memory-mib=1024",
            "--cell-budget=10000000", "--max-tiles-per-batch=100000",
            "--beyond-end-windows=1"
        ))
        exact_replay <- shard_count == 8L && full_default &&
            identical(provenance$config_id[[1L]],
                      fertility_tile_configuration(replay_options)$config_id) &&
            all(provenance$retry == "FALSE") &&
            identical(provenance$timeout_seconds[[1L]], "600") &&
            identical(provenance$chunk_rows[[1L]], "50000") &&
            identical(provenance$column_batch[[1L]], "32") &&
            identical(provenance$memory_mib[[1L]], "1024") &&
            identical(provenance$cell_budget[[1L]], "10000000") &&
            identical(provenance$max_tiles_per_batch[[1L]], "100000") &&
            identical(provenance$beyond_end_windows[[1L]], "1")
        if (!isTRUE(exact_replay)) {
            stop("historical schema-10 replay claim is not the exact eight-shard run")
        }
    }
    expected_family <- fertility_family_manifest(canonical, options)
    expected_family <- fertility_manifest_character(
        expected_family, c("id", "program", "level", "release", "shard_index")
    )
    manifests <- lapply(bundles, function(bundle) fertility_manifest_character(
        bundle$family_manifest,
        c("id", "program", "level", "release", "shard_index")
    ))
    for (manifest in manifests) {
        if (!identical(manifest, expected_family) ||
            !identical(fertility_manifest_id(manifest),
                       provenance$family_manifest_id[[1L]])) {
            stop("shard family manifest is not canonical")
        }
    }
    expected_family_id <- fertility_family_id_from_manifest(
        expected_family, provenance$framework_id[[1L]],
        provenance$config_id[[1L]], provenance$build_provenance_id[[1L]],
        provenance$inventory_id[[1L]], shard_count, provenance$max_files[[1L]],
        provenance$report_schema_id[[1L]], provenance$evidence_origin[[1L]],
        as.integer(provenance$source_corpus_schema_version[[1L]])
    )
    if (!identical(family_id, expected_family_id)) {
        stop("family ID is not bound to the canonical manifest")
    }
    expected_files <- integer_field("expected_family_files")[[1L]]
    if (nrow(expected_family) != expected_files) {
        stop("family manifest count disagrees with provenance")
    }
    selected_files <- integer_field("selected_files")
    if (anyDuplicated(provenance$selection_id)) stop("duplicate shard selection report")
    for (index in seq_along(bundles)) {
        results <- fertility_manifest_character(
            bundles[[index]]$results, fertility_result_fields()
        )
        fertility_validate_public_results(results)
        expected <- expected_family[
            expected_family$shard_index == as.character(shard_indexes[[index]]),
            c("id", "program", "level", "release"), drop = FALSE
        ]
        rownames(expected) <- NULL
        if (nrow(results) != selected_files[[index]] || nrow(results) != nrow(expected)) {
            stop("shard result count disagrees with canonical selection")
        }
        if (!identical(results[c("id", "program", "level", "release")], expected)) {
            stop("shard results do not match canonical family membership")
        }
        if (nrow(results) && (
            any(results$framework_id != provenance$framework_id[[index]]) ||
            any(results$build_provenance_id !=
                provenance$build_provenance_id[[index]])
        )) stop("shard result provenance disagrees with its bundle")
        expected_selection_id <- fertility_stable_id(list(
            family_id = family_id, shard_index = shard_indexes[[index]],
            selected_ids = paste(expected$id, collapse = ",")
        ))
        if (!identical(provenance$selection_id[[index]], expected_selection_id)) {
            stop("shard selection identity disagrees with canonical membership")
        }
        expected_evidence_selection_id <- fertility_evidence_selection_id(
            expected_selection_id, provenance$input_attestation_id[[index]],
            provenance$evidence_origin[[index]],
            as.integer(provenance$source_corpus_schema_version[[index]]),
            provenance$report_schema_id[[index]],
            provenance$acceptance_authority[[index]],
            provenance$acceptance_commitment_id[[index]]
        )
        if (!identical(provenance$evidence_selection_id[[index]],
                       expected_evidence_selection_id)) {
            stop("shard evidence selection identity is invalid")
        }
        bundles[[index]]$results <- results
    }
    results <- do.call(rbind, lapply(bundles, `[[`, "results"))
    results <- results[order(match(results$id, expected_family$id)), , drop = FALSE]
    rownames(results) <- NULL
    if (anyDuplicated(results$id) || nrow(results) != expected_files ||
        !identical(results[c("id", "program", "level", "release")],
                   expected_family[c("id", "program", "level", "release")])) {
        stop("shard reports do not provide exact family accounting")
    }
    if (accepted[[1L]]) {
        if (full_default || shard_count != 1L || length(options$programs) ||
            length(options$releases) || is.finite(options$max_files) ||
            !identical(sort(options$ids), fertility_accepted_ids()) ||
            !identical(results$id, fertility_accepted_ids()) ||
            any(results$classification %in% c(
                "inventory-hash-error", "expected-unsupported-111"
            ))) {
            stop("accepted-current-hash family is not the exact executable five-ID family")
        }
    }
    if (full_default && fertility_full_output_family(options)) {
        fertility_validate_full_output_results(results)
    } else if (full_default) {
        if (!identical(results$id, sprintf("F%04d", seq_len(fertility_expected_rows)))) {
            stop("full corpus IDs are not exactly F0001 through F1004")
        }
        release_counts <- table(factor(
            as.integer(results$release), levels = as.integer(names(fertility_expected_releases))
        ))
        if (!identical(as.integer(release_counts),
                       as.integer(fertility_expected_releases))) {
            stop("full corpus release counts are invalid")
        }
        unsupported <- !(as.integer(results$release) %in% fertility_supported_releases)
        if (!all(results$classification[unsupported] == "expected-unsupported-111")) {
            stop("unsupported release classifications are invalid")
        }
        supported <- !unsupported
        hash_errors <- results$classification[supported] == "inventory-hash-error"
        if (sum(hash_errors) != 5L || sum(!hash_errors) != nrow(results) - 5L ||
            any(results$classification[supported] == "expected-unsupported-111")) {
            stop("supported corpus executable accounting is invalid")
        }
    }
    list(results = results, provenance = provenance, shard_count = shard_count,
         full_default = full_default, family_manifest = expected_family)
}

fertility_validate_assessment_families <- function(full, accepted) {
    required <- c(
        "results", "provenance", "full_default", "evidence_family_id",
        "source_format", "source_id"
    )
    if (!is.list(full) || !is.list(accepted) ||
        !all(required %in% names(full)) || !all(required %in% names(accepted)) ||
        !full$source_format %in% c(
            "current-merged-report-v2", "legacy-original-merged-report-v2"
        ) || !identical(accepted$source_format, "current-merged-report-v2") ||
        !grepl("^[0-9a-f]{64}$", full$source_id) ||
        !grepl("^[0-9a-f]{64}$", accepted$source_id)) {
        stop("assessment family evidence is invalid")
    }
    fertility_validate_original_assessment_results(full$results)
    original_acceptance <- intersect(
        c("acceptance_authority", "acceptance_commitment_id",
          "acceptance_artifact_sha256"), names(full$provenance)
    )
    if (!isTRUE(full$full_default) ||
        (length(original_acceptance) && any(nzchar(unlist(
            full$provenance[original_acceptance], use.names = FALSE
        ))))) {
        stop("assessment original full family is not the preserved manifest-gated family")
    }
    if (isTRUE(accepted$full_default) || !is.data.frame(accepted$input_attestation) ||
        !identical(names(accepted$provenance), fertility_merge_provenance_fields()) ||
        !identical(names(accepted$input_attestation), c(
            "shard_index", "input_attestation_id", "evidence_selection_id"
        )) || !identical(accepted$results$id, fertility_accepted_ids()) ||
        any(accepted$results$classification %in% c(
            "inventory-hash-error", "expected-unsupported-111"
        )) || !all(nzchar(accepted$provenance$acceptance_commitment_id)) ||
        !all(accepted$provenance$acceptance_authority ==
             fertility_acceptance_authority()) ||
        !all(accepted$provenance$evidence_origin == "fresh-execution")) {
        stop("assessment accepted family is not valid explicit local evidence")
    }
    if (!identical(unique(full$provenance$inventory_id),
                   unique(accepted$provenance$inventory_id))) {
        stop("assessment families do not share inventory authority")
    }
    list(
        manifest_gate = "blocked-signature-mismatch",
        explicit_local_evidence_gate = "validated",
        acceptance_authority = accepted$provenance$acceptance_authority[[1L]],
        acceptance_commitment_id =
            accepted$provenance$acceptance_commitment_id[[1L]]
    )
}

fertility_framework_id <- function(provenance_id, datasigs_path,
                                   acceptance = NULL,
                                   schema_version = fertility_schema_version) {
    if (!is.numeric(schema_version) || length(schema_version) != 1L ||
        is.na(schema_version) || schema_version != as.integer(schema_version) ||
        !as.integer(schema_version) %in% c(
            fertility_schema_version, fertility_legacy_corpus_schema_version
        )) stop("framework corpus schema version is invalid")
    datasigs_sha256 <- tolower(as.character(openssl::sha256(file(datasigs_path))))
    fields <- list(
        schema_version = as.integer(schema_version),
        provenance_id = provenance_id,
        datasigs_sha256 = datasigs_sha256,
        comparator_tolerance = "1e-7"
    )
    if (!is.null(acceptance)) {
        fields$acceptance_authority <- acceptance$authority
        fields$acceptance_commitment_id <- acceptance$commitment_id
        fields$acceptance_artifact_sha256 <- acceptance$artifact_sha256
    }
    fertility_stable_id(fields)
}

fertility_validate_canonical_inventory <- function(manifest, exact = FALSE) {
    values <- fertility_manifest_character(
        manifest, c("id", "program", "level", "release")
    )
    if (any(!grepl("^F[0-9]{4}$", values$id)) || anyDuplicated(values$id) ||
        any(!values$program %in% fertility_programs) ||
        any(!values$level %in% fertility_levels) ||
        any(!grepl("^[1-9][0-9]*$", values$release))) {
        stop("canonical inventory manifest is invalid")
    }
    if (exact) {
        if (!identical(values$id, sprintf("F%04d", seq_len(fertility_expected_rows)))) {
            stop("canonical inventory IDs are not exactly F0001 through F1004")
        }
        release_counts <- table(factor(
            as.integer(values$release),
            levels = as.integer(names(fertility_expected_releases))
        ))
        if (any(!(as.integer(values$release) %in%
                  as.integer(names(fertility_expected_releases)))) ||
            !identical(as.integer(release_counts),
                       as.integer(fertility_expected_releases))) {
            stop("canonical inventory release counts are invalid")
        }
    }
    values
}

fertility_framework_inventory <- function(
    snapshot_root, inventory = NULL, framework_id = NULL,
    report_schema_version = fertility_report_schema_version
) {
    snapshot_parent <- dirname(snapshot_root)
    snapshot_root <- fertility_assert_existing_directory(
        snapshot_root, snapshot_parent, "framework snapshot"
    )
    manifest_path <- fertility_assert_existing_file(
        file.path(snapshot_root, "inventory-manifest.tsv"), snapshot_root,
        "canonical inventory manifest"
    )
    provenance_path <- fertility_assert_existing_file(
        file.path(snapshot_root, "inventory-manifest-provenance.tsv"), snapshot_root,
        "canonical inventory manifest provenance"
    )
    manifest <- read.delim(manifest_path, colClasses = "character",
                           check.names = FALSE)
    manifest <- fertility_validate_canonical_inventory(manifest, exact = FALSE)
    provenance <- read.delim(provenance_path, colClasses = "character",
                             check.names = FALSE)
    report_schema_version <- as.integer(report_schema_version)
    legacy <- identical(report_schema_version, fertility_legacy_report_schema_version)
    fields <- c(
        "schema_version",
        if (!legacy) "report_schema_version",
        "framework_id", "inventory_id", "inventory_manifest_id",
        "report_schema_id", "files"
    )
    corpus_schema_version <- if (legacy) fertility_legacy_corpus_schema_version else
        fertility_schema_version
    if (nrow(provenance) != 1L || !identical(names(provenance), fields) ||
        !identical(provenance$schema_version[[1L]],
                   as.character(corpus_schema_version)) ||
        (!legacy && !identical(provenance$report_schema_version[[1L]],
                               as.character(report_schema_version))) ||
        any(!grepl("^[0-9a-f]{64}$", unlist(provenance[c(
            "framework_id", "inventory_id", "inventory_manifest_id",
            "report_schema_id"
        )], use.names = FALSE))) ||
        !identical(provenance$inventory_manifest_id[[1L]],
                   fertility_manifest_id(
                       manifest, schema_version = corpus_schema_version
                   )) ||
        !identical(provenance$report_schema_id[[1L]],
                   fertility_report_schema_id(report_schema_version)) ||
        !identical(provenance$files[[1L]], as.character(nrow(manifest)))) {
        stop("canonical inventory manifest provenance is invalid")
    }
    if (!is.null(framework_id) &&
        !identical(provenance$framework_id[[1L]], framework_id)) {
        stop("canonical inventory manifest has a foreign framework")
    }
    if (!is.null(inventory)) {
        expected <- fertility_manifest_character(
            fertility_inventory_manifest(inventory), names(manifest)
        )
        if (!identical(manifest, expected) ||
            !identical(provenance$inventory_id[[1L]], fertility_inventory_id(inventory))) {
            stop("canonical inventory manifest does not match the live inventory")
        }
    }
    acceptance_path <- file.path(snapshot_root, "acceptance-provenance.tsv")
    acceptance_provenance <- NULL
    if (file.exists(acceptance_path) || dir.exists(acceptance_path) ||
        fertility_path_is_symlink(acceptance_path)) {
        acceptance_path <- fertility_assert_existing_file(
            acceptance_path, snapshot_root, "framework acceptance provenance"
        )
        acceptance_provenance <- read.delim(
            acceptance_path, colClasses = "character", check.names = FALSE
        )
        if (nrow(acceptance_provenance) != 1L || !identical(
            names(acceptance_provenance),
            c("authority", "commitment_id", "artifact_sha256")
        ) || !identical(acceptance_provenance$authority[[1L]],
                        fertility_acceptance_authority()) ||
            any(!grepl("^[0-9a-f]{64}$", unlist(
                acceptance_provenance[c("commitment_id", "artifact_sha256")],
                use.names = FALSE
            )))) stop("corpus framework acceptance provenance is invalid")
    }
    list(
        manifest = manifest, provenance = provenance,
        acceptance_provenance = acceptance_provenance
    )
}

fertility_prepare_framework_snapshot <- function(script_dir, raw_root, framework_id,
                                                 inventory, acceptance = NULL) {
    snapshot_root <- fertility_assert_output_parent(
        raw_root, "framework", framework_id, create = TRUE
    )
    Sys.chmod(c(file.path(raw_root, "framework"), snapshot_root), mode = "0700")
    for (name in c("common.R", "accepted.R", "worker.R", "compare.R", "runtime.R")) {
        source_path <- fertility_assert_existing_file(
            file.path(script_dir, name), script_dir, "framework source file"
        )
        snapshot_path <- file.path(snapshot_root, name)
        if (!file.exists(snapshot_path) && !dir.exists(snapshot_path) &&
            !fertility_path_is_symlink(snapshot_path)) {
            temporary <- tempfile(paste0(name, "."), tmpdir = snapshot_root)
            if (!file.copy(source_path, temporary, overwrite = TRUE)) {
                stop("could not snapshot corpus framework")
            }
            Sys.chmod(temporary, mode = "0600")
            fertility_assert_existing_file(
                temporary, snapshot_root, "temporary framework snapshot file"
            )
            fertility_assert_new_destination(
                snapshot_path, snapshot_root, "framework snapshot file"
            )
            if (!file.rename(temporary, snapshot_path)) {
                unlink(temporary)
                if (!file.exists(snapshot_path)) {
                    stop("could not publish corpus framework snapshot")
                }
            }
        }
        snapshot_path <- fertility_assert_existing_file(
            snapshot_path, snapshot_root, "framework snapshot file"
        )
        if (!identical(unname(tools::sha256sum(source_path)),
                       unname(tools::sha256sum(snapshot_path)))) {
            stop("corpus framework snapshot does not match its provenance")
        }
    }
    manifest <- fertility_inventory_manifest(inventory)
    manifest_provenance <- data.frame(
        schema_version = fertility_schema_version,
        report_schema_version = fertility_report_schema_version,
        framework_id = framework_id,
        inventory_id = fertility_inventory_id(inventory),
        inventory_manifest_id = fertility_manifest_id(manifest),
        report_schema_id = fertility_report_schema_id(),
        files = nrow(manifest), stringsAsFactors = FALSE, check.names = FALSE
    )
    manifest_path <- file.path(snapshot_root, "inventory-manifest.tsv")
    provenance_path <- file.path(snapshot_root, "inventory-manifest-provenance.tsv")
    if (!file.exists(manifest_path) && !dir.exists(manifest_path) &&
        !fertility_path_is_symlink(manifest_path)) {
        fertility_assert_new_destination(
            manifest_path, snapshot_root, "canonical inventory manifest"
        )
        fertility_atomic_write_table(manifest, manifest_path)
    } else fertility_assert_existing_file(
        manifest_path, snapshot_root, "canonical inventory manifest"
    )
    if (!file.exists(provenance_path) && !dir.exists(provenance_path) &&
        !fertility_path_is_symlink(provenance_path)) {
        fertility_assert_new_destination(
            provenance_path, snapshot_root,
            "canonical inventory manifest provenance"
        )
        fertility_atomic_write_table(manifest_provenance, provenance_path)
    } else fertility_assert_existing_file(
        provenance_path, snapshot_root,
        "canonical inventory manifest provenance"
    )
    acceptance_path <- file.path(snapshot_root, "acceptance-provenance.tsv")
    if (!is.null(acceptance)) {
        acceptance_provenance <- data.frame(
            authority = acceptance$authority,
            commitment_id = acceptance$commitment_id,
            artifact_sha256 = acceptance$artifact_sha256,
            stringsAsFactors = FALSE, check.names = FALSE
        )
        if (!file.exists(acceptance_path) && !dir.exists(acceptance_path) &&
            !fertility_path_is_symlink(acceptance_path)) {
            fertility_assert_new_destination(
                acceptance_path, snapshot_root, "framework acceptance provenance"
            )
            fertility_atomic_write_table(acceptance_provenance, acceptance_path)
        }
        acceptance_path <- fertility_assert_existing_file(
            acceptance_path, snapshot_root, "framework acceptance provenance"
        )
        recorded_acceptance <- read.delim(
            acceptance_path, colClasses = "character", check.names = FALSE
        )
        if (!identical(recorded_acceptance, acceptance_provenance)) {
            stop("corpus framework acceptance provenance is invalid")
        }
    } else if (file.exists(acceptance_path)) {
        stop("unaccepted corpus framework contains acceptance provenance")
    }
    invisible(fertility_framework_inventory(
        snapshot_root, inventory = inventory, framework_id = framework_id
    ))
    snapshot_root
}

fertility_verify_framework_snapshot <- function(script_dir, raw_root, framework_id,
                                                inventory = NULL,
                                                acceptance = NULL) {
    framework_root <- fertility_assert_existing_directory(
        file.path(raw_root, "framework"), raw_root, "framework output directory"
    )
    snapshot_root <- fertility_assert_existing_directory(
        file.path(framework_root, framework_id), framework_root,
        "framework snapshot"
    )
    for (name in c("common.R", "accepted.R", "worker.R", "compare.R", "runtime.R")) {
        source_path <- file.path(script_dir, name)
        snapshot_path <- fertility_assert_existing_file(
            file.path(snapshot_root, name), snapshot_root,
            "framework snapshot file"
        )
        if (!identical(unname(tools::sha256sum(source_path)),
                       unname(tools::sha256sum(snapshot_path)))) {
            stop("corpus framework snapshot does not match its provenance")
        }
    }
    acceptance_path <- file.path(snapshot_root, "acceptance-provenance.tsv")
    if (is.null(acceptance)) {
        if (file.exists(acceptance_path)) {
            stop("unaccepted corpus framework contains acceptance provenance")
        }
    } else {
        recorded <- if (file.exists(acceptance_path) && !dir.exists(acceptance_path)) {
            acceptance_path <- fertility_assert_existing_file(
                acceptance_path, snapshot_root, "framework acceptance provenance"
            )
            read.delim(
                acceptance_path, colClasses = "character", check.names = FALSE
            )
        } else NULL
        expected <- data.frame(
            authority = acceptance$authority,
            commitment_id = acceptance$commitment_id,
            artifact_sha256 = acceptance$artifact_sha256,
            stringsAsFactors = FALSE, check.names = FALSE
        )
        if (is.null(recorded) || !identical(recorded, expected)) {
            stop("corpus framework acceptance provenance is invalid")
        }
    }
    invisible(fertility_framework_inventory(
        snapshot_root, inventory = inventory, framework_id = framework_id
    ))
    snapshot_root
}

fertility_tile_configuration <- function(options, acceptance = NULL) {
    fields <- list(
        chunk_rows = options$chunk_rows, column_batch = options$column_batch,
        memory_mib = options$memory_mib, cell_budget = options$cell_budget,
        max_tiles_per_batch = options$max_tiles_per_batch,
        beyond_end_windows = options$beyond_end_windows,
        timeout_seconds = options$timeout_seconds, object_overhead_bytes = 64L,
        readers_per_tile = 3L, strl_sample_count = 16L,
        strl_safety_factor = 8, strl_fallback_rows = 64L
    )
    encoding_overrides <- fertility_encoding_overrides_text(
        options$encoding_overrides
    )
    identity_fields <- fields
    if (nzchar(encoding_overrides)) {
        identity_fields$encoding_overrides <- encoding_overrides
    }
    acceptance_fields <- list()
    if (!is.null(acceptance)) {
        acceptance_fields <- list(
            acceptance_authority = acceptance$authority,
            acceptance_commitment_id = acceptance$commitment_id,
            acceptance_artifact_sha256 = acceptance$artifact_sha256
        )
        identity_fields <- c(identity_fields, acceptance_fields)
    }
    c(fields, list(encoding_overrides = encoding_overrides), acceptance_fields, list(
        config_id = fertility_stable_id(identity_fields)
    ))
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

fertility_strl_sample_offsets <- function(total_rows, sample_count) {
    if (!is.finite(total_rows) || total_rows < 0) stop("invalid structural row count")
    sample_count <- as.integer(sample_count)
    if (sample_count < 1L) stop("strL sample count must be positive")
    if (total_rows == 0) return(0)
    count <- min(as.double(sample_count), total_rows)
    unique(floor(seq(0, total_rows - 1, length.out = count)))
}

fertility_strl_rows <- function(payload_bytes_per_row, column_count, configuration) {
    payload <- as.double(payload_bytes_per_row)
    if (length(payload) != 1L || is.na(payload) || payload < 0) {
        return(as.integer(min(configuration$chunk_rows,
                              configuration$strl_fallback_rows)))
    }
    readers <- as.double(configuration$readers_per_tile)
    overhead <- readers * as.double(configuration$object_overhead_bytes) *
        max(1, as.double(column_count))
    estimated <- max(1, payload + overhead)
    memory_bytes <- as.double(configuration$memory_mib) * 1024^2
    by_memory <- floor(memory_bytes /
                       (as.double(configuration$strl_safety_factor) * estimated))
    by_cells <- floor(as.double(configuration$cell_budget) /
                      (readers * max(1, as.double(column_count))))
    as.integer(max(1, min(configuration$chunk_rows, by_memory, by_cells)))
}

fertility_metadata_tile <- function() {
    list(tile_id = "metadata", type = "metadata", batch = 0L, skip = 0L,
         n_max = 0L, column_names = character(), column_hash = "all")
}

fertility_sizing_tile <- function(batch, column_names, total_rows,
                                  sample_count) {
    offsets <- fertility_strl_sample_offsets(total_rows, sample_count)
    list(
        tile_id = sprintf("b%05d-sizing", as.integer(batch)),
        type = "sizing", batch = as.integer(batch), skip = 0, n_max = 1L,
        column_names = column_names, sample_offsets = as.double(offsets),
        column_hash = fertility_stable_id(list(
            batch = as.integer(batch), type = "sizing",
            names = paste(column_names, collapse = "\037"),
            sample_offsets = paste(format(offsets, scientific = FALSE), collapse = ",")
        ))
    )
}

fertility_value_tile <- function(batch, skip, n_max, column_names,
                                 type = "value", probe = 0L) {
    list(
        tile_id = sprintf("b%05d-%s%02d-r%015.0f-n%010d", as.integer(batch),
                          if (identical(type, "value")) "v" else "p",
                          as.integer(probe), as.double(skip), as.integer(n_max)),
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

fertility_process_adaptive_range <- function(batch, skip, n_max, column_names,
                                             process, split_budget) {
    tile <- fertility_value_tile(batch, skip, n_max, column_names)
    result <- process(tile)
    if (identical(result$classification, "memory-limit") && n_max > 1L &&
        split_budget$remaining >= 2L) {
        # The failed parent was already executed; splitting launches two more
        # subprocess tiles, so consume two execution credits.
        split_budget$remaining <- split_budget$remaining - 2L
        left <- as.integer(floor(n_max / 2L))
        right <- as.integer(n_max - left)
        return(c(
            fertility_process_adaptive_range(
                batch, skip, left, column_names, process, split_budget
            ),
            fertility_process_adaptive_range(
                batch, as.double(skip) + left, right, column_names,
                process, split_budget
            )
        ))
    }
    list(result)
}

fertility_recorded_result_valid <- function(
    result, item, framework_id, configuration,
    corpus_schema_version = fertility_schema_version
) {
    required <- c(
        "schema_version", "framework_id", "config_id", "input_id", "id",
        "program", "level", "release", "expected_sha512", "timeout_seconds",
        "classification", "secondary_categories", "mismatch_count",
        "mismatch_categories", "mismatch_signatures", "rows", "columns",
        "tiles_expected", "tiles_completed", "complete", "actual_sha512",
        "elapsed_seconds"
    )
    acceptance_fields <- c(
        "acceptance_authority", "acceptance_commitment_id",
        "acceptance_artifact_sha256", "accepted_sha512",
        "manifest_hash_status", "local_evidence_status"
    )
    accepted <- all(acceptance_fields %in% names(result))
    schema_valid <- setequal(
        names(result), c(required, if (accepted) acceptance_fields else character())
    )
    acceptance_valid <- !accepted || (
        identical(result$acceptance_authority, fertility_acceptance_authority()) &&
        grepl("^[0-9a-f]{64}$", result$acceptance_commitment_id) &&
        grepl("^[0-9a-f]{64}$", result$acceptance_artifact_sha256) &&
        grepl("^[0-9a-f]{128}$", result$accepted_sha512) &&
        identical(result$manifest_hash_status, "signature-mismatch") &&
        identical(result$local_evidence_status,
                  "accepted-current-sha512-match")
    )
    is.list(result) && schema_valid && acceptance_valid &&
        identical(result$schema_version, as.integer(corpus_schema_version)) &&
        identical(result$framework_id, framework_id) &&
        identical(result$config_id, configuration$config_id) &&
        is.character(result$input_id) && length(result$input_id) == 1L &&
        grepl("^[0-9a-f]{64}$", result$input_id) &&
        identical(result$id, item$id) && identical(result$program, item$program) &&
        identical(result$level, item$level) &&
        identical(as.integer(result$release), as.integer(item$release)) &&
        is.character(result$expected_sha512) && length(result$expected_sha512) == 1L &&
        grepl("^([0-9a-f]{128})?$", result$expected_sha512) &&
        ((is.character(result$actual_sha512) &&
          length(result$actual_sha512) == 1L &&
          grepl("^[0-9a-f]{128}$", result$actual_sha512)) ||
         (is.character(result$actual_sha512) &&
          length(result$actual_sha512) == 1L &&
          is.na(result$actual_sha512) &&
          identical(result$classification, "inventory-hash-error") &&
          identical(result$secondary_categories, "hash-read-error"))) &&
        identical(as.integer(result$timeout_seconds),
                  as.integer(configuration$timeout_seconds)) &&
        is.character(result$classification) && length(result$classification) == 1L &&
        result$classification %in% fertility_classifications() &&
        is.logical(result$complete) && length(result$complete) == 1L &&
        !is.na(result$complete)
}

fertility_validate_recorded_input_attestation <- function(result) {
    expected <- result$expected_sha512
    actual <- result$actual_sha512
    expected_valid <- is.character(expected) && length(expected) == 1L &&
        grepl("^([0-9a-f]{128})?$", expected)
    actual_missing <- is.character(actual) && length(actual) == 1L &&
        is.na(actual)
    actual_valid <- is.character(actual) && length(actual) == 1L &&
        !is.na(actual) && grepl("^[0-9a-f]{128}$", actual)
    input_id_valid <- is.character(result$input_id) && length(result$input_id) == 1L &&
        grepl("^[0-9a-f]{64}$", result$input_id)
    inventory_hash_error <- identical(
        result$classification, "inventory-hash-error"
    )
    reasons <- c(
        "hash-read-error", "signature-mismatch", "input-changed"
    )
    reason <- if (is.character(result$secondary_categories) &&
                  length(result$secondary_categories) == 1L &&
                  result$secondary_categories %in% reasons) {
        result$secondary_categories
    } else ""
    accepted <- all(c(
        "acceptance_authority", "acceptance_commitment_id",
        "acceptance_artifact_sha256", "accepted_sha512",
        "manifest_hash_status", "local_evidence_status"
    ) %in% names(result))
    accepted_valid <- accepted &&
        identical(result$acceptance_authority, fertility_acceptance_authority()) &&
        grepl("^[0-9a-f]{64}$", result$acceptance_commitment_id) &&
        grepl("^[0-9a-f]{64}$", result$acceptance_artifact_sha256) &&
        grepl("^[0-9a-f]{128}$", result$accepted_sha512) &&
        identical(result$manifest_hash_status, "signature-mismatch") &&
        identical(result$local_evidence_status,
                  "accepted-current-sha512-match") &&
        expected_valid && nzchar(expected) && actual_valid &&
        !identical(actual, expected) && identical(actual, result$accepted_sha512)
    valid_reason <- switch(
        reason,
        "hash-read-error" = actual_missing,
        "signature-mismatch" = expected_valid && nzchar(expected) &&
            actual_valid && !identical(actual, expected),
        "input-changed" = expected_valid && actual_valid && input_id_valid,
        if (accepted) accepted_valid else expected_valid && actual_valid &&
            (!nzchar(expected) || identical(actual, expected))
    )
    if (!input_id_valid ||
        !identical(inventory_hash_error, nzchar(reason)) || !valid_reason) {
        stop("recorded input preflight attestation is inconsistent")
    }
    invisible(TRUE)
}

fertility_validate_recorded_input_result <- function(result, tile_count) {
    fertility_validate_recorded_input_attestation(result)
    if (!identical(result$classification, "inventory-hash-error") ||
        !is.integer(tile_count) || length(tile_count) != 1L ||
        is.na(tile_count) || tile_count < 0L ||
        (!identical(result$secondary_categories, "input-changed") &&
         tile_count != 0L) ||
        !identical(result$complete, FALSE) ||
        !identical(result$mismatch_count, 0L)) {
        stop("recorded input-validation result is inconsistent")
    }
    invisible(TRUE)
}

fertility_input_attestation_id <- function(results) {
    if (!length(results)) return(fertility_stable_id(list(cases = "")))
    ids <- vapply(results, `[[`, character(1), "id")
    if (anyDuplicated(ids) || !identical(ids, sort(ids))) {
        stop("input attestations are not in canonical case order")
    }
    commitments <- vapply(results, function(result) {
        fertility_validate_recorded_input_attestation(result)
        accepted <- "acceptance_commitment_id" %in% names(result)
        status <- if (identical(result$classification, "inventory-hash-error")) {
            result$secondary_categories
        } else if (accepted) {
            "explicit-local-current-sha512"
        } else if (nzchar(result$expected_sha512)) {
            "verified-signature"
        } else "verified-empty-expected"
        fields <- list(
            id = result$id, input_id = result$input_id,
            expected_sha512 = result$expected_sha512,
            actual_sha512 = if (is.na(result$actual_sha512)) "" else
                result$actual_sha512,
            status = status
        )
        if (accepted) {
            fields$acceptance_authority <- result$acceptance_authority
            fields$acceptance_commitment_id <- result$acceptance_commitment_id
            fields$acceptance_artifact_sha256 <- result$acceptance_artifact_sha256
            fields$accepted_sha512 <- result$accepted_sha512
            fields$manifest_hash_status <- result$manifest_hash_status
            fields$local_evidence_status <- result$local_evidence_status
        }
        fertility_stable_id(fields)
    }, character(1))
    fertility_stable_id(list(
        ids = paste(ids, collapse = ","),
        commitments = paste(commitments, collapse = ",")
    ))
}

fertility_evidence_selection_id <- function(
    selection_id, input_attestation_id, evidence_origin,
    source_corpus_schema_version, report_schema_id,
    acceptance_authority = "", acceptance_commitment_id = ""
) {
    fields <- list(
        selection_id = selection_id, input_attestation_id = input_attestation_id,
        evidence_origin = evidence_origin,
        source_corpus_schema_version = as.integer(source_corpus_schema_version),
        report_schema_id = report_schema_id
    )
    if (nzchar(acceptance_commitment_id)) {
        fields$acceptance_authority <- acceptance_authority
        fields$acceptance_commitment_id <- acceptance_commitment_id
    }
    fertility_stable_id(fields)
}

fertility_family_input_attestation <- function(provenance) {
    fields <- c("shard_index", "input_attestation_id", "evidence_selection_id")
    if (!is.data.frame(provenance) || !all(fields %in% names(provenance))) {
        stop("family input attestation provenance is invalid")
    }
    attestation <- fertility_manifest_character(provenance[fields], fields)
    indexes <- suppressWarnings(as.integer(attestation$shard_index))
    ordering <- order(indexes)
    if (anyNA(indexes) || !identical(indexes[ordering], seq_along(indexes)) ||
        any(!grepl("^[0-9a-f]{64}$", attestation$input_attestation_id)) ||
        any(!grepl("^[0-9a-f]{64}$", attestation$evidence_selection_id))) {
        stop("family input attestations are not in canonical shard order")
    }
    attestation[ordering, , drop = FALSE]
}

fertility_family_input_attestation_id <- function(provenance) {
    attestation <- fertility_family_input_attestation(provenance)
    fertility_stable_id(list(
        shard_indexes = paste(attestation$shard_index, collapse = ","),
        input_attestation_ids = paste(
            attestation$input_attestation_id, collapse = ","
        ),
        evidence_selection_ids = paste(
            attestation$evidence_selection_id, collapse = ","
        )
    ))
}

fertility_prepare_report_stages <- function(
    items, create_stage, write_stage, remove_path, path_exists
) {
    stages <- list()
    complete <- FALSE
    on.exit(if (!complete) {
        cleanup_ok <- TRUE
        for (stage in rev(stages)) {
            removed <- isTRUE(remove_path(stage$stage)) || !path_exists(stage$stage)
            cleanup_ok <- cleanup_ok && removed
        }
        if (!cleanup_ok) warning("report staging cleanup did not remove every stage")
    }, add = TRUE)
    for (item in items) {
        stage <- create_stage(item)
        if (!is.list(stage) || is.null(stage$stage)) {
            stop("could not create report stage")
        }
        stages[[length(stages) + 1L]] <- stage
        if (!isTRUE(write_stage(stage, item))) stop("could not write report stage")
    }
    complete <- TRUE
    stages
}

fertility_publish_pointer_transaction <- function(
    stages, rename_path, write_pointer, remove_path, pointer_state, path_exists,
    before_rename = function(index, stage) TRUE,
    before_pointer = function(index, stage) TRUE
) {
    renamed <- integer()
    for (index in seq_along(stages)) {
        ready <- tryCatch(
            before_rename(index, stages[[index]]), error = function(error) FALSE
        )
        if (!isTRUE(ready) ||
            !isTRUE(rename_path(stages[[index]]$stage, stages[[index]]$published))) {
            for (rollback in rev(renamed)) remove_path(stages[[rollback]]$published)
            if (any(vapply(stages[renamed], function(stage) {
                path_exists(stage$published)
            }, logical(1)))) stop("report bundle rename rollback failed")
            stop("could not atomically publish every report bundle")
        }
        renamed <- c(renamed, index)
    }
    pointed <- integer()
    pointer_failure <- FALSE
    for (index in seq_along(stages)) {
        ready <- tryCatch(
            before_pointer(index, stages[[index]]), error = function(error) FALSE
        )
        if (!isTRUE(ready) || !isTRUE(write_pointer(
            stages[[index]]$parent, basename(stages[[index]]$published)
        ))) {
            pointer_failure <- TRUE
            break
        }
        pointed <- c(pointed, index)
    }
    if (!pointer_failure) return(invisible(TRUE))
    rollback_ok <- TRUE
    for (index in rev(pointed)) {
        stage <- stages[[index]]
        restored <- if (is.na(stage$old_current)) {
            isTRUE(remove_path(file.path(stage$parent, "CURRENT"))) ||
                is.na(pointer_state(stage$parent))
        } else isTRUE(write_pointer(stage$parent, stage$old_current))
        rollback_ok <- rollback_ok && restored
    }
    for (index in rev(renamed)) {
        removed <- isTRUE(remove_path(stages[[index]]$published)) ||
            !path_exists(stages[[index]]$published)
        rollback_ok <- rollback_ok && removed
    }
    states_ok <- vapply(stages, function(stage) {
        identical(pointer_state(stage$parent), stage$old_current) &&
            !path_exists(stage$published)
    }, logical(1))
    if (!rollback_ok || !all(states_ok)) {
        stop("report publication rollback did not restore every prior state")
    }
    stop("could not atomically publish every republished shard pointer")
}

fertility_evidence_family_id <- function(
    family_id, family_input_attestation_id, evidence_origin,
    source_corpus_schema_version, report_schema_id,
    acceptance_authority = "", acceptance_commitment_id = ""
) {
    fields <- list(
        family_id = family_id,
        family_input_attestation_id = family_input_attestation_id,
        evidence_origin = evidence_origin,
        source_corpus_schema_version = as.integer(source_corpus_schema_version),
        report_schema_id = report_schema_id
    )
    if (nzchar(acceptance_commitment_id)) {
        fields$acceptance_authority <- acceptance_authority
        fields$acceptance_commitment_id <- acceptance_commitment_id
    }
    fertility_stable_id(fields)
}

fertility_validate_recorded_tile <- function(
    checkpoint, corpus_schema_version = fertility_schema_version,
    allow_legacy_empty_reader_artifact = FALSE
) {
    explicit_corpus_schema <- !missing(corpus_schema_version)
    common <- c(
        "schema_version", "framework_id", "config_id", "input_id", "id",
        "tile_id", "tile_type", "batch", "skip", "n_max", "column_hash",
        "timeout_seconds", "classification", "secondary", "mismatches", "rows",
        "reader_rows", "columns", "column_names", "storage", "structural_rows",
        "column_bytes", "strl", "projection_expected_count",
        "projection_expected_hash", "projection_counts", "projection_hashes",
        "projection_ok", "elapsed_seconds"
    )
    sizing_extra <- c(
        "program", "level", "release", "expected_sha512", "samples_requested",
        "samples_completed", "payload_bytes_per_row", "chosen_rows",
        "sample_offsets_hash"
    )
    acceptance_extra <- c(
        "acceptance_authority", "acceptance_commitment_id",
        "acceptance_artifact_sha256"
    )
    if (!is.list(checkpoint) || !checkpoint$tile_type %in%
        c("metadata", "value", "terminal", "sizing")) {
        stop("recorded tile checkpoint schema is invalid")
    }
    accepted <- all(acceptance_extra %in% names(checkpoint))
    expected <- c(
        common, if (identical(checkpoint$tile_type, "sizing")) sizing_extra,
        if (accepted) acceptance_extra
    )
    acceptance_valid <- !accepted || (
        identical(checkpoint$acceptance_authority,
                  fertility_acceptance_authority()) &&
        grepl("^[0-9a-f]{64}$", checkpoint$acceptance_commitment_id) &&
        grepl("^[0-9a-f]{64}$", checkpoint$acceptance_artifact_sha256)
    )
    if (!setequal(names(checkpoint), expected) || !acceptance_valid ||
        !identical(checkpoint$schema_version, as.integer(corpus_schema_version)) ||
        !is.character(checkpoint$input_id) || length(checkpoint$input_id) != 1L ||
        !grepl("^[0-9a-f]{64}$", checkpoint$input_id) ||
        !is.character(checkpoint$classification) ||
        length(checkpoint$classification) != 1L ||
        !checkpoint$classification %in% c(
            fertility_classifications(), "input-changed"
        ) || !is.character(checkpoint$secondary) || anyNA(checkpoint$secondary)) {
        stop("recorded tile checkpoint schema is invalid")
    }
    legacy_artifact <- checkpoint$secondary == "-reader-error"
    legacy_artifact_allowed <- isTRUE(allow_legacy_empty_reader_artifact) &&
        explicit_corpus_schema &&
        identical(as.integer(corpus_schema_version),
                  fertility_legacy_corpus_schema_version)
    allowed_secondary <- c(
        fertility_classifications(), fertility_mismatch_categories(),
        "direct-reader-error", "rust-reader-error", "haven-reader-error",
        "metadata-reader-error", "row-termination-mismatch",
        "structural-metadata-unavailable", "input-changed"
    )
    if ((any(legacy_artifact) && !legacy_artifact_allowed) ||
        any(!legacy_artifact & !checkpoint$secondary %in% allowed_secondary) ||
        !is.data.frame(checkpoint$mismatches) ||
        !identical(names(checkpoint$mismatches),
                   c("category", "detail", "component", "pair"))) {
        stop("recorded tile checkpoint contains malformed or non-canonical detail")
    }
    mismatches <- checkpoint$mismatches
    input_changed <- identical(checkpoint$classification, "input-changed")
    input_changed_secondary <- any(checkpoint$secondary == "input-changed")
    if ((input_changed && !identical(checkpoint$secondary, "input-changed")) ||
        (!input_changed && input_changed_secondary) ||
        (input_changed && nrow(mismatches))) {
        stop("recorded tile checkpoint contains malformed or non-canonical detail")
    }
    if (nrow(mismatches) && (
        any(!mismatches$category %in% fertility_mismatch_categories()) ||
        anyNA(mismatches$detail) || !is.character(mismatches$detail) ||
        any(!is.na(mismatches$component) &
            (!is.finite(mismatches$component) | mismatches$component < 1)) ||
        any(!is.na(mismatches$pair) & !mismatches$pair %in%
            c("direct-rust", "direct-haven", "rust-haven"))
    )) stop("recorded tile checkpoint contains malformed or non-canonical detail")
    invisible(TRUE)
}

fertility_replay_file_tiles <- function(
    item, file_root, framework_id, configuration, input,
    corpus_schema_version = fertility_schema_version,
    allow_legacy_empty_reader_artifact = FALSE
) {
    file_parent <- dirname(file_root)
    file_root <- fertility_assert_existing_directory(
        file_root, file_parent, "checkpoint case directory"
    )
    tile_root <- fertility_assert_existing_directory(
        file.path(file_root, "tiles"), file_root, "checkpoint tile directory"
    )
    load_tile <- function(tile, path) {
        path <- fertility_assert_existing_file(
            path, tile_root, "checkpoint tile file"
        )
        checkpoint <- tryCatch(readRDS(path), error = function(error) NULL)
        if (is.null(checkpoint)) stop("recorded tile checkpoint is absent or invalid")
        fertility_validate_recorded_tile(
            checkpoint, corpus_schema_version,
            allow_legacy_empty_reader_artifact
        )
        if (!fertility_tile_checkpoint_valid(
            checkpoint, item, tile, framework_id, configuration$config_id,
            input$input_id, configuration$timeout_seconds,
            corpus_schema_version = corpus_schema_version
        )) stop("recorded tile checkpoint is absent or invalid")
        checkpoint
    }
    metadata_tile <- fertility_metadata_tile()
    metadata <- load_tile(metadata_tile, file.path(tile_root, "metadata.rds"))
    tiles <- list(metadata)
    column_names <- metadata$column_names
    column_bytes <- metadata$column_bytes
    batches <- fertility_structural_batches(
        column_names, configuration$column_batch, column_bytes, metadata$columns
    )
    total_rows <- metadata$structural_rows
    structurally_valid <- is.finite(total_rows) && total_rows >= 0 &&
        identical(as.integer(metadata$columns), as.integer(length(column_names))) &&
        length(column_bytes) == length(column_names)
    planning_failure <- function(batch, detail) list(
        schema_version = as.integer(corpus_schema_version), framework_id = framework_id,
        id = item$id, tile_id = paste0("planning-", batch), tile_type = "planning",
        batch = as.integer(batch), skip = 0, n_max = 0L,
        classification = "unresolved", secondary = detail,
        mismatches = data.frame(
            category = "unresolved", detail = detail, component = NA_integer_,
            pair = NA_character_, stringsAsFactors = FALSE
        ), rows = NA_integer_, elapsed_seconds = 0
    )
    if (length(batches) && isTRUE(structurally_valid)) {
        for (batch in seq_along(batches)) {
            bytes <- fertility_batch_bytes(
                batches[[batch]], column_names, column_bytes
            )
            rows_per_tile <- fertility_adaptive_rows(bytes, configuration)
            is_strl_batch <- any(!is.finite(bytes))
            if (is_strl_batch) {
                sizing_tile <- fertility_sizing_tile(
                    batch, batches[[batch]], total_rows,
                    configuration$strl_sample_count
                )
                sizing <- load_tile(
                    sizing_tile, file.path(tile_root, paste0(sizing_tile$tile_id, ".rds"))
                )
                expected_rows <- fertility_strl_rows(
                    sizing$payload_bytes_per_row, length(sizing_tile$column_names),
                    configuration
                )
                if (!identical(as.integer(sizing$chosen_rows), expected_rows)) {
                    stop("recorded strL sizing checkpoint is inconsistent")
                }
                rows_per_tile <- expected_rows
            }
            reserved_probes <- if (batch == 1L)
                configuration$beyond_end_windows else 0L
            available_tiles <- configuration$max_tiles_per_batch - reserved_probes -
                if (is_strl_batch) 1L else 0L
            if (available_tiles < 1L) {
                tiles[[length(tiles) + 1L]] <- planning_failure(
                    batch, "tile-ceiling-reached"
                )
                next
            }
            plan <- fertility_plan_offsets(total_rows, rows_per_tile, available_tiles)
            if (plan$ceiling) {
                tiles[[length(tiles) + 1L]] <- planning_failure(
                    batch, "tile-ceiling-reached"
                )
                next
            }
            split_budget <- new.env(parent = emptyenv())
            split_budget$remaining <- as.integer(available_tiles - length(plan$offsets))
            process <- function(tile) load_tile(
                tile, file.path(tile_root, paste0(tile$tile_id, ".rds"))
            )
            for (offset in plan$offsets) {
                requested <- if (total_rows == 0) 1L else as.integer(min(
                    rows_per_tile, total_rows - offset
                ))
                tiles <- c(tiles, fertility_process_adaptive_range(
                    batch, offset, requested, batches[[batch]], process, split_budget
                ))
            }
            if (batch == 1L) for (probe in seq_len(configuration$beyond_end_windows)) {
                tile <- fertility_value_tile(
                    batch, total_rows + (probe - 1L), 1L, batches[[batch]],
                    type = "terminal", probe = probe
                )
                tiles[[length(tiles) + 1L]] <- load_tile(
                    tile, file.path(tile_root, paste0(tile$tile_id, ".rds"))
                )
            }
        }
    } else if (length(batches)) {
        tiles[[length(tiles) + 1L]] <- planning_failure(
            0L, "structural-metadata-unavailable"
        )
    }
    list(tiles = tiles, batches = batches, total_rows = total_rows)
}

fertility_memory_error <- function(error) {
    grepl("vector memory exhausted|cannot allocate|memory limit|out of memory",
          conditionMessage(error), ignore.case = TRUE)
}

fertility_tile_checkpoint_valid <- function(
    checkpoint, item, tile, framework_id, config_id, input_id, timeout_seconds,
    corpus_schema_version = fertility_schema_version
) {
    is.list(checkpoint) &&
        identical(checkpoint$schema_version, as.integer(corpus_schema_version)) &&
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

fertility_mark_tile_input_changed <- function(result) {
    result$classification <- "input-changed"
    result$secondary <- "input-changed"
    if (is.data.frame(result$mismatches)) {
        result$mismatches <- result$mismatches[0L, , drop = FALSE]
    }
    result
}

fertility_tile_should_retry <- function(checkpoint) {
    checkpoint$classification %in% c(
        "timeout", "crash", "dtaparser-only-error", "haven-only-error",
        "shared-reader-error", "memory-limit", "unresolved", "input-changed"
    )
}

fertility_process_tile <- function(item, tile, checkpoint_path, framework_id,
                                   configuration, input, retry, execute) {
    checkpoint_path <- fertility_assert_checkpoint_file(
        checkpoint_path, "tile checkpoint"
    )
    checkpoint <- if (file.exists(checkpoint_path)) tryCatch(
        readRDS(fertility_assert_checkpoint_file(
            checkpoint_path, "tile checkpoint", must_exist = TRUE
        )), error = function(error) NULL
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
    if (!is.null(input$acceptance_commitment_id) &&
        nzchar(input$acceptance_commitment_id)) {
        result$acceptance_authority <- input$acceptance_authority
        result$acceptance_commitment_id <- input$acceptance_commitment_id
        result$acceptance_artifact_sha256 <- input$acceptance_artifact_sha256
    }
    result$column_hash <- tile$column_hash
    result$timeout_seconds <- configuration$timeout_seconds
    fertility_assert_checkpoint_file(checkpoint_path, "tile checkpoint")
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
    # Public signatures intentionally contain only fixed public categories and
    # fixed reader-pair IDs. Private details and column ordinals remain solely in
    # the private RDS checkpoints and cannot be dictionary-recovered from reports.
    pair <- if ("pair" %in% names(mismatches)) mismatches$pair else ""
    pair[is.na(pair)] <- ""
    keys <- paste(mismatches$category, pair, sep = ":")
    counts <- table(keys)
    signature_hashes <- vapply(names(counts), function(key) {
        fertility_stable_id(list(signature = key))
    }, character(1))
    signature_order <- order(-as.integer(counts), signature_hashes)
    category_counts <- table(mismatches$category)
    category_order <- order(-as.integer(category_counts), names(category_counts))
    list(
        count = as.integer(sum(counts)),
        categories = paste(
            names(category_counts)[category_order],
            as.integer(category_counts)[category_order], sep = "=", collapse = ","
        ),
        signatures = paste(
            signature_hashes[signature_order], as.integer(counts)[signature_order],
            sep = "=", collapse = ","
        )
    )
}

fertility_tile_secondary <- function(
    tiles, allow_legacy_empty_reader_artifact = FALSE
) {
    values <- unlist(lapply(tiles, `[[`, "secondary"), use.names = FALSE)
    artifact <- values == "-reader-error"
    canonical_reader_errors <- c(
        "direct-reader-error", "rust-reader-error", "haven-reader-error",
        "metadata-reader-error"
    )
    malformed_reader_error <- grepl("reader-error", values, fixed = TRUE) &
        !artifact & !values %in% canonical_reader_errors
    if (any(malformed_reader_error)) {
        stop("non-canonical reader-error category is not allowed")
    }
    if (any(artifact) && !isTRUE(allow_legacy_empty_reader_artifact)) {
        stop("legacy empty-reader artifact is not allowed for current evidence")
    }
    values[!artifact]
}

fertility_aggregate_classification <- function(
    tiles, complete, execution_complete = complete,
    allow_legacy_empty_reader_artifact = FALSE
) {
    classes <- vapply(tiles, `[[`, character(1), "classification")
    secondary <- unique(fertility_tile_secondary(
        tiles, allow_legacy_empty_reader_artifact
    ))
    if (any(classes == "input-changed")) return("inventory-hash-error")
    if (any(classes == "timeout")) return("timeout")
    if (any(classes == "memory-limit")) return("memory-limit")
    if (any(classes == "crash")) return("crash")
    if (!execution_complete || any(classes == "unresolved")) return("unresolved")
    for (classification in c("shared-reader-error", "dtaparser-only-error",
                             "haven-only-error")) {
        if (classification %in% classes) return(classification)
    }
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

fertility_validate_tile_execution <- function(
    tiles, batches, total_rows, configuration, tiles_expected = length(tiles)
) {
    scalar_number <- function(value) {
        length(value) == 1L && is.numeric(value) && !is.na(value) &&
            is.finite(value)
    }
    valid_type <- function(tile) {
        is.list(tile) && is.character(tile$tile_type) &&
            length(tile$tile_type) == 1L && !is.na(tile$tile_type) &&
            tile$tile_type %in% c("metadata", "value", "terminal")
    }
    if (!is.list(tiles) || !length(tiles) || !all(vapply(
            tiles, valid_type, logical(1)
        )) || !identical(tiles[[1L]]$tile_type, "metadata") ||
        !scalar_number(tiles_expected) || tiles_expected < 1 ||
        tiles_expected != as.integer(tiles_expected) ||
        !identical(as.integer(length(tiles)), as.integer(tiles_expected)) ||
        !scalar_number(total_rows) || total_rows < 0 ||
        total_rows != floor(total_rows) || !is.list(batches) ||
        !length(batches) || !all(vapply(batches, is.character, logical(1))) ||
        is.null(configuration$beyond_end_windows) ||
        !scalar_number(configuration$beyond_end_windows) ||
        configuration$beyond_end_windows < 0 ||
        configuration$beyond_end_windows !=
            as.integer(configuration$beyond_end_windows)) return(FALSE)
    terminal_tiles <- tiles[vapply(
        tiles, function(tile) identical(tile$tile_type, "terminal"), logical(1)
    )]
    expected_probes <- as.integer(configuration$beyond_end_windows)
    if (length(terminal_tiles) != expected_probes) return(FALSE)
    if (length(terminal_tiles) && !all(vapply(terminal_tiles, function(tile) {
        scalar_number(tile$batch) && scalar_number(tile$skip) &&
            scalar_number(tile$n_max)
    }, logical(1)))) return(FALSE)
    terminal_tiles <- terminal_tiles[order(vapply(
        terminal_tiles, `[[`, numeric(1), "skip"
    ))]
    expected_terminal_skips <- as.double(total_rows) +
        seq.int(0, expected_probes - 1L)
    expected_terminal_count <- length(batches[[1L]])
    for (probe in seq_len(expected_probes)) {
        tile <- terminal_tiles[[probe]]
        framework_valid <- is.character(tile$framework_id) &&
            length(tile$framework_id) == 1L && !is.na(tile$framework_id)
        expected_hash <- if (framework_valid) {
            fertility_projection_hash(batches[[1L]], tile$framework_id)
        } else NA_character_
        projection_planned <- scalar_number(tile$projection_expected_count) &&
            tile$projection_expected_count ==
                as.integer(tile$projection_expected_count) &&
            identical(as.integer(tile$projection_expected_count),
                      as.integer(expected_terminal_count)) &&
            is.character(tile$projection_expected_hash) &&
            length(tile$projection_expected_hash) == 1L &&
            !is.na(tile$projection_expected_hash) &&
            identical(tile$projection_expected_hash, expected_hash)
        if (!framework_valid || !projection_planned ||
            !identical(as.integer(tile$batch), 1L) ||
            !identical(as.double(tile$skip), expected_terminal_skips[[probe]]) ||
            !identical(as.integer(tile$n_max), 1L)) return(FALSE)
    }
    value_tiles <- tiles[vapply(
        tiles, function(tile) identical(tile$tile_type, "value"), logical(1)
    )]
    if (!length(value_tiles) || !all(vapply(value_tiles, function(tile) {
        scalar_number(tile$batch) && tile$batch == as.integer(tile$batch) &&
            tile$batch >= 1L && tile$batch <= length(batches) &&
            scalar_number(tile$skip) && tile$skip >= 0 &&
            tile$skip == floor(tile$skip) &&
            scalar_number(tile$n_max) && tile$n_max >= 1L &&
            tile$n_max == as.integer(tile$n_max) &&
            is.character(tile$framework_id) &&
            length(tile$framework_id) == 1L && !is.na(tile$framework_id) &&
            is.character(tile$classification) &&
            length(tile$classification) == 1L && !is.na(tile$classification)
    }, logical(1)))) return(FALSE)
    if (!identical(
        sort(unique(vapply(value_tiles, function(tile) {
            as.integer(tile$batch)
        }, integer(1)))), seq_along(batches)
    )) return(FALSE)
    reader_errors <- c(
        "shared-reader-error", "dtaparser-only-error", "haven-only-error"
    )
    for (batch in seq_along(batches)) {
        current <- value_tiles[vapply(
            value_tiles, function(tile) identical(as.integer(tile$batch), batch),
            logical(1)
        )]
        current <- current[order(vapply(current, `[[`, numeric(1), "skip"))]
        expected_skip <- 0
        expected_count <- length(batches[[batch]])
        for (tile in current) {
            expected_hash <- fertility_projection_hash(
                batches[[batch]], tile$framework_id
            )
            planned <- identical(as.integer(tile$projection_expected_count),
                                 as.integer(expected_count)) &&
                is.character(tile$projection_expected_hash) &&
                length(tile$projection_expected_hash) == 1L &&
                !is.na(tile$projection_expected_hash) &&
                identical(tile$projection_expected_hash, expected_hash) &&
                identical(as.double(tile$skip), as.double(expected_skip))
            if (!isTRUE(planned)) return(FALSE)
            expected_rows <- min(
                as.integer(tile$n_max), as.double(total_rows) - expected_skip
            )
            observed_rows <- suppressWarnings(as.double(tile$rows))
            observed_valid <- length(observed_rows) == 1L &&
                !is.na(observed_rows) && is.finite(observed_rows) &&
                identical(observed_rows, as.double(expected_rows))
            if (!observed_valid && !tile$classification %in% reader_errors) {
                return(FALSE)
            }
            expected_skip <- expected_skip + expected_rows
        }
        if (!identical(as.double(expected_skip), as.double(total_rows))) return(FALSE)
    }
    TRUE
}

fertility_validate_tile_completeness <- function(tiles, batches, total_rows,
                                                 configuration) {
    if (!fertility_validate_tile_execution(
        tiles, batches, total_rows, configuration, length(tiles)
    )) return(FALSE)
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

fertility_tiled_result <- function(
    item, framework_id, configuration, input, tiles, batches, total_rows,
    tiles_expected = length(tiles), allow_legacy_empty_reader_artifact = FALSE
) {
    execution_complete <- fertility_validate_tile_execution(
        tiles, batches, total_rows, configuration, tiles_expected
    )
    complete <- execution_complete && fertility_validate_tile_completeness(
        tiles, batches, total_rows, configuration
    )
    input_changed <- any(vapply(
        tiles, function(tile) identical(tile$classification, "input-changed"),
        logical(1)
    ))
    mismatch <- if (input_changed) {
        list(count = 0L, categories = "", signatures = "")
    } else {
        fertility_mismatch_summary(tiles)
    }
    secondary <- if (input_changed) {
        "input-changed"
    } else {
        sort(unique(c(
            fertility_tile_secondary(tiles, allow_legacy_empty_reader_artifact),
            unlist(lapply(tiles, function(tile) {
                if (is.data.frame(tile$mismatches)) {
                    tile$mismatches$category
                } else {
                    character()
                }
            }), use.names = FALSE)
        )))
    }
    c(list(
        schema_version = fertility_schema_version, framework_id = framework_id,
        config_id = configuration$config_id, input_id = input$input_id,
        id = item$id, program = item$program, level = item$level,
        release = as.integer(item$release), expected_sha512 = item$expected_sha512,
        timeout_seconds = configuration$timeout_seconds,
        classification = fertility_aggregate_classification(
            tiles, complete, execution_complete,
            allow_legacy_empty_reader_artifact
        ),
        secondary_categories = paste(secondary, collapse = ","),
        mismatch_count = mismatch$count, mismatch_categories = mismatch$categories,
        mismatch_signatures = mismatch$signatures,
        rows = as.double(total_rows), columns = length(unlist(batches)),
        tiles_expected = as.integer(tiles_expected),
        tiles_completed = length(tiles), complete = complete,
        actual_sha512 = input$actual_sha512,
        elapsed_seconds = sum(vapply(tiles, function(tile) tile$elapsed_seconds,
                                     numeric(1)), na.rm = TRUE)
    ), fertility_result_acceptance_fields(input))
}
