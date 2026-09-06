# General snapshots remove dibble dispatch. A display snapshot restores only
# its public identity, plus temporary string views; stored columns are unchanged.
.dibble_display_snapshot <- function(x) {
    result <- .reference_snapshot(x)
    if (!is_dibble(x)) return(result)
    for (index in seq_along(result)) {
        column <- .subset2(result, index)
        classes <- setdiff(class(column), .dta_metadata_vector_class)
        bare_string <- !length(classes) || identical(classes, "character")
        if (is.character(column) && bare_string &&
            !is.null(attr(column, "stata.string.storage", exact = TRUE))) {
            column <- .metadata_copy(column)
            class(column) <- c("dtatools_dibble_string", class(column))
            result[[index]] <- column
        }
    }
    class(result) <- c("dibble", class(result))
    result
}

# Use pillar's summary hook so grouped and rowwise summaries still supply
# their own dimensions and grouping lines.
#' @exportS3Method pillar::tbl_sum
tbl_sum.dibble <- function(x, ...) {
    result <- NextMethod()
    names(result)[[1L]] <- "A dibble"
    result
}

# Delegate to the registered ordinary table method so pillar can still call
# tbl_sum.dibble on the snapshot, without recursively dispatching print.dibble.
.print_dibble <- function(x, ...) {
    utils::getS3method("print", "tbl")(.dibble_display_snapshot(x), ...)
}

#' @export
print.dibble <- function(x, ...) {
    if (.skip_bracket_autoprint(x, sys.nframe(), sys.call(1L))) {
        return(invisible(x))
    }
    .print_dibble(x, ...)
    invisible(x)
}

#' @export
format.dibble <- function(x, ...) {
    utils::getS3method("format", "tbl")(.dibble_display_snapshot(x), ...)
}

# Legacy dibbles still dispatch through shared reference support.
#' @export
format.dtatools_ref_data <- function(x, ...) {
    if (is_dibble(x)) format.dibble(x, ...) else format(.reference_snapshot(x), ...)
}

# These labels read declarations only, including for empty vectors and
# string declarations wider than their current contents. The temporary
# character class is restored by vctrs when pillar slices displayed rows.
#' @exportS3Method vctrs::vec_ptype_abbr
vec_ptype_abbr.dtatools_dibble_string <- function(x, ...) {
    attr(x, "stata.string.storage", exact = TRUE)
}

#' @exportS3Method vctrs::vec_ptype_abbr
vec_ptype_abbr.dta_numeric <- function(x, ...) {
    .declared_dta_storage(x)
}

#' @exportS3Method vctrs::vec_ptype_abbr
vec_ptype_abbr.dta_string <- function(x, ...) {
    attr(x, "stata.string.storage", exact = TRUE)
}

#' @exportS3Method vctrs::vec_ptype_abbr
vec_ptype_abbr.dta_temporal <- function(x, ...) {
    meaning <- if (inherits(x, "Date")) "date" else "dttm"
    paste(.declared_dta_storage(x), meaning, sep = "/")
}

# Metadata restoration puts its marker first, including after pillar slices
# rows. vctrs chooses the most specific class for type abbreviations, so let
# the underlying type supply the label. A metadata copy keeps compact strings
# unchanged while the display-only class attribute is removed.
#' @exportS3Method vctrs::vec_ptype_abbr
vec_ptype_abbr.dtatools_dta_metadata_vector <- function(x, ...) {
    value <- .metadata_copy(x)
    classes <- setdiff(class(value), .dta_metadata_vector_class)
    attr(value, "class") <- if (length(classes)) classes else NULL
    vctrs::vec_ptype_abbr(value, suffix_shape = FALSE)
}
