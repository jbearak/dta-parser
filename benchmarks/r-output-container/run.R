#!/usr/bin/env Rscript

if (!requireNamespace("dtatools", quietly = TRUE) ||
    !requireNamespace("data.table", quietly = TRUE) ||
    !requireNamespace("tibble", quietly = TRUE)) {
    stop("Install dtatools, data.table, and tibble before running this benchmark")
}

iterations <- 100L

fresh_frame <- function(columns, rows) {
    values <- rep(list(seq_len(rows)), columns)
    names(values) <- sprintf("v%05d", seq_len(columns))
    structure(values, class = "data.frame", row.names = .set_row_names(rows))
}

clone_shell <- function(data) {
    structure(
        unname(as.list(data)),
        names = names(data), class = "data.frame", row.names = attr(data, "row.names")
    )
}

elapsed_ms <- function(expression, times = iterations) {
    gc()
    elapsed <- system.time({
    for (index in seq_len(times)) {
            expression()
        }
    })[["elapsed"]]
    unname(1000 * elapsed / times)
}

finalization_case <- function(label, rows, columns) {
    source <- fresh_frame(columns, rows)
    tibble_then_setdt <- elapsed_ms(function() {
        value <- tibble::as_tibble(clone_shell(source), .name_repair = "unique")
        data.table::setDT(value)
    })
    direct <- elapsed_ms(function() {
        dtatools:::.finalize_output_container(
            clone_shell(source), "data.table", "unique"
        )
    })
    data.frame(
        workload = label,
        rows = rows,
        columns = columns,
        tibble_then_setDT_ms = tibble_then_setdt,
        direct_data_table_ms = direct,
        stringsAsFactors = FALSE
    )
}

results <- rbind(
    finalization_case("tall-narrow", 1000000L, 10L),
    finalization_case("short-wide", 100L, 10000L)
)

fixture <- file.path("tests", "fixtures", "dta", "wide_v118.dta")
if (file.exists(fixture)) {
    results <- rbind(results, data.frame(
        workload = "wide-dta-complete-read",
        rows = NA_integer_,
        columns = NA_integer_,
        tibble_then_setDT_ms = elapsed_ms(function() {
            value <- dtatools::read_dta(fixture, output = "tibble")
            data.table::setDT(value)
        }),
        direct_data_table_ms = elapsed_ms(function() {
            dtatools::read_dta(fixture, output = "data.table")
        }),
        stringsAsFactors = FALSE
    ))
}

print(results, row.names = FALSE)
