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
#' @details When either operand is a `dta_num`, missing values behave as
#'   in Stata, and R's `NA` on the other side counts as `.`. Comparisons
#'   never give NA and put missing values above every number (`.` < `.a`
#'   < ... < `.z`). Arithmetic and math functions are R's on the numbers
#'   (so `round(x, 1)` rounds to one digit, `%%` is R's), but give `.` for
#'   any missing operand and for results Stata cannot hold (`NaN`, `Inf`),
#'   as a new `dta_num` without labels. In `&`, `|` and `!` a value is true
#'   when it is nonzero or missing. `sum()`, `mean()`, `max()` and the
#'   like keep R's rules. For `pmax()` and `pmin()`, use [dta_pmax()]
#'   and [dta_pmin()].
#' @examples
#' x <- dta_num(c(1, 5, NA, .d), labels = c(Low = 1, High = 5), label = "Score")
#' x > 3          # missing values are above every number, as in Stata
#' sort(x)        # 1 5 . .d
#' x + 1          # any missing operand gives .
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
  v <- v + 0  # -0 shows as 0
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
  plain <- function(e) if (inherits(e, "dta_num")) named_numbers(e) else e
  if (.Generic %in% c("&", "|", "!")) {
    # As in Stata, a value is true when nonzero or missing (R's NA too).
    truthy <- function(e) {
      v <- plain(e)
      if (!is.numeric(v) && !is.logical(v)) {
        stop("dtatools: ", .Generic, " needs numbers or logicals, not ", class(e)[[1]], call. = FALSE)
      }
      is.na(v) | v != 0
    }
    if (missing(e2)) return(!truthy(e1))
    return(get(.Generic)(truthy(e1), truthy(e2)))
  }
  # Arithmetic: R's operation on the numbers, but any missing operand,
  # and any result Stata cannot hold (NaN, Inf), is `.`. (R's own rules
  # give NA^0 == 1 and 1^NA == 1.)
  if (missing(e2)) return(stata_number(get(.Generic)(plain(e1))))
  a <- plain(e1)
  b <- plain(e2)
  r <- get(.Generic)(a, b)
  r[is.na(a) | is.na(b)] <- NA
  stata_number(r)
}

# R's function on the numbers (so round() is R's, to digits), with
# missing values as Stata's: `.` in, or NaN or Inf out, gives `.`. Stata
# gives `.` without a warning where R warns "NaNs produced".
#' @export
Math.dta_num <- function(x, ...) stata_number(suppressWarnings(get(.Generic)(named_numbers(x), ...)))

#' Parallel maxima and minima of Stata numbers
#'
#' R's `pmax()` and `pmin()` on the numbers, with missing values as in
#' Stata's arithmetic: every missing result is `.`, never `.a` to `.z`,
#' and the result is a new `dta_num` (storage double, no labels, label or
#' format), as from `x + y`.
#'
#' Base `pmax()` and `pmin()` given a `dta_num` run slower R code that
#' keeps a letter where every argument is missing (the last argument's,
#' so the result depends on their order) and copies the first argument's
#' labels onto the result.
#'
#' @param ... `dta_num` vectors, doubles, integers or logicals, recycled
#'   to a common length as `pmax()` recycles them. R's `NA` and `NaN` are `.`.
#' @param na.rm `FALSE`: a row with any missing value gives `.`. `TRUE`:
#'   missing values are skipped, and a row with no number gives `.`.
#' @return A `dta_num` vector, named as the first argument when it is as
#'   long as the result. An infinite result is `.`; an infinite argument
#'   that is not the result does not matter.
#' @examples
#' x <- dta_num(c(1, 5, NA, NA))
#' y <- dta_num(c(2, .a, .b, NA))
#' dta_pmax(x, y)                # 2 . . .
#' dta_pmax(x, y, na.rm = TRUE)  # 2 5 . .
#' dta_pmin(x, 3, na.rm = TRUE)  # 1 3 3 3
#' @export
dta_pmax <- function(..., na.rm = FALSE) parallel_extreme(base::pmax, "dta_pmax", list(...), na.rm)

#' @rdname dta_pmax
#' @export
dta_pmin <- function(..., na.rm = FALSE) parallel_extreme(base::pmin, "dta_pmin", list(...), na.rm)

# Base pmax or pmin on the plain numbers (its fast C code, which a
# classed argument would bypass), then every NA, NaN or Inf made `.`.
parallel_extreme <- function(f, name, args, na.rm) {
  if (!isTRUE(na.rm) && !isFALSE(na.rm)) stop(name, ": na.rm must be TRUE or FALSE", call. = FALSE)
  plain <- lapply(args, function(a) {
    if ((!is.numeric(a) && !is.logical(a) && !is.null(a)) ||
        (is.object(a) && !inherits(a, "dta_num")) || !is.null(dim(a))) {
      stop(name, ": arguments must be numbers, not ", class(a)[[1]], call. = FALSE)
    }
    named_numbers(a)
  })
  stata_number(do.call(f, c(plain, na.rm = na.rm)))
}

# The numbers with their names, so R's operations name results as usual.
named_numbers <- function(x) {
  v <- numbers(x)
  names(v) <- names(x)
  v
}

# A new dta_num from the result of arithmetic: every NA, NaN or Inf is `.`
# (an NA without a letter), as in Stata. No labels, label or format; the
# names R gave the result.
stata_number <- function(x) {
  nm <- names(x)
  x <- as.double(x)
  attributes(x) <- NULL
  x[!is.finite(x)] <- NA_real_
  out <- dta_num(x)
  names(out) <- nm
  out
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
