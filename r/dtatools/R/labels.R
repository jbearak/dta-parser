#' Value labels
#'
#' `val_labels(x)` gives `x`'s value labels as a named `dta_num`: the codes,
#' named by their text. `val_label(x, values)` gives the text of each of
#' `values` (NA where unlabelled). `labelbook(data)` lists every labelled
#' column's labels, in Stata's order.
#'
#' @param x A labelled column, such as one `read_dta` returned.
#' @param values Codes to look up.
#' @return See above. `labelbook()` returns `list(mappings = <data.frame>)`
#'   with columns `variable`, `label_set`, `code`, `code_text` and `text`.
#' @export
val_labels <- function(x) {
  labels <- attr(x, "labels", exact = TRUE)
  if (is.null(labels)) return(NULL)
  out <- numbers(labels)
  names(out) <- names(labels)
  class(out) <- "dta_num"
  out
}

#' @rdname val_labels
#' @export
val_label <- function(x, values) {
  labels <- attr(x, "labels", exact = TRUE)
  if (is.null(labels)) return(rep(NA_character_, length(values)))
  unname(names(labels)[match(dta_keys(values), dta_keys(labels))])
}

#' @rdname val_labels
#' @param data A data frame.
#' @export
labelbook <- function(data) {
  rows <- lapply(names(data), function(name) {
    labels <- val_labels(data[[name]])
    if (is.null(labels)) return(NULL)
    labels <- labels[order(dta_keys(labels))]
    list(variable = rep(name, length(labels)),
         label_set = rep(attr(data[[name]], "label_set", exact = TRUE) %||% name, length(labels)),
         code = labels, text = unname(names(labels)))
  })
  rows <- Filter(Negate(is.null), rows)
  code <- if (length(rows)) do.call(c, lapply(rows, `[[`, "code")) else dta_num()
  names(code) <- NULL
  list(mappings = data.frame(
    variable = unlist(lapply(rows, `[[`, "variable")) %||% character(),
    label_set = unlist(lapply(rows, `[[`, "label_set")) %||% character(),
    code = code,
    code_text = code_text(code),
    text = unlist(lapply(rows, `[[`, "text")) %||% character(),
    stringsAsFactors = FALSE
  ))
}
