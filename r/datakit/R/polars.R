# Parquet, .dta and fixed-width files into polars frames and back (plan
# 0025, stage 3), through dtaparser's Arrow streams: R builds no column:
# the rules are written as polars expressions.

# Stata's dates count from 1960, polars' from 1970.
DAYS_1960 <- 3653
MS_1960 <- DAYS_1960 * 86400000
UNIT_MS <- c(ms = 1, us = 1000, ns = 1e6)

# The characteristics that mark a column written from a categorical.
FACTOR_MARK <- "dtaparser_factor"
CATEGORICAL_MARK <- "dtaparser_categorical"

# The numbers a .dta long holds; a value label's code is one.
LONG_RANGE <- c(-2147483647, 2147483620)
INT_RANGE <- list(Int8 = c(-127, 100), Int16 = c(-32767, 32740), Int32 = c(-2147483647, 2147483620))

# ---------------------------------------------------------------- arguments

check_window <- function(skip, n_max) {
  if (!is.numeric(skip) || length(skip) != 1 || is.na(skip) || skip < 0) stop("skip must be a number >= 0", call. = FALSE)
  if (!is.numeric(n_max) || length(n_max) != 1 || is.na(n_max) || n_max < 0) stop("n_max must be a number >= 0", call. = FALSE)
}

check_bool <- function(x, what) {
  if (!rlang::is_bool(x)) stop(what, " must be TRUE or FALSE", call. = FALSE)
}

# Two nanoarrow streams for a read to fill: the frame and the letters.
new_streams <- function() {
  list(data = nanoarrow::nanoarrow_allocate_array_stream(), letters = nanoarrow::nanoarrow_allocate_array_stream())
}

# ---------------------------------------------------------------- reads

#' Read a Parquet or `.dta` file into a polars DataFrame
#'
#' `read_parquet_pl()` and `read_dta_pl()` read a file into a polars
#' DataFrame and a [`datakit_meta`][datakit_meta] beside it,
#' through dtaparser's Arrow streams. No R vector is built. [read_parquet()]
#' and [read_dta()] read into a tibble instead.
#'
#' **Types.** Parquet's types become polars' (INT64 and DECIMAL exactly;
#' a categorical an Enum). In a `.dta` file byte, int, long, float and
#' double become Int8, Int16, Int32, Float32 and Float64; strN and text
#' strLs String, binary strLs Binary. A `%td` column is a Date and a
#' `%tc` column a Datetime in milliseconds; `%tC` and the other `%t`
#' formats stay numbers, with their format in `meta`.
#'
#' **Missing values.** `.` is a null. With `letters = TRUE` (the
#' default) each column holding `.a` to `.z` in the rows read is Float64,
#' each letter a NaN tagged with it ([na_tag_pl()] reads them,
#' [tagged_na_pl()] makes one): an Int8, Int16, Int32 or Float32 column
#' is cast, its dtype kept in `meta$storage` so that a save gives it
#' back; a Date or Datetime becomes Stata's number (days, or
#' milliseconds, since 1960) with a `%td` or `%tc` format; a categorical
#' its level numbers from 1, labelled by its value label set. polars
#' counts a NaN as a value and makes every NaN equal: use [is_missing()]
#' where R would use `is.na()`, and [datakit_by_pl()] to group. With
#' `letters = FALSE` they are nulls, like `.`, and the column keeps its
#' dtype.
#'
#' **Categoricals in `.dta` files.** A column that `save_dta()` wrote
#' from a polars Enum or Categorical (marked by its
#' `dtaparser_categorical` characteristic) is an Enum again, of its value
#' labels in code order, unless it holds `.a` to `.z` in the rows read;
#' if the file changed since, so that the mark no longer fits, it is read
#' as an unmarked column, with a warning.
#'
#' **Lifetime.** The frame's buffers stay in dtaparser's memory, and
#' their release lives in dtaparser's library: do not unload dtaparser
#' while frames read from it exist. datakit imports dtaparser, so a
#' session does not unload it by itself.
#'
#' The polars functions need R 4.3 or later, and the polars and
#' nanoarrow packages. polars installs from R-multiverse:
#' `install.packages("polars", repos = "https://community.r-multiverse.org")`.
#'
#' @param file For `read_parquet_pl()`, the path to a Parquet file or a
#'   raw vector holding a whole file; for `read_dta_pl()`, the path to a
#'   `.dta` file (releases 104 to 119).
#' @param col_select Columns to read, as in [read_parquet()]: names, or
#'   a tidyselect expression. All when `NULL`.
#' @param skip,n_max Skip that many rows, then read at most `n_max`.
#' @param factors Make each labelled numeric column an Enum of its
#'   labels, as `read_parquet(factors = TRUE)` makes a factor. An Enum
#'   cannot hold `.a` to `.z`: in a column made one they are nulls, with a
#'   warning. A categorical stored with letters stays its level numbers.
#' @param letters Keep `.a` to `.z` as tagged NaNs (`TRUE`) or read them
#'   as nulls (`FALSE`).
#' @param timestamps `"error"` (the default) or `"truncate"`: for
#'   Parquet, a date held as days with a fraction, or a timestamp held as
#'   seconds that no whole number of microseconds gives back; for
#'   `.dta`, a `%td` value with a fraction of a day or a `%tc` value with
#'   a fraction of a millisecond. An error names the column and row.
#' @param nested `"error"` (the default) or `"skip"`, for Parquet files
#'   with list, map or struct columns, which are not read.
#' @param encoding For text in `.dta` files before release 118:
#'   `"windows-1252"` (when `NULL`), `"latin1"` or `"utf-8"`.
#' @return `list(df, meta)`: `df` a polars DataFrame, `meta` a
#'   `datakit_meta`.
#' @seealso [save_parquet()] and [save_dta()], which take the frame and
#'   its `meta` back; [read_fixed_width_pl()].
#' @examples
#' if (requireNamespace("polars", quietly = TRUE) && requireNamespace("nanoarrow", quietly = TRUE) &&
#'     getRversion() >= "4.3") {
#'   path <- tempfile(fileext = ".parquet")
#'   save_parquet(data.frame(id = 1:3, x = c(1, NA, tagged_na("a"))), path)
#'   res <- read_parquet_pl(path)
#'   res$df$select(polars::pl$col("x"), na_tag_pl("x")$alias("letter"), is_na(polars::pl$col("x"))$alias("na"))
#' }
#' @export
read_parquet_pl <- function(file, col_select = NULL, skip = 0, n_max = Inf, factors = FALSE, letters = TRUE,
                            timestamps = "error", nested = "error") {
  check_polars("read_parquet_pl")
  check_window(skip, n_max)
  check_bool(factors, "factors")
  check_bool(letters, "letters")
  timestamps <- one_of(timestamps, c("error", "truncate"), "timestamps")
  nested <- one_of(nested, c("error", "skip"), "nested")
  file <- parquet_source(file)
  # A variable holding names keeps its name as the attribute "prefer":
  # the reader picks the column of that name if the file has one, so the
  # footer is read once, there.
  cols <- parquet_selection(rlang::enquo(col_select), file, nested)
  prefer <- attr(cols, "prefer", exact = TRUE)
  if (!is.null(cols)) cols <- structure(enc2utf8(as.character(cols)), prefer = if (!is.null(prefer)) enc2utf8(prefer))
  s <- new_streams()
  m <- .Call(C_dta_parquet_read_arrow, file, cols, floor(skip), floor(n_max), c(nested, timestamps), s$data,
             s$letters)
  # A dtaparser built before it read "prefer" (with the same ABI number)
  # has read the names, whatever the file's columns are.
  if (!is.null(prefer) && !isTRUE(attr(m, "prefer", exact = TRUE))) {
    stop("datakit needs dtaparser built from the same release; reinstall dtaparser", call. = FALSE)
  }
  finish_pl(s, m, factors = factors, letters = letters)
}

#' @rdname read_parquet_pl
#' @export
read_dta_pl <- function(file, col_select = NULL, skip = 0, n_max = Inf, factors = FALSE, letters = TRUE,
                        encoding = NULL, timestamps = "error") {
  check_polars("read_dta_pl")
  check_window(skip, n_max)
  check_bool(factors, "factors")
  check_bool(letters, "letters")
  timestamps <- one_of(timestamps, c("error", "truncate"), "timestamps")
  if (!is.character(file) || length(file) != 1 || is.na(file)) stop("file must be a path", call. = FALSE)
  file <- normalizePath(file, mustWork = TRUE)
  cols <- dta_selection(rlang::enquo(col_select), file, encoding)
  s <- new_streams()
  m <- .Call(C_dta_dta_read_arrow, file, if (!is.null(cols)) enc2utf8(cols), floor(skip), floor(n_max), encoding,
             timestamps, s$data, s$letters)
  finish_pl(s, m, factors = factors, letters = letters, markers = TRUE)
}

# NULL for every column, or the names selected, of a .dta file: names
# as given, anything else through tidyselect over the file's names.
dta_selection <- function(select, file, encoding) {
  if (rlang::quo_is_null(select)) return(NULL)
  expr <- rlang::quo_get_expr(select)
  if (is.character(expr)) return(unique(expr))
  if (rlang::is_call(expr, "c") && length(expr) > 1 && all(vapply(as.list(expr)[-1], is.character, NA))) {
    return(unique(unlist(as.list(expr)[-1])))
  }
  names <- dtaparser::read_meta(file, encoding)$variables$name
  if (rlang::is_symbol(expr) && !(rlang::as_string(expr) %in% names)) {
    value <- tryCatch(rlang::eval_tidy(select), error = function(e) NULL)
    if (is.character(value) && !anyNA(value)) select <- rlang::quo(tidyselect::all_of(!!value))
  }
  names[unname(tidyselect::eval_select(select, stats::setNames(as.list(seq_along(names)), names)))]
}

#' Read a fixed-width text file through its SAS setup file into polars
#'
#' As [read_fixed_width()], into a polars DataFrame and its
#' [`datakit_meta`][datakit_meta]: the native reader writes the data as a
#' release 118 `.dta` file in a temporary directory, which
#' [read_dta_pl()] reads with the selection, window, `factors` and
#' `letters`. No R vector is built.
#'
#' Release 118 limits what the file keeps: a variable label of up to 320
#' UTF-8 bytes is kept whole (200 ASCII characters, say), and a longer
#' one is cut at a character boundary, with a warning (200 `"é"` become
#' 160); a value label text may be 32,000 bytes. [read_fixed_width()],
#' on datparser, cuts nothing.
#'
#' Statements the reader does not run give one warning of class
#' `datakit_fixed_width_warning`, whose `messages` field lists them all.
#'
#' @inheritParams read_fixed_width
#' @inheritParams read_parquet_pl
#' @param recodes `"setup"`, `"tagged"` or `"none"`, as in
#'   [read_fixed_width()].
#' @return `list(df, meta)`, as [read_dta_pl()] returns.
#' @examples
#' if (requireNamespace("polars", quietly = TRUE) && requireNamespace("nanoarrow", quietly = TRUE) &&
#'     getRversion() >= "4.3") {
#'   dir <- tempfile()
#'   dir.create(dir)
#'   writeLines(c(
#'     "PROC FORMAT; VALUE kidsf 0='None' 98='DK' 99='Not ascertained';",
#'     "DATA; INPUT ID 1-3 KIDS 4-5;",
#'     "IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;",
#'     "FORMAT KIDS kidsf.;"
#'   ), file.path(dir, "survey.sas"))
#'   writeLines(c("001 2", "00298", "00399", "004 0"), file.path(dir, "survey.dat"))
#'   res <- read_fixed_width_pl(file.path(dir, "survey.dat"), file.path(dir, "survey.sas"), recodes = "tagged")
#'   res$df$select(na_tag_pl("KIDS"))
#'   res$meta$value_labels$kidsf
#' }
#' @export
read_fixed_width_pl <- function(file, setup, recodes = "setup", col_select = NULL, skip = 0, n_max = Inf,
                                commented_formats = TRUE, factors = FALSE, letters = TRUE) {
  check_polars("read_fixed_width_pl")
  recodes <- one_of(recodes, c("setup", "tagged", "none"), "recodes")
  check_bool(commented_formats, "commented_formats")
  check_window(skip, n_max)
  check_bool(factors, "factors")
  check_bool(letters, "letters")
  if (!is.character(file) || length(file) != 1 || is.na(file)) stop("file must be a path", call. = FALSE)
  if (!is.character(setup) || length(setup) < 1 || anyNA(setup)) stop("setup must be one or more paths", call. = FALSE)
  file <- normalizePath(file, mustWork = TRUE)
  setup <- normalizePath(setup, mustWork = TRUE)
  dir <- tempfile("datakit")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  out <- file.path(dir, "data.dta")
  messages <- .Call(C_dta_fixed_width_dta, file, setup, out, recodes, commented_formats)
  res <- read_dta_pl(out, col_select = {{ col_select }}, skip = skip, n_max = n_max, factors = factors,
                     letters = letters)
  if (length(messages)) warn_fixed_width_pl(messages)
  res
}

# One warning with the first few messages, each cut short; all of them
# in its `messages` field.
warn_fixed_width_pl <- function(messages) {
  shown <- utils::head(messages, 8)
  long <- nchar(shown) > 100
  shown[long] <- paste0(substr(shown[long], 1, 97), "...")
  lines <- stats::setNames(shown, rep("*", length(shown)))
  if (length(messages) > 8) lines <- c(lines, i = paste(length(messages) - 8, "more; see the warning's $messages"))
  rlang::warn(c("The setup file was read with warnings:", lines), class = "datakit_fixed_width_warning",
              messages = messages)
}

# The polars frame of a native read's stream, which is a struct of the
# columns. polars::as_polars_df() does this after inferring the struct's
# dtype in R, a field at a time (3.4 ms of 5.4 ms for 5,160 columns).
stream_frame <- function(stream) polars::as_polars_series(stream)$struct$unnest()

# `list(df, meta)` from a native read. With
# `letters`, each column holding .a to .z in the rows read is Float64
# with them as tagged NaNs; with `markers` (a .dta read) the columns
# marked dtaparser_categorical are Enums again unless they hold letters;
# `factors` makes labelled columns Enums, those holding letters too,
# their letters nulls, with one warning.
finish_pl <- function(s, m, factors, letters, markers = FALSE) {
  for (w in m$warnings) warning(w, call. = FALSE)
  df <- frame_of(stream_frame(s$data), m)
  meta <- meta_of(m)
  found <- character()
  ldf <- NULL
  if (letters && length(m$letter_columns)) {
    ldf <- stream_frame(s$letters)
    counts <- unlist(as.list(ldf$select(polars::pl$all()$null_count()), as_series = FALSE))
    found <- names(counts)[counts < ldf$height]
  }
  schema <- schema_of(df, found)
  enums <- found[vapply(found, function(n) inherits(schema[[n]], "polars_dtype_enum"), NA)]
  if (markers) {
    restored <- restore_categoricals(df, meta, skip = if (factors) character() else found)
    df <- restored$df
    meta <- restored$meta
    if (length(restored$stale)) warn_stale_pl(restored$stale)
  }
  if (factors) {
    made <- to_factors(df, meta)
    df <- made
    schema <- schema_of(df, found)
    lost <- found[!(found %in% enums) & vapply(found, function(n) inherits(schema[[n]], "polars_dtype_enum"), NA)]
    if (length(lost)) {
      shown <- paste0("\"", lost, "\"", collapse = ", ")
      warning(".a to .z in ", shown, " are nulls in ", if (length(lost) == 1) "its Enum" else "their Enums",
              "; read with factors = FALSE to keep them", call. = FALSE)
      found <- setdiff(found, lost)
    }
  }
  if (length(found)) {
    done <- with_letters(df, meta, ldf, found)
    df <- done$df
    meta <- done$meta
  }
  list(df = df, meta = meta)
}

warn_stale_pl <- function(stale) {
  one <- length(stale) == 1
  warning(if (one) "column " else "columns ", paste0("\"", stale, "\"", collapse = ", "), if (one) " was" else " were",
          " written as categoricals, but the file has changed since: their value label set changed, a value ",
          "has no label, two codes share a text, a code is not a whole number, `.` is labelled, a date format ",
          "was given, or a column has both markers; read as unmarked columns", call. = FALSE)
}

# The frame with the casts the read asks for: a categorical of the rows'
# values, and DECIMAL text as Decimal.
frame_of <- function(df, m) {
  pl <- polars::pl
  casts <- list()
  cols <- m$columns
  for (k in which(!is.na(cols$flag))) {
    flag <- cols$flag[[k]]
    name <- cols$name[[k]]
    if (flag == "categorical") {
      casts <- c(casts, list(pl$col(name)$cast(pl$Categorical())))
    } else if (startsWith(flag, "decimal(")) {
      ps <- as.integer(strsplit(substr(flag, 9, nchar(flag) - 1), ",", fixed = TRUE)[[1]])
      if (ps[[1]] <= 38) casts <- c(casts, list(decimal_of(df$get_column(name), ps[[1]], ps[[2]])))
    }
  }
  if (length(casts)) df$with_columns(!!!casts) else df
}

# A DECIMAL column read as text as Decimal(precision, scale); as
# Decimal(38, scale) when a value has more digits than its precision
# allows (as some writers make), with a warning; else text.
decimal_of <- function(text, precision, scale) {
  pl <- polars::pl
  out <- tryCatch(text$cast(pl$Decimal(precision, scale)), error = function(e) NULL)
  if (!is.null(out)) return(out)
  out <- tryCatch(text$cast(pl$Decimal(38, scale)), error = function(e) NULL)
  kept <- paste0("Decimal(38, ", scale, ")")
  if (is.null(out)) {
    out <- text
    kept <- "String"
  }
  warning("column \"", text$name, "\" holds values with more digits than its DECIMAL(", precision, ", ", scale,
          ") allows; read as ", kept, ", every digit kept", call. = FALSE)
  out
}

# The present values of a Series, as R doubles: no nulls, and no NaN
# (so no letter).
present_values <- function(s) {
  v <- s$drop_nulls()$unique()$cast(polars::pl$Float64)$to_r_vector()
  v[!is.na(v)]
}

# The dtypes of `names` only: df$schema makes an R object for every
# column, 90 ms on a frame of 5,000. By position, since select() reads
# a name like "^x$" as a regular expression.
schema_of <- function(df, names) {
  if (length(names) == 0) return(list())
  df$select(polars::pl$nth(match(names, df$columns) - 1L))$schema
}

is_numeric_dtype <- function(dt) inherits(dt, "polars_dtype_numeric") && !inherits(dt, "polars_dtype_decimal")

# The levels a dtaparser_categorical mark gives a column whose set is
# `set_name`, as list(codes, texts, ordered), or NULL when the file no
# longer holds what was written.
marked_levels <- function(mark, set_name, value_labels) {
  if (!is.character(mark) || length(mark) != 1) return(NULL)
  m <- regmatches(mark, regexec("^(ordered|unordered) ([\\s\\S]+)$", mark, perl = TRUE))[[1]]
  table <- if (!is.null(set_name)) value_labels[[set_name]]
  if (length(m) == 0 || is.null(set_name) || m[[3]] != set_name || is.null(table)) return(NULL)
  codes <- unname(table)
  if (any(is.na(codes) & is.na(dtaparser::na_tag(codes)))) return(NULL)  # `.` labelled
  keep <- !is.na(codes)
  codes <- codes[keep]
  texts <- names(table)[keep]
  o <- order(codes)
  codes <- codes[o]
  texts <- texts[o]
  if (any(codes != round(codes) | codes < LONG_RANGE[[1]] | codes > LONG_RANGE[[2]])) return(NULL)
  if (anyDuplicated(texts)) return(NULL)
  list(codes = as.double(codes), texts = texts, ordered = m[[2]] == "ordered")
}

# Each column marked dtaparser_categorical that still fits its mark an
# Enum of its set's texts in code order.
restore_categoricals <- function(df, meta, skip = character()) {
  pl <- polars::pl
  changes <- list()
  stale <- character()
  schema <- schema_of(df, intersect(df$columns, names(meta$characteristics)))
  for (name in df$columns) {
    chars <- meta$characteristics[[name]]
    if (is.null(chars) || !(CATEGORICAL_MARK %in% names(chars)) || name %in% skip) next
    s <- df$get_column(name)
    col <- meta$columns[[name]] %||% meta_column()
    levels <- NULL
    if (!(FACTOR_MARK %in% names(chars)) && is_numeric_dtype(schema[[name]])) {
      levels <- marked_levels(chars[[CATEGORICAL_MARK]], col$value_labels, meta$value_labels)
    }
    if (!is.null(levels) && !all(present_values(s) %in% levels$codes)) levels <- NULL
    if (is.null(levels)) {
      stale <- c(stale, name)
      next
    }
    changes <- c(changes, list(pl$col(name)$cast(pl$Float64)$replace_strict(
      levels$codes, levels$texts, default = pl$lit(NULL), return_dtype = pl$Enum(levels$texts))))
    col$ordered <- levels$ordered
    meta$columns[name] <- list(col)
    rest <- chars[names(chars) != CATEGORICAL_MARK]
    if (length(rest)) meta$characteristics[[name]] <- rest else meta$characteristics[[name]] <- NULL
  }
  list(df = if (length(changes)) df$with_columns(!!!changes) else df, meta = meta, stale = stale)
}

# Each labelled numeric column as an Enum, as read_parquet(factors =
# TRUE) makes a factor.
to_factors <- function(df, meta) {
  pl <- polars::pl
  changes <- list()
  labelled <- names(meta$columns)[vapply(meta$columns, function(c) !is.null(c$value_labels), NA)]
  schema <- schema_of(df, intersect(labelled, df$columns))
  for (name in names(meta$columns)) {
    set <- meta$columns[[name]]$value_labels
    if (!(name %in% df$columns) || is.null(set) || !is_numeric_dtype(schema[[name]])) next
    labels <- meta$value_labels[[set]]
    labels <- labels[!is.na(labels)]
    if (length(labels) == 0) next
    values <- sort(unique(c(present_values(df$get_column(name)), unname(labels))))
    integer <- inherits(schema[[name]], "polars_dtype_integer")
    text <- if (integer) sprintf("%.0f", values) else as.character(values)
    at <- match(values, unname(labels))
    text[!is.na(at)] <- names(labels)[at[!is.na(at)]]
    changes <- c(changes, list(pl$col(name)$cast(pl$Float64)$replace_strict(
      values, text, default = pl$lit(NULL), return_dtype = pl$Enum(unique(text)))))
  }
  if (length(changes)) df$with_columns(!!!changes) else df
}

# `df` with each column of `found` Float64, its letters (from `ldf`)
# tagged NaNs.
with_letters <- function(df, meta, ldf, found) {
  pl <- polars::pl
  schema <- schema_of(df, found)
  tmp <- unname(letter_temps(found, df$columns))
  df <- df$with_columns(!!!lapply(seq_along(found), function(i) ldf$get_column(found[[i]])$alias(tmp[[i]])))
  changes <- list()
  for (i in seq_along(found)) {
    name <- found[[i]]
    t <- schema[[name]]
    col <- pl$col(name)
    if (inherits(t, c("polars_dtype_int8", "polars_dtype_int16", "polars_dtype_int32", "polars_dtype_float32"))) {
      meta$storage[[name]] <- format(t)
      values <- col$cast(pl$Float64)
    } else if (inherits(t, "polars_dtype_float64")) {
      values <- col
    } else if (inherits(t, "polars_dtype_date")) {
      values <- col$cast(pl$Int32)$cast(pl$Float64) + DAYS_1960
      meta <- set_format(meta, name, "%td")
    } else if (inherits(t, "polars_dtype_datetime")) {
      unit <- t$time_unit
      values <- col$dt$epoch(unit)$cast(pl$Float64) / UNIT_MS[[unit]] + MS_1960
      meta <- set_format(meta, name, "%tc")
    } else if (inherits(t, "polars_dtype_enum")) {
      values <- col$to_physical()$cast(pl$Float64) + 1
      entry <- meta$columns[[name]] %||% meta_column()
      if (!is.null(entry$ordered)) {
        entry["ordered"] <- list(NULL)
        meta$columns[name] <- list(entry)
      }
    } else {
      next
    }
    changes <- c(changes, list(tag_expr(values, pl$col(tmp[[i]]))$alias(name)))
  }
  df <- if (length(changes)) df$with_columns(!!!changes) else df
  list(df = df$drop(tmp), meta = meta)
}

# Names for temporary letter columns of `names`, none of them in `taken`.
letter_temps <- function(names, taken) {
  prefix <- "__datakit_letters__"
  while (any(paste0(prefix, names) %in% taken)) prefix <- paste0("_", prefix)
  stats::setNames(paste0(prefix, names), names)
}

set_format <- function(meta, name, fmt) {
  entry <- meta$columns[[name]] %||% meta_column()
  if (!startsWith(entry$format %||% "", fmt)) {
    entry["format"] <- list(fmt)
    meta$columns[name] <- list(entry)
  }
  meta
}

# ---------------------------------------------------------------- saves

check_frame <- function(data, who) {
  if (inherits(data, "polars_lazy_frame")) {
    stop(who, "() takes a polars DataFrame, not a LazyFrame; call $collect() on it first", call. = FALSE)
  }
  if (!inherits(data, "polars_data_frame")) stop(who, "() takes a polars DataFrame, not ", class(data)[[1]], call. = FALSE)
}

# The dtype a column a read widened to Float64 is written as: `storage`
# when every value (its letters already null) fits it exactly, else
# Float64. NULL to leave it.
stored_dtype <- function(out, name, storage) {
  pl <- polars::pl
  if (is.null(storage) || is.na(storage)) return(NULL)
  x <- pl$col(name)$drop_nulls()
  if (storage == "Float32") {
    stats <- as.list(out$select(x$is_nan()$any()$alias("nan"),
                                (x$cast(pl$Float32)$cast(pl$Float64) == x)$all()$alias("exact")), as_series = FALSE)
    if (isTRUE(stats$nan) || !isTRUE(stats$exact)) return(NULL)
    return(pl$Float32)
  }
  range <- INT_RANGE[[storage]]
  if (is.null(range)) return(NULL)
  stats <- as.list(out$select(x$is_nan()$any()$alias("nan"), (x == x$round(0))$all()$alias("whole"),
                              x$is_infinite()$any()$alias("inf"), x$min()$alias("min"), x$max()$alias("max"),
                              x$len()$alias("n")), as_series = FALSE)
  if (isTRUE(stats$nan) || !isTRUE(stats$whole) || isTRUE(stats$inf)) return(NULL)
  if (stats$n > 0 && (stats$min < range[[1]] || stats$max > range[[2]])) return(NULL)
  switch(storage, Int8 = pl$Int8, Int16 = pl$Int16, Int32 = pl$Int32)
}

# The frame to write and what the native writer takes of meta:
# every tagged NaN null in the frame, its letters in
# `missing`; a column a read widened given its storage type back; the
# sort checked. Returns list(df, meta), meta in write_meta()'s form.
prepare_pl <- function(data, meta, missing_letters, who) {
  pl <- polars::pl
  check_frame(data, who)
  if (!is.null(meta) && !inherits(meta, "datakit_meta")) {
    stop("meta must be a datakit_meta (as a read gives) or NULL, not ", class(meta)[[1]], call. = FALSE)
  }
  check_bool(missing_letters, "missing_letters")
  storage <- meta$storage %||% character()
  f64 <- data$select(pl$col(pl$Float64))$columns
  tagged <- character()
  if (length(f64)) {
    any_letter <- lapply(f64, function(n) na_tag_expr(pl$col(n))$is_not_null()$any()$alias(n))
    has <- unlist(as.list(data$select(!!!any_letter), as_series = FALSE))
    tagged <- f64[has]
  }
  letters_df <- NULL
  if (length(tagged) && missing_letters) {
    letters_df <- data$select(!!!lapply(tagged, function(n) na_tag_expr(pl$col(n))$alias(n)))
  }
  out <- data
  if (length(tagged)) {
    out <- out$with_columns(!!!lapply(tagged, function(n) {
      pl$when(na_tag_expr(pl$col(n))$is_not_null())$then(pl$lit(NULL, pl$Float64))$otherwise(pl$col(n))$alias(n)
    }))
  }
  casts <- list()
  for (n in intersect(f64, names(storage))) {
    t <- stored_dtype(out, n, storage[[n]])
    if (!is.null(t)) casts <- c(casts, list(pl$col(n)$cast(t)))
  }
  if (length(casts)) out <- out$with_columns(!!!casts)
  if (is.null(meta)) meta <- new_datakit_meta()
  kept <- out$columns
  letter_names <- if (is.null(letters_df)) character() else letters_df$columns
  wm <- write_meta(
    meta,
    kept = kept,
    sort = checked_sort(out, meta$sort, letters_df),
    missing = stats::setNames(lapply(letter_names, function(n) nanoarrow::as_nanoarrow_array_stream(letters_df$select(n))),
                              letter_names)
  )
  list(df = out, meta = wm)
}

# What the native writers take: a list of label, timestamp, notes, sort,
# characteristics (variable, name, value), columns (name, label, format,
# value_labels, ordered), value_labels (names, codes, texts) and missing
# (names, streams), in that order (init.c's write_meta_arg).
write_meta <- function(meta, kept, sort, missing) {
  text <- function(x) enc2utf8(as.character(x))
  or_na <- function(x) if (is.null(x)) NA_character_ else text(x)
  chars <- meta$characteristics[names(meta$characteristics) %in% c(kept, "_dta")]
  vars <- rep(names(chars), lengths(chars))
  cols <- meta$columns[names(meta$columns) %in% kept]
  sets <- meta$value_labels
  list(
    label = if (!is.null(meta$label)) text(meta$label),
    timestamp = if (!is.null(meta$timestamp)) text(meta$timestamp),
    notes = text(meta$notes %||% character()),
    sort = text(sort),
    characteristics = list(text(vars), text(unlist(lapply(chars, names), use.names = FALSE) %||% character()),
                           text(unlist(chars, use.names = FALSE) %||% character())),
    columns = list(text(names(cols)),
                   vapply(cols, function(c) or_na(c$label), "", USE.NAMES = FALSE),
                   vapply(cols, function(c) or_na(c$format), "", USE.NAMES = FALSE),
                   vapply(cols, function(c) or_na(c$value_labels), "", USE.NAMES = FALSE),
                   vapply(cols, function(c) if (is.null(c$ordered)) NA else isTRUE(c$ordered), NA, USE.NAMES = FALSE)),
    value_labels = list(text(names(sets)), lapply(sets, function(s) as.double(unclass(s))) |> unname(),
                        lapply(sets, function(s) text(names(s) %||% character())) |> unname()),
    missing = list(text(names(missing)), unname(missing))
  )
}

# `sort` up to its first column not in `df`, if the rows are in that
# order as Stata orders them (values, then `.`, then .a to .z);
# otherwise character() with a warning.
checked_sort <- function(df, sort, letters_df) {
  pl <- polars::pl
  keys <- character()
  for (name in sort) {
    if (!(name %in% df$columns)) break
    keys <- c(keys, name)
  }
  if (length(keys) == 0 || df$height < 2) return(keys)
  schema <- schema_of(df, keys)
  frame <- df$select(!!!lapply(keys, function(k) pl$col(k)))
  lettered <- intersect(keys, if (is.null(letters_df)) character() else letters_df$columns)
  tmp <- letter_temps(lettered, keys)
  if (length(lettered)) {
    frame <- frame$with_columns(!!!lapply(lettered, function(k) letters_df$get_column(k)$alias(tmp[[k]])))
  }
  parts <- list()
  for (k in keys) {
    t <- schema[[k]]
    col <- pl$col(k)
    if (inherits(t, "polars_dtype_string")) {
      parts <- c(parts, list(col$fill_null("")))
      next
    }
    if (inherits(t, "polars_dtype_binary")) {
      parts <- c(parts, list(col$fill_null(pl$lit(raw(0)))))
      next
    }
    nulls <- col$is_null()
    tier <- if (k %in% lettered) {
      code <- pl$col(tmp[[k]])$to_physical()$cast(pl$UInt8) + 2
      pl$when(nulls$not())$then(0)$otherwise(code$fill_null(1))
    } else {
      nulls$cast(pl$UInt8)
    }
    value <- if (inherits(t, c("polars_dtype_enum", "polars_dtype_categorical"))) col$to_physical() else col
    parts <- c(parts, list(tier, value))
  }
  parts <- lapply(seq_along(parts), function(i) parts[[i]]$alias(paste0("p", i)))
  ok <- frame$select(
    (pl$arg_sort_by(!!!parts, maintain_order = TRUE)$cast(pl$Int64) == pl$int_range(0, pl$len())$cast(pl$Int64))$all()
  )$to_series()$to_r_vector()
  if (isTRUE(ok)) return(keys)
  warning("meta$sort (", paste(keys, collapse = ", "), ") does not describe the order of the frame's rows, so it ",
          "is not saved; sort with nulls last, then the letters, to keep it", call. = FALSE)
  character()
}
