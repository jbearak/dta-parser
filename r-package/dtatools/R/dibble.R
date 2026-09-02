#' Dibbles: tibbles that carry dtatools reference state
#'
#' A dibble is a tibble that carries dtatools reference state from its
#' creation rather than acquiring it at the first [gen()]. It is the default
#' container of [read_dta()], [read_arrow()], and [dta_append()], and the
#' container [dta_merge()] returns for a dibble `x`. `dibble()` builds one
#' from columns with the argument semantics of [tibble::tibble()];
#' `as_dibble()` converts a data frame, tibble, or data table; `is_dibble()`
#' tests for one.
#'
#' Reference state is what lets [gen()], [replace_values()], [keep_vars()],
#' and the other by-reference operations change a dataset in place so that
#' every binding to it sees the change. On a plain tibble the first `gen()`
#' attaches that state, so a dibble and a tibble that has been through
#' `gen()` are the same kind of object: `is_dibble()` is `TRUE` for both,
#' and `gen()` on a plain tibble is one way to obtain a dibble.
#'
#' A dibble prints, subsets, and joins as a tibble. Ordinary replacement
#' (`$<-`, `[[<-`, `[<-`, `names<-`) and most dplyr verbs return plain
#' tibbles holding the current contents, following copy-on-modify;
#' [dplyr::group_by()] and [dplyr::ungroup()] return a grouped or ungrouped
#' dibble. [tibble::as_tibble()] returns a tibble snapshot. `as_dibble()` of
#' a grouped tibble keeps its grouping.
#'
#' `as_dibble()` returns a dibble as is. Otherwise it returns a new object
#' and leaves its argument unchanged: a tibble or data frame is shallow
#' copied, sharing its column vectors as any R copy does. A data table is
#' copied into a fresh tibble, because a dibble cannot share data.table's
#' self-reference or its over-allocated column slots; keys, indexes, and
#' allocation capacity are left behind. In every case compact Stata numeric
#' and dictionary-string columns stay compact.
#'
#' A dibble needs unique, non-empty column names, because its reference
#' state indexes columns by name. Readers repair names before building one,
#' so only `.name_repair = "minimal"` can produce names a dibble rejects;
#' request `output = "tibble"` for such a read.
#'
#' @param ... For `dibble()`, columns and [tibble::tibble()] options such as
#'   `.rows` and `.name_repair`.
#' @param x For `as_dibble()`, a data frame, tibble, grouped tibble, data
#'   table, or dibble. For `is_dibble()`, any object.
#' @return `dibble()` and `as_dibble()` return a dibble. `is_dibble()`
#'   returns `TRUE` or `FALSE`.
#' @examples
#' survey <- dibble(id = 1:3, income = c(10, 20, 30))
#' is_dibble(survey)
#' gen(survey, adjusted = income * 1.1)
#' survey
#'
#' frame <- as_dibble(data.frame(x = 1:2))
#' grouped <- dplyr::group_by(frame, x)
#' is_dibble(grouped)
#' dplyr::group_vars(grouped)
#' @name dibble
NULL

#' @rdname dibble
#' @export
dibble <- function(...) {
    .as_dibble(tibble::tibble(...))
}

#' @rdname dibble
#' @export
as_dibble <- function(x) {
    if (is_dibble(x)) return(x)
    if (!is.data.frame(x)) {
        stop("`x` must be a data frame, tibble, or data table", call. = FALSE)
    }
    if (inherits(x, "dtatools_ref_data")) {
        # A base data frame that went through gen() carries reference state
        # without being a tibble; its current contents become the dibble.
        x <- .reference_snapshot(x)
    }
    .as_dibble(x)
}

#' @rdname dibble
#' @export
is_dibble <- function(x) {
    if (!inherits(x, "dtatools_ref_data")) return(FALSE)
    state <- .reference_state(x)
    !is.null(state) && "tbl_df" %in% state$classes
}

# Builds the dibble from a data frame carrying no reference state. A grouped
# or rowwise tibble keeps its class, so `state$classes` records the grouping
# and dplyr sees it again on the snapshot. The shallow copy leaves the
# caller's object untouched by the in-place mark.
.as_dibble <- function(x) {
    .reject_data_table_subclass(x, "x")
    x <- if (inherits(x, "tbl_df")) {
        .Call(C_dtatools_metadata_copy, x)
    } else if (inherits(x, "data.table")) {
        .data_table_as_tibble(x)
    } else {
        tibble::as_tibble(x, .name_repair = "minimal")
    }
    names <- attr(x, "names", exact = TRUE)
    if (is.null(names) || anyNA(names) || any(names == "") ||
        anyDuplicated(names) > 0L) {
        stop(
            paste0(
                "a dibble needs unique, non-missing column names; repair ",
                "them first or request `output = \"tibble\"`"
            ),
            call. = FALSE
        )
    }
    .mark_reference_data(x, .new_reference_state(x))
}

# `tibble::as_tibble()` on a data.table goes through data.table's own
# conversion, which materializes compact dictionary-string columns. Building
# the tibble from the bare column list keeps them compact; dataset
# attributes follow, minus data.table's runtime state, which a tibble
# cannot hold.
.data_table_as_tibble <- function(x) {
    columns <- .plain_data_columns(x)
    names(columns) <- attr(x, "names", exact = TRUE)
    result <- tibble::as_tibble(columns, .name_repair = "minimal")
    source_attributes <- attributes(x)
    carried <- setdiff(
        names(source_attributes),
        c("names", "row.names", "class", ".internal.selfref", "sorted",
          "index")
    )
    for (name in carried) attr(result, name) <- source_attributes[[name]]
    result
}
