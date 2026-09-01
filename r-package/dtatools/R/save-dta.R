#' Write a Stata 18 or 19 DTA file
#'
#' Streams a data frame to the standalone DTA encoding used by Stata 18 and
#' 19. Stata 18 targets are limited to 32,767 variables and DTA release 118.
#' Stata 19 targets use release 118 through that limit and release 119 above it.
#'
#' @section Conversions and metadata:
#' Bare logical, integer, and double columns use Stata `byte`, `long`, and
#' `double` storage. A valid `stata.storage` declaration takes precedence.
#' Compatible Stata display formats, dataset and variable labels, value labels,
#' tagged missing codes, dates, datetimes, long strings, numbered notes, and
#' arbitrary Stata characteristics at dataset and variable scope are retained.
#'
#' Factors become value-labelled Stata `long` variables, in factor-level order.
#' Character missing values become empty strings, Stata's string-missing value.
#' Numeric values that the selected storage type cannot represent become Stata
#' system missing. Each applicable conversion category produces one aggregated
#' warning naming the affected columns and counts.
#'
#' Metadata outside documented Stata limits, unsupported column classes,
#' malformed or storage-incompatible display formats, invalid variable or
#' characteristic names, and over-limit notes or characteristics are not
#' silently repaired or truncated.
#' Duplicate value-label keys already present in imported source metadata are
#' retained in stable order; the package's metadata setters remain stricter for
#' newly authored tables.
#' An imported `value.label.name` attribute preserves a nondefault or shared
#' value-label table name. Columns that claim one name with different mappings
#' produce one aggregated warning and fall back to separate variable-name
#' tables. A table-name attribute without a usable `labels` mapping is invalid.
#'
#' @section Output safety:
#' Only local, uncompressed files are supported. The complete input is validated
#' before native serialization starts. Output streams to a sibling temporary
#' file and atomically replaces the destination only after the file is closed;
#' an existing destination therefore survives validation, interruption, and I/O
#' failures reported before replacement. Delayed close or writeback failures and
#' crash durability are not covered. Symbolic-link, directory, and other
#' non-regular destinations are rejected. Output is always little-endian.
#'
#' @param data A data frame or tibble.
#' @param path Local output path. If the final filename has no extension,
#'   `.dta` is appended with a warning, matching Stata's `save` behavior.
#' @param version Target Stata application version, either 18 or 19.
#' @param label Dataset label. Defaults to the data frame's `label` attribute.
#' @param strl_threshold Character columns whose maximum UTF-8 byte length is
#'   greater than this value are stored as `strL`. An explicit
#'   `stata.string.storage` fixed-width declaration takes precedence.
#' @param adjust_tz For `POSIXct` columns, whether to preserve displayed clock
#'   time (`TRUE`) or the underlying UTC instant (`FALSE`).
#' @return `data`, invisibly.
#' @examples
#' path <- tempfile(fileext = ".dta")
#' data <- data.frame(answer = stata_byte(c(1, tagged_missing("a"))))
#' save_dta(data, path)
#' read_dta(path)
#' unlink(path)
#' @export
save_dta <- function(data, path, version = 19L,
                      label = attr(data, "label", exact = TRUE),
                      strl_threshold = 2045L, adjust_tz = TRUE) {
    original_data <- data
    write_data <- .reference_snapshot(data)
    resolved_path <- .resolve_dta_write_path(path)
    for (write_warning in resolved_path$warnings) {
        .dta_write_warn(write_warning$message, write_warning$class)
    }
    version <- .write_scalar_whole(
        version, "version", allowed = c(18L, 19L)
    )
    specification <- .prepare_dta_write(
        write_data, label, strl_threshold, adjust_tz, version
    )
    destination <- resolved_path$path
    write_warnings <- attr(specification, "write_warnings", exact = TRUE)
    write_warnings <- .emit_dta_write_preflight_warnings(write_warnings)

    temporary <- tempfile(
        pattern = paste0(".", basename(destination), "-dtatools-"),
        tmpdir = dirname(destination), fileext = ".tmp"
    )
    on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
    numeric_replacements <- tryCatch(
        .Call(C_dtatools_write, specification, temporary),
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

.commit_dta_write <- function(temporary, destination) {
    destination_kind <- .validate_dta_write_destination(destination)
    mode <- if (destination_kind == 1L) {
        file.info(destination)$mode
    } else if (.Platform$OS.type == "unix") {
        as.octmode(bitwAnd(
            strtoi("666", base = 8L),
            bitwNot(as.integer(Sys.umask()))
        ))
    }
    if (!is.null(mode) && !is.na(mode) &&
        !isTRUE(Sys.chmod(temporary, mode = mode))) {
        .dta_write_abort(sprintf(
            "Could not set permissions on the completed file `%s`",
            destination
        ), "dtatools_write_path_error")
    }
    if (!file.rename(temporary, destination)) {
        .dta_write_abort(sprintf(
            "Could not atomically replace `%s` with the completed file",
            destination
        ), "dtatools_write_path_error")
    }
    invisible(NULL)
}

.dta_write_abort <- function(message, subclass = "dtatools_write_validation_error") {
    rlang::abort(message, class = c(subclass, "dtatools_write_error"))
}

.dta_write_warn <- function(message, subclass) {
    rlang::warn(
        message,
        class = c(subclass, "dtatools_write_warning")
    )
}

.dta_write_warning <- function(message, subclass) {
    list(message = message, class = subclass)
}

.emit_dta_write_preflight_warnings <- function(write_warnings) {
    preflight <- vapply(write_warnings, function(write_warning) {
        identical(
            write_warning$class,
            "dtatools_write_value_label_name_conflict_warning"
        )
    }, logical(1))
    for (write_warning in write_warnings[preflight]) {
        .dta_write_warn(write_warning$message, write_warning$class)
    }
    write_warnings[!preflight]
}

.dta_write_count_warnings <- function(counts, column_names, prefix, subclass) {
    affected <- counts > 0
    if (!any(affected)) return(list())
    details <- sprintf(
        "`%s` (%s)", column_names[affected],
        format(counts[affected], big.mark = ",", scientific = FALSE)
    )
    list(.dta_write_warning(
        sprintf("%s in %s", prefix, paste(details, collapse = ", ")),
        subclass
    ))
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
            "dtatools_write_argument_error"
        )
    }
    as.integer(value)
}

.write_scalar_logical <- function(value, argument) {
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
        .dta_write_abort(
            sprintf("`%s` must be one non-missing logical value", argument),
            "dtatools_write_argument_error"
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

.stata_reserved_names <- c(
    "alias", "_all", "_b", "_coef", "_cons", "_n", "_N", "_pi",
    "_pred", "_r_b", "_rc", "_r_ci", "_r_cri", "_r_crlb", "_r_crub",
    "_r_df", "_r_lb", "_r_p", "_r_se", "_r_ub", "_r_z", "_r_z_abs",
    "_se", "_skip", "_weight", "byte", "double", "float", "int",
    "long", "in", "if", "strL", "using", "with"
)

.valid_stata_name_syntax <- function(names, maximum_characters) {
    lengths <- nchar(names, type = "chars", allowNA = TRUE)
    !is.na(names) & nzchar(names) & !is.na(lengths) &
        lengths <= maximum_characters &
        grepl(r"{^[\p{L}_][\p{L}\p{N}_]*$}", names, perl = TRUE)
}

.valid_stata_names <- function(names) {
    reserved <- names %in% .stata_reserved_names |
        grepl("^str[1-9][0-9]*$", names, perl = TRUE)
    .valid_stata_name_syntax(names, 32L) & !reserved
}

.write_column_kind <- function(column) {
    if (!is.null(dim(column))) return(NA_character_)
    classes <- attr(column, "class", exact = TRUE)
    if (is.factor(column)) {
        if (all(classes %in% c(
            .stata_metadata_vector_class, "ordered", "factor"
        ))) return("factor")
        return(NA_character_)
    }
    if (inherits(column, "Date")) {
        if (all(classes %in% c(
            .stata_metadata_vector_class,
            "stata_temporal", "stata_date", "Date"
        ))) return("date")
        return(NA_character_)
    }
    if (inherits(column, "POSIXct")) {
        if (all(classes %in% c(
            .stata_metadata_vector_class,
            "stata_temporal", "stata_datetime", "POSIXct", "POSIXt"
        ))) return("datetime")
        return(NA_character_)
    }
    if (is.character(column)) {
        if (is.null(classes) || all(
            classes %in% c(
                .stata_metadata_vector_class,
                "stata_string", "vctrs_vctr", "character"
            )
        )) return("character")
        return(NA_character_)
    }
    if (!(typeof(column) %in% c("logical", "integer", "double"))) {
        return(NA_character_)
    }
    if (is.null(classes) || all(classes %in% c(
        .stata_metadata_vector_class,
        "haven_labelled", "vctrs_vctr", "stata_numeric",
        paste0("stata_", .stata_storage), "double", "integer", "logical"
    ))) return("numeric")
    NA_character_
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

.valid_stata_decimal_format <- function(format) {
    matched <- regmatches(
        format,
        regexec(
            "^%-?([0-9]+)[.,]([0-9]+)([efg])(c?)$",
            format,
            perl = TRUE
        )
    )[[1L]]
    if (length(matched) != 5L) {
        return(format %in% c("%21x", "%8H", "%8L", "%16H", "%16L"))
    }
    width <- suppressWarnings(as.numeric(matched[[2L]]))
    decimals <- suppressWarnings(as.numeric(matched[[3L]]))
    is.finite(width) && width >= 1 && width <= 2045 &&
        is.finite(decimals) && decimals >= 0 && decimals < width &&
        !(identical(matched[[4L]], "e") && nzchar(matched[[5L]]))
}

.valid_stata_string_format <- function(format) {
    matched <- regmatches(
        format,
        regexec("^%-?([0-9]+)s$", format, perl = TRUE)
    )[[1L]]
    if (length(matched) != 2L) return(FALSE)
    width <- suppressWarnings(as.numeric(matched[[2L]]))
    is.finite(width) && width >= 1 && width <= 2045
}

.valid_stata_datetime_details <- function(details, tokens) {
    if (!nzchar(details)) return(TRUE)
    tokens <- tokens[order(nchar(tokens), decreasing = TRUE)]
    position <- 1L
    final <- nchar(details, type = "chars")
    separators <- c(".", ",", ":", "-", "_", " ", "/", "\\", "+")
    while (position <= final) {
        remaining <- substr(details, position, final)
        first <- substr(remaining, 1L, 1L)
        if (identical(first, "!")) {
            if (position == final) return(FALSE)
            position <- position + 2L
            next
        }
        matched <- tokens[startsWith(remaining, tokens)]
        if (length(matched)) {
            position <- position + nchar(matched[[1L]], type = "chars")
            next
        }
        if (!(first %in% separators)) return(FALSE)
        position <- position + 1L
    }
    TRUE
}

.valid_stata_calendar_format <- function(format, allowed) {
    normalized <- sub("^%-", "%", format)
    if (startsWith(normalized, "%d")) {
        if (!("d" %in% allowed)) return(FALSE)
        type <- "d"
        details <- substring(normalized, 3L)
    } else if (startsWith(normalized, "%t")) {
        if (nchar(normalized, type = "chars") < 3L) return(FALSE)
        type <- substr(normalized, 3L, 3L)
        if (!(type %in% allowed)) return(FALSE)
        details <- substring(normalized, 4L)
    } else {
        return(FALSE)
    }

    year <- c("CC", "cc", "YY", "yy", "C", "c", "Y", "y")
    month <- c(
        "Month", "month", "Mon", "mon", "NN", "nn", "M", "m", "N", "n"
    )
    day <- c(
        "DAYNAME", "Dayname", "JJJ", "jjj", "Day", "day", "DD", "dd",
        "Da", "da", "J", "j", "D", "d"
    )
    clock <- c(
        "A.M.", "a.m.", ".sss", ".ss", "HH", "Hh", "hH", "hh", "MM",
        "mm", "SS", "ss", "AM", "am", ".s"
    )
    tokens <- c(
        year, month, day, clock, "WW", "ww", "W", "w", "q", "h"
    )
    if (identical(type, "g")) return(!nzchar(details))
    if (identical(type, "b")) {
        calendar <- sub(":.*$", "", details)
        if (!.valid_stata_name_syntax(calendar, 10L)) return(FALSE)
        if (!grepl(":", details, fixed = TRUE)) return(TRUE)
        details <- sub("^[^:]*:", "", details)
        if (!nzchar(details)) return(TRUE)
    }
    .valid_stata_datetime_details(details, tokens)
}

.prepare_write_format <- function(column, name, default, kind) {
    format <- attr(column, "format.stata", exact = TRUE)
    if (is.null(format)) format <- default
    format <- .write_text(
        format, sprintf("format.stata for `%s`", name),
        maximum_characters = 56L, maximum_bytes = 56L
    )
    compatible <- switch(kind,
        string = .valid_stata_string_format(format),
        numeric = .valid_stata_decimal_format(format) ||
            .valid_stata_calendar_format(format, c("w", "m", "q", "h", "y", "g", "b")),
        date = .valid_stata_calendar_format(format, "d"),
        datetime = .valid_stata_calendar_format(format, c("c", "C"))
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

.validate_write_value_label_shape <- function(column, name) {
    labels <- attr(column, "labels", exact = TRUE)
    if (is.null(labels)) return(NULL)
    argument <- sprintf("labels for `%s`", name)
    if (!is.numeric(labels) ||
        !(typeof(labels) %in% c("integer", "double")) ||
        !is.null(dim(labels))) {
        .dta_write_abort(sprintf(
            "`%s` must be a named numeric vector", argument
        ))
    }
    label_text <- names(labels)
    if (is.null(label_text) || length(label_text) != length(labels)) {
        .dta_write_abort(sprintf(
            "`%s` must have non-missing text for every code", argument
        ))
    }
    labels
}

.validate_write_value_label_structure <- function(column, name) {
    labels <- .validate_write_value_label_shape(column, name)
    if (is.null(labels)) return(NULL)
    if (anyNA(names(labels))) {
        argument <- sprintf("labels for `%s`", name)
        .dta_write_abort(sprintf(
            "`%s` must have non-missing text for every code", argument
        ))
    }
    labels
}

.prepare_write_value_labels <- function(column, name,
                                        allow_legacy_codes = FALSE,
                                        validate_structure = TRUE) {
    labels <- if (validate_structure) {
        .validate_write_value_label_structure(column, name)
    } else {
        attr(column, "labels", exact = TRUE)
    }
    if (is.null(labels)) return(list(double(), character()))
    argument <- sprintf("labels for `%s`", name)
    label_text <- names(labels)
    valid <- if (allow_legacy_codes) {
        missing_codes <- .tab_missing_codes(labels)
        tagged <- !is.na(missing_codes) &
            missing_codes >= utf8ToInt("a") &
            missing_codes <= utf8ToInt("z")
        observed <- is.na(missing_codes) & is.finite(labels) &
            labels == floor(labels) &
            labels >= -(.Machine$integer.max + 1) &
            labels <= .Machine$integer.max
        tagged | observed
    } else {
        .stata_value_label_code_info(labels)$valid
    }
    if (any(!valid)) {
        range <- if (allow_legacy_codes) {
            "signed 32-bit integers"
        } else {
            "nonmissing integers in Stata's long range"
        }
        .dta_write_abort(sprintf(
            paste0(
                "`%s` codes must be %s or extended missings ",
                "`.a` through `.z`"
            ),
            argument, range
        ))
    }
    violations <- .value_label_limit_violations(
        length(labels), label_text, name
    )
    if (length(violations)) {
        .dta_write_abort(paste(violations, collapse = "; "))
    }
    list(unname(labels), enc2utf8(label_text))
}

.value_label_mappings_identical <- function(left, right,
                                             right_values = NULL) {
    if (identical(left$source, right$source, single.NA = FALSE)) return(TRUE)
    if (!is.numeric(left$label_values) || !is.numeric(right$label_values) ||
        is.null(left$label_texts) || is.null(right$label_texts)) {
        return(FALSE)
    }
    if (!identical(
        enc2utf8(left$label_texts), enc2utf8(right$label_texts)
    )) return(FALSE)
    if (is.null(right_values)) right_values <- as.double(right$label_values)
    identical(
        as.double(left$label_values), right_values,
        single.NA = FALSE
    )
}

.write_value_label_mapping <- function(column, factor_value_labels) {
    if (factor_value_labels && is.factor(column)) {
        levels <- levels(column)
        return(list(
            source = levels,
            label_values = seq_along(levels),
            label_texts = levels
        ))
    }
    labels <- attr(column, "labels", exact = TRUE)
    if (is.null(labels)) return(NULL)
    list(
        source = labels,
        label_values = labels,
        label_texts = names(labels)
    )
}

.resolve_write_value_label_names <- function(data,
                                              factor_value_labels = FALSE) {
    column_names <- names(data)
    mappings <- lapply(
        data, .write_value_label_mapping,
        factor_value_labels = factor_value_labels
    )
    usable <- !vapply(mappings, is.null, logical(1))
    explicit <- lapply(data, attr, which = "value.label.name", exact = TRUE)

    for (index in seq_along(data)) {
        table_name <- explicit[[index]]
        if (is.null(table_name)) next
        if (!is.character(table_name) || length(table_name) != 1L ||
            is.na(table_name) || !.valid_stata_names(table_name)) {
            .dta_write_abort(sprintf(
                paste0(
                    "Column `%s` has an invalid `value.label.name`; ",
                    "it must be one valid Stata name with at most 32 Unicode characters"
                ),
                column_names[[index]]
            ))
        }
        if (!usable[[index]]) {
            .dta_write_abort(sprintf(
                paste0(
                    "Column `%s` has `value.label.name` but no usable ",
                    "`labels` mapping"
                ),
                column_names[[index]]
            ))
        }
        explicit[[index]] <- enc2utf8(table_name)
    }

    if (!any(usable)) {
        return(list(
            names = column_names,
            indices = rep.int(-1L, length(data)),
            first_columns = integer(),
            warnings = list()
        ))
    }

    requested <- column_names
    for (index in which(usable)) {
        if (!is.null(explicit[[index]])) requested[[index]] <- explicit[[index]]
    }
    initial_claimants <- split(which(usable), requested[usable])
    claimants <- list2env(
        initial_claimants, envir = new.env(hash = TRUE, parent = emptyenv())
    )
    possible_owner_names <- unique(c(
        names(initial_claimants),
        column_names[usable & !vapply(explicit, is.null, logical(1))]
    ))
    owner_indices <- match(possible_owner_names, column_names, nomatch = 0L)
    has_owner <- owner_indices > 0L
    owners <- list2env(
        as.list(stats::setNames(
            owner_indices[has_owner], possible_owner_names[has_owner]
        )),
        envir = new.env(hash = TRUE, parent = emptyenv())
    )
    fallback <- rep(FALSE, length(data))
    initial_names <- names(initial_claimants)
    explicit_count <- sum(!vapply(explicit, is.null, logical(1)))
    conflicts <- new.env(hash = TRUE, parent = emptyenv())
    conflict_names <- character(length(initial_names) + explicit_count)
    conflict_count <- 0L
    queue <- character(length(initial_names) + explicit_count)
    if (length(initial_names)) queue[seq_along(initial_names)] <- initial_names
    head <- 1L
    tail <- length(initial_names)

    while (head <= tail) {
        table_name <- queue[[head]]
        head <- head + 1L
        members <- get0(
            table_name, envir = claimants, inherits = FALSE,
            ifnotfound = integer()
        )
        if (length(members)) members <- members[!fallback[members]]
        owner <- get0(table_name, envir = owners, inherits = FALSE)
        if (!is.null(owner) && usable[[owner]] && fallback[[owner]]) {
            members <- unique(c(members, owner))
        }
        if (length(members) < 2L) next

        reference <- mappings[[members[[1L]]]]
        reference_values <- NULL
        same <- TRUE
        for (index in members[-1L]) {
            mapping <- mappings[[index]]
            if (!identical(
                mapping$source, reference$source, single.NA = FALSE
            ) && is.null(reference_values) &&
                is.numeric(reference$label_values)) {
                reference_values <- as.double(reference$label_values)
            }
            if (!.value_label_mappings_identical(
                mapping, reference, reference_values
            )) {
                same <- FALSE
                break
            }
        }
        if (same) next

        existing_conflict <- get0(
            table_name, envir = conflicts, inherits = FALSE,
            ifnotfound = character()
        )
        if (!length(existing_conflict)) {
            conflict_count <- conflict_count + 1L
            conflict_names[[conflict_count]] <- table_name
        }
        assign(
            table_name,
            unique(c(existing_conflict, column_names[members])),
            envir = conflicts
        )
        newly_fallback <- members[
            !fallback[members] & requested[members] != column_names[members]
        ]
        if (length(newly_fallback)) {
            fallback[newly_fallback] <- TRUE
            positions <- tail + seq_along(newly_fallback)
            queue[positions] <- column_names[newly_fallback]
            tail <- tail + length(newly_fallback)
        }
    }
    resolved <- requested
    resolved[fallback] <- column_names[fallback]

    table_indices <- new.env(hash = TRUE, parent = emptyenv())
    indices <- rep.int(-1L, length(data))
    first_columns <- integer(length(data))
    table_count <- 0L
    for (index in which(usable)) {
        table_name <- resolved[[index]]
        table_index <- get0(
            table_name, envir = table_indices, inherits = FALSE
        )
        if (is.null(table_index)) {
            table_index <- table_count
            assign(table_name, table_index, envir = table_indices)
            first_columns[[table_count + 1L]] <- index
            table_count <- table_count + 1L
        }
        indices[[index]] <- table_index
    }

    warnings <- list()
    if (conflict_count) {
        details <- vapply(
            conflict_names[seq_len(conflict_count)],
            function(table_name) {
                sprintf(
                    "`%s` (%s)", table_name,
                    paste(sprintf(
                        "`%s`",
                        get(table_name, envir = conflicts, inherits = FALSE)
                    ), collapse = ", ")
                )
            },
            character(1)
        )
        warnings <- list(.dta_write_warning(
            sprintf(
                paste0(
                    "Conflicting value-label table mappings: %s. ",
                    "Used each affected variable name as its table name instead."
                ),
                paste(details, collapse = "; ")
            ),
            "dtatools_write_value_label_name_conflict_warning"
        ))
    }

    list(
        names = resolved,
        indices = indices,
        first_columns = first_columns[seq_len(table_count)],
        warnings = warnings
    )
}

.new_write_value_label_plan <- function(data, factor_value_labels = FALSE,
                                         validate_column, prepare_table) {
    resolution <- .resolve_write_value_label_names(
        data, factor_value_labels = factor_value_labels
    )
    for (column_index in which(resolution$indices >= 0L)) {
        validate_column(
            data[[column_index]], names(data)[[column_index]], column_index
        )
    }
    tables <- vector("list", length(resolution$first_columns))
    for (table_position in seq_along(resolution$first_columns)) {
        column_index <- resolution$first_columns[[table_position]]
        prepared <- prepare_table(
            data[[column_index]], names(data)[[column_index]], column_index
        )
        tables[[table_position]] <- stats::setNames(list(
            enc2utf8(resolution$names[[column_index]]),
            prepared[[1L]], prepared[[2L]]
        ), c("name", "label_values", "label_texts"))
    }
    list(
        indices = resolution$indices,
        tables = tables,
        warnings = resolution$warnings
    )
}

.write_datetime_timezone <- function(column) {
    timezone <- attr(column, "tzone", exact = TRUE)
    if (is.null(timezone) || !length(timezone) || is.na(timezone[[1L]])) {
        ""
    } else {
        timezone[[1L]]
    }
}

.adjust_datetime_write_values <- function(values, timezone) {
    values <- as.double(values)
    row_count <- length(values)
    start <- 1
    while (start <= row_count) {
        end <- min(start + 65535, row_count)
        rows <- seq.int(start, end)
        rows <- rows[is.finite(values[rows])]
        if (length(rows)) {
            local <- suppressWarnings(as.POSIXlt(
                structure(
                    values[rows],
                    class = c("POSIXct", "POSIXt"),
                    tzone = timezone
                ),
                tz = timezone
            ))
            resolved <- rep(FALSE, length(rows))
            offset <- local$gmtoff
            if (!is.null(offset) && length(offset) == length(rows)) {
                valid_offset <- !is.na(offset)
                if (any(valid_offset)) {
                    resolved[valid_offset] <- TRUE
                    offset_rows <- rows[valid_offset]
                    values[offset_rows] <-
                        values[offset_rows] + offset[valid_offset]
                }
            }
            unresolved <- which(!resolved)
            if (length(unresolved)) {
                fallback <- suppressWarnings(as.double(ISOdatetime(
                    local$year[unresolved] + 1900L,
                    local$mon[unresolved] + 1L,
                    local$mday[unresolved],
                    local$hour[unresolved],
                    local$min[unresolved],
                    local$sec[unresolved],
                    tz = "UTC"
                )))
                valid_fallback <- is.finite(fallback)
                if (any(valid_fallback)) {
                    values[rows[unresolved[valid_fallback]]] <-
                        fallback[valid_fallback]
                }
            }
        }
        start <- end + 1L
    }
    values
}

.temporal_write_values <- function(column, kind, adjust_tz) {
    values <- as.double(column)
    if (identical(kind, "date")) {
        return(list(values = values, shift = 3653, scale = 1))
    }
    if (adjust_tz) {
        timezone <- .write_datetime_timezone(column)
        if (!(timezone %in% c("UTC", "GMT"))) {
            values <- .adjust_datetime_write_values(values, timezone)
        }
    }
    list(values = values, shift = 315619200, scale = 1000)
}

.prepare_dta_write_numeric <- function(column, name, kind, adjust_tz) {
    temporal <- if (kind %in% c("date", "datetime")) kind else NULL
    storage <- .numeric_write_storage(column)
    if (is.null(storage)) {
        .dta_write_abort(sprintf(
            "Column `%s` has unsupported type or class: %s",
            name, paste(class(column), collapse = "/")
        ))
    }
    values <- if (is.null(temporal)) {
        list(values = column, shift = 0, scale = 1)
    } else {
        .temporal_write_values(column, temporal, adjust_tz)
    }
    list(
        storage = storage,
        temporal = temporal,
        values = values$values,
        shift = values$shift,
        scale = values$scale
    )
}

.dta_write_numeric_replacement_mask <- function(plan) {
    values <- as.double(plan$values)
    missing_codes <- .tab_missing_codes(values)
    observed <- is.na(missing_codes)
    valid_missing <- missing_codes == 0L |
        (missing_codes >= utf8ToInt("a") &
         missing_codes <= utf8ToInt("z"))
    invalid_missing <- !observed & !valid_missing
    temporal <- if (is.null(plan$temporal)) {
        .stata_temporal_none
    } else {
        switch(
            plan$temporal,
            date = .stata_temporal_date,
            datetime = .stata_temporal_datetime
        )
    }
    encoded <- .encode_stata_temporal(
        values, observed, temporal
    )
    invalid_missing |
        .invalid_stata_observed(
            encoded, observed, plan$storage
        )
}

.new_dta_write_column <- function(name, type_code, format, label, values,
                                  numeric_shift = 0,
                                  numeric_scale = 1,
                                  value_label_index = -1L,
                                  character_missing = NULL,
                                  stata_metadata) {
    result <- stats::setNames(list(
        enc2utf8(name), as.integer(type_code), enc2utf8(format), label,
        values, numeric_shift, numeric_scale, as.integer(value_label_index),
        stata_metadata
    ), c(
        "name", "type_code", "format", "label", "values",
        "numeric_shift", "numeric_scale", "value_label_index",
        "stata_metadata"
    ))
    if (!is.null(character_missing)) {
        attr(result, "character_missing") <- character_missing
    }
    result
}

.prepare_dta_write_column <- function(column, name, kind, strl_threshold,
                                      adjust_tz, value_label_index) {
    variable_label <- .write_text(
        attr(column, "label", exact = TRUE),
        sprintf("variable label for `%s`", name)
    )
    stata_metadata <- .stata_metadata_payload(
        stata_notes(column), stata_characteristics(column)
    )
    if (identical(kind, "factor")) {
        format <- .prepare_write_format(
            column, name, .default_stata_format("long"), "numeric"
        )
        return(.new_dta_write_column(
            name, 2L, format, variable_label, column,
            value_label_index = value_label_index,
            stata_metadata = stata_metadata
        ))
    }
    if (identical(kind, "character")) {
        plan <- .Call(C_dtatools_write_string_plan, column)
        maximum <- plan[[1L]]
        values <- plan[[3L]]
        declared <- attr(column, "stata.string.storage", exact = TRUE)
        if (!is.null(declared) && (!is.character(declared) ||
            length(declared) != 1L || is.na(declared) ||
            !grepl("^(strL|str([1-9]|[1-9][0-9]{1,2}|1[0-9]{3}|20[0-3][0-9]|204[0-5]))$", declared))) {
            .dta_write_abort(sprintf(
                "Column `%s` has an invalid `stata.string.storage` declaration",
                name
            ))
        }
        declared_width <- if (!is.null(declared) && declared != "strL") {
            as.integer(sub("^str", "", declared))
        } else NULL
        if (!is.null(declared_width)) maximum <- max(maximum, declared_width)
        fixed <- !identical(declared, "strL") &&
            maximum <= 2045L &&
            (!is.null(declared_width) || maximum <= strl_threshold)
        width <- max(1L, maximum)
        type_code <- if (fixed) width + 4L else 2050L
        storage <- if (fixed) "fixed" else "strL"
        format <- .prepare_write_format(
            column, name, .default_stata_format(storage, width), "string"
        )
        if (!is.null(attr(column, "labels", exact = TRUE))) {
            .dta_write_abort(sprintf(
                "Character column `%s` cannot have numeric value labels", name
            ))
        }
        return(.new_dta_write_column(
            name, type_code, format, variable_label, values,
            character_missing = plan[[2L]],
            stata_metadata = stata_metadata
        ))
    }
    numeric <- .prepare_dta_write_numeric(
        column, name, kind, adjust_tz
    )
    if (is.null(numeric$temporal)) {
        format <- .prepare_write_format(
            column, name, .default_stata_format(numeric$storage),
            "numeric"
        )
    } else {
        default_format <- if (identical(numeric$temporal, "date")) {
            "%td"
        } else "%tc"
        format <- .prepare_write_format(
            column, name, default_format, numeric$temporal
        )
    }
    .new_dta_write_column(
        name, match(numeric$storage, .stata_storage) - 1L,
        format, variable_label, numeric$values,
        numeric_shift = numeric$shift,
        numeric_scale = numeric$scale,
        value_label_index = value_label_index,
        stata_metadata = stata_metadata
    )
}

.write_timestamp <- function(time = Sys.time()) {
    local <- as.POSIXlt(time)
    sprintf(
        "%02d %s %04d %02d:%02d",
        local$mday, month.abb[[local$mon + 1L]], local$year + 1900L,
        local$hour, local$min
    )
}

.prepare_dta_write <- function(data, label, strl_threshold, adjust_tz,
                               version = 19L) {
    write_warnings <- list()
    if (!is.data.frame(data)) {
        .dta_write_abort("`data` must be a data frame or tibble",
                         "dtatools_write_argument_error")
    }
    if (ncol(data) == 0L) {
        .dta_write_abort("`data` must contain at least one column")
    }
    if (ncol(data) > 120000L) {
        .dta_write_abort("`data` has more than Stata's 120,000-variable limit")
    }
    if (version == 18L && ncol(data) > 32767L) {
        .dta_write_abort(
            "`data` has more than Stata 18's 32,767-variable limit"
        )
    }
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
    kinds <- vapply(data, .write_column_kind, character(1))
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
    label <- .write_text(label, "label")
    notes <- stata_notes(data)
    characteristics <- stata_characteristics(data)
    value_label_plan <- .new_write_value_label_plan(
        data,
        factor_value_labels = TRUE,
        validate_column = function(column, name, index) {
            if (identical(kinds[[index]], "factor")) {
                levels <- levels(column)
                if (anyNA(levels) || any(!nzchar(levels))) {
                    .dta_write_abort(sprintf(
                        "Factor column `%s` has an empty or missing level", name
                    ))
                }
                return(invisible(NULL))
            }
            if (identical(kinds[[index]], "character")) {
                .dta_write_abort(sprintf(
                    "Character column `%s` cannot have numeric value labels",
                    name
                ))
            }
            .validate_write_value_label_shape(column, name)
            invisible(NULL)
        },
        prepare_table = function(column, name, index) {
            if (identical(kinds[[index]], "factor")) {
                levels <- levels(column)
                violations <- .value_label_limit_violations(
                    length(levels), levels, name
                )
                if (length(violations)) {
                    .dta_write_abort(paste(violations, collapse = "; "))
                }
                return(list(as.double(seq_along(levels)), enc2utf8(levels)))
            }
            .prepare_write_value_labels(column, name)
        }
    )
    columns <- Map(
        .prepare_dta_write_column, data, data_names, kinds,
        value_label_plan$indices,
        MoreArgs = list(
            strl_threshold = strl_threshold,
            adjust_tz = adjust_tz
        )
    )
    write_warnings <- c(write_warnings, value_label_plan$warnings)
    factor_columns <- data_names[kinds == "factor"]
    if (length(factor_columns)) {
        write_warnings <- c(write_warnings, list(.dta_write_warning(
            sprintf(
                paste0(
                    "Converted factor columns to labelled Stata long integers: %s. ",
                    "Factor class and orderedness will not be restored on read."
                ),
                paste(sprintf("`%s`", factor_columns), collapse = ", ")
            ),
            "dtatools_write_factor_warning"
        )))
    }
    character_missing <- vapply(columns, function(column) {
        count <- attr(column, "character_missing", exact = TRUE)
        if (is.null(count)) 0 else count
    }, numeric(1))
    write_warnings <- c(write_warnings, .dta_write_count_warnings(
        character_missing,
        data_names,
        "Converted character missing values to empty strings",
        "dtatools_write_character_missing_warning"
    ))
    specification <- list(
        label, .stata_metadata_payload(notes, characteristics),
        columns, .write_timestamp(), value_label_plan$tables
    )
    attr(specification, "write_warnings") <- write_warnings
    specification
}

.validate_dta_write_destination <- function(path) {
    kind <- tryCatch(
        .Call(C_dtatools_write_path_kind, path),
        error = function(condition) {
            .dta_write_abort(
                conditionMessage(condition),
                "dtatools_write_path_error"
            )
        }
    )
    if (kind == 2L) {
        .dta_write_abort(
            "Refusing to replace a symbolic-link destination",
            "dtatools_write_path_error"
        )
    }
    if (kind == 3L) {
        .dta_write_abort(
            "Refusing to replace a directory destination",
            "dtatools_write_path_error"
        )
    }
    if (kind == 4L) {
        .dta_write_abort(
            "Refusing to replace a non-regular-file destination",
            "dtatools_write_path_error"
        )
    }
    kind
}

.resolve_dta_write_path <- function(path, default_extension = "dta") {
    if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
        .dta_write_abort("`path` must be one nonempty local filename",
                         "dtatools_write_path_error")
    }
    path <- path.expand(path)
    write_warnings <- list()
    extension <- tolower(tools::file_ext(basename(path)))
    if (extension %in% c("gz", "bz2", "xz", "zip")) {
        .dta_write_abort(sprintf(
            "Compressed output paths are not supported; write an ordinary `.%s` file",
            default_extension
        ), "dtatools_write_path_error")
    }
    if (!nzchar(extension)) {
        path <- paste0(path, ".", default_extension)
        write_warnings <- list(.dta_write_warning(
            sprintf("`path` has no extension; writing `%s`", path),
            "dtatools_write_extension_warning"
        ))
    }
    parent <- dirname(path)
    if (!dir.exists(parent)) {
        .dta_write_abort(sprintf("Output directory does not exist: `%s`", parent),
                         "dtatools_write_path_error")
    }
    path <- file.path(
        normalizePath(parent, winslash = "/", mustWork = TRUE),
        basename(path)
    )
    .validate_dta_write_destination(path)
    list(path = path, warnings = write_warnings)
}
