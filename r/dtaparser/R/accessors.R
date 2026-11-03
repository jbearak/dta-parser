#' Extended missing values `.a` to `.z`
#'
#' [read_dta()] keeps `.a` to `.z` in double columns as `NA` with the
#' letter stored in its bits (haven's tagged NA), so R sees `NA`.
#' `na_tag()` gives the letters back; `is_tagged_na()` says which values
#' are `.a` to `.z`, or one of the letters in `tag`. `tagged_na()` makes
#' them, for writing values and labels of your own.
#'
#' An integer, logical or factor gives `NA` (and `FALSE`) throughout: it
#' cannot hold a letter. A byte, int or long column is an integer only
#' when the rows read held no `.a` to `.z`, so the same code works on the
#' first rows of a file and on all of it. A `Date` or `POSIXct` column
#' keeps its letters.
#'
#' These are haven's names. haven's `na_tag()` and `is_tagged_na()` stop
#' on anything that is not a double, drop names, and take one `tag`;
#' these take several. haven's `tagged_na()` takes its letters as `...`,
#' drops names, and makes a tag from any character; this one takes one
#' vector, keeps its names, and takes only `"a"` to `"z"`, since `"ab"`,
#' `"A"` or `NA` is more likely a typo. With haven attached too, call
#' `dtaparser::tagged_na()` where the names matter, as in a labels
#' vector.
#'
#' @param x For `na_tag()` and `is_tagged_na()`, a double, integer,
#'   logical or factor vector. For `tagged_na()`, a character vector of
#'   letters `"a"` to `"z"`.
#' @param tag Letters `"a"` to `"z"`; `NULL` for any of them.
#' @return `na_tag()`: a character vector as long as `x`, keeping its
#'   names: the letter of each `.a` to `.z`, `NA` for numbers and for
#'   `.`. `is_tagged_na()`: a logical vector as long as `x`.
#'   `tagged_na()`: a double vector as long as `x`, keeping its names,
#'   each element `NA` with its letter.
#' @seealso [val_label()], to get the text of each missing value's label.
#' @examples
#' dir <- tempfile()
#' dir.create(dir)
#' writeLines(c(
#'   "PROC FORMAT; VALUE kidsf 98='DK' 99='Not ascertained';",
#'   "DATA; INPUT KIDS 1-2;",
#'   "IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;",
#'   "FORMAT KIDS kidsf.;"
#' ), file.path(dir, "survey.sas"))
#' writeLines(c(" 2", "98", "99", " 0"), file.path(dir, "survey.dat"))
#' df <- read_fixed_width(file.path(dir, "survey.dat"), file.path(dir, "survey.sas"),
#'                        recodes = "tagged")
#' df$KIDS                     # 2 NA NA 0
#' na_tag(df$KIDS)             # NA "a" "b" NA
#' is_tagged_na(df$KIDS, "b")  # FALSE FALSE TRUE FALSE
#'
#' x <- c(1, tagged_na("d"), NA)
#' na_tag(x)                   # NA "d" NA
#' is.na(x)                    # FALSE TRUE TRUE
#' tagged_na(c(Refused = "r", "Don't know" = "d"))  # Refused = NA, Don't know = NA
#' @export
na_tag <- function(x) {
  if (is.double(x)) {
    out <- .Call(C_dta_na_tag, x)
  } else if (is.integer(x) || is.logical(x) || is.factor(x)) {
    out <- rep(NA_character_, length(x))
  } else {
    stop("x must be a double, integer, logical or factor vector, not ", class(x)[1], call. = FALSE)
  }
  names(out) <- names(x)
  out
}

#' @rdname na_tag
#' @export
is_tagged_na <- function(x, tag = NULL) {
  tags <- na_tag(x)
  if (is.null(tag)) return(unname(!is.na(tags)))
  if (!is.character(tag) || !length(tag) || anyNA(tag) || !all(tag %in% letters)) {
    stop("tag must be letters \"a\" to \"z\"", call. = FALSE)
  }
  unname(tags %in% tag)
}

#' @rdname na_tag
#' @export
tagged_na <- function(x) {
  if (!is.character(x)) stop("x must be a character vector, not ", class(x)[1], call. = FALSE)
  bad <- !(x %in% letters)
  if (any(bad)) {
    stop("x must be lowercase letters \"a\" to \"z\", not ", encodeString(x[bad][1], quote = "\""), call. = FALSE)
  }
  # NA_real_'s eight bytes, little-endian, once per element; the letter
  # goes in byte 4, which is bits 32 to 39.
  bytes <- rep(as.raw(c(0xa2, 0x07, 0, 0, 0, 0, 0xf0, 0x7f)), length(x))
  bytes[seq(5, by = 8, length.out = length(x))] <- charToRaw(paste(x, collapse = ""))
  out <- readBin(bytes, "double", n = length(x), size = 8, endian = "little")
  names(out) <- names(x)
  out
}

#' Variable and value labels
#'
#' [read_dta()] keeps each column's variable label in its `label`
#' attribute and, for columns that are not factors, its value labels in
#' its `labels` attribute.
#'
#' `var_label(x)` gives the variable label. `val_labels(x)` gives the
#' value labels: the codes, named by their text, with `.a` to `.z` as
#' tagged NAs (see [na_tag()]). Given a data frame, both give a named list
#' with one element per column, `NULL` where it has none.
#'
#' `val_label(x, values)` gives the text of each of `values` under `x`'s
#' labels, `NA` where a value has none. Numbers match by value, and `.a`
#' to `.z` by letter, so `.a` never matches `.b`; `.` has no label. With
#' the default `values = x`, it gives each row's label, which says why
#' each missing value is missing.
#'
#' A factor, from `read_dta(factors = TRUE)`, has no value labels here:
#' its levels are the labels, and its integer codes are not the file's
#' codes. `val_label()` gives `NA` throughout for a column
#' without labels (a factor, a date, an unlabelled column), so
#' `lapply(df, val_label)` works on any tibble `read_dta()` returns.
#'
#' These are labelled's names. labelled's `val_labels()` and
#' `val_label()` read only class `haven_labelled`, so on dtaparser's
#' columns they give `NULL`; its `val_label(x, v)` looks up one value.
#' dtatools exports `val_labels()` and `val_label()` too, for its
#' `dta_num` columns; its `val_label()` needs `values`. With either
#' package attached as well, call these as `dtaparser::val_label()`.
#'
#' @param x A column, such as one `read_dta()` returned; for
#'   `var_label()` and `val_labels()`, also a data frame.
#' @param values Codes to look up: a double, integer or logical vector.
#' @return `var_label()`: a string or `NULL`. `val_labels()`: a named
#'   double or integer vector, or `NULL`. For a data frame, a named list
#'   of those. `val_label()`: a character vector as long as `values`.
#' @examples
#' dir <- tempfile()
#' dir.create(dir)
#' writeLines(c(
#'   "PROC FORMAT; VALUE kidsf 0='None' 98='DK' 99='Not ascertained';",
#'   "DATA; INPUT KIDS 1-2;",
#'   "LABEL KIDS = 'Number of children';",
#'   "IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;",
#'   "FORMAT KIDS kidsf.;"
#' ), file.path(dir, "survey.sas"))
#' writeLines(c(" 2", "98", "99", " 0"), file.path(dir, "survey.dat"))
#' df <- read_fixed_width(file.path(dir, "survey.dat"), file.path(dir, "survey.sas"),
#'                        recodes = "tagged")
#' var_label(df$KIDS)   # "Number of children"
#' val_labels(df$KIDS)  # None = 0, DK = NA, Not ascertained = NA
#' val_label(df$KIDS)   # NA "DK" "Not ascertained" "None"
#' @name val_labels
NULL

#' @rdname val_labels
#' @export
var_label <- function(x) {
  if (is.data.frame(x)) return(lapply(x, var_label))
  attr(x, "label", exact = TRUE)
}

#' @rdname val_labels
#' @export
val_labels <- function(x) {
  if (is.data.frame(x)) return(lapply(x, val_labels))
  attr(x, "labels", exact = TRUE)
}

#' @rdname val_labels
#' @export
val_label <- function(x, values = x) {
  if (is.list(x)) stop("x must be a column, not a ", class(x)[1], call. = FALSE)
  labels <- attr(x, "labels", exact = TRUE)
  if (is.null(labels)) return(rep(NA_character_, length(values)))
  if (!(is.double(values) || is.integer(values) || is.logical(values)) || is.factor(values)) {
    stop("values must be a double, integer or logical vector", call. = FALSE)
  }
  values <- as.double(unclass(values))
  codes <- as.double(unclass(labels))
  text <- names(labels)
  out <- rep(NA_character_, length(values))
  # match() pairs NA with NA, so NA keys stay out of both sides: numbers
  # against numeric codes, then letters against the codes' letters.
  number <- !is.na(values)
  coded <- !is.na(codes)
  out[number] <- text[coded][match(values[number], codes[coded])]
  tags <- na_tag(values)
  tagged <- !is.na(tags)
  code_tags <- na_tag(codes)
  has_tag <- !is.na(code_tags)
  out[tagged] <- text[has_tag][match(tags[tagged], code_tags[has_tag])]
  out
}
