# Printing alone adds these classes. General snapshots remain ordinary
# tibbles, and the stored columns keep their classes and compact backing.
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
    class(result) <- c("dtatools_dibble_display", class(result))
    result
}

# Use pillar's summary hook so grouped and rowwise summaries still supply
# their own dimensions and grouping lines.
#' @exportS3Method pillar::tbl_sum
tbl_sum.dtatools_dibble_display <- function(x, ...) {
    result <- NextMethod()
    names(result)[[1L]] <- "A dibble"
    result
}

#' @export
format.dtatools_ref_data <- function(x, ...) {
    format(.dibble_display_snapshot(x), ...)
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
