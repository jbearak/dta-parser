# Result publication captures nested values without changing their public
# representation. A shallow list copy cannot isolate a physical table or a
# scalar vector returned by foreign subsetting. Environments and closures keep
# their intentional reference identity. The call-local memo roots both sides;
# it is discarded after publication and never becomes an ownership registry.
# Cyclic payloads are rejected before public vector assembly traverses them.
.capture_dibble_nested <- function(value) {
    # An atomic vector takes `.metadata_copy()` in one native call (ADR 0055).
    captured <- .Call(C_dtatools_capture_atomic, value)
    if (!is.null(captured)) return(captured)
    if (is.environment(value) || is.function(value) ||
        typeof(value) %in% c("externalptr", "weakref", "bytecode")) return(value)
    if (typeof(value) != "list") return(.metadata_copy(value))
    completed <- utils::hashtab(type = "address")
    capture <- function(value) {
        if (is.environment(value) || is.function(value) ||
            typeof(value) %in% c("externalptr", "weakref", "bytecode")) return(value)
        # Pairlists/language objects retain the existing opaque copy policy;
        # the physical-slot setters below operate only on ordinary list vectors.
        if (typeof(value) != "list") return(.metadata_copy(value))
        entry <- utils::gethash(completed, value, nomatch = NULL)
        if (!is.null(entry)) {
            if (entry$active) rlang::abort("Cyclic nested list or data frame values are not supported.")
            return(entry$result)
        }
        frame <- is.data.frame(value)
        dibble <- frame && is_dibble(value)
        if (dibble) .as_mutation_data(value, allow_grouped = TRUE)
        columns <- if (frame) .data_columns(value) else .plain_data_columns(value)
        metadata <- attributes(value)
        if (frame) {
            metadata$.dtatools_ref_state <- NULL
            metadata$.internal.selfref <- NULL
            metadata$class <- .reference_base_classes(metadata$class)
            metadata$names <- names(columns)
            metadata$row.names <- .row_names_info(value, 0L)
        }
        # Establish the final physical shell before recursing. Active entries
        # reject ancestor cycles; completed entries reuse captured siblings.
        # All slots are replaced through the existing native setter.
        result <- .Call(C_dtatools_metadata_copy, columns)
        attributes(result) <- metadata
        if (dibble) result <- .reserve_column_capacity(result)
        if (frame && inherits(result, "data.table")) result <- data.table::setalloccol(result)
        entry <- new.env(parent = emptyenv())
        entry$source <- value
        entry$result <- result
        entry$active <- TRUE
        utils::sethash(completed, value, entry)
        addresses <- vapply(columns, rlang::obj_address, character(1))
        first <- match(addresses, addresses)
        for (index in seq_along(columns)) {
            prior <- first[[index]]
            column <- if (prior < index) .subset2(result, prior) else capture(.subset2(columns, index))
            if (dibble) column <- .typed_column(column, nrow(value),
                "nested dibble result")
            .Call(C_dtatools_set_data_column, result, as.integer(index), column)
        }
        for (name in intersect(c("ptype", "groups"), names(metadata))) {
            .Call(C_dtatools_set_attribute, result, name, capture(metadata[[name]]))
        }
        if (dibble) .validate_group_metadata(result)
        if (dibble) .mark_fresh_reference(result)
        entry$active <- FALSE
        result
    }
    capture(value)
}

# `lapply(chunks, .capture_dibble_nested)` for a group's results. One native
# call captures the atomic chunks in order, and the R code captures the rest
# from the first chunk the call declines (ADR 0058).
.capture_dibble_chunks <- function(chunks) {
    native <- .Call(C_dtatools_capture_atomic_list, chunks)
    if (is.null(native)) return(lapply(chunks, .capture_dibble_nested))
    captured <- native[[1L]]
    taken <- native[[2L]]
    for (index in seq_len(length(chunks) - taken) + taken)
        captured[index] <- list(.capture_dibble_nested(chunks[[index]]))
    names(captured) <- names(chunks)
    captured
}
