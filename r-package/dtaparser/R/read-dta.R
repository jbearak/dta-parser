#' Read a Stata DTA file
#'
#' Reads releases 105, 108, 110--111, 113--115, and 117--119 through the native Rust parser.
#' Numeric and character columns are created directly by native code. Dataset
#' and variable labels, dataset notes, Stata display formats, value labels,
#' `strL` content, and Stata system/extended missing values are retained.
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
#'   Windows-1252 for releases 105, 108, 110--111, 113--115, and 117 and UTF-8 for releases
#'   118--119. Explicit UTF-8
#'   replaces malformed input sequences deterministically with U+FFFD. Haven
#'   2.5.5 may instead omit an affected label.
#' @param col_select One or more tidyselect expressions. Predicates see Stata
#'   string storage as character and numeric storage as double. If a source
#'   variable is selected more than once, its first selection and alias win.
#'   Selection is resolved from metadata before observation data are read.
#' @param skip Number of observations to skip. Must be one non-negative whole
#'   number no larger than `2^53`.
#' @param n_max Maximum observations to read. `NA`, either infinity, and
#'   negative finite values read all remaining rows, following haven's
#'   unlimited-row convention. Non-negative values must be whole numbers no
#'   larger than `2^53`.
#' @param .name_repair Name repair passed to [tibble::as_tibble()].
#' @return A tibble. `%td` columns and legacy or custom formats beginning `%d`
#'   have class `Date`; `%tc` and `%tC` columns have classes `POSIXct` and
#'   `POSIXt` in UTC. Other Stata temporal formats remain numeric with their
#'   `format.stata` attribute.
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
    row_window <- .normalize_row_window(skip, n_max)

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
        row_window$skip,
        row_window$n_max,
        identical(materialization, "direct"),
        encoding
    )
    if (!is.null(column_indices)) {
        names(native) <- selected_names
    }

    dataset_label <- attr(native, "label", exact = TRUE)
    dataset_notes <- attr(native, "notes", exact = TRUE)
    result <- tibble::as_tibble(native, .name_repair = .name_repair)
    if (!is.null(dataset_label)) attr(result, "label") <- dataset_label
    if (!is.null(dataset_notes)) attr(result, "notes") <- dataset_notes
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

.normalize_row_window <- function(skip, n_max) {
    list(
        skip = .normalize_skip(skip),
        n_max = .normalize_n_max(n_max)
    )
}

.normalize_skip <- function(value) {
    .validate_count_shape(value, "skip")
    if (is.na(value) || !is.finite(value) || value < 0 ||
        value > 2^53 || (!is.integer(value) && value != floor(value))) {
        stop(
            "`skip` must be one non-negative whole number no larger than 2^53",
            call. = FALSE
        )
    }
    as.double(value)
}

.normalize_n_max <- function(value) {
    if (length(value) != 1L) {
        stop("`n_max` must have length 1", call. = FALSE)
    }

    # Bare NA is logical in R, but it is the conventional spelling of haven's
    # unlimited-row sentinel. Other logical and non-numeric values remain
    # invalid rather than entering native coercion.
    if (identical(value, NA)) return(Inf)
    .validate_count_type(value, "n_max")
    if (is.na(value)) {
        if (is.nan(value)) {
            stop("`n_max` must not be NaN", call. = FALSE)
        }
        return(Inf)
    }
    if (is.infinite(value) || value < 0) return(Inf)
    if (value > 2^53 || (!is.integer(value) && value != floor(value))) {
        stop(paste(
            "`n_max` must be a whole number no larger than 2^53,",
            "or an unlimited-row sentinel"
        ), call. = FALSE)
    }
    as.double(value)
}

.validate_count_shape <- function(value, argument) {
    if (length(value) != 1L) {
        stop(sprintf("`%s` must have length 1", argument), call. = FALSE)
    }
    .validate_count_type(value, argument)
}

.validate_count_type <- function(value, argument) {
    if (is.object(value) || !(typeof(value) %in% c("integer", "double"))) {
        stop(sprintf("`%s` must be one integer or double", argument),
             call. = FALSE)
    }
}
