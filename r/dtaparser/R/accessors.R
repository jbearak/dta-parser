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
#' path <- tempfile(fileext = ".dta")
#' save_dta(data.frame(KIDS = c(2, tagged_na("a"), tagged_na("b"), 0)), path)
#' df <- read_dta(path)
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

#' A value's place in Stata's missing-value order
#'
#' Stata puts every number below `.`, `.` below `.a`, and `.a` to `.z`
#' in order, and a comparison with a missing value is never missing.
#' `missing_rank()` gives each value's place in that order, so that
#' comparisons that follow Stata's missing-value order are one line of
#' R: Stata's `x > .a` is `missing_rank(x) > missing_rank(tagged_na("a"))`,
#' and the same holds for `>=`, `<` and `<=`. The ranks never are `NA`.
#'
#' Only the missing values are ranked: every number is 0, so compare
#' numbers with each other as usual. The letter of a tagged NA is read
#' before anything else, so `.a` to `.z` are never taken for `.`.
#' An integer or logical vector cannot hold a letter, so it ranks only 0
#' or 1; a `Date` or `POSIXct` read by [read_dta()] keeps its letters
#' and ranks them like any double.
#'
#' @param x A double, integer or logical vector, including a `Date`, a
#'   `POSIXct` and a labelled column from [with_labels()] or [read_dta()].
#'   A character vector, factor, list or data frame is an error.
#' @return A plain integer vector as long as `x`, with no names or other
#'   attributes: `0L` for a number, `1L` for `NA` or `NaN` (Stata's `.`),
#'   and `2L` to `27L` for `.a` to `.z`.
#' @seealso [na_tag()] for the letters themselves.
#' @examples
#' x <- c(5, NA, NaN, tagged_na(c("a", "b", "z")))
#' missing_rank(x)                                # 0 1 1 2 3 27
#' missing_rank(x) > missing_rank(tagged_na("a")) # Stata's x > .a
#' missing_rank(x) <= missing_rank(tagged_na("b")) # Stata's x <= .b
#' missing_rank(c(1L, NA))                        # 0 1
#' @export
missing_rank <- function(x) {
  if (is.factor(x) || !(is.double(x) || is.integer(x) || is.logical(x))) {
    stop("x must be a double, integer, logical, Date, POSIXct or labelled vector, not ",
         class(x)[1], call. = FALSE)
  }
  .Call(C_dta_missing_rank, x)
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
#' `dta_num` columns. With either
#' package attached as well, call these as `dtaparser::val_label()`.
#'
#' @param x A column, such as one `read_dta()` returned; for
#'   `var_label()` and `val_labels()`, also a data frame.
#' @param values Codes to look up: a double, integer or logical vector.
#' @return `var_label()`: a string or `NULL`. `val_labels()`: a named
#'   double or integer vector, or `NULL`. For a data frame, a named list
#'   of those. `val_label()`: a character vector as long as `values`.
#' @examples
#' kids <- with_labels(c(2, tagged_na("a"), tagged_na("b"), 0),
#'                     c(None = 0, tagged_na(c(DK = "a", "Not ascertained" = "b"))),
#'                     label = "Number of children")
#' path <- tempfile(fileext = ".dta")
#' save_dta(data.frame(KIDS = kids), path)
#' df <- read_dta(path)
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

#' A column without its labels
#'
#' `drop_labels(x)` gives `x` without its value labels (the `labels`
#' attribute) and its variable label (the `label` attribute), and
#' without the `dtaparser_labelled` class if it has it. Everything else
#' stays: the values, `.a` to `.z` with their letters, names, a `Date`
#' or `POSIXct` class and its time zone, and the display format
#' [save_dta()] writes. A vector with no labels comes back as it is.
#'
#' It is for copying a column without its labels while keeping its date
#' class, as Stata's `gen y = x` copies values but not labels.
#' `as.vector(x)` and `as.numeric(x)` drop the labels too, but also every
#' other attribute: a `Date` becomes a number of days.
#'
#' @param x A vector: double, integer, logical or character, a `Date`, a
#'   `POSIXct`, a factor, or a labelled column from [with_labels()] or
#'   [read_dta()]. A list or data frame is an error.
#' @return `x` without its `labels` and `label` attributes; a labelled
#'   column becomes its plain codes.
#' @seealso [var_label()], [val_labels()], [with_labels()].
#' @examples
#' x <- with_labels(c(1, 0, tagged_na("r")), c(No = 0, Yes = 1), label = "Wants a baby")
#' y <- drop_labels(x)
#' y                    # 1 0 NA
#' na_tag(y)            # NA NA "r"
#' val_labels(y)        # NULL
#'
#' d <- structure(as.Date("2024-01-31"), label = "Interview date")
#' drop_labels(d)       # "2024-01-31", still a Date
#' var_label(drop_labels(d))  # NULL
#' @export
drop_labels <- function(x) {
  if (is.list(x)) stop("x must be a column, not a ", class(x)[1], call. = FALSE)
  # The labelled class is always c("dtaparser_labelled", "vctrs_vctr")
  # around bare codes; unclass() keeps names and format.
  if (inherits(x, "dtaparser_labelled")) x <- unclass(x)
  attr(x, "labels") <- NULL
  attr(x, "label") <- NULL
  x
}
