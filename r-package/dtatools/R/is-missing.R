#' Test values with Stata's missing-value rule
#'
#' `is_missing()` is the dtatools translation of Stata's `missing()` and
#' `mi()` expression functions. With one argument, it returns one logical value
#' per element. With several arguments, it returns `TRUE` in each row where any
#' corresponding value is missing. Arguments of size one are recycled; other
#' incompatible sizes are errors.
#'
#' Numeric system missing, every extended missing `.a` through `.z`, R `NA`,
#' and R `NaN` are missing. For character vectors, both `""` and
#' `NA_character_` are missing. Nonmissing logical values, nonempty strings,
#' and observed numeric values are not missing. Unlike [is.na()], this function
#' therefore detects Stata's empty-string missing value. Unlike
#' [is_tagged_missing()], it detects system missing and non-tagged R missing
#' values as well as extended missings. It never changes the input or a tagged
#' missing payload.
#'
#' Atomic dtatools numeric and temporal vectors, base [Date] and [POSIXct]
#' vectors, and haven-style labelled atomic vectors use their underlying
#' numeric or character values. This includes labelled strings. Factors,
#' matrices and arrays, lists, data frames, `POSIXlt`, `difftime`, raw and
#' complex vectors, and other classes are rejected. These objects do not map to
#' one Stata expression variable without an explicit conversion.
#'
#' Zero-length inputs return `logical(0)`. A zero-length argument may be
#' combined with size-one arguments, but not with longer vectors. When several
#' arguments determine the same non-scalar size, the first named argument of
#' that size supplies result names. Other attributes are not copied. Compact
#' DTA and Arrow numeric columns are inspected without materializing their
#' double backing. The result is always a logical vector suitable for command
#' expressions such as `where`.
#'
#' @param ... One or more supported atomic vectors.
#' @return A logical vector with the arguments' common size.
#' @examples
#' values <- c(1, NA_real_, tagged_missing("a"), NaN)
#' is_missing(values)
#'
#' # Stata: missing(month), mi(month), and missing(month, year)
#' month <- c(1, NA, 3)
#' year <- c(2020, 2021, NA)
#' is_missing(month)
#' is_missing(month, year)
#'
#' is_missing(c("observed", "", NA_character_))
#' is.na("")
#' is_missing("")
#' is_tagged_missing(values)
#'
#' # Stata: egen births = total(!mi(bh_line_number)), by(woman)
#' bh_line_number <- c(1, NA, tagged_missing("a"), 2)
#' sum(!is_missing(bh_line_number))
#' @export
is_missing <- function(...) {
    .Call(C_dtatools_is_missing, list(...))
}
