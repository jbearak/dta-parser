.output_container_choices <- c("default", "dibble", "tibble", "data.table")

# The containers a reader can build, and the values `save_arrow()` records.
.output_containers <- c("dibble", "tibble", "data.table")

.normalize_output_container <- function(output, stored = NULL,
                                        profiled = TRUE) {
    output <- rlang::arg_match(output, .output_container_choices)
    requested <- output
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
    # Data without the dtatools profile has no Stata semantics to carry,
    # so it does not become a dibble unless the caller asks for one.
    if (!profiled && identical(requested, "default") &&
        identical(output, "dibble")) {
        output <- "tibble"
    }
    if (identical(output, "data.table")) .require_data_table()
    output
}

.finalize_output_container <- function(native, output, .name_repair,
                                       stored = NULL, profiled = TRUE) {
    output <- .normalize_output_container(output, stored, profiled)
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
.complete_output_container <- function(result, output, stored = NULL,
                                       profiled = TRUE) {
    resolved <- .normalize_output_container(output, stored, profiled)
    if (identical(resolved, "dibble")) return(.as_dibble(result))
    if (identical(resolved, "data.table")) return(reserve_columns(result))
    .reserve_column_capacity(result)
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
        setdiff(class(data), "dtatools_dta_metadata"),
        c("data.table", "data.frame")
    )
}

.require_data_table <- function() {
    if (!requireNamespace("data.table", quietly = TRUE,
                          versionCheck = list(op = ">=", version = "1.18.2.1"))) {
        stop("Install or update data.table to version 1.18.2.1 or newer for dtatools data.table support",
             call. = FALSE)
    }
    invisible(NULL)
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
    if (.ordinary_data_table(data)) .require_data_table()
    invisible(NULL)
}

.repair_data_table_container <- function(data) {
    if (inherits(data, "data.table")) .require_data_table()
    if (inherits(data, "data.table") &&
        inherits(data, "dtatools_dta_metadata")) {
        # A data.table must never carry the frame marker: its `[` method
        # would intercept data.table's non-standard evaluation. Strip a
        # stray marker (for example from an object saved by an older
        # release) while keeping the metadata attributes themselves.
        data.table::setattr(
            data, "class", setdiff(class(data), "dtatools_dta_metadata")
        )
    }
    if (.ordinary_data_table(data)) data.table::setalloccol(data) else data
}

# Explicit mutation supports these complete class chains plus package markers.
# Unknown subclasses can carry invariants our physical commits cannot update.
.mutation_container_classes <- function(data) {
    setdiff(.reference_base_classes(class(data)), "dtatools_dta_metadata")
}

.supported_mutation_container <- function(data) {
    classes <- .mutation_container_classes(data)
    is.list(data) &&
        !(inherits(data, "data.table") && inherits(data, "dtatools_ref_data")) &&
        any(vapply(list(
        "data.frame", c("tbl_df", "tbl", "data.frame"),
        c("grouped_df", "tbl_df", "tbl", "data.frame"),
        c("rowwise_df", "tbl_df", "tbl", "data.frame"),
        c("data.table", "data.frame")
    ), identical, logical(1), classes))
}

.validate_mutation_container <- function(data, allow_grouped = FALSE,
                                         allow_rowwise = allow_grouped) {
    if (!is.data.frame(data) || !.supported_mutation_container(data)) {
        stop(paste0(
            if (.data_table_container(data)) "`data` must be an ordinary data.table " else
                "`data` must be an ordinary base data frame, tibble, or data.table ",
            "without additional classes. For an explicit Stata-typed conversion, ",
            "assign `data <- as_dibble(data)` first."
        ), call. = FALSE)
    }
    if (.data_table_container(data)) .require_data_table()
    if ((!allow_grouped && inherits(data, "grouped_df")) ||
        (!allow_rowwise && inherits(data, "rowwise_df"))) {
        stop(paste0("`data` must be an ungrouped data frame or tibble for this helper; ",
                    "assign `data <- dplyr::ungroup(data)` first, then assign ",
                    "`reserve_columns(data)` if structural changes need preparation"),
             call. = FALSE)
    }
    invisible(NULL)
}

# Table forms validate before resolving runtime names or evaluating updates.
# Vector forms retain their assigned-copy APIs and their own validators.
.validate_metadata_input <- function(data) {
    if (is.data.frame(data)) .as_mutation_data(data, allow_grouped = TRUE)
    invisible(NULL)
}

#' Containers supported by explicit mutation helpers
#'
#' Explicit table helpers mutate the supplied physical table on ordinary
#' base data frames, tibbles, dibbles and data.tables. Additional container
#' subclasses are rejected before runtime targets or updates are evaluated.
#' Assign `data <- as_dibble(data)` for an explicit conversion that removes
#' additional classes and applies Stata column typing. Helpers never perform
#' that conversion themselves. Package metadata and reference markers are
#' supported, except a reference marker on data.table.
#'
#' [gen()], [egen()] and [repl()] accept grouped tibbles and dibbles, using
#' their validated dplyr groups. Rowwise value mutation is unsupported.
#' [keep_vars()], [drop_vars()], [order_vars()], [rename_vars()] and
#' [reorder_dta_rows()] require ungrouped input. Assign
#' `data <- dplyr::ungroup(data)` first, then assign [reserve_columns()] if
#' the structural change needs preparation.
#'
#' All table label, format, generic metadata, note and characteristic setters
#' support grouped and rowwise inputs without changing their groups. This
#' includes their add, drop and renumber variants. Vector forms of metadata
#' setters return copies that must be assigned.
#'
#' [copy_data()] and [reserve_columns()] return isolated, assigned results
#' and retain valid grouping. [column_capacity()] and [can_add_columns()]
#' inspect all supported containers without changing them. Only a dibble
#' has dtatools' bracket `:=`; a data.table uses its own bracket semantics.
#'
#' Same-size values and metadata need no spare capacity. Growth is checked
#' before row selection, RHS evaluation or sorting. Keep/drop validate their
#' column selectors first and then check the resulting size before committing.
#' Copying, subsetting and serialization can require assigned preparation.
#'
#' A data.table needs data.table 1.18.2.1 or newer. Dropping its last column
#' leaves zero rows, including stored row names. Base data frames, tibbles and
#' dibbles retain their row count when all columns are dropped.
#' @name mutation-containers
#' @seealso [dibble], [reserve_columns()], [set_dta_metadata()]
NULL
