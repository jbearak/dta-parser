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
#' `.arrow` file. File sources are read in two passes: the first reads
#' their schema alone, and the second reads their observations, so
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
        .append_read_schema(the_sources[[my_index]], my_index, output)
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
.append_read_schema <- function(source, index, output = "default") {
    kind <- .append_source_kind(source, index)
    schema <- switch(
        kind,
        frame = vctrs::vec_slice(source, integer()),
        dta = .append_read_dta_schema(source, output),
        arrow = .append_read_arrow_schema(source, output)
    )
    rows <- if (identical(kind, "frame")) {
        nrow(source)
    } else {
        source_rows <- attr(schema, "dtatools.source.rows", exact = TRUE)
        if (!is.numeric(source_rows) || length(source_rows) != 1L ||
            is.na(source_rows) || source_rows < 0 ||
            source_rows > .Machine$integer.max) {
            stop("file source has too many rows for an R data frame",
                 call. = FALSE)
        }
        as.integer(source_rows)
    }
    attr(schema, "dtatools.source.rows") <- NULL
    list(
        kind = kind, source = source, index = index, schema = schema,
        rows = rows
    )
}

.append_read_dta_schema <- function(source, output) {
    .read_dta_impl(
        source, NULL, rlang::quo(NULL), 0, 0, "unique", output,
        materialization = "direct",
        threads = getOption("dtatools.threads", 0L),
        use_numeric_altrep = getOption("dtatools.numeric_altrep", TRUE),
        record_datasig = FALSE, keep_source_rows = TRUE
    )
}

.append_read_arrow_schema <- function(source, output) {
    .read_arrow_impl(
        source, rlang::quo(NULL), 0, 0, TRUE, TRUE, "unique", output,
        getOption("dtatools.numeric_altrep", TRUE),
        getOption("dtatools.threads", 0L), FALSE,
        keep_source_rows = TRUE
    )
}

.append_read_data <- function(entry) {
    switch(
        entry$kind,
        frame = entry$source,
        dta = read_dta(entry$source, output = "tibble"),
        arrow = read_arrow(entry$source, output = "tibble")
    )
}

.append_build_plan <- function(schemas, force) {
    source_count <- length(schemas)
    the_names <- character(0)
    occurrences <- integer(0)
    plan_lookup <- new.env(hash = TRUE, parent = emptyenv())
    source_plans <- vector("list", source_count)
    for (my_index in seq_len(source_count)) {
        source_names <- names(schemas[[my_index]]$schema)
        if (is.null(source_names)) source_names <- rep("", ncol(
            schemas[[my_index]]$schema
        ))
        source_names[is.na(source_names)] <- ""
        source_occurrences <- .append_name_occurrences(source_names)
        source_plans[[my_index]] <- integer(length(source_names))
        for (my_column in seq_along(source_names)) {
            name_key <- paste0("x", enc2utf8(source_names[[my_column]]))
            if (exists(name_key, plan_lookup, inherits = FALSE)) {
                name_lookup <- get(name_key, plan_lookup, inherits = FALSE)
            } else {
                name_lookup <- new.env(hash = TRUE, parent = emptyenv())
                assign(name_key, name_lookup, plan_lookup)
            }
            occurrence_key <- as.character(
                source_occurrences[[my_column]]
            )
            if (exists(occurrence_key, name_lookup, inherits = FALSE)) {
                plan_index <- get(
                    occurrence_key, name_lookup, inherits = FALSE
                )
            } else {
                the_names <- c(the_names, source_names[[my_column]])
                occurrences <- c(
                    occurrences, source_occurrences[[my_column]]
                )
                plan_index <- length(the_names)
                assign(occurrence_key, plan_index, name_lookup)
            }
            source_plans[[my_index]][[my_column]] <- plan_index
        }
    }
    source_columns <- lapply(source_plans, function(plan_indices) {
        columns <- rep(NA_integer_, length(the_names))
        columns[plan_indices] <- seq_along(plan_indices)
        columns
    })

    prototypes <- vector("list", length(the_names))
    metadata_owners <- vector("list", length(the_names))
    # A source is dropped for one variable when its storage cannot
    # meet the accumulated prototype; those rows take missing values.
    dropped <- vector("list", length(the_names))

    for (plan_index in seq_along(the_names)) {
        my_name <- the_names[[plan_index]]
        prototype <- NULL
        conflicting <- integer(0)
        for (my_index in seq_len(source_count)) {
            my_column <- source_columns[[my_index]][[plan_index]]
            if (is.na(my_column)) next
            value <- schemas[[my_index]]$schema[[my_column]]
            candidate <- vctrs::vec_ptype(value)
            if (is.null(prototype)) {
                prototype <- candidate
                metadata_owners[[plan_index]] <- candidate
                next
            }
            merged <- tryCatch(
                .append_common_prototype(prototype, candidate),
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
        prototypes[[plan_index]] <- .append_restore_owned_metadata(
            prototype, metadata_owners[[plan_index]]
        )
        dropped[[plan_index]] <- conflicting
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

    list(
        names = the_names, prototypes = prototypes, dropped = dropped,
        source_columns = source_columns, force = force
    )
}

.append_restore_owned_metadata <- function(prototype, owner) {
    result <- .metadata_copy(prototype)
    owned <- c(
        "label", "value.label.name", "notes", "stata.note.numbers",
        "stata.characteristics"
    )
    for (my_name in owned) {
        attr(result, my_name) <- attr(owner, my_name, exact = TRUE)
    }
    owner_format <- attr(owner, "format.stata", exact = TRUE)
    if (!is.null(owner_format) || !inherits(prototype, "stata_temporal")) {
        attr(result, "format.stata") <- owner_format
    }
    if (is.null(attr(owner, "labels", exact = TRUE))) {
        attr(result, "labels") <- NULL
    }
    result
}

.append_name_occurrences <- function(the_names) {
    counts <- new.env(hash = TRUE, parent = emptyenv())
    vapply(the_names, function(my_name) {
        key <- paste0("x", enc2utf8(my_name))
        occurrence <- if (exists(key, counts, inherits = FALSE)) {
            get(key, counts, inherits = FALSE) + 1L
        } else {
            1L
        }
        assign(key, occurrence, counts)
        occurrence
    }, integer(1))
}

.append_common_prototype <- function(left, right) {
    if (inherits(left, .stata_metadata_vector_class)) {
        left <- .stata_metadata_vector_base(left)
    }
    if (inherits(right, .stata_metadata_vector_class)) {
        right <- .stata_metadata_vector_base(right)
    }
    left_storage <- stata_storage_type(left)
    right_storage <- stata_storage_type(right)
    left_declared <- !is.null(left_storage) &&
        !inherits(left, "stata_temporal")
    right_declared <- !is.null(right_storage) &&
        !inherits(right, "stata_temporal")
    left_bare <- is.numeric(left) && is.null(left_storage) &&
        !inherits(left, "stata_temporal")
    right_bare <- is.numeric(right) && is.null(right_storage) &&
        !inherits(right, "stata_temporal")
    if (left_declared && right_bare) {
        right <- .append_promote_bare_numeric(right)
    }
    if (right_declared && left_bare) {
        left <- .append_promote_bare_numeric(left)
    }
    vctrs::vec_ptype2(left, right)
}

.append_promote_bare_numeric <- function(prototype) {
    widened <- .restore_stata_variable_metadata(
        stata_double(), prototype, names = NULL
    )
    .as_stata_metadata_vector(widened)
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
    total_rows <- sum(as.double(row_counts))
    if (total_rows > .Machine$integer.max) {
        stop(
            "combined sources exceed R's maximum data-frame row count",
            call. = FALSE
        )
    }
    total_rows <- as.integer(total_rows)
    offsets <- as.integer(cumsum(c(0, as.double(row_counts))))

    # A column whose prototype and contributors share one physical
    # layout gets a buffer allocated once at the full row count, and
    # each source writes into its own row range. Anything else keeps
    # its per-source pieces for the general vctrs concatenation.
    buffers <- vector("list", length(plan$names))
    pieces <- vector("list", length(plan$names))
    for (plan_index in seq_along(plan$names)) {
        buffers[plan_index] <- list(.append_allocate_buffer(
            plan$prototypes[[plan_index]], total_rows
        ))
        if (is.null(buffers[[plan_index]])) {
            pieces[plan_index] <- list(vector("list", source_count))
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
        for (plan_index in seq_along(plan$names)) {
            prototype <- plan$prototypes[[plan_index]]
            my_column <- plan$source_columns[[my_index]][[plan_index]]
            value <- if (my_index %in% plan$dropped[[plan_index]] ||
                is.na(my_column)) {
                NULL
            } else {
                data[[my_column]]
            }
            if (!is.null(buffers[[plan_index]])) {
                if (!is.null(value) && rows > 0L) {
                    # A value that does not already share the buffer's
                    # layout is cast to the prototype first. A cast the
                    # prototype cannot represent leaves the range at its
                    # missing initialization, which is what the pieces
                    # path does for the same out-of-range source.
                    writable <- if (.append_fits_buffer(value, prototype)) {
                        value
                    } else {
                        .append_cast_to_buffer(value, prototype)
                    }
                    if (is.null(writable)) {
                        .append_unwritable_source(
                            plan$names[[plan_index]], schemas[[my_index]],
                            plan$force
                        )
                    } else {
                        buffer <- buffers[[plan_index]]
                        # Clear the list slot first. While the list still
                        # references the buffer, `[<-` would duplicate
                        # the whole column on every source instead of
                        # writing the destination range in place.
                        buffers[plan_index] <- list(NULL)
                        buffer[span] <- .append_buffer_values(writable)
                        buffers[[plan_index]] <- buffer
                    }
                }
                next
            }
            pieces[[plan_index]][[my_index]] <- if (is.null(value)) {
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
        buffer <- buffers[[my_index]]
        if (is.null(buffer)) {
            columns[[my_index]] <- .append_combine_pieces(
                pieces[[my_index]], plan$prototypes[[my_index]], row_counts,
                schemas, plan$names[[my_index]], plan$force
            )
            pieces[my_index] <- list(NULL)
            next
        }
        # Release the list's reference before encoding. A held double
        # buffer would be copied whole on the way into compact storage,
        # and every finished buffer would stay resident beside the
        # result until the whole frame was built.
        buffers[my_index] <- list(NULL)
        columns[[my_index]] <- .append_finish_buffer(
            buffer, plan$prototypes[[my_index]]
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
        # `NA_character_` has no Stata string encoding. Sending it through
        # the cast lets the source fail the same way it does on the pieces
        # path, instead of erroring when the finished buffer is encoded.
        return(is.character(value) && !inherits(value, "stata_temporal") &&
            !anyNA(value))
    }
    # Any declared Stata numeric may widen into the buffer without a
    # cast: the plan's prototype is the sources' common type on Stata's
    # lossless lattice, so it represents every contributor's values
    # exactly. A bare double carries no such guarantee, so the caller
    # casts it to the prototype before writing.
    !is.null(stata_storage_type(value)) &&
        !inherits(value, "stata_temporal") && is.null(names(value))
}

.append_cast_to_buffer <- function(value, prototype) {
    if (inherits(value, .stata_metadata_vector_class)) {
        value <- .stata_metadata_vector_base(value)
    }
    writable <- tryCatch(
        vctrs::vec_cast(value, prototype),
        error = function(condition) NULL
    )
    if (is.null(writable) || inherits(prototype, "stata_string")) {
        return(writable)
    }
    storage <- stata_storage_type(prototype)
    if (is.null(storage)) {
        return(writable)
    }
    valid <- tryCatch({
        if (inherits(prototype, "stata_temporal")) {
            .construct_stata_numeric(
                as.double(.base_stata_temporal(writable)), NULL, storage,
                temporal = .stata_temporal_code(prototype)
            )
        } else {
            .construct_stata_numeric(as.double(writable), NULL, storage)
        }
        TRUE
    }, error = function(condition) FALSE)
    if (valid) writable else NULL
}

.append_unwritable_source <- function(my_name, schema, force) {
    if (!force) {
        stop(sprintf(
            paste0(
                "variable `%s` has incompatible storage across sources; ",
                "use `force = TRUE` to fill the conflicting rows with ",
                "missing values"
            ),
            my_name
        ), call. = FALSE)
    }
    message(sprintf(
        paste0(
            "note: `%s` is stored differently in %s; force specified, ",
            "so those observations are missing"
        ),
        my_name, .append_source_label(schema$source, schema$index)
    ))
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
.append_combine_pieces <- function(the_pieces, prototype, row_counts,
                                   schemas, my_name, force) {
    # Stata numerics, including temporals, need observation-level range
    # validation in addition to vctrs' type compatibility check.
    if (!is.null(stata_storage_type(prototype))) {
        for (my_index in seq_along(the_pieces)) {
            cast <- .append_cast_to_buffer(the_pieces[[my_index]], prototype)
            if (is.null(cast)) {
                .append_unwritable_source(
                    my_name, schemas[[my_index]], force
                )
                cast <- .append_missing_column(
                    prototype, row_counts[[my_index]]
                )
            }
            the_pieces[[my_index]] <- cast
        }
        return(vctrs::vec_c(!!!the_pieces, .ptype = prototype))
    }
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
            .append_unwritable_source(
                my_name, schemas[[my_index]], force
            )
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
    if (inherits(prototype, "stata_temporal")) {
        return(vctrs::vec_init(prototype, rows))
    }
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
