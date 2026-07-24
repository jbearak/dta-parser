suppressPackageStartupMessages(library(haven))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
    stop("usage: haven.R <snapshot|benchmark> <output.json> [arguments ...]")
}
if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("the R package 'jsonlite' is required")
}

mode <- args[[1]]
output_path <- args[[2]]

canonical_cell <- function(value) {
    if (is.na(value)) {
        tag <- haven::na_tag(value)
        missing <- if (is.na(tag)) "." else paste0(".", tag)
        return(list(missing = missing))
    }
    if (is.character(value)) as.character(value) else as.double(value)
}

snapshot_file <- function(file_path) {
    data <- haven::read_dta(file_path)
    variables <- lapply(names(data), function(name) {
        column <- data[[name]]
        labels <- attr(column, "labels", exact = TRUE)
        label_entries <- if (is.null(labels)) {
            list()
        } else {
            lapply(seq_along(labels), function(index) {
                list(
                    value = canonical_cell(unname(labels[[index]])),
                    label = unname(names(labels)[[index]])
                )
            })
        }
        list(
            name = name,
            label = attr(column, "label", exact = TRUE) %||% "",
            format = attr(column, "format.stata", exact = TRUE) %||% "",
            labels = label_entries
        )
    })
    rows <- lapply(seq_len(nrow(data)), function(row_index) {
        unname(lapply(
            data,
            function(column) canonical_cell(column[[row_index]])
        ))
    })
    list(
        file = basename(file_path),
        dataset_label = attr(data, "label", exact = TRUE) %||% "",
        nrow = nrow(data),
        ncol = ncol(data),
        variables = variables,
        rows = rows
    )
}

`%||%` <- function(left, right) {
    if (is.null(left)) right else left
}

elapsed_samples <- function(read_once, warmup, iterations) {
    for (index in seq_len(warmup)) read_once()
    vapply(seq_len(iterations), function(index) {
        start <- as.numeric(Sys.time())
        read_once()
        (as.numeric(Sys.time()) - start) * 1000
    }, numeric(1))
}

observe_dimensions <- function(data) {
    invisible(nrow(data) + ncol(data))
}

benchmark_file <- function(file_path, warmup, iterations) {
    metadata <- haven::read_dta(file_path, n_max = 0)
    row_count <- nrow(haven::read_dta(file_path, col_select = 1))
    selected <- c(1L, 2L, min(5L, length(names(metadata))))
    selected <- unique(selected)
    file_size <- file.info(file_path)$size
    raw_data <- readBin(file_path, what = "raw", n = file_size)
    file_spec <- readr::datasource(file_path)
    raw_spec <- readr::datasource(raw_data)
    native_file <- function(n_max = -1L) {
        data <- haven:::df_parse_dta_file(
            file_spec, "", character(), n_max, 0L,
            name_repair = "unique"
        )
        observe_dimensions(data)
    }
    native_raw <- function() {
        data <- haven:::df_parse_dta_raw(
            raw_spec, "", character(), -1L, 0L,
            name_repair = "unique"
        )
        observe_dimensions(data)
    }
    raw_file_read <- function() {
        data <- readBin(file_path, what = "raw", n = file_size)
        invisible(length(data))
    }
    synthetic_result_shape <- function() {
        columns <- lapply(metadata, function(template) {
            column <- if (is.character(template)) {
                character(row_count)
            } else {
                numeric(row_count)
            }
            for (attribute in c(
                "label", "format.stata", "class", "labels", "units", "tzone"
            )) {
                value <- attr(template, attribute, exact = TRUE)
                if (!is.null(value)) attr(column, attribute) <- value
            }
            column
        })
        names(columns) <- names(metadata)
        data <- tibble::as_tibble(columns, .name_repair = "minimal")
        label <- attr(metadata, "label", exact = TRUE)
        if (!is.null(label)) attr(data, "label") <- label
        assign(".haven_decomposition_sink", data, envir = .GlobalEnv)
        observe_dimensions(data)
    }
    full_read <- function() {
        data <- haven::read_dta(file_path)
        observe_dimensions(data)
    }
    selected_read <- function() {
        data <- haven::read_dta(
            file_path,
            col_select = tidyselect::all_of(selected)
        )
        observe_dimensions(data)
    }
    full_samples <- elapsed_samples(full_read, warmup, iterations)
    selected_samples <- elapsed_samples(
        selected_read, warmup, iterations
    )
    list(
        file = basename(file_path),
        full = as.list(full_samples),
        selected = as.list(selected_samples),
        selected_indices = as.list(selected - 1L),
        decomposition = list(
            end_to_end_file = as.list(full_samples),
            native_file = as.list(elapsed_samples(
                native_file, warmup, iterations
            )),
            native_preloaded_raw = as.list(elapsed_samples(
                native_raw, warmup, iterations
            )),
            native_metadata_file = as.list(elapsed_samples(
                function() native_file(0L), warmup, iterations
            )),
            raw_file_read = as.list(elapsed_samples(
                raw_file_read, warmup, iterations
            )),
            synthetic_result_shape = as.list(elapsed_samples(
                synthetic_result_shape, warmup, iterations
            ))
        )
    )
}

if (mode == "snapshot") {
    files <- args[-c(1, 2)]
    result <- list(
        haven_version = as.character(utils::packageVersion("haven")),
        r_version = R.version.string,
        datasets = lapply(files, snapshot_file)
    )
} else if (mode == "benchmark") {
    if (length(args) < 5) {
        stop("benchmark mode requires <warmup> <iterations> <files ...>")
    }
    warmup <- as.integer(args[[3]])
    iterations <- as.integer(args[[4]])
    files <- args[-c(1, 2, 3, 4)]
    result <- list(
        haven_version = as.character(utils::packageVersion("haven")),
        r_version = R.version.string,
        datasets = lapply(
            files, benchmark_file,
            warmup = warmup, iterations = iterations
        )
    )
} else {
    stop(paste("unknown mode:", mode))
}

jsonlite::write_json(
    result, output_path,
    auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE
)
