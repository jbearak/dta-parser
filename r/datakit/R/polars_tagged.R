# .a to .z in polars (plan 0025): tagged NaNs in Float64 columns, as in
# Python's datakit (_tagged.py) and ADR 0036. A letter is R's NA_real_
# (a NaN whose low word is 1954) with the letter's ASCII code in bits 32
# to 39, the layout of dtaparser's tagged_na(). Reading one back ignores
# the sign and the quiet bit, which arithmetic may change.

# The bits of NA_real_, and the mask that keeps what a letter fixes,
# as text: R's doubles cannot hold them exactly.
NA_BITS_TEXT <- "9218868437227407266"
TAG_MASK_TEXT <- "9221119141824430079"

# polars, nanoarrow and R 4.3, which the polars functions need.
check_polars <- function(what) {
  if (getRversion() < "4.3") {
    stop(what, "() needs R 4.3 or later, as polars does; this is R ", getRversion(), call. = FALSE)
  }
  rlang::check_installed(c("polars", "nanoarrow"), reason = paste0("for ", what, "()"))
}

# The Enum of ".a" to ".z" that na_tag_pl() gives (Python's LETTERS).
letters_dtype <- function() polars::pl$Enum(paste0(".", letters))

u64 <- function(x) polars::pl$lit(x)$cast(polars::pl$UInt64)

# The letter of each row of the expression `e`, as LETTERS, or null.
# Any dtype: a cast never makes R's tag pattern, so only a Float64
# column's own letters count.
na_tag_expr <- function(e) {
  pl <- polars::pl
  bits <- e$to_physical()$cast(pl$Float64, strict = FALSE)$reinterpret(dtype = pl$UInt64)
  byte <- (bits %/% u64(2^32)) %% u64(256)
  tagged <- (bits & u64(TAG_MASK_TEXT)) == u64(NA_BITS_TEXT)
  letter <- byte$replace_strict(97:122, paste0(".", letters), default = pl$lit(NULL),
                                return_dtype = letters_dtype())
  pl$when(tagged)$then(letter)$otherwise(pl$lit(NULL, letters_dtype()))
}

# `values` (a Float64 expression) with a tagged NaN wherever `letters`
# (a LETTERS expression) has a letter.
tag_expr <- function(values, letters) {
  pl <- polars::pl
  code <- letters$to_physical()$cast(pl$UInt64) + u64(97)
  tags <- (u64(NA_BITS_TEXT) + code * u64(2^32))$reinterpret(dtype = pl$Float64)
  pl$when(letters$is_not_null())$then(tags)$otherwise(values)
}

# `f` of a Series: run on it as a one-column frame.
on_series <- function(s, f) {
  name <- s$name
  s$alias("x")$to_frame()$select(f(polars::pl$col("x"))$alias(name))$to_series()
}

# A column name (one string) or an expression as an expression; a
# Series as itself.
as_column <- function(x, what) {
  if (is.character(x) && length(x) == 1 && !is.na(x)) return(polars::pl$col(x))
  if (inherits(x, c("polars_expr", "polars_series"))) return(x)
  stop(what, "() takes a column name, a polars expression or a polars Series, not ",
       class(x)[[1]], call. = FALSE)
}

one_letter <- function(letter) {
  if (!is.character(letter) || length(letter) != 1 || is.na(letter)) {
    stop("a letter is one string, \".a\" to \".z\" or \"a\" to \"z\"", call. = FALSE)
  }
  t <- sub("^\\.", "", letter)
  if (!(t %in% letters)) stop("a letter is \".a\" to \".z\" or \"a\" to \"z\", not \"", letter, "\"", call. = FALSE)
  t
}

#' `.a` to `.z` in polars frames
#'
#' In a polars frame from [read_parquet_pl()], [read_dta_pl()] or
#' [read_fixed_width_pl()], `.` is a null and `.a` to `.z` are NaNs
#' tagged with their letter in Float64 columns, the bits R holds
#' [dtaparser::tagged_na()] in. These expressions make and read them,
#' as Python datakit's `dk.tagged_na()`, `dk.na_tag()` and
#' `dk.is_tagged_na()` do.
#'
#' `tagged_na_pl()` is needed because R polars reads every R `NA`,
#' tagged or not, as a null: `pl$lit(tagged_na("a"))` is a null, not
#' `.a`.
#'
#' polars makes every NaN equal to every other, so grouping by a column
#' merges `.a` with `.b`; [datakit_by_pl()] keeps them apart. polars
#' also counts a NaN as a value: [is_missing()] says what R's `is.na()`
#' says.
#'
#' @param letter One letter: `".a"` to `".z"`, or `"a"` to `"z"`. For
#'   `is_tagged_na_pl()`, `NULL` (the default) tests for any letter.
#' @param x A column name, a polars expression, or a polars Series.
#' @return `tagged_na_pl()`: a Float64 literal expression. `na_tag_pl()`:
#'   each row's letter, `".a"` to `".z"` (an Enum of the 26), null for a
#'   number, `.` or a NaN that is not a letter; only Float64 holds
#'   letters, so any other dtype gives all null. `is_tagged_na_pl()`:
#'   true where a row is a letter (or the letter `letter`), false
#'   elsewhere, `.` included. An expression for a name or an expression,
#'   a Series for a Series.
#' @seealso [is_missing()], [datakit_by_pl()].
#' @examples
#' if (requireNamespace("polars", quietly = TRUE) && getRversion() >= "4.3") {
#'   pl <- polars::pl
#'   df <- pl$DataFrame(x = c(1, 2, 3))$with_columns(
#'     pl$when(pl$col("x") > 1)$then(tagged_na_pl("d"))$otherwise(pl$col("x"))$alias("x")
#'   )
#'   df$select(na_tag_pl("x"), is_tagged_na_pl("x", "d")$alias("is_d"))
#' }
#' @export
tagged_na_pl <- function(letter) {
  check_polars("tagged_na_pl")
  t <- one_letter(letter)
  code <- utf8ToInt(t)
  (u64(NA_BITS_TEXT) + u64(code * 2^32))$reinterpret(dtype = polars::pl$Float64)
}

#' @rdname tagged_na_pl
#' @export
na_tag_pl <- function(x) {
  check_polars("na_tag_pl")
  e <- as_column(x, "na_tag_pl")
  if (inherits(e, "polars_series")) {
    if (!inherits(e$dtype, "polars_dtype_float64")) {
      return(polars::as_polars_series(rep(NA_character_, e$len()), e$name)$cast(letters_dtype()))
    }
    return(on_series(e, na_tag_expr))
  }
  na_tag_expr(e)
}

#' @rdname tagged_na_pl
#' @export
is_tagged_na_pl <- function(x, letter = NULL) {
  check_polars("is_tagged_na_pl")
  tags <- na_tag_pl(x)
  if (is.null(letter)) return(tags$is_not_null())
  want <- paste0(".", one_letter(letter))
  if (inherits(tags, "polars_series")) {
    return(on_series(tags, function(e) e$eq_missing(polars::pl$lit(want, letters_dtype()))))
  }
  tags$eq_missing(polars::pl$lit(want, letters_dtype()))
}

#' Which values are missing: `.` and `.a` to `.z`
#'
#' `is_missing()` says what R's `is.na()` says, for R vectors and for
#' polars expressions and Series, where `.` is a null and `.a` to `.z`
#' are tagged NaNs (see [tagged_na_pl()]). `is_na()` is the same
#' function. A NaN that is not a letter counts too, as it does for
#' `is.na()`.
#'
#' polars' own `$is_null()` sees only `.`, and polars counts a NaN as a
#' value, so on a column holding letters:
#'
#' | expression | rows of `1, 5000, .a, .b, .` a filter keeps |
#' |---|---|
#' | `x != 1` | 3: `5000`, `.a`, `.b` |
#' | `(x != 1) & x$is_not_null()` | 3 |
#' | `(x != 1) & !is_na(x)` | 1: `5000` |
#'
#' polars also orders a NaN above every number, so `x > 3000` is true on
#' a letter: write `(x > 3000) & !is_na(x)`.
#'
#' - An R vector: `is.na(x)`.
#' - A polars expression, such as `pl$col("x")`: an expression, true
#'   where the row is null or, read as a Float64, NaN. It has no dtype
#'   until it runs, and is right for numeric, Boolean, Decimal, Date,
#'   Datetime, Duration, Time, Categorical, Enum and Null columns. It is
#'   not for text (the text `"nan"` would count as missing) nor for
#'   Binary, List, Array or Struct (polars raises an error when it runs):
#'   use `$is_null()` on those, or pass the Series.
#' - A polars Series: by its dtype, `$is_null() | $is_nan()` for a float,
#'   `$is_null()` for anything else.
#'
#' rlang exports an `is_na()` (a test for one `NA`) and an
#' `is_missing()` (a test for a missing argument), and dtatools an
#' `is_missing()` for its columns (Stata's rule: `""` is missing text).
#' Whichever package is attached last is the one R finds; write
#' `datakit::is_missing()` to be sure.
#'
#' @param x An R vector, a polars expression, or a polars Series.
#' @return A logical vector, a Boolean expression, or a Boolean Series
#'   with no nulls.
#' @seealso [tagged_na_pl()], [datakit_by_pl()].
#' @examples
#' is_missing(c(1, NA, tagged_na("a")))   # FALSE TRUE TRUE
#' if (requireNamespace("polars", quietly = TRUE) && getRversion() >= "4.3") {
#'   pl <- polars::pl
#'   df <- pl$DataFrame(x = c(1, 5000, NA))
#'   df$filter(pl$col("x") != 1 & !is_na(pl$col("x")))
#' }
#' @export
is_missing <- function(x) UseMethod("is_missing")

#' @rdname is_missing
#' @export
is_na <- is_missing

#' @export
is_missing.default <- function(x) is.na(x)

#' @export
is_missing.polars_expr <- function(x) {
  pl <- polars::pl
  x$is_null() | x$to_physical()$cast(pl$Float64, strict = FALSE)$is_nan()$fill_null(FALSE)
}

#' @export
is_missing.polars_series <- function(x) {
  if (inherits(x$dtype, "polars_dtype_float")) return(on_series(x, function(e) (e$is_null() | e$is_nan())$fill_null(TRUE)))
  x$is_null()
}

#' Columns to group or join by in polars, with `.a` to `.z` kept apart
#'
#' polars makes every NaN equal to every other, so `$group_by()` and
#' `$unique()` put `.a` and `.b` in one group, and `$join()` matches them
#' (see Joins below). `datakit_by_pl()` returns,
#' for each column you give it, the column and its letters as a column
#' of its own (`<name><.suffix>`, from [na_tag_pl()]), so that grouping
#' by both keeps the letters apart, as [datakit_by()] does for dplyr and
#' Python datakit's `dk.by()` for polars. polars groups nulls together,
#' so `.` is a group of its own.
#'
#' ```r
#' df$group_by(!!!datakit_by_pl("x"))$agg(pl$len())
#' df$with_columns(!!!datakit_by_pl("x"))$unique(subset = c("x", "x_letter"))
#' ```
#'
#' polars takes a list of expressions spliced with `!!!`.
#'
#' Every argument gets a letter column: an expression has no dtype until
#' it runs, so the letter column of a column that is not Float64 is all
#' null, which changes no grouping. A Binary, List, Array or Struct
#' column raises polars' error when the expression runs: group by it
#' alone.
#'
#' @section Joins:
#' polars joins on a key holding letters as it groups: every letter
#' matches every other, so `.a` in one frame matches both `.a` and `.b`
#' in the other. A null key matches nothing, so `.` matches `.` only with
#' `nulls_equal = TRUE`.
#'
#' To match each letter only with itself, add the letter columns to both
#' frames and join on the key and its letter column, with `nulls_equal =
#' TRUE`. The letter column is null for every number and for `.`, so
#' without `nulls_equal = TRUE` only the letters would match.
#'
#' ```r
#' left <- left$with_columns(!!!datakit_by_pl("x"))
#' right <- right$with_columns(!!!datakit_by_pl("x"))
#' left$join(right, on = c("x", "x_letter"), how = "left", nulls_equal = TRUE)
#' ```
#'
#' @param ... Columns: names, or polars expressions with an output name
#'   (`pl$col("x")`, `(pl$col("x") * 2)$alias("y")`). A named argument,
#'   `y = pl$col("x") * 2`, is named so.
#' @param .suffix Appended to a column's name to name its letter column.
#' @return A list of polars expressions: each column, then its letters.
#'   Two outputs with one name are an error.
#' @seealso [datakit_by()] for tibbles; [is_missing()].
#' @examples
#' if (requireNamespace("polars", quietly = TRUE) && getRversion() >= "4.3") {
#'   pl <- polars::pl
#'   df <- pl$DataFrame(x = c(1, 1, 2))$with_columns(
#'     pl$when(pl$col("x") == 2)$then(tagged_na_pl("a"))$otherwise(pl$col("x"))$alias("x")
#'   )
#'   df$group_by(!!!datakit_by_pl("x"), .maintain_order = TRUE)$agg(pl$len())
#' }
#' @export
datakit_by_pl <- function(..., .suffix = "_letter") {
  check_polars("datakit_by_pl")
  if (!is.character(.suffix) || length(.suffix) != 1 || is.na(.suffix) || !nzchar(.suffix)) {
    stop(".suffix must be one non-empty string", call. = FALSE)
  }
  args <- list(...)
  if (length(args) == 0) stop("datakit_by_pl() needs at least one column", call. = FALSE)
  given <- names(args) %||% rep("", length(args))
  out <- list()
  names <- character()
  for (i in seq_along(args)) {
    e <- as_column(args[[i]], "datakit_by_pl")
    if (inherits(e, "polars_series")) stop("datakit_by_pl() takes column names or expressions, not a Series", call. = FALSE)
    if (nzchar(given[[i]])) e <- e$alias(given[[i]])
    name <- tryCatch(e$meta$output_name(), error = function(err) NULL)
    if (is.null(name)) {
      stop("datakit_by_pl() needs a name for argument ", i, ": give it one with $alias()", call. = FALSE)
    }
    out <- c(out, list(e, na_tag_expr(e)$alias(paste0(name, .suffix))))
    names <- c(names, name, paste0(name, .suffix))
  }
  dup <- unique(names[duplicated(names)])
  if (length(dup)) {
    stop("datakit_by_pl() would make two columns named ", paste0("\"", dup, "\"", collapse = ", "),
         "; rename an argument or pick another .suffix", call. = FALSE)
  }
  out
}
