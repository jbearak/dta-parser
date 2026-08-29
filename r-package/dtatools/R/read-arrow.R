#' Read a dtatools Arrow profile file
#'
#' Reads an Arrow IPC file written by [save_arrow()] through the native Rust
#' reader, restoring the Stata semantics recorded by the dtatools Arrow
#' profile: storage declarations with compact ALTREP backing, raw Stata
#' missing storage (system missing and tagged codes `.a` through `.z`,
#' bit-exactly), labels, display formats, notes, and value-label tables.
#' Standard R semantics that [save_dta()] cannot round-trip are restored too:
#' factor levels and orderedness, `POSIXct` timezones, `difftime` units, and
#' the integer-versus-double distinction.
#'
#' Plain Arrow IPC files written by other tools are read as ordinary R
#' columns; they never acquire Stata semantics. Files carrying a newer
#' profile version than this package understands are a hard error naming that
#' version; pass `profile = FALSE` to read such a file as plain Arrow data.
#'
#' Only the Arrow IPC file variant (`.arrow`) is handled, not the IPC stream
#' variant. Column projection reads only the selected columns' buffers, and
#' `skip`/`n_max` read only the record batches that overlap the requested
#' rows.
#'
#' @param file A path, URL, raw vector, or binary connection holding an Arrow
#'   IPC file. Unlike [read_dta()], no extension is appended to extensionless
#'   paths.
#' @param col_select One or more tidyselect expressions. Predicates see each
#'   column's R type as recorded in the file: logical, integer, double,
#'   character, factor, or raw.
#' @param skip Number of rows to skip. Must be one non-negative whole number
#'   no larger than `2^53`.
#' @param n_max Maximum rows to read. `NA`, either infinity, and negative
#'   finite values read all remaining rows.
#' @param verify Whether to verify the profile's per-buffer xxHash64
#'   checksums while reading. Verification is on by default and detects
#'   corrupted buffers; it applies only to files carrying the dtatools Arrow
#'   profile.
#' @param profile Whether to apply dtatools Arrow profile metadata. Setting
#'   `FALSE` reads the file as plain Arrow data with standard semantics only,
#'   which also disables checksum verification: the checksums are profile
#'   metadata.
#' @param .name_repair Name repair passed to [tibble::as_tibble()].
#' @param use_numeric_altrep Whether profiled byte, int, long, and float
#'   columns should retain their compact Stata storage through ALTREP. Set to
#'   `FALSE` to create eager R double vectors while reading.
#' @param threads Number of threads for record-batch decoding, checksum
#'   verification, and column conversion. `0` (the default) chooses
#'   automatically based on the input size and machine; `1` disables
#'   parallelism.
#' @param datasig Whether to record the file's [datasig()] signature in the
#'   result's `datasig` attribute. The signature is derived from the file's
#'   stored footer checksums and schema documents without rehashing any data,
#'   so it costs almost nothing and covers the complete file even under
#'   `col_select`, `skip`, or `n_max` — it is a record of what the whole file
#'   on disk signs as, not of the projection loaded, and it is never updated
#'   afterwards. Because it restates what the file declares, pair it with
#'   `verify = TRUE` (and a full read) when the checksums themselves must be
#'   validated against the stored bytes. Requires a file written with
#'   checksums; only file paths are supported.
#' @return A tibble.
#' @export
read_arrow <- function(file, col_select = NULL, skip = 0, n_max = Inf,
                       verify = TRUE, profile = TRUE,
                       .name_repair = "unique",
                       use_numeric_altrep = getOption(
                           "dtatools.numeric_altrep", TRUE
                       ),
                       threads = getOption("dtatools.threads", 0L),
                       datasig = FALSE) {
    selection <- rlang::enquo(col_select)
    row_window <- .normalize_row_window(skip, n_max)
    verify <- .normalize_arrow_flag(verify, "verify")
    profile <- .normalize_arrow_flag(profile, "profile")
    datasig <- .normalize_arrow_flag(datasig, "datasig")
    use_numeric_altrep <- .normalize_use_numeric_altrep(use_numeric_altrep)
    threads <- .normalize_threads(threads)

    source <- .resolve_dta_source(
        file, fileext = ".arrow", implicit_extension = FALSE
    )
    on.exit(.cleanup_dta_source(source), add = TRUE)

    if (rlang::quo_is_null(selection)) {
        column_indices <- NULL
    } else {
        metadata <- .arrow_metadata(source$path)
        selection_proxy <- stats::setNames(
            lapply(metadata$types, .arrow_selection_proxy),
            metadata$names
        )
        selected <- tidyselect::eval_select(selection, selection_proxy)
        selected <- selected[!duplicated(unname(selected))]
        column_indices <- as.integer(unname(selected) - 1L)
        selected_names <- names(selected)
    }

    native <- .Call(
        C_dtatools_read_arrow,
        source$path,
        column_indices,
        row_window$skip,
        row_window$n_max,
        verify,
        profile,
        use_numeric_altrep,
        threads
    )
    if (!is.null(column_indices)) {
        names(native) <- selected_names
    }

    dataset_label <- attr(native, "label", exact = TRUE)
    dataset_notes <- attr(native, "notes", exact = TRUE)
    result <- tibble::as_tibble(native, .name_repair = .name_repair)
    if (!is.null(dataset_label)) attr(result, "label") <- dataset_label
    if (!is.null(dataset_notes)) attr(result, "notes") <- dataset_notes
    if (datasig) {
        attr(result, "datasig") <- .Call(
            C_dtatools_arrow_datasig, source$path
        )
    }
    result
}

.arrow_metadata <- function(file) {
    metadata <- .Call(C_dtatools_arrow_metadata, file)
    list(names = metadata[[1L]], types = metadata[[2L]])
}

.arrow_selection_proxy <- function(type) {
    switch(type,
        logical = logical(),
        integer = integer(),
        character = character(),
        factor = factor(),
        raw = raw(),
        double()
    )
}

.normalize_arrow_flag <- function(value, argument) {
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
        stop(sprintf("`%s` must be one non-missing logical value", argument),
             call. = FALSE)
    }
    value
}
