#' Multiple and immediate Stata tabulations
#'
#' `tab1()` creates one one-way table for each selected variable. `tab2()`
#' creates each pairwise two-way table, or only pairs involving the first
#' variable when `firstonly = TRUE`. Both accept the vector and data-frame
#' forms of [tab()], and named `tab()` options through `...`.
#'
#' `tabi()` tabulates a matrix of nonnegative integer cell frequencies
#' directly, without expanding the represented observations. With no table
#' options it requests Fisher's exact test for a two-by-two input, and
#' Pearson's chi-squared test otherwise, as Stata's immediate command does.
#'
#' @param x A vector or data frame for `tab1()` and `tab2()`; a numeric matrix
#'   of cell frequencies for `tabi()`.
#' @param ... Additional variables and named [tab()] options for `tab1()` and
#'   `tab2()`; named `tab()` presentation and test options for `tabi()`.
#' @param data Optional data frame containing the selected variables.
#' @param firstonly Whether to pair only the first variable with the others.
#' @param replace Whether to attach the compact immediate data as the `data`
#'   attribute, with columns `row`, `col`, and `pop`. R's calling data are
#'   unchanged.
#' @return `tab1()` and `tab2()` return a `dta_tabs` list of `dta_tab` objects.
#'   Its `r` attribute contains the final table's stored results. `tabi()`
#'   returns one `dta_tab`, as [tab()] does.
#' @export
tab1 <- function(x, ..., data = NULL) {
    .tab_multiple(if (missing(x)) NULL else rlang::enquo(x),
        rlang::enquos(...), data, rlang::caller_env(), pairwise = FALSE)
}

#' @rdname tab1
#' @export
tab2 <- function(x, ..., data = NULL, firstonly = FALSE) {
    .dta_group_flag(firstonly, "firstonly")
    .tab_multiple(if (missing(x)) NULL else rlang::enquo(x),
        rlang::enquos(...), data, rlang::caller_env(), pairwise = TRUE,
        firstonly = firstonly)
}

.tab_multiple <- function(x, dots, data, caller, pairwise, firstonly = FALSE) {
    option_names <- setdiff(names(formals(tab)), c("x", "...", "data"))
    option <- names(dots) %in% option_names
    options <- as.list(dots[option])
    lazy_options <- c("where", "by", "weights", "subpop", "summarize")
    for (name in setdiff(names(options), lazy_options)) {
        options[name] <- list(rlang::eval_tidy(options[[name]]))
    }
    selectors <- dots[!option]
    inputs <- .tab_inputs(x, selectors, data, caller)
    if (length(inputs$values) < if (pairwise) 2L else 1L) {
        stop(if (pairwise) "`tab2()` needs at least two variables" else
             "nothing to tabulate", call. = FALSE)
    }
    frame <- inputs$data
    if (!is.null(frame)) {
        # Recover original selection quosures to preserve their environments
        # and user-supplied names while forwarding sample expressions intact.
        # When no explicit data argument was supplied, .tab_inputs can only
        # return a data frame here by having evaluated x to that frame.
        # Do not evaluate x a second time: it may read data or have effects.
        first_is_frame <- is.null(data) && !is.null(x)
        selected <- c(if (!first_is_frame && !is.null(x)) list(x), selectors)
        if (!length(selected)) selected <- lapply(names(frame), function(name)
            rlang::new_quosure(rlang::sym(name), caller))
    } else {
        # Values are already resolved, and their quosures need no data mask.
        # Passing literal vectors also supports tab1(list(a = x, b = y)).
        selected <- lapply(inputs$values, rlang::new_quosure, env = caller)
    }
    names(selected) <- inputs$names
    if (pairwise && "weights" %in% names(options) &&
        !rlang::quo_is_null(options$weights)) {
        weight <- if ("weight" %in% names(options))
            options$weight else "aweight"
        weight <- match.arg(weight, c("aweight", "fweight", "iweight"))
        if (!identical(weight, "fweight"))
            stop("`tab2()` allows fweights only", call. = FALSE)
    }
    indices <- if (!pairwise) lapply(seq_along(selected), identity) else {
        pairs <- utils::combn(seq_along(selected), 2L, simplify = FALSE)
        if (firstonly) Filter(function(pair) pair[[1L]] == 1L, pairs) else pairs
    }
    result <- lapply(indices, function(index) {
        rlang::inject(tab(!!!selected[index], data = !!frame, !!!options))
    })
    names(result) <- vapply(indices, function(index) {
        paste(inputs$names[index], collapse = " by ")
    }, character(1))
    where <- if (!is.null(options$where) && !rlang::quo_is_null(options$where))
        paste0("if ", rlang::as_label(options$where)) else ""
    positions <- if (!is.null(options$rows)) .egen_positions(options$rows) else NULL
    rows <- if (length(positions)) {
        if (all(diff(sort(unique(positions))) == 1L))
            paste0("in ", min(positions), "/", max(positions)) else
            paste0("in ", paste(positions, collapse = ","))
    } else ""
    attr(result, "qualifier") <- if (nzchar(where) && nzchar(rows))
        paste0(" ", where, "  ", rows) else paste0(" ", where, " ", rows)
    attr(result, "r") <- attr(result[[length(result)]], "r", exact = TRUE)
    class(result) <- c("dta_tabs", "list")
    if (all(vapply(result, inherits, logical(1), "dta_tab_grouped"))) {
        # Native by: runs the entire convenience command within each group,
        # so group headings surround each sequence of variable tables.
        first <- result[[1L]]
        grouped <- lapply(seq_along(first), function(index) {
            one <- lapply(result, `[[`, index)
            attr(one, "qualifier") <- attr(result, "qualifier", exact = TRUE)
            attr(one, "r") <- attr(one[[length(one)]], "r", exact = TRUE)
            class(one) <- c("dta_tabs", "list")
            one
        })
        attr(grouped, "groups") <- attr(first, "groups", exact = TRUE)
        attr(grouped, "r") <- if (length(grouped))
            attr(grouped[[length(grouped)]], "r", exact = TRUE) else list()
        class(grouped) <- c("dta_tab_grouped", "list")
        return(grouped)
    }
    result
}

#' @export
format.dta_tabs <- function(x, ...) {
    unlist(lapply(seq_along(x), function(index) {
        c(if (index > 1L) "", paste0("-> tabulation of ", names(x)[[index]],
                                   attr(x, "qualifier", exact = TRUE)),
          "", format(x[[index]], ...))
    }), use.names = FALSE)
}

#' @export
print.dta_tabs <- function(x, ...) {
    lines <- format(x, ...)
    if (length(lines)) cat(lines, sep = "\n")
    invisible(x)
}

#' @rdname tab1
#' @export
tabi <- function(x, ..., replace = FALSE) {
    .dta_group_flag(replace, "replace")
    if (!is.matrix(x) || !is.numeric(x) || any(dim(x) < 2L) ||
        anyNA(x) || any(!is.finite(x)) || any(x < 0) || any(x != floor(x))) {
        stop("`x` must be a numeric matrix with at least two rows and columns and nonnegative integer counts",
             call. = FALSE)
    }
    options <- rlang::enquos(...)
    allowed <- setdiff(names(formals(tab)), c("x", "...", "data", "where", "rows",
        "by", "weights", "weight", "subpop", "generate", "summarize", "means",
        "standard", "obs"))
    if (any(!nzchar(names(options))) || any(!names(options) %in% allowed)) {
        stop("`tabi()` requires named frequency-table options", call. = FALSE)
    }
    options <- lapply(options, rlang::eval_tidy)
    if (!length(options)) {
        options <- if (all(dim(x) == 2L)) list(exact = TRUE) else
            list(chi2 = TRUE)
    }
    # One record per input cell, independent of total frequency. Native
    # replace retains zero cells and orders records across each table row;
    # tab's weight sampling excludes those zeros from the frequency table.
    compact <- expand.grid(col = seq_len(ncol(x)), row = seq_len(nrow(x)),
        KEEP.OUT.ATTRS = FALSE)[c("row", "col")]
    compact$pop <- as.vector(t(x))
    labels <- dimnames(x)
    if (!is.null(labels)) {
        for (i in seq_len(2L)) if (!is.null(labels[[i]])) {
            attr(compact[[i]], "labels") <- stats::setNames(
                as.double(seq_along(labels[[i]])), labels[[i]])
        }
        headers <- names(labels)
        if (!is.null(headers)) for (i in seq_len(2L)) if (nzchar(headers[[i]]))
            attr(compact[[i]], "label") <- headers[[i]]
    }
    result <- rlang::inject(tab(!!rlang::sym("row"), !!rlang::sym("col"),
        data = compact, weights = !!compact$pop,
        weight = "fweight", !!!options))
    if (replace) attr(result, "data") <- compact
    result
}
