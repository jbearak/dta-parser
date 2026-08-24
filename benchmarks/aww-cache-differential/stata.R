aww_resolve_stata <- function(explicit = "") {
    candidates <- c(
        explicit,
        Sys.which("stata-mp"),
        Sys.which("stata"),
        "/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp"
    )
    candidates <- unique(candidates[nzchar(candidates)])
    candidates <- candidates[file.exists(candidates)]
    if (!length(candidates)) return(NA_character_)
    normalizePath(candidates[[1L]], winslash = "/", mustWork = TRUE)
}

.aww_stata_cache <- new.env(parent = emptyenv())

aww_stata_info <- function(options, run_dir, script_dir) {
    stata <- aww_resolve_stata(options$stata)
    if (is.na(stata)) return(list(state = "stata-unavailable", id = "unavailable"))
    info <- file.info(stata, extra_cols = FALSE)
    executable_id <- aww_sha256_raw(paste(stata, info$size, as.numeric(info$mtime), sep = "\037"))
    if (exists(executable_id, envir = .aww_stata_cache, inherits = FALSE)) {
        return(get(executable_id, envir = .aww_stata_cache, inherits = FALSE))
    }
    work_dir <- file.path(run_dir, "stata", paste0("version-", substr(executable_id, 1L, 12L)))
    dir.create(work_dir, recursive = TRUE, showWarnings = FALSE, mode = "0700")
    file.copy(file.path(script_dir, "version-probe.do"),
              file.path(work_dir, "version-probe.do"), overwrite = TRUE)
    unlink(file.path(work_dir, "stata-version.txt"))
    process <- tryCatch(processx::run(
        stata, c("-q", "-b", "do", "version-probe.do"), wd = work_dir,
        timeout = options$timeout * 1000, error_on_status = FALSE,
        echo = FALSE, windows_verbatim_args = TRUE
    ), error = identity)
    version_path <- file.path(work_dir, "stata-version.txt")
    if (inherits(process, "error") || process$status != 0L || !file.exists(version_path)) {
        result <- list(state = "stata-version-error", path = stata,
                       id = paste0(executable_id, ":version-error"))
    } else {
        version_lines <- readLines(version_path, warn = FALSE)
        version <- if (length(version_lines)) trimws(version_lines[[1L]]) else ""
        version_parts <- strsplit(version, "[.]", fixed = FALSE)[[1L]]
        major <- if (length(version_parts)) suppressWarnings(as.integer(version_parts[[1L]])) else NA_integer_
        state <- if (!is.na(major) && major == 18L) "available" else "stata-unsupported-version"
        result <- list(state = state, path = stata, version = version,
                       id = paste(executable_id, version, state, sep = ":"))
    }
    assign(executable_id, result, envir = .aww_stata_cache)
    result
}

aww_hex_decode <- function(value) {
    if (!nzchar(value)) return("")
    if (nchar(value) %% 2L) stop("odd Stata hex string")
    bytes <- substring(value, seq.int(1L, nchar(value), 2L), seq.int(2L, nchar(value), 2L))
    rawToChar(as.raw(strtoi(bytes, 16L)))
}

aww_stata_kind <- function(dispute) {
    if (identical(dispute$kind, "cell")) return("cell")
    attribute <- dispute$attribute
    if (identical(dispute$category, "name")) return(if (is.na(dispute$column)) "names" else "name")
    if (identical(dispute$category, "storage")) return("storage")
    if (identical(dispute$category, "format")) return("format")
    if (identical(dispute$category, "class")) {
        labelled <- any(vapply(c(dispute$dtaparser, dispute$haven), function(value) {
            is.character(value) && "haven_labelled" %in% value
        }, logical(1)))
        return(if (identical(attribute, "class") && labelled) {
            "value_label_name"
        } else "format")
    }
    if (identical(attribute, "label")) return(if (is.na(dispute$column)) "dataset_label" else "variable_label")
    if (startsWith(attribute, "notes:")) return("note_entry")
    if (startsWith(attribute, "labels:")) return("value_label_entry")
    if (identical(attribute, "ncol")) return("nvar")
    if (attribute %in% c("tile-nrow", "source-row-count", "observed-row-count",
                         "declared-row-count", "row-bound-exceeded")) return("nobs")
    "unsupported"
}

aww_stata_job <- function(disputes, metadata, work_dir, adapter) {
    requests <- lapply(seq_len(nrow(disputes)), function(index) {
        row <- disputes[index, , drop = FALSE]
        entry <- if (grepl(":", row$attribute, fixed = TRUE)) {
            suppressWarnings(as.integer(sub("^.*:", "", row$attribute)))
        } else 0L
        list(id = index, kind = aww_stata_kind(row), column = row$column,
             observation = row$row, entry = entry)
    })
    supported <- vapply(requests, function(request) request$kind != "unsupported", logical(1))
    columns <- sort(unique(vapply(requests[supported], function(request) {
        if (is.na(request$column)) NA_integer_ else request$column
    }, integer(1))))
    columns <- columns[!is.na(columns) & columns >= 1L & columns <= metadata$columns]
    if (!length(columns) && metadata$columns > 0L) columns <- 1L
    cell_rows <- vapply(requests, function(request) {
        if (identical(request$kind, "cell")) request$observation else NA_real_
    }, numeric(1))
    cell_rows <- cell_rows[is.finite(cell_rows)]
    first <- if (length(cell_rows)) min(cell_rows) else 1
    last <- if (length(cell_rows)) max(cell_rows) else max(1, first)
    lines <- c(
        "version 18.0", "set more off",
        sprintf("do \"%s\"", adapter),
        "aww_open, input(\"input.dta\") output(\"response.tsv\")"
    )
    if (metadata$columns > 0L) {
        lines <- c(lines, sprintf(
            "aww_load, columns(%s) first(%d) last(%d)",
            paste(columns, collapse = " "), as.integer(first), as.integer(last)
        ))
    } else {
        lines <- c(lines, "quietly use \"input.dta\", clear", "global AWW_FIRST \"1\"")
    }
    for (request in requests) {
        if (identical(request$kind, "unsupported")) next
        if (identical(request$kind, "cell")) {
            lines <- c(lines, sprintf(
                "aww_cell, id(%d) column(%d) observation(%d)",
                request$id, request$column, as.integer(request$observation)
            ))
        } else {
            column <- if (is.na(request$column)) 0L else request$column
            lines <- c(lines, sprintf(
                "aww_meta, id(%d) kind(%s) column(%d) index(%d)",
                request$id, request$kind, column, request$entry
            ))
        }
    }
    c(lines, "aww_close", "exit, clear")
}

aww_canonical_labels <- function(labels) aww_label_entries(labels)

aww_stata_value <- function(response) {
    if (!nrow(response)) return(NULL)
    kind <- response$kind[[1L]]
    if (kind %in% c("name", "names", "storage", "format", "variable_label", "dataset_label")) {
        values <- unname(vapply(response$value, aww_hex_decode, character(1)))
        return(if (length(values) == 1L) values[[1L]] else values)
    }
    if (kind == "note_absent") return(list(present = FALSE))
    if (kind == "note_entry") {
        return(list(present = TRUE, value = aww_hex_decode(response$value[[1L]])))
    }
    if (kind == "value_label_absent") return(list(present = FALSE))
    if (kind == "value_label_code") {
        text <- response[response$kind == "value_label_text", "value", drop = TRUE]
        if (length(text) != 1L) return(NULL)
        return(list(
            present = TRUE,
            value = list(code = response$value[[1L]], text = aww_hex_decode(text[[1L]]))
        ))
    }
    if (kind %in% c("nobs", "nvar")) return(as.double(response$value[[1L]]))
    response$value[[1L]]
}

aww_expected_class <- function(format) {
    if (startsWith(format, "%tC") || startsWith(format, "%tc")) return(c("POSIXct", "POSIXt"))
    if (startsWith(format, "%td") || startsWith(format, "%d")) return("Date")
    NULL
}

aww_matches_stata <- function(private, source, dispute, metadata) {
    kind <- aww_stata_kind(dispute)
    if (identical(kind, "cell")) {
        evidence <- private
        if (is.null(evidence) || is.null(evidence$kind)) return(FALSE)
        if (startsWith(source, ".")) return(identical(evidence$kind, source))
        if (identical(evidence$kind, "string")) return(identical(as.character(evidence$value), aww_hex_decode(source)))
        if (!identical(evidence$kind, "value")) return(FALSE)
        value <- evidence$value
        format <- if (!is.na(dispute$column) && dispute$column <= length(metadata$formats)) metadata$formats[[dispute$column]] else ""
        source_value <- aww_source_value(value, format)
        parsed <- suppressWarnings(as.numeric(source))
        storage <- if (!is.na(dispute$column) && dispute$column <= length(metadata$storage)) metadata$storage[[dispute$column]] else NA_character_
        limit <- if (storage %in% c("float", "double")) 1e-7 else 0
        return(length(source_value) == 1L && is.finite(parsed) &&
               abs(as.numeric(source_value) - parsed) <= limit)
    }
    if (kind %in% c("note_entry", "value_label_entry")) {
        if (!is.list(source) || is.null(source$present)) return(FALSE)
        if (!source$present) return(is.null(private))
        return(identical(private, source$value))
    }
    if (kind %in% c("nobs", "nvar")) {
        expected <- as.double(source)
        if (identical(dispute$attribute, "tile-nrow")) {
            if (!is.finite(dispute$skip) || is.na(dispute$n_max)) return(FALSE)
            expected <- max(0, min(as.double(dispute$n_max), expected - dispute$skip))
        }
        return(length(private) == 1L && !is.na(private) &&
               as.double(private) == expected)
    }
    if (identical(dispute$category, "class")) {
        expected <- if (kind == "value_label_name") {
            if (is.character(source) && length(source) == 1L && nzchar(source)) {
                c("haven_labelled", "vctrs_vctr", "double")
            } else NULL
        } else if (identical(dispute$attribute, "tzone")) {
            class <- aww_expected_class(source)
            if (!is.null(class) && "POSIXct" %in% class) "UTC" else NULL
        } else aww_expected_class(source)
        return(identical(private, expected))
    }
    if (kind == "storage") {
        expected <- if (startsWith(source, "str")) "character" else "double"
        return(identical(private, expected))
    }
    identical(private, source)
}

aww_chunk_indices <- function(indices, maximum) {
    if (!length(indices)) return(list())
    split(indices, ceiling(seq_along(indices) / maximum))
}

aww_stata_batches <- function(disputes, maximum_requests, maximum_rows) {
    cell <- disputes$kind == "cell" & is.finite(disputes$row)
    batches <- aww_chunk_indices(which(!cell), maximum_requests)
    if (any(cell)) {
        cell_indices <- which(cell)
        windows <- floor((disputes$row[cell_indices] - 1) / maximum_rows)
        for (window in unique(windows)) {
            batches <- c(batches, aww_chunk_indices(cell_indices[windows == window], maximum_requests))
        }
    }
    unname(batches)
}

aww_stata_open <- function(item, options, run_dir, script_dir, stata_info = NULL) {
    if (!aww_source_unchanged(item)) return("input-changed")
    if (is.null(stata_info)) stata_info <- aww_stata_info(options, run_dir, script_dir)
    if (!identical(stata_info$state, "available")) return(stata_info$state)
    work_dir <- file.path(run_dir, "stata", paste0(item$id, "-open"))
    dir.create(work_dir, recursive = TRUE, showWarnings = FALSE, mode = "0700")
    marker <- file.path(work_dir, "open-ok.txt")
    unlink(marker)
    input <- file.path(work_dir, "input.dta")
    unlink(input)
    if (!file.symlink(item$path, input)) return("input-alias-error")
    file.copy(file.path(script_dir, "open-probe.do"), file.path(work_dir, "open-probe.do"), overwrite = TRUE)
    process <- tryCatch(processx::run(
        stata_info$path, c("-q", "-b", "do", "open-probe.do"), wd = work_dir,
        timeout = options$timeout * 1000, error_on_status = FALSE,
        echo = FALSE, windows_verbatim_args = TRUE
    ), error = identity)
    if (!aww_source_unchanged(item)) return("input-changed")
    if (inherits(process, "error") || process$status != 0L || !file.exists(marker)) {
        "stata-source-error"
    } else "open"
}

aww_adjudicate_batch <- function(disputes, metadata, item, options, run_dir,
                                 script_dir, stata_info, batch_id) {
    if (!aww_source_unchanged(item)) {
        return(list(state = "input-changed", ownership = rep("unresolved", nrow(disputes))))
    }
    work_dir <- file.path(run_dir, "stata", item$id, sprintf("batch-%05d", batch_id))
    dir.create(work_dir, recursive = TRUE, showWarnings = FALSE, mode = "0700")
    input <- file.path(work_dir, "input.dta")
    unlink(input)
    if (!file.symlink(item$path, input)) {
        return(list(state = "input-alias-error", ownership = rep("unresolved", nrow(disputes))))
    }
    job <- file.path(work_dir, "job.do")
    response_path <- file.path(work_dir, "response.tsv")
    unlink(response_path)
    lines <- aww_stata_job(disputes, metadata, work_dir, file.path(script_dir, "adjudicate.do"))
    writeLines(lines, job, useBytes = TRUE)
    process <- tryCatch(processx::run(
        stata_info$path, c("-q", "-b", "do", "job.do"), wd = work_dir,
        timeout = options$timeout * 1000, error_on_status = FALSE,
        echo = FALSE, windows_verbatim_args = TRUE
    ), error = identity)
    if (!aww_source_unchanged(item)) {
        return(list(state = "input-changed", ownership = rep("unresolved", nrow(disputes))))
    }
    if (inherits(process, "error") || process$status != 0L || !file.exists(response_path)) {
        return(list(state = "stata-error", ownership = rep("unresolved", nrow(disputes))))
    }
    response <- tryCatch(read.delim(
        response_path, sep = "\t", quote = "", comment.char = "",
        colClasses = "character", check.names = FALSE, stringsAsFactors = FALSE
    ), error = identity)
    if (inherits(response, "error") ||
        !identical(names(response), c("id", "status", "kind", "index", "value"))) {
        return(list(state = "stata-protocol-error", ownership = rep("unresolved", nrow(disputes))))
    }
    response$id <- suppressWarnings(as.integer(response$id))
    if (anyNA(response$id) || any(response$id < 1L | response$id > nrow(disputes))) {
        return(list(state = "stata-protocol-error", ownership = rep("unresolved", nrow(disputes))))
    }
    ownership <- rep("unresolved", nrow(disputes))
    for (index in seq_len(nrow(disputes))) {
        dispute <- disputes[index, , drop = FALSE]
        if (aww_stata_kind(dispute) == "unsupported") next
        rows <- response[response$id == index & response$status == "ok", , drop = FALSE]
        source <- aww_stata_value(rows)
        if (is.null(source)) next
        left <- aww_matches_stata(dispute$dtaparser[[1L]], source, dispute, metadata)
        right <- aww_matches_stata(dispute$haven[[1L]], source, dispute, metadata)
        ownership[[index]] <- if (identical(dispute$reader, "dtaparser")) {
            if (left) "representation-only" else "dtaparser-wrong"
        } else if (identical(dispute$reader, "haven")) {
            if (right) "representation-only" else "haven-wrong"
        } else if (left && !right) "haven-wrong" else
            if (!left && right) "dtaparser-wrong" else
            if (left && right) "representation-only" else "both-wrong"
    }
    list(state = "complete", ownership = ownership, response = response)
}

aww_stata_row_count <- function(item, metadata, options, run_dir, script_dir,
                                 stata_info, batch_id) {
    dispute <- aww_dispute(
        "metadata", "dimension", attribute = "source-row-count",
        dtaparser = NA_real_, haven = NA_real_
    )
    result <- aww_adjudicate_batch(
        dispute, metadata, item, options, run_dir, script_dir,
        stata_info, 900000L + batch_id
    )
    if (!identical(result$state, "complete") || is.null(result$response)) {
        return(list(state = result$state, rows = NA_real_))
    }
    rows <- result$response[
        result$response$id == 1L & result$response$status == "ok", , drop = FALSE
    ]
    value <- aww_stata_value(rows)
    list(
        state = if (length(value) == 1L && is.finite(value) && value >= 0) {
            "complete"
        } else "stata-protocol-error",
        rows = if (length(value) == 1L && is.finite(value) && value >= 0) {
            as.double(value)
        } else NA_real_
    )
}

aww_adjudicate <- function(disputes, metadata, item, options, run_dir, script_dir,
                           stata_info = NULL) {
    if (!nrow(disputes)) return(list(state = "not-needed", ownership = character()))
    if (!aww_source_unchanged(item)) {
        return(list(state = "input-changed", ownership = rep("unresolved", nrow(disputes))))
    }
    if (is.null(stata_info)) stata_info <- aww_stata_info(options, run_dir, script_dir)
    if (!identical(stata_info$state, "available")) {
        return(list(state = stata_info$state, ownership = rep("unresolved", nrow(disputes))))
    }
    batches <- aww_stata_batches(disputes, options$stata_requests, options$stata_row_window)
    ownership <- rep("unresolved", nrow(disputes))
    states <- character()
    responses <- vector("list", length(batches))
    for (batch_index in seq_along(batches)) {
        indices <- batches[[batch_index]]
        result <- aww_adjudicate_batch(
            disputes[indices, , drop = FALSE], metadata, item, options, run_dir,
            script_dir, stata_info, batch_index
        )
        ownership[indices] <- result$ownership
        states <- c(states, result$state)
        responses[batch_index] <- list(result$response)
        if (identical(result$state, "input-changed")) break
    }
    if (!aww_source_unchanged(item)) {
        return(list(state = "input-changed", ownership = rep("unresolved", nrow(disputes))))
    }
    state <- if (length(states) && all(states == "complete")) "complete" else
        if ("input-changed" %in% states) "input-changed" else
        if (length(states)) paste0("partial-", states[[which(states != "complete")[[1L]]]]) else "stata-protocol-error"
    list(state = state, ownership = ownership, responses = responses,
         stata_id = stata_info$id, stata_version = stata_info$version)
}
