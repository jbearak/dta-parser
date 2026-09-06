# Shared deterministic fixtures and assertions for the benchmark runners.

make_pair <- function(kind, rows, columns) {
    values <- lapply(seq_len(columns), function(index) {
        type <- if (kind == "mixed") {
            c("double", "compact_int", "string", "logical")[(index - 1L) %% 4L + 1L]
        } else kind
        value <- switch(type,
            double = dta_double(rep(c(index, index + 0.5), length.out = rows)),
            compact_int = dta_int(rep(c(index, index + 1L), length.out = rows)),
            string = dta_string(rep(c(sprintf("a%04d", index), "", "b"), length.out = rows), "str12"),
            declared_character = structure(rep(c(sprintf("a%04d", index), "", "b"), length.out = rows), stata.string.storage = "str12"),
            dict_string = dta_string(rep(c(sprintf("a%04d", index), "", "b"), length.out = rows), "str12"),
            logical = rep(c(TRUE, FALSE), length.out = rows),
            factor = factor(rep(c("a", "b"), length.out = rows)),
            stop("Unknown kind")
        )
        attr(value, "label") <- paste("Column", index)
        value
    })
    names(values) <- sprintf("c%02d", seq_len(columns))
    typed <- tibble::new_tibble(values, nrow = rows)
    if (kind == "dict_string") {
        path <- tempfile(fileext = ".dta")
        on.exit(unlink(path))
        save_dta(typed, path)
        data <- read_dta(path)
    } else {
        data <- as_dibble(typed)
    }
    # Identical column objects; the container is the controlled variable.
    typed <- dtatools:::.reference_snapshot(data)
    stopifnot(all(vapply(seq_along(data), function(index) {
        identical(rlang::obj_address(.subset2(data, index)),
                  rlang::obj_address(.subset2(typed, index)))
    }, logical(1))))
    list(dibble = data, typed_tibble = typed)
}

compact_state <- function(data) vapply(seq_along(data), function(index) {
    value <- .subset2(data, index)
    dtatools:::.is_unmaterialized_numeric_altrep(value) ||
        dtatools:::.is_unmaterialized_dictstring(value)
}, logical(1))

column_values <- function(data) lapply(seq_along(data), function(index) {
    value <- .subset2(data, index)
    if (is.numeric(value)) as.double(value) else as.vector(value)
})

operations <- list(
    rename = function(data) rename(data, renamed = c01),
    select_all = function(data) select(data, everything()),
    mutate_symbol = function(data) mutate(data, c01 = c02),
    filter_half = function(data) filter(data, seq_len(n()) %% 2L == 0L),
    pipeline_five = function(data) {
        for (index in seq_len(5L)) data <- mutate(data, c01 = c02)
        data
    }
)
