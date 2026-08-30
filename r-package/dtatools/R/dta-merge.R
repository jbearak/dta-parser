#' Merge DTA datasets under Stata missing-code identity
#'
#' `dta_merge()` follows Stata's `merge` command. It matches key columns
#' under Stata missing-code identity: system missing `.` matches only `.`,
#' and each extended missing `.a` through `.z` matches only itself. Base
#' [merge()] and dplyr joins instead place all 27 codes in one R missing
#' bucket. Keys containing R `NaN` are rejected because `NaN` has no Stata
#' missing identity; use `NA_real_` or [tagged_missing()].
#' Character keys containing `NA_character_` are also rejected because Stata
#' has only the empty string for a missing string; use `""` instead.
#'
#' `x` plays the role of Stata's master dataset and `y` the using dataset.
#' Match results are named `"x"` (a row only in `x`), `"y"` (a row only in
#' `y`), and `"match"` (a row in both). `"master"` and `"using"` are
#' permanent aliases for `"x"` and `"y"`, matching Stata's vocabulary.
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
#' cast to the common type. There are no suffixed duplicate columns. Stata
#' applies this rule silently; `dta_merge()` warns and names the
#' overlapping variables, because the `y` values for matched rows are
#' discarded whether or not they agree with `x`. When the inputs disagree
#' on a coalesced variable's variable label or value-label table (keys
#' included), an additional warning names those variables, since the
#' resolution keeps `x`'s side and Stata would say nothing.
#'
#' Every merge generates a `_merge` variable, a `stata_byte` column using
#' Stata's `_merge` codes with value labels `x only (1)`, `y only (2)`, and
#' `matched (3)`. Merging errors if either input already has a `_merge`
#' column. The result keeps the dataset label and notes from `x`.
#'
#' Unlike Stata, which re-sorts the merged dataset by the key variables, the
#' result keeps `x` rows in their original order followed by unmatched `y`
#' rows in theirs. Sort afterward if key order matters.
#'
#' @param x,y Data frames to merge, or file paths read with [read_dta()] or
#'   [read_arrow()], in any combination. `x` supplies the retained values for
#'   overlapping variables and the dataset label and notes. Passing paths
#'   mirrors Stata's `merge ... using filename` and keeps only the merged
#'   result in the caller's workspace. A path ending in `.arrow` is read with
#'   [read_arrow()]; any other path, including an extensionless one with the
#'   implicit `.dta` extension, accepts anything `read_dta()`'s `file`
#'   argument accepts as one string. Read the file first when a merge needs
#'   non-default read arguments. Data-frame inputs must have unique,
#'   non-missing, nonempty column names.
#' @param by A character vector naming key columns present in both inputs.
#' @param relationship The declared key multiplicity: `"1:1"`, `"m:1"`, or
#'   `"1:m"`. Required.
#' @param keep Match results to retain: any of `"x"`, `"y"`, and `"match"`,
#'   with `"master"` and `"using"` accepted as aliases for `"x"` and `"y"`.
#'   The default keeps every row, as Stata does.
#' @param assert Optional match results that are allowed to occur, using the
#'   same names as `keep`. Any other match result is an error naming each
#'   disallowed match result and its row count.
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
#' dta_merge(master, using, by = "id", relationship = "1:1")
#' @export
dta_merge <- function(x, y, by, relationship,
                      keep = c("x", "y", "match"),
                      assert = NULL) {
    x <- .resolve_merge_input(x, "x")
    y <- .resolve_merge_input(y, "y")
    .validate_merge_input_names(x, "x")
    .validate_merge_input_names(y, "y")
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
            x = .dta_merge_cast(x[[name]], prototype, paste0("x$", name)),
            y = .dta_merge_cast(y[[name]], prototype, paste0("y$", name))
        )
    })
    names(keys) <- by

    proxies <- .dta_merge_key_frames(keys, by)
    matches <- tryCatch(
        vctrs::vec_locate_matches(
            proxies$x, proxies$y,
            remaining = NA_integer_,
            relationship = .merge_vctrs_relationships[[relationship]],
            needles_arg = "x",
            haystack_arg = "y"
        ),
        vctrs_error_matches_relationship = function(condition) {
            stop(sprintf(
                "`relationship = \"%s\"` requires unique keys in `%s`",
                relationship, .merge_duplicated_side(condition)
            ), call. = FALSE)
        }
    )
    x_rows <- matches$needles
    y_rows <- matches$haystack
    .validate_unmatched_duplicates(proxies, x_rows, y_rows, relationship)
    merge_codes <- rep(3, length(x_rows))
    merge_codes[is.na(y_rows)] <- 1
    merge_codes[is.na(x_rows)] <- 2

    if (!is.null(assert)) {
        .assert_match_results(merge_codes, assert)
    }
    keep_codes <- .match_result_codes(keep)
    if (length(setdiff(c(1, 2, 3), keep_codes)) > 0L) {
        retained <- merge_codes %in% keep_codes
        if (!all(retained)) {
            x_rows <- x_rows[retained]
            y_rows <- y_rows[retained]
            merge_codes <- merge_codes[retained]
        }
    }
    using_only <- which(is.na(x_rows))

    columns <- list()
    for (name in by) {
        column <- .dta_merge_coalesce(
            keys[[name]]$x, keys[[name]]$y,
            x_rows, y_rows, using_only
        )
        columns[[name]] <- .dta_merge_reconcile_variable_label(
            column, x[[name]], y[[name]]
        )
    }
    x_extra <- setdiff(names(x), by)
    overlapping <- intersect(x_extra, names(y))
    if (length(overlapping) > 0L) {
        warning(sprintf(
            paste0(
                "%d variable%s in both inputs besides the keys; matched ",
                "rows keep the `x` values: %s"
            ),
            length(overlapping),
            if (length(overlapping) == 1L) " is" else "s are",
            .listed_variable_names(overlapping)
        ), call. = FALSE)
    }
    .warn_coalesced_metadata(x, y, c(by, overlapping))

    x_only <- setdiff(x_extra, overlapping)
    y_only <- setdiff(names(y), c(by, overlapping))
    x_only_columns <- .dta_merge_slice_columns(x[x_only], x_rows)
    y_only_columns <- .dta_merge_slice_columns(y[y_only], y_rows)
    overlap_x <- overlap_prototypes <- vector(
        "list", length(overlapping)
    )
    names(overlap_x) <- names(overlap_prototypes) <- overlapping
    for (name in overlapping) {
        prototype <- vctrs::vec_ptype2(
            x[[name]], y[[name]],
            x_arg = paste0("x$", name),
            y_arg = paste0("y$", name)
        )
        overlap_prototypes[[name]] <- prototype
        overlap_x[[name]] <- .dta_merge_cast(
            x[[name]], prototype, paste0("x$", name)
        )
    }
    overlap_columns <- .dta_merge_coalesce_columns(
        overlap_x, y[overlapping],
        x_rows, y_rows, using_only, overlap_prototypes
    )
    for (name in overlapping) {
        overlap_columns[[name]] <- .dta_merge_reconcile_variable_label(
            overlap_columns[[name]], x[[name]], y[[name]]
        )
    }
    for (name in x_extra) {
        columns[[name]] <- if (name %in% overlapping) {
            overlap_columns[[name]]
        } else {
            x_only_columns[[name]]
        }
    }
    for (name in y_only) {
        columns[[name]] <- y_only_columns[[name]]
    }
    indicator <- stata_byte(merge_codes)
    val_labels(indicator) <- c(
        "x only (1)" = 1,
        "y only (2)" = 2,
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
        extension <- .data_source_file_extension(value)
        if (identical(extension, "arrow")) return(read_arrow(value))
        return(read_dta(value))
    }
    stop(sprintf(
        "`%s` must be a data frame or one DTA or Arrow file path", side
    ), call. = FALSE)
}

.validate_merge_input_names <- function(data, side) {
    column_names <- names(data)
    if (length(column_names) != ncol(data) || anyNA(column_names) ||
        any(column_names == "") || anyDuplicated(column_names)) {
        stop(sprintf(
            "`%s` must have unique, non-missing, nonempty column names",
            side
        ), call. = FALSE)
    }
    invisible(NULL)
}

.merge_match_results <- c(
    x = 1, y = 2, master = 1, using = 2, match = 3
)

.merge_result_labels <- c(
    "x only (1)", "y only (2)", "matched (3)"
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
    valid <- is.character(results) && length(results) > 0L &&
        !anyNA(results) && all(results %in% names(.merge_match_results))
    if (valid && anyDuplicated(.merge_match_results[results])) {
        valid <- FALSE
    }
    if (!valid) {
        stop(sprintf(
            paste0(
                "`%s` values must be \"x\", \"y\", or \"match\", without ",
                "repeating a match result; \"master\" and \"using\" are ",
                "aliases for \"x\" and \"y\""
            ),
            argument
        ), call. = FALSE)
    }
    results
}

.listed_variable_names <- function(names) {
    shown <- names[seq_len(min(5L, length(names)))]
    listed <- paste(shown, collapse = ", ")
    if (length(names) > length(shown)) {
        listed <- sprintf(
            "%s, and %d more", listed, length(names) - length(shown)
        )
    }
    listed
}

.normalized_value_labels <- function(column) {
    labels <- val_labels(column)
    if (is.null(labels) || length(labels) == 0L) {
        return(NULL)
    }
    labels[order(unname(labels), names(labels))]
}

# Coalescing keeps one column per variable, so metadata the two inputs
# disagree on is silently resolved; Stata says nothing, we warn.
.warn_coalesced_metadata <- function(x, y, coalesced) {
    var_label_diff <- character()
    val_label_diff <- character()
    for (name in coalesced) {
        x_label <- var_label(x[[name]])
        y_label <- var_label(y[[name]])
        if (!is.null(x_label) && !is.null(y_label) &&
            !identical(x_label, y_label)) {
            var_label_diff <- c(var_label_diff, name)
        }
        if (!identical(
            .normalized_value_labels(x[[name]]),
            .normalized_value_labels(y[[name]])
        )) {
            val_label_diff <- c(val_label_diff, name)
        }
    }
    if (length(var_label_diff) > 0L) {
        warning(sprintf(
            paste0(
                "variable labels differ for %d coalesced variable%s; ",
                "the `x` labels win: %s"
            ),
            length(var_label_diff),
            if (length(var_label_diff) == 1L) "" else "s",
            .listed_variable_names(var_label_diff)
        ), call. = FALSE)
    }
    if (length(val_label_diff) > 0L) {
        warning(sprintf(
            paste0(
                "value labels differ for %d coalesced variable%s; ",
                "the tables combine and `x` wins conflicts: %s"
            ),
            length(val_label_diff),
            if (length(val_label_diff) == 1L) "" else "s",
            .listed_variable_names(val_label_diff)
        ), call. = FALSE)
    }
    invisible(NULL)
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
# themselves while every observed value compares numerically. A key with no
# missing values on either side skips the code column, because the codes
# would be constant and matching a single column is cheaper.
.dta_merge_key_half <- function(key, arg) {
    if (typeof(key) == "character" && anyNA(key)) {
        stop(sprintf(
            paste0(
                "`%s` contains `NA_character_`, but Stata uses the empty ",
                "string for missing string values; use `\"\"` instead"
            ),
            arg
        ), call. = FALSE)
    }
    if (typeof(key) != "double") {
        return(list(value = key, missing = FALSE))
    }
    values <- as.double(key)
    codes <- .tab_missing_codes(values)
    observed <- is.na(codes)
    if (all(observed)) {
        return(list(value = values, missing = FALSE))
    }
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
    list(value = values, code = codes, missing = TRUE)
}

# Both proxy frames must have the same shape, so the code column is decided
# per key name across the two sides.
.dta_merge_key_frames <- function(keys, by) {
    x_columns <- list()
    y_columns <- list()
    for (name in by) {
        x_half <- .dta_merge_key_half(keys[[name]]$x, paste0("x$", name))
        y_half <- .dta_merge_key_half(keys[[name]]$y, paste0("y$", name))
        with_code <- x_half$missing || y_half$missing
        value_name <- paste0(name, "..value")
        code_name <- paste0(name, "..code")
        x_columns[[value_name]] <- x_half$value
        y_columns[[value_name]] <- y_half$value
        if (with_code) {
            x_columns[[code_name]] <- if (is.null(x_half$code)) {
                rep(-1L, length(x_half$value))
            } else {
                x_half$code
            }
            y_columns[[code_name]] <- if (is.null(y_half$code)) {
                rep(-1L, length(y_half$value))
            } else {
                y_half$code
            }
        }
    }
    list(
        x = vctrs::new_data_frame(x_columns),
        y = vctrs::new_data_frame(y_columns)
    )
}

# Casting to a prototype the value already has re-encodes compact numeric
# columns for nothing, and merges of files with shared heritage hit that
# case on most columns.
.dta_merge_cast <- function(value, prototype, arg) {
    if (identical(vctrs::vec_ptype(value), prototype)) {
        return(value)
    }
    vctrs::vec_cast(value, prototype, x_arg = arg)
}

.dta_merge_has_compact_storage <- function(value) {
    !identical(stata_storage_type(value), "double") &&
        .is_unmaterialized_numeric_altrep(value)
}

.dta_merge_same_compact_storage <- function(x, y) {
    .dta_merge_has_compact_storage(x) &&
        .dta_merge_has_compact_storage(y) &&
        identical(stata_storage_type(x), stata_storage_type(y)) &&
        identical(
            .temporal_kind_or_missing(x),
            .temporal_kind_or_missing(y)
        )
}

.dta_merge_same_double_storage <- function(x, y) {
    identical(stata_storage_type(x), "double") &&
        identical(stata_storage_type(y), "double") &&
        identical(
            .temporal_kind_or_missing(x),
            .temporal_kind_or_missing(y)
        )
}

.dta_merge_restore_gathered <- function(value, prototype) {
    storage <- stata_storage_type(prototype)
    if (inherits(prototype, "stata_temporal")) {
        return(.attach_stata_temporal(value, prototype, storage))
    }
    .restore_stata_metadata(value, prototype, storage)
}

.dta_merge_reconcile_variable_label <- function(value, x, y) {
    label <- var_label(x)
    if (is.null(label)) label <- var_label(y)
    if (identical(var_label(value), label)) return(value)
    var_label(value) <- label
    value
}

.dta_merge_slice <- function(value, rows) {
    if (.dta_merge_has_compact_storage(value)) {
        gathered <- .Call(
            C_dtatools_gather_numeric,
            value, NULL, rows, NULL
        )
        return(.dta_merge_restore_gathered(gathered, value))
    }
    if (identical(stata_storage_type(value), "double")) {
        gathered <- .stata_data(value)[rows]
        return(.dta_merge_restore_gathered(gathered, value))
    }
    vctrs::vec_slice(value, rows)
}

.dta_merge_slice_columns <- function(values, rows) {
    count <- length(values)
    result <- vector("list", count)
    names(result) <- names(values)
    if (count == 0L) return(result)

    storage <- vapply(values, function(value) {
        storage <- stata_storage_type(value)
        if (is.null(storage)) "" else storage
    }, character(1))
    compact <- vapply(
        values, .dta_merge_has_compact_storage, logical(1)
    )
    native <- compact | storage == "double"
    if (any(native)) {
        gathered <- .Call(
            C_dtatools_gather_numeric_columns,
            unname(as.list(values[native])), NULL, rows, NULL
        )
        locations <- which(native)
        for (offset in seq_along(locations)) {
            location <- locations[[offset]]
            value <- values[[location]]
            result[[location]] <- if (is.null(gathered[[offset]])) {
                .dta_merge_slice(value, rows)
            } else {
                gathered[[offset]]
            }
        }
    }

    ordinary <- storage == ""
    if (any(ordinary)) {
        gathered <- vctrs::vec_slice(values[ordinary], rows)
        result[ordinary] <- unname(as.list(gathered))
    }

    fallback <- !(native | ordinary)
    for (location in which(fallback)) {
        result[[location]] <- .dta_merge_slice(
            values[[location]], rows
        )
    }
    result
}

.dta_merge_coalesce <- function(
    x, y, x_rows, y_rows, using_only,
    prototype = NULL, y_arg = ""
) {
    if (.dta_merge_same_compact_storage(x, y)) {
        gathered <- .Call(
            C_dtatools_gather_numeric,
            x, y, x_rows, y_rows
        )
        if (!is.null(gathered)) {
            return(.dta_merge_restore_gathered(gathered, x))
        }
    }
    if (.dta_merge_same_double_storage(x, y)) {
        gathered <- .stata_data(x)[x_rows]
        if (length(using_only) > 0L) {
            gathered[using_only] <- .stata_data(y)[y_rows[using_only]]
        }
        return(.dta_merge_restore_gathered(gathered, x))
    }

    column <- .dta_merge_slice(x, x_rows)
    if (length(using_only) == 0L) return(column)
    replacement <- .dta_merge_slice(y, y_rows[using_only])
    if (!is.null(prototype)) {
        replacement <- .dta_merge_cast(replacement, prototype, y_arg)
    }
    vctrs::vec_assign(column, using_only, replacement)
}

.dta_merge_coalesce_columns <- function(
    x, y, x_rows, y_rows, using_only, prototypes
) {
    count <- length(x)
    result <- vector("list", count)
    names(result) <- names(x)
    if (count == 0L) return(result)

    native <- vapply(seq_len(count), function(index) {
        .dta_merge_same_compact_storage(x[[index]], y[[index]]) ||
            .dta_merge_same_double_storage(x[[index]], y[[index]])
    }, logical(1))
    if (any(native)) {
        gathered <- .Call(
            C_dtatools_gather_numeric_columns,
            unname(x[native]), unname(as.list(y[native])),
            x_rows, y_rows
        )
        locations <- which(native)
        for (offset in seq_along(locations)) {
            location <- locations[[offset]]
            result[[location]] <- if (is.null(gathered[[offset]])) {
                .dta_merge_coalesce(
                    x[[location]], y[[location]],
                    x_rows, y_rows, using_only,
                    prototype = prototypes[[location]],
                    y_arg = paste0("y$", names(x)[[location]])
                )
            } else {
                gathered[[offset]]
            }
        }
    }

    ordinary <- !native & vapply(seq_len(count), function(index) {
        is.null(stata_storage_type(x[[index]])) &&
            is.null(stata_storage_type(y[[index]]))
    }, logical(1))
    if (any(ordinary)) {
        gathered <- vctrs::vec_slice(
            vctrs::new_data_frame(x[ordinary]), x_rows
        )
        if (length(using_only) > 0L) {
            replacement <- vctrs::vec_slice(
                vctrs::new_data_frame(as.list(y[ordinary])),
                y_rows[using_only]
            )
            locations <- which(ordinary)
            for (offset in seq_along(locations)) {
                location <- locations[[offset]]
                replacement[[offset]] <- .dta_merge_cast(
                    replacement[[offset]], prototypes[[location]],
                    paste0("y$", names(x)[[location]])
                )
            }
            gathered <- vctrs::vec_assign(
                gathered, using_only, replacement
            )
        }
        result[ordinary] <- unname(as.list(gathered))
    }

    fallback <- !(native | ordinary)
    for (location in which(fallback)) {
        result[[location]] <- .dta_merge_coalesce(
            x[[location]], y[[location]],
            x_rows, y_rows, using_only,
            prototype = prototypes[[location]],
            y_arg = paste0("y$", names(x)[[location]])
        )
    }
    result
}

.merge_vctrs_relationships <- c(
    "1:1" = "one-to-one", "m:1" = "many-to-one", "1:m" = "one-to-many"
)

# vctrs enforces the declared relationship only across matched pairs, so
# duplicate keys among unmatched rows must be caught separately; the check
# hashes only the unmatched remainder.
.validate_unmatched_duplicates <- function(proxies, x_rows, y_rows,
                                           relationship) {
    sides <- switch(relationship,
        "1:1" = c("x", "y"),
        "m:1" = "y",
        "1:m" = "x"
    )
    for (side in sides) {
        rows <- if (identical(side, "x")) {
            x_rows[is.na(y_rows)]
        } else {
            y_rows[is.na(x_rows)]
        }
        if (length(rows) > 1L && vctrs::vec_duplicate_any(
            vctrs::vec_slice(proxies[[side]], rows)
        )) {
            stop(sprintf(
                "`relationship = \"%s\"` requires unique keys in `%s`",
                relationship, side
            ), call. = FALSE)
        }
    }
    invisible(NULL)
}

# vctrs reports the side whose row matched multiple values, which is the
# opposite side from the duplicate keys.
.merge_duplicated_side <- function(condition) {
    if (inherits(condition, "vctrs_error_matches_relationship_one_to_many")) {
        return("x")
    }
    if (inherits(condition, "vctrs_error_matches_relationship_many_to_one")) {
        return("y")
    }
    if (identical(condition$which, "haystack")) "x" else "y"
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
