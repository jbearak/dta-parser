#' Dibbles: Stata datasets with by-reference mutation
#'
#' A dibble is a tibble that is a Stata dataset. It is the default
#' container of [`read_dta()`][dtatools::read_dta], [read_arrow()], and [dta_append()], and the
#' container [dta_merge()] returns for a dibble `x`. `dibble()` builds one
#' from columns with the argument semantics of [tibble::tibble()];
#' `as_dibble()` converts a data frame, tibble, or data table; `is_dibble()`
#' tests for one. Those are the only ways to get one: no operation turns a
#' table you already have into a dibble behind your back.
#'
#' New ungrouped dibbles have class
#' `c("dibble", "dtatools_ref_data", "tbl_df", "tbl", "data.frame")`.
#' Grouping and metadata classes follow `dibble` and shared reference support.
#' The `dibble` class identifies current objects even after bookkeeping or
#' spare capacity is lost. `is_dibble()` also recognizes legacy serialized
#' objects without that class: their reference-state flag must be `TRUE`,
#' or absent with stored tibble classes. An explicit legacy `FALSE` stays
#' ordinary. Prefer `is_dibble()` to exact class comparisons for recognition
#' across package versions. This predicate does not validate ownership or
#' capacity. Assign [reserve_columns()] when preparation is needed.
#' Assigned `as_dibble()`, `copy_data()`, and `reserve_columns()` upgrade
#' legacy dibbles to the current class on a fresh object, leaving aliases
#' and their shared bookkeeping unchanged.
#'
#' [gen()], \code{\link[=replace_values]{replace_values()}}, [keep_vars()],
#' and the other by-reference operations change a prepared dataset in place.
#' Within capacity, every binding sees the change. [gen()] keeps an ordinary
#' tibble or data frame's existing columns unchanged and types only its new
#' column; `is_dibble()` remains `FALSE`. Call `as_dibble()` to type the
#' whole dataset. Conversion does not make function-local replacement reach its caller.
#'
#' A dibble is a Stata dataset held in a tibble, and two invariants follow.
#' Every numeric and string column carries Stata storage: `dibble()` and
#' `as_dibble()` type bare columns by the mapping in
#' [dta-storage-defaults], and so does every operation that adds or
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
#' isolated for later writes, using copy-on-write for compact columns and
#' package-owned ordinary atomic columns.
#' `dplyr::select()`, `dplyr::rename()`, and `dplyr::relocate()` resolve
#' selectors against the actual Stata columns and build their dibble result
#' directly. Owned ordinary doubles, strings, logicals and integer/factor
#' columns share value backing with distinct metadata handles. Borrowed values
#' are captured before sharing. String declarations are checked against backing
#' facts; unchanged owned values need no repeated scan. Unknown or externally
#' writable values are checked again before their declarations are trusted.
#' Ordinary row brackets and [slice_dta_rows()] share batch row gathering with
#' the dplyr row-slicing hook. Package-owned grouping validation and rebuilding
#' retain sorted groups, empty factor groups and rowwise identifiers. Row
#' brackets rebuild groups from selected values; dplyr's row hook remaps the
#' existing group indices and honors its `preserve` argument.
#'
#' Ordinary `$<-`, `[[<-`, `[<-`, `names<-`, `dimnames<-`, and
#' `row.names<-` return a changed dibble and leave existing aliases unchanged.
#' Nested attribute or label replacement follows the same R copy-and-rebind
#' rule, including inside functions. Return and assign that result in the caller.
#' To change a caller's table, use explicit helpers such as [set_var_format()],
#' [set_var_label()], [set_val_labels()], [set_dta_metadata()], [set_dta_note()],
#' and [set_dta_characteristic()], or `gen()`, `repl()`, and dibble `:=`.
#' Replacement results isolate unchanged columns too, so subsequent explicit
#' writes cannot reach the input. Compact columns retain compact backing.
#' A dibble reserves 1,024 spare column slots by default, controlled by
#' `dtatools.alloccol`. By default, [gen()], [egen()] and `:=` rebuild an
#' isolated table when additions need more room and warn that aliases retain
#' the old table. Return the updated table from functions and assign it in
#' the caller. Set `options(dtatools.auto_grow = FALSE)` to require assigned
#' [reserve_columns()] before adding columns. Dropping and other nongrowth
#' structural helpers retain their preparation requirements.
#' [tibble::as_tibble()] returns a tibble snapshot, and `with()` returns
#' its expression's value. `as_dibble()` of a grouped tibble keeps its
#' grouping.
#'
#' Printing and formatting use the heading `# A dibble:` and show declared
#' Stata storage below column names: `byte`, `int`, `long`, `float`, `double`,
#' `str#`, or `strL`. Temporal columns show storage and meaning, such as
#' `float/date` and `double/dttm`. String widths come from the declaration,
#' even for empty columns or values shorter than that width. Logical, factor,
#' and other untyped columns retain their usual tibble type labels. Grouping,
#' cell formatting, missing-value display, and tibble printing options are
#' unchanged. Displaying a dibble leaves its stored columns unchanged.
#'
#' `as_dibble()` returns an ordinary dibble as is. For an additional container
#' subclass it returns a new dibble without that subclass, retaining recognized
#' grouped or rowwise structure and dataset metadata. The removed subclass's
#' invariants are not retained. Otherwise it returns a new object
#' and leaves its argument unchanged: a tibble or data frame is shallow
#' copied. Supported borrowed atomic columns are captured into independent backing;
#' owned atomic and compact columns can share until a write needs to detach
#' them. A data table is
#' copied into a fresh tibble, because a dibble cannot share data.table's
#' self-reference or its over-allocated column slots; keys, indexes, and
#' allocation capacity are left behind. In every case compact Stata numeric
#' and dictionary-string columns stay compact.
#'
#' A dibble needs unique, non-empty column names to identify columns.
#' Readers repair names before building one,
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
#' if (requireNamespace("dplyr", quietly = TRUE)) {
#'   grouped <- dplyr::group_by(frame, x)
#'   is_dibble(grouped)
#'   dplyr::group_vars(grouped)
#' }
#' @seealso [dibble-bracket] for `survey[i, y := value]`, the assignment
#'   shape only a dibble supports; [dta-storage-defaults] for the Stata
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
    if (inherits(x, "dibble") && .supported_mutation_container(x)) return(x)
    if (!is.data.frame(x)) {
        stop("`x` must be a data frame, tibble, or data table", call. = FALSE)
    }
    if (inherits(x, "dtatools_ref_data") && !inherits(x, "data.table")) {
        # A base data frame that went through gen() carries reference state
        # without being a tibble; its current contents become the dibble.
        x <- .reference_snapshot(x)
    }
    .as_dibble(x)
}

#' @rdname dibble
#' @export
is_dibble <- function(x) {
    if (inherits(x, "dibble")) return(TRUE)
    state <- .reference_state(x)
    # Current type identity is independent of ownership and legacy flags.
    # Older serialized objects use the flag in their reference state.
    if (is.null(state)) return(FALSE)
    # Serialized pre-0025 dibbles have no explicit flag. Preserve a stored
    # FALSE on ordinary containers that acquired state through gen().
    if (is.null(state$dibble)) {
        "tbl_df" %in% state$classes
    } else {
        isTRUE(state$dibble)
    }
}

# Builds the dibble from a data frame carrying no reference state. A grouped
# or rowwise tibble keeps its class, so `state$classes` records the grouping
# and dplyr sees it again on the snapshot. The shallow copy leaves the
# caller's object untouched by the in-place mark.
.prepare_dibble_frame <- function(x) {
    if (is.data.frame(x) && !.supported_mutation_container(x)) {
        x <- .metadata_copy(x)
        class(x) <- if (inherits(x, "data.table")) {
            c("data.table", "data.frame")
        } else if (inherits(x, "tbl_df")) {
            c(if (inherits(x, "grouped_df")) "grouped_df" else
                if (inherits(x, "rowwise_df")) "rowwise_df",
              "tbl_df", "tbl", "data.frame")
        } else "data.frame"
        attr(x, ".dtatools_ref_state") <- NULL
    }
    .reject_data_table_subclass(x, "x")
    x <- if (inherits(x, "tbl_df")) {
        .Call(C_dtatools_metadata_copy, x)
    } else if (inherits(x, "data.table")) {
        .data_table_as_tibble(x)
    } else {
        tibble::as_tibble(x, .name_repair = "minimal")
    }
    .validate_dibble_names(x)
    .as_mutation_data(x, allow_grouped = TRUE)
    x
}

.validate_dibble_names <- function(x) {
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
    invisible(NULL)
}

.as_dibble <- function(x, caller = "as_dibble()") {
    x <- .prepare_dibble_frame(x)
    .new_validated_dibble(.type_dibble_columns(x, caller))
}

# Reader-only constructor, after name repair and dataset metadata attachment.
# Native readers supply a rectangular tibble with fresh, privately owned
# column handles. They need neither arbitrary-frame preparation nor capture
# of those handles. Arrow can also supply untyped R columns. Strings still
# need declaration checks: decoding can expand UTF-8 widths, and an Arrow
# declaration need not fit its values. Normalize these through the same
# policy as as_dibble(), capturing only replacement columns.
.new_reader_dibble <- function(x) {
    .validate_dibble_names(x)
    row_count <- nrow(x)
    column_names <- names(x)
    for (index in seq_along(column_names)) {
        column <- .subset2(x, index)
        typed <- .typed_column_named(
            column, row_count, "as_dibble()", column_names[[index]]
        )
        if (!identical(rlang::obj_address(typed), rlang::obj_address(column))) {
            captured <- .Call(C_dtatools_capture_column, typed)
            .Call(C_dtatools_set_data_column, x, as.integer(index), captured)
        }
    }
    .new_validated_dibble(x)
}

# Private constructor. Its caller has checked table shape and normalized every
# column. Validation does not imply isolation; result finalization owns that.
.new_validated_dibble <- function(x) {
    # Spare column slots let `gen()` append in place, so the physical
    # list stays the complete dataset for every reader.
    x <- .reserve_column_capacity(x)
    .mark_reference_data(x, .new_reference_state(x, dibble = TRUE))
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
#' of the assignments after it. `j` is not a general expression.
#' The data.table special symbols `.SD`, `.GRP`, and `.BY` are not provided.
#' Use [dplyr::summarise()] for aggregation that returns one row per group;
#' grouped `gen()` and `:=` instead write results into the existing rows.
#'
#' After automatic growth, a bare target such as `data` is rebound in the
#' calling scope, including when the whole assignment is injected into `j`.
#' A function must return that updated local table and its caller must assign
#' it. With an explicit `:=` call, a plain list or environment target such as
#' `box$data` or `box[["data"]]` is also supported. A base `get()` or `get0()`
#' target needs a literal name and, when supplied, a named environment object.
#' These destinations are captured before assignment-name callbacks; a
#' replaced list or target is not overwritten. Computed extraction indices,
#' custom getters, and extraction targets with a whole-`j` injection return
#' the grown table without rebinding the original target. Assign that result
#' explicitly. Existing aliases retain the old table after growth.
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
#' Without `:=`, brackets return a new dibble holding the selection. Later
#' writes to the source or result leave the other dataset unchanged.
#' In two-dimensional reads, compound row expressions such as `data[x == y, ]`
#' resolve columns first, then caller objects. Use `.env$x` to request a caller
#' object when a column is also named `x`. Expressions run once over the whole
#' table, including grouped and rowwise dibbles. A lone symbol remains a
#' programmatic index: `data[rows, ]` reads `rows` from the caller. Parentheses
#' make `(rows)` a compound expression, so a column named `rows` wins there;
#' `.env$rows` always requests the caller index. The resulting value follows
#' tibble's index rules; returned language is not evaluated again.
#' Missing `i` selects all rows, explicit `NULL` selects none, and logical `NA`
#' produces a padded missing row. Typed strings in padded rows are empty.
#'
#' `data[, .(x, y)]` selects columns in the stated order, and combines with row
#' expressions as `data[x == y, .(x, y)]`. Read `.()` accepts unnamed bare column
#' names or literal strings only. It does not compute or rename columns, and
#' `.()` selects zero columns. For dynamic names, use `data[, cols]` with a
#' character or numeric index. Ordinary indexing such as `data[1, ]`,
#' `data[, "x"]`, and one-dimensional `data["x"]` remains available. These read
#' forms need neither dplyr nor data.table. Assignment retains its separate
#' lookup rules and the dynamic target spelling `.(name) := value`.
#'
#' @param x A dibble.
#' @param i Row selection, as `where` in \code{\link[=replace_values]{replace_values()}}: missing or
#'   `NULL` for every row, a logical expression, or row positions.
#'   Without `:=` in `j`, a whole-table column expression or a caller-supplied
#'   index, following tibble's row rules; explicit `NULL` selects no rows.
#' @param j One or more `:=` assignments, or, without `:=`, ordinary
#'   tibble column indexing or `.()` with unnamed column names or strings.
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
#' survey[income > 20, .(id, income)]
#' cutoff <- 20
#' survey[income > .env$cutoff, .("income", id)]
#' cols <- c("income", "id")
#' survey[, cols]
#' @seealso [dibble], \code{\link[=replace_values]{replace_values()}}
#' @name dibble-bracket
NULL

#' @rdname dibble-bracket
#' @export
`[.dtatools_ref_data` <- function(x, i, j, ..., by = NULL, bysort = NULL,
                                  drop) {
    .validate_mutation_container(x, allow_grouped = TRUE)
    raw_j <- rlang::enquo0(j)
    expression <- if (rlang::quo_is_missing(raw_j)) NULL else rlang::quo_get_expr(raw_j)
    target_expr <- substitute(x)
    destination <- if (is.symbol(target_expr)) target_expr else NULL
    original_x <- x
    if (is.call(expression) && identical(expression[[1L]], quote(`:=`))) {
        # The primitive has forced x, but no assignment-name, quosure, row or
        # grouping callback has run. Snapshot a recoverable destination now.
        destination <- if (is.call(target_expr)) {
            .capture_mutation_binding(target_expr, parent.frame(), value = x)
        } else target_expr
        .require_dibble_assignment(x)
        .as_mutation_data(x, allow_grouped = TRUE, allow_rowwise = FALSE,
                          private_views = TRUE)
    }
    assignments <- .bracket_assignments(rlang::enquo(j), x)
    if (is.null(assignments)) {
        if (!missing(by) || !missing(bysort)) {
            stop("`by` and `bysort` need a `:=` assignment in `j`",
                 call. = FALSE)
        }
        call <- sys.call()
        environment <- parent.frame()
        one_dimension <- (nargs() - !missing(drop)) <= 2L
        return(.reference_bracket(x, call, environment, one_dimension))
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
    .reject_data_table_subclass(x)
    .as_mutation_data(x, allow_grouped = TRUE, allow_rowwise = FALSE,
                      private_views = TRUE)
    # A whole-j injection can retain a bare-symbol destination. Extraction
    # operands were not captured before its callbacks, so those return only.
    auto_grow <- .mutation_auto_grow()
    new_names <- setdiff(vapply(assignments, `[[`, character(1), "name"),
                         .reference_names(x))
    if (length(new_names)) {
        x <- .prepare_column_growth(x, length(x) + length(new_names), auto_grow)
    } else .prepare_column_operation(x, length(x), names_change = FALSE)
    selection <- .mutation_selection(
        x, where,
        by = by_quo,
        bysort = if (missing(bysort)) NULL else rlang::enquo(bysort)
    )
    for (assignment in assignments) {
        # `:=` creates or overwrites, so the target's presence picks the
        # path. Looked up per assignment because an earlier one may have
        # created the column.
        exists <- assignment$name %in% .reference_names(x)
        x <- .mutate_data(
            x, rlang::new_quosure(assignment$name, emptyenv()),
            assignment$values, where, generate = !exists,
            selection = selection, promote = TRUE
        )
        destination <- .rebind_mutation(original_x, x, destination, parent.frame())
        original_x <- x
    }
    # `[` forces its result visible after dispatch, so `invisible()` alone
    # would autoprint the dataset after every assignment. Recorded after
    # the last write so a failed assignment still shows its error only.
    .suppress_bracket_autoprint(x)
    invisible(x)
}

# A reference marker also belongs to ordinary tables after explicit helpers.
# Only dibble type grants the package's bracket mutation syntax.
.require_dibble_assignment <- function(data) {
    if (!is_dibble(data)) {
        stop("`:=` bracket assignment needs a dibble; use `gen()` or `replace_values()`",
             call. = FALSE)
    }
    invisible(NULL)
}

# Reads `j` as one or more `:=` assignments, or `NULL` when `j` is
# missing or not a `:=` call so the ordinary tibble `[` applies. Three
# spellings: `y := v`, with `y` a bare name, string, `.(name)` call, or
# the string `!!name` unquotes to; `` `:=`(y = v, z = w) `` with tagged
# arguments; and `names := list(v, w)`, where `names` is a `c()` call or
# character vector and the right side a `list()` call of the same length.
# Each value becomes a quosure in `j`'s environment so it is evaluated as
# `values` is in `gen()`.
.bracket_assignments <- function(j_quo, data) {
    if (rlang::quo_is_missing(j_quo)) return(NULL)
    expression <- rlang::quo_get_expr(j_quo)
    if (!is.call(expression) || !identical(expression[[1L]], quote(`:=`))) {
        return(NULL)
    }
    # Injection can supply the complete := call, so recheck its container
    # before resolving the expanded expression's runtime targets or values.
    .require_dibble_assignment(data)
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
