#' Write a Stata 18 or 19 DTA file
#'
#' Streams a data frame to the standalone DTA encoding used by Stata 18 and
#' 19. Files with at most 32,767 variables use DTA release 118; wider files use
#' release 119.
#'
#' @section Conversions and metadata:
#' Bare logical, integer, and double columns use Stata `byte`, `long`, and
#' `double` storage. A valid `stata.storage` declaration takes precedence.
#' Compatible Stata display formats, dataset and variable labels, value labels,
#' tagged missing codes, dates, datetimes, long strings, and the data frame's
#' `notes` attribute are retained.
#'
#' Factors become value-labelled Stata `long` variables, in factor-level order.
#' Character missing values become empty strings, Stata's string-missing value.
#' Numeric values that the selected storage type cannot represent become Stata
#' system missing. Each applicable conversion category produces one aggregated
#' warning naming the affected columns and counts.
#'
#' Metadata outside documented Stata limits, unsupported column classes,
#' malformed or storage-incompatible display formats, invalid variable names,
#' and arbitrary Stata characteristics are not silently repaired or truncated.
#' Duplicate value-label keys already present in imported source metadata are
#' retained in stable order; the package's metadata setters remain stricter for
#' newly authored tables.
#'
#' @section Output safety:
#' Only local, uncompressed files are supported. The complete input is validated
#' before native serialization starts. Output streams to a sibling temporary
#' file and atomically replaces the destination only after the file is closed;
#' an existing destination therefore survives validation, I/O, and interruption
#' failures. Symbolic-link and directory destinations are rejected. Output is
#' always little-endian.
#'
#' @param data A data frame or tibble.
#' @param path Local output path. If the final filename has no extension,
#'   `.dta` is appended with a warning, matching Stata's `save` behavior.
#' @param version Target Stata application version, either 18 or 19.
#' @param label Dataset label. Defaults to the data frame's `label` attribute.
#' @param strl_threshold Character columns whose maximum UTF-8 byte length is
#'   greater than this value are stored as `strL`.
#' @param adjust_tz For `POSIXct` columns, whether to preserve displayed clock
#'   time (`TRUE`) or the underlying UTC instant (`FALSE`).
#' @return `data`, invisibly.
#' @examples
#' path <- tempfile(fileext = ".dta")
#' data <- data.frame(answer = stata_byte(c(1, tagged_missing("a"))))
#' write_dta(data, path)
#' read_dta(path)
#' unlink(path)
#' @export
write_dta <- function(data, path, version = 19L,
                      label = attr(data, "label", exact = TRUE),
                      strl_threshold = 2045L, adjust_tz = TRUE) {
    resolved_path <- .resolve_dta_write_path(path)
    for (write_warning in resolved_path$warnings) {
        .dta_write_warn(write_warning$message, write_warning$class)
    }
    specification <- .prepare_dta_write(
        data, version, label, strl_threshold, adjust_tz
    )
    destination <- resolved_path$path
    write_warnings <- attr(specification, "write_warnings", exact = TRUE)

    temporary <- tempfile(
        pattern = paste0(".", basename(destination), "-dtaparser-"),
        tmpdir = dirname(destination), fileext = ".tmp"
    )
    complete <- FALSE
    on.exit(if (!complete && file.exists(temporary)) unlink(temporary), add = TRUE)
    tryCatch(
        .Call(C_dtaparser_write, specification, temporary),
        error = function(condition) {
            if (inherits(condition, "interrupt")) stop(condition)
            .dta_write_abort(
                conditionMessage(condition),
                "dtaparser_write_native_error"
            )
        }
    )
    for (write_warning in write_warnings) {
        .dta_write_warn(write_warning$message, write_warning$class)
    }

    if (file.exists(destination)) {
        mode <- file.info(destination)$mode
        if (!is.na(mode)) Sys.chmod(temporary, mode = mode)
    }
    if (!file.rename(temporary, destination)) {
        .dta_write_abort(sprintf(
            "Could not atomically replace `%s` with the completed DTA file",
            destination
        ), "dtaparser_write_path_error")
    }
    complete <- TRUE
    invisible(data)
}

.dta_write_abort <- function(message, subclass = "dtaparser_write_validation_error") {
    rlang::abort(message, class = c(subclass, "dtaparser_write_error"))
}

.dta_write_warn <- function(message, subclass) {
    rlang::warn(
        message,
        class = c(subclass, "dtaparser_write_warning")
    )
}

.dta_write_warning <- function(message, subclass) {
    list(message = message, class = subclass)
}

.write_scalar_whole <- function(value, argument, allowed = NULL,
                                minimum = NULL, maximum = NULL) {
    valid <- is.numeric(value) && length(value) == 1L && !is.na(value) &&
        is.finite(value) && value == floor(value)
    if (valid && !is.null(allowed)) valid <- value %in% allowed
    if (valid && !is.null(minimum)) valid <- value >= minimum
    if (valid && !is.null(maximum)) valid <- value <= maximum
    if (!valid) {
        requirement <- if (!is.null(allowed)) {
            paste(allowed, collapse = " or ")
        } else {
            sprintf("a whole number from %s through %s", minimum, maximum)
        }
        .dta_write_abort(
            sprintf("`%s` must be %s", argument, requirement),
            "dtaparser_write_argument_error"
        )
    }
    as.integer(value)
}

.write_scalar_logical <- function(value, argument) {
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
        .dta_write_abort(
            sprintf("`%s` must be one non-missing logical value", argument),
            "dtaparser_write_argument_error"
        )
    }
    value
}

.write_text <- function(value, argument, maximum_characters = 80L,
                        maximum_bytes = maximum_characters * 4L) {
    if (is.null(value)) return("")
    if (!is.character(value) || length(value) != 1L || is.na(value)) {
        .dta_write_abort(
            sprintf("`%s` must be NULL or one non-missing character string", argument)
        )
    }
    characters <- nchar(value, type = "chars", allowNA = FALSE)
    if (characters > maximum_characters) {
        .dta_write_abort(sprintf(
            "`%s` has %s Unicode characters; Stata's limit is %s",
            argument, characters, maximum_characters
        ))
    }
    bytes <- nchar(value, type = "bytes", allowNA = FALSE)
    if (bytes > maximum_bytes) {
        .dta_write_abort(sprintf(
            "`%s` has %s UTF-8 bytes; Stata's limit is %s",
            argument, bytes, maximum_bytes
        ))
    }
    enc2utf8(value)
}

.valid_stata_names <- function(names) {
    nonempty <- !is.na(names) & nzchar(names)
    lengths <- nchar(names, type = "chars", allowNA = TRUE)
    syntax <- grepl(r"{^[\p{L}_][\p{L}\p{N}_]*$}", names, perl = TRUE)
    nonempty & !is.na(lengths) & lengths <= 32L & syntax
}

.supported_write_column <- function(column) {
    classes <- attr(column, "class", exact = TRUE)
    if (is.factor(column)) {
        return(is.null(dim(column)) && all(classes %in% c("ordered", "factor")))
    }
    if (inherits(column, "Date")) {
        return(is.null(dim(column)) && all(classes %in% c(
            "stata_temporal", "stata_date", "Date"
        )))
    }
    if (inherits(column, "POSIXct")) {
        return(is.null(dim(column)) && all(classes %in% c(
            "stata_temporal", "stata_datetime", "POSIXct", "POSIXt"
        )))
    }
    if (is.character(column)) {
        return(is.null(dim(column)) && is.null(classes))
    }
    if (!(typeof(column) %in% c("logical", "integer", "double")) ||
        !is.null(dim(column))) {
        return(FALSE)
    }
    if (is.null(classes)) return(TRUE)
    all(classes %in% c(
        "haven_labelled", "vctrs_vctr", "stata_numeric",
        paste0("stata_", .stata_storage), "double", "integer", "logical"
    ))
}

.write_column_description <- function(column) {
    classes <- attr(column, "class", exact = TRUE)
    if (is.null(classes)) typeof(column) else paste(classes, collapse = "/")
}

.default_stata_format <- function(storage, width = NULL) {
    switch(storage,
        byte = "%8.0g",
        int = "%8.0g",
        long = "%12.0g",
        float = "%9.0g",
        double = "%10.0g",
        fixed = sprintf("%%%ss", max(9L, width)),
        strL = "%9s"
    )
}

.prepare_write_format <- function(column, name, default, kind) {
    format <- attr(column, "format.stata", exact = TRUE)
    if (is.null(format)) format <- default
    format <- .write_text(
        format, sprintf("format.stata for `%s`", name),
        maximum_characters = 56L, maximum_bytes = 56L
    )
    basic <- grepl("^%[^[:space:]]+[[:alpha:]]$", format, perl = TRUE)
    becomes_r_temporal <- startsWith(format, "%td") ||
        (startsWith(format, "%d") && !startsWith(format, "%dollar")) ||
        startsWith(format, "%tc") || startsWith(format, "%tC")
    compatible <- switch(kind,
        string = grepl("^%-?[0-9]{1,4}s$", format, perl = TRUE),
        numeric = basic && !grepl("s$", format) && !becomes_r_temporal,
        temporal = basic
    )
    if (!compatible) {
        .dta_write_abort(sprintf(
            "Column `%s` has malformed or incompatible display format `%s`",
            name, format
        ))
    }
    format
}

.numeric_write_storage <- function(column) {
    explicit <- attr(column, "stata.storage", exact = TRUE)
    if (!is.null(explicit)) {
        if (!is.character(explicit) || length(explicit) != 1L ||
            !(explicit %in% .stata_storage)) {
            return(NULL)
        }
        return(explicit)
    }
    switch(typeof(column),
        logical = "byte",
        integer = "long",
        double = "double",
        NULL
    )
}

.prepare_write_value_labels <- function(column, name) {
    labels <- attr(column, "labels", exact = TRUE)
    if (is.null(labels)) return(list(double(), character(), FALSE))
    argument <- sprintf("labels for `%s`", name)
    if (!is.numeric(labels) ||
        !(typeof(labels) %in% c("integer", "double")) ||
        !is.null(dim(labels))) {
        .dta_write_abort(sprintf(
            "`%s` must be a named numeric vector", argument
        ))
    }
    label_text <- names(labels)
    if (is.null(label_text) || length(label_text) != length(labels) ||
        anyNA(label_text)) {
        .dta_write_abort(sprintf(
            "`%s` must have non-missing text for every code", argument
        ))
    }
    missing_codes <- .tab_missing_codes(labels)
    tagged <- !is.na(missing_codes) &
        missing_codes >= utf8ToInt("a") & missing_codes <= utf8ToInt("z")
    observed <- is.na(missing_codes) & is.finite(labels) &
        labels == floor(labels) &
        labels >= -2147483647 & labels <= 2147483620
    if (any(!(tagged | observed))) {
        .dta_write_abort(sprintf(
            paste0(
                "`%s` codes must be nonmissing integers in Stata's long ",
                "range or extended missings `.a` through `.z`"
            ),
            argument
        ))
    }
    if (length(labels) > 65536L) {
        .dta_write_abort(sprintf(
            "Value-label table for `%s` has more than 65,536 entries", name
        ))
    }
    byte_lengths <- nchar(label_text, type = "bytes", allowNA = FALSE)
    if (any(byte_lengths > 32000L)) {
        .dta_write_abort(sprintf(
            paste0(
                "Value-label text for `%s` has %s UTF-8 bytes; ",
                "Stata's limit is 32,000"
            ),
            name, format(max(byte_lengths), big.mark = ",", scientific = FALSE)
        ))
    }
    list(unname(labels), enc2utf8(label_text), TRUE)
}

.prepare_numeric_write_values <- function(column, storage, shift = 0, scale = 1) {
    type_code <- match(storage, .stata_storage) - 1L
    issue_count <- .Call(
        C_dtaparser_write_numeric_issues, column, as.integer(type_code),
        as.double(shift), as.double(scale)
    )
    if (issue_count == 0) {
        return(list(values = column, issue_count = issue_count))
    }

    values <- as.double(column)
    missing_codes <- .tab_missing_codes(values)
    tagged <- !is.na(missing_codes) &
        missing_codes >= utf8ToInt("a") & missing_codes <= utf8ToInt("z")
    system <- !is.na(missing_codes) & missing_codes == 0L
    observed <- is.na(missing_codes)
    checked <- values
    checked[observed] <- (checked[observed] + shift) * scale
    invalid <- (!observed & !(tagged | system)) |
        .invalid_stata_observed(checked, observed, storage)
    values[invalid] <- NA_real_
    list(values = values, issue_count = issue_count)
}

.temporal_write_values <- function(column, kind, adjust_tz) {
    values <- column
    missing_codes <- .tab_missing_codes(values)
    observed <- is.na(missing_codes)
    if (identical(kind, "date")) {
        return(list(values = values, shift = 3653, scale = 1))
    }

    if (adjust_tz && any(observed)) {
        timezone <- attr(column, "tzone", exact = TRUE)
        if (is.null(timezone) || !length(timezone) || is.na(timezone[[1L]])) {
            timezone <- ""
        } else {
            timezone <- timezone[[1L]]
        }
        if (!(timezone %in% c("UTC", "GMT"))) {
            values <- as.double(column)
            local <- as.POSIXlt(column[observed], tz = timezone)
            offset <- local$gmtoff
            if (!is.null(offset) && length(offset) == sum(observed) &&
                !anyNA(offset)) {
                values[observed] <- values[observed] + offset
            } else {
                values[observed] <- as.double(ISOdatetime(
                    local$year + 1900L, local$mon + 1L, local$mday,
                    local$hour, local$min, local$sec, tz = "UTC"
                ))
            }
        }
    }
    list(values = values, shift = 315619200, scale = 1000)
}

.prepare_dta_write_column <- function(column, name, strl_threshold,
                                      adjust_tz) {
    if (is.factor(column)) {
        levels <- levels(column)
        if (anyNA(levels) || any(!nzchar(levels))) {
            .dta_write_abort(sprintf(
                "Factor column `%s` has an empty or missing level", name
            ))
        }
        if (length(levels) > 65536L ||
            any(nchar(levels, type = "bytes", allowNA = FALSE) > 32000L)) {
            .dta_write_abort(sprintf(
                "Factor column `%s` exceeds Stata's value-label limits", name
            ))
        }
        format <- .prepare_write_format(
            column, name, .default_stata_format("long"), "numeric"
        )
        variable_label <- .write_text(
            attr(column, "label", exact = TRUE),
            sprintf("variable label for `%s`", name)
        )
        prepared_values <- .prepare_numeric_write_values(
            as.integer(column), "long"
        )
        result <- list(
            enc2utf8(name), 2L, enc2utf8(format), variable_label,
            as.double(seq_along(levels)), enc2utf8(levels),
            prepared_values$values,
            TRUE, 0, 1
        )
        attr(result, "numeric_replacements") <- prepared_values$issue_count
        return(result)
    }
    if (is.character(column) && is.null(dim(column))) {
        plan <- .Call(C_dtaparser_write_string_plan, column)
        maximum <- plan[[1L]]
        values <- if (plan[[3L]] != 0) enc2utf8(column) else column
        fixed <- maximum <= strl_threshold && maximum <= 2045L
        width <- max(1L, maximum)
        type_code <- if (fixed) width + 4L else 2050L
        storage <- if (fixed) "fixed" else "strL"
        format <- .prepare_write_format(
            column, name, .default_stata_format(storage, width), "string"
        )
        variable_label <- .write_text(
            attr(column, "label", exact = TRUE),
            sprintf("variable label for `%s`", name)
        )
        if (!is.null(attr(column, "labels", exact = TRUE))) {
            .dta_write_abort(sprintf(
                "Character column `%s` cannot have numeric value labels", name
            ))
        }
        result <- list(
            enc2utf8(name), as.integer(type_code), enc2utf8(format),
            variable_label, double(), character(), values, FALSE, 0, 1
        )
        attr(result, "character_missing") <- plan[[2L]]
        return(result)
    }
    temporal <- if (inherits(column, "Date")) {
        "date"
    } else if (inherits(column, "POSIXct")) {
        "datetime"
    } else {
        NULL
    }
    if (!is.null(temporal)) {
        storage <- .numeric_write_storage(column)
        if (is.null(storage)) storage <- "double"
        format <- attr(column, "format.stata", exact = TRUE)
        if (is.null(format)) format <- if (identical(temporal, "date")) "%td" else "%tc"
        compatible <- if (identical(temporal, "date")) {
            startsWith(format, "%td") ||
                (startsWith(format, "%d") && !startsWith(format, "%dollar"))
        } else {
            startsWith(format, "%tc") || startsWith(format, "%tC")
        }
        if (!compatible) {
            .dta_write_abort(sprintf(
                "Column `%s` has incompatible temporal display format `%s`",
                name, format
            ))
        }
        format <- .prepare_write_format(column, name, format, "temporal")
        variable_label <- .write_text(
            attr(column, "label", exact = TRUE),
            sprintf("variable label for `%s`", name)
        )
        value_labels <- .prepare_write_value_labels(column, name)
        temporal_values <- .temporal_write_values(column, temporal, adjust_tz)
        prepared_values <- .prepare_numeric_write_values(
            temporal_values$values, storage,
            temporal_values$shift, temporal_values$scale
        )
        result <- list(
            enc2utf8(name), as.integer(match(storage, .stata_storage) - 1L),
            enc2utf8(format), variable_label, value_labels[[1L]],
            value_labels[[2L]], prepared_values$values, value_labels[[3L]],
            temporal_values$shift, temporal_values$scale
        )
        attr(result, "numeric_replacements") <- prepared_values$issue_count
        return(result)
    }
    storage <- .numeric_write_storage(column)
    if (is.null(storage)) {
        .dta_write_abort(sprintf(
            "Column `%s` has unsupported type or class: %s",
            name, paste(class(column), collapse = "/")
        ))
    }
    type_code <- match(storage, .stata_storage) - 1L
    format <- .prepare_write_format(
        column, name, .default_stata_format(storage), "numeric"
    )
    variable_label <- .write_text(
        attr(column, "label", exact = TRUE),
        sprintf("variable label for `%s`", name)
    )
    value_labels <- .prepare_write_value_labels(column, name)
    prepared_values <- .prepare_numeric_write_values(column, storage)
    result <- list(
        enc2utf8(name), as.integer(type_code), enc2utf8(format),
        variable_label, value_labels[[1L]], value_labels[[2L]],
        prepared_values$values, value_labels[[3L]], 0, 1
    )
    attr(result, "numeric_replacements") <- prepared_values$issue_count
    result
}

.write_timestamp <- function(time = Sys.time()) {
    local <- as.POSIXlt(time)
    sprintf(
        "%02d %s %04d %02d:%02d",
        local$mday, month.abb[[local$mon + 1L]], local$year + 1900L,
        local$hour, local$min
    )
}

.prepare_dta_write <- function(data, version, label, strl_threshold,
                               adjust_tz) {
    write_warnings <- list()
    if (!is.data.frame(data)) {
        .dta_write_abort("`data` must be a data frame or tibble",
                         "dtaparser_write_argument_error")
    }
    if (ncol(data) == 0L) {
        .dta_write_abort("`data` must contain at least one column")
    }
    if (ncol(data) > 120000L) {
        .dta_write_abort("`data` has more than Stata's 120,000-variable limit")
    }
    version <- .write_scalar_whole(version, "version", allowed = c(18L, 19L))
    strl_threshold <- .write_scalar_whole(
        strl_threshold, "strl_threshold", minimum = 1L, maximum = 2045L
    )
    adjust_tz <- .write_scalar_logical(adjust_tz, "adjust_tz")
    data_names <- names(data)
    if (is.null(data_names) || anyDuplicated(data_names) ||
        !all(.valid_stata_names(data_names))) {
        .dta_write_abort(paste0(
            "Column names must be unique, nonempty valid Stata names with ",
            "at most 32 Unicode characters"
        ))
    }
    supported <- vapply(data, .supported_write_column, logical(1))
    if (any(!supported)) {
        details <- sprintf(
            "`%s` (%s)", data_names[!supported],
            vapply(data[!supported], .write_column_description, character(1))
        )
        .dta_write_abort(sprintf(
            "Unsupported columns: %s", paste(details, collapse = ", ")
        ))
    }
    label <- .write_text(label, "label")
    notes <- attr(data, "notes", exact = TRUE)
    if (is.null(notes)) notes <- character()
    if (!is.character(notes) || anyNA(notes)) {
        .dta_write_abort("The data frame's `notes` attribute must be NULL or a character vector")
    }
    notes <- enc2utf8(notes)
    if (length(notes) > 9999L || any(nchar(notes, type = "bytes") > 67784L)) {
        .dta_write_abort("Dataset notes exceed Stata's count or UTF-8 byte limits")
    }
    columns <- Map(
        .prepare_dta_write_column, unname(data), data_names,
        MoreArgs = list(
            strl_threshold = strl_threshold,
            adjust_tz = adjust_tz
        )
    )
    factor_columns <- data_names[vapply(data, is.factor, logical(1))]
    if (length(factor_columns)) {
        write_warnings <- c(write_warnings, list(.dta_write_warning(
            sprintf(
                paste0(
                    "Converted factor columns to labelled Stata long integers: %s. ",
                    "Factor class and orderedness will not be restored on read."
                ),
                paste(sprintf("`%s`", factor_columns), collapse = ", ")
            ),
            "dtaparser_write_factor_warning"
        )))
    }
    character_missing <- vapply(columns, function(column) {
        count <- attr(column, "character_missing", exact = TRUE)
        if (is.null(count)) 0 else count
    }, numeric(1))
    if (any(character_missing > 0L)) {
        affected <- data_names[character_missing > 0L]
        details <- sprintf(
            "`%s` (%s)", affected,
            format(character_missing[affected], big.mark = ",", scientific = FALSE)
        )
        write_warnings <- c(write_warnings, list(.dta_write_warning(
            sprintf(
                "Converted character missing values to empty strings in %s",
                paste(details, collapse = ", ")
            ),
            "dtaparser_write_character_missing_warning"
        )))
    }
    numeric_replacements <- vapply(columns, function(column) {
        count <- attr(column, "numeric_replacements", exact = TRUE)
        if (is.null(count)) 0 else count
    }, numeric(1))
    if (any(numeric_replacements > 0)) {
        affected <- data_names[numeric_replacements > 0]
        details <- sprintf(
            "`%s` (%s)", affected,
            format(
                numeric_replacements[numeric_replacements > 0],
                big.mark = ",", scientific = FALSE
            )
        )
        write_warnings <- c(write_warnings, list(.dta_write_warning(
            sprintf(
                "Converted unrepresentable numeric values to Stata system missing in %s",
                paste(details, collapse = ", ")
            ),
            "dtaparser_write_numeric_replacement_warning"
        )))
    }
    specification <- list(label, notes, columns, version, .write_timestamp())
    attr(specification, "write_warnings") <- write_warnings
    specification
}

.resolve_dta_write_path <- function(path) {
    if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
        .dta_write_abort("`path` must be one nonempty local filename",
                         "dtaparser_write_path_error")
    }
    path <- path.expand(path)
    write_warnings <- list()
    extension <- tolower(tools::file_ext(basename(path)))
    if (extension %in% c("gz", "bz2", "xz", "zip")) {
        .dta_write_abort(
            "Compressed output paths are not supported; write an ordinary `.dta` file",
            "dtaparser_write_path_error"
        )
    }
    if (!nzchar(extension)) {
        path <- paste0(path, ".dta")
        write_warnings <- list(.dta_write_warning(
            sprintf("`path` has no extension; writing `%s`", path),
            "dtaparser_write_extension_warning"
        ))
    }
    parent <- dirname(path)
    if (!dir.exists(parent)) {
        .dta_write_abort(sprintf("Output directory does not exist: `%s`", parent),
                         "dtaparser_write_path_error")
    }
    path <- file.path(
        normalizePath(parent, winslash = "/", mustWork = TRUE),
        basename(path)
    )
    link <- Sys.readlink(path)
    if (!is.na(link) && nzchar(link)) {
        .dta_write_abort("Refusing to replace a symbolic-link destination",
                         "dtaparser_write_path_error")
    }
    if (dir.exists(path)) {
        .dta_write_abort("Refusing to replace a directory destination",
                         "dtaparser_write_path_error")
    }
    list(path = path, warnings = write_warnings)
}
