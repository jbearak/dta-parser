.output_container_choices <- c("default", "dibble", "tibble", "data.table")

# The containers a reader can build, and the values `save_arrow()` records.
.output_containers <- c("dibble", "tibble", "data.table")

.normalize_output_container <- function(output, stored = NULL) {
    output <- rlang::arg_match(output, .output_container_choices)
    if (identical(output, "default")) {
        output <- if (!is.null(stored)) {
            # A stored value this release does not know (a file written by a
            # newer dtatools) must still read, so it degrades to a tibble
            # instead of failing the whole read.
            if (is.character(stored) && length(stored) == 1L &&
                !is.na(stored) && stored %in% .output_containers) {
                stored
            } else {
                "tibble"
            }
        } else {
            getOption("dtatools.output", "dibble")
        }
    }
    if (!is.character(output) || length(output) != 1L || is.na(output) ||
        !(output %in% .output_containers)) {
        stop(
            paste0(
                "`dtatools.output` must be \"dibble\", \"tibble\", or ",
                "\"data.table\"; got ", paste(deparse(output), collapse = " ")
            ),
            call. = FALSE
        )
    }
    if (identical(output, "data.table") &&
        !requireNamespace("data.table", quietly = TRUE)) {
        stop(
            "Install the data.table package to request data.table output",
            call. = FALSE
        )
    }
    output
}

.finalize_output_container <- function(native, output, .name_repair,
                                       stored = NULL) {
    output <- .normalize_output_container(output, stored)
    source_names <- names(native)
    if (is.null(source_names)) source_names <- rep("", length(native))
    repaired <- vctrs::vec_as_names(
        source_names, repair = .name_repair, repair_arg = ".name_repair"
    )
    names(native) <- repaired
    if (output %in% c("tibble", "dibble")) {
        # A dibble starts as this tibble and is marked by
        # `.complete_output_container()` once the caller has attached
        # dataset metadata: the metadata helpers replace columns through
        # `[<-`, which on a reference frame returns a plain snapshot.
        return(tibble::as_tibble(native, .name_repair = "minimal"))
    }

    class(native) <- c("data.table", "data.frame")
    data.table::setalloccol(native)
}

# Last step of every reader: the dibble mark goes on after metadata and
# data.table repair so that no later attribute helper snapshots it away.
# `output` is the caller's request, resolved again here so the reader does
# not have to thread the normalized value through.
.complete_output_container <- function(result, output, stored = NULL) {
    resolved <- .normalize_output_container(output, stored)
    if (identical(resolved, "dibble")) .as_dibble(result) else result
}

# The value `save_arrow()` records so `read_arrow()` can rebuild the same
# container. A plain data frame records nothing.
.stored_output_container <- function(data) {
    if (inherits(data, "data.table")) {
        "data.table"
    } else if (is_dibble(data)) {
        "dibble"
    } else if (inherits(data, "tbl_df")) {
        "tibble"
    } else {
        NULL
    }
}

.data_table_container <- function(data) {
    inherits(data, "data.table")
}

.ordinary_data_table <- function(data) {
    identical(
        setdiff(class(data), "dtatools_stata_metadata"),
        c("data.table", "data.frame")
    )
}

.reject_data_table_subclass <- function(data, argument = "data") {
    if (.data_table_container(data) && !.ordinary_data_table(data)) {
        stop(
            sprintf(
                "`%s` must be an ordinary data.table without additional classes",
                argument
            ),
            call. = FALSE
        )
    }
    invisible(NULL)
}

.repair_data_table_container <- function(data) {
    if (inherits(data, "data.table") &&
        inherits(data, "dtatools_stata_metadata")) {
        # A data.table must never carry the frame marker: its `[` method
        # would intercept data.table's non-standard evaluation. Strip a
        # stray marker (for example from an object saved by an older
        # release) while keeping the metadata attributes themselves.
        data.table::setattr(
            data, "class", setdiff(class(data), "dtatools_stata_metadata")
        )
    }
    if (.ordinary_data_table(data)) data.table::setalloccol(data) else data
}
