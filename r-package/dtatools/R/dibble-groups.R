# Group construction, factor expansion, and row-slice policies adapt dplyr
# 1.2.1 grouped-df.R, generics.R, rowwise.R and src/group_by.cpp. See NOTICE
# for the pinned revision, modifications, and full MIT notice.
.group_vars <- function(data) {
    if (!inherits(data, c("grouped_df", "rowwise_df"))) return(character())
    setdiff(names(attr(data, "groups", exact = TRUE)), ".rows")
}

.group_drop_default <- function(data) {
    !inherits(data, "grouped_df") ||
        !identical(attr(attr(data, "groups", exact = TRUE), ".drop"), FALSE)
}

.validate_group_metadata <- function(data, columns = .data_columns(data),
                                     names = base::names(columns), row_count = nrow(data)) {
    if (inherits(data, "grouped_df") || inherits(data, "rowwise_df")) {
        groups <- attr(data, "groups", exact = TRUE)
        group_columns <- attr(groups, "names", exact = TRUE)
        if (!is.data.frame(groups) || !is.list(groups) ||
            is.null(group_columns) || anyNA(group_columns) ||
            any(!nzchar(group_columns)) || anyDuplicated(group_columns) ||
            !identical(utils::tail(group_columns, 1L), ".rows")) {
            stop("`data` has malformed grouping metadata; group columns need unique, non-missing names and one `.rows` column; assign `data <- dplyr::ungroup(data)` and group again",
                 call. = FALSE)
        }
        if (any(vapply(.plain_data_columns(groups), NROW, numeric(1)) !=
                abs(.row_names_info(groups, 2L)))) {
            stop("`data` has malformed grouping metadata with inconsistent row counts; assign `data <- dplyr::ungroup(data)` and group again",
                 call. = FALSE)
        }
        if (!is.list(groups$.rows) ||
            !all(vapply(groups$.rows, is.integer, logical(1)))) {
            stop("`data` has malformed grouping metadata; assign `data <- dplyr::ungroup(data)` first",
                 call. = FALSE)
        }
        group_names <- setdiff(names(groups), ".rows")
        rows <- unlist(groups$.rows, use.names = FALSE)
        if (anyNA(rows) || any(rows < 1L | rows > row_count) ||
            !all(group_names %in% names) ||
            any(vapply(groups$.rows, is.unsorted, logical(1), strictly = TRUE)) ||
            !identical(sort(as.integer(rows)), seq_len(row_count)) ||
            (inherits(data, "rowwise_df") &&
             (!all(lengths(groups$.rows) == 1L) ||
              !identical(as.integer(rows), seq_len(row_count))))) {
            stop("`data` has malformed grouping metadata; assign `data <- dplyr::ungroup(data)` first",
                 call. = FALSE)
        }
        if (inherits(data, "grouped_df") &&
            vctrs::vec_duplicate_any(groups[group_names])) {
            stop("`data` has duplicated grouping keys; assign `data <- dplyr::ungroup(data)` and group again",
                 call. = FALSE)
        }
        # A complete partition is not enough: each key must describe every
        # row assigned to it. Otherwise grouped helpers silently compute on
        # the wrong observations after ordinary edits to grouping metadata.
        for (name in group_names) {
            actual <- vctrs::vec_slice(columns[[name]], rows)
            expected <- vctrs::vec_slice(.subset2(groups, name),
                rep.int(seq_len(nrow(groups)), lengths(groups$.rows)))
            if (!all(vctrs::vec_equal(.grouping_key_value(actual),
                                     .grouping_key_value(expected), na_equal = TRUE))) {
                stop("`data` has grouping keys that do not match its rows; assign `data <- dplyr::ungroup(data)` and group again",
                     call. = FALSE)
            }
        }
    }
    invisible(NULL)
}

# Label/metadata wrappers do not change a grouping key's values. Compare
# without those wrappers while retaining factors, dates and Stata missing-code
# identity. Copies here change attributes only, never the supplied columns.
.grouping_key_value <- function(value) {
    if (inherits(value, "dtatools_dta_metadata_vector")) {
        value <- .dta_metadata_vector_base(value)
    }
    if (inherits(value, "haven_labelled") && !inherits(value, "dta_numeric")) {
        value <- .metadata_copy(value)
        classes <- setdiff(class(value), c("haven_labelled", "vctrs_vctr", typeof(value)))
        attr(value, "class") <- if (length(classes)) classes else NULL
    }
    value
}

.group_key_frame <- function(columns, keys, row_count) {
    tibble::new_tibble(columns[keys], nrow = row_count)
}

.build_group_metadata <- function(columns, keys, row_count,
                                   drop = TRUE, rowwise = FALSE) {
    key_frame <- .group_key_frame(columns, keys, row_count)
    if (rowwise) {
        key_frame$.rows <- vctrs::new_list_of(as.list(seq_len(row_count)),
                                             ptype = integer())
        return(key_frame)
    }
    if (!length(keys)) return(NULL)
    located <- vctrs::vec_locate_sorted_groups(key_frame, nan_distinct = TRUE)
    legacy_locale <- getOption("dplyr.legacy_locale")
    if (!is.null(legacy_locale)) {
        if (!is.logical(legacy_locale) || length(legacy_locale) != 1L || is.na(legacy_locale)) {
            rlang::abort("Global option `dplyr.legacy_locale` must be a single `TRUE` or `FALSE`.")
        }
        if (legacy_locale) located <- vctrs::vec_slice(
            located, .group_order_legacy(located$key))
    }
    groups <- tibble::new_tibble(as.list(located$key), nrow = nrow(located$key))
    groups$.rows <- vctrs::new_list_of(located$loc, ptype = integer())
    if (!isTRUE(drop) && any(vapply(groups[keys], is.factor, logical(1)))) {
        groups <- .expand_group_metadata(groups, keys)
    }
    attr(groups, ".drop") <- drop
    groups
}

# Adapted from dplyr's arrange.R legacy order proxies; see NOTICE. Public
# order proxies preserve Stata missing ranks while base order supplies locale
# collation for this compatibility option. Data-frame proxies need dense ranks.
.group_order_legacy <- function(data) {
    if (!length(data)) return(seq_len(nrow(data)))
    proxies <- lapply(data, function(value) {
        proxy <- vctrs::vec_proxy_order(value)
        if (is.data.frame(proxy)) {
            unique <- vctrs::vec_unique(proxy)
            return(vctrs::vec_match(proxy, vctrs::vec_slice(
                unique, .group_order_legacy(unique))))
        }
        attributes(proxy) <- NULL
        proxy
    })
    do.call(order, unname(proxies))
}

# Expand each factor's complete levels within the preceding key prefix.
# An absent prefix gives non-factor keys one missing placeholder, whereas an
# observed prefix uses only its observed values. This is not a Cartesian join
# of all keys: factor order and nested non-factor keys affect empty groups.
.expand_group_metadata <- function(groups, keys) {
    old_keys <- as.list(groups[keys])
    uniques <- lapply(old_keys, function(key) {
        if (is.factor(key)) key else vctrs::vec_unique(key)
    })
    positions <- Map(function(key, unique) {
        if (is.factor(key)) as.integer(key) else vctrs::vec_match(key, unique)
    }, old_keys, uniques)
    leaves <- list()
    rows <- list()
    visit <- function(depth, remaining, path) {
        if (depth > length(keys)) {
            leaves[[length(leaves) + 1L]] <<- path
            rows[[length(rows) + 1L]] <<- if (length(remaining))
                groups$.rows[[remaining[[1L]]]] else integer()
            return(invisible(NULL))
        }
        values <- positions[[depth]][remaining]
        candidates <- if (is.factor(old_keys[[depth]])) {
            c(seq_along(levels(old_keys[[depth]])),
              if (anyNA(values)) NA_integer_)
        } else if (length(remaining)) unique(values) else NA_integer_
        for (value in candidates) {
            selected <- if (is.na(value)) is.na(values) else
                !is.na(values) & values == value
            visit(depth + 1L, remaining[selected], c(path, value))
        }
        invisible(NULL)
    }
    visit(1L, seq_len(nrow(groups)), integer())
    columns <- lapply(seq_along(keys), function(index) {
        locations <- vapply(leaves, `[[`, integer(1), index)
        key <- old_keys[[index]]
        if (is.factor(key)) {
            attributes(locations) <- attributes(key)
            # Observation names cannot describe the expanded result.
            names(locations) <- NULL
            locations
        } else vctrs::vec_slice(uniques[[index]], locations)
    })
    names(columns) <- keys
    result <- tibble::new_tibble(columns, nrow = length(rows))
    result$.rows <- vctrs::new_list_of(rows, ptype = integer())
    result
}

.restore_group_metadata <- function(result, template, policy = "rebuild",
                                     locations = NULL, preserve = FALSE) {
    grouped <- inherits(template, "grouped_df")
    rowwise <- inherits(template, "rowwise_df")
    if (!grouped && !rowwise) return(result)
    keys <- if (rowwise && policy %in% c("bracket", "columns"))
        intersect(names(result), .group_vars(template)) else
        intersect(.group_vars(template), names(result))
    groups <- if (grouped && identical(policy, "columns") &&
                  identical(keys, .group_vars(template))) {
        attr(template, "groups", exact = TRUE)
    } else if (grouped && identical(policy, "slice")) {
        old <- attr(template, "groups", exact = TRUE)
        ids <- integer(nrow(template))
        for (index in seq_len(nrow(old))) ids[old$.rows[[index]]] <- index
        located <- vctrs::vec_group_loc(vctrs::vec_slice(ids, locations))
        rows <- rep(list(integer()), nrow(old))
        # Missing row locations have no existing group. The upstream hook
        # rejects these at reconstruction rather than inventing a new key.
        if (anyNA(located$key)) {
            stop("Missing row locations cannot retain grouped row indices", call. = FALSE)
        }
        rows[located$key] <- located$loc
        old$.rows <- vctrs::new_list_of(rows, ptype = integer())
        if (!preserve && isTRUE(attr(old, ".drop"))) {
            old <- vctrs::vec_slice(old, which(lengths(rows) > 0L))
        }
        old
    } else .build_group_metadata(.data_columns(result), keys, nrow(result),
                                 drop = .group_drop_default(template),
                                 rowwise = rowwise)
    attr(result, "row.names") <- .set_row_names(nrow(result))
    attr(result, "groups") <- groups
    classes <- .reference_base_classes(class(template))
    class(result) <- if (rowwise || length(keys)) classes else
        setdiff(classes, c("grouped_df", "rowwise_df"))
    result
}
