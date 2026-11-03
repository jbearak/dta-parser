#' Labelled columns that keep their labels
#'
#' With `factors = FALSE`, [read_dta()] and [read_fixed_width()] return a
#' column with value labels as a `dtaparser_labelled`: its codes, `.a` to
#' `.z` among them as tagged NAs, with the labels and the variable label
#' as attributes. The class tells vctrs, and so dplyr, how to combine it,
#' so the labels survive `bind_rows()`, `case_when()` and `if_else()`,
#' which drop a plain `labels` attribute. `with_labels()` makes one.
#'
#' **Missing values.** Every missing value, `.` and `.a` to `.z` alike, is
#' `NA` to `is.na()`, comparisons and arithmetic, as R's rules say.
#' [val_label()] gives the text of `.a` to `.z`, which says why each is
#' missing. `unique()`, `count()` and `group_by()` put every missing value
#' in one group, as for any double; group on `val_label(x)` to count them
#' by reason.
#'
#' **Text and factors.** `as.character(x)` gives each value's label, or
#' its number where it has none, and `NA` for every missing value.
#' `factor(x)` and `table(x)` follow from it: levels are the values
#' present, in code order, by their text, and no missing value is a level.
#' Two codes with the same text share a level, and so does an unlabelled
#' number whose text is another code's label. Printing shows code and
#' label, `1 [Yes]`, and `NA(r) [Refused]` for a labelled `.r`.
#'
#' **Survey estimates.** The column is a double (or integer), so the
#' survey package treats it as a number: `svymean(~x, design)` averages
#' the codes. For the share of each answer, write
#' `svymean(~factor(x), design, na.rm = TRUE)`.
#'
#' **Comparisons and arithmetic.** `x == 1`, `x > 0`, `x %in% c(1, 5)`
#' and `match(1, x)` compare codes. A label stands for its code in `==`
#' and `!=`: `x == "Yes"` is `x == 1`. A label of a missing value is an
#' error there, since `NA` compares as `NA` (write `is_tagged_na(x, "r")`
#' or `val_label(x) == "Refused"`), and so are `<` and `>` with text,
#' since labels have no order. `x %in% c("Yes", "No")` compares codes with
#' text and is `FALSE` throughout; write `val_label(x) %in% c("Yes", "No")`.
#' Arithmetic, math and summaries (`x + 1`,
#' `abs(x)`, `sum(x)`, `mean(x)`, `max(x)`, `median(x)`, `quantile(x)`)
#' give plain numbers: a computed number has no label.
#'
#' **Combining.** Two labelled columns combine to one with the union of
#' their labels. A code, or a letter, with different text in the two is
#' an error; relabel first with `with_labels()`. The variable label is the
#' first one found. A labelled column and plain numbers combine to a
#' labelled column with the labelled side's labels, so
#' `if_else(cond, x, 99)` keeps them. Those labels still describe the old
#' codes: `case_when(x == 1 ~ 2, .default = x)` leaves code 2 with code
#' 2's old label, whatever 2 now means. Base `ifelse()` drops the class
#' and labels; use `dplyr::if_else()`.
#'
#' **Plain vectors.** `as.numeric(x)` and `vctrs::vec_data(x)` give the
#' codes with no attributes, `.a` to `.z` kept; `unclass(x)` keeps
#' `labels` and `label`. `as.integer(x)` is an error when `x` holds `.a`
#' to `.z` or fractions. `x[i] <- value` casts into `x`'s type, so a
#' fraction into integer codes is an error there; `d[i, x] := value`
#' widens the codes to double instead. A label assigns its code, as in
#' `x[i] <- "No"`, `if_else(cond, "No", x)` or `d[i, x] := "Refused"`; a
#' string that labels no code, or two, is an error.
#' `dplyr::recode()` has no method
#' for the class; use `dplyr::case_match()`.
#'
#' @param x An integer or double vector, or a `dtaparser_labelled`, whose
#'   codes are kept and whose labels are replaced.
#' @param labels The codes, named by their text: an integer or double
#'   vector with `.a` to `.z` as [tagged_na()], no repeated code or
#'   letter, no plain `NA` or `NaN`, and no empty or `NA` name.
#' @param label The variable label, a string; `NULL` keeps `x`'s.
#' @return A `dtaparser_labelled` with `x`'s codes. Its labels are kept
#'   in code order, `.a` to `.z` last.
#' @seealso [val_label()], [val_labels()], [na_tag()].
#' @examples
#' x <- with_labels(c(1, 0, tagged_na("r"), 1, NA),
#'                  c(No = 0, Yes = 1, tagged_na(c(Refused = "r"))),
#'                  label = "Wants a baby")
#' x                   # 1 [Yes] 0 [No] NA(r) [Refused] 1 [Yes] NA
#' x == 1              # TRUE FALSE NA TRUE NA
#' x == "Yes"          # the same
#' x[2] <- "Yes"       # code 1
#' val_label(x)        # "Yes" "No" "Refused" "Yes" NA
#' as.character(x)     # "Yes" "No" NA "Yes" NA
#' table(x)            # No 1, Yes 2
#'
#' # Labels survive dplyr; the union is kept.
#' y <- with_labels(c(0, tagged_na("d")), c(No = 0, Yes = 1, tagged_na(c("Don't know" = "d"))))
#' z <- vctrs::vec_c(x, y)
#' val_labels(z)       # No = 0, Yes = 1, Don't know = NA, Refused = NA
#' na_tag(z)           # NA NA "r" NA NA NA "d"
#' @export
with_labels <- function(x, labels, label = NULL) {
  if (is.null(label)) label <- attr(x, "label", exact = TRUE)
  if (inherits(x, "dtaparser_labelled")) x <- vctrs::vec_data(x)
  if (!(is.double(x) || is.integer(x)) || is.object(x)) {
    stop("x must be an integer or double vector, not ", class(x)[1], call. = FALSE)
  }
  if (!is.null(label) && !(is.character(label) && length(label) == 1 && !is.na(label))) {
    stop("label must be a string or NULL", call. = FALSE)
  }
  new_labelled(x, checked_labels(labels), label)
}

checked_labels <- function(labels) {
  if (!(is.double(labels) || is.integer(labels)) || is.object(labels)) {
    stop("labels must be an integer or double vector, not ", class(labels)[1], call. = FALSE)
  }
  labels <- stats::setNames(as.double(labels), names(labels))
  text <- names(labels)
  if (length(labels) && (is.null(text) || anyNA(text) || any(!nzchar(text)))) {
    stop("labels must each have a name, its text", call. = FALSE)
  }
  tags <- na_tag(labels)
  if (any(is.na(labels) & is.na(tags))) stop("labels cannot label NA or NaN, only numbers and .a to .z", call. = FALSE)
  keys <- label_keys(labels)
  if (anyDuplicated(keys)) stop("labels has code ", keys[anyDuplicated(keys)], " more than once", call. = FALSE)
  labels
}

# The class around the codes `x`, with `labels` put in code order.
new_labelled <- function(x, labels, label) {
  attributes(x) <- NULL
  vctrs::new_vctr(x, labels = in_code_order(labels), label = label, class = "dtaparser_labelled")
}

# A read column with a `labels` attribute as the class.
as_labelled_column <- function(x) {
  new_labelled(x, attr(x, "labels", exact = TRUE), attr(x, "label", exact = TRUE))
}

in_code_order <- function(labels) {
  if (is.null(labels)) return(stats::setNames(double(), character()))
  tags <- na_tag(labels)
  numbers <- labels[is.na(tags)]
  tagged <- labels[!is.na(tags)]
  c(numbers[order(numbers)], tagged[order(tags[!is.na(tags)])])
}

# Each code as text, ".r" for a tagged NA, to match codes by: match()
# pairs every NA with every other.
label_keys <- function(codes) {
  tags <- na_tag(codes)
  unname(ifelse(is.na(tags), sprintf("%.17g", codes), paste0(".", tags)))
}

labels_of <- function(x) attr(x, "labels", exact = TRUE)

# The labels of x and y together. A code with two texts is an error.
union_labels <- function(x, y) {
  all <- c(labels_of(x), labels_of(y))
  keys <- label_keys(all)
  first <- !duplicated(keys)
  kept <- all[first]
  text <- names(kept)[match(keys, keys[first])]
  clash <- which(names(all) != text)
  if (length(clash)) {
    i <- clash[[1]]
    stop("Can't combine labels: code ", keys[[i]], " is \"", text[[i]], "\" in one and \"", names(all)[[i]],
         "\" in the other; relabel one with with_labels()", call. = FALSE)
  }
  in_code_order(kept)
}

first_label <- function(x, y) attr(x, "label", exact = TRUE) %||% attr(y, "label", exact = TRUE)

# The plain codes of a labelled value, other values as they are.
plain <- function(x) if (inherits(x, "dtaparser_labelled")) vctrs::vec_data(x) else x

# `x`'s codes as `to`'s type: integer only when no code is a fraction
# or .a to .z, which an integer cannot hold.
codes_as <- function(x, to, x_arg, to_arg, call) {
  x <- plain(x)
  if (is.double(vctrs::vec_data(to))) return(as.double(x))
  out <- vctrs::vec_cast(x, integer(), x_arg = x_arg, call = call)
  if (is.double(x)) {
    out <- vctrs::maybe_lossy_cast(out, x, to, lossy = is_tagged_na(x), x_arg = x_arg, to_arg = to_arg, call = call)
  }
  out
}

#' @export
vec_ptype_abbr.dtaparser_labelled <- function(x, ...) {
  if (is.integer(vctrs::vec_data(x))) "int+lbl" else "dbl+lbl"
}

#' @export
vec_ptype_full.dtaparser_labelled <- function(x, ...) {
  paste0("dtaparser_labelled<", typeof(vctrs::vec_data(x)), ">")
}

#' @export
format.dtaparser_labelled <- function(x, ...) {
  codes <- vctrs::vec_data(x)
  tags <- na_tag(as.double(codes))
  shown <- ifelse(is.na(codes), ifelse(is.na(tags), "NA", paste0("NA(", tags, ")")), as.character(codes))
  text <- val_label(x)
  ifelse(is.na(text), shown, paste0(shown, " [", text, "]"))
}

#' @export
as.character.dtaparser_labelled <- function(x, ...) {
  codes <- vctrs::vec_data(x)
  text <- val_label(x)
  out <- ifelse(is.na(text), as.character(codes), text)
  out[is.na(codes)] <- NA_character_
  out
}

#' @export
mtfrm.dtaparser_labelled <- function(x) vctrs::vec_data(x)

#' @export
vec_ptype2.dtaparser_labelled.dtaparser_labelled <- function(x, y, ...) {
  both_integer <- is.integer(vctrs::vec_data(x)) && is.integer(vctrs::vec_data(y))
  new_labelled(if (both_integer) integer() else double(), union_labels(x, y), first_label(x, y))
}

#' @export
vec_ptype2.dtaparser_labelled.double <- function(x, y, ...) new_labelled(double(), labels_of(x), first_label(x, y))
#' @export
vec_ptype2.double.dtaparser_labelled <- function(x, y, ...) new_labelled(double(), labels_of(y), first_label(y, x))

#' @export
vec_ptype2.dtaparser_labelled.integer <- function(x, y, ...) {
  new_labelled(vctrs::vec_ptype(vctrs::vec_data(x)), labels_of(x), first_label(x, y))
}
#' @export
vec_ptype2.integer.dtaparser_labelled <- function(x, y, ...) {
  new_labelled(vctrs::vec_ptype(vctrs::vec_data(y)), labels_of(y), first_label(y, x))
}

#' @export
vec_cast.dtaparser_labelled.dtaparser_labelled <- function(x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()) {
  merged <- union_labels(to, x)
  if (length(merged) != length(labels_of(to))) {
    extra <- setdiff(label_keys(labels_of(x)), label_keys(labels_of(to)))
    vctrs::stop_incompatible_cast(x, to, x_arg = x_arg, to_arg = to_arg, call = call,
                                  details = paste0("Code ", extra[[1]], " has a label that `", to_arg %|% "to",
                                                   "` lacks, so the cast would drop it."))
  }
  new_labelled(codes_as(x, to, x_arg, to_arg, call), labels_of(to), attr(to, "label", exact = TRUE))
}

#' @export
vec_cast.dtaparser_labelled.double <- function(x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()) {
  new_labelled(codes_as(x, to, x_arg, to_arg, call), labels_of(to), attr(to, "label", exact = TRUE))
}
#' @export
vec_cast.dtaparser_labelled.integer <- vec_cast.dtaparser_labelled.double

#' @export
vec_cast.double.dtaparser_labelled <- function(x, to, ...) as.double(vctrs::vec_data(x))

#' @export
vec_cast.integer.dtaparser_labelled <- function(x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()) {
  codes_as(x, integer(), x_arg, to_arg, call)
}

`%|%` <- function(x, y) if (nzchar(x)) x else y

#' @export
#' @method vec_arith dtaparser_labelled
vec_arith.dtaparser_labelled <- function(op, x, y, ...) {
  codes <- vctrs::vec_data(x)
  # -x and +x arrive with y as vctrs' MISSING().
  if (inherits(y, "MISSING")) {
    return(switch(op, "-" = -codes, "+" = codes, vctrs::stop_incompatible_op(op, x, y)))
  }
  vctrs::vec_arith_base(op, codes, plain(y))
}

#' @export
#' @method vec_arith.numeric dtaparser_labelled
vec_arith.numeric.dtaparser_labelled <- function(op, x, y, ...) vctrs::vec_arith_base(op, x, vctrs::vec_data(y))

#' @export
vec_math.dtaparser_labelled <- function(.fn, .x, ...) vctrs::vec_math_base(.fn, vctrs::vec_data(.x), ...)

#' @export
Summary.dtaparser_labelled <- function(..., na.rm = FALSE) {
  do.call(.Generic, c(lapply(list(...), plain), na.rm = na.rm))
}

#' @export
median.dtaparser_labelled <- function(x, na.rm = FALSE, ...) stats::median(vctrs::vec_data(x), na.rm = na.rm, ...)

#' @export
quantile.dtaparser_labelled <- function(x, ...) stats::quantile(vctrs::vec_data(x), ...)

#' @export
summary.dtaparser_labelled <- function(object, ...) summary(vctrs::vec_data(object), ...)

# The code each string in `text` labels in `to`: NA for NA. A string
# that labels no code, or two, names no one code and is an error.
text_codes <- function(text, to) {
  labels <- labels_of(to)
  text_of <- names(labels) %||% character()
  hit <- match(text, text_of)
  unknown <- !is.na(text) & is.na(hit)
  if (any(unknown)) {
    shown <- if (length(text_of)) paste0("\"", text_of, "\"", collapse = ", ") else "none"
    stop("\"", text[unknown][[1]], "\" is not a label of this column; its labels are ", shown, call. = FALSE)
  }
  shared <- !is.na(text) & text %in% text_of[duplicated(text_of)]
  if (any(shared)) stop("\"", text[shared][[1]], "\" labels more than one code; give the code", call. = FALSE)
  unname(as.double(labels))[hit]
}

#' @export
vec_ptype2.dtaparser_labelled.character <- function(x, y, ...) {
  new_labelled(double(), labels_of(x), attr(x, "label", exact = TRUE))
}
#' @export
vec_ptype2.character.dtaparser_labelled <- function(x, y, ...) {
  new_labelled(double(), labels_of(y), attr(y, "label", exact = TRUE))
}

#' @export
vec_cast.dtaparser_labelled.character <- function(x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()) {
  codes <- text_codes(x, to)
  new_labelled(codes_as(codes, to, x_arg, to_arg, call), labels_of(to), attr(to, "label", exact = TRUE))
}

# == and != with a string compare the code it labels. A label of a
# missing value would compare as NA on every row, and labels have no
# order, so those are errors. Everything else goes on to vctrs.
#' @export
Ops.dtaparser_labelled <- function(e1, e2) {
  if (nargs() == 2 && (is.character(e1) || is.character(e2)) && .Generic %in% c("==", "!=", "<", ">", "<=", ">=")) {
    if (!.Generic %in% c("==", "!=")) {
      stop("`", .Generic, "`: labels have no order; compare codes, as in x ", .Generic, " 1", call. = FALSE)
    }
    labelled <- if (is.character(e1)) e2 else e1
    text <- if (is.character(e1)) e1 else e2
    codes <- text_codes(text, labelled)
    missing <- !is.na(text) & is.na(codes)
    if (any(missing)) {
      tag <- na_tag(codes[missing][[1]])
      stop("\"", text[missing][[1]], "\" labels the missing value .", tag, ", and NA compares as NA; write is_tagged_na(x, \"",
           tag, "\") or val_label(x) == \"", text[missing][[1]], "\"", call. = FALSE)
    }
    return(get(.Generic)(vctrs::vec_data(labelled), codes))
  }
  NextMethod()
}
