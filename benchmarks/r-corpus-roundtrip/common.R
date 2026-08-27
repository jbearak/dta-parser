roundtrip_corpora <- c("DHS", "MICS", "NSFG")
roundtrip_modern_prefix <- charToRaw("<stata_dta><header><release>")
roundtrip_legacy_releases <- c(104L, 105L, 108L, 110L, 111L, 113L, 114L, 115L)

roundtrip_release <- function(path) {
    size <- file.info(path, extra_cols = FALSE)$size[[1L]]
    if (is.na(size) || size < 1) return(NA_integer_)
    needed <- length(roundtrip_modern_prefix) + 3L
    connection <- file(path, "rb")
    on.exit(close(connection), add = TRUE)
    header <- readBin(connection, "raw", n = min(size, needed))
    first <- as.integer(header[[1L]])
    if (first %in% roundtrip_legacy_releases) return(first)
    if (length(header) < needed ||
        !identical(header[seq_along(roundtrip_modern_prefix)], roundtrip_modern_prefix)) {
        return(NA_integer_)
    }
    release <- suppressWarnings(as.integer(rawToChar(header[(length(
        roundtrip_modern_prefix
    ) + 1L):needed])))
    if (length(release) != 1L || is.na(release)) NA_integer_ else release
}

roundtrip_walk_dta <- function(directory) {
    entries <- list.files(
        directory, all.files = TRUE, full.names = TRUE,
        no.. = TRUE, recursive = FALSE
    )
    result <- character()
    for (path in entries) {
        if (!is.na(Sys.readlink(path)) && nzchar(Sys.readlink(path))) next
        info <- file.info(path, extra_cols = FALSE)
        if (is.na(info$isdir[[1L]])) stop("cannot inspect corpus entry")
        if (isTRUE(info$isdir[[1L]])) {
            result <- c(result, roundtrip_walk_dta(path))
        } else if (grepl("[.]dta$", basename(path), ignore.case = TRUE)) {
            result <- c(result, normalizePath(path, winslash = "/", mustWork = TRUE))
        }
    }
    result
}

roundtrip_stable_id <- function(corpus, relative_path, sha256) {
    digest <- tools::sha256sum(bytes = charToRaw(paste(
        corpus, relative_path, sha256, sep = "\037"
    )))
    paste0(corpus, "-", substr(unname(digest), 1L, 24L))
}

roundtrip_inventory <- function(cache_root, progress = TRUE) {
    roots <- setNames(file.path(cache_root, roundtrip_corpora), roundtrip_corpora)
    if (!all(dir.exists(roots))) {
        stop("cache root must contain DHS, MICS, and NSFG directories")
    }
    rows <- list()
    completed <- 0L
    for (corpus in names(roots)) {
        paths <- roundtrip_walk_dta(roots[[corpus]])
        relative <- substring(paths, nchar(cache_root, type = "chars") + 2L)
        order_index <- order(relative, method = "radix")
        paths <- paths[order_index]
        relative <- relative[order_index]
        info <- file.info(paths, extra_cols = FALSE)
        sha256 <- character(length(paths))
        for (index in seq_along(paths)) {
            sha256[[index]] <- unname(tools::sha256sum(paths[[index]]))
            completed <- completed + 1L
            if (progress && completed %% 50L == 0L) {
                message("hashed ", completed, " corpus files")
            }
        }
        rows[[corpus]] <- data.frame(
            corpus = rep(corpus, length(paths)),
            id = mapply(roundtrip_stable_id, rep(corpus, length(paths)),
                        relative, sha256,
                        USE.NAMES = FALSE),
            relative_path = relative,
            path = paths,
            release = vapply(paths, roundtrip_release, integer(1)),
            bytes = as.double(info$size),
            sha256 = sha256,
            stringsAsFactors = FALSE
        )
    }
    inventory <- do.call(rbind, rows)
    rownames(inventory) <- NULL
    if (anyDuplicated(inventory$id)) stop("stable corpus ID collision")
    inventory
}

roundtrip_expected_exclusions <- data.frame(
    corpus = c("MICS", "MICS"),
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
        roundtrip_expected_exclusions$bytes == item$bytes &
        roundtrip_expected_exclusions$sha256 == item$sha256
    )
    if (length(matched) == 1L) roundtrip_expected_exclusions$reason[[matched]] else NA_character_
}

roundtrip_manifest_hash <- function(path) {
    unname(tools::sha256sum(path))
}

roundtrip_directory_hash <- function(directory) {
    directory <- normalizePath(directory, winslash = "/", mustWork = TRUE)
    paths <- list.files(directory, recursive = TRUE, all.files = TRUE,
                        full.names = TRUE, no.. = TRUE)
    paths <- sort(paths[file_test("-f", paths)])
    relative <- substring(paths, nchar(directory, type = "chars") + 2L)
    hashes <- unname(tools::sha256sum(paths))
    unname(tools::sha256sum(bytes = charToRaw(paste(
        paste(relative, hashes, sep = "\t"), collapse = "\n"
    ))))
}

roundtrip_parse_memory <- function(stderr) {
    lines <- strsplit(stderr, "\n", fixed = TRUE)[[1L]]
    if (identical(Sys.info()[["sysname"]], "Darwin")) {
        line <- grep("maximum resident set size", lines, value = TRUE)
        if (length(line)) as.numeric(sub("^ *([0-9]+).*$", "\\1", tail(line, 1L))) else NA_real_
    } else {
        line <- grep("Maximum resident set size [(]kbytes[)]", lines, value = TRUE)
        if (length(line)) 1024 * as.numeric(sub("^.*: *([0-9]+).*$", "\\1", tail(line, 1L))) else NA_real_
    }
}

roundtrip_append_tsv <- function(row, path) {
    write.table(
        row, path, sep = "\t", row.names = FALSE, quote = TRUE,
        append = file.exists(path), col.names = !file.exists(path)
    )
}
