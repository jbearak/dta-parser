#' Write a data frame as a Stata .dta file (release 118)
#'
#' Writes what [read_dta()] returns, and any other data frame, as release
#' 118. Only the columns' types and attributes say how; nothing depends
#' on the package that made them.
#'
#' **Numbers.** A numeric column keeps its `storage` attribute when it
#' has one (dtatools' `dta_num` columns do); otherwise integers are
#' written as long, doubles as double and logicals as byte. `NA` is
#' `.`, and a tagged NA ([tagged_na()]) is its letter, `.a` to `.z`. A
#' value that does not fit its storage type is an error.
#'
#' **Value labels.** A column's `labels` attribute, as a
#' [`dtaparser_labelled`][with_labels] column has, is written as a value
#' label set named by its `label_set` attribute or else the column's
#' name; `.a` to `.z` may be labelled. Columns sharing a set must have
#' the same labels.
#'
#' **Dates.** A `Date` is written as days since 1 January 1960 with
#' display format `%td`: as long when every day is a whole number, as
#' double otherwise. A `POSIXct` is written as milliseconds since
#' 1960 as double, with `%tc`. Stata's datetimes have no time zone, so
#' the clock time written is the UTC one, which is what `read_dta()`
#' gives back. A `format` or `storage` attribute takes the place of
#' either default.
#'
#' **Factors.** A factor is written as Stata's `encode` would make it:
#' codes 1 to k, stored as long, labelled with the levels in order. A
#' factor from `read_dta(factors = TRUE)` therefore comes back with
#' codes 1 to k, not the file's own codes, which that read did not
#' keep. To keep them, read with `factors = FALSE`, the default.
#'
#' Each factor also gets a characteristic, `dtaparser_factor`, saying
#' whether it was ordered and naming its label set (`"ordered size"`),
#' so that [read_dta()] reads it back as the same factor. Stata keeps
#' the characteristic, and other readers do not act on it. Markers already in
#' the `characteristics` attribute are dropped and written afresh, so a
#' column that is no longer a factor loses its marker.
#'
#' **Strings.** Character columns are strN, or strL beyond 2045 bytes;
#' `NA` is written as `""`, since Stata strings have no missing value.
#' Strings must be UTF-8 (see [enc2utf8()]).
#'
#' Other classes, such as `POSIXlt`, `difftime` or lists, are an error.
#'
#' **Metadata.** A column's `label` attribute is its variable label and
#' its `format` its display format. The data frame's attributes give the
#' file's: `label`, `notes`, `characteristics` (a data frame with
#' character columns `variable`, `name`, `value`; those of variables not
#' in `data` are dropped), `sort_order` (column names; only its leading
#' keys found in `data` are written) and `timestamp`, written as given.
#' Without a `timestamp` attribute the file is stamped with the current
#' time.
#'
#' @param data A data frame, such as one `read_dta()` returned.
#' @param file Path to write.
#' @return `file`, invisibly.
#' @seealso [read_dta()] to read it back.
#' @examples
#' df <- data.frame(
#'   id = 1:3,
#'   smoker = with_labels(c(1, 0, tagged_na("d")),
#'                        c(No = 0, Yes = 1, tagged_na(c("Don't know" = "d"))),
#'                        label = "Smokes daily"),
#'   seen = as.Date(c("2024-01-15", NA, "2024-03-02"))
#' )
#' attr(df, "label") <- "Smoking"
#' path <- tempfile(fileext = ".dta")
#' save_dta(df, path)
#' back <- read_dta(path)
#' val_label(back$smoker)  # "Yes" "No" "Don't know"
#' back$seen               # a Date again
#' @export
save_dta <- function(data, file) {
  stopifnot(is.data.frame(data))
  # Columns go to the writer as they are, without copies; it reads
  # doubles, integers, logicals and UTF-8 strings in place. Dates and
  # factors become the numbers Stata stores.
  cols <- Map(written_column, data, names(data))
  label_sets <- vapply(cols, function(c) c$label_set, "", USE.NAMES = FALSE)
  sets <- list()
  for (c in cols) {
    if (!nzchar(c$label_set)) next
    entry <- list(name = enc2utf8(c$label_set), codes = as.double(unclass(c$labels)), texts = enc2utf8(names(c$labels)))
    if (!is.null(sets[[c$label_set]]) && !identical(sets[[c$label_set]], entry)) {
      stop("save_dta: columns sharing label set \"", c$label_set, "\" have different labels")
    }
    sets[[c$label_set]] <- entry
  }
  text_attr <- function(name) {
    vapply(data, function(x) enc2utf8(attr(x, name, exact = TRUE) %||% ""), "", USE.NAMES = FALSE)
  }
  notes <- enc2utf8(attr(data, "notes", exact = TRUE) %||% character())
  chars <- with_factor_marks(kept_characteristics(attr(data, "characteristics", exact = TRUE), names(data)), data, cols)
  chars <- lapply(c("variable", "name", "value"), function(n) enc2utf8(as.character(chars[[n]])))
  keys <- kept_sort_order(attr(data, "sort_order", exact = TRUE), names(data))
  timestamp <- attr(data, "timestamp", exact = TRUE) %||% stata_timestamp(Sys.time())
  spec <- list(
    columns = unname(lapply(cols, `[[`, "x")),
    names = enc2utf8(names(data)),
    storage = vapply(cols, function(c) c$storage, "", USE.NAMES = FALSE),
    formats = vapply(cols, function(c) enc2utf8(c$format), "", USE.NAMES = FALSE),
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

# Days from 1960-01-01, Stata's origin, to 1970-01-01, R's.
DAYS_1960_TO_1970 <- 3653

# What the writer gets for column `x` named `name`: the values, storage
# type, display format and value labels with their set's name ("" for
# none).
written_column <- function(x, name) {
  storage <- attr(x, "storage", exact = TRUE)
  format <- attr(x, "format", exact = TRUE)
  labels <- attr(x, "labels", exact = TRUE)
  label_set <- attr(x, "label_set", exact = TRUE)
  if (is.factor(x)) {
    levels <- levels(x)
    x <- as.integer(x)
    labels <- stats::setNames(as.double(seq_along(levels)), levels)
    storage <- storage %||% "long"
  } else if (inherits(x, "Date")) {
    x <- as.double(x) + DAYS_1960_TO_1970
    known <- x[is.finite(x)]
    storage <- storage %||% if (all(known == trunc(known))) "long" else "double"
    format <- format %||% "%td"
    labels <- NULL
  } else if (inherits(x, "POSIXct")) {
    x <- (as.double(x) + DAYS_1960_TO_1970 * 86400) * 1000
    storage <- storage %||% "double"
    format <- format %||% "%tc"
    labels <- NULL
  } else if (is.character(x)) {
    storage <- "str"
    labels <- NULL
  } else if (is.numeric(x) || is.logical(x)) {
    storage <- storage %||% if (is.logical(x)) "byte" else if (is.integer(x)) "long" else "double"
  } else {
    stop("save_dta: cannot write ", name, ", a column of class ", class(x)[[1]])
  }
  label_set <- if (is.null(labels)) "" else label_set %||% name
  list(x = x, storage = storage, format = format %||% "", labels = labels, label_set = label_set)
}

# "28 Oct 2026 14:38", with English month names whatever the locale.
stata_timestamp <- function(time) {
  lt <- as.POSIXlt(time)
  sprintf("%02d %s %d %02d:%02d", lt$mday, month.abb[lt$mon + 1], lt$year + 1900, lt$hour, lt$min)
}

# The characteristics of the variables in `names`, and the dataset's
# other than notes (the `notes` attribute holds those); NULL if none.
kept_characteristics <- function(chars, names) {
  if (is.null(chars)) return(NULL)
  if (!is.data.frame(chars) || !all(c("variable", "name", "value") %in% names(chars))) {
    stop("characteristics must be a data frame with columns variable, name and value")
  }
  note <- chars$variable == "_dta" & grepl("^note[0-9]+$", chars$name)
  chars <- chars[chars$variable %in% c("_dta", names) & !note, c("variable", "name", "value"), drop = FALSE]
  rownames(chars) <- NULL
  if (nrow(chars)) chars
}

# The characteristic that marks a factor column (plan 0020); its value
# is "ordered" or "unordered", a space, and the column's label set.
FACTOR_MARK <- "dtaparser_factor"

# `chars` without factor marks, plus one for each factor in `data`.
with_factor_marks <- function(chars, data, cols) {
  if (!is.null(chars)) chars <- chars[chars$name != FACTOR_MARK, , drop = FALSE]
  factor <- vapply(data, is.factor, NA, USE.NAMES = FALSE)
  if (!any(factor)) return(chars)
  marks <- data.frame(
    variable = names(data)[factor],
    name = FACTOR_MARK,
    value = paste(ifelse(vapply(data[factor], is.ordered, NA), "ordered", "unordered"),
                  vapply(cols[factor], function(c) c$label_set, "", USE.NAMES = FALSE)),
    stringsAsFactors = FALSE
  )
  rbind(chars, marks)
}

# The leading keys of a sort order that are among `names`: data sorted
# by a, b, c is still sorted by a once b is dropped, but not by a then c.
# NULL if none.
kept_sort_order <- function(keys, names) {
  gone <- which(!(keys %in% names))
  if (length(gone)) keys <- keys[seq_len(gone[[1]] - 1)]
  if (length(keys)) keys
}
