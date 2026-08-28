source(file.path(script_dir, "..", "benchmark-common.R"), local = TRUE)

roundtrip_corpora <- c("DHS", "MICS", "NSFG")

roundtrip_stable_id <- function(corpus, relative_path, sha256) {
    digest <- tools::sha256sum(bytes = charToRaw(paste(
        corpus, relative_path, sha256, sep = "\037"
    )))
    paste0(corpus, "-", substr(unname(digest), 1L, 24L))
}

roundtrip_inventory_files <- function(cache_root, max_files = Inf) {
    inventory <- benchmark_corpus_inventory_files(
        cache_root, roundtrip_corpora
    )
    rows <- lapply(roundtrip_corpora, function(corpus) {
        items <- inventory[inventory$corpus == corpus, , drop = FALSE]
        order_index <- if (is.finite(max_files)) {
            head(order(-items$bytes, items$relative_path, method = "radix"),
                 max_files)
        } else {
            seq_len(nrow(items))
        }
        items <- items[order_index, , drop = FALSE]
        data.frame(
            corpus = items$corpus,
            relative_path = items$relative_path,
            path = items$path,
            bytes = items$bytes,
            modified = sprintf("%.6f", items$mtime),
            stringsAsFactors = FALSE
        )
    })
    result <- do.call(rbind, rows)
    rownames(result) <- NULL
    result
}

roundtrip_inventory <- function(cache_root, progress = TRUE, max_files = Inf) {
    files <- roundtrip_inventory_files(cache_root, max_files)
    sha256 <- benchmark_files_sha256(files$path, progress)
    inventory <- data.frame(
        corpus = files$corpus,
        id = mapply(
            roundtrip_stable_id, files$corpus, files$relative_path, sha256,
            USE.NAMES = FALSE
        ),
        relative_path = files$relative_path,
        path = files$path,
        release = vapply(files$path, corpus_dta_release, integer(1)),
        bytes = files$bytes,
        modified = files$modified,
        sha256 = sha256,
        stringsAsFactors = FALSE
    )
    rownames(inventory) <- NULL
    if (anyDuplicated(inventory$id)) stop("stable corpus ID collision")
    inventory
}

roundtrip_cached_inventory <- function(cache_root, path, max_files = Inf) {
    inventory <- read.delim(
        path, check.names = FALSE, stringsAsFactors = FALSE,
        colClasses = "character"
    )
    required <- c(
        "corpus", "id", "relative_path", "release", "bytes", "modified",
        "sha256"
    )
    if (!identical(names(inventory), required) ||
        anyDuplicated(inventory$id) ||
        !all(inventory$corpus %in% roundtrip_corpora) ||
        any(!grepl("^[0-9a-f]{64}$", inventory$sha256))) {
        stop("cached corpus inventory is invalid")
    }

    files <- roundtrip_inventory_files(cache_root, max_files)
    if (!identical(inventory$corpus, files$corpus) ||
        !identical(inventory$relative_path, files$relative_path) ||
        !identical(inventory$bytes, sprintf("%.0f", files$bytes)) ||
        !identical(inventory$modified, files$modified)) {
        stop("corpus files changed since the cached inventory was created")
    }
    cached_releases <- suppressWarnings(as.integer(inventory$release))
    canonical_releases <- ifelse(
        is.na(cached_releases), NA_character_, as.character(cached_releases)
    )
    if (!identical(inventory$release, canonical_releases)) {
        stop("cached corpus inventory is invalid")
    }
    current_hashes <- benchmark_files_sha256(files$path, progress = FALSE)
    current_ids <- mapply(
        roundtrip_stable_id,
        files$corpus,
        files$relative_path,
        current_hashes,
        USE.NAMES = FALSE
    )
    current_releases <- unname(vapply(
        files$path, corpus_dta_release, integer(1L)
    ))
    if (!identical(inventory$sha256, current_hashes) ||
        !identical(inventory$id, current_ids) ||
        !identical(cached_releases, current_releases)) {
        stop("corpus files changed since the cached inventory was created")
    }
    inventory$release <- current_releases
    inventory$bytes <- as.double(inventory$bytes)
    inventory$path <- files$path
    rownames(inventory) <- NULL
    inventory[c(
        "corpus", "id", "relative_path", "path", "release", "bytes",
        "modified", "sha256"
    )]
}

roundtrip_qualification_successes <- function(rows) {
    required <- c("id", "status")
    if (!all(required %in% names(rows))) {
        stop("qualification rows are missing resume columns")
    }
    if (anyDuplicated(rows$id)) {
        stop("qualification contains duplicate file IDs")
    }
    rows[
        rows$status %in% c("pass", "expected-exclusion"),
        ,
        drop = FALSE
    ]
}

roundtrip_qualification_status <- function(failures, wide_status) {
    if (failures == 0L && identical(wide_status, "pass")) {
        "complete"
    } else {
        "failed"
    }
}

roundtrip_validate_complete_qualification <- function(rows, inventory) {
    if (!all(c("id", "status") %in% names(rows)) || anyDuplicated(rows$id) ||
        nrow(rows) != nrow(inventory)) {
        stop("qualification does not cover the exact corpus inventory")
    }
    indices <- match(inventory$id, rows$id)
    if (anyNA(indices)) {
        stop("qualification does not cover the exact corpus inventory")
    }
    expected <- vapply(seq_len(nrow(inventory)), function(index) {
        if (is.na(roundtrip_exclusion_reason(inventory[index, , drop = FALSE]))) {
            "pass"
        } else {
            "expected-exclusion"
        }
    }, character(1L))
    if (!identical(rows$status[indices], expected)) {
        stop("qualification statuses do not match the bound corpus inventory")
    }
    rows[indices, , drop = FALSE]
}

roundtrip_validate_benchmark_matrix <- function(raw, inputs, writers) {
    required <- c("id", "writer", "status", "input_sha256")
    if (!all(required %in% names(raw)) ||
        !all(c("id", "sha256") %in% names(inputs)) ||
        anyDuplicated(inputs$id) || anyDuplicated(writers)) {
        stop("benchmark rows are missing identity columns")
    }
    actual_keys <- paste(raw$id, raw$writer, sep = "\037")
    expected_keys <- unlist(lapply(inputs$id, function(id) {
        paste(id, writers, sep = "\037")
    }), use.names = FALSE)
    if (anyDuplicated(actual_keys) ||
        !identical(sort(actual_keys), sort(expected_keys))) {
        stop("benchmark does not contain the exact input-by-writer matrix")
    }
    expected_sha256 <- inputs$sha256[match(raw$id, inputs$id)]
    if (anyNA(raw$input_sha256) || anyNA(expected_sha256) ||
        any(!grepl("^[0-9a-f]{64}$", raw$input_sha256)) ||
        !identical(tolower(raw$input_sha256), tolower(expected_sha256))) {
        stop("benchmark rows do not match their bound input identities")
    }
    if (anyNA(raw$status) || any(raw$status != "ok")) {
        stop("write benchmark contains worker failures")
    }
    invisible(NULL)
}

roundtrip_expected_exclusions <- data.frame(
    corpus = c("MICS", "MICS"),
    id = c(
        "MICS-9fcbb54ada2fcece459bca33",
        "MICS-8cb7d864111538cd2265198f"
    ),
    bytes = c(0, 27792),
    sha256 = c(
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "76b12af213a2e89d4ae241694a1d09dc06efbc5a36f6b85cb2d0257c89e1111a"
    ),
    reason = c("empty-source", "malformed-source"),
    stringsAsFactors = FALSE
)

roundtrip_exclusion_reason <- function(item) {
    matched <- which(
        roundtrip_expected_exclusions$corpus == item$corpus &
        roundtrip_expected_exclusions$id == item$id &
        roundtrip_expected_exclusions$bytes == item$bytes &
        roundtrip_expected_exclusions$sha256 == item$sha256
    )
    if (length(matched) == 1L) roundtrip_expected_exclusions$reason[[matched]] else NA_character_
}
