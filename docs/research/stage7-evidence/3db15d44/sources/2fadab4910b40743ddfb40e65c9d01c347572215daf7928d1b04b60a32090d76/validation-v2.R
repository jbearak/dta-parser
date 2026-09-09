# Benchmark checks use fixed predecessor metadata and independent fixture math.
# No candidate operation constructs an expected result.
stage7_metadata <- function(value) {
    fields <- attributes(value)
    fields$.dtatools_ref_state <- NULL
    fields$.internal.selfref <- NULL
    if (is.data.frame(value)) fields$row.names <- NULL
    fields <- fields[sort(names(fields))]
    lapply(names(fields), function(name) {
        item <- fields[[name]]
        list(name = name, value = if (name %in% c("groups", "ptype"))
            stage7_schema(item) else item)
    })
}

stage7_schema <- function(value) {
    slots <- NULL
    if (typeof(value) == "list") {
        items <- lapply(seq_along(value), function(i) stage7_schema(.subset2(value, i)))
        if (is.data.frame(value)) {
            slots <- items
        } else if (length(items)) {
            stopifnot(all(vapply(items, identical, logical(1), items[[1L]])))
            slots <- items[1L]
        } else slots <- list()
    }
    list(type = typeof(value), metadata = stage7_metadata(value), slots = slots)
}

# Saved smoke records contain ordinary values and attributes, never live owned
# handles. Reconstruct them only to extract a schema with the same function.
stage7_from_semantic <- function(node) {
    value <- if (node$type == "list") lapply(node$values, stage7_from_semantic) else
        switch(node$type, logical = as.logical(node$values), integer = as.integer(node$values),
            double = as.double(node$values), character = as.character(node$values),
            raw = as.raw(node$values), stop("Unexpected saved semantic type"))
    attributes(value) <- lapply(node$fields, stage7_from_semantic)
    value
}

stage7_partition <- function(rows, groups) {
    lapply(seq_len(groups), function(group) seq.int(group, rows, by = groups))
}

stage7_values <- function(column, index) {
    position <- (index - 1L) %% 4L + 1L
    switch((column - 1L) %% 8L + 1L,
        as.double(index %% 101L) + .25,
        c(1L, 0L, 1L, 0L)[position],
        c(2L, 1L, 2L, 3L)[position],
        c(2L, 1L, 2L, 3L)[position],
        c("alpha", "beta", "", "é")[position],
        c("one", "two", "", "é")[position],
        as.double(index %% 67L),
        as.double(index %% 31L) - .5)
}

stage7_plain_values <- function(value) {
    out <- switch(typeof(value), double = as.double(value),
        integer = as.integer(value), logical = as.integer(value),
        character = as.character(value), stop("Unexpected payload type"))
    attributes(out) <- NULL
    out
}

stage7_check_frame <- function(value, rows, names) {
    stopifnot(is.data.frame(value), identical(base::names(value), names),
        .row_names_info(value, 2L) == rows,
        identical(attr(value, "row.names"), seq_len(rows)),
        all(vapply(seq_along(value), function(i) length(.subset2(value, i)) == rows,
                   logical(1))))
}

stage7_check_payload <- function(value, columns, index) {
    for (column in seq_len(columns)) {
        actual <- .subset2(value, sprintf("c%02d", column))
        stopifnot(identical(stage7_plain_values(actual), stage7_values(column, index)))
    }
    invisible(NULL)
}

stage7_check_groups <- function(value, keys, locations) {
    groups <- attr(value, "groups", exact = TRUE)
    stopifnot(is.data.frame(groups), identical(names(groups), c("g", ".rows")),
        identical(stage7_plain_values(groups$g), keys),
        length(groups$.rows) == length(locations),
        identical(attr(groups$.rows, "ptype"), integer()))
    for (i in seq_along(locations))
        stopifnot(identical(.subset2(groups$.rows, i), locations[[i]]))
    stage7_check_frame(groups, length(keys), c("g", ".rows"))
    invisible(NULL)
}

stage7_check_source <- function(value, rows, columns, groups, schema) {
    payload <- sprintf("c%02d", seq_len(columns))
    stopifnot(identical(stage7_schema(value), schema))
    stage7_check_frame(value, rows, c("g", payload))
    stage7_check_payload(value, columns, seq_len(rows))
    stopifnot(identical(stage7_plain_values(value$g),
        sprintf("g%03d", (seq_len(rows) - 1L) %% groups + 1L)))
    stage7_check_groups(value, sprintf("g%03d", seq_len(groups)),
        stage7_partition(rows, groups))
    invisible(NULL)
}

stage7_check_output <- function(value, rows, columns, groups, workload, schema) {
    stopifnot(identical(stage7_schema(value), schema), dtatools::is_dibble(value))
    payload <- sprintf("c%02d", seq_len(columns))
    partition <- stage7_partition(rows, groups)
    keys <- sprintf("g%03d", seq_len(groups))
    selected <- switch(workload,
        reframe_half = unlist(lapply(partition, function(index)
            index[seq.int(2L, length(index), by = 2L)]), use.names = FALSE),
        group_modify_identity = unlist(partition, use.names = FALSE), integer())
    output_rows <- if (length(selected)) length(selected) else groups
    column_names <- switch(workload, summarise_one = c("g", "total"),
        reframe_half = c("g", "value"), group_nest = c("g", "data"),
        nest_by = c("g", "data"), c("g", payload))
    stage7_check_frame(value, output_rows, column_names)
    expected_keys <- if (length(selected))
        sprintf("g%03d", (selected - 1L) %% groups + 1L) else keys
    stopifnot(identical(stage7_plain_values(value$g), expected_keys))
    if (workload == "summarise_one") {
        expected <- vapply(partition, function(index) sum(stage7_values(1L, index)), 0)
        stopifnot(identical(stage7_plain_values(value$total), expected))
    } else if (workload == "summarise_width") {
        for (column in payload)
            stopifnot(identical(as.double(.subset2(value, column)), as.double(lengths(partition))))
    } else if (workload == "reframe_half") {
        stopifnot(identical(stage7_plain_values(value$value), stage7_values(1L, selected)))
    } else if (workload == "group_modify_identity") {
        stage7_check_payload(value, columns, selected)
        ends <- cumsum(lengths(partition))
        starts <- c(1L, head(ends, -1L) + 1L)
        stage7_check_groups(value, keys, Map(seq.int, starts, ends))
    } else {
        stopifnot(length(value$data) == groups)
        for (i in seq_len(groups)) {
            frame <- .subset2(value$data, i)
            stage7_check_frame(frame, length(partition[[i]]), payload)
            stage7_check_payload(frame, columns, partition[[i]])
        }
        prototype <- attr(value$data, "ptype", exact = TRUE)
        stage7_check_frame(prototype, 0L, payload)
        stage7_check_payload(prototype, columns, integer())
        if (workload == "nest_by")
            stage7_check_groups(value, keys, lapply(seq_len(groups), identity))
    }
    invisible(NULL)
}
