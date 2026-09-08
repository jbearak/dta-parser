# Result publication captures nested values without changing their public
# representation. A shallow list copy cannot isolate a physical table or a
# scalar vector returned by foreign subsetting. Environments and closures keep
# their intentional reference identity. The call-local memo roots both sides;
# it is discarded after publication and never becomes an ownership registry.
# Cyclic payloads are rejected before public vector assembly traverses them.
.capture_dibble_nested <- function(value) {
    completed <- new.env(hash = TRUE, parent = emptyenv())
    capture <- function(value) {
        if (is.environment(value) || is.function(value) ||
            typeof(value) %in% c("externalptr", "weakref", "bytecode")) return(value)
        # Pairlists/language objects retain the existing opaque copy policy;
        # the physical-slot setters below operate only on ordinary list vectors.
        if (typeof(value) != "list") return(.metadata_copy(value))
        address <- rlang::obj_address(value)
        if (exists(address, completed, inherits = FALSE)) {
            entry <- completed[[address]]
            if (entry$active) rlang::abort("Cyclic nested list or data frame values are not supported.")
            return(entry$result)
        }
        frame <- is.data.frame(value)
        dibble <- frame && is_dibble(value)
        reference <- frame && inherits(value, "dtatools_ref_data")
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
        if (dibble || (reference && !inherits(result, "data.table"))) {
            result <- .reserve_column_capacity(result)
        }
        if (frame && inherits(result, "data.table")) result <- data.table::setalloccol(result)
        completed[[address]] <- list(source = value, result = result, active = TRUE)
        addresses <- vapply(columns, rlang::obj_address, character(1))
        for (index in seq_along(columns)) {
            prior <- match(addresses[[index]], addresses[seq_len(index - 1L)])
            column <- if (!is.na(prior)) .subset2(result, prior) else capture(.subset2(columns, index))
            if (dibble) column <- .typed_column_named(column, nrow(value),
                "nested dibble result", names(columns)[[index]])
            .Call(C_dtatools_set_data_column, result, as.integer(index), column)
        }
        for (name in intersect(c("ptype", "groups"), names(metadata))) {
            .Call(C_dtatools_set_attribute, result, name, capture(metadata[[name]]))
        }
        if (dibble) .validate_group_metadata(result)
        if (dibble || reference) .mark_reference_data(result,
            .new_reference_state(result, dibble = dibble))
        completed[[address]]$active <- FALSE
        result
    }
    capture(value)
}
