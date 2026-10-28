#' Stata-typed tibbles
#'
#' A dibble is a tibble whose numeric columns are `dta_num`. `read_dta`
#' returns one. `dibble()` builds one from plain columns, following
#' `tibble()` for names and recycling, so fixtures need no classes:
#' doubles become `dta_num` with storage `double`, integers `long`,
#' logicals `byte`; `.a` to `.z` written inline (`c(1, NA, .d)`) keep
#' their codes; a factor becomes character; a `Date` becomes days since
#' 1960-01-01 with format `%td`; a haven `labelled` column keeps its
#' labels; character columns stay character. Any other class is an
#' error. `as_dibble()` converts a data frame by the same rules.
#' Assigning into a dibble stores values as given.
#'
#' @param ... Columns, as for `tibble::tibble()`.
#' @param x A data frame.
#' @return A dibble.
#' @export
dibble <- function(...) as_dibble(tibble::tibble(...))

#' @rdname dibble
#' @export
as_dibble <- function(x) {
  label <- attr(x, "label", exact = TRUE)
  notes <- attr(x, "notes", exact = TRUE)
  cols <- lapply(names(x), function(name) dta_column(x[[name]], name))
  names(cols) <- names(x)
  out <- tibble::new_tibble(cols, nrow = nrow(x), class = "dibble")
  attr(out, "label") <- label
  attr(out, "notes") <- notes
  out
}

dta_column <- function(x, name) {
  if (inherits(x, "dta_num") || is.character(x)) return(x)
  if (is.factor(x)) return(as.character(x))
  if (inherits(x, "Date")) {
    days <- as.numeric(x - as.Date("1960-01-01"))
    return(dta_num(days, label = attr(x, "label", exact = TRUE), storage = "long", format = "%td"))
  }
  if (inherits(x, "haven_labelled")) {
    return(dta_num(as.double(unclass(x)), labels = attr(x, "labels", exact = TRUE),
                   label = attr(x, "label", exact = TRUE)))
  }
  if (is.object(x)) stop("dibble: cannot make column ", name, " of class ", class(x)[[1]], " a Stata column")
  if (is.numeric(x) || is.logical(x)) return(dta_num(x))
  stop("dibble: cannot make column ", name, " a Stata column")
}
