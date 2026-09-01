.output_container_choices <- c("default", "tibble", "data.table")

.normalize_output_container <- function(output, stored = NULL) {
    output <- rlang::arg_match(output, .output_container_choices)
    if (identical(output, "default")) {
        output <- if (!is.null(stored)) {
            stored
        } else {
            getOption("dtatools.output", "tibble")
        }
    }
    if (!is.character(output) || length(output) != 1L || is.na(output) ||
        !(output %in% c("tibble", "data.table"))) {
        stop(
            paste0(
                "`dtatools.output` must be \"tibble\" or \"data.table\"; ",
                "got ", paste(deparse(output), collapse = " ")
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
    if (identical(output, "tibble")) {
        return(tibble::as_tibble(native, .name_repair = "minimal"))
    }

    class(native) <- c("data.table", "data.frame")
    data.table::setalloccol(native)
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
    if (.ordinary_data_table(data)) data.table::setalloccol(data) else data
}
