#' Columns to group or join by, with `.a` to `.z` kept apart
#'
#' R's grouping and matching treat every `NA` as one value, so dplyr's
#' `group_by()`, `count()`, `distinct()` and joins put `.` and `.a` to
#' `.z` in one group. `datakit_by()` returns each column you give it and,
#' beside each one that can hold a letter, its letter as a column of its
#' own (`dtaparser::na_tag()`), so that grouping or joining by both keeps
#' the letters apart:
#'
#' ```r
#' d |> group_by(datakit_by(x)) |> summarise(n = n(), .groups = "drop")
#' d |> count(datakit_by(x, y))
#' d |> distinct(datakit_by(x))
#' d |> mutate(datakit_by(x)) |> left_join(lookup, by = c("x", "x_letter"))
#' ```
#'
#' dplyr splices the tibble it returns into columns. `summarise()` keeps
#' each group's first value of `x`, so `x` keeps its letters in the
#' result. By default `summarise()` drops the last grouping column, which
#' is the letter column, so the result is grouped by `x` alone and a
#' later grouped step would merge the letters again: give `.groups =
#' "drop"`, or group again with `datakit_by()`.
#'
#' `.by =` and `join_by()` take column names, not calls: `summarise(d,
#' n = n(), .by = datakit_by(x))` fails with "object 'x' not found".
#' Make the columns with `mutate(datakit_by(x))` first, then name both
#' (`.by = c(x, x_letter)`, `by = c("x", "x_letter")`). A join must keep
#' dplyr's default `na_matches = "na"`: with `"never"`, the letter column
#' of every number is `NA` and no number would match.
#'
#' @param ... Columns, as `group_by()` takes them: a column name, an
#'   expression, or `name = expression`. Each is named as `group_by()`
#'   names it: a bare column keeps its name, as do `.data$x`,
#'   `.data[[v]]` and `{{ var }}`.
#' @param .suffix Appended to a column's name to name its letter column.
#' @return A tibble with, for each argument in order, the column, and
#'   right after a column that can hold a letter, a character column
#'   `<name><.suffix>`: `"a"` to `"z"` for `.a` to `.z`, `NA` for numbers
#'   and `.`. The columns that can hold a letter are doubles with no
#'   class, `dtaparser_labelled` and `haven_labelled` doubles, `Date` and
#'   `POSIXct`; others (integers, text, factors, `integer64`,
#'   `difftime`) get no letter column. The letter column is there even
#'   when no row holds a letter, so a script gives the same columns for
#'   every file. Two columns of the result with one name are an error; a
#'   column of the data frame with the name of one is replaced, as dplyr
#'   replaces a column for any named result.
#' @examples
#' d <- tibble::tibble(x = c(1, dtaparser::tagged_na("a"), dtaparser::tagged_na("b"), NA, 1))
#' if (requireNamespace("dplyr", quietly = TRUE)) {
#'   dplyr::count(d, x)               # 1 and NA: the letters merged
#'   dplyr::count(d, datakit_by(x))   # 1, .a, .b and . apart
#' }
#' @export
datakit_by <- function(..., .suffix = "_letter") {
  if (!is.character(.suffix) || length(.suffix) != 1 || is.na(.suffix) || !nzchar(.suffix)) {
    stop(".suffix must be one non-empty string", call. = FALSE)
  }
  quos <- rlang::enquos(..., .named = TRUE)
  if (length(quos) == 0) stop("datakit_by() needs at least one column", call. = FALSE)
  values <- list(...)
  cols <- list()
  nms <- character()
  for (i in seq_along(values)) {
    x <- values[[i]]
    cols[[length(cols) + 1]] <- x
    nms <- c(nms, names(quos)[i])
    if (can_hold_letter(x)) {
      cols[[length(cols) + 1]] <- unname(dtaparser::na_tag(x))
      nms <- c(nms, paste0(names(quos)[i], .suffix))
    }
  }
  dup <- unique(nms[duplicated(nms)])
  if (length(dup) > 0) {
    stop("datakit_by() would make two columns named ", paste0("\"", dup, "\"", collapse = ", "),
         "; give the arguments other names or another .suffix", call. = FALSE)
  }
  cols <- vctrs::vec_recycle_common(!!!cols)
  names(cols) <- nms
  tibble::new_tibble(cols, nrow = vctrs::vec_size(cols[[1]]))
}

# A double with no class, a labelled double (dtaparser's or haven's), a
# Date or a POSIXct: the types whose values can be R's tagged NAs.
can_hold_letter <- function(x) {
  is.double(x) && (is.null(oldClass(x)) || inherits(x, c("dtaparser_labelled", "haven_labelled", "Date", "POSIXct")))
}
