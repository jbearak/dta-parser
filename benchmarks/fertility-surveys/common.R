fertility_schema_version <- 1L
fertility_expected_rows <- 1004L
fertility_expected_releases <- c(`111` = 130L, `113` = 475L, `114` = 23L,
                                  `117` = 150L, `118` = 226L)
fertility_supported_releases <- c(113L, 114L, 117L, 118L)
fertility_opt_in_value <- "I_UNDERSTAND_THIS_READS_PROPRIETARY_DATA"

fertility_script_path <- function() {
    argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
    if (!length(argument)) stop("could not determine script path", call. = FALSE)
    normalizePath(sub("^--file=", "", argument[[1L]]), winslash = "/")
}

fertility_checkout_root <- function(script_path = fertility_script_path()) {
    normalizePath(file.path(dirname(script_path), "..", ".."), winslash = "/")
}

fertility_assert_manual_run <- function() {
    ci_variables <- c("CI", "GITHUB_ACTIONS", "GITHUB_RUN_ID", "GITHUB_WORKFLOW")
    active <- ci_variables[nzchar(Sys.getenv(ci_variables, unset = ""))]
    if (length(active)) {
        stop("fertility corpus runs are refused in CI and GitHub Actions", call. = FALSE)
    }
    if (!identical(Sys.getenv("DTAPARSER_FERTILITY_CORPUS"), fertility_opt_in_value)) {
        stop(paste0(
            "manual opt-in required: set DTAPARSER_FERTILITY_CORPUS=",
            fertility_opt_in_value
        ), call. = FALSE)
    }
}

fertility_required_paths <- function() {
    home <- normalizePath("~", winslash = "/", mustWork = TRUE)
    list(
        cache = "/opt/aww_cache",
        datasigs = file.path(home, "repos", "fertility_surveys", "datasigs.csv")
    )
}

fertility_atomic_save_rds <- function(value, path) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE, mode = "0700")
    Sys.chmod(dirname(path), mode = "0700")
    temporary <- tempfile(paste0(basename(path), "."), tmpdir = dirname(path))
    on.exit(unlink(temporary), add = TRUE)
    saveRDS(value, temporary, version = 3L)
    Sys.chmod(temporary, mode = "0600")
    if (!file.rename(temporary, path)) stop("could not atomically replace checkpoint")
    invisible(path)
}

fertility_atomic_write_table <- function(value, path) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE, mode = "0700")
    Sys.chmod(dirname(path), mode = "0700")
    temporary <- tempfile(paste0(basename(path), "."), tmpdir = dirname(path))
    on.exit(unlink(temporary), add = TRUE)
    write.table(value, temporary, sep = "\t", row.names = FALSE, quote = FALSE,
                na = "")
    Sys.chmod(temporary, mode = "0600")
    if (!file.rename(temporary, path)) stop("could not atomically replace report")
    invisible(path)
}

fertility_file_sha512 <- function(path) {
    if (!requireNamespace("openssl", quietly = TRUE)) stop("openssl is required")
    unname(unclass(tolower(as.character(openssl::sha512(file(path))))))
}

fertility_stable_id <- function(fields) {
    values <- vapply(names(fields), function(name) {
        value <- fields[[name]]
        if (length(value) != 1L) stop("stable ID fields must be scalar")
        paste0(name, "=", as.character(value[[1L]]))
    }, character(1))
    unname(unclass(tolower(as.character(openssl::sha256(
        charToRaw(paste(values, collapse = "\n"))
    )))))
}

fertility_release <- function(path) {
    connection <- file(path, open = "rb")
    on.exit(close(connection), add = TRUE)
    bytes <- readBin(connection, "raw", n = 256L)
    if (!length(bytes)) stop("empty DTA input")
    modern_prefix <- charToRaw("<stata_dta>")
    is_modern <- length(bytes) >= length(modern_prefix) &&
        identical(bytes[seq_along(modern_prefix)], modern_prefix)
    if (is_modern) {
        needle <- charToRaw("<release>")
        starts <- seq_len(length(bytes) - length(needle) + 1L)
        found <- starts[vapply(starts, function(start) {
            identical(bytes[start:(start + length(needle) - 1L)], needle)
        }, logical(1))]
        if (length(found) != 1L) stop("modern DTA release marker is missing")
        release_start <- found[[1L]] + length(needle)
        release <- rawToChar(bytes[release_start:(release_start + 2L)])
        if (!grepl("^[0-9]{3}$", release)) stop("modern DTA release is invalid")
        return(as.integer(release))
    }
    as.integer(bytes[[1L]])
}

fertility_build_inventory <- function(paths = fertility_required_paths(),
                                      assert_counts = TRUE,
                                      enforce_required_paths = TRUE) {
    expected_cache <- "/opt/aww_cache"
    expected_datasigs <- file.path(normalizePath("~", winslash = "/", mustWork = TRUE),
                                   "repos", "fertility_surveys", "datasigs.csv")
    if (enforce_required_paths &&
        (!identical(paths$cache, expected_cache) ||
         !identical(paths$datasigs, expected_datasigs))) {
        stop("corpus paths are fixed to /opt/aww_cache and ~/repos/fertility_surveys/datasigs.csv")
    }
    if (!dir.exists(paths$cache)) stop("required /opt/aww_cache directory is missing")
    cache_root <- normalizePath(paths$cache, winslash = "/", mustWork = TRUE)
    if (!file.exists(paths$datasigs)) {
        stop("required ~/repos/fertility_surveys/datasigs.csv file is missing")
    }
    rows <- read.csv(paths$datasigs, colClasses = "character", check.names = FALSE,
                     stringsAsFactors = FALSE)
    required <- c("program", "survey", "level", "sha512")
    if (!all(required %in% names(rows))) stop("datasigs.csv is missing required columns")

    path1 <- c(
        dhs = "DHS/Original_Data", mics = "MICS/Data/Original Data",
        wfs = "WFS/Data", nsfg = "NSFG/Data/Original Data",
        enadid = "ENADID/Data/Original Data"
    )
    path2 <- c(dhs = "DHS/Original_Data_Provenance_Unknown")
    inventory <- vector("list", nrow(rows))
    for (i in seq_len(nrow(rows))) {
        program <- tolower(rows$program[[i]])
        level <- tolower(rows$level[[i]])
        if (!(program %in% names(path1))) stop("datasigs.csv contains an unknown program")
        if (!(level %in% c("women", "births"))) stop("datasigs.csv contains an unknown level")
        folder <- if (identical(program, "wfs")) "" else
            gsub("_", ",", rows$survey[[i]], fixed = TRUE)
        filename <- if (identical(program, "wfs")) {
            paste0(rows$survey[[i]], ".dta")
        } else if (identical(level, "women")) "wm.dta" else "bh.dta"
        candidates <- file.path(paths$cache, unname(path1[[program]]), folder, filename)
        if (program %in% names(path2)) {
            candidates <- c(candidates, file.path(
                paths$cache, unname(path2[[program]]), folder, filename
            ))
        }
        present <- candidates[file.exists(candidates)]
        if (!length(present)) stop(sprintf("inventory row F%04d is missing", i))
        # Match check_raw_data.r exactly: the primary path wins and the DHS
        # provenance-unknown path is consulted only when the primary is absent.
        resolved <- normalizePath(present[[1L]], winslash = "/", mustWork = TRUE)
        if (!startsWith(resolved, paste0(cache_root, "/"))) {
            stop(sprintf("inventory row F%04d resolves outside the cache root", i))
        }
        inventory[[i]] <- data.frame(
            id = sprintf("F%04d", i), program = program, level = level,
            release = fertility_release(resolved), path = resolved,
            expected_sha512 = tolower(rows$sha512[[i]]),
            stringsAsFactors = FALSE
        )
    }
    inventory <- do.call(rbind, inventory)
    if (anyDuplicated(inventory$id) || anyDuplicated(inventory$path)) {
        stop("inventory IDs and resolved input paths must be unique")
    }
    if (assert_counts) {
        if (nrow(inventory) != fertility_expected_rows) {
            stop("expected exactly 1,004 datasigs.csv rows")
        }
        actual <- table(factor(inventory$release,
                               levels = as.integer(names(fertility_expected_releases))))
        names(actual) <- names(fertility_expected_releases)
        if (!identical(as.integer(actual), as.integer(fertility_expected_releases))) {
            stop("DTA release counts do not match the expected corpus inventory")
        }
        if (any(!(inventory$release %in% as.integer(names(fertility_expected_releases))))) {
            stop("corpus contains an unexpected DTA release")
        }
    }
    inventory
}

fertility_public_inventory <- function(inventory) {
    inventory[c("id", "program", "level", "release")]
}
