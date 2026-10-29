#' Write a data frame as a Stata .dta file (release 118)
#'
#' Numeric columns keep their `storage` attribute when they have one;
#' otherwise integers are written as long, doubles as double and logicals
#' as byte. Character columns are strN, or strL beyond 2045 bytes; `NA`
#' is written as `""`, since Stata strings have no missing value. Strings
#' must be UTF-8 (see [enc2utf8()]). Value
#' labels come from each column's `labels` attribute, under its
#' `label_set` name (or the column's name); `.a` to `.z` may be labelled.
#' A value that does not fit its storage type is an error.
#'
#' The data frame's attributes give the file's metadata, as [read_dta()]
#' leaves them: `label`, `notes`, `characteristics` (a data frame with
#' character columns `variable`, `name`, `value`; those of variables not
#' in `data` are dropped), `sort_order` (column names; only its leading
#' keys found in `data` are written) and `timestamp`, written as given.
#' Without a `timestamp` attribute the file is stamped with the current
#' time, so a file read without a timestamp comes back with one.
#'
#' @param data A data frame, such as one `read_dta` returned.
#' @param file Path to write.
#' @return `file`, invisibly.
#' @examples
#' df <- dibble(
#'   id = 1:3,
#'   smoker = dta_num(c(1, 0, .d), storage = "byte", label = "Smokes daily",
#'                    labels = c(No = 0, Yes = 1, "Don't know" = .d))
#' )
#' attr(df, "label") <- "Smoking"
#' path <- tempfile(fileext = ".dta")
#' save_dta(df, path)
#' val_label(read_dta(path)$smoker, c(0, 1, .d))
#' @export
save_dta <- function(data, file) {
  stopifnot(is.data.frame(data))
  # Columns go to the writer as they are, without copies; it reads
  # doubles, integers, logicals and UTF-8 strings in place.
  columns <- lapply(data, function(x) {
    if (is.factor(x)) stop("save_dta: convert factors to character or numbers first")
    if (!is.character(x) && !is.numeric(x) && !is.logical(x)) {
      stop("save_dta: cannot write a column of class ", class(x)[[1]])
    }
    x
  })
  storage <- vapply(data, function(x) {
    if (is.character(x)) return("str")
    attr(x, "storage", exact = TRUE) %||%
      if (is.logical(x)) "byte" else if (is.integer(x)) "long" else "double"
  }, "")
  text_attr <- function(name) {
    vapply(data, function(x) enc2utf8(attr(x, name, exact = TRUE) %||% ""), "", USE.NAMES = FALSE)
  }
  label_sets <- vapply(names(data), function(n) {
    x <- data[[n]]
    if (is.null(attr(x, "labels", exact = TRUE)) || is.character(x)) "" else attr(x, "label_set", exact = TRUE) %||% n
  }, "", USE.NAMES = FALSE)
  sets <- list()
  for (i in seq_along(data)) {
    set <- label_sets[[i]]
    if (!nzchar(set)) next
    labels <- attr(data[[i]], "labels", exact = TRUE)
    entry <- list(name = enc2utf8(set), codes = as.double(unclass(labels)), texts = enc2utf8(names(labels)))
    if (!is.null(sets[[set]]) && !identical(sets[[set]], entry)) {
      stop("save_dta: columns sharing label set \"", set, "\" have different labels")
    }
    sets[[set]] <- entry
  }
  notes <- enc2utf8(attr(data, "notes", exact = TRUE) %||% character())
  chars <- kept_characteristics(attr(data, "characteristics", exact = TRUE), names(data))
  chars <- lapply(c("variable", "name", "value"), function(n) enc2utf8(as.character(chars[[n]])))
  keys <- kept_sort_order(attr(data, "sort_order", exact = TRUE), names(data))
  timestamp <- attr(data, "timestamp", exact = TRUE) %||% stata_timestamp(Sys.time())
  spec <- list(
    columns = unname(columns),
    names = enc2utf8(names(data)),
    storage = unname(storage),
    formats = text_attr("format"),
    labels = text_attr("label"),
    label_sets = label_sets,
    sets = unname(sets),
    data_label = enc2utf8(attr(data, "label", exact = TRUE) %||% ""),
    timestamp = enc2utf8(timestamp),
    notes = notes,
    characteristics = chars,
    sort_order = match(keys, names(data)) - 1L
  )
  .Call(C_dta_write, path.expand(file), spec)
  invisible(file)
}

# "28 Oct 2026 14:38", with English month names whatever the locale.
stata_timestamp <- function(time) {
  lt <- as.POSIXlt(time)
  sprintf("%02d %s %d %02d:%02d", lt$mday, month.abb[lt$mon + 1], lt$year + 1900, lt$hour, lt$min)
}
