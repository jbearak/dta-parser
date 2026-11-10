# datakit_meta: what a polars frame cannot hold, kept beside it
# (plan 0025, stage 3).

# A datakit_meta from its fields.
new_datakit_meta <- function(label = NULL, notes = character(), characteristics = list(), sort = character(),
                             timestamp = NULL, columns = list(), value_labels = list(), rows = 0,
                             storage = character()) {
  structure(list(label = label, notes = notes, characteristics = characteristics, sort = sort,
                 timestamp = timestamp, columns = columns, value_labels = value_labels, rows = rows,
                 storage = storage),
            class = "datakit_meta")
}

# One column's entry: label, format, value_labels (a set's name) and
# ordered, each NULL when it has none.
meta_column <- function(label = NULL, format = NULL, value_labels = NULL, ordered = NULL) {
  list(label = label, format = format, value_labels = value_labels, ordered = ordered)
}

# The datakit_meta of a native read's list.
# Each column's entry is meta_column() of its four fields, NA as NULL,
# built in C (src/meta.c).
meta_of <- function(m) {
  cols <- m$columns
  columns <- .Call(C_dta_meta_columns, as.character(cols$name), as.character(cols$label), as.character(cols$format),
                   as.character(cols$value_labels), as.logical(cols$ordered))
  new_datakit_meta(label = m$label, notes = m$notes, characteristics = characteristics_of(m$characteristics),
                   sort = m$sort, timestamp = m$timestamp, columns = columns, value_labels = m$value_labels,
                   rows = m$rows)
}

# list(variable, name, value) as a named list of named character
# vectors, a name given twice keeping its first place and its last text.
characteristics_of <- function(chars) {
  out <- list()
  for (i in seq_along(chars$variable)) {
    v <- chars$variable[[i]]
    entry <- out[[v]] %||% character()
    entry[[chars$name[[i]]]] <- chars$value[[i]]
    out[[v]] <- entry
  }
  out
}

#' The metadata beside a polars frame
#'
#' The polars readers ([read_parquet_pl()], [read_dta_pl()],
#' [read_fixed_width_pl()]) return `list(df, meta)`, where `meta` holds
#' what a polars frame cannot: a list of class `datakit_meta` with the
#' fields below. Change them
#' as any list's; [save_parquet()] and [save_dta()] take it back as
#' `meta =`. It does not follow polars operations: a renamed, dropped or
#' new column is yours to mirror.
#'
#' - `label`: the data label, or `NULL`.
#' - `notes`: the notes, a character vector.
#' - `characteristics`: a named list, by variable (or `"_dta"`), of named
#'   character vectors (`name = text`).
#' - `sort`: the columns the rows are sorted by. A save checks it against
#'   the rows and leaves it out, with a warning, if they are no longer in
#'   that order.
#' - `timestamp`: the file's time stamp, such as `"05 Nov 2026 10:00"`, or
#'   `NULL`.
#' - `columns`: a named list with one entry per column read, each a list
#'   of `label`, `format`, `value_labels` (the name of its set in
#'   `value_labels`) and `ordered` (for an Enum read from a file's
#'   categorical), each `NULL` when it has none.
#' - `value_labels`: a named list of value label sets, each a named
#'   double vector as [dtaparser::val_labels()] gives: the names are the
#'   texts, the values the codes, `NA` for `.` and tagged `NA`s
#'   ([dtaparser::tagged_na()]) for `.a` to `.z`.
#' - `rows`: the frame's height as read.
#' - `storage`: a named character vector, the polars dtype (`"Int8"`,
#'   `"Int16"`, `"Int32"` or `"Float32"`) each column had before a read
#'   made it Float64 to hold `.a` to `.z`; a save gives it back when the
#'   values still fit. `print()` leaves it out.
#'
#' `.a` to `.z` are not in `meta`: they are in the frame, as tagged NaNs
#' (see [tagged_na_pl()]).
#'
#' @param x A `datakit_meta`.
#' @param ... Unused.
#' @return `print()`: `x`, invisibly. `format()`: the lines it prints.
#' @aliases datakit_meta
#' @examples
#' if (requireNamespace("polars", quietly = TRUE) && requireNamespace("nanoarrow", quietly = TRUE) &&
#'     getRversion() >= "4.3") {
#'   path <- tempfile(fileext = ".parquet")
#'   d <- data.frame(x = with_labels(c(1, tagged_na("a")), c(Yes = 1, tagged_na(c(Refused = "a")))))
#'   save_parquet(d, path)
#'   read_parquet_pl(path)$meta
#' }
#' @export
format.datakit_meta <- function(x, ...) {
  text <- function(v) if (is.null(v)) "NULL" else encodeString(v, quote = "\"")
  vec <- function(v) if (length(v) == 0) "character(0)" else paste0("c(", paste(text(v), collapse = ", "), ")")
  code <- function(v) {
    tag <- dtaparser::na_tag(v)
    ifelse(!is.na(tag), paste0(".", tag), ifelse(is.na(v), ".", vapply(v, function(z) format(z, digits = 15), "")))
  }
  out <- c(
    "<datakit_meta>",
    paste0("label: ", text(x$label)),
    paste0("notes: ", vec(x$notes)),
    paste0("characteristics:", if (length(x$characteristics) == 0) " (none)"),
    unlist(lapply(names(x$characteristics), function(v) {
      ch <- x$characteristics[[v]]
      paste0("  ", v, ": ", paste0(names(ch), " = ", text(unname(ch)), collapse = ", "))
    })),
    paste0("sort: ", vec(x$sort)),
    paste0("timestamp: ", text(x$timestamp)),
    paste0("columns:", if (length(x$columns) == 0) " (none)"),
    unlist(lapply(names(x$columns), function(n) {
      c <- x$columns[[n]]
      paste0("  ", n, ": label = ", text(c$label), ", format = ", text(c$format), ", value_labels = ",
             text(c$value_labels), ", ordered = ", if (is.null(c$ordered)) "NULL" else c$ordered)
    })),
    paste0("value_labels:", if (length(x$value_labels) == 0) " (none)"),
    unlist(lapply(names(x$value_labels), function(s) {
      set <- x$value_labels[[s]]
      paste0("  ", s, ": ", paste0(code(unname(set)), " = ", text(names(set)), collapse = ", "))
    })),
    paste0("rows: ", format(x$rows, scientific = FALSE))
  )
  out
}

#' @rdname format.datakit_meta
#' @export
print.datakit_meta <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}
