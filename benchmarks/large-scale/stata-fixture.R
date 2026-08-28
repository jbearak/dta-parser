stata_fixture_storage <- c(
    byte = 4L, int = 4L, long = 9L, float = 4L, double = 9L,
    string = 10L
)
stata_fixture_schema <- paste(
    names(stata_fixture_storage), stata_fixture_storage,
    sep = "=", collapse = ","
)
stata_fixture_columns <- sum(stata_fixture_storage)
stata_fixture_row_bytes <- 431L
stata_fixture_calibration_rows <- 1000L

validate_stata_fixture_paths <- function(manifest_path, paths) {
    paths <- as.character(paths)
    if (length(paths) != 2L || anyNA(paths) ||
        !identical(
            basename(paths),
            c("synthetic-100mb.dta", "synthetic-1gb.dta")
        )) {
        stop("Stata fixture manifest paths are invalid")
    }
    target_root <- normalizePath(
        dirname(manifest_path), winslash = "/", mustWork = TRUE
    )
    generations_root <- file.path(target_root, "fixture-generations")
    links <- Sys.readlink(c(generations_root, paths))
    if (any(!is.na(links) & nzchar(links))) {
        stop("Stata fixture generation paths must not be symbolic links")
    }
    generations_root <- normalizePath(
        generations_root, winslash = "/", mustWork = TRUE
    )
    resolved <- vapply(
        paths, normalizePath, character(1L), winslash = "/",
        mustWork = TRUE
    )
    generation_dirs <- unique(dirname(resolved))
    if (length(generation_dirs) != 1L ||
        !identical(dirname(generation_dirs), generations_root) ||
        !grepl("^[0-9a-f]{32}$", basename(generation_dirs))) {
        stop("Stata fixture manifest does not select one immutable generation")
    }
    info <- file.info(resolved, extra_cols = FALSE)
    if (anyNA(info$isdir) || any(info$isdir)) {
        stop("Stata fixture generation files are invalid")
    }
    unname(resolved)
}

read_stata_fixture_manifest <- function(manifest_path, generator_sha256) {
    generator_sha256 <- benchmark_validate_sha256(
        generator_sha256, 1L, "Stata fixture generator"
    )
    datasets <- read.delim(
        manifest_path, check.names = FALSE, stringsAsFactors = FALSE,
        colClasses = "character"
    )
    required <- c(
        "dataset", "path", "target_bytes", "actual_bytes", "sha256",
        "rows", "columns", "obs_bytes", "base_rows", "creator",
        "generator_sha256"
    )
    if (!all(required %in% names(datasets)) || nrow(datasets) != 2L ||
        !identical(as.character(datasets$dataset), c("100mb", "1gb"))) {
        stop("dataset manifest is invalid")
    }

    numeric_fields <- c(
        "target_bytes", "actual_bytes", "rows", "columns", "obs_bytes",
        "base_rows"
    )
    for (field in numeric_fields) {
        value <- suppressWarnings(as.double(datasets[[field]]))
        if (any(!is.finite(value) | value <= 0 | value != floor(value))) {
            stop("manifest field is not positive integral: ", field)
        }
        datasets[[field]] <- value
    }
    if (!identical(datasets$target_bytes, c(100000000, 1000000000))) {
        stop("dataset manifest target sizes are invalid")
    }

    datasets$path <- validate_stata_fixture_paths(
        manifest_path, datasets$path
    )
    generator_hashes <- tolower(as.character(datasets$generator_sha256))
    if (anyNA(datasets$creator) || anyNA(generator_hashes) ||
        any(!grepl("^[0-9a-f]{64}$", generator_hashes)) ||
        any(generator_hashes != generator_sha256) ||
        any(datasets$creator != "stata-first-save") ||
        any(datasets$columns != stata_fixture_columns) ||
        any(datasets$obs_bytes != stata_fixture_row_bytes)) {
        stop("dataset manifest does not match the current Stata generator")
    }
    if (length(unique(datasets$base_rows)) != 1L) {
        stop("scaled datasets disagree on base row metadata")
    }
    overhead <- datasets$actual_bytes - datasets$rows * datasets$obs_bytes
    if (any(overhead <= 0) || length(unique(overhead)) != 1L) {
        stop("scaled dataset row width and overhead are inconsistent")
    }
    if (any(abs(datasets$actual_bytes - datasets$target_bytes) >
            datasets$obs_bytes / 2 + 0.5)) {
        stop("scaled dataset size is inconsistent with its target")
    }

    actual_sizes <- as.double(file.info(datasets$path)$size)
    if (!identical(actual_sizes, datasets$actual_bytes)) {
        stop("dataset file size does not match manifest actual_bytes")
    }
    expected_hashes <- tolower(as.character(datasets$sha256))
    if (anyNA(expected_hashes) ||
        any(!grepl("^[0-9a-f]{64}$", expected_hashes))) {
        stop("dataset manifest contains an invalid SHA-256")
    }
    actual_hashes <- benchmark_file_sha256(datasets$path)
    if (!identical(actual_hashes, expected_hashes)) {
        stop("dataset SHA-256 does not match manifest")
    }

    datasets$sha256 <- expected_hashes
    datasets$generator_sha256 <- generator_hashes
    datasets$overhead_bytes <- overhead
    datasets
}

parse_fixture_write_result <- function(fields, writer) {
    if (length(fields) != 6L || fields[[1L]] != writer ||
        fields[[2L]] != "ok") {
        stop(writer, " fixture write failed")
    }
    numeric <- suppressWarnings(as.numeric(fields[3:6]))
    if (any(!is.finite(numeric)) || numeric[[1L]] < 0 ||
        numeric[[2L]] <= 0 || numeric[[3L]] != stata_fixture_columns ||
        numeric[[4L]] <= 0) {
        stop(writer, " fixture write returned invalid measurements")
    }
    list(
        elapsed_seconds = numeric[[1L]], rows = numeric[[2L]],
        columns = numeric[[3L]], bytes = numeric[[4L]]
    )
}

read_stata_fixture_result <- function(path) {
    fields <- strsplit(
        readLines(path, n = 1L, warn = FALSE), "\t", fixed = TRUE
    )[[1L]]
    parse_fixture_write_result(fields, "stata")
}
