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
#' Reference state is what lets [gen()], \code{\link[=replace_values]{replace_values()}}, [keep_vars()],
#' and the other by-reference operations change a dataset in place so that
#' every binding to it sees the change. On a plain tibble the first `gen()`
#' attaches that state, so a dibble and a tibble that has been through
#' `gen()` are the same kind of object: `is_dibble()` is `TRUE` for both,
#' and `gen()` on a plain tibble is one way to obtain a dibble.
#'
#' A dibble is a Stata dataset held in a tibble, and two invariants follow.
#' Every numeric and string column carries Stata storage: `dibble()` and
#' `as_dibble()` type bare columns by the mapping in
#' [stata-storage-defaults], and so does every operation that adds or
#' changes a column, including [dplyr::mutate()], `transform()`, and the
#' replacement operators `$<-`, `[[<-`, and `[<-`. Logical columns stay
#' logical and factors stay factors. And every dataset operation on a
#' dibble returns a dibble: dplyr verbs, joins with a dibble on the left,
#' `bind_rows()` with a dibble first, base `subset()`, `transform()`,
#' `within()`, `head()`, `rbind()`, `cbind()`, and `[` subsetting. Each
#' result is a fresh object holding the current contents; the input is
#' unchanged, and a by-reference write on either the input or the result
#' leaves the other as it was, and leaves any other frame the operation
#' drew columns from as it was. Columns an operation leaves alone are
#' shared copy-on-write, so compact columns stay compact.
#'
#' The replacement operators are the exception: `$<-`, `[[<-`, `[<-`,
#' `names<-`, `dimnames<-`, and `row.names<-` on a dibble write by
#' reference, as [gen()], \code{\link[=replace_values]{replace_values()}}, and `:=` do, so every binding
#' to the dataset sees the change and a replacement inside a function
#' reaches the caller's dibble. Because R
#' spells `var_label(data$x) <- "Age"` as a `$<-` call, every metadata
#' setter used in replacement form is by reference on a dibble too:
#' [var_label<-], [val_labels<-], and `attr<-` on `format.stata`, notes, or
#' characteristics. A vector assigned in is copied on its first write, so
#' the frame it came from is never reached. Use [copy_data()] for an
#' independent dataset and [tibble::as_tibble()] for a copy with R's
#' semantics. On a tibble or data frame that is not a dibble the operators
#' keep R's copy-on-modify behaviour. A dibble is built with spare capacity
#' for 256 more columns, so [gen()] appends to its column list in place
#' and `bind_rows()`, `bind_cols()`, and other consumers that read the
#' list directly see every column; past that capacity, and on a tibble
#' that became a dibble at its first `gen()`, such consumers need
#' [tibble::as_tibble()], as documented under [gen()].
#' [tibble::as_tibble()] returns a tibble snapshot, and `with()` returns
#' its expression's value. `as_dibble()` of a grouped tibble keeps its
#' grouping.
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
#' @seealso [dibble-bracket] for `survey[i, y := value]`, the assignment
#'   shape only a dibble supports; [stata-storage-defaults] for the Stata
#'   storage a dibble gives its columns.
#' @name dibble
NULL

#' @rdname dibble
#' @export
dibble <- function(...) {
    .as_dibble(tibble::tibble(...), "dibble()")
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
.as_dibble <- function(x, caller = "as_dibble()") {
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
    x <- .type_dibble_columns(x, caller)
    # Spare column slots let `gen()` append in place, so the physical
    # list stays the complete dataset for every reader.
    x <- .reserve_column_capacity(x)
    .mark_reference_data(x, .new_reference_state(x))
}

# `tibble::as_tibble()` on a data.table goes through data.table's own
# conversion, which materializes compact dictionary-string columns. Building
# the tibble from the bare column list keeps them compact; dataset
# attributes follow, minus data.table's runtime state, which a tibble
# cannot hold. The columns are deep-copied rather than shared: a later
# by-reference replacement through the dibble would otherwise rewrite the
# data.table's own vectors while its key and index attributes still
# describe the old values, so a keyed lookup could return the wrong rows.
# `.deep_copy_value()` keeps compact columns compact.
.data_table_as_tibble <- function(x) {
    columns <- lapply(.plain_data_columns(x), .deep_copy_value)
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

#' Bracket mutation on a dibble
#'
#' A dibble supports data.table's assignment shape, `data[i, j, by]`, with
#' `j` one or more `:=` assignments:
#' `data[income > 20, adjusted := income * 1.1]`. The assignment happens by
#' reference, as with [gen()] and \code{\link[=replace_values]{replace_values()}}, and the call returns
#' the dibble so brackets chain:
#' `data[i, y := 1][j, z := 2]`. Because `[` always makes its result
#' visible, the dataset would print after every assignment; as data.table
#' does, the next top-level print of the mutated dataset is skipped, so an
#' assignment typed at the console prints nothing and `data` on the
#' following line prints as usual. The skip lasts only for the statement
#' that made the assignment: after `result <- data[i, y := 1]`, a loop, or
#' `invisible(data[i, y := 1])`, nothing is skipped. Only a dibble has this
#' form. dtatools cannot own `[` on a plain data frame or tibble, and a
#' data table's own `:=` has different storage, missing-value, and
#' type-promotion semantics, so on those containers `[i, y := 1]` is
#' whatever error their `[` raises; use `gen()` or `replace_values()`,
#' which accept every supported container.
#'
#' `i` is `where`: `NULL` or missing selects every row, and a logical
#' expression or numeric row positions follow the rules of
#' \code{\link[=replace_values]{replace_values()}}, including the shadow check and the `.n`/`.N` mask
#' variables. Each right-hand side of `:=` is `values`, evaluated in the
#' same data mask. Unlike `gen()`, which refuses an existing name, and
#' `replace_values()`, which refuses a new one, `:=` creates a column that
#' is absent and overwrites one that exists, as a user of the data.table
#' shape expects; a new column takes `gen()`'s storage rules, including
#' Stata's `generate` default of `float` for a bare double, and an existing
#' one is promoted from its storage as [dplyr::mutate()] does, so a
#' declared `dta_*()` target widens only when the values do not fit.
#' `data[i, y := 1]` is otherwise `repl(data, y = 1, where = i)` or
#' `gen(data, y = 1, where = i)`.
#'
#' `j` may carry several assignments: `` `:=`(y = v, z = w) ``, or
#' `c("y", "z") := list(v, w)` with one value expression per name. Names
#' follow `gen()`'s tag rules, so `.(name) := v` and `!!name := v` name a
#' column held in a string, and a plain string works too: `"y" := v`.
#' Assignments apply left to right, each seeing the columns the previous
#' one wrote, and each commits or fails on its own, so a failed second
#' column leaves the first written, as two Stata lines would. Rows are
#' selected once for the whole `j`, before any assignment writes: a later
#' assignment cannot change which rows an earlier one selected, and an
#' assignment that overwrites the column `i` reads does not move the rows
#' of the assignments after it. `j` is not a general expression, and
#' `.SD`, `.GRP`, and `.BY` are not provided; summaries stay with dplyr.
#'
#' `by` may also be given positionally, as data.table's third slot:
#' `data[, total := sum(x), id]` is `data[, total := sum(x), by = id]`.
#'
#' `by`, `bysort`, and a grouped dibble behave exactly as in
#' \code{\link[=replace_values]{replace_values()}}: groups are formed first, then `i` and each value
#' are evaluated on each group's rows, which is Stata's `by varlist:`
#' order rather than data.table's; see the group-wise assignment section
#' there for `.n`/`.N`, sorting, and the `by`-plus-grouped error. Under
#' groups, several assignments run column by column across all groups, so
#' `.n` and `.N` are the same in every assignment of one call. `by` or
#' `bysort` without a `:=` in `j` is an error.
#'
#' Without `:=` the brackets are ordinary tibble subsetting of the current
#' contents: `data[1, ]`, `data[, "x"]`, `data["x"]`, and `data[i, cols]`
#' return a new dibble holding the selection, following copy-on-modify.
#'
#' @param x A dibble.
#' @param i Row selection, as `where` in \code{\link[=replace_values]{replace_values()}}: missing or
#'   `NULL` for every row, a logical expression, or row positions.
#'   Without `:=` in `j`, ordinary tibble row indexing.
#' @param j One or more `:=` assignments, or, without `:=`, ordinary
#'   tibble column indexing.
#' @param ... Passed to tibble's `[` when `j` is not an assignment.
#'   Not allowed otherwise.
#' @param by,bysort Assignment groups, as in \code{\link[=replace_values]{replace_values()}}. Only
#'   allowed with a `:=` in `j`.
#' @param drop Passed to tibble's `[` when `j` is not an assignment.
#' @return With a `:=` in `j`, `x` invisibly, mutated. Otherwise the
#'   tibble subset.
#' @examples
#' survey <- dibble(id = 1:4, income = c(10, 20, 30, 40))
#' survey[income > 20, adjusted := income * 1.1]
#' survey[, adjusted := 0][id == 1, adjusted := 1]
#' survey[, `:=`(rows = .N, last = .n == .N), by = id]
#' survey[, first := .n == 1, id]
#' survey[, c("a", "b") := list(id * 2, id * 3)]
#' name <- "flag"
#' survey[id > 2, .(name) := TRUE]
#' survey[1, ]
#' @seealso [dibble], \code{\link[=replace_values]{replace_values()}}
#' @name dibble-bracket
NULL

#' @rdname dibble-bracket
#' @export
`[.dtatools_ref_data` <- function(x, i, j, ..., by = NULL, bysort = NULL,
                                  drop) {
    assignments <- .bracket_assignments(rlang::enquo(j))
    if (is.null(assignments)) {
        if (!missing(by) || !missing(bysort)) {
            stop("`by` and `bysort` need a `:=` assignment in `j`",
                 call. = FALSE)
        }
        # Ordinary subsetting: hand the snapshot to tibble's `[` with the
        # original call, so `data[i]`, `data[, j]`, and `drop` all keep
        # tibble's meaning and its own errors.
        call <- sys.call()
        call[[1L]] <- quote(`[`)
        call[[2L]] <- .reference_snapshot(x)
        return(.close_dibble(x, eval(call, parent.frame())))
    }
    # data.table's third slot is `by`, so `data[i, j, id]` puts `id` in
    # `...`; one unnamed dot is that positional `by`.
    dots <- rlang::enquos(...)
    by_quo <- if (missing(by)) NULL else rlang::enquo(by)
    positional_by <- length(dots) == 1L && !nzchar(names(dots)[[1L]]) &&
        is.null(by_quo)
    if (positional_by) {
        by_quo <- dots[[1L]]
    } else if (length(dots) > 0L || !missing(drop)) {
        stop("`[` with `:=` takes `i`, `j`, `by`, and `bysort` only",
             call. = FALSE)
    }
    where <- if (missing(i)) {
        rlang::new_quosure(NULL, emptyenv())
    } else {
        rlang::enquo(i)
    }
    selection <- .mutation_selection(
        x, where,
        by = by_quo,
        bysort = if (missing(bysort)) NULL else rlang::enquo(bysort)
    )
    for (assignment in assignments) {
        # `:=` creates or overwrites, so the target's presence picks the
        # path. Looked up per assignment because an earlier one may have
        # created the column.
        exists <- .has_mutation_column(
            .as_mutation_data(x, allow_grouped = TRUE)$columns,
            assignment$name
        )
        .mutate_data(
            x, rlang::new_quosure(assignment$name, emptyenv()),
            assignment$values, where, generate = !exists,
            selection = selection, promote = TRUE
        )
    }
    # `[` forces its result visible after dispatch, so `invisible()` alone
    # would autoprint the dataset after every assignment. Recorded after
    # the last write so a failed assignment still shows its error only.
    .suppress_bracket_autoprint(x)
    invisible(x)
}

# Reads `j` as one or more `:=` assignments, or `NULL` when `j` is
# missing or not a `:=` call so the ordinary tibble `[` applies. Three
# spellings: `y := v`, with `y` a bare name, string, `.(name)` call, or
# the string `!!name` unquotes to; `` `:=`(y = v, z = w) `` with tagged
# arguments; and `names := list(v, w)`, where `names` is a `c()` call or
# character vector and the right side a `list()` call of the same length.
# Each value becomes a quosure in `j`'s environment so it is evaluated as
# `values` is in `gen()`.
.bracket_assignments <- function(j_quo) {
    if (rlang::quo_is_missing(j_quo)) return(NULL)
    expression <- rlang::quo_get_expr(j_quo)
    if (!is.call(expression) || !identical(expression[[1L]], quote(`:=`))) {
        return(NULL)
    }
    environment <- rlang::quo_get_env(j_quo)
    arguments <- as.list(expression)[-1L]
    tags <- names(arguments)
    if (is.null(tags)) tags <- rep("", length(arguments))
    value_quosure <- function(value) {
        if (identical(value, quote(expr = ))) {
            stop("`:=` needs a value for every column", call. = FALSE)
        }
        rlang::new_quosure(value, environment)
    }
    if (any(nzchar(tags))) {
        if (!all(nzchar(tags))) {
            stop("`:=` mixes tagged and untagged arguments", call. = FALSE)
        }
        if (anyDuplicated(tags) > 0L) {
            stop("`:=` names each column once", call. = FALSE)
        }
        return(lapply(seq_along(arguments), function(index) {
            list(
                name = .validated_runtime_name(tags[[index]]),
                values = value_quosure(arguments[[index]])
            )
        }))
    }
    if (length(arguments) != 2L) {
        stop("`:=` takes one left-hand side and one right-hand side",
             call. = FALSE)
    }
    left <- arguments[[1L]]
    right <- arguments[[2L]]
    names <- .bracket_target_names(left, environment)
    # The left-hand shape picks the form: a `c()` call or a vector of
    # several names pairs with `list()`, and anything else takes the
    # whole right-hand side as one value expression, so `y := list(x)`
    # is not mistaken for the multi-column form.
    multiple <- .bracket_is_call_to(left, "c") ||
        (is.character(left) && length(left) > 1L)
    if (!multiple) {
        return(list(list(name = names, values = value_quosure(right))))
    }
    if (!.bracket_is_call_to(right, "list") ||
        length(right) - 1L != length(names)) {
        stop(sprintf(
            "`%s :=` needs `list()` of %d value expressions on the right",
            paste(deparse(left), collapse = " "), length(names)
        ), call. = FALSE)
    }
    if (!is.null(names(right)) && any(nzchar(names(right)))) {
        stop("the `list()` of `:=` values takes no names", call. = FALSE)
    }
    values <- as.list(right)[-1L]
    lapply(seq_along(names), function(index) {
        list(name = names[[index]], values = value_quosure(values[[index]]))
    })
}

# The left-hand side of an untagged `:=`: `gen()`'s target rules extended
# to a character vector or a `c()` of names for the multi-column form.
.bracket_target_names <- function(left, environment) {
    message <- paste(
        "the left of `:=` must be one column name or `c()` of names: a",
        "bare name, a string, `!!name`, or `.(name)`"
    )
    if (is.symbol(left)) {
        if (identical(left, quote(...))) stop(message, call. = FALSE)
        return(as.character(left))
    }
    if (is.character(left)) {
        if (length(left) == 0L || anyNA(left) || !all(nzchar(left))) {
            stop(message, call. = FALSE)
        }
        names <- left
    } else if (.is_runtime_name_call(left)) {
        return(.runtime_name_call_value(left, environment))
    } else if (.bracket_is_call_to(left, "c")) {
        parts <- as.list(left)[-1L]
        if (length(parts) == 0L) stop(message, call. = FALSE)
        names <- unlist(lapply(parts, function(part) {
            if (.bracket_is_call_to(part, "c")) stop(message, call. = FALSE)
            .bracket_target_names(part, environment)
        }), use.names = FALSE)
    } else {
        stop(message, call. = FALSE)
    }
    if (anyDuplicated(names) > 0L) {
        stop("`:=` names each column once", call. = FALSE)
    }
    names
}

.bracket_is_call_to <- function(expression, name) {
    is.call(expression) &&
        .selection_call_is(expression[[1L]], name, "base")
}
