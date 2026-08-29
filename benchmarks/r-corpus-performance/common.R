source(file.path(script_dir, "..", "benchmark-common.R"), local = TRUE)

corpus_pair_results <- function(raw, inventory) {
    raw_required <- c(
        "corpus", "id", "reader", "status", "elapsed_seconds", "rows",
        "columns", "rss_bytes", "footprint_bytes"
    )
    inventory_required <- c("corpus", "id", "release", "bytes")
    if (!all(raw_required %in% names(raw))) {
        stop("raw results are missing pairing columns")
    }
    if (!all(inventory_required %in% names(inventory))) {
        stop("inventory is missing pairing columns")
    }
    if (anyDuplicated(raw[c("corpus", "id", "reader")])) {
        stop("raw results contain duplicate reader measurements")
    }

    direct <- raw[raw$reader == "dtatools", , drop = FALSE]
    haven <- raw[raw$reader == "haven", , drop = FALSE]
    stata <- raw[raw$reader == "stata", , drop = FALSE]
    paired <- merge(
        direct, haven, by = c("corpus", "id"),
        suffixes = c("_dtatools", "_haven")
    )
    paired <- merge(paired, stata, by = c("corpus", "id"))
    stata_columns <- c(
        "reader", "reader_order", "status", "elapsed_seconds", "rows",
        "columns", "rss_bytes", "footprint_bytes"
    )
    names(paired)[names(paired) %in% stata_columns] <- paste0(
        names(paired)[names(paired) %in% stata_columns], "_stata"
    )
    paired <- paired[
        paired$status_dtatools == "ok" & paired$status_haven == "ok" &
            paired$status_stata == "ok" &
            paired$rows_dtatools == paired$rows_haven &
            paired$columns_dtatools == paired$columns_haven &
            paired$rows_dtatools == paired$rows_stata &
            paired$columns_dtatools == paired$columns_stata,
        , drop = FALSE
    ]
    merge(
        paired, inventory[c("corpus", "id", "release", "bytes")],
        by = c("corpus", "id")
    )
}

corpus_summary_row <- function(corpus, release, all_files, common) {
    has_common <- nrow(common) > 0L
    sum_or_na <- function(values) if (has_common) sum(values) else NA_real_
    max_or_na <- function(values) if (has_common) max(values) else NA_real_

    direct_seconds <- sum_or_na(common$elapsed_seconds_dtatools)
    haven_seconds <- sum_or_na(common$elapsed_seconds_haven)
    stata_seconds <- sum_or_na(common$elapsed_seconds_stata)
    direct_rss <- max_or_na(common$rss_bytes_dtatools)
    haven_rss <- max_or_na(common$rss_bytes_haven)
    stata_rss <- max_or_na(common$rss_bytes_stata)
    data.frame(
        corpus = corpus,
        release = release,
        files = nrow(common),
        excluded_files = nrow(all_files) - nrow(common),
        input_gb = if (has_common) sum(common$bytes) / 1e9 else 0,
        dtatools_seconds = direct_seconds,
        haven_seconds = haven_seconds,
        stata_seconds = stata_seconds,
        dtatools_to_haven_time_ratio = direct_seconds / haven_seconds,
        dtatools_to_stata_time_ratio = direct_seconds / stata_seconds,
        dtatools_peak_rss_gb = direct_rss / 1e9,
        haven_peak_rss_gb = haven_rss / 1e9,
        stata_peak_rss_gb = stata_rss / 1e9,
        vs_haven_rss_reduction = 1 - direct_rss / haven_rss,
        vs_stata_rss_reduction = 1 - direct_rss / stata_rss,
        stringsAsFactors = FALSE
    )
}

corpus_performance_summary <- function(inventory, paired, corpus_names) {
    inventory_required <- c("corpus", "id", "release")
    paired_required <- c(
        "corpus", "id", "release", "bytes",
        "elapsed_seconds_dtatools", "elapsed_seconds_haven",
        "elapsed_seconds_stata", "rss_bytes_dtatools", "rss_bytes_haven",
        "rss_bytes_stata"
    )
    if (!all(inventory_required %in% names(inventory))) {
        stop("inventory is missing release-summary columns")
    }
    if (!all(paired_required %in% names(paired))) {
        stop("paired results are missing release-summary columns")
    }
    if (anyDuplicated(inventory[c("corpus", "id")])) {
        stop("inventory contains duplicate corpus IDs")
    }
    if (anyDuplicated(paired[c("corpus", "id")])) {
        stop("paired results contain duplicate corpus IDs")
    }

    rows <- list()
    append_row <- function(row) rows[[length(rows) + 1L]] <<- row
    for (corpus in corpus_names) {
        corpus_inventory <- inventory[inventory$corpus == corpus, , drop = FALSE]
        corpus_common <- paired[paired$corpus == corpus, , drop = FALSE]
        releases <- sort(unique(corpus_inventory$release[!is.na(corpus_inventory$release)]))
        for (release in releases) {
            append_row(corpus_summary_row(
                corpus, as.character(release),
                corpus_inventory[
                    !is.na(corpus_inventory$release) &
                        corpus_inventory$release == release,
                    , drop = FALSE
                ],
                corpus_common[
                    !is.na(corpus_common$release) & corpus_common$release == release,
                    , drop = FALSE
                ]
            ))
        }
        if (anyNA(corpus_inventory$release)) {
            append_row(corpus_summary_row(
                corpus, "unknown",
                corpus_inventory[is.na(corpus_inventory$release), , drop = FALSE],
                corpus_common[is.na(corpus_common$release), , drop = FALSE]
            ))
        }
        append_row(corpus_summary_row(corpus, "all", corpus_inventory, corpus_common))
    }
    do.call(rbind, rows)
}
