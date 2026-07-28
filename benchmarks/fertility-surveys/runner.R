fertility_report_schema_version <- 2L
fertility_legacy_report_schema_version <- 1L
fertility_legacy_corpus_schema_version <- 10L

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
    rows <- if (!nrow(manifest)) character() else apply(
        manifest, 1L, function(row) paste(as.character(row), collapse = "\037")
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
    list(
        programs = programs, releases = releases, ids = ids,
        shard_index = 1L, shard_count = shard_count, max_files = max_files
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

fertility_full_default_family <- function(options) {
    !length(options$programs) && !length(options$releases) &&
        !length(options$ids) && !is.finite(options$max_files)
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

fertility_base_result <- function(item, framework_id, timeout_seconds, input,
                                  classification, elapsed_seconds = NA_real_) {
    list(
        schema_version = fertility_schema_version,
        framework_id = framework_id, input_id = input$input_id,
        id = item$id, program = item$program, level = item$level,
        release = as.integer(item$release), expected_sha512 = item$expected_sha512,
        timeout_seconds = timeout_seconds, classification = classification,
        component = NA_integer_, secondary_categories = "", mismatch_count = 0L,
        mismatch_categories = "", mismatch_signatures = "", rows = NA_real_,
        columns = NA_integer_, tiles_expected = 0L, tiles_completed = 0L,
        complete = FALSE, actual_sha512 = input$actual_sha512,
        elapsed_seconds = elapsed_seconds
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
            item, framework_id, timeout_seconds, input_before, "inventory-hash-error"
        )
    } else if (nzchar(item$expected_sha512) &&
               !identical(input_before$actual_sha512,
                          tolower(item$expected_sha512))) {
        result <- fertility_base_result(
            item, framework_id, timeout_seconds, input_before,
            "inventory-hash-error"
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

fertility_run_provenance_fields <- function() c(
    "schema_version", "report_schema_version", "evidence_origin",
    "source_corpus_schema_version", "replayed_at_utc", "selection_id",
    "evidence_selection_id", "input_attestation_id", "family_id",
    "family_manifest_id", "framework_id", "config_id", "build_provenance_id",
    "inventory_id", "report_schema_id", "selected_files", "expected_family_files",
    "full_default_family", "program_filter", "release_filter", "id_filter",
    "max_files", "shard_index", "shard_count", "timeout_seconds",
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

fertility_publish_results <- function(checkpoints, build_provenance_id, path) {
    results <- fertility_result_frame(checkpoints)
    results$build_provenance_id <- rep(build_provenance_id, nrow(results))
    fertility_validate_public_results(results)
    fertility_atomic_write_table(results, path)
    results
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

fertility_validate_shard_bundles <- function(bundles, family_id,
                                               canonical_inventory) {
    if (!length(bundles)) stop("no current shard reports found for family ID")
    required <- fertility_run_provenance_fields()
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
        }, logical(1))) || any(!provenance$retry %in% c("TRUE", "FALSE")) ||
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
        "source_corpus_schema_version", "replayed_at_utc", "family_id",
        "family_manifest_id", "framework_id",
        "config_id", "build_provenance_id", "inventory_id", "report_schema_id",
        "expected_family_files", "full_default_family", "program_filter",
        "release_filter", "id_filter", "max_files", "shard_count",
        "timeout_seconds", "chunk_rows", "column_batch", "memory_mib",
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
    if (!identical(full_default, fertility_full_default_family(options))) {
        stop("full-default provenance disagrees with filter provenance")
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
            provenance$report_schema_id[[index]]
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
    if (full_default) {
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
        unsupported <- results$release == "111"
        if (!all(results$classification[unsupported] == "expected-unsupported-111")) {
            stop("release 111 classifications are invalid")
        }
        supported <- !unsupported
        hash_errors <- results$classification[supported] == "inventory-hash-error"
        if (sum(hash_errors) != 5L || sum(!hash_errors) != 869L ||
            any(results$classification[supported] == "expected-unsupported-111")) {
            stop("supported corpus executable accounting is invalid")
        }
    }
    list(results = results, provenance = provenance, shard_count = shard_count,
         full_default = full_default, family_manifest = expected_family)
}

fertility_framework_id <- function(provenance_id, datasigs_path) {
    datasigs_sha256 <- tolower(as.character(openssl::sha256(file(datasigs_path))))
    fertility_stable_id(list(
        schema_version = fertility_schema_version,
        provenance_id = provenance_id,
        datasigs_sha256 = datasigs_sha256,
        comparator_tolerance = "1e-7"
    ))
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
    manifest_path <- file.path(snapshot_root, "inventory-manifest.tsv")
    provenance_path <- file.path(snapshot_root, "inventory-manifest-provenance.tsv")
    if (!file.exists(manifest_path) || !file.exists(provenance_path)) {
        stop("canonical inventory manifest is absent")
    }
    manifest <- read.delim(manifest_path, colClasses = "character",
                           check.names = FALSE)
    manifest <- fertility_validate_canonical_inventory(manifest, exact = TRUE)
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
    list(manifest = manifest, provenance = provenance)
}

fertility_prepare_framework_snapshot <- function(script_dir, raw_root, framework_id,
                                                 inventory) {
    snapshot_root <- file.path(raw_root, "framework", framework_id)
    dir.create(snapshot_root, recursive = TRUE, showWarnings = FALSE, mode = "0700")
    Sys.chmod(c(file.path(raw_root, "framework"), snapshot_root), mode = "0700")
    for (name in c("common.R", "worker.R", "compare.R", "runtime.R")) {
        source_path <- file.path(script_dir, name)
        snapshot_path <- file.path(snapshot_root, name)
        if (!file.exists(snapshot_path)) {
            temporary <- tempfile(paste0(name, "."), tmpdir = snapshot_root)
            if (!file.copy(source_path, temporary, overwrite = TRUE)) {
                stop("could not snapshot corpus framework")
            }
            Sys.chmod(temporary, mode = "0600")
            if (!file.rename(temporary, snapshot_path)) {
                unlink(temporary)
                if (!file.exists(snapshot_path)) {
                    stop("could not publish corpus framework snapshot")
                }
            }
        }
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
    if (!file.exists(manifest_path)) fertility_atomic_write_table(manifest, manifest_path)
    if (!file.exists(provenance_path)) {
        fertility_atomic_write_table(manifest_provenance, provenance_path)
    }
    invisible(fertility_framework_inventory(
        snapshot_root, inventory = inventory, framework_id = framework_id
    ))
    snapshot_root
}

fertility_verify_framework_snapshot <- function(script_dir, raw_root, framework_id,
                                                inventory = NULL) {
    snapshot_root <- file.path(raw_root, "framework", framework_id)
    if (!dir.exists(snapshot_root)) stop("corpus framework snapshot is absent")
    for (name in c("common.R", "worker.R", "compare.R", "runtime.R")) {
        source_path <- file.path(script_dir, name)
        snapshot_path <- file.path(snapshot_root, name)
        if (!file.exists(snapshot_path) ||
            !identical(unname(tools::sha256sum(source_path)),
                       unname(tools::sha256sum(snapshot_path)))) {
            stop("corpus framework snapshot does not match its provenance")
        }
    }
    invisible(fertility_framework_inventory(
        snapshot_root, inventory = inventory, framework_id = framework_id
    ))
    snapshot_root
}

fertility_tile_configuration <- function(options) {
    fields <- list(
        chunk_rows = options$chunk_rows, column_batch = options$column_batch,
        memory_mib = options$memory_mib, cell_budget = options$cell_budget,
        max_tiles_per_batch = options$max_tiles_per_batch,
        beyond_end_windows = options$beyond_end_windows,
        timeout_seconds = options$timeout_seconds, object_overhead_bytes = 64L,
        readers_per_tile = 3L, strl_sample_count = 16L,
        strl_safety_factor = 8, strl_fallback_rows = 64L
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
    is.list(result) && setequal(names(result), required) &&
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
         (is.na(result$actual_sha512) &&
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
    actual_missing <- length(actual) != 1L || is.na(actual)
    actual_valid <- !actual_missing && is.character(actual) &&
        grepl("^[0-9a-f]{128}$", actual)
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
    valid_reason <- switch(
        reason,
        "hash-read-error" = actual_missing,
        "signature-mismatch" = expected_valid && nzchar(expected) &&
            actual_valid && !identical(actual, expected),
        "input-changed" = expected_valid && actual_valid && input_id_valid,
        expected_valid && actual_valid &&
            (!nzchar(expected) || identical(actual, expected))
    )
    if (!identical(inventory_hash_error, nzchar(reason)) || !valid_reason) {
        stop("recorded input preflight attestation is inconsistent")
    }
    invisible(TRUE)
}

fertility_validate_recorded_input_result <- function(result, tile_count) {
    fertility_validate_recorded_input_attestation(result)
    if (!identical(result$classification, "inventory-hash-error") ||
        length(tile_count) != 1L || is.na(tile_count) || tile_count < 0L ||
        !identical(as.integer(tile_count), tile_count) ||
        (!identical(result$secondary_categories, "input-changed") &&
         tile_count != 0L) ||
        isTRUE(result$complete) || result$mismatch_count != 0L) {
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
        status <- if (identical(result$classification, "inventory-hash-error")) {
            result$secondary_categories
        } else if (nzchar(result$expected_sha512)) {
            "verified-signature"
        } else "verified-empty-expected"
        fertility_stable_id(list(
            id = result$id, input_id = result$input_id,
            expected_sha512 = result$expected_sha512,
            actual_sha512 = if (is.na(result$actual_sha512)) "" else
                result$actual_sha512,
            status = status
        ))
    }, character(1))
    fertility_stable_id(list(
        ids = paste(ids, collapse = ","),
        commitments = paste(commitments, collapse = ",")
    ))
}

fertility_evidence_selection_id <- function(
    selection_id, input_attestation_id, evidence_origin,
    source_corpus_schema_version, report_schema_id
) {
    fertility_stable_id(list(
        selection_id = selection_id, input_attestation_id = input_attestation_id,
        evidence_origin = evidence_origin,
        source_corpus_schema_version = as.integer(source_corpus_schema_version),
        report_schema_id = report_schema_id
    ))
}

fertility_family_input_attestation_id <- function(provenance) {
    if (!is.data.frame(provenance) || !all(c(
        "shard_index", "input_attestation_id", "evidence_selection_id"
    ) %in% names(provenance))) stop("family input attestation provenance is invalid")
    indexes <- suppressWarnings(as.integer(provenance$shard_index))
    ordering <- order(indexes)
    if (anyNA(indexes) || !identical(indexes[ordering], seq_along(indexes))) {
        stop("family input attestations are not in canonical shard order")
    }
    fertility_stable_id(list(
        shard_indexes = paste(indexes[ordering], collapse = ","),
        input_attestation_ids = paste(
            provenance$input_attestation_id[ordering], collapse = ","
        ),
        evidence_selection_ids = paste(
            provenance$evidence_selection_id[ordering], collapse = ","
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
    stages, rename_path, write_pointer, remove_path, pointer_state, path_exists
) {
    renamed <- integer()
    for (index in seq_along(stages)) {
        if (!isTRUE(rename_path(stages[[index]]$stage, stages[[index]]$published))) {
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
        if (!isTRUE(write_pointer(
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
    source_corpus_schema_version, report_schema_id
) {
    fertility_stable_id(list(
        family_id = family_id,
        family_input_attestation_id = family_input_attestation_id,
        evidence_origin = evidence_origin,
        source_corpus_schema_version = as.integer(source_corpus_schema_version),
        report_schema_id = report_schema_id
    ))
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
    if (!is.list(checkpoint) || !checkpoint$tile_type %in%
        c("metadata", "value", "terminal", "sizing")) {
        stop("recorded tile checkpoint schema is invalid")
    }
    expected <- c(common, if (identical(checkpoint$tile_type, "sizing")) sizing_extra)
    if (!setequal(names(checkpoint), expected) ||
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
        "metadata-reader-error", "row-termination-mismatch"
    )
    if ((any(legacy_artifact) && !legacy_artifact_allowed) ||
        any(!legacy_artifact & !checkpoint$secondary %in% allowed_secondary) ||
        !is.data.frame(checkpoint$mismatches) ||
        !identical(names(checkpoint$mismatches),
                   c("category", "detail", "component", "pair"))) {
        stop("recorded tile checkpoint contains malformed or non-canonical detail")
    }
    mismatches <- checkpoint$mismatches
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
    tile_root <- file.path(file_root, "tiles")
    load_tile <- function(tile, path) {
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
    tiles, complete, allow_legacy_empty_reader_artifact = FALSE
) {
    classes <- vapply(tiles, `[[`, character(1), "classification")
    secondary <- unique(fertility_tile_secondary(
        tiles, allow_legacy_empty_reader_artifact
    ))
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

fertility_tiled_result <- function(
    item, framework_id, configuration, input, tiles, batches, total_rows,
    allow_legacy_empty_reader_artifact = FALSE
) {
    complete <- fertility_validate_tile_completeness(
        tiles, batches, total_rows, configuration
    )
    mismatch <- fertility_mismatch_summary(tiles)
    secondary <- sort(unique(c(
        fertility_tile_secondary(tiles, allow_legacy_empty_reader_artifact),
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
        classification = fertility_aggregate_classification(
            tiles, complete, allow_legacy_empty_reader_artifact
        ),
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
