fertility_usage <- function() {
    paste(
        "usage: run.R [--inventory-only] [--program=a,b] [--release=113,118]",
        "[--id=F0001,F0002] [--shard-index=N --shard-count=N] [--max-files=N]",
        "[--timeout-seconds=N] [--retry]"
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
        max_files = Inf, timeout_seconds = 600L, retry = FALSE
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
        } else stop(fertility_usage())
    }
    if (xor(seen_shard_index, seen_shard_count)) {
        stop("--shard-index and --shard-count must be supplied together")
    }
    if (options$shard_index > options$shard_count) {
        stop("--shard-index must not exceed --shard-count")
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
    fields <- c("framework_id", "id", "program", "level", "release",
                "classification", "component", "rows", "columns",
                "elapsed_seconds")
    rows <- lapply(checkpoints, function(value) {
        as.data.frame(value[fields], stringsAsFactors = FALSE, optional = TRUE)
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
