#' Resolve or confirm a Stata variable reference
#'
#' `resolve_var_name()` resolves one variable reference against the current
#' names of `data`. It returns the physical column name. `confirm_var()` checks
#' the same reference and returns a logical value. It throws an error by
#' default, like Stata's uncaptured `confirm variable` command.
#'
#' Both functions prefer an exact match. Otherwise, when `exact = FALSE`, a
#' prefix resolves only if it identifies one column. No match and an ambiguous
#' prefix are failures. `exact = TRUE` corresponds to Stata's `, exact` option
#' and disables abbreviation.
#'
#' Use `confirm_var(..., on_failure = "false")` for the control-flow role of
#' Stata's `capture confirm variable`: failures return `FALSE` without a
#' warning. Use `resolve_var_name(..., on_failure = "error")` when resolution
#' failures should stop execution.
#'
#' @param data A data frame, tibble, data table, or `dtatools_ref_data`.
#' @param name One nonempty, non-missing character string.
#' @param exact If `TRUE`, require an exact column name and do not resolve
#'   abbreviations.
#' @param on_failure Failure policy. `resolve_var_name()` accepts `"missing"`
#'   or `"error"`; `confirm_var()` accepts `"error"` or `"false"`.
#'
#' @return `resolve_var_name()` returns one character value: the physical
#'   column name on success or `NA_character_` when `on_failure = "missing"`.
#'   `confirm_var()` returns `TRUE` on success or `FALSE` when
#'   `on_failure = "false"`. Error policies throw a typed condition instead.
#'
#' @examples
#' survey <- data.frame(identifier = 1:2, income = c(10, 20))
#' resolve_var_name(survey, "ident")
#' confirm_var(survey, "income")
#' confirm_var(survey, "missing", on_failure = "false")
#'
#' @export
resolve_var_name <- function(
    data,
    name,
    exact = FALSE,
    on_failure = c("missing", "error")
) {
    .validate_variable_reference_args(data, name, exact)
    on_failure <- rlang::arg_match(on_failure)

    column_names <- names(data)
    exact_locations <- which(column_names == name)
    if (length(exact_locations) == 1L) {
        return(column_names[[exact_locations]])
    }

    candidates <- if (length(exact_locations) > 1L) {
        column_names[exact_locations]
    } else if (!exact) {
        column_names[which(startsWith(column_names, name))]
    } else {
        character()
    }

    if (length(candidates) == 1L) return(candidates[[1L]])
    if (on_failure == "missing") return(NA_character_)

    if (length(candidates) == 0L) {
        rlang::abort(
            sprintf("Variable `%s` not found", name),
            class = c(
                "dtatools_variable_not_found_error",
                "dtatools_variable_resolution_error"
            ),
            name = name
        )
    }
    rlang::abort(
        sprintf(
            "Variable reference `%s` is ambiguous; matches: %s",
            name,
            paste(candidates, collapse = ", ")
        ),
        class = c(
            "dtatools_ambiguous_variable_error",
            "dtatools_variable_resolution_error"
        ),
        name = name,
        candidates = candidates
    )
}

#' @rdname resolve_var_name
#' @export
confirm_var <- function(
    data,
    name,
    exact = FALSE,
    on_failure = c("error", "false")
) {
    on_failure <- rlang::arg_match(on_failure)
    resolved <- resolve_var_name(
        data,
        name,
        exact = exact,
        on_failure = if (on_failure == "error") "error" else "missing"
    )
    !is.na(resolved)
}

.validate_variable_reference_args <- function(data, name, exact) {
    if (!inherits(data, "data.frame")) {
        rlang::abort("`data` must be a data frame, tibble, or data table")
    }
    if (!is.character(name) || length(name) != 1L || is.na(name) ||
        !nzchar(name)) {
        rlang::abort("`name` must be one nonempty, non-missing string")
    }
    if (!is.logical(exact) || length(exact) != 1L || is.na(exact)) {
        rlang::abort("`exact` must be `TRUE` or `FALSE`")
    }
    invisible(NULL)
}
