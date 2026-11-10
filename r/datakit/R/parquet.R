#' Read a Parquet file into the types read_dta() returns
#'
#' `read_parquet()` reads a Parquet file as [dtaparser::read_dta()] reads
#' a `.dta` file: the same arguments where they mean the same, and the
#' same tibble back. arrow and nanoparquet also export a `read_parquet()`;
#' where either is attached after datakit, call `datakit::read_parquet()`.
#' An argument only arrow's function has, such as `as_data_frame`, then
#' fails as an unused argument.
#'
#' A file [save_parquet()] wrote keeps everything the data frame had:
#' value and variable labels, display formats, `.a` to `.z`, factor
#' levels, time zones, the data label and notes. They travel in the
#' file's `dta` metadata entry (see `docs/parquet.md`), which other tools
#' ignore. Files from other tools read as plain Parquet.
#'
#' @param file Path to a Parquet file, or a raw vector holding a whole
#'   file.
#' @param col_select Columns to read: a character vector of names, or a
#'   tidyselect expression such as `starts_with("v")`. All columns when
#'   `NULL`. Columns come back in the order selected. An unknown name is
#'   an error that lists the file's columns.
#' @param skip Rows to skip at the start.
#' @param n_max The most rows to read; `Inf` for all. Only the row groups,
#'   and within them the pages, that hold the rows wanted are read.
#' @param factors Whether columns with value labels become factors, as in
#'   [dtaparser::read_dta()]. A factor cannot hold `.a` to `.z`, so the
#'   default keeps the numbers. A categorical holding `.a` to `.z` stays a
#'   labelled double either way.
#' @param int64 How to return 64-bit integer columns, signed or not, and
#'   unsigned 32-bit ones: `"double"` (the default; a value a double cannot
#'   hold exactly is an error naming the column and row), `"integer64"`
#'   (bit64's class, every value exact; an unsigned value of 2^63 or more
#'   is an error) or `"character"`, every digit kept.
#' @param decimal How to return DECIMAL columns: `"double"` (the default),
#'   the nearest double to each value, where a value with more than 15
#'   significant digits is an error naming the column and row; or
#'   `"character"`, every digit kept.
#' @param timestamps What to do with nanosecond timestamps that are not a
#'   whole number of microseconds: `"error"` (the default) or
#'   `"truncate"`, which drops the nanoseconds below a microsecond.
#' @param nested What to do with nested columns (lists, maps, groups),
#'   which are not read: `"error"` (the default, when `col_select` does not
#'   leave them out) or `"skip"`, which leaves them out.
#' @param warn_extended_missing Whether to warn when `factors = TRUE`
#'   turns `.a` to `.z` into plain `NA`.
#' @return A tibble, with the column types of [dtaparser::read_dta()]:
#'
#'   | Parquet | R |
#'   |---|---|
#'   | INT32 (INT(8), INT(16) or none), BOOLEAN | integer, logical |
#'   | unsigned 8 and 16 bits | integer |
#'   | INT64, unsigned 32 and 64 bits | double; see `int64` |
#'   | FLOAT, DOUBLE | double |
#'   | DECIMAL | double; see `decimal` |
#'   | DATE | `Date` |
#'   | TIMESTAMP, INT96 | `POSIXct`, in the zone the file names, else UTC |
#'   | TIME | `difftime` in seconds |
#'   | STRING, ENUM, JSON | character |
#'   | BYTE_ARRAY, FIXED_LEN_BYTE_ARRAY, UUID | a list of raw vectors (`NULL` for null) |
#'   | a categorical `save_parquet()` wrote | factor, ordered if it was |
#'   | a categorical holding `.a` to `.z` (DOUBLE level numbers, which TypeScript's datakit wrote) | [`dtaparser_labelled`][dtaparser::with_labels] double, whatever `factors` says |
#'   | a dictionary of strings in `ARROW:schema` (an arrow factor, a pandas `category`, a polars `Categorical`) | factor, unordered |
#'
#'   Every missing value is `NA`. In doubles `.a` to `.z` are tagged NAs
#'   that keep their letter ([dtaparser::na_tag()]), as `read_dta()` keeps
#'   them; a double NaN stays NaN. A column with value labels is a
#'   [`dtaparser_labelled`][dtaparser::with_labels]; one written as a
#'   byte, int or long that holds `.a` to `.z` in the rows read is a
#'   double. Columns carry their variable label as attribute `label` and
#'   their display format as `format`; the tibble carries the data label
#'   as `label` and the notes as `notes`.
#'
#'   String columns come back packed, as `read_dta()`'s do: R makes each
#'   string when it is first used, and a column with few distinct values
#'   is kept as those values and a code per row.
#'
#'   A time zone comes from the `dta` entry, else from the `ARROW:schema`
#'   entry that arrow, pyarrow and polars write, else is UTC. An INT96
#'   timestamp, which has no zone, is in UTC, as pyarrow reads it.
#'
#'   A dictionary of strings in `ARROW:schema`, with no levels in the
#'   `dta` entry, is a factor whose levels are the distinct values of the
#'   rows read, in the order they first appear: another window of rows can
#'   give other levels, and reading every row gives them all; a level no
#'   row holds is not among them. `factors` does not apply to these. A
#'   dictionary of another type reads as its values' type.
#'
#'   A categorical holding `.a` to `.z` is written as DOUBLE level
#'   numbers, 1 for the first level, with tagged NaNs for the letters. A
#'   factor cannot hold the letters, so it reads as a labelled double: the
#'   numbers 1 to k, `.a` to `.z` as tagged NAs, `labels` from its value
#'   label set (the levels, and any labels on letters), and its attribute
#'   `label_set` the set's name. A value that is not a level number (a
#'   fraction, a number past the levels) is `NA`, with one warning per call
#'   naming the column and the first such row read. [save_parquet()]
#'   writes the column back as labelled numbers, not as a categorical.
#'
#'   Not read, each an error naming the column and its type: FLOAT16 and
#'   INTERVAL.
#' @seealso [read_parquet_info()] for the columns and their types without
#'   the data; [save_parquet()] to write.
#' @examples
#' path <- tempfile(fileext = ".parquet")
#' df <- data.frame(id = 1:3, smoker = dtaparser::with_labels(c(1, 0, dtaparser::tagged_na("d")),
#'   c(No = 0, Yes = 1, dtaparser::tagged_na(c("Don't know" = "d")))))
#' save_parquet(df, path)
#' back <- read_parquet(path)
#' dtaparser::val_label(back$smoker)   # "Yes" "No" "Don't know"
#' read_parquet(path, col_select = "id", skip = 1)
#' @export
read_parquet <- function(file, col_select = NULL, skip = 0, n_max = Inf,
                         factors = FALSE, int64 = "double", decimal = "double",
                         timestamps = "error", nested = "error",
                         warn_extended_missing = TRUE) {
  if (!is.numeric(skip) || length(skip) != 1 || is.na(skip) || skip < 0) stop("skip must be a number >= 0", call. = FALSE)
  if (!is.numeric(n_max) || length(n_max) != 1 || is.na(n_max) || n_max < 0) stop("n_max must be a number >= 0", call. = FALSE)
  if (!rlang::is_bool(factors)) stop("factors must be TRUE or FALSE", call. = FALSE)
  if (!rlang::is_bool(warn_extended_missing)) stop("warn_extended_missing must be TRUE or FALSE", call. = FALSE)
  int64 <- one_of(int64, c("double", "integer64", "character"), "int64")
  decimal <- one_of(decimal, c("double", "character"), "decimal")
  timestamps <- one_of(timestamps, c("error", "truncate"), "timestamps")
  nested <- one_of(nested, c("error", "skip"), "nested")
  if (int64 == "integer64") rlang::check_installed("bit64", "to read 64-bit integers as integer64")
  file <- parquet_source(file)
  cols <- parquet_selection(rlang::enquo(col_select), file, nested)
  options <- c(match(int64, c("double", "integer64", "character")),
               match(timestamps, c("error", "truncate")),
               match(nested, c("error", "skip")),
               match(decimal, c("double", "character"))) - 1L
  res <- .Call(C_dta_parquet_read, file, cols, floor(skip), floor(n_max), options)
  for (w in res$warnings) warning(w, call. = FALSE)
  values <- res$columns
  names(values) <- res$names
  if (factors) {
    lost <- character()
    for (i in seq_along(values)) {
      x <- values[[i]]
      if (!inherits(x, "dtaparser_labelled")) next
      # A categorical holding .a to .z stays a labelled double: a factor
      # would lose the letters.
      if (isTRUE(res$letter_levels[i])) next
      labels <- attr(x, "labels", exact = TRUE)
      if (!any(!is.na(labels))) next
      codes <- vctrs::vec_data(x)
      if (warn_extended_missing && any(!is.na(dtaparser::na_tag(as.double(codes))))) lost <- c(lost, names(values)[i])
      values[[i]] <- labelled_factor(codes, labels, attr(x, "label", exact = TRUE), res$integer[[i]])
    }
    if (length(lost)) warn_lost(lost)
  }
  out <- tibble::new_tibble(values, nrow = res$rows)
  attr(out, "label") <- res$label
  attr(out, "notes") <- if (length(res$notes)) res$notes
  out
}

#' Describe a Parquet file without reading its data
#'
#' Reads only the file's footer: its size, row groups, and for each
#' column the Parquet type, the R type [read_parquet()] gives it, and what
#' the `dta` metadata entry says about it.
#'
#' @param file Path to a Parquet file, or a raw vector holding a whole
#'   file.
#' @return A list:
#'
#'   - `rows`: the number of rows.
#'   - `row_groups`: a tibble with `rows`, `compressed_bytes` and
#'     `uncompressed_bytes` of each row group.
#'   - `created_by`: the writer the file names, or `NULL`.
#'   - `compression`: the codecs its column chunks use, such as `"zstd"`.
#'   - `label` and `notes`: the data label (or `NULL`) and the notes.
#'   - `columns`: a tibble with one row per column: `name`; `role`
#'     (`"data"`, or `"nested"` for a list, map or group, which is not
#'     read); `r_type`, the class `read_parquet()` returns with its default
#'     arguments (`NA` for a column it does not read); `physical_type` and
#'     `logical_type`, Parquet's; `label`, the variable label;
#'     `value_labels`, the name of its value label set; and `storage` and
#'     `logical`, the storage type (`"byte"`, `"int"`, `"long"`,
#'     `"float"`) or the date or time (`"date"`, `"timestamp"`) of a
#'     column written as DOUBLE because it holds `.a` to `.z`. `logical` is
#'     `"categorical"` for a categorical, whether written as text or, when
#'     it holds `.a` to `.z`, as DOUBLE level numbers.
#'   - `key_value`: a tibble of every key-value entry in the footer,
#'     `key` and `value` (as text, `NA` for an entry with no value): the
#'     `dta` profile, `ARROW:schema` and any other writer's entries.
#' @seealso [read_parquet()].
#' @examples
#' path <- tempfile(fileext = ".parquet")
#' save_parquet(data.frame(id = 1:3, day = as.Date("2024-01-01") + 0:2), path)
#' info <- read_parquet_info(path)
#' info$rows
#' info$columns[, c("name", "r_type", "physical_type", "logical_type")]
#' @export
read_parquet_info <- function(file) {
  info <- .Call(C_dta_parquet_info, parquet_source(file))
  for (w in info$warnings) warning(w, call. = FALSE)
  list(
    rows = info$rows,
    row_groups = tibble::new_tibble(info$row_groups, nrow = length(info$row_groups$rows)),
    created_by = info$created_by,
    compression = info$compression,
    label = info$label,
    notes = info$notes,
    columns = tibble::new_tibble(info$columns, nrow = length(info$columns$name)),
    key_value = key_value_table(info$key_value)
  )
}

# The footer's key-value entries, which a dtaparser built before they
# were added (with the same ABI number) does not return.
key_value_table <- function(kv) {
  if (is.null(kv)) {
    stop("datakit needs dtaparser built from the same release; reinstall dtaparser", call. = FALSE)
  }
  tibble::new_tibble(kv, nrow = length(kv$key))
}

#' Write a data frame as a Parquet file
#'
#' Writes what [dtaparser::save_dta()] writes, and with the same checks,
#' plus what a `.dta` file cannot hold: factors with their levels (ordered
#' or not), logicals, time zones, long text and binary data. The file is
#' plain Parquet that every Parquet reader opens; what Parquet has no
#' place for goes into one JSON entry of its metadata, under the key
#' `dta`, which [read_parquet()] reads back.
#'
#' **Round trip.** For a data frame `x` that [dtaparser::read_dta()]
#' returned, `read_parquet()` of the file gives a tibble `identical()` to
#' `x`.
#'
#' **Numbers.** Integers are INT32 and doubles DOUBLE; a `storage`
#' attribute (`"byte"`, `"int"`, `"long"`, `"float"`, `"double"`), as
#' dtatools' columns have, writes that type instead, and a value it cannot
#' hold is an error. `NA` is a null. `.a` to `.z` ([dtaparser::tagged_na()])
#' are written as tagged NaNs, the bits R holds them in, so a column that
#' holds any is DOUBLE; other tools read them as NaN, and arrow and
#' nanoparquet as tagged NAs. `missing_letters = FALSE` writes them as
#' nulls instead, losing the letters. NaN is written as NaN.
#'
#' **Value labels.** A column's `labels` attribute, as a
#' [`dtaparser_labelled`][dtaparser::with_labels] or haven_labelled
#' column has, is written as a value label set named by its `label_set`
#' attribute or else the column's name. Columns sharing a set must have
#' the same labels.
#'
#' **Dates and times.** A `Date` is a DATE; a `POSIXct` a TIMESTAMP in
#' microseconds, adjusted to UTC, with its `tzone` kept. A `Date` with
#' fractions of a day, and a `POSIXct` whose seconds no whole number of
#' microseconds gives back exactly, are written as DOUBLE days or seconds
#' since 1970, so that they read back unchanged; other tools then see
#' numbers.
#'
#' **Factors** are written dictionary-encoded, every level in order in
#' every row group, so arrow, pyarrow and polars read them as factors and
#' categoricals too. **Logicals** are BOOLEAN. **Character** columns are
#' text of any length (strings must be UTF-8; see [enc2utf8()]). **A list
#' of raw vectors** (or `NULL`) is binary. bit64's **integer64** is INT64.
#' Any other column type (another list, a nested data frame, complex
#' numbers, `POSIXlt`, `difftime`) is an error naming the column.
#'
#' **Metadata.** A column's `label` attribute is its variable label and
#' its `format` its display format. The data frame's attributes give the
#' rest: `label`, `notes`, `characteristics` (a data frame with character
#' columns `variable`, `name`, `value`) and `sort_order` (column names), as
#' for `save_dta()`.
#'
#' @param data A data frame, such as one `read_dta()` or `read_parquet()`
#'   returned.
#' @param file Path to write.
#' @param compression The codec: `"snappy"` (the default), `"zstd"`,
#'   `"gzip"`, `"lz4_raw"` or `"none"`. Other tools read snappy files
#'   faster, and zstd made survey files only about a sixth smaller;
#'   `docs/parquet.md` has the measurements.
#' @param compression_level The codec's level: 1 to 22 for zstd (3 by
#'   default), 0 to 10 for gzip (6). `NULL` for the default.
#' @param row_group_size Rows per row group. `NULL` (the default) puts as
#'   many rows in each as fit in about 1 GiB, at most 262,144.
#' @param missing_letters Whether to keep `.a` to `.z` as tagged NaNs
#'   (`TRUE`) or write them as nulls (`FALSE`), for files meant for SQL
#'   engines and polars, which count NaN as a value.
#' @return `data`, invisibly.
#' @seealso [read_parquet()].
#' @examples
#' df <- data.frame(
#'   id = 1:3,
#'   smoker = dtaparser::with_labels(c(1, 0, dtaparser::tagged_na("d")),
#'                                   c(No = 0, Yes = 1, dtaparser::tagged_na(c("Don't know" = "d"))),
#'                                   label = "Smokes daily"),
#'   region = factor(c("North", "South", "North"), levels = c("North", "South", "West"))
#' )
#' attr(df, "label") <- "Smoking"
#' path <- tempfile(fileext = ".parquet")
#' save_parquet(df, path)
#' back <- read_parquet(path)
#' levels(back$region)   # "North" "South" "West"
#' @export
save_parquet <- function(data, file, compression = "snappy", compression_level = NULL, row_group_size = NULL,
                         missing_letters = TRUE) {
  if (!is.data.frame(data)) stop("data must be a data frame", call. = FALSE)
  check_parquet_options(file, compression, compression_level, row_group_size, missing_letters)
  names <- names(data)
  if (anyDuplicated(names)) stop("save_parquet: two columns are named \"", names[anyDuplicated(names)], "\"", call. = FALSE)
  cols <- Map(parquet_column, data, names)
  # Label sets by name, in a hashed environment: a wide file has thousands.
  sets <- new.env(hash = TRUE, parent = emptyenv(), size = length(cols))
  set_names <- character(length(cols))
  n_sets <- 0L
  for (c in cols) {
    if (!nzchar(c$label_set)) next
    entry <- list(name = enc2utf8(c$label_set), codes = as.double(unclass(c$labels)), texts = enc2utf8(names(c$labels)))
    seen <- sets[[c$label_set]]
    if (is.null(seen)) {
      assign(c$label_set, entry, envir = sets)
      n_sets <- n_sets + 1L
      set_names[n_sets] <- c$label_set
    } else if (!identical(seen, entry)) {
      stop("save_parquet: columns sharing label set \"", c$label_set, "\" have different labels", call. = FALSE)
    }
  }
  sets <- unname(mget(set_names[seq_len(n_sets)], envir = sets))
  field <- function(name) vapply(cols, function(c) c[[name]], "", USE.NAMES = FALSE)
  chars <- kept_characteristics(attr(data, "characteristics", exact = TRUE), names)
  spec <- list(
    columns = unname(lapply(cols, `[[`, "x")),
    names = enc2utf8(names),
    kinds = field("kind"),
    labels = enc2utf8(field("label")),
    formats = enc2utf8(field("format")),
    label_sets = enc2utf8(field("label_set")),
    sets = sets,
    tz = enc2utf8(vapply(cols, function(c) c$tz, NA_character_, USE.NAMES = FALSE)),
    levels = unname(lapply(cols, function(c) if (!is.null(c$levels)) enc2utf8(c$levels))),
    ordered = vapply(cols, function(c) c$ordered, NA, USE.NAMES = FALSE),
    label = enc2utf8(attr(data, "label", exact = TRUE) %||% ""),
    notes = enc2utf8(as.character(attr(data, "notes", exact = TRUE) %||% character())),
    characteristics = lapply(c("variable", "name", "value"), function(n) enc2utf8(as.character(chars[[n]]))),
    sort = enc2utf8(kept_sort_order(attr(data, "sort_order", exact = TRUE), names) %||% character())
  )
  options <- list(compression, if (!is.null(compression_level)) as.integer(compression_level),
                  if (!is.null(row_group_size)) as.double(row_group_size), missing_letters)
  .Call(C_dta_parquet_write, path.expand(file), spec, options)
  invisible(data)
}

check_parquet_options <- function(file, compression, compression_level, row_group_size, missing_letters) {
  if (!is.character(file) || length(file) != 1 || is.na(file)) stop("file must be a path", call. = FALSE)
  if (!is.character(compression) || length(compression) != 1 || is.na(compression)) {
    stop("compression must be one of \"snappy\", \"zstd\", \"gzip\", \"lz4_raw\" or \"none\"", call. = FALSE)
  }
  if (!is.null(compression_level) && !(is.numeric(compression_level) && length(compression_level) == 1 &&
                                       !is.na(compression_level) && compression_level == round(compression_level))) {
    stop("compression_level must be a whole number or NULL", call. = FALSE)
  }
  if (!is.null(row_group_size) && !(is.numeric(row_group_size) && length(row_group_size) == 1 &&
                                    !is.na(row_group_size) && row_group_size >= 1)) {
    stop("row_group_size must be a number of rows >= 1, or NULL", call. = FALSE)
  }
  if (!rlang::is_bool(missing_letters)) stop("missing_letters must be TRUE or FALSE", call. = FALSE)
}

# What the writer gets for column `x` named `name`: the vector, the kind
# lib.rs writes it as, its metadata and value labels with their set's
# name ("" for none). Like save_dta's written_column, nothing is copied.
parquet_column <- function(x, name) {
  storage <- attr(x, "storage", exact = TRUE)
  labels <- attr(x, "labels", exact = TRUE)
  out <- list(x = x, kind = NA_character_, label = attr(x, "label", exact = TRUE) %||% "",
              format = attr(x, "format", exact = TRUE) %||% "", tz = NA_character_, levels = NULL,
              ordered = FALSE)
  if (!is.character(out$label) || length(out$label) != 1) stop("save_parquet: the label of ", name, " must be a string", call. = FALSE)
  if (!is.character(out$format) || length(out$format) != 1) stop("save_parquet: the format of ", name, " must be a string", call. = FALSE)
  if (is.factor(x)) {
    out$kind <- "categorical"
    out$levels <- levels(x)
    out$ordered <- is.ordered(x)
    labels <- NULL
  } else if (inherits(x, "Date")) {
    out$kind <- "date"
    labels <- NULL
  } else if (inherits(x, "POSIXct")) {
    out$kind <- "timestamp"
    tz <- attr(x, "tzone", exact = TRUE)
    out$tz <- if (length(tz) && !is.na(tz[[1]])) tz[[1]] else NA_character_
    if (!is.double(x)) out$x <- as.double(x)
    labels <- NULL
  } else if (inherits(x, "integer64")) {
    out$kind <- "int64"
    labels <- NULL
  } else if (is.character(x)) {
    out$kind <- "text"
    labels <- NULL
  } else if (is.list(x) && (!is.object(x) || inherits(x, c("arrow_binary", "blob")))) {
    out$kind <- "binary"
    labels <- NULL
  } else if (is.logical(x) && !is.object(x)) {
    out$kind <- "bool"
  } else if (is.numeric(x) && (is.integer(x) || is.double(x))) {
    kinds <- c(byte = "int8", int = "int16", long = "int32", float = "float", double = "double")
    if (!is.null(storage) && !(is.character(storage) && length(storage) == 1 && storage %in% names(kinds))) {
      stop("save_parquet: ", name, " has storage type \"", paste(storage, collapse = " "),
           "\"; use \"byte\", \"int\", \"long\", \"float\" or \"double\"", call. = FALSE)
    }
    out$kind <- if (!is.null(storage)) kinds[[storage]] else if (is.integer(x)) "int32" else "double"
    if (is.integer(x) && out$kind %in% c("float", "double")) out$x <- as.double(x)
  } else {
    stop("save_parquet: cannot write ", name, ", a column of class ", class(x)[[1]], call. = FALSE)
  }
  out$label_set <- if (is.null(labels)) "" else attr(x, "label_set", exact = TRUE) %||% name
  out$labels <- labels
  out
}

# The file to read: a raw vector as it is, or the full path of a file
# that exists.
parquet_source <- function(file) {
  if (is.raw(file)) return(file)
  if (!is.character(file) || length(file) != 1 || is.na(file)) stop("file must be a path or a raw vector", call. = FALSE)
  normalizePath(file, mustWork = TRUE)
}

# NULL for every column, or the names selected. Names given as text go
# straight to the reader, which names the file's columns if one is
# unknown; any other selection is a tidyselect expression over the
# file's columns, read from its footer first.
parquet_selection <- function(select, file, nested) {
  if (rlang::quo_is_null(select)) return(NULL)
  expr <- rlang::quo_get_expr(select)
  if (is.character(expr)) return(unique(expr))
  if (rlang::is_call(expr, "c") && length(expr) > 1 && all(vapply(as.list(expr)[-1], is.character, NA))) {
    return(unique(unlist(as.list(expr)[-1])))
  }
  # A variable holding names, as in col_select = cols, goes through
  # all_of(), as read_dta() does, unless a column has the variable's
  # name: the reader checks that, so the footer is read once.
  if (rlang::is_symbol(expr)) {
    value <- tryCatch(rlang::eval_tidy(select), error = function(e) NULL)
    if (is.character(value) && !anyNA(value)) return(structure(unique(value), prefer = rlang::as_string(expr)))
  }
  info <- .Call(C_dta_parquet_info, file)
  names <- info$columns$name
  if (nested == "skip") names <- names[info$columns$role == "data"]
  picked <- tryCatch(
    tidyselect::eval_select(select, stats::setNames(as.list(seq_along(names)), names)),
    vctrs_error_subscript_oob = function(e) {
      shown <- paste0("\"", utils::head(names, 20), "\"", collapse = ", ")
      if (length(names) > 20) shown <- paste(shown, "and", length(names) - 20, "more")
      stop(conditionMessage(e), "\nThe file's columns are ", shown, ".", call. = FALSE)
    }
  )
  names[unname(picked)]
}

one_of <- function(x, choices, what) {
  if (!is.character(x) || length(x) != 1 || !(x %in% choices)) {
    stop(what, " must be ", paste0("\"", choices[-length(choices)], "\"", collapse = ", "), " or \"",
         choices[length(choices)], "\"", call. = FALSE)
  }
  x
}

# A factor from labelled codes, as dtaparser's read_dta(factors = TRUE)
# makes it: levels in order of value, labelled codes by their text and
# other values by as.character() (of the integer when `integer`, the
# column being a byte, int or long, though the codes are double when they
# hold .a to .z); repeated texts are one level. Missing values, labelled
# or not, are NA.
labelled_factor <- function(x, labels, label, integer) {
  labels <- labels[!is.na(labels)]
  values <- sort(unique(c(unname(labels), as.double(unique(x[!is.na(x)])))))
  text <- if (integer) as.character(as.integer(values)) else as.character(values)
  text[match(labels, values)] <- names(labels)
  levels <- unique(text)
  out <- match(text, levels)[match(x, values)]
  attr(out, "levels") <- levels
  class(out) <- "factor"
  attr(out, "label") <- label
  out
}

# One warning naming the columns whose factors lost .a to .z, of the
# class read_dta() uses.
warn_lost <- function(cols) {
  shown <- paste0("`", utils::head(cols, 5), "`")
  if (length(cols) > 5) shown <- c(shown, paste(length(cols) - 5, "more"))
  if (length(shown) > 1) shown <- paste(paste(shown[-length(shown)], collapse = ", "), "and", shown[length(shown)])
  rlang::warn(
    paste0("Extended missing values (.a to .z) in ", shown, " are plain NA in their factors; ",
           "read with factors = FALSE to keep them, or warn_extended_missing = FALSE to silence this."),
    class = "dtaparser_extended_missing"
  )
}

# As save_dta: the characteristics of the variables in `names`, and the
# dataset's other than notes; NULL if none.
kept_characteristics <- function(chars, names) {
  if (is.null(chars)) return(NULL)
  if (!is.data.frame(chars) || !all(c("variable", "name", "value") %in% names(chars))) {
    stop("characteristics must be a data frame with columns variable, name and value", call. = FALSE)
  }
  note <- chars$variable == "_dta" & grepl("^note[0-9]+$", chars$name)
  chars <- chars[chars$variable %in% c("_dta", names) & !note, c("variable", "name", "value"), drop = FALSE]
  if (nrow(chars)) chars
}

# As save_dta: the leading keys of a sort order that are among `names`.
kept_sort_order <- function(keys, names) {
  gone <- which(!(keys %in% names))
  if (length(gone)) keys <- keys[seq_len(gone[[1]] - 1)]
  if (length(keys)) keys
}
