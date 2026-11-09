#' Read a Stata .dta file into standard R types
#'
#' @param file Path to a `.dta` file.
#' @param col_select Columns to read: a character vector of names, or a
#'   tidyselect expression such as `tidyselect::all_of(names)`. All
#'   columns when `NULL`. Columns come back in the order selected.
#' @param encoding Text encoding of files older than release 118:
#'   `"windows-1252"` (the default), `"latin1"` or `"utf-8"`.
#' @param skip Rows to skip at the start.
#' @param n_max The most rows to read; `Inf` for all.
#' @param factors Whether columns with value labels become factors. A
#'   factor cannot hold `.a` to `.z`, so the default keeps the numbers.
#' @param dates Whether columns with date and datetime formats become
#'   `Date` and `POSIXct`.
#' @param warn_extended_missing Whether to warn when `factors = TRUE`
#'   turns `.a` to `.z` into plain `NA`.
#' @return A tibble. Byte, int and long columns are integers; float and
#'   double columns are doubles; string columns are character. Every
#'   missing value, `.` and `.a` to `.z` alike, is `NA`, so R's rules
#'   apply (`x > 5` is `NA` where `x` is missing). In doubles, `.a` to
#'   `.z` keep their letter as haven's tagged NAs do: [na_tag()] gives
#'   it back. An integer column holding any of them in the rows
#'   read is a double instead, so its type can depend on `skip` and
#'   `n_max`. Strings are as stored: Stata's missing string is `""`.
#'
#'   By default a column with value labels keeps its numbers as a
#'   [`dtaparser_labelled`][with_labels], whose `labels` attribute holds
#'   the codes, `.a` to `.z` among them, named by their text.
#'   [val_labels()] gives them and [val_label()] each value's text. The
#'   class keeps the labels through dplyr's `bind_rows()`, `case_when()`
#'   and `if_else()`; `as.numeric()` gives the plain codes.
#'
#'   With `factors = TRUE`, a column with value labels on any non-missing
#'   value is a factor whose
#'   levels are, in order of value, the labelled codes and the unlabelled
#'   values read (as `as.character()` of the integer or double); codes
#'   with the same text share a level, and missing values, labelled or
#'   not, are `NA`. A factor cannot keep `.a` to `.z`, so this warns
#'   when it loses them (see `warn_extended_missing`).
#'
#'   A column that [save_dta()] wrote from a factor is a factor again,
#'   ordered if it was, whatever `factors` says: its levels and their
#'   order come from its value labels. save_dta() marks such columns
#'   with a characteristic; a marked column is read as a factor only if
#'   the file still holds what that factor held: the same label set,
#'   a label on every non-missing value, no two codes with the same
#'   text, and no `.a` to `.z`. Otherwise (the file was changed in
#'   Stata, say) it is read as it would be unmarked, with one warning
#'   naming such columns.
#'
#'   A column that Python's or TypeScript's datakit wrote from a
#'   categorical carries another characteristic, `dtaparser_categorical`,
#'   and is read as such a factor too, ordered if it was, with every
#'   level of its value labels, when the rows read hold no `.a` to `.z`.
#'   A categorical may hold them, and a factor cannot, so when the rows
#'   read do, the column keeps its numbers as a `dtaparser_labelled`,
#'   letters and their labels included, without a warning, whatever
#'   `factors` says. So the same file can give a factor for some rows and
#'   numbers for others. The checks are a factor's, except that `.a` to
#'   `.z` and labels on them are allowed; the column must also be stored
#'   as numbers, not be read as a date (with `dates = TRUE`, its format
#'   is not one that makes a `Date` or `POSIXct`), not label `.`, and
#'   label only whole numbers within long's range. A column failing one
#'   of them, or carrying both characteristics, is read as unmarked
#'   (with `factors = TRUE`, as any labelled column), with one warning
#'   of class `dtaparser_stale_categorical` naming such columns.
#'
#'   A column whose labels are all on missing values keeps its numbers
#'   as a `dtaparser_labelled` either way (a date column stays a date
#'   and drops them).
#'
#'   With `dates = TRUE`, a column without such value labels whose format
#'   starts with `%td`, `%-td` or `%d` is a `Date`, and one whose format
#'   starts with `%tc` or `%-tc` is a `POSIXct` in UTC. `%tC`, which
#'   counts leap seconds, and the other `%t` formats stay numbers.
#'
#'   Columns carry their variable label as attribute `label`
#'   ([var_label()]); the tibble
#'   carries the dataset label as `label` and its notes as `notes`.
#'
#'   A numeric column whose display format says more than the default,
#'   such as `%9.2f`, or `%tdCCYY-NN-DD` on a `Date`, carries it as
#'   attribute `format`, which [save_dta()] writes back. Columns with a
#'   general format (`%9.0g` and the like, Stata's defaults), and dates
#'   with plain `%td` or `%tc`, have no such attribute, so they stay
#'   plain vectors; nor do factors and strings. The attribute stays
#'   through `filter()`, `arrange()`, joins and arithmetic. A labelled
#'   column keeps it everywhere, as it keeps its labels; other columns
#'   lose it in `bind_rows()`, `if_else()`, `case_when()` and base
#'   `x[i]`, and are then written with the default.
#'
#'   String columns come back packed: R makes each string when it is
#'   first used, so reading is fast and the first operation over every
#'   value of a column pays the cost instead. A column with few distinct
#'   values is kept as those values and a code per row.
#'
#'   haven differs in a few places: it reads every number as a double,
#'   gives labelled columns class `haven_labelled`,
#'   reads `%-td` and `%-tc` as numbers and `%tC` as `POSIXct`, and its
#'   `as_factor()` keeps labelled missing values as levels.
#' @export
read_dta <- function(file, col_select = NULL, encoding = NULL, skip = 0, n_max = Inf,
                     factors = FALSE, dates = TRUE, warn_extended_missing = TRUE) {
  if (!is.numeric(skip) || length(skip) != 1 || is.na(skip) || skip < 0) stop("skip must be a number >= 0")
  if (!is.numeric(n_max) || length(n_max) != 1 || is.na(n_max) || n_max < 0) stop("n_max must be a number >= 0")
  if (!rlang::is_bool(factors)) stop("factors must be TRUE or FALSE")
  if (!rlang::is_bool(dates)) stop("dates must be TRUE or FALSE")
  if (!rlang::is_bool(warn_extended_missing)) stop("warn_extended_missing must be TRUE or FALSE")
  file <- normalizePath(file, mustWork = TRUE)
  meta <- .Call(C_dta_meta, file, encoding)
  names <- meta$names
  cols <- seq_along(names)
  select <- rlang::enquo(col_select)
  if (!rlang::quo_is_null(select)) {
    # A variable holding names, as in col_select = cols, goes through
    # all_of(), which is what tidyselect asks for, unless a column has
    # the variable's name (tidyselect's precedence).
    expr <- rlang::quo_get_expr(select)
    if (rlang::is_symbol(expr) && !(rlang::as_string(expr) %in% names)) {
      value <- tryCatch(rlang::eval_tidy(select), error = function(e) NULL)
      if (is.character(value)) select <- rlang::quo(tidyselect::all_of(!!value))
    }
    cols <- unname(tidyselect::eval_select(select, stats::setNames(as.list(cols), names)))
  }
  mode <- if (dates) 2L else 0L
  values <- .Call(C_dta_read, file, as.integer(cols - 1L), floor(skip), floor(n_max), encoding, mode)
  names(values) <- names[cols]
  marks <- factor_marks(meta$characteristics, names(values))
  stale <- character()
  stale_categorical <- character()
  # Valid categoricals left as labelled numbers for their .a to .z, which
  # the factors = TRUE pass leaves alone.
  keep <- logical(length(values))
  for (i in which(!is.na(marks$factor) | !is.na(marks$categorical))) {
    x <- values[[i]]
    integer <- meta$storage[cols[i]] %in% c("byte", "int", "long")
    if (!is.na(marks$factor[i]) && !is.na(marks$categorical[i])) {
      stale_categorical <- c(stale_categorical, names(values)[i])
      next
    }
    categorical <- is.na(marks$factor[i])
    mark <- if (categorical) marks$categorical[i] else marks$factor[i]
    holds <- if (categorical) {
      marked_categorical_holds(x, mark, meta$label_sets[cols[i]], meta$storage[cols[i]], meta$formats[cols[i]], dates)
    } else {
      marked_factor_holds(x, mark, meta$label_sets[cols[i]])
    }
    if (!holds) {
      if (categorical) stale_categorical <- c(stale_categorical, names(values)[i])
      else stale <- c(stale, names(values)[i])
    } else if (categorical && .Call(C_dta_has_letters, x)) {
      keep[i] <- TRUE
    } else {
      x <- labelled_factor(x, integer)
      if (startsWith(mark, "ordered ")) class(x) <- c("ordered", "factor")
      values[[i]] <- x
    }
  }
  if (length(stale)) warn_stale(stale)
  if (length(stale_categorical)) warn_stale_categorical(stale_categorical)
  if (factors) {
    lost <- character()
    for (i in seq_along(values)) {
      if (keep[i] || is.factor(values[[i]]) || !any(!is.na(attr(values[[i]], "labels", exact = TRUE)))) next
      if (warn_extended_missing && .Call(C_dta_has_letters, values[[i]])) lost <- c(lost, names(values)[i])
      values[[i]] <- labelled_factor(values[[i]], meta$storage[cols[i]] %in% c("byte", "int", "long"))
    }
    if (length(lost)) warn_lost(lost)
  }
  # Labelled numbers, factors aside, as the class that keeps their labels.
  for (i in seq_along(values)) {
    x <- values[[i]]
    if (is.numeric(x) && !is.object(x) && !is.null(attr(x, "labels", exact = TRUE))) values[[i]] <- as_labelled_column(x)
  }
  rows <- min(max(meta$nobs - floor(skip), 0), floor(n_max))
  out <- tibble::new_tibble(values, nrow = rows)
  attr(out, "label") <- nonempty(meta$label)
  attr(out, "notes") <- if (length(meta$notes)) meta$notes
  out
}

# The markers of each of `names`: list(factor =, categorical =), the
# values of its `dtaparser_factor` (plan 0020) and `dtaparser_categorical`
# (plan 0023) characteristics, NA where it has none.
factor_marks <- function(chars, names) {
  mark_of <- function(name) {
    marks <- rep(NA_character_, length(names))
    if (is.null(chars) || !length(chars$name)) return(marks)
    mark <- chars$name == name & chars$variable %in% names
    marks[match(chars$variable[mark], names)] <- chars$value[mark]
    marks
  }
  list(factor = mark_of(FACTOR_MARK), categorical = mark_of(CATEGORICAL_MARK))
}

# Whether `x`, read from a column with label set `set` marked as a
# factor with `mark`, still holds what that factor held.
marked_factor_holds <- function(x, mark, set) {
  m <- regmatches(mark, regexec("^(ordered|unordered) (.+)$", mark))[[1]]
  labels <- attr(x, "labels", exact = TRUE)
  if (!length(m) || is.null(labels) || !identical(set, m[[3]])) return(FALSE)
  codes <- labels[!is.na(labels)]
  if (anyDuplicated(names(codes)) || .Call(C_dta_has_letters, x)) return(FALSE)
  all(x[!is.na(x)] %in% codes)
}

# Whether `x`, read from a column stored as `storage` with display format
# `format` and label set `set`, marked as a categorical with `mark`, still
# holds what that categorical held (plan 0023): numbers, not read as
# dates, whose set is the one marked, labels no `.`, gives each code a
# whole number within long's range and its own text, and labels every
# value read. Unlike a factor, it may hold .a to .z, labelled or not.
marked_categorical_holds <- function(x, mark, set, storage, format, dates) {
  m <- regmatches(mark, regexec("^(ordered|unordered) (.+)$", mark))[[1]]
  if (!length(m) || !identical(set, m[[3]])) return(FALSE)
  if (!(storage %in% c("byte", "int", "long", "float", "double"))) return(FALSE)
  if (dates && grepl("^%-?(td|d|tc)", format)) return(FALSE)
  labels <- attr(x, "labels", exact = TRUE)
  if (is.null(labels) || any(is.na(labels) & is.na(na_tag(unclass(labels))))) return(FALSE)
  codes <- unclass(labels)[!is.na(labels)]
  if (any(codes != trunc(codes) | codes < -2147483647 | codes > 2147483620)) return(FALSE)
  if (anyDuplicated(names(codes))) return(FALSE)
  all(x[!is.na(x)] %in% codes)
}

# One warning naming marked factor columns read as unmarked.
warn_stale <- function(cols) {
  rlang::warn(
    paste0("save_dta() wrote ", show_columns(cols), " as factors, but the file has changed since: ",
           "their label set changed, a value has no label or shares its text, or they hold .a to .z; ",
           "read as unmarked columns."),
    class = "dtaparser_stale_factor"
  )
}

# One warning naming marked categorical columns read as unmarked.
warn_stale_categorical <- function(cols) {
  rlang::warn(
    paste0("The file marks ", show_columns(cols), " as categoricals, but has changed since they were written: ",
           "their value label set changed, a value has no label, two codes share a text, ",
           "a code is not a whole number within long's range, `.` is labelled, a date format was given, ",
           "they are stored as text, or they have both markers; read as unmarked columns."),
    class = "dtaparser_stale_categorical"
  )
}

# `a`, `a` and `b`, or `a`, `b`, `c`, `d`, `e` and 2 more.
show_columns <- function(cols) {
  shown <- paste0("`", utils::head(cols, 5), "`")
  if (length(cols) > 5) shown <- c(shown, paste(length(cols) - 5, "more"))
  if (length(shown) > 1) shown <- paste(paste(shown[-length(shown)], collapse = ", "), "and", shown[length(shown)])
  shown
}

# One warning naming the columns whose factors lost .a to .z.
warn_lost <- function(cols) {
  rlang::warn(
    paste0("Extended missing values (.a to .z) in ", show_columns(cols), " are plain NA in their factors; ",
           "read with factors = FALSE to keep them, or warn_extended_missing = FALSE to silence this."),
    class = "dtaparser_extended_missing"
  )
}

# A factor from a labelled integer or double column: levels in order of
# value, labelled codes by their text and other values by
# as.character() (of the integer when `integer`, the file's storage
# being byte, int or long, though x is double when it held .a to .z);
# repeated texts are one level. Missing values, labelled or not, are NA.
labelled_factor <- function(x, integer) {
  labels <- attr(x, "labels", exact = TRUE)
  labels <- labels[!is.na(labels)]
  values <- sort(unique(c(unname(labels), as.double(unique(x[!is.na(x)])))))
  text <- if (integer) as.character(as.integer(values)) else as.character(values)
  text[match(labels, values)] <- names(labels)
  levels <- unique(text)
  out <- match(text, levels)[match(x, values)]
  attr(out, "levels") <- levels
  class(out) <- "factor"
  attr(out, "label") <- attr(x, "label", exact = TRUE)
  out
}

nonempty <- function(x) if (nzchar(x)) x
