# Separate result-write experiment. Each action receives a fresh prepared pair.
expression_write_cases <- c("retained_shared", "computed_first", "computed_shared",
                            "computed_private", "full_replacement")

expression_write_state <- function(data, phase) {
    rows <- lapply(seq_along(data), function(index) {
        state <- owned_native("C_dtatools_mutation_info", data, as.integer(index))
        type <- switch(names(data)[[index]], s = "character", d = "logical", "double")
        bytes <- nrow(data) * switch(type, character = .Machine$sizeof.pointer,
                                    logical = 4, double = 8)
        if (is.null(state$backing) || !isTRUE(state$depth == 1L) ||
            !identical(state$exposed, FALSE) || !isTRUE(state$bytes == bytes)) {
            dput(list(column = names(data)[[index]], phase = phase, state = state))
            stop("Write fixture lacks expected unexposed owned backing")
        }
        data.frame(phase, column = names(data)[[index]], type, backing = state$backing,
                   depth = state$depth, bytes = state$bytes, exposed = state$exposed,
                   handle_shared = state$handle_shared, backing_private = state$backing_private)
    })
    do.call(rbind, rows)
}

expression_write_prepare <- function(rows, mode, case) {
    if (!case %in% expression_write_cases) stop("Unknown write case")
    data <- expression_fixture(rows, 16L, 1L, "ungrouped")
    sink <- new.env(parent = emptyenv())
    result <- expression_operation("dependent", "ungrouped", mode, sink)(data)
    captured <- NULL
    if (case %in% c("computed_shared", "full_replacement")) captured <- result$a
    if (case == "computed_private") repl(result, a = 8, where = 1L)
    action <- switch(case,
        retained_shared = function() { repl(result, s = "bb", where = 2L); invisible(NULL) },
        full_replacement = function() { repl(result, a = 9); invisible(NULL) },
        function() { repl(result, a = 9, where = 2L); invisible(NULL) })
    # Table attributes contain no column handles for this ungrouped corpus.
    # Extracting result[[i]] for metadata or owned_info changes handle sharing;
    # expected column metadata is obtained from a separate fixture instead.
    table_metadata <- owned_table_metadata(result)
    list(data = data, result = result, source_alias = data, result_alias = result,
         captured = captured, action = action, case = case, rows = rows,
         table_metadata = table_metadata)
}

expression_write_check_state <- function(pair, before, after, native) {
    target <- if (pair$case == "retained_shared") "s" else "a"
    old <- before[before$column == target, ]
    new <- after[after$column == target, ]
    expression_equal(before$backing[before$column != target],
                     after$backing[after$column != target], "unwritten result backing")
    if (pair$case == "retained_shared") {
        source <- expression_write_state(pair$data, "source_after_write")
        expression_equal(old$backing, source$backing[source$column == "s"], "retained original backing")
    }
    if (pair$case == "computed_private" &&
        (old$handle_shared || !old$backing_private)) stop("Private write was not prepared private")
    if (pair$case == "computed_shared" &&
        !old$handle_shared && old$backing_private) stop("Captured column did not force shared state")
    expected_copy <- if (pair$case == "full_replacement") 0 else {
        if (old$handle_shared || !old$backing_private) old$bytes else 0
    }
    expression_equal(unname(native[["mutation_target_copy"]]), as.double(expected_copy), "target copy budget")
    if (expected_copy > 0 && identical(old$backing, new$backing)) stop("Shared target failed to detach")
    if (pair$case == "computed_private") expression_equal(old$backing, new$backing, "private target keeps backing")
    if (pair$case == "full_replacement") {
        expression_equal(unname(native[["old_journal"]]), 0, "full replacement needs no old journal")
    }
    invisible(TRUE)
}

expression_write_check_values <- function(pair, expected_metadata) {
    n <- pair$rows
    x <- rep(c(1, 2, 3, 4), length.out = n)
    strings <- rep(c("aa", "b"), length.out = n)
    source_values <- c(list(x, strings), lapply(3:16, function(i) rep(as.double(i), n)))
    expression_equal(column_values(pair$data), source_values, "source values after result write")
    expression_equal(column_values(pair$source_alias), source_values, "physical source alias")
    expected_a <- x + 1
    if (pair$case == "retained_shared") strings[[2L]] <- "bb" else {
        if (pair$case == "computed_private") expected_a[[1L]] <- 8
        if (pair$case == "full_replacement") expected_a[] <- 9 else expected_a[[2L]] <- 9
    }
    result_values <- source_values
    result_values[[2L]] <- strings
    result_values <- c(result_values, list(expected_a, (x + 1) * 2, x + 1, rep(TRUE, n)))
    expression_equal(column_values(pair$result), result_values, "all result values")
    expression_equal(column_values(pair$result_alias), result_values, "physical result alias")
    expression_equal(lapply(seq_along(pair$result), function(i) attributes(pair$result[[i]])),
                     expected_metadata, "write preserves column metadata")
    expression_equal(owned_table_metadata(pair$result), pair$table_metadata, "write preserves table metadata")
    if (!is.null(pair$captured)) expression_equal(as.double(pair$captured), x + 1, "captured result column")
    invisible(TRUE)
}
