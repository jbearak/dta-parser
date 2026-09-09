# Deterministic, source-only Stage 7 workload definitions. Setup is untimed.
# Eight payload types repeat at width sixteen; the grouping key is additional.
stage7_raw_fixture <- function(rows, columns, groups) {
    stopifnot(rows >= 2L * groups, columns %in% c(8L, 16L), groups >= 1L)
    index <- seq_len(rows)
    payload <- lapply(seq_len(columns), function(column) {
        value <- switch((column - 1L) %% 8L + 1L,
            dtatools::dta_double(as.double(index %% 101L) + .25),
            rep(c(TRUE, FALSE, TRUE, FALSE), length.out = rows),
            factor(rep(c("b", "a", "b", "c"), length.out = rows),
                   levels = c("a", "b", "c", "unused")),
            ordered(rep(c("b", "a", "b", "c"), length.out = rows),
                    levels = c("a", "b", "c", "unused")),
            structure(rep(c("alpha", "beta", "", "é"), length.out = rows),
                      class = c("dta_string", "vctrs_vctr", "character"),
                      stata.string.storage = "str12"),
            structure(rep(c("one", "two", "", "é"), length.out = rows),
                      stata.string.storage = "str12"),
            as.integer(index %% 67L),
            dtatools::dta_double(as.double(index %% 31L) - .5))
        attr(value, "label") <- paste("Payload", column)
        value
    })
    names(payload) <- sprintf("c%02d", seq_len(columns))
    tibble::new_tibble(c(list(g = sprintf("g%03d", (index - 1L) %% groups + 1L)), payload),
                       nrow = rows)
}

stage7_fixture <- function(rows, columns, groups) {
    data <- dtatools::as_dibble(stage7_raw_fixture(rows, columns, groups))
    attr(data, "label") <- "Stage 7 mixed payload fixture"
    dplyr::group_by(data, g)
}

stage7_workload_names <- c("summarise_one", "summarise_width", "reframe_half",
                         "group_modify_identity", "group_nest", "nest_by")

stage7_workload <- function(data, workload, route = "public") {
    stopifnot(workload %in% stage7_workload_names,
              route %in% c("public", "predecessor_safe_reference"))
    payload <- setdiff(names(data), "g")
    specification <- switch(workload,
        summarise_one = list(generic = "summarise", dots = list(total = rlang::quo(sum(c01))),
                             arguments = list(.groups = "drop")),
        summarise_width = list(generic = "summarise",
            dots = list(rlang::quo(dplyr::across(tidyselect::all_of(payload), length))),
            arguments = list(.groups = "drop")),
        reframe_half = list(generic = "reframe",
            dots = list(value = rlang::quo(c01[seq.int(2L, length(c01), by = 2L)])),
            arguments = list()),
        group_modify_identity = list(generic = "group_modify", dots = list(),
            arguments = list(.f = function(.x, .y) .x, .keep = FALSE)),
        group_nest = list(generic = "group_nest", dots = list(), arguments = list(keep = FALSE)),
        nest_by = list(generic = "nest_by", dots = list(), arguments = list(.keep = FALSE)))
    if (route == "predecessor_safe_reference") {
        return(stage7_safe_reference(data, specification$generic,
                                     specification$dots, specification$arguments))
    }
    eval(rlang::call2(getExportedValue("dplyr", specification$generic), data,
                     !!!specification$dots, !!!specification$arguments))
}
