#' Merge datasets under Stata missing-code identity
#'
#' `stata_merge()` follows Stata's `merge` command. It matches key columns
#' under Stata missing-code identity: system missing `.` matches only `.`,
#' and each extended missing `.a` through `.z` matches only itself. Base
#' [merge()] and dplyr joins instead place all 27 codes in one R missing
#' bucket. Keys containing R `NaN` are rejected because `NaN` has no Stata
#' missing identity; use `NA_real_` or [tagged_missing()].
#'
#' `x` plays the role of Stata's master dataset and `y` the using dataset.
#' Match results keep Stata's names: a `"master"` row exists only in `x`, a
#' `"using"` row only in `y`, and a `"match"` row in both.
#'
#' The declared merge relationship is required, as in Stata. `"1:1"` requires
#' unique keys on both sides, `"m:1"` unique keys in `y`, and `"1:m"` unique
#' keys in `x`. Duplicate keys on a side that must be unique are an error,
#' and `"m:m"` is not supported.
#'
#' Key columns coalesce into their common Stata storage type through the
#' package's vctrs methods, which promote storage losslessly, keep `x`'s
#' variable label unless it is absent, and combine compatible value-label
#' tables with a warning when one code's text conflicts. Overlapping non-key
#' variables follow Stata's master-wins rule: matched and master-only rows
#' keep the values from `x`, and using-only rows take the values from `y`
#' cast to the common type. There are no suffixed duplicate columns.
#'
#' Every merge generates a `_merge` variable, a `stata_byte` column with
#' Stata's value labels `master only (1)`, `using only (2)`, and
#' `matched (3)`. Merging errors if either input already has a `_merge`
#' column. The result keeps the dataset label and notes from `x`.
#'
#' Unlike Stata, which re-sorts the merged dataset by the key variables, the
#' result keeps `x` rows in their original order followed by unmatched `y`
#' rows in theirs. Sort afterward if key order matters.
#'
#' @param x,y Data frames to merge, or DTA file paths read with
#'   [read_dta()], in any combination. `x` supplies the retained values for
#'   overlapping variables and the dataset label and notes. Passing paths
#'   mirrors Stata's `merge ... using filename` and keeps only the merged
#'   result in the caller's workspace; a path accepts anything `read_dta()`'s
#'   `file` argument accepts as one string, including the implicit `.dta`
#'   extension. Read with [read_dta()] first when a merge needs non-default
#'   read arguments.
#' @param by A character vector naming key columns present in both inputs.
#' @param relationship The declared key multiplicity: `"1:1"`, `"m:1"`, or
#'   `"1:m"`. Required.
#' @param keep Match results to retain: any of `"master"`, `"using"`, and
#'   `"match"`. The default keeps every row, as Stata does.
#' @param assert Optional match results that are allowed to occur. Any other
#'   match result is an error naming the offending rows.
#' @return A tibble with the key columns, the remaining columns of `x`, the
#'   columns only in `y`, and `_merge`, in that order.
#' @examples
#' master <- tibble::tibble(
#'     id = stata_byte(c(1, NA_real_, tagged_missing("a"))),
#'     score = c(10, 20, 30)
#' )
#' using <- tibble::tibble(
#'     id = stata_byte(c(tagged_missing("a"), 7)),
#'     group = c("x", "y")
#' )
#' stata_merge(master, using, by = "id", relationship = "1:1")
#' @export
stata_merge <- function(x, y, by, relationship,
                        keep = c("master", "using", "match"),
                        assert = NULL) {
    x <- .resolve_merge_input(x, "x")
    y <- .resolve_merge_input(y, "y")
    relationship <- .validate_merge_relationship(
        if (missing(relationship)) NULL else relationship
    )
    keep <- .validate_match_results(keep, "keep")
    if (!is.null(assert)) {
        assert <- .validate_match_results(assert, "assert")
    }
    by <- .validate_merge_by(x, y, by)
    for (side in c("x", "y")) {
        if ("_merge" %in% names(get(side, inherits = FALSE))) {
            stop(sprintf(
                "`%s` already has a `_merge` column; rename it first",
                side
            ), call. = FALSE)
        }
    }

    keys <- lapply(by, function(name) {
        prototype <- vctrs::vec_ptype2(
            x[[name]], y[[name]],
            x_arg = paste0("x$", name),
            y_arg = paste0("y$", name)
        )
        list(
            x = vctrs::vec_cast(
                x[[name]], prototype, x_arg = paste0("x$", name)
            ),
            y = vctrs::vec_cast(
                y[[name]], prototype, x_arg = paste0("y$", name)
            )
        )
    })
    names(keys) <- by

    x_proxy <- .stata_merge_key_frame(keys, "x", by)
    y_proxy <- .stata_merge_key_frame(keys, "y", by)
    .validate_merge_uniqueness(x_proxy, y_proxy, relationship)

    matches <- vctrs::vec_locate_matches(
        x_proxy, y_proxy,
        remaining = NA_integer_,
        needles_arg = "x",
        haystack_arg = "y"
    )
    x_rows <- matches$needles
    y_rows <- matches$haystack
    merge_codes <- ifelse(is.na(x_rows), 2, ifelse(is.na(y_rows), 1, 3))

    if (!is.null(assert)) {
        .assert_match_results(merge_codes, assert)
    }
    retained <- merge_codes %in% .match_result_codes(keep)
    if (!all(retained)) {
        x_rows <- x_rows[retained]
        y_rows <- y_rows[retained]
        merge_codes <- merge_codes[retained]
    }

    columns <- list()
    for (name in by) {
        column <- vctrs::vec_slice(keys[[name]]$x, x_rows)
        using_only <- which(is.na(x_rows))
        if (length(using_only) > 0L) {
            column <- vctrs::vec_assign(
                column, using_only,
                vctrs::vec_slice(keys[[name]]$y, y_rows[using_only])
            )
        }
        columns[[name]] <- column
    }
    x_extra <- setdiff(names(x), by)
    overlapping <- intersect(x_extra, names(y))
    for (name in x_extra) {
        if (name %in% overlapping) {
            prototype <- vctrs::vec_ptype2(
                x[[name]], y[[name]],
                x_arg = paste0("x$", name),
                y_arg = paste0("y$", name)
            )
            column <- vctrs::vec_slice(
                vctrs::vec_cast(x[[name]], prototype),
                x_rows
            )
            using_only <- which(is.na(x_rows))
            if (length(using_only) > 0L) {
                column <- vctrs::vec_assign(
                    column, using_only,
                    vctrs::vec_slice(
                        vctrs::vec_cast(y[[name]], prototype),
                        y_rows[using_only]
                    )
                )
            }
            columns[[name]] <- column
        } else {
            columns[[name]] <- vctrs::vec_slice(x[[name]], x_rows)
        }
    }
    for (name in setdiff(names(y), c(by, overlapping))) {
        columns[[name]] <- vctrs::vec_slice(y[[name]], y_rows)
    }
    indicator <- stata_byte(merge_codes)
    val_labels(indicator) <- c(
        "master only (1)" = 1,
        "using only (2)" = 2,
        "matched (3)" = 3
    )
    columns[["_merge"]] <- indicator

    result <- tibble::new_tibble(columns, nrow = length(merge_codes))
    dataset_label(result) <- dataset_label(x)
    notes <- attr(x, "notes", exact = TRUE)
    if (!is.null(notes)) attr(result, "notes") <- notes
    result
}

.resolve_merge_input <- function(value, side) {
    if (is.data.frame(value)) return(value)
    if (is.character(value) && length(value) == 1L && !is.na(value)) {
        return(read_dta(value))
    }
    stop(sprintf("`%s` must be a data frame or one DTA file path", side),
         call. = FALSE)
}

.merge_match_results <- c(master = 1, using = 2, match = 3)

.merge_result_labels <- c(
    "master only (1)", "using only (2)", "matched (3)"
)

.match_result_codes <- function(results) {
    unname(.merge_match_results[results])
}

.validate_merge_relationship <- function(relationship) {
    if (identical(relationship, "m:m")) {
        stop(
            paste0(
                "`relationship = \"m:m\"` is not supported; a many-to-many ",
                "merge crosses duplicate keys and is almost always a mistake"
            ),
            call. = FALSE
        )
    }
    if (!is.character(relationship) || length(relationship) != 1L ||
        is.na(relationship) ||
        !relationship %in% c("1:1", "m:1", "1:m")) {
        stop("`relationship` must be \"1:1\", \"m:1\", or \"1:m\"",
             call. = FALSE)
    }
    relationship
}

.validate_match_results <- function(results, argument) {
    if (!is.character(results) || length(results) == 0L ||
        anyNA(results) || anyDuplicated(results) ||
        !all(results %in% names(.merge_match_results))) {
        stop(sprintf(
            "`%s` values must be \"master\", \"using\", or \"match\"",
            argument
        ), call. = FALSE)
    }
    results
}

.validate_merge_by <- function(x, y, by) {
    if (missing(by) || !is.character(by) || length(by) == 0L ||
        anyNA(by) || anyDuplicated(by) || any(by == "")) {
        stop("`by` must name at least one key column present in both inputs",
             call. = FALSE)
    }
    for (side in c("x", "y")) {
        data <- if (identical(side, "x")) x else y
        unknown <- setdiff(by, names(data))
        if (length(unknown) > 0L) {
            stop(sprintf(
                "`by` column%s not found in `%s`: %s",
                if (length(unknown) == 1L) "" else "s",
                side,
                paste(unknown, collapse = ", ")
            ), call. = FALSE)
        }
    }
    by
}

# The tag-preserving equality proxy: a double key column becomes an observed
# value plus its Stata missing code, so `.` and `.a` through `.z` match only
# themselves while every observed value compares numerically.
.stata_merge_key_proxy <- function(key, arg) {
    if (typeof(key) != "double") {
        return(list(value = key))
    }
    values <- as.double(key)
    codes <- .tab_missing_codes(values)
    observed <- is.na(codes)
    if (any(codes[!observed] == 256L)) {
        stop(sprintf(
            paste0(
                "`%s` contains NaN, which has no Stata missing identity; ",
                "use `NA_real_` or `tagged_missing()`"
            ),
            arg
        ), call. = FALSE)
    }
    values[!observed] <- NA_real_
    codes[observed] <- -1L
    list(value = values, code = codes)
}

.stata_merge_key_frame <- function(keys, side, by) {
    columns <- list()
    for (name in by) {
        proxy <- .stata_merge_key_proxy(
            keys[[name]][[side]], paste0(side, "$", name)
        )
        names(proxy) <- paste0(name, "..", names(proxy))
        columns <- c(columns, proxy)
    }
    vctrs::new_data_frame(columns)
}

.validate_merge_uniqueness <- function(x_proxy, y_proxy, relationship) {
    unique_sides <- switch(relationship,
        "1:1" = c("x", "y"),
        "m:1" = "y",
        "1:m" = "x"
    )
    for (side in unique_sides) {
        proxy <- if (identical(side, "x")) x_proxy else y_proxy
        if (vctrs::vec_duplicate_any(proxy)) {
            stop(sprintf(
                "`relationship = \"%s\"` requires unique keys in `%s`",
                relationship, side
            ), call. = FALSE)
        }
    }
    invisible(NULL)
}

.assert_match_results <- function(merge_codes, assert) {
    allowed <- .match_result_codes(assert)
    violations <- setdiff(unique(merge_codes), allowed)
    if (length(violations) == 0L) return(invisible(NULL))

    counts <- vapply(
        sort(violations),
        function(code) sum(merge_codes == code),
        double(1)
    )
    descriptions <- sprintf(
        "%d %s", counts, .merge_result_labels[sort(violations)]
    )
    stop(sprintf(
        "`assert` failed; disallowed match results: %s",
        paste(descriptions, collapse = ", ")
    ), call. = FALSE)
}
