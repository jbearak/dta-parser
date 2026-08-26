#' Create and inspect Stata tagged missing values
#'
#' `tagged_missing()` creates the R double representation of Stata extended
#' missing values `.a` through `.z`. `missing_tag()` extracts their letters,
#' and `is_tagged_missing()` selects any tagged missing value or a requested
#' set of tags. The inspectors read compact dtaparser columns without
#' materializing their decoded double backing.
#'
#' Tags must be one ASCII letter from `a` through `z`. Uppercase letters are
#' normalized to lowercase. Use ordinary `NA_real_` for Stata system missing
#' (`.`); it is not a tagged missing value. The inspectors recognize only
#' canonical tagged-missing payloads with Stata's `.a` through `.z` tags. They do
#' not classify arbitrary R `NaN` payloads as Stata missing codes.
#'
#' @param tag For `tagged_missing()`, a character vector containing one tag per
#'   element. For `is_tagged_missing()`, tags to match or `NULL` to match any
#'   tagged missing value.
#' @param x A numeric vector.
#' @return `tagged_missing()` returns a double vector. `missing_tag()` returns
#'   each tag letter or `NA_character_`. `is_tagged_missing()` returns a
#'   logical vector. Results retain names, dimensions, and dimension names but
#'   not other attributes from their input.
#' @examples
#' values <- c(1, NA_real_, tagged_missing(c("a", "f", "z")))
#' is.na(values)
#' missing_tag(values)
#' is_tagged_missing(values)
#' is_tagged_missing(values, c("a", "f"))
#' @export
tagged_missing <- function(tag) {
    .Call(C_dtaparser_tagged_missing, tag)
}

#' @rdname tagged_missing
#' @export
missing_tag <- function(x) {
    .Call(C_dtaparser_missing_tag, x)
}

#' @rdname tagged_missing
#' @export
is_tagged_missing <- function(x, tag = NULL) {
    .Call(C_dtaparser_is_tagged_missing, x, tag)
}
