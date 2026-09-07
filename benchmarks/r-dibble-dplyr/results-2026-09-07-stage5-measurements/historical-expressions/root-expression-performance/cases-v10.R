# Benchmark-only reference and deterministic oracles. The optional dplyr
# reference retains the installed package's expression typing and safe closure.
# It omits the legacy second retyping pass for this explicitly checked corpus.
# Grouped/rowwise timing fixtures omit dataset labels because old delegation
# drops them; the candidate preservation correction has separate behavior proof.
expression_mutate <- function(data, dots, arguments = list(), mode = "direct") {
    if (mode == "direct") return(rlang::inject(dplyr::mutate(data, !!!dots, !!!arguments)))
    if (mode == "legacy") {
        return(dtatools:::.typed_mask_verb(data, "mutate", dots, arguments, "mutate()"))
    }
    if (mode != "safe_reference") stop("Unknown execution mode")
    wrapped <- dtatools:::.wrap_mask_expressions(dots, dtatools:::.data_columns(data), "mutate()")
    environment <- new.env(parent = baseenv())
    environment$mutate <- dplyr::mutate
    call <- rlang::call2("mutate", dtatools:::.reference_snapshot(data),
                         !!!wrapped$dots, !!!arguments)
    result <- dtatools:::.relabel_mask_conditions(eval(call, environment), wrapped$labels)
    dtatools:::.close_dibble(data, result, "mutate()")
}

expression_fixture <- function(rows, columns, groups, kind) {
    x <- rep(c(1, 2, 3, 4), length.out = rows)
    values <- list(x = dtatools::dta_double(x),
                   s = dtatools::dta_string(rep(c("aa", "b"), length.out = rows), "str2"))
    if (columns > 2L) for (i in seq.int(3L, columns)) {
        values[[paste0("p", i)]] <- dtatools::dta_double(rep(i, rows))
    }
    for (name in names(values)) attr(values[[name]], "label") <- paste("Input", name)
    if (kind %in% c("grouped", "by")) {
        values$g <- dtatools::dta_double(rep(as.double(seq_len(groups)), length.out = rows))
    }
    data <- dtatools::dibble(!!!values)
    attr(data, "label") <- if (kind %in% c("grouped", "rowwise")) NULL else "Expression benchmark"
    if (kind == "grouped") data <- dplyr::group_by(data, g)
    if (kind == "rowwise") data <- dplyr::rowwise(data)
    attr(data, "label") <- if (kind %in% c("grouped", "rowwise")) NULL else "Expression benchmark"
    data
}

expression_operation <- function(name, kind, mode, sink) {
    arguments <- if (kind == "by") list(.by = rlang::quo(g)) else list()
    dots <- switch(name,
        retain = rlang::quos(x = x),
        dependent = rlang::quos(a = x + 1, b = a * 2, c = b - a, d = c > 0),
        capture = rlang::quos(a = { sink$values[[length(sink$values) + 1L]] <- x; x + 1 }, x = x + 2),
        pipeline_five = rlang::quos(x = x + 1),
        stop("Unknown operation"))
    function(data) {
        sink$values <- list()
        count <- if (name == "pipeline_five") 5L else 1L
        for (i in seq_len(count)) data <- expression_mutate(data, dots, arguments, mode)
        data
    }
}

expression_snapshot <- function(data) {
    attributes <- lapply(dtatools:::.data_columns(data), function(value) {
        out <- attributes(value)
        if (is.null(out)) NULL else out[order(names(out), method = "radix")]
    })
    table <- attributes(data)
    table$.dtatools_ref_state <- NULL
    table$row.names <- .row_names_info(data, 0L)
    table <- table[order(names(table), method = "radix")]
    list(values = column_values(data), columns = attributes, table = table)
}

expression_equal <- function(actual, expected, label) {
    if (!identical(actual, expected)) {
        dput(list(label = label, actual = actual, expected = expected))
        stop("Expression oracle mismatch: ", label)
    }
}

expression_check <- function(data, result, name, kind, rows, sink) {
    if (!dtatools::is_dibble(result)) stop("Operation did not return a dibble")
    x <- rep(c(1, 2, 3, 4), length.out = rows)
    expected_x <- x + switch(name, capture = 2, pipeline_five = 5, 0)
    expression_equal(as.double(result$x), expected_x, "x values")
    expression_equal(as.character(result$s), rep(c("aa", "b"), length.out = rows), "retained string values")
    expression_equal(dtatools::dta_storage_type(result$s), "str2", "retained string storage")
    expression_equal(attr(result, "label"), if (kind %in% c("grouped", "rowwise")) NULL else "Expression benchmark", "dataset label")
    expression_equal(attr(result$x, "label"), if (name %in% c("capture", "pipeline_five")) NULL else "Input x", "numeric variable label")
    expression_equal(.row_names_info(result, 0L), c(NA_integer_, -as.integer(rows)), "raw row names")
    if (name %in% c("dependent", "capture")) {
        expression_equal(as.double(result$a), x + 1, "a values")
        expression_equal(dtatools::dta_storage_type(result$a), "double", "a storage")
    }
    if (name == "dependent") {
        expression_equal(as.double(result$b), (x + 1) * 2, "b values")
        expression_equal(as.double(result$c), x + 1, "c values")
        expression_equal(result$d, rep(TRUE, rows), "d values")
    }
    if (name == "capture") {
        if (kind == "ungrouped") expression_equal(as.double(sink$values[[1L]]), x, "captured original")
        else stop("Capture benchmark is deliberately ungrouped")
    }
    for (column in setdiff(names(data), "x")) {
        expression_equal(column_values(result[column]), column_values(data[column]),
                         paste("unchanged column", column))
        expression_equal(attributes(result[[column]]), attributes(data[[column]]),
                         paste("unchanged column metadata", column))
    }
    expression_equal(dplyr::group_vars(result), dplyr::group_vars(data), "group variables")
    if (kind %in% c("grouped", "rowwise")) {
        expression_equal(attr(result, "groups"), attr(data, "groups"), "group metadata")
    }
    invisible(TRUE)
}

expression_grid <- function() {
    rows <- list()
    add <- function(n, p, g, kind, name) {
        rows[[length(rows) + 1L]] <<- data.frame(rows = n, columns = p, groups = g, kind, operation = name)
    }
    for (n in c(10000L, 100000L, 1000000L)) {
        for (name in c("retain", "dependent", "capture", "pipeline_five")) add(n, 16L, 1L, "ungrouped", name)
    }
    for (p in c(2L, 64L)) for (name in c("retain", "dependent")) add(100000L, p, 1L, "ungrouped", name)
    for (g in c(10L, 100L, 1000L)) for (kind in c("grouped", "by")) {
        add(100000L, 16L, g, kind, "dependent")
    }
    for (n in c(100L, 1000L, 10000L)) add(n, 2L, n, "rowwise", "dependent")
    do.call(rbind, rows)
}

# Mixed double/string owned-state assertions. State inspection is outside the
# measured operation and records sharing separately from exclusive ownership.
expression_state <- function(data, phase) {
    rows <- lapply(seq_along(data), function(index) {
        # owned_info reads flags without materializing or exporting backing.
        # Its result contains scalar facts and addresses, never a column handle.
        owned <- .Call(get("C_dtatools_owned_info", asNamespace("dtatools")), data[[index]])
        state <- .Call(get("C_dtatools_mutation_info", asNamespace("dtatools")), data, as.integer(index))
        # The deterministic fixture uses ordinary doubles and one string.
        # Inspect through the table; avoid retaining a column while reading state.
        type <- if (names(data)[[index]] == "s") "character" else "double"
        bytes <- nrow(data) * switch(type, double = 8, character = .Machine$sizeof.pointer,
                                     integer = 4, logical = 4, stop("Unsupported benchmark type"))
        if (is.null(owned) || is.null(state$backing) || !isTRUE(state$depth == 1L) ||
            !identical(state$exposed, FALSE) || !isTRUE(state$bytes == bytes)) {
            dput(list(column = names(data)[[index]], phase = phase, state = state))
            stop("Benchmark fixture is not unexposed owned backing of the expected size/depth")
        }
        data.frame(phase, column = names(data)[[index]], type, owned = TRUE, backing = state$backing,
                   depth = state$depth, bytes = state$bytes, exposed = state$exposed,
                   handle_shared = state$handle_shared, backing_private = state$backing_private)
    })
    do.call(rbind, rows)
}
