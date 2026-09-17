args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("usage: mutation-gate-worker.R INPUT_DTA")

script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_dir <- dirname(normalizePath(
    sub("^--file=", "", script_argument), winslash = "/"
))
source(file.path(script_dir, "common.R"), local = TRUE)
benchmark_activate_library(c("dtatools", "dplyr", "data.table", "tibble"))

input <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)

# One line per (verb, container) pair. The third field is a data signature,
# or `not-applicable` when the dataset has no column the verb needs. Every
# run emits the same rows for a file, so a verb that stops running shows up
# in `compare` as a changed row rather than a silent gap.
emit <- function(verb, container, value) {
    cat(sprintf("DTATOOLS_MUTATION_GATE\t%s\t%s\t%s\n", verb, container, value))
}

signature <- function(data) dtatools::datasig(data, threads = 1L)

first_column <- function(data, predicate) {
    for (name in names(data)) {
        if (predicate(data[[name]])) return(name)
    }
    NULL
}

containers <- c("dibble", "tibble", "data.frame", "data.table")
as_container <- function(data, container) {
    switch(
        container,
        dibble = dtatools::copy_data(data),
        tibble = tibble::as_tibble(data),
        data.frame = as.data.frame(data),
        data.table = data.table::as.data.table(data)
    )
}

result <- tryCatch({
    base <- dtatools::read_dta(input, output = "dibble")
    if (!dtatools::is_dibble(base)) stop("read_dta() did not return a dibble")
    rows <- nrow(base)
    numeric_target <- first_column(base, function(x) {
        is.numeric(x) && !is.factor(x)
    })
    string_target <- first_column(base, is.character)
    numeric_symbol <- if (!is.null(numeric_target)) as.name(numeric_target)
    string_symbol <- if (!is.null(string_target)) as.name(string_target)

    # Each by-reference verb runs on its own copy of the dataset so the verbs
    # do not observe one another. The copy is a dibble, the only mutation
    # target.
    on_copy <- function(verb, applicable, body) {
        if (!applicable) {
            emit(verb, "dibble", "not-applicable")
            return(invisible(NULL))
        }
        data <- dtatools::copy_data(base)
        # Every verb returns the dataset, so a table that had to grow past
        # its capacity is still the one whose signature is recorded.
        data <- eval(body, list(data = data), environment())
        emit(verb, "dibble", signature(data))
        rm(data)
        gc()
        invisible(NULL)
    }

    on_copy("gen", TRUE, quote(dtatools::gen(data, .gate_row = .n)))
    on_copy("gen-numeric", !is.null(numeric_target), bquote(
        dtatools::gen(data, .gate_num = .(numeric_symbol) * 2)
    ))
    on_copy("egen", !is.null(numeric_target), bquote(
        dtatools::egen(data, .gate_mean = dtatools::dta_mean(.(numeric_symbol)))
    ))
    on_copy("repl", !is.null(numeric_target) && rows > 0L, bquote(
        dtatools::repl(data, .(numeric_symbol), 0, where = .n == 1L)
    ))
    on_copy("replace_values-string", !is.null(string_target) && rows > 0L, bquote(
        dtatools::replace_values(data, .(string_symbol), "gate", where = .n == 1L)
    ))
    on_copy("bracket-assign", !is.null(numeric_target) && rows > 0L, bquote(
        data[1L, .(numeric_symbol) := 1]
    ))
    column_names <- names(base)
    on_copy("keep_vars", ncol(base) > 1L, bquote(
        dtatools::keep_vars(data, tidyselect::all_of(.(column_names[-length(column_names)])))
    ))
    on_copy("drop_vars", ncol(base) > 1L, bquote(
        dtatools::drop_vars(data, tidyselect::all_of(.(column_names[[1L]])))
    ))
    on_copy("rename_vars", TRUE, bquote(
        dtatools::rename_vars(data, .names = .(sprintf("gate_%04d", seq_along(column_names))))
    ))
    on_copy("order_vars", ncol(base) > 1L, bquote(
        dtatools::order_vars(data, tidyselect::all_of(.(column_names[[length(column_names)]])))
    ))
    on_copy("reorder_dta_rows", TRUE, quote(
        dtatools::reorder_dta_rows(data, rev(seq_len(nrow(data))))
    ))

    # Copying verbs run once per output container. The dibble input is a
    # fresh copy; the other containers are conversions of the base dibble.
    keyed <- dtatools::copy_data(base)
    # Stata's `_merge` is a common corpus variable, and `dta_merge()` refuses
    # an input that already carries it.
    if ("_merge" %in% names(keyed)) dtatools::drop_vars(keyed, tidyselect::all_of("_merge"))
    dtatools::gen(keyed, .gate_id = .n)
    using <- dtatools::dibble(.gate_id = seq_len(rows), .gate_flag = rep(1, rows))
    edge_rows <- unique(c(1L, rows))[seq_len(min(rows, 2L))]
    half <- rows %/% 2L
    for (container in containers) {
        data <- as_container(base, container)
        emit("slice_dta_rows", container, signature(
            dtatools::slice_dta_rows(data, edge_rows)
        ))
        emit("dplyr-mutate", container, if (is.null(numeric_target)) {
            "not-applicable"
        } else {
            signature(eval(bquote(
                dplyr::mutate(data, .gate_num = .(numeric_symbol) * 2)
            )))
        })
        emit("dplyr-filter", container, signature(
            dplyr::filter(data, dplyr::row_number() <= half)
        ))
        emit("dplyr-select", container, if (ncol(data) > 1L) {
            signature(dplyr::select(data, -1L))
        } else {
            "not-applicable"
        })
        rm(data)
        merge_x <- as_container(keyed, container)
        emit("dta_merge", container, signature(dtatools::dta_merge(
            merge_x, using, by = ".gate_id", relationship = "1:1"
        )))
        rm(merge_x)
        gc()
    }
    TRUE
}, error = function(condition) {
    message("mutation gate worker: ", conditionMessage(condition))
    FALSE
})

if (!result) quit(status = 1L)
