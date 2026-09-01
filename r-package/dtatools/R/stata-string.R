#' Construct a Stata string vector
#'
#' Creates an owned Stata string vector whose fixed-width or `strL` storage
#' declaration survives supported vector operations. Stata strings use `""`
#' for missing values, so `NA_character_` is rejected.
#'
#' @param x A character vector without missing values.
#' @param storage `NULL` to infer the narrowest storage, `"str1"` through
#'   `"str2045"`, or `"strL"`.
#' @return A character vector with declared Stata string storage.
#' @export
stata_string <- function(x = character(), storage = NULL) {
    if (!is.character(x) || !is.null(dim(x))) {
        stop("`x` must be a character vector", call. = FALSE)
    }
    if (anyNA(x)) {
        stop("Stata strings cannot contain `NA_character_`; use `\"\"`", call. = FALSE)
    }
    x <- enc2utf8(x)
    required <- .stata_string_required_width(x)
    storage <- .normalize_stata_string_storage(storage, required)
    .new_stata_string(x, storage)
}

.stata_string_required_width <- function(x) {
    if (!length(x)) return(1L)
    max(nchar(enc2utf8(x), type = "bytes"))
}

.stata_string_storage_width <- function(storage) {
    if (identical(storage, "strL")) return(Inf)
    as.integer(substring(storage, 4L))
}

.normalize_stata_string_storage <- function(storage, required = 1L) {
    if (is.null(storage)) {
        return(if (required > 2045L) "strL" else paste0("str", max(1L, required)))
    }
    valid <- is.character(storage) && length(storage) == 1L && !is.na(storage) &&
        (identical(storage, "strL") || grepl("^str([1-9]|[1-9][0-9]{1,2}|1[0-9]{3}|20[0-3][0-9]|204[0-5])$", storage))
    if (!valid) {
        stop("`storage` must be `str1` through `str2045`, or `strL`", call. = FALSE)
    }
    if (.stata_string_storage_width(storage) < required) {
        stop(sprintf(
            "Stata %s storage cannot represent `x`; use `stata_string(x, storage = %s)`",
            storage, if (required > 2045L) '"strL"' else paste0('"str', required, '"')
        ), call. = FALSE)
    }
    storage
}

.new_stata_string <- function(x, storage, prototype = NULL) {
    value_names <- names(x)
    if (!is.null(prototype)) {
        # Attribute replacement materializes the dictionary-string ALTREP used
        # by read_dta(). Restore the owned attributes in place so imported
        # strings keep their deferred backing until a value operation needs it.
        x <- .restore_stata_variable_metadata(x, prototype, names = value_names)
    } else {
        for (name in setdiff(names(attributes(x)), "names")) {
            attr(x, name) <- NULL
        }
    }
    attr(x, "stata.string.storage") <- storage
    attr(x, "class") <- c("stata_string", "vctrs_vctr", "character")
    if (!is.null(value_names)) names(x) <- value_names
    x
}

.stata_string_data <- function(x) {
    value_names <- names(x)
    attributes(x) <- NULL
    names(x) <- value_names
    x
}

#' @export
as.character.stata_string <- function(x, ...) .stata_string_data(x)

#' @export
vec_proxy.stata_string <- function(x, ...) .stata_string_data(x)

#' @export
vec_restore.stata_string <- function(x, to, ...) {
    storage <- attr(to, "stata.string.storage", exact = TRUE)
    .new_stata_string(as.character(x), storage, to)
}

#' @export
`[.stata_string` <- function(x, i, ..., drop = TRUE) {
    if (length(list(...))) stop("Stata string vectors do not support array subscripts", call. = FALSE)
    data <- .stata_string_data(x)
    result <- if (missing(i)) data[] else data[i]
    .new_stata_string(result, attr(x, "stata.string.storage", exact = TRUE), x)
}

#' @export
`[[.stata_string` <- function(x, i, ...) {
    if (length(list(...))) stop("Stata string vectors do not support array subscripts", call. = FALSE)
    result <- .stata_string_data(x)[[i]]
    .new_stata_string(result, attr(x, "stata.string.storage", exact = TRUE), x)
}

.stata_string_common_storage <- function(x, y) {
    declared <- c(
        if (inherits(x, "stata_string")) attr(x, "stata.string.storage", exact = TRUE),
        if (inherits(y, "stata_string")) attr(y, "stata.string.storage", exact = TRUE)
    )
    required <- max(
        .stata_string_required_width(as.character(x)),
        .stata_string_required_width(as.character(y))
    )
    if ("strL" %in% declared || required > 2045L) return("strL")
    widths <- vapply(declared, .stata_string_storage_width, numeric(1))
    paste0("str", max(c(1, required, widths)))
}

.stata_string_ptype2 <- function(x, y, ..., x_arg = "", y_arg = "") {
    both_owned <- inherits(x, "stata_string") && inherits(y, "stata_string")
    storage <- if (both_owned) .stata_string_common_storage(x, y) else "strL"
    prototype <- if (inherits(x, "stata_string")) x else y
    result <- .new_stata_string(character(), storage, prototype)
    if (both_owned) {
        result <- .reconcile_stata_metadata(result, x, y, x_arg, y_arg)
    }
    result
}

#' @export
vec_ptype2.stata_string.stata_string <- .stata_string_ptype2
#' @export
vec_ptype2.stata_string.character <- .stata_string_ptype2
#' @export
vec_ptype2.character.stata_string <- .stata_string_ptype2

.cast_stata_string <- function(x, to) {
    storage <- attr(to, "stata.string.storage", exact = TRUE)
    value <- as.character(x)
    if (anyNA(value)) {
        stop("Stata strings cannot contain `NA_character_`; use `\"\"`", call. = FALSE)
    }
    .normalize_stata_string_storage(storage, .stata_string_required_width(value))
    .new_stata_string(value, storage, to)
}

#' @export
vec_cast.stata_string.stata_string <- function(x, to, ...) .cast_stata_string(x, to)
#' @export
vec_cast.stata_string.character <- function(x, to, ...) .cast_stata_string(x, to)
#' @export
vec_cast.character.stata_string <- function(x, to, ...) as.character(x)

#' @export
`[<-.stata_string` <- function(x, i, ..., value) {
    if (length(list(...))) stop("Stata string vectors do not support array subscripts", call. = FALSE)
    replacement <- as.character(.cast_stata_string(value, x))
    data <- .stata_string_data(x)
    if (missing(i)) data[] <- replacement else data[i] <- replacement
    if (anyNA(data)) {
        stop("Stata strings cannot contain `NA_character_`; use `\"\"`", call. = FALSE)
    }
    .new_stata_string(data, attr(x, "stata.string.storage", exact = TRUE), x)
}

#' @export
`[[<-.stata_string` <- function(x, i, ..., value) {
    if (length(list(...))) stop("Stata string vectors do not support array subscripts", call. = FALSE)
    replacement <- as.character(.cast_stata_string(value, x))
    data <- .stata_string_data(x)
    data[[i]] <- replacement
    if (anyNA(data)) {
        stop("Stata strings cannot contain `NA_character_`; use `\"\"`", call. = FALSE)
    }
    .new_stata_string(data, attr(x, "stata.string.storage", exact = TRUE), x)
}

#' @export
c.stata_string <- function(..., recursive = FALSE) {
    if (recursive) stop("recursive concatenation is not supported", call. = FALSE)
    vctrs::vec_c(...)
}

#' @export
sort.stata_string <- function(
    x, decreasing = FALSE, na.last = NA, ..., partial = NULL,
    method = "auto"
) {
    if (!is.null(partial)) {
        stop(
            "Partial sorting of Stata-backed vectors is not supported yet",
            call. = FALSE
        )
    }
    if (!missing(na.last) && !identical(na.last, NA)) {
        warning(
            "`na.last` has no effect because Stata strings cannot contain `NA_character_`",
            call. = FALSE
        )
    }
    method <- match.arg(method, c("auto", "shell", "radix"))
    x[order(as.character(x), decreasing = decreasing, method = method)]
}
