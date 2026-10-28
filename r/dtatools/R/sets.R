#' Sets, groups and tabulations with Stata's missing values
#'
#' These treat `.`, `.a`, ..., `.z` as distinct values, as Stata does,
#' and accept `dta_num` vectors, plain doubles (such as `c(NA, .i)`),
#' logical `NA` and character vectors.
#'
#' - `dta_setequal(x, y)`, `dta_setdiff(x, y)`: set equality and
#'   difference.
#' - `dta_group_id(...)`: Stata's `egen group()`: numbers groups 1, 2,
#'   ... in sorted order. Rows with a missing value get NA unless
#'   `missing = TRUE`.
#' - `dta_group_tag(...)`: Stata's `egen tag()`: 1 on the first row of
#'   each group, else 0 (and 0 for rows with a missing value unless
#'   `missing = TRUE`).
#' - `tab(x)`: counts of each value in Stata's order, named as Stata
#'   writes the value (`1`, `.`, `.a`); missing values only with
#'   `missing = TRUE`.
#'
#' @param x,y Vectors.
#' @param ... Vectors of the same length, or one data frame.
#' @param missing Whether missing values count as values.
#' @name dta_sets
NULL

# What two values compare by: the text for character vectors, else keys.
set_keys <- function(x, character) if (character) as.character(x) else dta_keys(x)

#' @rdname dta_sets
#' @export
dta_setequal <- function(x, y) {
  character <- is.character(x) || is.character(y)
  setequal(set_keys(x, character), set_keys(y, character))
}

#' @rdname dta_sets
#' @export
dta_setdiff <- function(x, y) {
  character <- is.character(x) || is.character(y)
  kx <- set_keys(x, character)
  keep <- !(kx %in% set_keys(y, character)) & !duplicated(kx)
  x[keep]
}

group_columns <- function(...) {
  cols <- list(...)
  if (length(cols) == 1 && is.data.frame(cols[[1]])) cols <- as.list(cols[[1]])
  if (!length(cols)) stop("no columns to group by")
  cols
}

#' @rdname dta_sets
#' @export
dta_group_id <- function(..., missing = FALSE) {
  cols <- group_columns(...)
  keys <- lapply(cols, function(x) if (is.character(x)) x else dta_keys(x))
  n <- length(keys[[1]])
  if (n == 0) return(integer())
  ord <- do.call(order, c(unname(keys), method = "radix"))
  # A new group starts where any key changes, in sorted order.
  starts <- logical(n)
  starts[1] <- TRUE
  for (k in keys) {
    s <- k[ord]
    starts[-1] <- starts[-1] | s[-1] != s[-n]
  }
  id <- integer(n)
  id[ord] <- cumsum(starts)
  if (!missing) {
    has_missing <- Reduce(`|`, lapply(cols, is_missing))
    id[has_missing] <- NA
    id <- match(id, sort(unique(id[!has_missing])))
  }
  id
}

#' @rdname dta_sets
#' @export
dta_group_tag <- function(..., missing = FALSE) {
  id <- dta_group_id(..., missing = missing)
  tag <- as.integer(!duplicated(id))
  tag[is.na(id)] <- 0L
  tag
}

#' @rdname dta_sets
#' @export
tab <- function(x, missing = FALSE) {
  if (is.character(x)) {
    if (!missing) x <- x[x != ""]
    counts <- table(x)
    return(stats::setNames(as.integer(counts), names(counts)))
  }
  if (!missing) x <- x[dta_codes(x) == 0]
  keys <- dta_keys(x)
  values <- sort(unique(keys))
  first <- match(values, keys)
  stats::setNames(tabulate(match(keys, values), length(values)), code_text(x[first]))
}
