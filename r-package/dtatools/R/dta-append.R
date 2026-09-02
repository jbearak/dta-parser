.APPEND_NOTE_POLICIES <- c("first", "none", "all")

#' Append data-frame rows with Stata semantics
#'
#' Stacks a list of sources the way Stata's `append using ..., force`
#' does: the result holds the union of the sources' variables in
#' first-appearance order, a source that lacks a variable contributes
#' that variable's missing value for its own rows, string storage
#' widens to the widest contributor, and numeric storage promotes
#' along Stata's lossless lattice.
#'
#' Sources are taken as a list rather than as a master and a using
#' pair so the schema union is resolved in one pass. Stata appends one
#' file at a time only because it holds a single dataset in memory;
#' repeating that here would reallocate the whole result once per
#' source, which is quadratic in total rows.
#'
#' Each element may be a base data frame, tibble, or data.table
#' already in memory, a path to a `.dta` file, or a path to an
#' `.arrow` file. File sources are read once, in a first pass for
#' their schema alone and in a second pass for their observations, so
#' peak memory is roughly the result plus the largest single source
#' rather than every source at once.
#'
#' @section Type conflicts:
#' When one source stores a variable as a string and another stores it
#' as a numeric, there is no common Stata type. With `force = TRUE`
#' the first contributor's type wins, exactly as the master dataset's
#' type wins in Stata, the conflicting sources contribute missing
#' values for their rows, and a message names the variable and the
#' sources. With `force = FALSE` the conflict is an error. A value
#' that fits the common type but not the specific storage - a numeric
#' too wide to re-encode, say - is treated the same way.
#'
#' @section Metadata:
#' Variable labels, value labels, formats, and variable-level notes
#' come from the first source that contributes the variable.
#' Combining is delegated to the package's own coercion rules, so two
#' sources that give the same code different label text keep the first
#' contributor's text and warn. Value-label tables that disagree only
#' by covering different codes are merged.
#'
#' Stata does not define what happens to dataset-level notes on
#' `append`, and it keeps the master's. `dataset_notes` therefore
#' defaults to `"first"`. Use `"all"` to concatenate every source's
#' notes in source order, or `"none"` to drop them.
#'
#' @param sources A list of data frames and file paths. A single data
#'   frame or path is accepted and returned as a one-source append.
#' @param force Whether to resolve a string/numeric conflict by
#'   filling the conflicting sources' rows with missing values, as
#'   Stata's `force` option does. `FALSE` makes such a conflict an
#'   error.
#' @param dataset_notes How to resolve dataset-level notes and
#'   characteristics: `"first"`, `"all"`, or `"none"`.
#' @param output `"default"`, `"tibble"`, or `"data.table"`.
#' @param .name_repair Name repair applied to the result, as in
#'   [read_dta()].
#' @return The stacked observations in the requested container,
#'   carrying the reconciled Stata metadata.
#' @export
dta_append <- function(sources, force = TRUE,
                       dataset_notes = c("first", "none", "all"),
                       output = c("default", "tibble", "data.table"),
                       .name_repair = "unique") {
    the_sources <- .append_normalize_sources(sources)
    dataset_notes <- rlang::arg_match(dataset_notes, .APPEND_NOTE_POLICIES)
    if (!isTRUE(force) && !isFALSE(force)) {
        stop("`force` must be `TRUE` or `FALSE`", call. = FALSE)
    }
    if (!length(the_sources)) {
        stop("`sources` must hold at least one source", call. = FALSE)
    }

    schemas <- lapply(seq_along(the_sources), function(my_index) {
        .append_read_schema(the_sources[[my_index]], my_index)
    })
    plan <- .append_build_plan(schemas, force)
    filled <- .append_fill_columns(schemas, plan)

    result <- vctrs::new_data_frame(
        filled$columns, n = filled$row_count
    )
    result <- .append_apply_dataset_metadata(result, schemas, dataset_notes)
    stored <- if (inherits(schemas[[1L]]$schema, "data.table")) {
        "data.table"
    } else {
        "tibble"
    }
    .as_stata_metadata_frame(
        .finalize_output_container(result, output, .name_repair, stored)
    )
}

.append_normalize_sources <- function(sources) {
    if (is.data.frame(sources)) return(list(sources))
    if (is.character(sources)) return(as.list(sources))
    if (!is.list(sources)) {
        stop(
            "`sources` must be a list of data frames and file paths",
            call. = FALSE
        )
    }
    sources
}

.append_source_label <- function(source, index) {
    if (is.character(source)) sQuote(basename(source)) else paste0(
        "source ", index
    )
}

.append_source_kind <- function(source, index) {
    if (is.data.frame(source)) return("frame")
    if (!is.character(source) || length(source) != 1L || is.na(source)) {
        stop(
            sprintf(
                "`sources[[%d]]` must be a data frame or one file path",
                index
            ),
            call. = FALSE
        )
    }
    if (grepl("\\.arrow$", source, ignore.case = TRUE)) "arrow" else "dta"
}

# Pass one. A file source is opened for its header alone, so the
# schema union costs one tiny read per file and no observation data.
.append_read_schema <- function(source, index) {
    kind <- .append_source_kind(source, index)
    schema <- switch(
        kind,
        frame = source[0L, , drop = FALSE],
        dta = read_dta(source, n_max = 0L),
        arrow = read_arrow(source, n_max = 0L)
    )
    list(
        kind = kind, source = source, index = index, schema = schema,
        rows = .append_source_rows(kind, source)
    )
}

# The header carries no observation count, so one narrow column is
# read to size the result. Reading a single variable costs a fraction
# of a second across two hundred survey files and lets pass two write
# straight into a buffer allocated at the final row count.
.append_source_rows <- function(kind, source) {
    if (identical(kind, "frame")) return(nrow(source))
    reader <- if (identical(kind, "arrow")) read_arrow else read_dta
    nrow(reader(source, col_select = 1L))
}

.append_read_data <- function(entry) {
    switch(
        entry$kind,
        frame = entry$source,
        dta = read_dta(entry$source),
        arrow = read_arrow(entry$source)
    )
}

.append_build_plan <- function(schemas, force) {
    the_names <- character(0)
    for (my_schema in schemas) {
        the_names <- c(the_names, setdiff(names(my_schema$schema), the_names))
    }

    source_count <- length(schemas)
    prototypes <- vector("list", length(the_names))
    names(prototypes) <- the_names
    # A source is dropped for one variable when its storage cannot
    # meet the accumulated prototype; those rows take missing values.
    dropped <- vector("list", length(the_names))
    names(dropped) <- the_names

    for (my_name in the_names) {
        prototype <- NULL
        conflicting <- integer(0)
        for (my_index in seq_len(source_count)) {
            value <- schemas[[my_index]]$schema[[my_name]]
            if (is.null(value)) next
            candidate <- vctrs::vec_ptype(value)
            if (is.null(prototype)) {
                prototype <- candidate
                next
            }
            merged <- tryCatch(
                vctrs::vec_ptype2(prototype, candidate),
                error = function(condition) NULL
            )
            if (is.null(merged)) {
                if (!force) {
                    stop(
                        sprintf(
                            paste0(
                                "variable `%s` has incompatible storage ",
                                "across sources; use `force = TRUE` to fill ",
                                "the conflicting rows with missing values"
                            ),
                            my_name
                        ),
                        call. = FALSE
                    )
                }
                conflicting <- c(conflicting, my_index)
                next
            }
            prototype <- merged
        }
        prototypes[[my_name]] <- prototype
        dropped[[my_name]] <- conflicting
        if (length(conflicting)) {
            message(sprintf(
                paste0(
                    "note: `%s` is stored differently in %s; ",
                    "force specified, so those observations are missing"
                ),
                my_name,
                paste(vapply(
                    conflicting,
                    function(k) .append_source_label(
                        schemas[[k]]$source, k
                    ),
                    character(1)
                ), collapse = ", ")
            ))
        }
    }

    list(names = the_names, prototypes = prototypes, dropped = dropped)
}

# Pass two. One source is held at a time: its columns are cast to the
# result prototype and set aside, then the source is released. The
# per-variable pieces are concatenated once, so each result column is
# allocated at its final length and filled in native code rather than
# grown per source.
.append_fill_columns <- function(schemas, plan) {
    source_count <- length(schemas)
    row_counts <- vapply(schemas, function(my_schema) {
        as.integer(my_schema$rows)
    }, integer(1))
    total_rows <- sum(row_counts)
    offsets <- cumsum(c(0L, row_counts))

    # A column whose prototype and contributors share one physical
    # layout gets a buffer allocated once at the full row count, and
    # each source writes into its own row range. Anything else keeps
    # its per-source pieces for the general vctrs concatenation.
    buffers <- vector("list", length(plan$names))
    names(buffers) <- plan$names
    pieces <- vector("list", length(plan$names))
    names(pieces) <- plan$names
    for (my_name in plan$names) {
        buffers[[my_name]] <- .append_allocate_buffer(
            plan$prototypes[[my_name]], total_rows
        )
        if (is.null(buffers[[my_name]])) {
            pieces[[my_name]] <- vector("list", source_count)
        }
    }

    for (my_index in seq_len(source_count)) {
        data <- .append_read_data(schemas[[my_index]])
        rows <- row_counts[[my_index]]
        span <- if (rows > 0L) {
            (offsets[[my_index]] + 1L):(offsets[[my_index]] + rows)
        } else {
            integer(0)
        }
        for (my_name in plan$names) {
            prototype <- plan$prototypes[[my_name]]
            value <- if (my_index %in% plan$dropped[[my_name]]) {
                NULL
            } else {
                data[[my_name]]
            }
            if (!is.null(buffers[[my_name]])) {
                if (!is.null(value) && rows > 0L) {
                    # A value that does not already share the buffer's
                    # layout is cast to the prototype first. A cast the
                    # prototype cannot represent leaves the range at its
                    # missing initialization, which is what the pieces
                    # path does for the same out-of-range source.
                    writable <- if (.append_fits_buffer(value, prototype)) {
                        value
                    } else {
                        tryCatch(
                            vctrs::vec_cast(value, prototype),
                            error = function(condition) NULL
                        )
                    }
                    if (!is.null(writable)) {
                        buffer <- buffers[[my_name]]
                        # Clear the list slot first. While the list still
                        # references the buffer, `[<-` would duplicate
                        # the whole column on every source instead of
                        # writing the destination range in place.
                        buffers[my_name] <- list(NULL)
                        buffer[span] <- .append_buffer_values(writable)
                        buffers[[my_name]] <- buffer
                    }
                }
                next
            }
            pieces[[my_name]][[my_index]] <- if (is.null(value)) {
                .append_missing_column(prototype, rows)
            } else {
                value
            }
        }
        rm(data)
    }

    columns <- vector("list", length(plan$names))
    names(columns) <- plan$names
    for (my_index in seq_along(plan$names)) {
        my_name <- plan$names[[my_index]]
        buffer <- buffers[[my_index]]
        if (is.null(buffer)) {
            columns[[my_index]] <- .append_combine_pieces(
                pieces[[my_name]], plan$prototypes[[my_name]], row_counts
            )
            pieces[my_name] <- list(NULL)
            next
        }
        # Release the list's reference before encoding. A held double
        # buffer would be copied whole on the way into compact storage,
        # and every finished buffer would stay resident beside the
        # result until the whole frame was built.
        buffers[my_index] <- list(NULL)
        columns[[my_index]] <- .append_finish_buffer(
            buffer, plan$prototypes[[my_name]]
        )
        rm(buffer)
    }
    list(columns = columns, row_count = total_rows)
}

# A Stata numeric buffer starts as system missing and a Stata string
# buffer as the empty string, so a source that never writes into its
# range already holds that variable's missing value.
.append_allocate_buffer <- function(prototype, total_rows) {
    if (inherits(prototype, "stata_temporal")) return(NULL)
    if (inherits(prototype, "stata_string")) {
        return(structure(character(total_rows), dtatools.buffer = "string"))
    }
    storage <- stata_storage_type(prototype)
    if (is.null(storage)) return(NULL)
    structure(
        rep(NA_real_, total_rows), dtatools.buffer = "numeric",
        dtatools.storage = storage
    )
}

.append_fits_buffer <- function(value, prototype) {
    if (inherits(prototype, "stata_string")) {
        return(is.character(value) && !inherits(value, "stata_temporal"))
    }
    # Any declared Stata numeric may widen into the buffer without a
    # cast: the plan's prototype is the sources' common type on Stata's
    # lossless lattice, so it represents every contributor's values
    # exactly. A bare double carries no such guarantee, so the caller
    # casts it to the prototype before writing.
    !is.null(stata_storage_type(value)) &&
        !inherits(value, "stata_temporal") && is.null(names(value))
}

.append_buffer_values <- function(value) {
    if (is.character(value)) as.character(value) else as.double(value)
}

.append_finish_buffer <- function(buffer, prototype) {
    kind <- attr(buffer, "dtatools.buffer", exact = TRUE)
    storage <- attr(buffer, "dtatools.storage", exact = TRUE)
    attributes(buffer) <- NULL
    if (identical(kind, "string")) return(vctrs::vec_cast(buffer, prototype))
    .restore_stata_variable_metadata(
        .construct_stata_numeric(buffer, NULL, storage), prototype,
        names = NULL
    )
}

# The plan already resolved every storage conflict the schemas could
# show, so the whole-column concatenation normally succeeds. A value
# that only its observations reveal to be out of range - a numeric too
# wide for the promoted storage - falls back to casting piece by piece
# so one bad source becomes missing instead of failing the append.
.append_combine_pieces <- function(the_pieces, prototype, row_counts) {
    combined <- tryCatch(
        vctrs::vec_c(!!!the_pieces, .ptype = prototype),
        error = function(condition) NULL
    )
    if (!is.null(combined)) return(combined)
    for (my_index in seq_along(the_pieces)) {
        cast <- tryCatch(
            vctrs::vec_cast(the_pieces[[my_index]], prototype),
            error = function(condition) NULL
        )
        the_pieces[[my_index]] <- if (is.null(cast)) {
            .append_missing_column(prototype, row_counts[[my_index]])
        } else {
            cast
        }
    }
    vctrs::vec_c(!!!the_pieces, .ptype = prototype)
}

# Stata strings use `""` for missing and compact numerics allocate
# system missing without a values vector, so neither can go through
# vec_init()'s `NA`.
.append_missing_column <- function(prototype, rows) {
    if (rows == 0L) return(prototype)
    if (inherits(prototype, "stata_string")) {
        return(vctrs::vec_cast(rep("", rows), prototype))
    }
    storage <- stata_storage_type(prototype)
    if (!is.null(storage) && storage %in%
        c("byte", "int", "long", "float", "double")) {
        constructor <- switch(
            storage,
            byte = stata_byte, int = stata_int, long = stata_long,
            float = stata_float, double = stata_double
        )
        return(vctrs::vec_cast(constructor(.size = rows), prototype))
    }
    vctrs::vec_init(prototype, rows)
}

.append_apply_dataset_metadata <- function(result, schemas, dataset_notes) {
    first <- schemas[[1L]]$schema
    label <- attr(first, "label", exact = TRUE)
    if (!is.null(label)) attr(result, "label") <- label

    if (identical(dataset_notes, "none")) return(result)
    if (identical(dataset_notes, "first")) {
        return(.copy_stata_metadata_attributes(first, result, mark = FALSE))
    }

    the_notes <- unlist(lapply(schemas, function(my_schema) {
        attr(my_schema$schema, "notes", exact = TRUE)
    }), use.names = FALSE)
    characteristics <- NULL
    for (my_schema in schemas) {
        value <- attr(my_schema$schema, "stata.characteristics", exact = TRUE)
        if (!is.null(value)) characteristics <- c(characteristics, value)
    }
    if (length(the_notes)) {
        attr(result, "notes") <- the_notes
        attr(result, "stata.note.numbers") <- seq_along(the_notes)
    }
    if (length(characteristics)) {
        attr(result, "stata.characteristics") <-
            characteristics[!duplicated(names(characteristics))]
    }
    result
}
