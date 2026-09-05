#' Stata group identifiers and first-observation tags
#'
#' `dta_group_id()` numbers distinct keys in Stata sort order, preserving
#' observation order. Codes are not permanent identifiers when keys change.
#' `dta_group_tag()` marks the first eligible observation of each key with one.
#' Both functions return vectors usable inside `egen()` or `:=`.
#'
#' Missing numeric keys and empty strings are excluded by default. With
#' `missing = TRUE`, system missing and each extended missing are distinct
#' keys. `NA_character_`, NaN, infinities, factors, and unsupported classes are
#' rejected. Columns must have equal lengths, including zero lengths.
#' Grouping column names must be unique; use named list elements to distinguish
#' repeated vectors intentionally.
#'
#' Group codes are unrounded doubles unless `autotype = TRUE`, which declares
#' byte, int, long, or double storage. Tags always declare byte storage.
#' Results receive a variable label `group(varlist)` or `tag(varlist)`; long
#' labels are stored in a note with the variable label `see notes`.
#' Both helpers use an 80-display-column threshold. This deliberately
#' normalizes Stata's shipped tag helper, whose byte-length check and final
#' label overwrite can leave a truncated expression instead of `see notes`.
#'
#' With `label = TRUE`, each code receives its key text, joined with spaces.
#' Numeric assigned labels take precedence over numeric text. Like Stata's
#' shipped group helper, numeric fallback ignores the source display format.
#' Truncation applies to strings and assigned label text, by Unicode display
#' width, before numeric fallback. Leading and trailing whitespace is trimmed
#' after truncation. R strings cannot contain embedded NUL bytes.
#' At most 65,536 groups can receive value labels. The optional table name is
#' a serialization hint; each result owns its mapping independently.
#'
#' @param ... Vectors, or a single list or data frame of columns. Supplied
#'   argument or list names are used literally in the generated variable label;
#'   otherwise bare argument names or positional names are used.
#' @param missing Include missing keys as groups.
#' @param autotype Declare the smallest byte, int, long, or double storage.
#' @param label Generate value labels for group codes.
#' @param label_name Optional value-label table name, requiring `label = TRUE`.
#' @param truncate Optional positive integer display width for label components,
#'   requiring `label = TRUE`.
#' @return A numeric vector with group metadata. Tags and autotyped identifiers
#'   are Stata numeric vectors.
#' @examples
#' dta_group_id(region = c("west", "east", "west"))
#' dta_group_tag(c(2, 1, 2, NA))
#' @export
dta_group_id <- function(..., missing = FALSE, autotype = FALSE,
                         label = FALSE, label_name = NULL, truncate = NULL) {
    .dta_group_flag(missing, "missing")
    .dta_group_flag(autotype, "autotype")
    .dta_group_flag(label, "label")
    if (!is.null(label_name) && (!label || !is.character(label_name) ||
        length(label_name) != 1L || is.na(label_name) ||
        !.valid_dta_names(label_name))) {
        stop("`label_name` requires `label = TRUE` and a valid Stata name",
             call. = FALSE)
    }
    if (!is.null(truncate) && (!label || !is.numeric(truncate) ||
        length(truncate) != 1L || is.na(truncate) || !is.finite(truncate) ||
        truncate < 1 || truncate != floor(truncate))) {
        stop("`truncate` requires `label = TRUE` and a positive integer",
             call. = FALSE)
    }
    columns <- .dta_group_columns(list(...), as.list(substitute(list(...)))[-1L])
    plan <- .Call(C_dtatools_egen_group, columns, missing,
                  isTRUE(.dta_egen_evaluation$allow_nan))
    result <- plan$codes
    if (autotype) {
        constructor <- get(paste0("dta_", .dta_group_storage(length(plan$first))),
                           envir = environment(dta_group_id))
        result <- constructor(result)
    }
    if (label) {
        if (length(plan$first) > 65536L)
            stop("Cannot label more than 65,536 groups", call. = FALSE)
        components <- lapply(columns, .dta_group_label_component,
                             rows = plan$first, truncate = truncate)
        text <- if (length(plan$first))
            do.call(paste, c(components, sep = " ")) else character()
        attr(result, "labels") <- stats::setNames(as.double(seq_along(text)), text)
        if (!is.null(label_name)) attr(result, "value.label.name") <- label_name
    }
    .dta_group_metadata(result, "group", names(columns))
}

#' @rdname dta_group_id
#' @export
dta_group_tag <- function(..., missing = FALSE) {
    .dta_group_flag(missing, "missing")
    columns <- .dta_group_columns(list(...), as.list(substitute(list(...)))[-1L])
    plan <- .Call(C_dtatools_egen_group, columns, missing,
                  isTRUE(.dta_egen_evaluation$allow_nan))
    result <- numeric(length(plan$codes))
    result[plan$first] <- 1
    .dta_group_metadata(dta_byte(result), "tag", names(columns))
}

.dta_group_flag <- function(value, name) {
    if (!is.logical(value) || length(value) != 1L || is.na(value))
        stop(sprintf("`%s` must be TRUE or FALSE", name), call. = FALSE)
}

.dta_egen_key_plan <- function(columns) {
    columns <- .dta_group_columns(columns, vector("list", length(columns)))
    .Call(C_dtatools_egen_group, columns, TRUE, FALSE)
}

.dta_group_columns <- function(values, expressions) {
    if (length(values) == 1L && (is.data.frame(values[[1L]]) ||
        (is.list(values[[1L]]) && !is.object(values[[1L]])))) {
        values <- as.list(values[[1L]])
        expressions <- vector("list", length(values))
    }
    if (!length(values)) stop("Supply at least one grouping column", call. = FALSE)
    sizes <- lengths(values)
    if (length(unique(sizes)) != 1L)
        stop("Grouping columns must have equal lengths", call. = FALSE)
    column_names <- names(values)
    if (is.null(column_names)) column_names <- rep("", length(values))
    for (i in seq_along(values)) {
        if (is.na(column_names[i]) || !nzchar(column_names[i])) {
            column_names[i] <- if (is.symbol(expressions[[i]]))
                as.character(expressions[[i]]) else paste0("v", i)
        }
        x <- values[[i]]
        supported <- if (typeof(x) == "character") {
            inherits(x, "dta_string") || .generated_numeric_class_supported(x)
        } else .dta_egen_numeric_supported(x)
        if (!supported || !is.null(dim(x)) || is.factor(x) ||
            inherits(x, c("integer64", "difftime")) ||
            !typeof(x) %in% c("double", "integer", "logical", "character"))
            stop("Grouping columns must be numeric or character vectors",
                 call. = FALSE)
        if (inherits(x, "dta_temporal")) {
            values[[i]] <- .base_dta_temporal(x)
        } else if (inherits(x, "Date")) {
            values[[i]] <- as.double(x) + 3653
        } else if (inherits(x, "POSIXct")) {
            values[[i]] <- (as.double(x) + 315619200) * 1000
        }
        if (!identical(values[[i]], x)) {
            attr(values[[i]], "labels") <- attr(x, "labels", exact = TRUE)
        }
    }
    if (anyDuplicated(column_names))
        stop("Grouping column names must be unique", call. = FALSE)
    names(values) <- column_names
    values
}

.dta_group_storage <- function(count) {
    if (count <= 100) "byte" else if (count <= 32740) "int" else
        if (count <= 2147483620) "long" else "double"
}

.dta_group_metadata <- function(value, function_name, columns) {
    text <- paste0(function_name, "(", paste(columns, collapse = " "), ")")
    # Share group()'s display-width rule and useful long-label fallback.
    # _gtag.ado instead checks bytes and overwrites its own fallback label.
    if (nchar(text, type = "width") > 80L) {
        attr(value, "label") <- "see notes"
        attr(value, "notes") <- text
        attr(value, "stata.note.numbers") <- 1L
    } else attr(value, "label") <- text
    value
}

.dta_group_truncate <- function(text, width) {
    if (is.null(width)) return(text)
    vapply(text, function(value) {
        characters <- strsplit(enc2utf8(value), "", fixed = TRUE)[[1L]]
        widths <- nchar(characters, type = "width")
        kept <- characters[cumsum(widths) <= width]
        trimws(paste0(kept, collapse = ""), whitespace = "[\\h\\v]")
    }, character(1), USE.NAMES = FALSE)
}

.dta_group_label_component <- function(x, rows, truncate) {
    values <- x[rows]
    if (typeof(values) == "character")
        return(.dta_group_truncate(as.character(unclass(values)), truncate))
    values <- as.double(unclass(values))
    if (inherits(x, "Date")) values <- values + 3653
    else if (inherits(x, "POSIXct")) values <- (values + 315619200) * 1000
    codes <- .tab_missing_codes(values)
    if (isTRUE(.dta_egen_evaluation$allow_nan)) {
        normalized <- !is.na(codes) & codes == 256L
        codes[normalized] <- 0L
        values[normalized] <- NA_real_
    }
    result <- rep("", length(values))
    observed <- is.na(codes)
    result[observed] <- vapply(values[observed], .dta_group_number, character(1))
    result[!observed] <- vapply(codes[!observed], .tab_missing_name, character(1))
    labels <- attr(x, "labels", exact = TRUE)
    if (!is.null(labels)) {
        if (!.valid_tab_labels(labels))
            stop("Grouping column has invalid value labels", call. = FALSE)
        matched <- match(.dta_value_label_keys(values),
                         .dta_value_label_keys(labels))
        mapped <- rep("", length(values))
        found <- !is.na(matched)
        mapped[found] <- names(labels)[matched[found]]
        mapped <- .dta_group_truncate(mapped, truncate)
        use <- !is.na(mapped) & nzchar(mapped)
        result[use] <- mapped[use]
    }
    result
}

.dta_group_number <- function(value) {
    # _ggroup.ado uses %18.0g for integers and %9.0g otherwise.
    # Their fixed/scientific switches and rounding are pinned by the
    # egen_number_labels_stata18.dta oracle, including carries at 1e7.
    if (value == trunc(value)) {
        return(if (abs(value) >= 1e16) .dta_group_scientific(value, 11L) else
            sprintf("%.0f", if (value == 0) 0 else value))
    }
    if (abs(value) < 1e-5 || abs(value) >= 1e7)
        return(.dta_group_scientific(value, 2L))
    magnitude <- floor(log10(abs(value)))
    places <- 7 - max(0, magnitude + 1)
    text <- sprintf(paste0("%.", places, "f"), value)
    if (abs(as.double(text)) >= 1e7) return(.dta_group_scientific(value, 2L))
    if (places > 0) {
        text <- sub("0+$", "", text)
        text <- sub("\\.$", "", text)
    }
    sub("^(-?)0\\.", "\\1.", text)
}

.dta_group_scientific <- function(value, decimals) {
    text <- sprintf(paste0("%.", decimals, "e"), value)
    exponent <- sub(".*e[+-]", "", text)
    if (nchar(exponent) > 2L) {
        text <- sprintf(paste0("%.", decimals - nchar(exponent) + 2L, "e"), value)
    }
    text
}
