#' Write a dtatools Arrow profile file
#'
#' Writes a data frame to the Arrow IPC file format carrying the dtatools
#' Arrow profile, experimental profile version `"0"`, which carries no
#' cross-version stability promise yet. The file is a valid Arrow IPC
#' file that any Arrow reader can open; profile metadata additionally records
#' the Stata semantics needed for a semantic Arrow round-trip through
#' [read_arrow()]: storage declarations, raw Stata missing storage (sentinel
#' integers and tagged NaN payloads), display formats, labels, notes, and
#' value-label tables, plus per-buffer checksums.
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
#'
#' Unlike [save_dta()], factor class and orderedness, `POSIXct` timezones,
#' and `difftime` units are preserved on read.
#'
#' @section Output safety:
#' Only local files are supported. The complete input is validated before
#' native serialization starts. Output streams to a sibling temporary file and
#' atomically replaces the destination only after the file is closed.
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
#'   unaffected: Arrow timestamps store the instant and the timezone.
#' @param threads Number of threads used to encode columns into Arrow
#'   buffers. `0` (the default) selects a thread count automatically; `1`
#'   forces serial encoding. Defaults to the `dtatools.threads` option.
#' @param checksums Whether to embed per-buffer xxHash64 checksums in the
#'   file footer (the default). Files written with `checksums = FALSE` are
#'   slightly smaller and faster to write, but [read_arrow()] can only read
#'   them with `verify = FALSE`.
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
    threads <- .normalize_threads(threads)
    checksums <- .normalize_arrow_flag(checksums, "checksums")
    resolved_path <- .resolve_dta_write_path(path, "arrow")
    for (write_warning in resolved_path$warnings) {
        .dta_write_warn(write_warning$message, write_warning$class)
    }
    compression <- .arrow_write_compression(compression)
    specification <- .prepare_arrow_write(data, label, adjust_tz)
    destination <- resolved_path$path
    write_warnings <- attr(specification, "write_warnings", exact = TRUE)

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
        names(data),
        "Converted unrepresentable numeric values to Stata system missing",
        "dtatools_write_numeric_replacement_warning"
    ))
    for (write_warning in write_warnings) {
        .dta_write_warn(write_warning$message, write_warning$class)
    }
    .commit_dta_write(temporary, destination)
    invisible(data)
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
        if (is.null(classes) || all(classes %in% c(
            "haven_labelled", "vctrs_vctr", "double"
        ))) return("double")
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

.prepare_arrow_write_column <- function(column, name, kind, adjust_tz) {
    variable_label <- .arrow_utf8(
        .write_text(
            attr(column, "label", exact = TRUE),
            sprintf("variable label for `%s`", name)
        ),
        sprintf("Variable label for `%s`", name)
    )
    levels <- character()
    ordered <- FALSE
    tz <- ""
    units <- ""
    storage_code <- -1L
    values <- column

    value_labels <- list(double(), character(), FALSE)
    if (kind %in% c("double", "date", "datetime", "difftime", "stata")) {
        value_labels <- .prepare_write_value_labels(
            column, name, allow_legacy_codes = TRUE
        )
        # The shared validator accepts integer and double code vectors. The
        # Arrow native descriptor has one f64 representation for both.
        value_labels[[1L]] <- as.double(value_labels[[1L]])
        value_labels[[2L]] <- .arrow_utf8(
            value_labels[[2L]], sprintf("Value-label text for `%s`", name)
        )
    } else if (!is.null(attr(column, "labels", exact = TRUE))) {
        .dta_write_abort(sprintf(
            "Column `%s` cannot carry numeric value labels", name
        ))
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
            tz <- .write_datetime_timezone(column)
            values <- as.double(column)
        } else if (identical(kind, "difftime")) {
            units <- .arrow_write_difftime_units(column, name)
            values <- as.double(column)
        }
    }

    format <- .arrow_utf8(format, sprintf("Display format for `%s`", name))
    tz <- .arrow_utf8(tz, sprintf("Timezone for `%s`", name))
    units <- .arrow_utf8(units, sprintf("Difftime units for `%s`", name))

    list(
        .arrow_utf8(name, "Column names"), .arrow_write_kinds[[kind]],
        values, levels, ordered,
        variable_label, format, storage_code, tz, units,
        value_labels[[1L]], value_labels[[2L]], value_labels[[3L]],
        inherits(column, "haven_labelled")
    )
}

.arrow_known_column_attributes <- function(kind) {
    common <- c("label", "format.stata")
    switch(kind,
        factor = c(common, "levels", "class"),
        date = c(common, "labels", "class"),
        datetime = c(common, "labels", "class", "tzone"),
        difftime = c(common, "labels", "class", "units"),
        stata = c(common, "labels", "stata.storage", "class"),
        double = c(common, "labels", "class"),
        common
    )
}

.arrow_dropped_attribute_warnings <- function(data, kinds) {
    details <- character()
    known_dataset_attributes <- c("names", "label", "notes")
    if (.row_names_info(data, type = 1L) <= 0L) {
        known_dataset_attributes <- c(known_dataset_attributes, "row.names")
    }
    dataset_class <- attr(data, "class", exact = TRUE)
    if (identical(dataset_class, "data.frame") ||
        identical(dataset_class, c("tbl_df", "tbl", "data.frame"))) {
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
    notes <- attr(data, "notes", exact = TRUE)
    if (is.null(notes)) notes <- character()
    if (!is.character(notes) || anyNA(notes)) {
        .dta_write_abort("The data frame's `notes` attribute must be NULL or a character vector")
    }
    notes <- .arrow_utf8(notes, "Dataset notes")
    if (length(notes) > 9999L || any(nchar(notes, type = "bytes") > 67784L)) {
        .dta_write_abort("Dataset notes exceed Stata's count or UTF-8 byte limits")
    }
    columns <- Map(
        .prepare_arrow_write_column, data, data_names, kinds,
        MoreArgs = list(adjust_tz = adjust_tz)
    )
    specification <- list(label, notes, unname(columns))
    attr(specification, "write_warnings") <-
        .arrow_dropped_attribute_warnings(data, kinds)
    specification
}
