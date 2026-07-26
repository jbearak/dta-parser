#' Read a Stata DTA file
#'
#' Reads releases 113--115 and 117--119 through the native Rust parser.
#' Numeric and character columns are created directly by native code. Dataset
#' and variable labels, Stata display formats, value labels, `strL` content,
#' and Stata system/extended missing values are retained.
#'
#' @param file A path, URL, raw vector, or binary connection. Local and remote
#'   gzip files and local bzip2, xz, and zip files are decompressed
#'   automatically. Character vectors containing literal data are not handled,
#'   matching `haven::read_dta()`. URLs are fetched at call time; applications
#'   accepting untrusted `file` values should validate or allowlist sources
#'   before calling `read_dta()`.
#' @param encoding Optional source encoding override. Supported aliases are
#'   `"UTF-8"`/`"UTF8"`, `"Windows-1252"`/`"CP1252"`, and
#'   `"ISO-8859-1"`/`"latin1"`, matched case-insensitively. `NULL` uses
#'   Windows-1252 for legacy files and UTF-8 for modern files. Explicit UTF-8
#'   replaces malformed input sequences deterministically with U+FFFD. Haven
#'   2.5.5 may instead omit an affected label.
#' @param col_select One or more tidyselect expressions. Predicates see Stata
#'   string storage as character and numeric storage as double. If a source
#'   variable is selected more than once, its first selection and alias win.
#'   Selection is resolved from metadata before observation data are read.
#' @param skip Number of observations to skip.
#' @param n_max Maximum observations to read. `Inf` reads all remaining rows.
#' @param .name_repair Name repair passed to [tibble::as_tibble()].
#' @return A tibble. `%td` columns have class `Date`; `%tc` and `%tC` columns
#'   have classes `POSIXct` and `POSIXt` in UTC. Other Stata temporal formats
#'   remain numeric with their `format.stata` attribute.
#' @export
read_dta <- function(file, encoding = NULL, col_select = NULL, skip = 0,
                     n_max = Inf, .name_repair = "unique") {
    .read_dta_impl(
        file, encoding, rlang::enquo(col_select), skip, n_max, .name_repair,
        materialization = "direct"
    )
}

# Internal A/B baseline. This deliberately retains the former two-stage path
# so direct-to-R materialization can be benchmarked and checked independently.
.read_dta_rust_vectors <- function(file, encoding = NULL, col_select = NULL,
                                   skip = 0, n_max = Inf,
                                   .name_repair = "unique") {
    .read_dta_impl(
        file, encoding, rlang::enquo(col_select), skip, n_max, .name_repair,
        materialization = "rust-vectors"
    )
}

.read_dta_impl <- function(file, encoding, selection, skip, n_max,
                           .name_repair, materialization) {
    encoding <- .validate_dta_encoding(encoding)
    .validate_count(skip, "skip", infinite = FALSE)
    .validate_count(n_max, "n_max", infinite = TRUE)

    source <- .resolve_dta_source(file)
    on.exit(.cleanup_dta_source(source), add = TRUE)
    metadata_names <- .dta_metadata(source$path, encoding)

    if (rlang::quo_is_null(selection)) {
        column_indices <- NULL
        selected_names <- metadata_names
    } else {
        storage <- attr(metadata_names, "dta_storage", exact = TRUE)
        selection_proxy <- stats::setNames(
            lapply(storage, function(type) {
                if (identical(type, "character")) character() else double()
            }),
            metadata_names
        )
        selected <- tidyselect::eval_select(selection, selection_proxy)
        selected <- selected[!duplicated(unname(selected))]
        column_indices <- as.integer(unname(selected) - 1L)
        selected_names <- names(selected)
    }

    native <- .Call(
        C_dtaparser_read,
        source$path,
        column_indices,
        as.double(skip),
        as.double(n_max),
        identical(materialization, "direct"),
        encoding
    )
    if (!is.null(column_indices)) {
        names(native) <- selected_names
    }

    dataset_label <- attr(native, "label", exact = TRUE)
    format_version <- attr(native, "dta_format_version", exact = TRUE)
    result <- tibble::as_tibble(native, .name_repair = .name_repair)
    if (!is.null(dataset_label)) attr(result, "label") <- dataset_label
    if (!is.null(format_version)) {
        attr(result, "dta_format_version") <- format_version
    }
    result
}

.resolve_dta_source <- function(file) {
    caller_supplied_source <- inherits(file, "source")
    caller_path <- .caller_dta_source_path(file)
    datasource <- readr::datasource(file)
    source_type <- class(datasource)[[1L]]

    if (identical(source_type, "source_file")) {
        path <- normalizePath(datasource[[1L]], winslash = "/", mustWork = TRUE)
        # Delete only a direct child of tempdir() that differs from a canonical
        # caller-owned path. Ownership never depends on datasource internals,
        # and a caller-supplied source object is always left to its caller.
        temporary_parent <- dirname(path)
        temporary_root <- normalizePath(
            tempdir(), winslash = "/", mustWork = TRUE
        )
        comparison_path <- path
        if (identical(.Platform$OS.type, "windows")) {
            temporary_parent <- tolower(temporary_parent)
            temporary_root <- tolower(temporary_root)
            comparison_path <- tolower(comparison_path)
            if (!is.null(caller_path)) caller_path <- tolower(caller_path)
        }
        temporary <- !caller_supplied_source &&
            identical(temporary_parent, temporary_root) &&
            (is.null(caller_path) || !identical(comparison_path, caller_path))
        return(list(
            path = path,
            temporary = temporary,
            datasource = datasource
        ))
    }

    if (identical(source_type, "source_raw")) {
        path <- tempfile(pattern = "dtaparser-", fileext = ".dta")
        complete <- FALSE
        on.exit(if (!complete) unlink(path), add = TRUE)
        writeBin(datasource[[1L]], path)
        complete <- TRUE
        return(list(path = path, temporary = TRUE, datasource = datasource))
    }

    stop("This kind of input is not handled.", call. = FALSE)
}

.caller_dta_source_path <- function(file) {
    path <- NULL
    if (is.character(file) && length(file) == 1L && !is.na(file) &&
        file.exists(file)) {
        path <- file
    } else if (inherits(file, "connection")) {
        description <- summary(file)$description
        if (is.character(description) && length(description) == 1L &&
            !is.na(description) && file.exists(description)) {
            path <- description
        }
    }

    if (is.null(path)) return(NULL)
    normalizePath(path, winslash = "/", mustWork = TRUE)
}

.cleanup_dta_source <- function(source) {
    if (isTRUE(source$temporary)) {
        unlink(source$path)
    }
    invisible(NULL)
}

.dta_metadata <- function(file, encoding = NULL) {
    .Call(C_dtaparser_metadata, file, encoding)
}

.validate_dta_encoding <- function(encoding) {
    if (is.null(encoding)) return(NULL)
    if (!is.character(encoding) || length(encoding) != 1L || is.na(encoding)) {
        stop("`encoding` must be NULL or one non-missing character string",
             call. = FALSE)
    }
    key <- tolower(gsub("[-_ ]", "", encoding))
    canonical <- switch(key,
        utf8 = "UTF-8",
        windows1252 = "Windows-1252",
        cp1252 = "Windows-1252",
        iso88591 = "ISO-8859-1",
        latin1 = "ISO-8859-1",
        NULL
    )
    if (is.null(canonical)) {
        stop(sprintf(
            "unsupported `encoding` %s; use UTF-8, Windows-1252, or ISO-8859-1",
            encodeString(encoding, quote = "\"")
        ), call. = FALSE)
    }
    canonical
}

.validate_count <- function(value, argument, infinite) {
    valid_infinite <- infinite && is.numeric(value) && length(value) == 1L &&
        is.infinite(value) && value > 0
    valid_finite <- is.numeric(value) && length(value) == 1L && !is.na(value) &&
        is.finite(value) && value >= 0 && value == floor(value) && value <= 2^53
    if (!valid_infinite && !valid_finite) {
        stop(sprintf("`%s` must be one non-negative whole number%s", argument,
            if (infinite) " or Inf" else ""), call. = FALSE)
    }
}
