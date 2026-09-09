# Match policies and condition attribution adapted from dplyr 1.2.1
# R/join-rows.R. The public vctrs matcher supplies locations, not table assembly.
# Full source attribution and MIT license are retained in inst/NOTICE.
.dibble_join_abort <- function(message, class, call) {
    rlang::abort(message, class = c(class, "dplyr_error_join", "dplyr_error"), call = call)
}
.dibble_join_warn <- function(message, class, call) {
    rlang::warn(message, class = c(class, "dplyr_warning_join", "dplyr_warning"), call = call)
}
.dibble_join_multiple <- function(i, x, y, class, call) {
    .dibble_join_abort(c(
        sprintf("Each row in `%s` must match at most 1 row in `%s`.", x, y),
        i = sprintf("Row %s of `%s` matches multiple rows in `%s`.", i, x, y)), class, call)
}
.dibble_join_direct <- function(env) {
    if (!identical(env, emptyenv()) && identical(topenv(env), globalenv())) return(TRUE)
    tested <- Sys.getenv("TESTTHAT_PKG")
    top <- topenv(env)
    nzchar(tested) && rlang::is_namespace(top) &&
        identical(rlang::ns_env_name(top), tested)
}

.dibble_join_matches <- function(x_key, y_key, type, by, na_matches, multiple,
                                 unmatched, relationship, call, user_env) {
    count <- length(unmatched)
    if (count != 1L && !(type == "inner" && count == 2L)) {
        rlang::abort(sprintf("`unmatched` must be length %s, not %s.",
            if (type == "inner") "1 or 2" else "1", count), call = call)
    }
    rlang::arg_match(unmatched, c("drop", "error"), multiple = TRUE,
                      error_arg = "unmatched", error_call = call)
    x_unmatched <- unmatched[[1L]]
    y_unmatched <- unmatched[[count]]
    condition <- by$condition
    filter <- by$filter
    if (by$cross) {
        x_key <- rep.int(1L, vctrs::vec_size(x_key))
        y_key <- rep.int(1L, vctrs::vec_size(y_key))
        condition <- "=="; filter <- "none"
    }
    if (is.null(relationship)) {
        relationship <- if (type %in% c("nest", "semi", "anti") || by$cross ||
            any(condition != "==") || !.dibble_join_direct(user_env)) "none" else
                "warn-many-to-many"
    } else relationship <- rlang::arg_match0(relationship,
        c("one-to-one", "one-to-many", "many-to-one", "many-to-many"), error_call = call)
    incomplete <- if (na_matches == "na") "compare" else
        if (x_unmatched == "error" && type %in% c("right", "inner")) "error" else
        if (type %in% c("inner", "right", "semi")) "drop" else
        if (type == "nest") 0L else NA_integer_
    no_match <- if (x_unmatched == "error" && type %in% c("right", "inner")) "error" else
        if (type %in% c("inner", "right", "semi")) "drop" else
        if (type == "nest") 0L else NA_integer_
    remaining <- if (y_unmatched == "error" && type %in% c("left", "inner", "nest")) "error" else
        if (type %in% c("right", "full")) NA_integer_ else "drop"
    missing_x <- function(cnd) .dibble_join_abort(c(
        "Each row of `x` must have a match in `y`.",
        i = sprintf("Row %s of `x` does not have a match.", cnd$i)),
        "dplyr_error_join_matches_nothing", call)
    matches <- withCallingHandlers(vctrs::vec_locate_matches(
        needles = x_key, haystack = y_key, condition = condition, filter = filter,
        incomplete = incomplete, no_match = no_match, remaining = remaining,
        multiple = multiple, relationship = relationship,
        needles_arg = "x", haystack_arg = "y", nan_distinct = TRUE),
        vctrs_error_incompatible_type = function(cnd) {
            rlang::abort("Join keys became incompatible after common casting.", .internal = TRUE)
        },
        vctrs_error_matches_overflow = function(cnd) .dibble_join_abort(c(
            "This join would result in more rows than dplyr can handle.",
            i = sprintf("%s rows would be returned. 2147483647 rows is the maximum number allowed.", cnd$size),
            i = paste0("Double check your join keys. This error commonly occurs due to a ",
                       "missing join key, or an improperly specified join condition.")),
            "dplyr_error_join_matches_overflow", call),
        vctrs_error_matches_nothing = missing_x,
        vctrs_error_matches_incomplete = missing_x,
        vctrs_error_matches_remaining = function(cnd) .dibble_join_abort(c(
            "Each row of `y` must be matched by `x`.",
            i = sprintf("Row %s of `y` was not matched.", cnd$i)),
            "dplyr_error_join_matches_remaining", call),
        vctrs_error_matches_relationship_one_to_one = function(cnd) {
            x <- if (cnd$which == "needles") "x" else "y"
            y <- if (cnd$which == "needles") "y" else "x"
            .dibble_join_multiple(cnd$i, x, y, "dplyr_error_join_relationship_one_to_one", call)
        },
        vctrs_error_matches_relationship_one_to_many = function(cnd) {
            .dibble_join_multiple(cnd$i, "y", "x", "dplyr_error_join_relationship_one_to_many", call)
        },
        vctrs_error_matches_relationship_many_to_one = function(cnd) {
            .dibble_join_multiple(cnd$i, "x", "y", "dplyr_error_join_relationship_many_to_one", call)
        },
        vctrs_warning_matches_relationship_many_to_many = function(cnd) {
            .dibble_join_warn(c(
                "Detected an unexpected many-to-many relationship between `x` and `y`.",
                i = sprintf("Row %s of `x` matches multiple rows in `y`.", cnd$i),
                i = sprintf("Row %s of `y` matches multiple rows in `x`.", cnd$j),
                i = paste0("If a many-to-many relationship is expected, ",
                    "set `relationship = \"many-to-many\"` to silence this warning.")),
                "dplyr_warning_join_relationship_many_to_many", call)
            tryInvokeRestart("muffleWarning")
        },
        vctrs_error_matches_multiple = function(cnd) {
            .dibble_join_multiple(cnd$i, "x", "y", "dplyr_error_join_matches_multiple", call)
        },
        vctrs_warning_matches_multiple = function(cnd) {
            .dibble_join_warn(c("Each row in `x` is expected to match at most 1 row in `y`.",
                i = sprintf("Row %s of `x` matches multiple rows.", cnd$i)),
                "dplyr_warning_join_matches_multiple", call)
            tryInvokeRestart("muffleWarning")
        })
    list(x = matches$needles, y = matches$haystack)
}
