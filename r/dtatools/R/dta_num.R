# The dta_num class: a double vector whose `.` is NA_real_ and whose `.a`
# to `.z` are NAs carrying the letter in their payload (ADR 0003), with
# the attributes `label`, `format`, `storage`, `labels` and `label_set`.

DTA_ATTRIBUTES <- c("label", "format", "storage", "labels", "label_set")
MISSING_NAMES <- c(".", paste0(".", letters))

#' A Stata numeric column
#'
#' @param x Numbers; `NA` is `.`, and `.a` to `.z` (such as
#'   `dtatools::.d`) keep their codes.
#' @param labels Value labels: a named vector of codes, names the text.
#' @param label Variable label.
#' @param storage `"byte"`, `"int"`, `"long"`, `"float"` or `"double"`;
#'   by default `long` for integers, `byte` for logicals, else `double`.
#' @param format Display format, such as `"%9.0g"`.
#' @return A `dta_num` vector.
#' @export
dta_num <- function(x = double(), labels = NULL, label = NULL, storage = NULL, format = NULL) {
  if (!is.numeric(x) && !is.logical(x)) stop("dta_num: x must be numeric or logical")
  storage <- storage %||% attr(x, "storage", exact = TRUE) %||%
    if (is.logical(x)) "byte" else if (is.integer(x)) "long" else "double"
  out <- as.double(x)
  attributes(out) <- NULL
  attr(out, "label") <- label %||% attr(x, "label", exact = TRUE)
  attr(out, "format") <- format %||% attr(x, "format", exact = TRUE)
  attr(out, "storage") <- storage
  if (!is.null(labels)) {
    if (is.null(names(labels))) stop("dta_num: labels must be named")
    attr(out, "labels") <- stats::setNames(as.double(unclass(labels)), names(labels))
  }
  class(out) <- "dta_num"
  out
}

# Copy the dta_num attributes of `from` onto the plain vector `x`.
restore <- function(x, from) {
  for (a in DTA_ATTRIBUTES) attr(x, a) <- attr(from, a, exact = TRUE)
  class(x) <- "dta_num"
  x
}

# The numbers alone: a plain double, every missing code as an NA.
numbers <- function(x) {
  x <- unclass(x)
  attributes(x) <- NULL
  x
}

# Missing codes: 0 for a number, 1 for `.`, 2 to 27 for `.a` to `.z`.
# Works on any numeric vector, classed or not.
dta_codes <- function(x) .Call(C_dta_codes, x)

# Keys that compare and sort as Stata does: numbers as themselves, `.`
# to `.z` as 27 increasing doubles above every number Stata stores.
# With keep_na, `.` stays NA, as match() needs (see mtfrm.dta_num).
dta_keys <- function(x, keep_na = FALSE) .Call(C_dta_keys, x, keep_na)

# The text Stata shows for each value: 3, 1.5, ., .a.
code_text <- function(x) {
  v <- numbers(x)
  codes <- dta_codes(x)
  out <- ifelse(is.finite(v) & v == round(v) & abs(v) < 1e15, sprintf("%.0f", v), as.character(v))
  out[codes > 0] <- MISSING_NAMES[codes[codes > 0]]
  out
}

#' @export
Ops.dta_num <- function(e1, e2) {
  if (.Generic %in% c("==", "!=", "<", "<=", ">", ">=")) {
    if (is.character(e1) || is.character(e2)) {
      text <- function(e) if (inherits(e, "dta_num")) code_text(e) else e
      return(get(.Generic)(text(e1), text(e2)))
    }
    # Stata's comparisons: never NA; missing values above every number.
    return(get(.Generic)(dta_keys(e1), dta_keys(e2)))
  }
  # Arithmetic and logic work on the numbers; every missing code is NA.
  if (missing(e2)) return(get(.Generic)(numbers(e1)))
  plain <- function(e) if (inherits(e, "dta_num")) numbers(e) else e
  get(.Generic)(plain(e1), plain(e2))
}

#' @export
`[.dta_num` <- function(x, ...) restore(NextMethod(), x)

#' @export
`[[.dta_num` <- function(x, ...) restore(NextMethod(), x)

#' @export
rep.dta_num <- function(x, ...) restore(NextMethod(), x)

#' @export
c.dta_num <- function(..., recursive = FALSE, use.names = TRUE) {
  parts <- lapply(list(...), function(x) {
    names <- if (use.names) names(x)
    x <- unclass(x)
    attributes(x) <- NULL
    names(x) <- names
    x
  })
  restore(unlist(parts, use.names = use.names), ..1)
}

#' @export
duplicated.dta_num <- function(x, incomparables = FALSE, ...) duplicated(dta_keys(x))

#' @export
unique.dta_num <- function(x, incomparables = FALSE, ...) x[!duplicated(dta_keys(x))]

#' @export
mtfrm.dta_num <- function(x) dta_keys(x, keep_na = TRUE)

#' @export
xtfrm.dta_num <- function(x) dta_keys(x)

#' @export
as.character.dta_num <- function(x, ...) code_text(x)

#' @export
format.dta_num <- function(x, ...) {
  out <- format(numbers(x), ...)
  codes <- dta_codes(x)
  if (any(codes > 0)) out[codes > 0] <- format(MISSING_NAMES[codes[codes > 0]], width = max(nchar(out)))
  names(out) <- names(x)
  out
}

#' @export
print.dta_num <- function(x, ...) {
  label <- attr(x, "label", exact = TRUE)
  if (!is.null(label)) cat("<", label, ">\n", sep = "")
  print(format(x), quote = FALSE)
  invisible(x)
}

#' @export
as.data.frame.dta_num <- function(x, ...) as.data.frame.vector(x, ...)

# vctrs: slicing, combining and grouping keep the class, the attributes,
# and `.a` apart from `.b` (tibble's own `[` goes through these).

vec_proxy.dta_num <- function(x, ...) numbers(x)
vec_restore.dta_num <- function(x, to, ...) restore(x, to)
vec_proxy_equal.dta_num <- function(x, ...) dta_keys(x)
vec_proxy_compare.dta_num <- function(x, ...) dta_keys(x)
vec_proxy_order.dta_num <- function(x, ...) dta_keys(x)
vec_ptype_abbr.dta_num <- function(x, ...) "dta"
vec_ptype2.dta_num.dta_num <- function(x, y, ...) restore(double(), x)
vec_ptype2.dta_num.double <- function(x, y, ...) restore(double(), x)
vec_ptype2.double.dta_num <- function(x, y, ...) restore(double(), y)
vec_ptype2.dta_num.integer <- function(x, y, ...) restore(double(), x)
vec_ptype2.integer.dta_num <- function(x, y, ...) restore(double(), y)
vec_ptype2.dta_num.logical <- function(x, y, ...) restore(double(), x)
vec_ptype2.logical.dta_num <- function(x, y, ...) restore(double(), y)
vec_cast.dta_num.dta_num <- function(x, to, ...) restore(numbers(x), to)
vec_cast.dta_num.double <- function(x, to, ...) restore(numbers(x), to)
vec_cast.dta_num.integer <- function(x, to, ...) restore(as.double(x), to)
vec_cast.dta_num.logical <- function(x, to, ...) restore(as.double(x), to)
vec_cast.double.dta_num <- function(x, to, ...) numbers(x)
