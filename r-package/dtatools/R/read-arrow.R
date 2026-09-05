#' Read a dtatools `.arrow` dataset
#'
#' Reads a standalone `.arrow` dataset written by [save_arrow()], restoring its
#' supported Stata-specific and ordinary R column classes and metadata. These
#' include storage declarations with compact ALTREP backing, raw Stata missing
#' storage (system missing and tagged codes `.a` through `.z`, bit-exactly),
#' labels, display formats, numbered notes, arbitrary Stata characteristics,
#' value-label tables, factor levels and orderedness, ordinary `POSIXct`
#' timezones, `difftime` units, and the
#' integer-versus-double distinction.
#' Imported Stata table identity is restored in the `value.label.name` column
#' attribute when the table name differs from the field name or several source
#' fields refer to it. Sharing is determined from the complete source schema,
#' including fields omitted by projection.
#'
#' Apache Arrow stores tabular data by column in a standard binary layout. The
#' on-disk format uses Arrow's IPC (interprocess communication) file format to
#' exchange that data between programs. The native Rust reader applies the
#' additional dtatools profile metadata.
#'
#' Plain Arrow IPC files written by other tools are read as ordinary R
#' columns; they never acquire Stata semantics. Files carrying a newer
#' profile version than this package understands are a hard error naming that
#' version; pass `profile = FALSE` to read such a file as plain Arrow data.
#' A profiled projection resolved without predicates validates the dataset
#' document and each selected field document, then discards unselected fields'
#' private documents without parsing them. A tidyselect predicate first builds
#' a full profiled summary so the predicate sees every column's restored R type;
#' that summary validates every field document. A full read also validates
#' every field document. With `profile = TRUE`, `datasig = TRUE` parses every
#' field document because the stored signature covers the complete schema.
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
#'   character, factor, or raw. A predicate-free projection validates selected
#'   field documents; a predicate or an omitted selection validates every field
#'   document when `profile = TRUE`.
#' @param skip Number of rows to skip. Must be one non-negative whole number
#'   no larger than `2^53`.
#' @param n_max Maximum rows to read. `NA`, either infinity, and negative
#'   finite values read all remaining rows.
#' @param verify Whether to check each data buffer's stored xxHash64
#'   fingerprint while reading. Verification is on by default and detects
#'   accidental file corruption; it applies only to files carrying the
#'   dtatools Arrow profile.
#' @param profile Whether to apply dtatools Arrow profile metadata. Setting
#'   `FALSE` reads the file as plain Arrow data with standard semantics only,
#'   which also disables checksum verification: the checksums are profile
#'   metadata.
#' @param .name_repair Name repair passed to [tibble::as_tibble()].
#' @param output Output container. An explicit `"dibble"`, `"tibble"`, or
#'   `"data.table"` overrides stored Arrow provenance. `"default"` restores a
#'   container recorded by [save_arrow()] and otherwise uses the
#'   `dtatools.output` option, falling back to `"dibble"`. A recorded
#'   container this release does not know reads as a tibble.
#'   `profile = FALSE` ignores stored provenance.
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
#'   validated against the stored bytes. With `profile = TRUE`, requesting the
#'   signature validates every field document even for a predicate-free
#'   projection.
#'   Requires a file written with checksums; only file paths are supported.
#' @return A [dibble][dibble()], tibble, or data table.
#' @export
read_arrow <- function(file, col_select = NULL, skip = 0, n_max = Inf,
                       verify = TRUE, profile = TRUE,
                       .name_repair = "unique",
                       output = c("default", "dibble", "tibble", "data.table"),
                       use_numeric_altrep = getOption(
                           "dtatools.numeric_altrep", TRUE
                       ),
                       threads = getOption("dtatools.threads", 0L),
                       datasig = FALSE) {
    .read_arrow_impl(
        file, rlang::enquo(col_select), skip, n_max, verify, profile,
        .name_repair, output, use_numeric_altrep, threads, datasig,
        keep_source_rows = FALSE
    )
}

.read_arrow_impl <- function(file, selection, skip, n_max, verify, profile,
                             .name_repair, output, use_numeric_altrep, threads,
                             datasig, keep_source_rows) {
    row_window <- .normalize_row_window(skip, n_max)
    verify <- .normalize_arrow_flag(verify, "verify")
    profile <- .normalize_arrow_flag(profile, "profile")
    datasig <- .normalize_arrow_flag(datasig, "datasig")
    use_numeric_altrep <- .normalize_use_numeric_altrep(use_numeric_altrep)
    threads <- .normalize_threads(threads)

    source <- .resolve_dta_source(
        file, fileext = ".arrow", implicit_extension = FALSE
    )
    snapshot <- NULL
    on.exit({
        if (!is.null(snapshot)) .Call(C_dtatools_close_arrow, snapshot)
        .cleanup_dta_source(source)
    }, add = TRUE)
    snapshot <- .Call(C_dtatools_open_arrow, source$path)

    if (rlang::quo_is_null(selection)) {
        column_indices <- NULL
    } else {
        selected <- .arrow_column_selection(
            selection, snapshot, profile, row_window
        )
        column_indices <- selected$indices
        selected_names <- selected$names
    }

    native <- .Call(
        C_dtatools_read_arrow,
        snapshot,
        column_indices,
        row_window$skip,
        row_window$n_max,
        verify,
        profile,
        use_numeric_altrep,
        threads,
        datasig,
        keep_source_rows
    )
    source_rows <- attr(native, "dtatools.source.rows", exact = TRUE)
    attr(native, "dtatools.source.rows") <- NULL
    if (!is.null(column_indices)) {
        names(native) <- selected_names
    }

    dataset_label <- attr(native, "label", exact = TRUE)
    disk_signature <- attr(native, "datasig", exact = TRUE)
    stored_output <- if (profile) {
        attr(native, "dtatools.output.container", exact = TRUE)
    }
    attr(native, "dtatools.output.container") <- NULL
    profiled <- identical(attr(native, "dtatools.profiled", exact = TRUE), 1L)
    attr(native, "dtatools.profiled") <- NULL
    result <- .finalize_output_container(
        native, output, .name_repair, stored = stored_output,
        profiled = profiled
    )
    if (!is.null(dataset_label)) attr(result, "label") <- dataset_label
    result <- .copy_dta_metadata_attributes(native, result)
    if (!is.null(disk_signature)) attr(result, "datasig") <- disk_signature
    result <- .repair_data_table_container(result)
    if (keep_source_rows) {
        attr(result, "dtatools.source.rows") <- source_rows
    }
    .complete_output_container(result, output, stored_output, profiled)
}

.arrow_metadata <- function(snapshot, profile = TRUE,
                            scan_ambiguous_int32 = FALSE,
                            skip = 0, n_max = Inf) {
    metadata <- .Call(
        C_dtatools_arrow_metadata, snapshot, profile, scan_ambiguous_int32,
        skip, n_max
    )
    list(
        names = metadata[[1L]], types = metadata[[2L]],
        value_label_names = metadata[[3L]], value_label_registry = metadata[[4L]]
    )
}

.arrow_column_selection <- function(selection, snapshot, profile, row_window) {
    metadata <- .arrow_metadata(
        snapshot, profile = FALSE, scan_ambiguous_int32 = FALSE,
        skip = row_window$skip, n_max = row_window$n_max
    )
    selection_proxy <- stats::setNames(
        lapply(metadata$types, .arrow_selection_proxy),
        metadata$names
    )
    needs_predicates <- FALSE
    selected <- tryCatch(
        tidyselect::eval_select(
            selection, selection_proxy, allow_predicates = FALSE
        ),
        tidyselect_error_predicates_unsupported = function(error) {
            needs_predicates <<- TRUE
            NULL
        }
    )
    if (needs_predicates) {
        metadata <- .arrow_metadata(
            snapshot, profile, scan_ambiguous_int32 = TRUE,
            skip = row_window$skip, n_max = row_window$n_max
        )
        selection_proxy <- stats::setNames(
            lapply(metadata$types, .arrow_selection_proxy),
            metadata$names
        )
        selected <- tidyselect::eval_select(selection, selection_proxy)
    }
    selected <- selected[!duplicated(unname(selected))]
    list(
        indices = as.integer(unname(selected) - 1L),
        names = names(selected)
    )
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
