#' Write a standalone dtatools `.arrow` dataset
#'
#' Writes a data frame to one standalone `.arrow` file. This is a separate
#' output choice from [save_dta()], and it can preserve a mix of supported
#' Stata-specific columns and ordinary R column classes.
#'
#' Apache Arrow stores tabular data by column in a standard binary layout. This
#' format uses Arrow's IPC (interprocess communication) file format to exchange
#' that data between programs. Compatible Arrow IPC readers can access the
#' standard storage arrays, but only profile-aware readers restore the added
#' dtatools semantics. The profile records storage declarations, raw Stata
#' missing storage (sentinel integers and tagged NaN payloads), display formats,
#' labels, numbered notes, arbitrary Stata characteristics, value-label tables,
#' and the R semantics that standard Arrow types alone do not express.
#' Experimental profile version `"0"` carries no
#' cross-version stability promise yet.
#'
#' @section Conversions and metadata:
#' Bare logical, integer, double, character, raw, and factor columns become
#' Boolean, Int32, Float64, Utf8, UInt8, and dictionary-encoded Utf8 columns.
#' `Date`, `POSIXct`, and `difftime` columns become Date32, Timestamp, and
#' Duration columns when exactly representable, with a Float64 fallback that
#' still restores the R class on read. Columns with a `stata.storage`
#' declaration keep raw Stata missing storage: compact ALTREP backing is
#' written directly without widening to doubles, and tagged missing codes
#' `.a` through `.z` survive bit-exactly. haven `labelled` double columns are
#' accepted and round-trip with their `labels` attribute. Values a declared
#' Stata storage type cannot represent become Stata system missing with one
#' aggregated warning per conversion category. Attributes outside the profile's
#' documented set are dropped with one warning naming each affected column and
#' attribute.
#' The recognized `value.label.name` attribute preserves an imported nondefault
#' or shared Stata table name in the existing dataset registry and field
#' reference. Columns that claim one name with different mappings produce one
#' aggregated warning and fall back to separate variable-name tables.
#'
#' Unlike [save_dta()], factor class and orderedness, `POSIXct` timezones on
#' ordinary R columns, and `difftime` units are preserved on read.
#'
#' @section Output safety:
#' Only local files are supported. The complete input is validated before
#' native serialization starts, including the Arrow reader's 64 MiB aggregate
#' footer-metadata limit. This limit covers the encoded schema, profile JSON,
#' checksum document, and record-batch index rather than each value separately.
#' Output streams to a sibling temporary file and atomically replaces the
#' destination only after the file is closed.
#' Symbolic-link, directory, and other non-regular destinations are rejected.
#'
#' @param data A data frame or tibble.
#' @param path Local output path. If the final filename has no extension,
#'   `.arrow` is appended with a warning.
#' @param compression Per-buffer body compression: `"uncompressed"`, `"lz4"`
#'   (LZ4 frame), or `"zstd"`.
#' @param label Dataset label. Defaults to the data frame's `label` attribute.
#' @param adjust_tz For `POSIXct` columns with a `stata.storage` declaration,
#'   whether to preserve displayed clock time (`TRUE`) or the underlying UTC
#'   instant (`FALSE`), matching [save_dta()]. Standard `POSIXct` columns are
#'   unaffected: Arrow timestamps store the instant and the timezone. A
#'   Stata-backed column's `tzone` is used for this conversion but is not stored;
#'   reading it restores UTC, matching a DTA round-trip.
#' @param threads Number of threads used to encode columns into Arrow
#'   buffers. `0` (the default) selects a thread count automatically; `1`
#'   forces serial encoding. Defaults to the `dtatools.threads` option.
#' @param checksums Whether to store an xxHash64 fingerprint for each data
#'   buffer (the default). [read_arrow()] checks these fingerprints to detect
#'   accidental file corruption. Files written with `checksums = FALSE` are
#'   slightly smaller and faster to write, but [read_arrow()] can only read them
#'   with `verify = FALSE`.
#' @return `data`, invisibly.
#' @examples
#' path <- tempfile(fileext = ".arrow")
#' data <- data.frame(answer = stata_byte(c(1, tagged_missing("a"))))
#' save_arrow(data, path)
#' read_arrow(path)
#' unlink(path)
#' @export
save_arrow <- function(data, path,
                       compression = c("uncompressed", "lz4", "zstd"),
                       label = attr(data, "label", exact = TRUE),
                       adjust_tz = TRUE,
                       threads = getOption("dtatools.threads", 0L),
                       checksums = TRUE) {
    original_data <- data
    write_data <- .reference_snapshot(data)
    threads <- .normalize_threads(threads)
    checksums <- .normalize_arrow_flag(checksums, "checksums")
    resolved_path <- .resolve_dta_write_path(path, "arrow")
    for (write_warning in resolved_path$warnings) {
        .dta_write_warn(write_warning$message, write_warning$class)
    }
    compression <- .arrow_write_compression(compression)
    specification <- .prepare_arrow_write(write_data, label, adjust_tz)
    destination <- resolved_path$path
    write_warnings <- attr(specification, "write_warnings", exact = TRUE)
    write_warnings <- .emit_dta_write_preflight_warnings(write_warnings)

    temporary <- tempfile(
        pattern = paste0(".", basename(destination), "-dtatools-"),
        tmpdir = dirname(destination), fileext = ".tmp"
    )
    on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
    numeric_replacements <- tryCatch(
        .Call(
            C_dtatools_save_arrow, specification, temporary, compression,
            threads, checksums
        ),
        error = function(condition) {
            if (inherits(condition, "interrupt")) stop(condition)
            .dta_write_abort(
                conditionMessage(condition),
                "dtatools_write_native_error"
            )
        }
    )
    write_warnings <- c(write_warnings, .dta_write_count_warnings(
        numeric_replacements,
        names(write_data),
        "Converted unrepresentable numeric values to Stata system missing",
        "dtatools_write_numeric_replacement_warning"
    ))
    for (write_warning in write_warnings) {
        .dta_write_warn(write_warning$message, write_warning$class)
    }
    .commit_dta_write(temporary, destination)
    invisible(original_data)
}

.arrow_write_compression <- function(compression) {
    choices <- c("uncompressed", "lz4", "zstd")
    if (identical(compression, choices)) return(choices[[1L]])
    if (!is.character(compression) || length(compression) != 1L ||
        is.na(compression) || !(compression %in% choices)) {
        .dta_write_abort(
            "`compression` must be \"uncompressed\", \"lz4\", or \"zstd\"",
            "dtatools_write_argument_error"
        )
    }
    compression
}

.arrow_utf8 <- function(value, what) {
    if (any(Encoding(value) == "bytes")) {
        .dta_write_abort(sprintf(
            "%s cannot contain strings with `bytes` encoding; Arrow Utf8 requires Unicode text",
            what
        ))
    }
    enc2utf8(value)
}

# Kind codes shared with C_dtatools_save_arrow and the native bridge.
.arrow_write_kinds <- c(
    logical = 0L, integer = 1L, double = 2L, character = 3L, raw = 4L,
    factor = 5L, date = 6L, datetime = 7L, difftime = 8L, stata = 9L
)

.arrow_write_column_kind <- function(column) {
    if (!is.null(dim(column))) return(NA_character_)
    classes <- attr(column, "class", exact = TRUE)
    if (is.factor(column)) {
        if (all(classes %in% c("ordered", "factor"))) return("factor")
        return(NA_character_)
    }
    if (!is.null(attr(column, "stata.storage", exact = TRUE))) {
        if (identical(typeof(column), "double") && all(classes %in% c(
            "haven_labelled", "vctrs_vctr", "stata_numeric",
            "stata_temporal", "stata_date", "stata_datetime",
            paste0("stata_", .stata_storage), "double",
            "Date", "POSIXct", "POSIXt"
        ))) return("stata")
        return(NA_character_)
    }
    if (inherits(column, "Date")) {
        if (all(classes %in% "Date")) return("date")
        return(NA_character_)
    }
    if (inherits(column, "POSIXct")) {
        if (all(classes %in% c("POSIXct", "POSIXt"))) return("datetime")
        return(NA_character_)
    }
    if (inherits(column, "difftime")) {
        if (all(classes %in% "difftime")) return("difftime")
        return(NA_character_)
    }
    if (is.character(column)) {
        if (is.null(classes)) return("character")
        return(NA_character_)
    }
    if (identical(typeof(column), "raw")) {
        if (is.null(classes)) return("raw")
        return(NA_character_)
    }
    if (identical(typeof(column), "logical")) {
        if (is.null(classes)) return("logical")
        return(NA_character_)
    }
    if (identical(typeof(column), "integer")) {
        if (is.null(classes)) return("integer")
        return(NA_character_)
    }
    if (identical(typeof(column), "double")) {
        if (is.null(classes) || (
            inherits(column, "haven_labelled") &&
            all(classes %in% c("haven_labelled", "vctrs_vctr", "double"))
        )) return("double")
        return(NA_character_)
    }
    NA_character_
}

.arrow_write_difftime_units <- function(column, name) {
    units <- attr(column, "units", exact = TRUE)
    if (!is.character(units) || length(units) != 1L || is.na(units) ||
        !nzchar(units)) {
        .dta_write_abort(sprintf(
            "Column `%s` must declare its difftime units", name
        ))
    }
    units
}

.arrow_write_datetime_timezone <- function(column) {
    timezone <- attr(column, "tzone", exact = TRUE)
    if (is.null(timezone)) return(NULL)
    .write_datetime_timezone(column)
}

.prepare_arrow_write_format <- function(column, name, kind) {
    if (is.null(attr(column, "format.stata", exact = TRUE))) return("")
    category <- switch(kind,
        character = "string",
        date = "date",
        datetime = "datetime",
        "numeric"
    )
    .prepare_write_format(column, name, "", category)
}

.prepare_arrow_write_stata <- function(column, name, adjust_tz) {
    storage <- attr(column, "stata.storage", exact = TRUE)
    if (!is.character(storage) || length(storage) != 1L ||
        !(storage %in% .stata_storage)) {
        .dta_write_abort(sprintf(
            "Column `%s` has an invalid `stata.storage` declaration", name
        ))
    }
    category <- if (inherits(column, "Date")) {
        "date"
    } else if (inherits(column, "POSIXct")) {
        "datetime"
    } else {
        "numeric"
    }
    default_format <- switch(category,
        date = "%td",
        datetime = "%tc",
        numeric = .default_stata_format(storage)
    )
    format <- .prepare_write_format(column, name, default_format, category)
    values <- column
    temporal <- switch(category,
        date = .stata_temporal_date,
        datetime = .stata_temporal_datetime,
        .stata_temporal_none
    )
    if (.is_unmaterialized_numeric_altrep(values) &&
        !.compact_stata_storage_matches(values, storage, temporal)) {
        values <- .force_altrep_materialization(values)
    }
    if (identical(category, "datetime") && adjust_tz) {
        timezone <- .write_datetime_timezone(column)
        if (!(timezone %in% c("UTC", "GMT"))) {
            values <- .adjust_datetime_write_values(
                as.double(column), timezone
            )
        }
    }
    list(
        values = values,
        storage_code = match(storage, .stata_storage) - 1L,
        format = format
    )
}

.prepare_arrow_write_column <- function(column, name, kind, adjust_tz,
                                        value_label_index,
                                        value_label_cache) {
    characteristics <- stata_characteristics(column)
    notes <- stata_notes(column)
    variable_label <- .arrow_utf8(
        .write_text(
            attr(column, "label", exact = TRUE),
            sprintf("variable label for `%s`", name)
        ),
        sprintf("Variable label for `%s`", name)
    )
    levels <- character()
    ordered <- FALSE
    tz <- NULL
    units <- ""
    storage_code <- -1L
    string_storage <- -1L
    values <- column
    write_kind <- kind
    haven_labelled <- inherits(column, "haven_labelled")

    value_labels <- list(double(), character(), FALSE)
    if (kind %in% c(
        "integer", "double", "date", "datetime", "difftime", "stata"
    ) && value_label_index >= 0L) {
        .validate_write_value_label_structure(column, name)
        value_labels <- .cached_write_value_labels(
            value_label_cache, value_label_index,
            function() {
                prepared <- .prepare_write_value_labels(
                    column, name, allow_legacy_codes = TRUE,
                    validate_structure = FALSE
                )
                # The Arrow native descriptor has one f64 representation for
                # integer and double label codes.
                prepared[[1L]] <- as.double(prepared[[1L]])
                prepared[[2L]] <- .arrow_utf8(
                    prepared[[2L]],
                    sprintf("Value-label text for `%s`", name)
                )
                prepared
            }
        )
    } else if (!is.null(attr(column, "labels", exact = TRUE))) {
        .dta_write_abort(sprintf(
            "Column `%s` cannot carry numeric value labels", name
        ))
    }

    # The frozen profile does not permit value-label references on Int32.
    # Promote labelled R integers to the lossless Float64 haven representation.
    if (identical(kind, "integer") && value_label_index >= 0L) {
        values <- as.double(column)
        write_kind <- "double"
        haven_labelled <- TRUE
    }

    if (identical(kind, "stata")) {
        prepared <- .prepare_arrow_write_stata(column, name, adjust_tz)
        values <- prepared$values
        storage_code <- prepared$storage_code
        format <- prepared$format
    } else {
        format <- .prepare_arrow_write_format(column, name, kind)
        if (identical(kind, "factor")) {
            levels <- levels(column)
            levels <- .arrow_utf8(
                levels, sprintf("Factor levels for `%s`", name)
            )
            ordered <- is.ordered(column)
        } else if (identical(kind, "character")) {
            declared <- attr(column, "stata.string.storage", exact = TRUE)
            if (!is.null(declared)) {
                if (!is.character(declared) || length(declared) != 1L ||
                    is.na(declared) ||
                    !grepl("^(strL|str([1-9]|[1-9][0-9]{1,2}|1[0-9]{3}|20[0-3][0-9]|204[0-5]))$", declared)) {
                    .dta_write_abort(sprintf(
                        "Column `%s` has an invalid `stata.string.storage` declaration",
                        name
                    ))
                }
                string_storage <- if (declared == "strL") 0L else
                    as.integer(sub("^str", "", declared))
            }
            # Unmaterialized dictionary-string columns are already UTF-8 and
            # export natively; enc2utf8() would materialize every CHARSXP.
            if (!.is_unmaterialized_dictstring(column)) {
                values <- .arrow_utf8(
                    column, sprintf("Character column `%s`", name)
                )
            }
        } else if (identical(kind, "date")) {
            values <- as.double(column)
        } else if (identical(kind, "datetime")) {
            tz <- .arrow_write_datetime_timezone(column)
            values <- as.double(column)
        } else if (identical(kind, "difftime")) {
            units <- .arrow_write_difftime_units(column, name)
            values <- as.double(column)
        }
    }

    format <- .arrow_utf8(format, sprintf("Display format for `%s`", name))
    if (!is.null(tz)) {
        tz <- .arrow_utf8(tz, sprintf("Timezone for `%s`", name))
    }
    units <- .arrow_utf8(units, sprintf("Difftime units for `%s`", name))

    stats::setNames(list(
        .arrow_utf8(name, "Column names"), .arrow_write_kinds[[write_kind]],
        values, levels, ordered,
        variable_label, format, storage_code, tz, units,
        double(), character(), value_labels[[3L]],
        haven_labelled, string_storage,
        as.integer(value_label_index),
        .stata_metadata_payload(notes, characteristics)
    ), c(
        "name", "kind", "values", "levels", "ordered", "label", "format",
        "storage", "tz", "units", "label_values", "label_texts",
        "has_value_labels", "haven_labelled", "string_storage",
        "value_label_index", "stata_metadata"
    ))
}

.arrow_known_column_attributes <- function(kind) {
    common <- c(
        "label", "format.stata", "stata.string.storage",
        "value.label.name", "notes", "stata.note.numbers",
        "stata.characteristics"
    )
    switch(kind,
        factor = c(common, "levels", "class"),
        date = c(common, "labels", "class"),
        datetime = c(common, "labels", "class", "tzone"),
        difftime = c(common, "labels", "class", "units"),
        stata = c(common, "labels", "stata.storage", "class"),
        double = c(common, "labels", "class"),
        integer = c(common, "labels"),
        common
    )
}

.arrow_dropped_attribute_warnings <- function(data, kinds) {
    details <- character()
    known_dataset_attributes <- c(
        "names", "label", "notes", "stata.note.numbers",
        "stata.characteristics"
    )
    if (.row_names_info(data, type = 1L) <= 0L) {
        known_dataset_attributes <- c(known_dataset_attributes, "row.names")
    }
    dataset_class <- attr(data, "class", exact = TRUE)
    ordinary_dataset_class <- setdiff(
        dataset_class, "dtatools_stata_metadata"
    )
    if (identical(ordinary_dataset_class, "data.frame") ||
        identical(ordinary_dataset_class, c("tbl_df", "tbl", "data.frame"))) {
        known_dataset_attributes <- c(known_dataset_attributes, "class")
    }
    dataset_attributes <- setdiff(
        names(attributes(data)),
        known_dataset_attributes
    )
    if (length(dataset_attributes)) {
        details <- sprintf(
            "the data frame (%s)", paste(dataset_attributes, collapse = ", ")
        )
    }
    for (index in seq_along(data)) {
        dropped <- setdiff(
            names(attributes(data[[index]])),
            .arrow_known_column_attributes(kinds[[index]])
        )
        if (length(dropped)) {
            details <- c(details, sprintf(
                "`%s` (%s)", names(data)[[index]], paste(dropped, collapse = ", ")
            ))
        }
    }
    if (!length(details)) return(list())
    list(.dta_write_warning(
        sprintf(
            "Dropped attributes the Arrow profile does not represent: %s",
            paste(details, collapse = "; ")
        ),
        "dtatools_write_attribute_drop_warning"
    ))
}

.prepare_arrow_write <- function(data, label, adjust_tz) {
    if (!is.data.frame(data)) {
        .dta_write_abort("`data` must be a data frame or tibble",
                         "dtatools_write_argument_error")
    }
    if (ncol(data) == 0L) {
        .dta_write_abort("`data` must contain at least one column")
    }
    adjust_tz <- .write_scalar_logical(adjust_tz, "adjust_tz")
    data_names <- names(data)
    if (is.null(data_names) || anyDuplicated(data_names) ||
        anyNA(data_names) || any(data_names == "")) {
        .dta_write_abort(
            "Column names must be unique, non-missing, and nonempty"
        )
    }
    kinds <- vapply(data, .arrow_write_column_kind, character(1))
    supported <- !is.na(kinds)
    if (any(!supported)) {
        details <- sprintf(
            "`%s` (%s)", data_names[!supported],
            vapply(data[!supported], .write_column_description, character(1))
        )
        .dta_write_abort(sprintf(
            "Unsupported columns: %s", paste(details, collapse = ", ")
        ))
    }
    label <- .arrow_utf8(.write_text(label, "label"), "Dataset label")
    notes <- stata_notes(data)
    characteristics <- stata_characteristics(data)
    notes[] <- .arrow_utf8(unname(notes), "Dataset notes")
    value_label_names <- .resolve_write_value_label_names(data)
    value_label_cache <- new.env(hash = TRUE, parent = emptyenv())
    columns <- Map(
        .prepare_arrow_write_column, data, data_names, kinds,
        value_label_names$indices,
        MoreArgs = list(
            adjust_tz = adjust_tz,
            value_label_cache = value_label_cache
        )
    )
    value_label_tables <- .write_value_label_registry(
        value_label_names, value_label_cache
    )
    specification <- list(
        label, .stata_metadata_payload(notes, characteristics),
        unname(columns), value_label_tables
    )
    attr(specification, "write_warnings") <- c(
        value_label_names$warnings,
        .arrow_dropped_attribute_warnings(data, kinds)
    )
    specification
}
